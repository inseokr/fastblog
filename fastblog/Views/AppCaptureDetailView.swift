//
//  AppCaptureDetailView.swift
//  fastblog
//
//  Full-screen paging viewer for in-app camera captures.
//  Supports caption editing and photo deletion.
//

import Photos
import SwiftUI
import UIKit

struct AppCaptureDetailView: View {
    @Binding var items: [AppCaptureItem]
    let initialId: UUID
    var onDelete: (UUID) -> Void
    var onCaptionSaved: (UUID, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var showControls = true
    @State private var isEditingCaption = false
    @State private var captionDraft = ""
    @State private var resolvedPlaceTitle: String = ""
    @State private var showDeleteConfirm = false
    @State private var isGeneratingCaption = false
    @State private var downloadToast: String?
    @State private var pendingCaptionEditorClose = false
    @FocusState private var captionFocused: Bool

    // MARK: - Vibe
    @StateObject private var vibePlayer = VibePlayer()
    /// Global toggle: once enabled, auto-plays Vibe as the user pages through photos.
    @State private var isVibeEnabled: Bool = false

    /// Restrict writing assist in full-screen gallery to iPhone 15+ hardware.
    private var supportsFullScreenWritingAssist: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return true }
        guard let modelIdentifier = Self.currentDeviceModelIdentifier() else { return false }
        guard modelIdentifier.hasPrefix("iPhone") else { return true }

