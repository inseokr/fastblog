//
//  PlaceStopActionSheet.swift
//  Capper
//

import SwiftUI
import UIKit

struct PlaceStopActionSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    var onEditName: () -> Void
    var onManagePhotos: () -> Void
    var onEditMode: () -> Void
    /// Non-nil when there is at least one adjacent stop eligible for merge.
    var onMergePlaces: (() -> Void)?
    /// Non-nil when the stop has more than one photo and can be split.
    var onSplit: (() -> Void)?
    var onRemoveFromBlog: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Header truncation on non‑Max phones at xxxLarge+ Dynamic Type (40 = 45 − 5 vs. the usual comfortable cap).
    private static let placeTitleHeaderCharLimitNarrowLargestType = 40

    private var sheetHeight: CGFloat {
        var base: CGFloat = 380
        if onMergePlaces != nil { base += 52 }
        if onSplit != nil { base += 52 }
        return base
    }

    /// Non‑Max iPhone widths are below ~428pt (e.g. 11 / 12 / 13 / 14 standard); Pro Max / Plus are wider.
    private var shouldUseTighterPlaceTitleHeader: Bool {
        UIScreen.main.bounds.width < 428 && dynamicTypeSize >= .xxxLarge
    }

    private var placeTitleForHeader: String {
        guard shouldUseTighterPlaceTitleHeader else { return placeTitle }
        let limit = Self.placeTitleHeaderCharLimitNarrowLargestType
        guard placeTitle.count > limit else { return placeTitle }
        guard let endIdx = placeTitle.index(placeTitle.startIndex, offsetBy: limit, limitedBy: placeTitle.endIndex) else {
            return placeTitle
        }
        let trimmed = String(placeTitle[..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return placeTitle }
        return trimmed + "…"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Header - Typography Hierarchy
            VStack(spacing: 4) {
                Text(placeTitleForHeader)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel(placeTitle)

                if let subtitle = placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 24)

            // Section 1: Editing Actions
            VStack(spacing: 0) {
                actionRow(icon: "pencil", title: "Edit Place Name", action: {
                    dismiss()
                    onEditName()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(icon: "photo.on.rectangle", title: "Manage Photos", action: {
                    dismiss()
                    onManagePhotos()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(icon: "text.alignleft", title: "Edit Caption & Details", action: {
                    dismiss()
                    onEditMode()
                })
            }
            .background(Color(white: 0.15))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, onMergePlaces != nil || onSplit != nil ? 12 : 24)

            // Section 2: Group Actions (merge / split) — shown only when applicable
            if onMergePlaces != nil || onSplit != nil {
                VStack(spacing: 0) {
                    if let merge = onMergePlaces {
                        actionRow(icon: "arrow.triangle.merge", title: "Merge Places", action: {
                            dismiss()
                            merge()
                        })
                        if onSplit != nil {
                            Divider().background(Color(white: 0.3))
                        }
                    }
                    if let split = onSplit {
                        actionRow(icon: "scissors", title: "Split Photo Group", action: {
                            dismiss()
                            split()
                        })
                    }
                }
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            // Section 3: Destructive Action
            VStack(spacing: 0) {
                Button(action: {
                    dismiss()
                    onRemoveFromBlog()
                }) {
                    Text("Hide from Blog")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .background(Color(white: 0.15))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .presentationBackground {
            // Subtle blur for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .presentationDetents([.height(sheetHeight)])
        .preferredColorScheme(.dark)
        .onAppear {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlaceStopActionSheet(
        placeTitle: "Golden Gate Bridge",
        placeSubtitle: "San Francisco",
        onEditName: {},
        onManagePhotos: {},
        onEditMode: {},
        onMergePlaces: {},
        onSplit: {},
        onRemoveFromBlog: {}
    )
}
