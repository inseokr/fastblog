//
//  PlaceStopCategoryPickerSheet.swift
//  fastblog
//

import SwiftUI

/// Lets the user pick one `MKPointOfInterestCategory` (stored as `PlaceStop.placeCategory`) or clear to no category (“Others”).
/// Tapping a row saves immediately and dismisses; only **Cancel** leaves without changes.
struct PlaceStopCategoryPickerSheet: View {
    let initialCategoryRaw: String?
    var onCancel: () -> Void
    var onDone: (String?) -> Void

    private var normalizedInitialRaw: String {
        initialCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Full MapKit POI list (see `PlacePOICategoryCatalog`) plus any stored value not yet in the catalog.
    private var sortedPOIRows: [(raw: String, label: String)] {
        var rows: [(raw: String, label: String)] = PlacePOICategoryCatalog.allSelectableCategoryRawValuesSortedByLabel().map {
            ($0, Self.displayLabel(forRaw: $0))
        }
        let initial = initialCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !initial.isEmpty, !rows.contains(where: { $0.raw == initial }) {
            rows.append((initial, Self.displayLabel(forRaw: initial)))
            rows.sort {
                let order = $0.label.localizedStandardCompare($1.label)
                if order == .orderedSame { return $0.raw < $1.raw }
                return order == .orderedAscending
            }
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedPOIRows, id: \.raw) { item in
                    categoryRow(
                        raw: item.raw,
                        label: item.label,
                        isSelected: normalizedInitialRaw == item.raw
                    ) {
                        onDone(item.raw)
                    }
                }
                categoryRow(
                    raw: "",
                    label: "Others",
                    isSelected: normalizedInitialRaw.isEmpty
                ) {
                    onDone(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Full row is tappable; icon + label use shared category color / symbol. Tap saves and dismisses the sheet.
    private func categoryRow(raw: String, label: String, isSelected: Bool, onPick: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        return Button(action: onPick) {
            HStack(spacing: 12) {
                Image(systemName: p.symbol)
                    .font(.body)
                    .foregroundStyle(p.color)
                    .frame(width: 28, alignment: .center)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Human-readable label for a stored category string (matches map / place row naming).
    static func displayLabel(forRaw rawValue: String) -> String {
        PlacePOICategoryPresentation.displayLabel(forRaw: rawValue)
    }
}
