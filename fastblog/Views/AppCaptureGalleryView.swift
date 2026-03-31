//
//  AppCaptureGalleryView.swift
//  fastblog
//
//  Grid gallery for all in-app camera captures (bloggo-capture: photos).
//  Each capture can be viewed full-screen, captioned, and deleted.
//  Select mode: download (left), "# Photos Selected" (center), trash (right); down arrow to dismiss.
//

import CoreLocation
import SwiftUI
import Photos

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
}

// MARK: - Gallery view

struct AppCaptureGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var items: [AppCaptureItem] = []
    @State private var selectedItem: AppCaptureItem?
    @State private var isLoading = true
    @State private var isSelectMode = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showRemoveConfirmation = false
    @State private var downloadToast: String?
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var dragStartIndex: Int?
    @State private var dragInitialSelectedIds: Set<UUID> = []
    @State private var dragTargetSelectState: Bool?
    @State private var lastDragGlobalLocation: CGPoint = .zero
    @State private var lastDragItemIndex: Int?
    @State private var galleryViewportFrame: CGRect = .zero
    @StateObject private var autoScrollInvoker = GalleryAutoScrollInvoker()

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

                // Bottom bar in select mode: download (left), "# Photos Selected" (center), trash (right)
                if isSelectMode && !items.isEmpty {
                    HStack {
                        Button {
                            saveSelectedToPhotoLibrary()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(selectedIds.isEmpty ? .gray : .white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedIds.isEmpty)
                        .accessibilityLabel("Save selected to Photos")

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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedIds.isEmpty)
                        .accessibilityLabel("Remove selected from gallery")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                VStack(spacing: 12) {
                    if let toast = downloadToast {
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.black.opacity(0.7)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                ToolbarItem(placement: .confirmationAction) {
                    if !items.isEmpty {
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
                Text("\(selectedIds.count) photo\(selectedIds.count == 1 ? "" : "s") will be deleted from this gallery. They will not be removed from your device photo library or any blog.")
            }
        }
        .presentationDetents([.fraction(1)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await loadItems() }
        .fullScreenCover(item: $selectedItem) { item in
            AppCaptureDetailView(
                items: $items,
                initialId: item.id,
                onDelete: { deletedId in
                    items.removeAll { $0.id == deletedId }
                },
                onCaptionSaved: { id, caption in
                    if let idx = items.firstIndex(where: { $0.id == id }) {
                        items[idx].caption = caption
                    }
                }
            )
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
                        isSelected: isSelected
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
        .scrollDisabled(isSelectMode && !selectedIds.isEmpty)
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard isSelectMode else { return }
                    lastDragGlobalLocation = value.location
                    if dragStartIndex == nil {
                        let dragDistance = hypot(value.translation.width, value.translation.height)
                        guard dragDistance > 8 else { return }
                        if shouldTreatDragAsScrollOnly(translation: value.translation) {
                            return
                        }
                        guard let startIndex = itemIndex(at: value.startLocation) else { return }
                        beginDragSelection(at: startIndex)
                        lastDragItemIndex = startIndex
                    }
                    if let currentIndex = itemIndex(at: value.location) {
                        lastDragItemIndex = currentIndex
                        applyDragSelection(to: currentIndex)
                    } else if let idx = lastDragItemIndex {
                        applyDragSelection(to: idx)
                    }
                    updateAutoScroll(proxy: proxy, globalY: value.location.y)
                }
                .onEnded { _ in
                    autoScrollInvoker.stop()
                    endDragSelection()
                    lastDragItemIndex = nil
                }
        )
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
                localVibeURL: service.vibeFileURL(for: uuid)
            ))
        }
        items = loaded
        isLoading = false
    }

    private func saveSelectedToPhotoLibrary() {
        let toSave = items.filter { selectedIds.contains($0.id) }
        let images = toSave.compactMap { $0.image }
        guard !images.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    downloadToast = "\(images.count) photo\(images.count == 1 ? "" : "s") saved to Photos"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                }
            }
        }
    }

    private func removeSelectedCaptures() {
        let service = AppCapturePhotoService.shared
        for id in selectedIds {
            service.deleteCapture(captureId: id)
        }
        items.removeAll { selectedIds.contains($0.id) }
        selectedIds = []
        isSelectMode = false
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

                // Caption indicator (bottom-left, after vibe badge)
                if !isSelectMode, let cap = item.caption, !cap.isEmpty {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(5)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(5)
                }

                // Vibe badge — static green waveform in a circle, bottom-left
                if !isSelectMode, item.localVibeURL != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
                        )
                        .padding(6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.green.opacity(0.5), lineWidth: 1))
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