        let remainder = modelIdentifier.dropFirst("iPhone".count)
        guard let majorPart = remainder.split(separator: ",").first,
              let major = Int(majorPart) else { return false }
        return major >= 15
    }

    private static func currentDeviceModelIdentifier() -> String? {
        // Simulator exposes target hardware via env var.
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simModel.isEmpty {
            return simModel
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let id = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return id.isEmpty ? nil : id
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        // Matches `PlacePhotoModalView` style (e.g. "30 Aug 2025 at 1:53 PM").
        f.dateFormat = "d MMM yyyy 'at' h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                emptyView
            } else {
                photoPageView
                if showControls && !isEditingCaption {
                    topBar
                    VStack {
                        Spacer()
                        galleryBottomChrome
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                if let downloadToast {
                    VStack {
                        Spacer()
                        Text(downloadToast)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .padding(.bottom, 32)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditingCaption {
                captionEditor
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let idx = items.firstIndex(where: { $0.id == initialId }) {
                currentIndex = idx
            }
            if items.indices.contains(currentIndex) {
                reconcileCaptionWithBlog(at: currentIndex)
            }
            captionDraft = currentItem?.caption ?? ""
            if let id = currentItem?.id {
                resolvedPlaceTitle = resolvePlaceTitle(for: id)
            } else {
                resolvedPlaceTitle = ""
            }
        }
        .onDisappear {
            vibePlayer.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            guard pendingCaptionEditorClose else { return }
            pendingCaptionEditorClose = false
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                isEditingCaption = false
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentPhoto() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the photo from your device.")
        }
    }

    // MARK: - Current item helper

    private var currentItem: AppCaptureItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    // MARK: - Photo pager

    private var photoPageView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PhotoPageCell(item: item)
                    .tag(index)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentIndex) { _, newIdx in
            if items.indices.contains(newIdx) {
                reconcileCaptionWithBlog(at: newIdx)
                captionDraft = items[newIdx].caption ?? ""
                resolvedPlaceTitle = resolvePlaceTitle(for: items[newIdx].id)
            }
            vibePlayer.stop()
            if isVibeEnabled, let url = items[safe: newIdx]?.localVibeURL {
                vibePlayer.play(url: url)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            ZStack {
                // Left: close button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Right: Vibe toggle when available (download/delete live in bottom bar)
                    if currentItem?.localVibeURL != nil {
                        let audioPlaying = vibePlayer.isPlaying
                        /// Vibe clips do not loop; after `audioPlayerDidFinishPlaying`, `audioPlaying` is false while `isVibeEnabled` may stay true (e.g. auto-play on swipe).
                        let vibeArmedIdle = isVibeEnabled && !audioPlaying
                        Button {
                            isVibeEnabled.toggle()
                            if isVibeEnabled, let url = currentItem?.localVibeURL {
                                vibePlayer.play(url: url)
                            } else {
                                vibePlayer.stop()
                            }
                        } label: {
                            // Match in-app camera: 44pt material circle. Waveform animates only while audio is actually playing.
                            AtmosphericWaveformView(isActive: audioPlaying)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .background(
                                    audioPlaying ? Color.cyan.opacity(0.32)
                                        : isVibeEnabled ? Color.white.opacity(0.06) : Color.clear
                                )
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            audioPlaying
                                                ? LinearGradient(
                                                    colors: [.cyan, .green],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                : LinearGradient(
                                                    colors: isVibeEnabled
                                                        ? [Color.white.opacity(0.28)]
                                                        : [Color.white.opacity(0.15)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                            lineWidth: audioPlaying ? 2 : 1
                                        )
                                )
                                .shadow(color: audioPlaying ? .cyan.opacity(0.55) : .clear, radius: audioPlaying ? 10 : 0)
                                .opacity(vibeArmedIdle ? 0.52 : 1)
                                .grayscale(vibeArmedIdle ? 0.85 : 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            audioPlaying ? "Vibe playing"
                                : isVibeEnabled ? "Vibe idle, tap to turn off"
                                : "Vibe off, tap to play"
                        )
                    }
                }

                // Center: photo index (e.g. 1/2)
                if items.count > 1 {
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Bottom chrome (flush under photo via safeAreaInset): metadata + square actions
    private var galleryBottomChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let item = currentItem {
                let placeTitle = resolvedPlaceTitle.isEmpty ? "Unknown Place" : resolvedPlaceTitle

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)

                    HStack(alignment: .center, spacing: 12) {
                        Text(Self.dateFormatter.string(from: item.timestamp))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 1)

                        Spacer(minLength: 0)

                        if supportsFullScreenWritingAssist,
                           (item.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           let cgImage = (item.image ?? AppCapturePhotoService.shared.loadImage(captureId: item.id))?.cgImage {
                            Button {
                                isGeneratingCaption = true
                                Task {
                                    let text = await StoryCaptionService.shared.generateCaptionForImage(cgImage: cgImage)
                                    await MainActor.run {
                                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let newCaption: String? = trimmed.isEmpty ? nil : trimmed
                                        try? AppCapturePhotoService.shared.updateCaption(captureId: item.id, caption: newCaption)
                                        CreatedRecapBlogStore.shared.syncPhotoCaptionFromAppCapture(captureId: item.id, caption: newCaption)
                                        items[currentIndex].caption = newCaption
                                        onCaptionSaved(item.id, newCaption)
                                        isGeneratingCaption = false
                                    }
                                }
                            } label: {
                                if isGeneratingCaption {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.caption)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.8, green: 0.5, blue: 1.0),
                                                    Color(red: 0.4, green: 0.7, blue: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            }
                            .disabled(isGeneratingCaption)
                        }
                    }
                }

                if let cap = item.caption, !cap.isEmpty {
                    Text(cap)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .onTapGesture {
                            captionDraft = cap
                            withAnimation { isEditingCaption = true }
                            DispatchQueue.main.async { captionFocused = true }
                        }
                } else {
                    Button {
                        captionDraft = ""
                        withAnimation { isEditingCaption = true }
                        DispatchQueue.main.async { captionFocused = true }
                    } label: {
                        Text("Leave a story for this photo...")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                HStack {
                    Button {
                        downloadCurrentPhotoToPhotoLibrary()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                    }
                    .accessibilityLabel("Download Photo")

                    Spacer()

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                    }
                    .accessibilityLabel("Delete Photo")
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Caption editor (anchored above keyboard via safeAreaInset)
    // Styling aligned with PlacePhotoModalView: gradient panel, TextField, AI wand.

    private var captionEditor: some View {
        VStack(spacing: 0) {
            // Toolbar: Cancel / Done
            HStack {
                Button("Cancel") {
                    captionDraft = currentItem?.caption ?? ""
                    requestCaptionEditorClose()
                }
                .foregroundColor(.white.opacity(0.7))

                Spacer()

                Button("Done") { saveCaption() }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)

            Divider().background(Color.white.opacity(0.15))

            VStack(alignment: .leading, spacing: 8) {
                if let item = currentItem {
                    let placeTitle = resolvedPlaceTitle.isEmpty ? "Unknown Place" : resolvedPlaceTitle

                    VStack(alignment: .leading, spacing: 4) {
                        Text(placeTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if !Self.dateFormatter.string(from: item.timestamp).isEmpty {
                            Text(Self.dateFormatter.string(from: item.timestamp))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.bottom, 4)

                    TextField("Leave a story for this photo...", text: $captionDraft, axis: .vertical)
                        .focused($captionFocused)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(2...6)
                        .padding(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    /// Prefer caption from persisted blog details when `meta.json` is missing it (same fix as gallery grid load).
    private func reconcileCaptionWithBlog(at index: Int) {
        guard items.indices.contains(index) else { return }
        let captureId = items[index].id
        guard let blogCaption = CreatedRecapBlogStore.shared.captionForAppCaptureInStoredBlogs(captureId: captureId) else { return }
        let existing = items[index].caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing != blogCaption else { return }
        try? AppCapturePhotoService.shared.updateCaption(captureId: captureId, caption: blogCaption)
        items[index].caption = blogCaption
        onCaptionSaved(captureId, blogCaption)
    }

    private func resolvePlaceTitle(for captureId: UUID) -> String {
        let target = AppCapturePhotoService.identifier(for: captureId)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // `visitedPlaces` contains the per-photo graph and is what the Year/Category filters also use.
        if let match = CreatedRecapBlogStore.shared.visitedPlaces.first(where: { place in
            place.photos.contains(where: { photo in
                photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) == target
            })
        }) {
            return match.displayName
        }

        return "Unknown Place"
    }

    private func downloadCurrentPhotoToPhotoLibrary() {
        guard let item = currentItem else { return }
        let image = item.image ?? AppCapturePhotoService.shared.loadImage(captureId: item.id)
        guard let image else {
            downloadToast = "Couldn’t load photo"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
            return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    downloadToast = "1 photo saved to Photos"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                } else {
                    downloadToast = "Couldn’t save to Photos"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                }
            }
        }
    }

    private func saveCaption() {
        guard let item = currentItem else { return }
        let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCaption: String? = trimmed.isEmpty ? nil : trimmed
        try? AppCapturePhotoService.shared.updateCaption(captureId: item.id, caption: newCaption)
        CreatedRecapBlogStore.shared.syncPhotoCaptionFromAppCapture(captureId: item.id, caption: newCaption)
        items[currentIndex].caption = newCaption
        onCaptionSaved(item.id, newCaption)
        requestCaptionEditorClose()
    }

    private func requestCaptionEditorClose() {
        pendingCaptionEditorClose = true
        captionFocused = false

        // If no software keyboard animation will fire (e.g. hardware keyboard), close immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard pendingCaptionEditorClose else { return }
            pendingCaptionEditorClose = false
            withAnimation(.easeOut(duration: 0.2)) {
                isEditingCaption = false
            }
        }
    }

    private func deleteCurrentPhoto() {
        guard let item = currentItem else { return }
        vibePlayer.stop()
        AppCapturePhotoService.shared.deleteCapture(captureId: item.id)
        CreatedRecapBlogStore.shared.excludeAppCapturesFromBlogs(captureIds: [item.id])
        InAppCameraPhotoStore.shared.removePhotos(ids: [item.id])
        onDelete(item.id)

        // Navigate to adjacent item or dismiss if last
        if items.count == 1 {
            dismiss()
        } else {
            let newIndex = min(currentIndex, items.count - 2)
            items.remove(at: currentIndex)
            currentIndex = newIndex
            captionDraft = items[safe: currentIndex]?.caption ?? ""
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No photos")
                .foregroundColor(.white.opacity(0.5))
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .padding(16)
            }
        }
    }
}

// MARK: - Individual page cell (zoomable image)

private struct PhotoPageCell: View {
    let item: AppCaptureItem

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let image = item.image {
                    imageContent(geo: geo, image: image)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func imageContent(geo: GeometryProxy, image: UIImage) -> some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * magnifyBy)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .updating($magnifyBy) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = max(1, scale * value)
                        if scale <= 1 { offset = .zero }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1 { scale = 1; offset = .zero }
                    else { scale = 2.5 }
                }
            }
        if scale > 1 {
            base.gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
                    .onEnded { _ in }
            )
        } else {
            base
        }
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
