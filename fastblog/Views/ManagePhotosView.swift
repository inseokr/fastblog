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

    private static let thumbnailSize: CGFloat = 60
    private static let thumbnailSpacing: CGFloat = 12
    private static let stripHeight: CGFloat = 88
    private static let bottomBarPadding: CGFloat = 16
    /// Extra bottom padding so the strip sits above home indicator and isn’t cut off.
    private static let bottomBarBottomPadding: CGFloat = 28

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
                    .padding(.bottom, 30)
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
        }
    }

    // MARK: - Main Photo

    private var mainPhotoArea: some View {
        ZStack {
            if let photo = currentPhoto {
                ZStack {
                    RecapPhotoThumbnail(
                        photo: photo,
                        cornerRadius: 0,
                        showIcon: false,
                        targetSize: CGSize(width: 800, height: 800)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if photo.isIncluded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 6)
                            .transition(.scale.combined(with: .opacity))
                            .frame(maxHeight: .infinity, alignment: .bottom) // Fills the space and sits at the bottom
                            .padding(.bottom, 20)
                    }
                }
                .id(photo.id)
                .contentShape(Rectangle())
                .onTapGesture { toggleInclusion() }
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let idx = photos.firstIndex(where: { $0.id == currentPhotoId }) ?? 0
                            let dx = value.translation.width
                            if dx < -40, idx + 1 < photos.count {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentPhotoId = photos[idx + 1].id
                                }
                            } else if dx > 40, idx > 0 {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentPhotoId = photos[idx - 1].id
                                }
                            }
                        }
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: currentPhotoId)
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
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

#Preview {
    ManagePhotosView(
        placeTitle: "Gyeongbokgung Palace",
        photos: .constant([
            RecapPhoto(timestamp: Date(), imageName: "photo", isIncluded: true),
            RecapPhoto(timestamp: Date(), imageName: "camera", isIncluded: false),
            RecapPhoto(timestamp: Date(), imageName: "mountain.2", isIncluded: true)
        ])
    )
}
