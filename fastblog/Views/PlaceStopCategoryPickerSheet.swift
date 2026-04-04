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
                    row(label: item.label, isSelected: draftRaw == item.raw) {
                        draftRaw = item.raw
                    }
                }
                row(label: "Others", isSelected: draftRaw.isEmpty) {
                    draftRaw = ""
                }
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

    private func row(label: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button {
            select()
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static func displayLabel(for cat: MKPointOfInterestCategory) -> String {
        displayLabel(forRaw: cat.rawValue)
    }

    /// Human-readable label for a stored category string (matches map / place row naming).
    static func displayLabel(forRaw rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Others" { return "Others" }

        let cat = MKPointOfInterestCategory(rawValue: trimmed)
        switch cat {
        case .restaurant:      return "Restaurant"
        case .cafe:            return "Café"
        case .bakery:          return "Bakery"
        case .winery:          return "Winery"
        case .brewery:         return "Brewery"
        case .nightlife:       return "Nightlife"
        case .hotel:           return "Hotel"
        case .campground:      return "Campground"
        case .museum:          return "Museum"
        case .movieTheater:    return "Movie Theater"
        case .theater:         return "Theater"
        case .amusementPark:   return "Amusement Park"
        case .zoo:             return "Zoo"
        case .aquarium:        return "Aquarium"
        case .park:            return "Park"
        case .beach:           return "Beach"
        case .nationalPark:    return "National Park"
        case .airport:         return "Airport"
        case .publicTransport: return "Transit"
        case .gasStation:      return "Gas Station"
        case .hospital:        return "Hospital"
        case .pharmacy:        return "Pharmacy"
        case .fitnessCenter:   return "Fitness"
        case .store:           return "Store"
        case .foodMarket:      return "Market"
        case .library:         return "Library"
        case .school:          return "School"
        case .university:      return "University"
        case .marina:          return "Marina"
        case .stadium:         return "Stadium"
        case .bank:            return "Bank"
        default: break
        }

        if trimmed.hasPrefix("MKPOICategory") {
            let remainder = String(trimmed.dropFirst("MKPOICategory".count))
            if remainder.isEmpty { return trimmed }
            return remainder.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
        if trimmed.count <= 4 { return trimmed.uppercased() }
        return trimmed
    }
}
