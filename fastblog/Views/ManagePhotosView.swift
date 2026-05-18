//
//  ManagePhotosView.swift
//  Capper
//

import SwiftUI
import UIKit
import Photos

/// iOS Photos-style grid view to include/exclude photos for a place stop.
/// Normal mode: scrollable 3-column grid; tap a photo to view full-screen.
/// Select mode: same scrollable grid; tap a photo to toggle include/exclude (like the iOS camera roll).
struct ManagePhotosView: View {
    let placeTitle: String
    @Binding var photos: [RecapPhoto]
    /// Split control in the bottom-leading corner. Nil hides it.
    var onSplitRequested: (() -> Void)? = nil
    /// Called from the trailing "…" menu when user chooses Add from Library. Nil hides that item.
    var onAddFromLibrary: (() -> Void)? = nil
    /// Called when user wants to add photos from Bloggo Gallery. Nil hides that option.
    var onAddFromBloggoGallery: (() -> Void)? = nil
    /// When Photos access is **limited**, set to `true` so Add can offer the system "select more / deselect" flow via `onExpandSharedPhotoLibrary`.
    var isLimitedPhotoLibraryAccess: Bool = false
    /// Presents `PHPhotoLibrary.presentLimitedLibraryPicker` (same UI as Settings / Trips **Select more photos**). Ignored unless `isLimitedPhotoLibraryAccess` and `onAddFromLibrary` are set.
    var onExpandSharedPhotoLibrary: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSelectMode = false
    @State private var fullScreenPhotoId: UUID? = nil
    @State private var cachedAiRanks: [UUID: Int] = [:]
    @State private var didPrimeGridCache = false
    @State private var existingPhotoLibraryAssetIds: Set<String> = []
    /// Library asset IDs added before `PHAsset.fetchAssets` reflects limited-access picks; keeps the grid showing the new photo immediately.
    @State private var provisionalLibraryAssetIds: Set<String> = []
    @State private var visiblePhotoCount: Int = 0
    @State private var existingAssetIdsRefreshTask: Task<Void, Never>? = nil

    /// Bottom Split / Add chips — wider “balloon” hit targets.
    private let cornerActionChipWidth: CGFloat = 84
    private let cornerActionChipHeight: CGFloat = 64

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// Pixel size for PHCachingImageManager / `ImageLoader` so grid cells hit the same cache keys as other ~⅓-screen thumbnails.
    private var gridThumbnailPixelSize: CGSize {
        let w = (UIScreen.main.bounds.width - 4) / 3
        let s = UIScreen.main.scale
        return CGSize(width: w * s, height: w * s)
    }

    /// Slots that should resolve to pixels.
    /// Source of truth is `localIdentifier` (Photo Library or app-capture). iCloud photos still have a `localIdentifier`;
    /// they are fetched by Photos on demand.
    ///
    /// Important: this must stay *cheap* because it's evaluated often during layout and scrolling. We batch-check asset
    /// existence via `existingPhotoLibraryAssetIds` instead of per-cell `PHAsset.fetchAssets(...)`.
    private var manageGridPhotos: [RecapPhoto] {
        photos
            .filter { photo in
                guard let lid = photo.localIdentifier, !lid.isEmpty else { return false }
                if lid.hasPrefix(AppCapturePhotoService.prefix) {
                    return AppCapturePhotoService.shared.loadImage(identifier: lid) != nil
                }
                return existingPhotoLibraryAssetIds.contains(lid) || provisionalLibraryAssetIds.contains(lid)
            }
            .sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
    }

    private let initialBatchSize = 60
    private let batchSize = 60

    private var gridCacheAssetIdentifiers: [String] {
        manageGridPhotos.compactMap(\.localIdentifier)
    }

    /// Render only a prefix at first, then extend as the user scrolls.
    private var visibleGridPhotos: [RecapPhoto] {
        let initial = min(initialBatchSize, manageGridPhotos.count)
        let effective = min(max(visiblePhotoCount, initial), manageGridPhotos.count)
        return Array(manageGridPhotos.prefix(effective))
    }

