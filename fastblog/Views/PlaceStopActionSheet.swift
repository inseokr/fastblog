//
//  PlaceStopActionSheet.swift
//  Capper
//

import SwiftUI
import UIKit

struct PlaceStopActionSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    /// Omit to hide "Edit Place Name". When the recap is read-only, the parent should open the name editor without toggling blog edit mode.
    var onEditPlaceName: (() -> Void)? = nil
    var onManagePhotos: () -> Void
    /// Omit to hide "Edit Caption". When the recap is read-only, the parent should open the caption editor without toggling blog edit mode.
    var onEditCaption: (() -> Void)? = nil
    /// Non-nil when there is at least one adjacent stop eligible for merge.
    var onMergePlaces: (() -> Void)?
    /// Non-nil when the stop has more than one photo and can be split.
    var onSplit: (() -> Void)?
    var onRemoveFromBlog: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Header truncation on non‑Max phones at xxxLarge+ Dynamic Type (40 = 45 − 5 vs. the usual comfortable cap).
    private static let placeTitleHeaderCharLimitNarrowLargestType = 40

    /// Row chrome matches `actionRow` / destructive button: 16pt vertical padding each side + label/icon line height.
    private var actionRowMinHeight: CGFloat {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        return max(24, ceil(bodyFont.lineHeight)) + 32
    }

    /// Derive height from typography so the pull-up grows with Dynamic Type (fixed pt values clip at accessibility sizes).
    private var sheetHeight: CGFloat {
        let headlineFont = UIFont.preferredFont(forTextStyle: .headline)
        let subheadFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let rowH = actionRowMinHeight

        var height: CGFloat = 8 + 5 + 10

        height += 2 * ceil(headlineFont.lineHeight) + 4
        if let subtitle = placeSubtitle, !subtitle.isEmpty {
            height += ceil(subheadFont.lineHeight)
        }
        height += 14

        var section1Rows = 1
        var section1Dividers = 0
        if onEditPlaceName != nil {
            section1Rows += 1
            section1Dividers += 1
        }
        if onEditCaption != nil {
            section1Rows += 1
            section1Dividers += 1
        }
        height += CGFloat(section1Rows) * rowH + CGFloat(section1Dividers)
        height += (onMergePlaces != nil || onSplit != nil) ? 12 : 24

        if onMergePlaces != nil || onSplit != nil {
            var section2Rows = 0
            var section2Dividers = 0
            if onMergePlaces != nil {
                section2Rows += 1
                if onSplit != nil { section2Dividers += 1 }
            }
            if onSplit != nil { section2Rows += 1 }
            height += CGFloat(section2Rows) * rowH + CGFloat(section2Dividers)
            height += 24
        }

        height += 8

        height += rowH
        height += 34

        return max(ceil(height), 320)
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
            RoundedRectangle(appChromeBaseRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

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
            .padding(.bottom, 14)

            // Section 1: Editing Actions
            VStack(spacing: 0) {
                if let onEditPlaceName {
                    actionRow(icon: "mappin.and.ellipse", title: "Edit Place Name", action: {
                        dismiss()
                        onEditPlaceName()
                    })
                    Divider()
                        .background(Color(white: 0.3))
                }
                actionRow(icon: "photo.on.rectangle", title: "Manage Media", action: {
                    dismiss()
                    onManagePhotos()
                })
                if let onEditCaption {
                    Divider()
                        .background(Color(white: 0.3))
                    actionRow(icon: "text.alignleft", title: "Edit Caption", action: {
                        dismiss()
                        onEditCaption()
                    })
                }
            }
            .background(Color(white: 0.15))
            .appChromeCornerRadius(12)
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
                        actionRow(icon: "scissors", title: "Split Moment", action: {
                            dismiss()
                            split()
                        })
                    }
                }
                .background(Color(white: 0.15))
                .appChromeCornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 8)

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
            .appChromeCornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
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
        onEditPlaceName: {},
        onManagePhotos: {},
        onEditCaption: {},
        onMergePlaces: {},
        onSplit: {},
        onRemoveFromBlog: {}
    )
}
