//
//  AppCaptureGalleryView.swift
//  fastblog
//
//  Grid gallery for all in-app camera captures (bloggo-capture: photos).
//  Each capture can be viewed full-screen, captioned, and deleted.
//  Select mode: download (left), "# Photos Selected" (center), trash (right); down arrow to dismiss.
//

import AVKit
import CoreLocation
import Photos
import SwiftUI


/// Repeating timer invokes the latest scroll closure so gallery state stays current (avoids stale SwiftUI view captures).
private final class GalleryAutoScrollInvoker: ObservableObject {
    var scrollAction: (() -> Void)?
    private var timer: Timer?

    func ensureRunning(interval: TimeInterval) {
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scrollAction?()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }
}

// MARK: - Gallery item model

struct AppCaptureItem: Identifiable {
    let id: UUID
    var image: UIImage?
    var timestamp: Date
    var caption: String?
    var location: PhotoCoordinate?
    /// Local file URL of the Vibe audio clip (vibe.m4a), if one was recorded for this capture.
    var localVibeURL: URL?
    /// Local file URL of the explicit voice memo (voice_memo.m4a), if the user attached one.
    var localVoiceMemoURL: URL?
    /// Local file URL of the five-second moment video (moment_video.mov), if recorded after capture.
    var localMomentVideoURL: URL?
    /// True when this capture was recorded in continuous (manual-stop) reel mode.
    var isManualReelCapture: Bool = false
}

// MARK: - Gallery view

