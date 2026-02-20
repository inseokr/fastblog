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

    private static let thumbnailSize: CGFloat = 56
    private static let thumbnailSpacing: CGFloat = 12
    private static let stripHeight: CGFloat = 72
    private static let bottomBarPadding: CGFloat = 20

    private var currentPhoto: RecapPhoto? {
        if let id = currentPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    private var includedCount: Int {
        photos.filter(\.isIncluded).count
    }

    /// Top-rated rank (1–3) by quality score for badge.
    private var aiRanks: [UUID: Int] { photos.aiRanksByPhotoId() }

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
        .padding(.bottom, Self.bottomBarPadding)
        .background(Color.black)
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.thumbnailSpacing) {
                    ForEach(photos) { photo in
                        managePhotoThumbnail(photo: photo)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .frame(height: Self.stripHeight)
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

    private func managePhotoThumbnail(photo: RecapPhoto) -> some View {
        let isCurrent = photo.id == currentPhotoId
        let isIncluded = photo.isIncluded
        let dim = shouldDimThumbnail(photoId: photo.id)
        let rank = aiRanks[photo.id]

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                currentPhotoId = photo.id
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
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
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
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
