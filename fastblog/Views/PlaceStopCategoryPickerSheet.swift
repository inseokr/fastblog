//
//  PlaceStopCategoryPickerSheet.swift
//  fastblog
//

import MapKit
import SwiftUI

/// Lets the user pick one `MKPointOfInterestCategory` (stored as `PlaceStop.placeCategory`) or clear to no category (“Others”).
struct PlaceStopCategoryPickerSheet: View {
    let initialCategoryRaw: String?
    var onCancel: () -> Void
    var onDone: (String?) -> Void

    @State private var draftRaw: String = ""

    private static let poiCategories: [MKPointOfInterestCategory] = [
        .restaurant, .cafe, .bakery, .winery, .brewery, .nightlife, .hotel, .campground,
        .museum, .movieTheater, .theater, .amusementPark, .zoo, .aquarium, .park, .beach,
        .nationalPark, .airport, .publicTransport, .gasStation, .hospital, .pharmacy,
        .fitnessCenter, .store, .foodMarket, .library, .school, .university, .marina, .stadium, .bank,
    ]

    private var extraInitialRow: (raw: String, label: String)? {
        let t = initialCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return nil }
        let known = Set(Self.poiCategories.map(\.rawValue))
        guard !known.contains(t) else { return nil }
        return (t, Self.displayLabel(forRaw: t))
    }

    /// POI rows sorted A–Z by display label; unknown initial category is merged in. “Others” is shown separately at the bottom.
    private var sortedPOIRows: [(raw: String, label: String)] {
        var rows: [(raw: String, label: String)] = Self.poiCategories.map {
            ($0.rawValue, Self.displayLabel(for: $0))
        }
        if let extra = extraInitialRow {
            rows.append((extra.raw, extra.label))
        }
        rows.sort {
            let order = $0.label.localizedStandardCompare($1.label)
            if order == .orderedSame { return $0.raw < $1.raw }
            return order == .orderedAscending
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
                        isSelected: draftRaw == item.raw,
                        select: { draftRaw = item.raw }
                    )
                }
                categoryRow(
                    raw: "",
                    label: "Others",
                    isSelected: draftRaw.isEmpty,
                    select: { draftRaw = "" }
                )
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(draftRaw.isEmpty ? nil : draftRaw)
                    }
                }
            }
        }
        .onAppear {
            draftRaw = initialCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Full row is tappable; icon + label use shared category color / symbol.
    private func categoryRow(raw: String, label: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        return Button(action: select) {
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

    private static func displayLabel(for cat: MKPointOfInterestCategory) -> String {
        displayLabel(forRaw: cat.rawValue)
    }

    /// Human-readable label for a stored category string (matches map / place row naming).
    static func displayLabel(forRaw rawValue: String) -> String {
        PlacePOICategoryPresentation.displayLabel(forRaw: rawValue)
    }
}
