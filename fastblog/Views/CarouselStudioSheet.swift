// CarouselStudioSheet.swift
// fastblog

import Photos
import SwiftUI

// MARK: - Model

struct CarouselSlide: Identifiable {
    let id: String
    let placeStop: PlaceStop
    let dayTitle: String
    var heroImage: UIImage?
    var isSelected = true

    /// Best available caption: AI narrative → overall story → user note.
    var caption: String? {
        [placeStop.placeNarrative, placeStop.overallStory, placeStop.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

// MARK: - Slide View

struct CarouselSlideView: View {
    let slide: CarouselSlide
    let width: CGFloat
    let aspectRatio: CGFloat
    let onToggleSelection: () -> Void
    let showsSelectionChrome: Bool
    private var height: CGFloat { width / aspectRatio }
    /// Keep framing consistent across Post/Story/Reel exports.
    private let heroImageScale: CGFloat = 1.12

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero photo or gradient fallback
            Group {
                if let image = slide.heroImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(heroImageScale)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 26/255, green: 26/255, blue: 46/255),
                            Color(red: 45/255, green: 53/255, blue: 97/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: width, height: height)
            .clipped()

            // Text scrim — extends higher when caption is present
            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.3), .clear],
                startPoint: .bottom,
                endPoint: slide.caption != nil ? .top : .center
            )

            // Place info
            VStack(alignment: .leading, spacing: 4) {
                Text(slide.placeStop.placeTitle)
                    .font(.system(size: width * 0.065, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let subtitle = slide.placeStop.placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: width * 0.048))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }

                Text(slide.dayTitle)
                    .font(.system(size: width * 0.04))
                    .foregroundColor(.white.opacity(0.6))

