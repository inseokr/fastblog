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
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            instructionBanner

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose where to split")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                photoStrip
                    .frame(maxHeight: .infinity, alignment: .top)

                if let idx = splitAfterIndex {
                    splitPreview(afterIndex: idx)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Spacer()

            confirmButton
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.92)
        }
    }

    // MARK: - Subviews

    private var instructionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "scissors")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Split Photo Group")
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            Text("Tap between two photos to set the split point.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)

            Text(placeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoStrip: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    RecapPhotoThumbnail(photo: photo, cornerRadius: 6, showIcon: false)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )

                    if index < photos.count - 1 {
                        splitPointButton(afterIndex: index)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func splitPointButton(afterIndex index: Int) -> some View {
        let isSelected = splitAfterIndex == index
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                splitAfterIndex = index
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Rectangle()
                    .fill(isSelected ? Color.orange.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 2)

                Rectangle()
                    .fill(isSelected ? Color.orange : Color.secondary.opacity(0.5))
                    .frame(height: isSelected ? 3 : 2)
                    .padding(.horizontal, 16)

                Image(systemName: "scissors")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(5)
                    .background(Circle().fill(Color.secondary.opacity(0.9)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    @ViewBuilder
    private func splitPreview(afterIndex idx: Int) -> some View {
        let firstCount = idx + 1
        let secondCount = photos.count - firstCount

        HStack(spacing: 16) {
            groupLabel(title: "Group 1", photoCount: firstCount, color: .orange)
            Image(systemName: "scissors")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            groupLabel(title: "Group 2", photoCount: secondCount, color: .primary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func groupLabel(title: String, photoCount: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text("\(photoCount) Photos")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
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
                .background(splitAfterIndex == nil ? Color(uiColor: .secondarySystemBackground) : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(splitAfterIndex == nil)
        .animation(.easeInOut(duration: 0.2), value: splitAfterIndex)
    }
}