struct AppCaptureGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    /// When provided the view works as a photo picker. The callback receives the UUIDs of selected
    /// captures and the sheet is dismissed automatically. Download/trash actions are hidden.
    var onPickerComplete: (([UUID]) -> Void)? = nil
    /// Capture identifiers (bloggo-capture:<uuid>) already present in the destination stop.
    /// These are hidden from the picker grid so the user only sees photos not yet added.
    var excludedIdentifiers: Set<String> = []

    private var isPickerMode: Bool { onPickerComplete != nil }

    @State private var items: [AppCaptureItem] = []
    @State private var selectedItem: AppCaptureItem?
    @State private var isLoading = true
    @State private var isSelectMode = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showRemoveConfirmation = false
    @State private var showCreateTripBlogAlert = false
    @AppStorage("bloggo.inAppCamera.hasSeenDownloadTooltip") private var hasSeenDownloadTooltip = false
    @State private var downloadToast: String?
    @State private var showDownloadTooltip = false

    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var dragStartIndex: Int?
    @State private var dragInitialSelectedIds: Set<UUID> = []
    @State private var dragTargetSelectState: Bool?
    @State private var lastDragGlobalLocation: CGPoint = .zero
    @State private var lastDragItemIndex: Int?
    @State private var galleryViewportFrame: CGRect = .zero
    @StateObject private var autoScrollInvoker = GalleryAutoScrollInvoker()
    @State private var playingMomentVideoURL: URL?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                } else {
                    ScrollViewReader { proxy in
                        scrollGrid(proxy: proxy)
                    }
                    .onChange(of: isSelectMode) { _, new in
                        if !new { autoScrollInvoker.stop() }
                    }
                }

                // Bottom bar in select mode
                if isSelectMode && !items.isEmpty {
                    if isPickerMode {
                        // Picker mode: full-width blue primary button
                        Button {
                            let ids = Array(selectedIds)
                            onPickerComplete?(ids)
                            dismiss()
                        } label: {
                            Text(selectedIds.isEmpty ? "Select Photos to Add" : "Add \(selectedIds.count) Photo\(selectedIds.count == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .background(
                            Color.blue.opacity(selectedIds.isEmpty ? 0.35 : 1),
                            in: RoundedRectangle(appChromeBaseRadius: 12)
                        )
                        .disabled(selectedIds.isEmpty)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Add selected photos to blog")
                    } else {
                        // Normal mode: download (left), count (center), trash (right)
                        HStack {
                            Button {
                                presentDownloadTooltipIfNeeded()
                                saveSelectedToPhotoLibrary()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(selectedIds.isEmpty ? .gray : .white)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                            }
                            .disabled(selectedIds.isEmpty)
                            .accessibilityLabel("Save selected to Photos")

                            Button {
                                showCreateTripBlogAlert = true
                            } label: {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(selectedIds.isEmpty ? .gray : .white)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                            }
                            .disabled(selectedIds.isEmpty)
                            .accessibilityLabel("Create trip blog from selection")

                            Spacer()

                            Text("\(selectedIds.count) Photos Selected")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                showRemoveConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(selectedIds.isEmpty ? .gray : .red)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                            }
                            .disabled(selectedIds.isEmpty)
                            .accessibilityLabel("Remove selected from gallery")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                }

                if let toast = downloadToast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(.bottom, isSelectMode ? 88 : 24)
                }

            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isPickerMode {
                        Button("Cancel") {
                            onPickerComplete?([])
                            dismiss()
                        }
                        .foregroundColor(.white)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                }
                ToolbarItem(placement: .principal) {
                    if isPickerMode {
                        Text("Bloggo Gallery")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !items.isEmpty && !isPickerMode {
                        if isSelectMode {
                            Button("Done") {
                                isSelectMode = false
                                selectedIds = []
                            }
                            .foregroundColor(.white)
                        } else {
                            Button("Select") {
                                isSelectMode = true
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
            }
            .alert("Remove selected photos?", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeSelectedCaptures()
                }
            } message: {
                Text(selectedIds.count == 1 ? "This photo will be removed from Bloggo." : "These photos will be removed from Bloggo.")
            }
            .alert("Create trip blog?", isPresented: $showCreateTripBlogAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Create Blog") {
                    createTripBlogFromSelectedCaptures()
                }
            } message: {
                Text("Selected captures will become a trip blog in My Blogs.")
            }
        }
        .presentationDetents([.fraction(1)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDownloadTooltip) {
            downloadTooltipContent
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .task {
            await loadItems()
            if isPickerMode && !isSelectMode {
                isSelectMode = true
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            AppCaptureDetailView(
                items: $items,
                initialId: item.id,
                onDelete: { deletedId in
                    items.removeAll { $0.id == deletedId }
                    if selectedItem?.id == deletedId {
                        selectedItem = nil
                    }
                },
                onCaptionSaved: { id, caption in
                    if let idx = items.firstIndex(where: { $0.id == id }) {
                        items[idx].caption = caption
                    }
                }
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingMomentVideoURL != nil },
            set: { if !$0 { playingMomentVideoURL = nil } }
        )) {
            if let url = playingMomentVideoURL {
                MomentVideoFullScreenPlayer(url: url) {
                    playingMomentVideoURL = nil
                }
            }
        }
    }

    // MARK: - Subviews

    private func scrollGrid(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // In-content title and count header (when not in select mode)
            if !isSelectMode {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bloggo Gallery")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("\(items.count) photo\(items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    let isSelected = selectedIds.contains(item.id)
                    GalleryCell(
                        item: item,
                        isSelectMode: isSelectMode,
                        isSelected: isSelected,
                        onPlayMomentVideo: { url in
                            playingMomentVideoURL = url
                        }
                    )
                    .id(item.id)
                    .onTapGesture {
                        if isSelectMode {
                            if isSelected {
                                selectedIds.remove(item.id)
                            } else {
                                selectedIds.insert(item.id)
                            }
                        } else {
                            selectedItem = item
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: AppCaptureGalleryCellFramePreferenceKey.self,
                                value: [item.id: geo.frame(in: .global)]
                            )
                        }
                    )
                }
            }
            .padding(.bottom, isSelectMode ? 72 : 88)
        }
        // Keep scrolling available while in select mode; multi-select now happens by taps only.
        .scrollDisabled(false)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { galleryViewportFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, new in
                        galleryViewportFrame = new
                    }
            }
        )
        .onPreferenceChange(AppCaptureGalleryCellFramePreferenceKey.self) { frames in
            cellFrames = frames
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No captures yet")
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
            Text("Photos you take with the in-app camera appear here.")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data loading

    private func loadItems() async {
        isLoading = true
        let service = AppCapturePhotoService.shared
        let ids = service.allCaptureIds()
        var loaded: [AppCaptureItem] = []
        let store = CreatedRecapBlogStore.shared
        for uuid in ids {
            if isPickerMode {
                let identifier = AppCapturePhotoService.identifier(for: uuid)
                if excludedIdentifiers.contains(identifier) { continue }
            }
            let image = service.loadImage(captureId: uuid)
            let info = service.metadata(captureId: uuid)
            let metaCaption = info?.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            let blogCaption = store.captionForAppCaptureInStoredBlogs(captureId: uuid)
            let merged: String?
            if let b = blogCaption, !b.isEmpty {
                merged = b
                if metaCaption != b {
                    try? service.updateCaption(captureId: uuid, caption: b)
                }
            } else if let m = metaCaption, !m.isEmpty {
                merged = m
            } else {
                merged = nil
            }
            loaded.append(AppCaptureItem(
                id: uuid,
                image: image,
                timestamp: info?.timestamp ?? Date(),
                caption: merged,
                location: info?.location,
                localVibeURL: service.vibeFileURL(for: uuid),
                localVoiceMemoURL: service.voiceMemoFileURL(for: uuid),
                localMomentVideoURL: service.momentVideoFileURL(for: uuid),
                isManualReelCapture: info?.isContinuousReel == true
            ))
        }
        items = loaded
        isLoading = false

        Task {
            for item in loaded where item.location != nil {
                let title = CreatedRecapBlogStore.shared.placeTitleForAppCapture(captureId: item.id) ?? ""
                guard PlacePlaceholderNaming.isResolvablePlaceholder(title) else { continue }
                await CreatedRecapBlogStore.shared.resolveAppCapturePlaceIfNeeded(
                    captureId: item.id,
                    fallbackCoordinate: item.location?.clCoordinate
                )
            }
        }
    }

    @ViewBuilder
    private var downloadTooltipContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Save to Photos")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("Selected Bloggo captures can be saved to your device's Photo Library. Reels are saved as video clips.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                showDownloadTooltip = false
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .appChromeCornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }

    private func presentDownloadTooltipIfNeeded() {
        guard !hasSeenDownloadTooltip else { return }
        hasSeenDownloadTooltip = true
        showDownloadTooltip = true
    }

    private func saveSelectedToPhotoLibrary() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }

        Task {
            var auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if auth == .notDetermined {
                auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
            guard auth == .authorized || auth == .limited else {
                await MainActor.run {
                    downloadToast = "Allow Photos access to save"
                    scheduleDownloadToastDismiss()
                }
                return
            }

            AppCapturePhotoService.shared.saveCapturesToPhotoLibrary(captureIds: ids) { count, success in
                if success, count > 0 {
                    let reelCount = ids.filter {
                        AppCapturePhotoService.shared.momentVideoFileURL(for: $0) != nil
                    }.count
                    let photoCount = count - reelCount
                    if reelCount > 0, photoCount == 0 {
                        downloadToast = "\(count) reel\(count == 1 ? "" : "s") saved to Photos"
                    } else if reelCount > 0 {
                        downloadToast = "\(count) item\(count == 1 ? "" : "s") saved to Photos"
                    } else {
                        downloadToast = "\(count) photo\(count == 1 ? "" : "s") saved to Photos"
                    }
                } else {
                    downloadToast = "Couldn't save to Photos"
                }
                scheduleDownloadToastDismiss()
            }
        }
    }

    private func scheduleDownloadToastDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            downloadToast = nil
        }
    }

    private func removeSelectedCaptures() {
        let toRemove = selectedIds
        let service = AppCapturePhotoService.shared
        for id in toRemove {
            service.deleteCapture(captureId: id)
        }
        CreatedRecapBlogStore.shared.excludeAppCapturesFromBlogs(captureIds: toRemove)
        InAppCameraPhotoStore.shared.removePhotos(ids: toRemove)
        items.removeAll { toRemove.contains($0.id) }
        selectedIds = []
        isSelectMode = false
    }

    private func createTripBlogFromSelectedCaptures() {
        let service = AppCapturePhotoService.shared
        let photos: [RecapPhoto] = selectedIds.compactMap { captureId in
            guard let meta = service.metadata(captureId: captureId) else { return nil }
            return RecapPhoto(
                id: captureId,
                timestamp: meta.timestamp,
                location: meta.location,
                imageName: "camera.fill",
                isIncluded: true,
                localIdentifier: AppCapturePhotoService.identifier(for: captureId),
                caption: meta.caption,
                digitizedTime: meta.digitizedTime
            )
        }
        guard !photos.isEmpty else { return }
        _ = createdRecapStore.createTripBlogFromEverydayPhotos(photos)
        selectedIds = []
        isSelectMode = false
        dismiss()
    }

    private func itemIndex(at location: CGPoint) -> Int? {
        for (index, item) in items.enumerated() {
            if let frame = cellFrames[item.id], frame.contains(location) {
                return index
            }
        }
        return nil
    }

    private func beginDragSelection(at index: Int) {
        guard items.indices.contains(index) else { return }
        dragStartIndex = index
        dragInitialSelectedIds = selectedIds
        let startId = items[index].id
        dragTargetSelectState = !dragInitialSelectedIds.contains(startId)
        applyDragSelection(to: index)
    }

    private func applyDragSelection(to currentIndex: Int) {
        guard let start = dragStartIndex,
              items.indices.contains(currentIndex),
              let shouldSelect = dragTargetSelectState else { return }
        let lower = min(start, currentIndex)
        let upper = max(start, currentIndex)
        var nextSelected = dragInitialSelectedIds
        for idx in lower...upper {
            let id = items[idx].id
            if shouldSelect {
                nextSelected.insert(id)
            } else {
                nextSelected.remove(id)
            }
        }
        selectedIds = nextSelected
    }

    private func endDragSelection() {
        dragStartIndex = nil
        dragInitialSelectedIds = []
        dragTargetSelectState = nil
    }

    private static let gridColumnCount = 3
    private static let edgeAutoScrollInset: CGFloat = 72
    private static let autoScrollInterval: TimeInterval = 0.05
    /// While nothing is selected yet, vertical drags are treated as scroll (avoids starting range-select when scrolling).
    private static let scrollDragDominanceRatio: CGFloat = 1.35

    private func shouldTreatDragAsScrollOnly(translation: CGSize) -> Bool {
        selectedIds.isEmpty && abs(translation.height) > abs(translation.width) * Self.scrollDragDominanceRatio
    }

    private func autoScrollEdgeDirection(globalY: CGFloat) -> Int? {
        guard galleryViewportFrame.height > 1 else { return nil }
        let top = galleryViewportFrame.minY + Self.edgeAutoScrollInset
        let bottom = galleryViewportFrame.maxY - Self.edgeAutoScrollInset
        if globalY < top { return -1 }
        if globalY > bottom { return +1 }
        return nil
    }

    private func updateAutoScroll(proxy: ScrollViewProxy, globalY: CGFloat) {
        guard dragStartIndex != nil else {
            autoScrollInvoker.stop()
            return
        }
        guard let direction = autoScrollEdgeDirection(globalY: globalY) else {
            autoScrollInvoker.stop()
            return
        }
        autoScrollInvoker.scrollAction = {
            performScrollStep(proxy: proxy, direction: direction)
        }
        autoScrollInvoker.ensureRunning(interval: Self.autoScrollInterval)
    }

    private func performScrollStep(proxy: ScrollViewProxy, direction: Int) {
        guard !items.isEmpty, dragStartIndex != nil else { return }
        let col = Self.gridColumnCount
        let anchorIdx = lastDragItemIndex ?? itemIndex(at: lastDragGlobalLocation) ?? dragStartIndex ?? 0
        var targetIdx: Int
        if direction < 0 {
            targetIdx = max(0, anchorIdx - col)
        } else {
            targetIdx = min(items.count - 1, anchorIdx + col)
        }
        if targetIdx == anchorIdx {
            if direction < 0 {
                targetIdx = max(0, anchorIdx - 1)
            } else {
                targetIdx = min(items.count - 1, anchorIdx + 1)
            }
        }
        guard targetIdx != anchorIdx else { return }
        proxy.scrollTo(items[targetIdx].id, anchor: .center)
        lastDragItemIndex = targetIdx
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            syncDragSelectionFromFinger()
        }
    }

    private func syncDragSelectionFromFinger() {
        guard dragStartIndex != nil else { return }
        if let idx = itemIndex(at: lastDragGlobalLocation) {
            lastDragItemIndex = idx
            applyDragSelection(to: idx)
        } else if let idx = lastDragItemIndex {
            applyDragSelection(to: idx)
        }
    }
}

