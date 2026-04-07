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

    private let thumbSize: CGFloat = 140

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionBanner

                photoStrip
                    .padding(.top, 20)

                if let idx = splitAfterIndex {
                    splitPreview(afterIndex: idx)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }

                Spacer(minLength: 0)

                confirmButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                let ids = photos.map(\.id)
                let uniqueIds = Set(ids)
                print("[SplitPlaceStop] onAppear place=\"\(placeTitle)\" photoCount=\(photos.count) uniqueIds=\(uniqueIds.count)")
                if uniqueIds.count != ids.count {
                    print("[SplitPlaceStop] ⚠️ duplicate RecapPhoto.id — duplicate count=\(ids.count - uniqueIds.count)")
                }
            }
            .onChange(of: splitAfterIndex) { old, new in
                print("[SplitPlaceStop] splitAfterIndex \(String(describing: old)) → \(String(describing: new))")
            }
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
                .foregroundColor(.white)

            Text(photos.count == 1 ? "1 Photo" : "\(photos.count) Photos")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    RecapPhotoThumbnail(
                        photo: photo,
                        cornerRadius: 6,
                        showIcon: false,
                        targetSize: CGSize(width: thumbSize * 2, height: thumbSize * 2)
                    )
                        .frame(width: thumbSize, height: thumbSize)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )

                    if index < photos.count - 1 {
                        splitDivider(afterIndex: index)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: thumbSize)
    }

    private func splitDivider(afterIndex index: Int) -> some View {
        let isSelected = splitAfterIndex == index
        return ZStack {
            Rectangle()
                .fill(isSelected ? Color.orange.opacity(0.15) : Color.clear)
                .frame(width: 36)

            Rectangle()
                .fill(isSelected ? Color.orange : Color.white.opacity(0.25))
                .frame(width: isSelected ? 3 : 1)

            Image(systemName: "scissors")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(4)
                .background(Circle().fill(Color.orange))
        }
        .frame(width: 36, height: thumbSize)
        .contentShape(Rectangle())
        .onTapGesture {
            let next: Int? = splitAfterIndex == index ? nil : index
            print("[SplitPlaceStop] divider tapped afterIndex=\(index) → \(String(describing: next))")
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                splitAfterIndex = next
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    /// Not `@ViewBuilder`: Swift 5.0 treats `if` branches here as views; assignment-only branches are `()`.
    private func splitPreview(afterIndex idx: Int) -> some View {
        let firstCount = idx + 1
        let secondCount = photos.count - firstCount
        // Split toward the left → smaller Group 1 (orange); toward the right → smaller Group 2 (orange).
        let group1TitleColor: Color
        let group2TitleColor: Color
        if firstCount < secondCount {
            group1TitleColor = .orange
            group2TitleColor = .white
        } else if secondCount < firstCount {
            group1TitleColor = .white
            group2TitleColor = .orange
        } else {
            group1TitleColor = .white
            group2TitleColor = .white
        }

        return HStack(spacing: 16) {
            groupLabel(title: "Group 1", photoCount: firstCount, titleColor: group1TitleColor)
            Image(systemName: "scissors")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            groupLabel(title: "Group 2", photoCount: secondCount, titleColor: group2TitleColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func groupLabel(title: String, photoCount: Int, titleColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(titleColor)
            Text("\(photoCount) Photos")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var confirmButton: some View {
        Button {
            guard let idx = splitAfterIndex else { return }
            print("[SplitPlaceStop] confirm split afterPhotoIndex=\(idx)")
            onSplit(idx)
            dismiss()
        } label: {
            Text(splitAfterIndex == nil ? "Select a split point above" : "Split into 2 Groups")
                .font(.body.weight(.semibold))
                .foregroundColor(splitAfterIndex == nil ? .secondary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(splitAfterIndex == nil ? Color(uiColor: .secondarySystemBackground) : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(splitAfterIndex == nil)
        .animation(.easeInOut(duration: 0.2), value: splitAfterIndex)
    }
}