                if let caption = slide.caption {
                    Text(caption)
                        .font(.system(size: width * 0.044))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                        .padding(.top, width * 0.02)
                }
            }
            .padding(width * 0.06)
        }
        .overlay(alignment: .topTrailing) {
            if showsSelectionChrome {
                Button(action: onToggleSelection) {
                    Label(slide.isSelected ? "Deselect slide" : "Select slide", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: width * 0.06, weight: .bold))
                        .foregroundColor(.white)
                        .padding(width * 0.04)
                        .background(slide.isSelected ? Color.blue : Color.black.opacity(0.35), in: Circle())
                }
                .padding(width * 0.04)
            }
        }
        .overlay {
            if showsSelectionChrome && !slide.isSelected {
                Color.black.opacity(0.45)
                VStack(spacing: 6) {
                    Text("Not Selected")
                        .font(.system(size: width * 0.05, weight: .semibold))
                }
                .foregroundColor(.white)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(slide.isSelected ? 1.0 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if showsSelectionChrome {
                onToggleSelection()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: slide.isSelected)
    }
}

// MARK: - Studio Sheet

struct SocialPostStudioSheet: View {
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case post
        case story
        case reel

        var id: String { rawValue }

        var title: String {
            switch self {
            case .post: return "Post"
            case .story: return "Story"
            case .reel: return "Reel"
            }
        }

        var icon: String {
            switch self {
            case .post: return "rectangle.portrait"
            case .story: return "sparkles.rectangle.stack"
            case .reel: return "play.rectangle"
            }
        }

        var subtitle: String {
            switch self {
            case .post: return "Classic feed format for photo carousels"
            case .story: return "Full-screen portrait layout for story posts"
            case .reel: return "Vertical cover format for short-form videos"
            }
        }

        var aspectRatio: CGFloat {
            switch self {
            case .post: return 4.0 / 5.0
            case .story, .reel: return 9.0 / 16.0
            }
        }
    }

    let blog: RecapBlogDetail

    @State private var slides: [CarouselSlide] = []
    @State private var exportFormat: ExportFormat = .post
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
    @Environment(\.dismiss) private var dismiss

    private let previewWidth: CGFloat = 260
    private let exportWidth: CGFloat = 1080
    private var exportHeight: CGFloat { exportWidth / exportFormat.aspectRatio }
    private var selectedSlides: [CarouselSlide] { slides.filter { $0.isSelected } }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing slides…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if slides.isEmpty {
                    Text("No places found in this blog.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    slidePreviewAndExport
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Social Post Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
        // Keep Social Post Studio layout stable regardless of system text size.
        .dynamicTypeSize(.medium)
        .task { await loadSlides() }
        .onChange(of: exportFormat) { _, _ in
            Task { await loadSlides() }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ShareSheet(
                items: shareItems,
                excludedActivityTypes: [
                    UIActivity.ActivityType(rawValue: "com.burbn.instagram.shareextension"),
                ]
            )
        }
        .alert("Slides Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedAlertMessage)
        }
    }

    // MARK: - Slide preview + export button

    private var savedAlertMessage: String {
        let selectedCount = selectedSlides.count
        // Keep success messaging generic; "Canva" is mentioned in the CTA copy instead of the success toast.
        return "Saved \(selectedCount) \(exportFormat.title.lowercased()) slides. You can post them now or refine later."
    }

    private var modeSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        modeCard(for: format)
                            .id(format.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: exportFormat) { _, selected in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
            .task {
                proxy.scrollTo(exportFormat.id, anchor: .center)
            }
        }
    }

    private func modeCard(for format: ExportFormat) -> some View {
        let isSelected = exportFormat == format
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                exportFormat = format
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: format.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(format.title)
                        .font(.headline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(format.aspectRatio == (4.0 / 5.0) ? "4:5" : "9:16")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(isSelected ? 0.28 : 0.14))
                        .clipShape(Capsule())
                }

                Text(format.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.86))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(width: 230, alignment: .leading)
            .background(
                LinearGradient(
                    colors: isSelected
                    ? [Color(red: 0.14, green: 0.5, blue: 1.0), Color(red: 0.24, green: 0.71, blue: 1.0)]
                    : [Color(white: 0.2), Color(white: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.35 : 0.12), lineWidth: isSelected ? 1.2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.26 : 0.12), radius: isSelected ? 12 : 6, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .scrollTransition(.animated.threshold(.visible(0.75))) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .opacity(phase.isIdentity ? 1 : 0.86)
        }
    }

    private var slidePreviewAndExport: some View {
        VStack(spacing: 0) {
            modeSelector
                .padding(.top, 14)

            // Slide count
            Text("\(selectedSlides.count) of \(slides.count) slides selected")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(slides.indices, id: \.self) { index in
                        let slide = slides[index]
                        CarouselSlideView(
                            slide: slide,
                            width: previewWidth,
                            aspectRatio: exportFormat.aspectRatio,
                            onToggleSelection: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    slides[index].isSelected.toggle()
                                }
                            },
                            showsSelectionChrome: true
                        )
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            VStack(spacing: 10) {
                // Primary: save to Photos for publish-later flow.
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    exportButtonLabel(
                        icon: "photo.on.rectangle.angled",
                        title: "Save to Photos",
                        subtitle: "Save your \(exportFormat.title.lowercased()) slides, then publish or refine."
                    )
                }
                .disabled(isRendering || selectedSlides.isEmpty)

                // Secondary: share sheet for immediate handoff.
                Button {
                    Task { await shareViaSheet() }
                } label: {
                    exportButtonLabel(
                        icon: "square.and.arrow.up",
                        title: "Share…",
                        subtitle: "Send your \(exportFormat.title.lowercased()) slides to any app (including Canva)."
                    )
                }
                .disabled(isRendering || selectedSlides.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Load

    private func loadSlides() async {
        var result: [CarouselSlide] = []
        for (dayIdx, day) in blog.days.enumerated() {
            let dayTitle = blog.days.count > 1 ? "Day \(dayIdx + 1)" : blog.title
            for stop in day.placeStops {
                let heroPhoto = stop.photos.first { $0.isIncluded }
                var image: UIImage?
                if let localId = heroPhoto?.localIdentifier {
                    image = await loadAssetImage(identifier: localId, size: CGSize(width: exportWidth, height: exportHeight))
                }
                result.append(CarouselSlide(
                    id: stop.id.uuidString,
                    placeStop: stop,
                    dayTitle: dayTitle,
                    heroImage: image
                ))
            }
        }
        slides = result
        isLoading = false
    }

    private func loadAssetImage(identifier: String, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Button label helper

    @ViewBuilder
    private func exportButtonLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            if isRendering {
                ProgressView().tint(.white)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .opacity(0.75)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color(white: 0.18))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Export

    @MainActor
    private func saveToPhotos() async {
        isRendering = true
        defer { isRendering = false }
        let images = renderSlides()
        for image in images {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        showSavedAlert = true
    }

    @MainActor
    private func shareViaSheet() async {
        isRendering = true
        defer { isRendering = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let images = renderSlides()
        var urls: [URL] = []
        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.92) else { continue }
            let fileURL = tempDir.appendingPathComponent("slide_\(index + 1).jpg")
            try? data.write(to: fileURL)
            urls.append(fileURL)
        }
        shareItems = urls
        showShareSheet = true
    }

    @MainActor
    private func renderSlides() -> [UIImage] {
        selectedSlides.compactMap { slide in
            let view = CarouselSlideView(
                slide: slide,
                width: exportWidth,
                aspectRatio: exportFormat.aspectRatio,
                onToggleSelection: {},
                showsSelectionChrome: false
            )
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0
            return renderer.uiImage
        }
    }

    private func cleanupTempFiles() {
        for url in shareItems.compactMap({ $0 as? URL }) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            break  // all files share the same temp dir
        }
        shareItems = []
    }
}