private struct AppCaptureGalleryCellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Grid cell

private struct GalleryCell: View {
    let item: AppCaptureItem
    var isSelectMode: Bool = false
    var isSelected: Bool = false
    var onPlayMomentVideo: ((URL) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                        .opacity(isSelectMode && isSelected ? 0.5 : 1)
                } else {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .frame(width: geo.size.width, height: geo.size.width)
                    Image(systemName: "camera.fill")
                        .foregroundColor(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isSelectMode && isSelected ? 0.5 : 1)
                }

                // Caption indicator (bottom-right).
                if !isSelectMode, let cap = item.caption, !cap.isEmpty {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(5)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }

                // Moment video, voice memo, vibe — bottom-leading column.
                if !isSelectMode {
                    VStack(alignment: .leading, spacing: 4) {
                        if let videoURL = item.localMomentVideoURL, let onPlayMomentVideo {
                            Button {
                                onPlayMomentVideo(videoURL)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.orange.opacity(0.88))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play moment video")
                        }
                        if item.localVoiceMemoURL != nil {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.purple.opacity(0.78))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                        }
                        if item.localVibeURL != nil {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
                                )
                                .padding(6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.green.opacity(0.5), lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
                }

                // Select mode checkmark
                if isSelectMode {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(isSelected ? .blue : .white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
