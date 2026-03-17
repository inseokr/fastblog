//
//  AppCaptureGalleryView.swift
//  fastblog
//
//  Grid gallery for all in-app camera captures (bloggo-capture: photos).
//  Each capture can be viewed full-screen, captioned, and deleted.
//

import SwiftUI

// MARK: - Gallery item model

struct AppCaptureItem: Identifiable {
    let id: UUID
    var image: UIImage?
    var timestamp: Date
    var caption: String?
    var location: PhotoCoordinate?
}

// MARK: - Gallery view

struct AppCaptureGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var items: [AppCaptureItem] = []
    @State private var selectedItem: AppCaptureItem?
    @State private var isLoading = true

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if items.isEmpty {
                    emptyState
                } else {
                    scrollGrid
                }
            }
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
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

    private var scrollGrid: some View {
        ScrollView {
            // Count header
            HStack {
                Text("\(items.count) photo\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    GalleryCell(item: item)
                        .onTapGesture { selectedItem = item }
                }
            }
            .padding(.bottom, 24)
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
            Text("Photos taken with the in-app camera appear here.")
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
        for uuid in ids {
            let image = service.loadImage(captureId: uuid)
            let info = service.metadata(captureId: uuid)
            loaded.append(AppCaptureItem(
                id: uuid,
                image: image,
                timestamp: info?.timestamp ?? Date(),
                caption: info?.caption,
                location: info?.location
            ))
        }
        items = loaded
        isLoading = false
    }
}

// MARK: - Grid cell

private struct GalleryCell: View {
    let item: AppCaptureItem

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .frame(width: geo.size.width, height: geo.size.width)
                    Image(systemName: "camera.fill")
                        .foregroundColor(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Caption indicator dot
                if let cap = item.caption, !cap.isEmpty {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(5)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