    private var visibleGridAssetIdentifiers: [String] {
        visibleGridPhotos.compactMap(\.localIdentifier)
    }

    private func refreshExistingAssetIds() {
        let ids = photos.compactMap(\.localIdentifier).filter { !$0.isEmpty && !$0.hasPrefix(AppCapturePhotoService.prefix) }
        guard !ids.isEmpty else {
            existingPhotoLibraryAssetIds = []
            return
        }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var set = Set<String>()
        set.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in
            set.insert(asset.localIdentifier)
        }
        existingPhotoLibraryAssetIds = set
        var nextProvisional = provisionalLibraryAssetIds
        nextProvisional.subtract(set)
        provisionalLibraryAssetIds = nextProvisional
    }

    /// After adding photos via PHPicker under limited library access, batched `PHAsset.fetch` can lag behind the binding update.
    private func scheduleExistingAssetIdRefreshRetriesIfNeeded() {
        existingAssetIdsRefreshTask?.cancel()
        let libraryIds = Set(photos.compactMap(\.localIdentifier).filter { !$0.isEmpty && !$0.hasPrefix(AppCapturePhotoService.prefix) })
        guard !libraryIds.isEmpty, !libraryIds.isSubset(of: existingPhotoLibraryAssetIds) else { return }
        existingAssetIdsRefreshTask = Task { @MainActor in
            let backoffMs: [UInt64] = [80, 160, 320, 640, 1200]
            for delayMs in backoffMs {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                guard !Task.isCancelled else { return }
                refreshExistingAssetIds()
                if libraryIds.isSubset(of: existingPhotoLibraryAssetIds) { return }
            }
        }
    }

    private func ensureInitialBatch() {
        if visiblePhotoCount == 0 {
            visiblePhotoCount = min(initialBatchSize, manageGridPhotos.count)
        }
    }

    private func maybeLoadMoreIfNeeded(currentPhoto: RecapPhoto) {
        guard let last = visibleGridPhotos.last, last.id == currentPhoto.id else { return }
        guard visiblePhotoCount < manageGridPhotos.count else { return }
        visiblePhotoCount = min(manageGridPhotos.count, visiblePhotoCount + batchSize)
        ImageLoader.shared.startCachingThumbnails(assetIdentifiers: visibleGridAssetIdentifiers, targetSize: gridThumbnailPixelSize)
    }

    private var includedCount: Int { manageGridPhotos.filter(\.isIncluded).count }

    /// Centered inline title; hidden while viewing a full-screen photo so the bar stays minimal.
    private var navigationBarTitle: String {
        fullScreenPhotoId == nil ? "Manage Photos" : ""
    }

    /// Bottom bar: split (when offered) and/or add-from-library/gallery. Split stays visible but disabled with one photo.
    private var managePhotosOverflowMenuVisible: Bool {
        onSplitRequested != nil || onAddFromLibrary != nil || onAddFromBloggoGallery != nil
    }

    private var addPhotoButtonVisible: Bool {
        onAddFromLibrary != nil || onAddFromBloggoGallery != nil
    }

    /// Multiple disambiguated actions (library + gallery): shown as a `Menu` (wider popover than action sheet).
    private var needsAddPhotoChoiceDialog: Bool {
        onAddFromLibrary != nil && onAddFromBloggoGallery != nil
    }

    /// Limited library: single library action is the system limited picker (no PHPicker).
    private var addFromLibraryInvokesLimitedPickerOnly: Bool {
        onAddFromLibrary != nil && onAddFromBloggoGallery == nil && isLimitedPhotoLibraryAccess && onExpandSharedPhotoLibrary != nil
    }

    /// Shared typography for Bloggo Gallery / Camera Roll menu rows (same size and weight).
    private func addPhotoMenuRow(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .frame(minWidth: addPhotoMenuMinRowWidth, alignment: .leading)
    }

    private var addPhotoMenuMinRowWidth: CGFloat {
        let w = UIScreen.main.bounds.width
        return min(360, max(268, w * 0.82))
    }

    @ViewBuilder
    private var addPhotoChipLabel: some View {
        VStack(spacing: 3) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            Text("Add")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(width: cornerActionChipWidth, height: cornerActionChipHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            photoGrid

            if manageGridPhotos.isEmpty, fullScreenPhotoId == nil {
                VStack(spacing: 10) {
                    Text("No photos")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Add photos from your library if you like.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.bottom, managePhotosOverflowMenuVisible ? 100 : 0)
                .allowsHitTesting(false)
            }

            if let photoId = fullScreenPhotoId {
                ManagePhotoDetailView(
                    photos: $photos,
                    gridPhotos: manageGridPhotos,
                    initialPhotoId: photoId,
                    aiRanks: cachedAiRanks,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) { fullScreenPhotoId = nil }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // Bottom-center selection count (select mode only)
            if isSelectMode && fullScreenPhotoId == nil {
                VStack {
                    Spacer()
                    Text("\(includedCount) of \(manageGridPhotos.count) Selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                }
                // Spacer fills the stack; don't steal scroll/taps from the grid underneath.
                .allowsHitTesting(false)
            }

            // Bottom-corner action buttons (hidden in select mode and full-screen photo)
            if !isSelectMode && fullScreenPhotoId == nil && managePhotosOverflowMenuVisible {
                VStack {
                    Spacer()
                    HStack {
                        if let split = onSplitRequested {
                            let canSplit = manageGridPhotos.count > 1
                            Button(action: split) {
                                VStack(spacing: 3) {
                                    Image(systemName: "scissors")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                    Text("Split")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                }
                                .frame(width: cornerActionChipWidth, height: cornerActionChipHeight)
                                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSplit)
                            .accessibilityLabel("Split")
                            .accessibilityHint(
                                canSplit
                                    ? "Splits this place into two at a chosen photo."
                                    : "Unavailable until this place has at least two photos."
                            )
                        }
                        Spacer()
                        if addPhotoButtonVisible {
                            if needsAddPhotoChoiceDialog {
                                Menu {
                                    if let onGallery = onAddFromBloggoGallery {
                                        Button(action: onGallery) {
                                            addPhotoMenuRow("Bloggo Gallery")
                                        }
                                    }
                                    if isLimitedPhotoLibraryAccess, let onExpand = onExpandSharedPhotoLibrary {
                                        Button(action: onExpand) {
                                            addPhotoMenuRow("Camera Roll")
                                        }
                                    } else if let onLibrary = onAddFromLibrary {
                                        Button(action: onLibrary) {
                                            addPhotoMenuRow("Camera Roll")
                                        }
                                    }
                                } label: {
                                    addPhotoChipLabel
                                }
                                .menuIndicator(.hidden)
                                .menuStyle(.automatic)
                                .accessibilityLabel("Add Photos")
                            } else {
                                Button(action: {
                                    if addFromLibraryInvokesLimitedPickerOnly {
                                        onExpandSharedPhotoLibrary?()
                                    } else {
                                        onAddFromLibrary?()
                                        onAddFromBloggoGallery?()
                                    }
                                }) {
                                    addPhotoChipLabel
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add Photos")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle(navigationBarTitle)
        .navigationBarTitleDisplayMode(.inline)
        // iOS 18: system back can ignore `.tint` on pushed destinations; custom chevron matches recap (white).
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if fullScreenPhotoId != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { fullScreenPhotoId = nil }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Close full photo")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.blue)
                    .accessibilityLabel("Save and close")
                }
            } else if isSelectMode {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) { isSelectMode = false }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                }
            } else {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Back")
                }
            }
            if fullScreenPhotoId == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelectMode ? "Save" : "Select") {
                        if isSelectMode {
                            withAnimation(.easeInOut(duration: 0.2)) { isSelectMode = false }
                            dismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { isSelectMode = true }
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(minWidth: isSelectMode ? 56 : 0, alignment: .center)
                    .foregroundColor(isSelectMode ? .blue : .white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(.white)
        .onAppear {
            refreshExistingAssetIds()
            scheduleExistingAssetIdRefreshRetriesIfNeeded()
            cachedAiRanks = photos.aiRanksByPhotoId()
            ensureInitialBatch()
            // Match previous behavior (persist AI sort to the binding) without blocking the first navigation frame.
            DispatchQueue.main.async {
                let sorted = photos.sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
                if sorted.map(\.id) != photos.map(\.id) {
                    photos = sorted
                }
            }
            // Prime Photos caching so the first grid paint is immediate (especially on iCloud assets).
            if !didPrimeGridCache {
                didPrimeGridCache = true
                ImageLoader.shared.startCachingThumbnails(assetIdentifiers: visibleGridAssetIdentifiers, targetSize: gridThumbnailPixelSize)
            }
        }
        .onDisappear {
            existingAssetIdsRefreshTask?.cancel()
            existingAssetIdsRefreshTask = nil
            if didPrimeGridCache {
                ImageLoader.shared.stopCachingThumbnails(assetIdentifiers: gridCacheAssetIdentifiers, targetSize: gridThumbnailPixelSize)
            }
        }
        .onChange(of: photos.map(\.id)) { oldIds, newIds in
            let currentLibraryIds = Set(
                photos.compactMap { p -> String? in
                    guard let lid = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty,
                          !lid.hasPrefix(AppCapturePhotoService.prefix) else { return nil }
                    return lid
                }
            )
            var nextProvisional = provisionalLibraryAssetIds.intersection(currentLibraryIds)
            let oldSet = Set(oldIds)
            for pid in newIds where !oldSet.contains(pid) {
                if let photo = photos.first(where: { $0.id == pid }),
                   let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !lid.isEmpty,
                   !lid.hasPrefix(AppCapturePhotoService.prefix) {
                    nextProvisional.insert(lid)
                }
            }
            provisionalLibraryAssetIds = nextProvisional

            // Defer the PHAsset bulk-fetch to a Task so SwiftUI renders the provisional photo
            // before the synchronous fetchAssets call can block the main thread.
            Task { @MainActor in
                refreshExistingAssetIds()
            }
            scheduleExistingAssetIdRefreshRetriesIfNeeded()
            cachedAiRanks = photos.aiRanksByPhotoId()
            // Reset progressive rendering when the photo set changes.
            visiblePhotoCount = min(max(initialBatchSize, visiblePhotoCount), manageGridPhotos.count)
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(visibleGridPhotos) { photo in
                    ManagePhotoGridCell(
                        photo: photo,
                        thumbnailTargetSize: gridThumbnailPixelSize,
                        isSelectMode: isSelectMode,
                        rank: cachedAiRanks[photo.id],
                        onTap: {
                            if isSelectMode {
                                toggleInclusion(for: photo)
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    fullScreenPhotoId = photo.id
                                }
                            }
                        }
                    )
                    .onAppear { maybeLoadMoreIfNeeded(currentPhoto: photo) }
                }
            }
            .padding(2)
        }
    }

    private func toggleInclusion(for photo: RecapPhoto) {
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { photos[idx].isIncluded.toggle() }
    }
}

// MARK: - Grid Cell

private struct ManagePhotoGridCell: View {
    let photo: RecapPhoto
    var thumbnailTargetSize: CGSize
    let isSelectMode: Bool
    let rank: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    RecapPhotoThumbnail(
                        photo: photo,
                        cornerRadius: 0,
                        showIcon: false,
                        targetSize: thumbnailTargetSize
                    )
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
                .aspectRatio(1, contentMode: .fit)

                // AI rank badge (top-left)
                if let rank = rank {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(rank)")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72))
                    .appChromeCornerRadius(4)
                    .padding(4)
                }

                // Favorite badge (top-right)
                if photo.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // Dim unselected photos in select mode
                if isSelectMode && !photo.isIncluded {
                    Color.black.opacity(0.45)
                        .allowsHitTesting(false)
                }

                // Selection indicator
                if isSelectMode {
                    ZStack {
                        if photo.isIncluded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 3)
                        } else {
                            Circle()
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
                } else if photo.isIncluded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
            // Full tile is tappable (avoids tiny/incorrect hit regions from nested GeometryReader + overlays).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-Screen Detail Viewer

/// Full-screen photo viewer shown when tapping a grid cell in normal mode.
private struct ManagePhotoDetailView: View {
    @Binding var photos: [RecapPhoto]
    /// Matches `manageGridPhotos` so limited-library picks appear before `PHAsset.fetch` catches up (`hasDisplayableLocalBacking` can be false briefly).
    let gridPhotos: [RecapPhoto]
    let initialPhotoId: UUID
    let aiRanks: [UUID: Int]
    let onDismiss: () -> Void

    @State private var currentPhotoId: UUID
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0

    init(
        photos: Binding<[RecapPhoto]>,
        gridPhotos: [RecapPhoto],
        initialPhotoId: UUID,
        aiRanks: [UUID: Int],
        onDismiss: @escaping () -> Void
    ) {
        _photos = photos
        self.gridPhotos = gridPhotos
        self.initialPhotoId = initialPhotoId
        self.aiRanks = aiRanks
        self.onDismiss = onDismiss
        _currentPhotoId = State(initialValue: initialPhotoId)
    }

    /// Same ordering as the grid (`manageGridPhotos`) so swipe order matches thumbnails.
    private var detailPhotos: [RecapPhoto] { gridPhotos }

    private var detailMainPixelSize: CGSize {
        let b = UIScreen.main.bounds
        let d = max(b.width, b.height) * UIScreen.main.scale
        return CGSize(width: d, height: d)
    }

    private var filmstripPixelSize: CGSize {
        let s = UIScreen.main.scale
        return CGSize(width: 120 * s, height: 120 * s)
    }

    private var currentPhoto: RecapPhoto? {
        detailPhotos.first(where: { $0.id == currentPhotoId }) ?? detailPhotos.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                TabView(selection: $currentPhotoId) {
                    ForEach(detailPhotos) { photo in
                        ZStack {
                            RecapPhotoThumbnail(
                                photo: photo,
                                cornerRadius: 0,
                                showIcon: false,
                                targetSize: detailMainPixelSize
                            )
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .scaleEffect(zoomScale)

                            // Subtle in-blog badge — centered pill
                            if photo.isIncluded {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Photo included in blog")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.85))
                                .appChromeCornerRadius(12)
                                .allowsHitTesting(false)
                                .transaction { $0.animation = nil }
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(photo.id)
                        .onTapGesture {
                            if zoomScale > 1.01 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    zoomScale = 1.0; baseZoomScale = 1.0
                                }
                            } else {
                                toggleInclusion()
                            }
                        }
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = max(1.0, baseZoomScale * value)
                                }
                                .onEnded { _ in
                                    if zoomScale < 1.1 {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            zoomScale = 1.0; baseZoomScale = 1.0
                                        }
                                    } else {
                                        baseZoomScale = zoomScale
                                    }
                                }
                        )
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        if let rank = aiRanks[currentPhotoId] {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("AI rank #\(rank)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .appChromeCornerRadius(6)
                        }
                        if currentPhoto?.isFavorite == true {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Favorited")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .appChromeCornerRadius(6)
                        }
                    }
                    Text(currentPhoto?.isIncluded == true ? "Tap to hide from blog" : "Tap to add to blog")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detailPhotos) { photo in
                                let isCurrent = photo.id == currentPhotoId
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPhotoId = photo.id
                                    }
                                } label: {
                                    RecapPhotoThumbnail(
                                        photo: photo,
                                        cornerRadius: 8,
                                        showIcon: false,
                                        targetSize: filmstripPixelSize
                                    )
                                    .frame(width: 56, height: 56)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(appChromeBaseRadius: 8)
                                            .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if photo.isFavorite {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(.red)
                                                .shadow(color: .black.opacity(0.5), radius: 2)
                                                .padding(4)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if photo.isIncluded {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.white)
                                                .shadow(color: .black.opacity(0.4), radius: 2)
                                                .padding(3)
                                        }
                                    }
                                    .opacity(photo.isIncluded ? 1.0 : 0.55)
                                }
                                .buttonStyle(.plain)
                                .id(photo.id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onAppear {
                        proxy.scrollTo(currentPhotoId, anchor: .center)
                    }
                    .onChange(of: currentPhotoId) { _, newId in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(.top, 8)
        }
        .onAppear {
            if let first = detailPhotos.first {
                if detailPhotos.contains(where: { $0.id == currentPhotoId }) == false {
                    currentPhotoId = first.id
                }
            }
        }
        .onChange(of: currentPhotoId) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 1.0; baseZoomScale = 1.0
            }
        }
    }

    private func toggleInclusion() {
        guard let id = currentPhoto?.id,
              let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { photos[idx].isIncluded.toggle() }
    }
}

