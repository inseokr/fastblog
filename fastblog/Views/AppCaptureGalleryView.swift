//
//  AppCaptureGalleryView.swift
//  fastblog
//
//  Grid gallery for all in-app camera captures (bloggo-capture: photos).
//  Each capture can be viewed full-screen, captioned, and deleted.
//  Select mode: download (left), "# Photos Selected" (center), trash (right); down arrow to dismiss.
//

import SwiftUI
import Photos

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
                } else {
                    scrollGrid
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
                    .padding(.bottom, 24)
                }

                if let toast = downloadToast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(.bottom, 100)
                }
            }
            .navigationTitle("Bloggo Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if items.isEmpty {
                        EmptyView()
                    } else if isSelectMode {
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

    private var scrollGrid: some View {
        ScrollView {
            // Count header (when not in select mode)
            if !isSelectMode {
                HStack {
                    Text("\(items.count) photo\(items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    Spacer()
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    let isSelected = selectedIds.contains(item.id)
                    GalleryCell(
                        item: item,
                        isSelectMode: isSelectMode,
                        isSelected: isSelected
                    )
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
                }
            }
            .padding(.bottom, isSelectMode ? 72 : 24)
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
