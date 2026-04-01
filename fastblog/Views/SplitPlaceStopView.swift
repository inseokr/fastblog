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
                        .padding(.top, 20)
                }

                Spacer(minLength: 0)

                confirmButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Split Photo Group")
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
        VStack(spacing: 4) {
            Text(placeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Tap the divider between two photos to set the split point.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 16)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    RecapPhotoThumbnail(photo: photo, cornerRadius: 6, showIcon: false)
                        .frame(width: thumbSize, height: thumbSize)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    if index < photos.count - 1 {
                        splitDivider(afterIndex: index)
                    }
                }
            }
            .padding(.horizontal, 16)
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

            if isSelected {
                Image(systemName: "scissors")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.orange))
            }
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

    @ViewBuilder
    private func splitPreview(afterIndex idx: Int) -> some View {
        let firstCount = idx + 1
        let secondCount = photos.count - firstCount

        HStack(spacing: 16) {
            groupLabel(title: "Group 1", photoCount: firstCount, color: .orange)
            Image(systemName: "scissors")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            groupLabel(title: "Group 2", photoCount: secondCount, color: .white)
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
                .background(splitAfterIndex == nil ? Color.white.opacity(0.08) : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(splitAfterIndex == nil)
        .animation(.easeInOut(duration: 0.2), value: splitAfterIndex)
    }
}
