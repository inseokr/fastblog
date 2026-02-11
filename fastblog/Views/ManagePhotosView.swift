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

    private var currentPhoto: RecapPhoto? {
        if let id = currentPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    private var includedCount: Int {
        photos.filter(\.isIncluded).count
    }

    private func shouldDimThumbnail(photoId: UUID) -> Bool {
        if photoId == currentPhotoId { return false }
        if let photo = photos.first(where: { $0.id == photoId }), photo.isIncluded { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    mainPhotoArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 12) {
                        Text("\(includedCount) of \(photos.count) selected")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        thumbnailStrip
                    }
                    .padding(.vertical, 12)
                    .background(Color.black)
                }
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

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos) { photo in
                        managePhotoThumbnail(photo: photo)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 72)
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
        let dim = shouldDimThumbnail(photoId: photo.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                currentPhotoId = photo.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                    .frame(width: 56, height: 56)
                if photo.isIncluded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(4)
                }
                if dim {
                    Color.black.opacity(0.2)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 3)
            )
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
