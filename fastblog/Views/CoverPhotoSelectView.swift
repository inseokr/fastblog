//
//  CoverPhotoSelectView.swift
//  Capper
//

import SwiftUI

struct CoverPhotoSelectView: View {
    let trip: TripDraft
    let coverTheme: String
    @Binding var coverAssetIdentifier: String?
    var onDone: () -> Void
    /// When set, used instead of "Done" for the primary button (e.g. "Update" in edit flow).
    var primaryButtonTitle: String? = nil

    @State private var showCoverPicker = false

    /// Selected photos from the trip (in order), for the cover picker.
    private var candidatePhotos: [MockPhoto] {
        trip.days.flatMap(\.photos).filter(\.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Cover Photo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            TripCoverImage(theme: coverTheme, coverAssetIdentifier: coverAssetIdentifier)
                .aspectRatio(16/10, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                showCoverPicker = true
            } label: {
                Text("Change")
                    .font(.body)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .disabled(candidatePhotos.isEmpty)

            Spacer()

            Button(action: onDone) {
                Text(primaryButtonTitle ?? "Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showCoverPicker) {
            CoverPhotoPickerView(
                candidatePhotos: candidatePhotos,
                selectedCoverAssetIdentifier: $coverAssetIdentifier,
                onSave: { showCoverPicker = false }
            )
        }
        .preferredColorScheme(.dark)
    }
}

/// Full-screen picker: 1x1 cover preview ~50% at top, then horizontally scrollable 3x3-style grid; tap to set preview, Save to confirm.
struct CoverPhotoPickerView: View {
    let candidatePhotos: [MockPhoto]
    @Binding var selectedCoverAssetIdentifier: String?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Local selection (updates 1x1 when tapping grid); committed on Save.
    @State private var pendingSelection: String?

    private var displayIdentifier: String? {
        pendingSelection ?? selectedCoverAssetIdentifier ?? candidatePhotos.compactMap(\.localIdentifier).first
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let topHeight = geo.size.height * 0.56
                VStack(spacing: 0) {
                    // Cover preview — updates when user taps a photo in the grid
                    Group {
                        if let id = displayIdentifier {
                            AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 800, height: 800))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.2))
                                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.secondary))
                        }
                    }
                    .id(displayIdentifier ?? "")
                    .frame(maxWidth: .infinity)
                    .frame(height: topHeight)
                    .clipped()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Text("Tap a photo to set as cover")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 12)

                // Horizontally scrollable 2-row grid of thumbnails (3 columns per row, scroll for more)
                ScrollView(.horizontal, showsIndicators: false) {
                    gridContent
                }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Change Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        selectedCoverAssetIdentifier = pendingSelection ?? selectedCoverAssetIdentifier
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if pendingSelection == nil {
                    pendingSelection = selectedCoverAssetIdentifier
                }
            }
        }
    }

    private var gridContent: some View {
        let itemSize: CGFloat = 100
        let spacing: CGFloat = 10
        let rowCount = 2
        let colCount = (candidatePhotos.count + rowCount - 1) / rowCount

        return HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<colCount, id: \.self) { col in
                VStack(spacing: spacing) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        let idx = col * rowCount + row
                        if idx < candidatePhotos.count {
                            let photo = candidatePhotos[idx]
                            let id = photo.localIdentifier
                            let isSelected = (id == displayIdentifier)
                            Button {
                                if let id = id {
                                    pendingSelection = id
                                }
                            } label: {
                                MockPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                                    .frame(width: itemSize, height: itemSize)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: itemSize, height: itemSize)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// Cover photo picker for the Recap Blog save flow. Uses RecapPhoto instead of MockPhoto.
/// Big preview at top, horizontal 2-row grid at bottom, Save commits selection.
struct BlogCoverPhotoPickerView: View {
    let photos: [RecapPhoto]
    @Binding var selectedIdentifier: String?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingSelection: String?

    private var displayIdentifier: String? {
        pendingSelection ?? selectedIdentifier ?? photos.compactMap(\.localIdentifier).first
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let topHeight = geo.size.height * 0.56
                VStack(spacing: 0) {
                    Group {
                        if let id = displayIdentifier {
                            AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 800, height: 800))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.2))
                                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.secondary))
                        }
                    }
                    .id(displayIdentifier ?? "")
                    .frame(maxWidth: .infinity)
                    .frame(height: topHeight)
                    .clipped()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Text("Select a cover photo for your blog")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        blogCoverGridContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Cover Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        selectedIdentifier = pendingSelection ?? selectedIdentifier
                        onSave()
                    }
                    .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if pendingSelection == nil {
                    pendingSelection = selectedIdentifier ?? photos.compactMap(\.localIdentifier).first
                }
            }
        }
    }

    private var blogCoverGridContent: some View {
        let itemSize: CGFloat = 100
        let spacing: CGFloat = 10
        let rowCount = 2
        let colCount = (photos.count + rowCount - 1) / rowCount

        return HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<colCount, id: \.self) { col in
                VStack(spacing: spacing) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        let idx = col * rowCount + row
                        if idx < photos.count {
                            let photo = photos[idx]
                            let id = photo.localIdentifier
                            let isSelected = (id == displayIdentifier)
                            Button {
                                if let id = id {
                                    pendingSelection = id
                                }
                            } label: {
                                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                                    .frame(width: itemSize, height: itemSize)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: itemSize, height: itemSize)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    CoverPhotoSelectView(
        trip: TripDraft(title: "Test", dateRangeText: "Jan 1", days: [], coverImageName: "photo", isScannedFromDefaultRange: true),
        coverTheme: "iceland",
        coverAssetIdentifier: .constant(nil),
        onDone: {}
    )
}
