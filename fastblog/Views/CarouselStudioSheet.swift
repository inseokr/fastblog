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
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero photo or gradient fallback
            Group {
                if let image = slide.heroImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
            .frame(width: size, height: size)
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
                    .font(.system(size: size * 0.065, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let subtitle = slide.placeStop.placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: size * 0.048))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }

                Text(slide.dayTitle)
                    .font(.system(size: size * 0.04))
                    .foregroundColor(.white.opacity(0.6))

                if let caption = slide.caption {
                    Text(caption)
                        .font(.system(size: size * 0.044))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                        .padding(.top, size * 0.02)
                }
            }
            .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Studio Sheet

struct CarouselStudioSheet: View {
    let blog: RecapBlogDetail

    @State private var slides: [CarouselSlide] = []
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
    @Environment(\.dismiss) private var dismiss

    private let previewSize: CGFloat = 260
    private let exportSize: CGFloat = 1080

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
            .navigationTitle("Carousel Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { await loadSlides() }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ShareSheet(items: shareItems)
        }
        .alert("Slides Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Instagram → + → Post → select all \(slides.count) slides to create a carousel.")
        }
    }

    // MARK: - Slide preview + export button

    private var slidePreviewAndExport: some View {
        VStack(spacing: 0) {
            // Slide count
            Text("\(slides.count) slides")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(slides) { slide in
                        CarouselSlideView(slide: slide, size: previewSize)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            VStack(spacing: 10) {
                // Primary: save to Photos (for Instagram carousel)
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    exportButtonLabel(
                        icon: "photo.on.rectangle.angled",
                        title: "Save to Photos",
                        subtitle: "Then post as carousel in Instagram"
                    )
                }
                .disabled(isRendering)

                // Secondary: share sheet (TikTok, Twitter, etc.)
                Button {
                    Task { await shareViaSheet() }
                } label: {
                    exportButtonLabel(
                        icon: "square.and.arrow.up",
                        title: "Share…",
                        subtitle: "TikTok, X, Messages and more"
                    )
                }
                .disabled(isRendering)
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
                    image = await loadAssetImage(identifier: localId, size: CGSize(width: 1080, height: 1080))
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
                Text(title).fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.75)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        slides.compactMap { slide in
            let view = CarouselSlideView(slide: slide, size: exportSize)
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