// MARK: - Debug / Preview

#if DEBUG
/// Standalone wrapper for live development — holds mutable @State so toggle/swipe gestures work
/// in both the preview canvas and simulator.
/// Flip `kDevBypassToManagePhotos` in fastblogApp.swift to launch straight here on app start.
struct ManagePhotosDevWrapper: View {
    @State private var photos: [RecapPhoto] = RecapPhoto.devMockPhotos

    var body: some View {
        NavigationStack {
            ManagePhotosView(placeTitle: "Gyeongbokgung Palace", photos: $photos)
        }
    }
}

private extension RecapPhoto {
    static var devMockPhotos: [RecapPhoto] {
        let score: (Double) -> PhotoScore = { t in
            PhotoScore(aesthetics: t * 0.78, sharpness: t * 0.92, facePenalty: 0, totalScore: t)
        }
        return [
            RecapPhoto(timestamp: Date(), imageName: "mountain.2.fill",   isIncluded: true,  qualityScore: score(0.92)),
            RecapPhoto(timestamp: Date(), imageName: "sun.max.fill",       isIncluded: true,  qualityScore: score(0.85)),
            RecapPhoto(timestamp: Date(), imageName: "camera.fill",        isIncluded: false, qualityScore: score(0.71)),
            RecapPhoto(timestamp: Date(), imageName: "photo.fill",         isIncluded: true,  qualityScore: score(0.68)),
            RecapPhoto(timestamp: Date(), imageName: "building.2.fill",    isIncluded: false, qualityScore: score(0.55)),
            RecapPhoto(timestamp: Date(), imageName: "leaf.fill",          isIncluded: true,  qualityScore: score(0.48)),
            RecapPhoto(timestamp: Date(), imageName: "cloud.fill",         isIncluded: false, qualityScore: score(0.35)),
            RecapPhoto(timestamp: Date(), imageName: "mappin.circle.fill", isIncluded: false, qualityScore: nil),
            RecapPhoto(timestamp: Date(), imageName: "star.fill",          isIncluded: false, qualityScore: nil),
            RecapPhoto(timestamp: Date(), imageName: "star.fill",          isIncluded: false, qualityScore: nil),
        ]
    }
}
#endif

#Preview {
    #if DEBUG
    ManagePhotosDevWrapper()
    #else
    ManagePhotosView(
        placeTitle: "Gyeongbokgung Palace",
        photos: .constant([])
    )
    #endif
}
