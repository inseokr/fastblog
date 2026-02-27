//
//  ManagePhotosView.swift
//  Capper
//

import SwiftUI

/// Full-screen photo viewer to add/remove photos for a place stop.
/// Big main photo + selected count + horizontal thumbnail strip at bottom.
struct ManagePhotosView: View {
    let placeTitle: String
    @Binding var photos: [RecapPhoto]
    @Environment(\.dismiss) private var dismiss

    @State private var currentPhotoId: UUID?
    /// Cached so the thumbnail strip doesn’t re-render when only selection changes.
    @State private var cachedAiRanks: [UUID: Int] = [:]

    // Zoom state for main photo
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0

    private static let thumbnailSize: CGFloat = 60
    private static let thumbnailSpacing: CGFloat = 12
    private static let stripHeight: CGFloat = 50
    private static let bottomBarPadding: CGFloat = 10
    /// Extra bottom padding so the strip sits above home indicator and isn’t cut off.
    private static let bottomBarBottomPadding: CGFloat = 10

    private var currentPhoto: RecapPhoto? {
        if let id = currentPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    private var includedCount: Int {
        photos.filter(\.isIncluded).count
    }

    /// Top-rated rank (1–3) by quality score for badge (cached to avoid strip re-renders).
    private var aiRanks: [UUID: Int] { cachedAiRanks }

    private func shouldDimThumbnail(photoId: UUID) -> Bool {
        if photoId == currentPhotoId { return false }
        if let photo = photos.first(where: { $0.id == photoId }), photo.isIncluded { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                mainPhotoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(placeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                // Reorder by quality score: best first (so bottom strip shows best at left)
                let sorted = photos.sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
                if sorted.map(\.id) != photos.map(\.id) {
                    photos = sorted
                }
                if currentPhotoId == nil {
                    currentPhotoId = photos.first?.id
                }
                cachedAiRanks = photos.aiRanksByPhotoId()
            }
            .onChange(of: photos.map(\.id)) { _, _ in
                cachedAiRanks = photos.aiRanksByPhotoId()
            }
            .onChange(of: currentPhotoId) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    zoomScale = 1.0
                    baseZoomScale = 1.0
                }
            }
        }
    }

    // MARK: - Main Photo

    private var mainPhotoArea: some View {
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
                            .padding(.bottom, 20)
                            .transaction { $0.animation = nil }
                    }
                }
                .contentShape(Rectangle())
                .tag(photo.id)
                .onTapGesture {
                    if zoomScale > 1.01 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            zoomScale = 1.0
                            baseZoomScale = 1.0
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
                                    zoomScale = 1.0
                                    baseZoomScale = 1.0
                                }
                            } else {
                                baseZoomScale = zoomScale
                            }
                        }
                )
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black)
    }

    private func toggleInclusion() {
        guard let id = currentPhoto?.id,
              let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            photos[idx].isIncluded.toggle()
        }
    }

    // MARK: - Bottom Bar (fixed; does not move when swiping main photo)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("\(includedCount) of \(photos.count) selected")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            thumbnailStrip
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Self.bottomBarPadding)
        .padding(.bottom, Self.bottomBarPadding + Self.bottomBarBottomPadding)
        .background(Color.black)
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ThumbnailStripScrollView(
            photos: photos,
            currentPhotoId: currentPhotoId,
            thumbnailSize: Self.thumbnailSize,
            thumbnailSpacing: Self.thumbnailSpacing,
            stripHeight: Self.stripHeight,
            aiRanks: aiRanks,
            shouldDim: shouldDimThumbnail,
            onSelect: { id in
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentPhotoId = id
                }
            }
        )
    }
}

// MARK: - Thumbnail strip (separate view to avoid full re-render when only selection changes)

private struct ThumbnailStripScrollView: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID?
    let thumbnailSize: CGFloat
    let thumbnailSpacing: CGFloat
    let stripHeight: CGFloat
    let aiRanks: [UUID: Int]
    let shouldDim: (UUID) -> Bool
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: thumbnailSpacing) {
                    ForEach(photos) { photo in
                        ThumbnailCellView(
                            photo: photo,
                            isCurrent: photo.id == currentPhotoId,
                            isIncluded: photo.isIncluded,
                            dim: shouldDim(photo.id),
                            rank: aiRanks[photo.id],
                            size: thumbnailSize,
                            onTap: { onSelect(photo.id) }
                        )
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .frame(height: stripHeight)
            .onAppear {
                if let id = currentPhotoId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: currentPhotoId) { _, newId in
                guard let id = newId else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
            }
            .id("thumbnail-scroll")
        }
    }
}

/// Single thumbnail cell; takes fixed props so only selection/dim changes trigger redraw.
private struct ThumbnailCellView: View {
    let photo: RecapPhoto
    let isCurrent: Bool
    let isIncluded: Bool
    let dim: Bool
    let rank: Int?
    let size: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

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

                if isIncluded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
                if dim {
                    Color.black.opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isCurrent ? Color.white : (isIncluded ? Color.green.opacity(0.9) : Color.clear),
                        lineWidth: isCurrent ? 3 : 2
                    )
            )
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// Standalone wrapper for live development — holds mutable @State so toggle/swipe gestures work
/// in both the preview canvas and simulator.
/// Flip `kDevBypassToManagePhotos` in fastblogApp.swift to launch straight here on app start.
struct ManagePhotosDevWrapper: View {
    @State private var photos: [RecapPhoto] = RecapPhoto.devMockPhotos

    var body: some View {
        ManagePhotosView(placeTitle: "Gyeongbokgung Palace", photos: $photos)
    }
}

private extension RecapPhoto {
    static var devMockPhotos: [RecapPhoto] {
        // Each item uses a different gradient-palette seed via id.hashValue (see MockPhotoView).
        // No localIdentifier → gradient placeholder, works offline and in canvas.
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
