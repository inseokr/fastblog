//
//  ManagePhotosView.swift
//  Capper
//

import SwiftUI

/// iOS Photos-style grid view to include/exclude photos for a place stop.
/// Normal mode: scrollable 3-column grid; tap a photo to view full-screen.
/// Select mode: drag up/down across the grid to range-select; scroll locks during drag.
struct ManagePhotosView: View {
    let placeTitle: String
    @Binding var photos: [RecapPhoto]
    /// Called from the trailing "…" menu when user chooses Split. Nil hides that item.
    var onSplitRequested: (() -> Void)? = nil
    /// Called from the trailing "…" menu when user chooses Add from Library. Nil hides that item.
    var onAddFromLibrary: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSelectMode = false
    @State private var fullScreenPhotoId: UUID? = nil
    @State private var cachedAiRanks: [UUID: Int] = [:]

    // Drag-selection state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var dragStartIndex: Int?
    @State private var dragTargetIsIncluded: Bool?
    @State private var dragInitialInclusionById: [UUID: Bool] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var includedCount: Int { photos.filter(\.isIncluded).count }

    /// Inline nav bar: long `placeTitle` steals horizontal space from trailing Select + More. Keep title empty in browse mode; select mode uses the count string.
    private var navigationBarTitle: String {
        if isSelectMode { return "\(includedCount) of \(photos.count) selected" }
        return ""
    }

    /// Split and add-from-library live in the trailing "…" menu; hide it when neither action exists.
    private var managePhotosOverflowMenuVisible: Bool {
        let canSplit = onSplitRequested != nil && photos.count > 1
        let canAddFromLibrary = onAddFromLibrary != nil
        return canSplit || canAddFromLibrary
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            photoGrid

            if let photoId = fullScreenPhotoId {
                ManagePhotoDetailView(
                    photos: $photos,
                    initialPhotoId: photoId,
                    aiRanks: cachedAiRanks,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) { fullScreenPhotoId = nil }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .navigationTitle(navigationBarTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(fullScreenPhotoId != nil)
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
            }
            if fullScreenPhotoId == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelectMode ? "Done" : "Select") {
                        if isSelectMode {
                            withAnimation(.easeInOut(duration: 0.2)) { isSelectMode = false }
                            dismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { isSelectMode = true }
                        }
                    }
                    .frame(minWidth: isSelectMode ? 56 : 0, alignment: .center)
                    .foregroundColor(.white)
                }

                if !isSelectMode, managePhotosOverflowMenuVisible {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            if let split = onSplitRequested, photos.count > 1 {
                                Button(action: split) {
                                    Label("Split", systemImage: "scissors")
                                }
                            }
                            if onAddFromLibrary != nil {
                                Button(action: { onAddFromLibrary?() }) {
                                    Label("Add Photos", systemImage: "photo.badge.plus")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .accessibilityLabel("More")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            let sorted = photos.sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
            if sorted.map(\.id) != photos.map(\.id) { photos = sorted }
            cachedAiRanks = photos.aiRanksByPhotoId()
        }
        .onChange(of: photos.map(\.id)) { _, _ in
            cachedAiRanks = photos.aiRanksByPhotoId()
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos) { photo in
                    ManagePhotoGridCell(
                        photo: photo,
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
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ManagePhotoGridCellFrameKey.self,
                                value: [photo.id: geo.frame(in: .named("managePhotoGrid"))]
                            )
                        }
                    )
                }
            }
            .padding(2)
        }
        .coordinateSpace(name: "managePhotoGrid")
        .onPreferenceChange(ManagePhotoGridCellFrameKey.self) { cellFrames = $0 }
        // Scroll off in select mode so vertical drag is unambiguously for range-select.
        .scrollDisabled(isSelectMode)
        // Use .gesture (not simultaneous) so it doesn't compete with ScrollView's pan.
        // In normal mode the guard returns early, so scroll works freely.
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("managePhotoGrid"))
                .onChanged { value in
                    guard isSelectMode else { return }
                    if dragStartIndex == nil {
                        guard let startIdx = photoIndex(at: value.startLocation) else { return }
                        beginRangeSelection(at: startIdx)
                    }
                    if let currentIdx = photoIndex(at: value.location) {
                        applyRangeSelection(currentIndex: currentIdx)
                    }
                }
                .onEnded { _ in endRangeSelection() }
        )
    }

    // MARK: - Drag selection helpers

    private func photoIndex(at location: CGPoint) -> Int? {
        for (idx, photo) in photos.enumerated() {
            if let frame = cellFrames[photo.id], frame.contains(location) { return idx }
        }
        return nil
    }

    private func beginRangeSelection(at index: Int) {
        guard photos.indices.contains(index) else { return }
        dragStartIndex = index
        dragInitialInclusionById = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.isIncluded) })
        dragTargetIsIncluded = !photos[index].isIncluded
        applyRangeSelection(currentIndex: index)
    }

    private func applyRangeSelection(currentIndex: Int) {
        guard let start = dragStartIndex,
              let target = dragTargetIsIncluded,
              photos.indices.contains(currentIndex) else { return }
        let lower = min(start, currentIndex)
        let upper = max(start, currentIndex)
        for idx in photos.indices {
            let id = photos[idx].id
            let initial = dragInitialInclusionById[id] ?? photos[idx].isIncluded
            photos[idx].isIncluded = (lower...upper).contains(idx) ? target : initial
        }
    }

    private func endRangeSelection() {
        dragStartIndex = nil
        dragTargetIsIncluded = nil
        dragInitialInclusionById = [:]
    }

    private func toggleInclusion(for photo: RecapPhoto) {
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { photos[idx].isIncluded.toggle() }
    }
}

// MARK: - Grid Cell

private struct ManagePhotoGridCellFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ManagePhotoGridCell: View {
    let photo: RecapPhoto
    let isSelectMode: Bool
    let rank: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    RecapPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false)
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
                .aspectRatio(1, contentMode: .fit)

                // AI rank badge
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
                    .cornerRadius(4)
                    .padding(4)
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-Screen Detail Viewer

/// Full-screen photo viewer shown when tapping a grid cell in normal mode.
private struct ManagePhotoDetailView: View {
    @Binding var photos: [RecapPhoto]
    let initialPhotoId: UUID
    let aiRanks: [UUID: Int]
    let onDismiss: () -> Void

    @State private var currentPhotoId: UUID?
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0

    private var currentPhoto: RecapPhoto? {
        if let id = currentPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                TabView(selection: $currentPhotoId) {
                    ForEach(photos) { photo in
                        ZStack {
                            RecapPhotoThumbnail(
                                photo: photo,
                                cornerRadius: 0,
                                showIcon: false,
                                targetSize: CGSize(width: 800, height: 800)
                            )
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(zoomScale)

                            if photo.isIncluded {
                                Color.black.opacity(0.4)
                                    .allowsHitTesting(false)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 72))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 6)
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
                    if let rank = aiRanks[currentPhotoId ?? UUID()] {
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
                        .cornerRadius(6)
                    }
                    Text("Tap to \(currentPhoto?.isIncluded == true ? "remove" : "include")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
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
                                        targetSize: CGSize(width: 120, height: 120)
                                    )
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .opacity(photo.isIncluded ? 1.0 : 0.55)
                                }
                                .buttonStyle(.plain)
                                .id(photo.id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onAppear {
                        if let id = currentPhotoId {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onChange(of: currentPhotoId) { _, newId in
                        guard let id = newId else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(.top, 8)
        }
        .onAppear {
            currentPhotoId = initialPhotoId
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
