//
//  SplitPlaceStopView.swift
//  Capper
//
//  Lets the user select a split point within a place stop's photo sequence,
//  then creates two separate place stops at that boundary.
//

import SwiftUI

struct SplitPlaceStopView: View {
    let placeTitle: String
    /// All photos for the stop, pre-sorted by timestamp ascending.
    let photos: [RecapPhoto]
    /// Called with the index after which the split should occur (0-based in `photos`).
    var onSplit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Index in `photos` after which the split will be made. Nil = nothing selected yet.
    @State private var splitAfterIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    instructionBanner

                    photoStrip
                        .padding(.top, 16)

                    if let idx = splitAfterIndex {
                        splitPreview(afterIndex: idx)
                            .padding(.top, 16)
                    }

                    Spacer()

                    confirmButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Split Place Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.orange)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Subviews

    private var instructionBanner: some View {
        VStack(spacing: 4) {
            Text(placeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Tap between two photos to set the split point.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 16)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    // Photo thumbnail
                    RecapPhotoThumbnail(photo: photo, cornerRadius: 6, showIcon: false)
                        .frame(width: 90, height: 90)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, 4)

                    // Split-point tap zone (not after the last photo)
                    if index < photos.count - 1 {
                        splitPointButton(afterIndex: index)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func splitPointButton(afterIndex index: Int) -> some View {
        let isSelected = splitAfterIndex == index
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                splitAfterIndex = isSelected ? nil : index
            }
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        } label: {
            ZStack {
                // Tap-target (invisible, generous touch area)
                Color.clear.frame(width: 32, height: 90)

                // Vertical divider line
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Color.orange : Color.white.opacity(0.2))
                    .frame(width: 2, height: 90)

                // Small orange pill badge when selected
                if isSelected {
                    Text("✂")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    @ViewBuilder
    private func splitPreview(afterIndex idx: Int) -> some View {
        let firstCount = idx + 1
        let secondCount = photos.count - firstCount

        HStack(spacing: 12) {
            groupLabel(title: "Group 1", photoCount: firstCount, color: .green)
            Image(systemName: "scissors")
                .font(.footnote)
                .foregroundColor(.orange)
            groupLabel(title: "Group 2", photoCount: secondCount, color: .blue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
    }

    private func groupLabel(title: String, photoCount: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var confirmButton: some View {
        Button {
            guard let idx = splitAfterIndex else { return }
            onSplit(idx)
            dismiss()
        } label: {
            Text(splitAfterIndex == nil ? "Select a split point above" : "Split into 2 Groups")
                .font(.body.weight(.semibold))
                .foregroundColor(splitAfterIndex == nil ? .secondary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(splitAfterIndex == nil ? Color.white.opacity(0.08) : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(splitAfterIndex == nil)
        .animation(.easeInOut(duration: 0.2), value: splitAfterIndex)
    }
}
