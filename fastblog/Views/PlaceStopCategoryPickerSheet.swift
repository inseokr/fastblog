//
//  PlaceStopCategoryPickerSheet.swift
//  fastblog
//

import SwiftUI
import MapKit

/// Lets the user pick one `MKPointOfInterestCategory` (stored as `PlaceStop.placeCategory`) or clear to no category (“Others”).
/// Tapping a row saves immediately and dismisses; only **Cancel** leaves without changes.
struct PlaceStopCategoryPickerSheet: View {
    private struct GroupedCategorySection: Identifiable {
        let id: String
        let title: String
        let items: [(raw: String, label: String)]
    }

    private enum CategoryGroup: String {
        case foodDrink = "Food & Drink"
        case staysTravel = "Stays & Travel"
        case artsEntertainment = "Arts & Entertainment"
        case sportsOutdoors = "Sports & Outdoors"
        case shoppingServices = "Shopping & Services"
        case civicEducationHealth = "Civic, Education & Health"
        case utilitiesTransport = "Utilities & Transit"
        case other = "Other"

        var order: Int {
            switch self {
            case .foodDrink: return 0
            case .staysTravel: return 1
            case .artsEntertainment: return 2
            case .sportsOutdoors: return 3
            case .shoppingServices: return 4
            case .civicEducationHealth: return 5
            case .utilitiesTransport: return 6
            case .other: return 7
            }
        }
    }

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

    private var groupedSections: [GroupedCategorySection] {
        var grouped: [CategoryGroup: [(raw: String, label: String)]] = [:]
        for item in sortedPOIRows {
            grouped[categoryGroup(forRaw: item.raw), default: []].append(item)
        }
        grouped[.other, default: []].append((raw: "", label: "Others"))

        let sections = grouped.compactMap { group, items -> GroupedCategorySection? in
            guard !items.isEmpty else { return nil }
            return GroupedCategorySection(
                id: group.rawValue,
                title: group.rawValue,
                items: items
            )
        }

        return sections.sorted { lhs, rhs in
            let leftOrder = CategoryGroup(rawValue: lhs.title)?.order ?? .max
            let rightOrder = CategoryGroup(rawValue: rhs.title)?.order ?? .max
            if leftOrder == rightOrder {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return leftOrder < rightOrder
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            CategoryChipFlowLayout(spacing: 10, rowSpacing: 10) {
                                ForEach(section.items, id: \.raw) { item in
                                    categoryChip(
                                        raw: item.raw,
                                        label: item.label,
                                        isSelected: normalizedInitialRaw == item.raw
                                    ) {
                                        if item.raw.isEmpty {
                                            onDone(nil)
                                        } else {
                                            onDone(item.raw)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
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

    /// Chip-style category picker that wraps into rows based on available width.
    private func categoryChip(raw: String, label: String, isSelected: Bool, onPick: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        return Button(action: onPick) {
            HStack(spacing: 8) {
                Image(systemName: p.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : p.color)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? p.color : p.color.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(p.color.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Human-readable label for a stored category string (matches map / place row naming).
    static func displayLabel(forRaw rawValue: String) -> String {
        PlacePOICategoryPresentation.displayLabel(forRaw: rawValue)
    }

    private func categoryGroup(forRaw raw: String) -> CategoryGroup {
        if raw.isEmpty { return .other }

        switch raw {
        case MKPointOfInterestCategory.restaurant.rawValue,
             MKPointOfInterestCategory.cafe.rawValue,
             MKPointOfInterestCategory.bakery.rawValue,
             MKPointOfInterestCategory.winery.rawValue,
             MKPointOfInterestCategory.brewery.rawValue,
             MKPointOfInterestCategory.foodMarket.rawValue,
             "MKPOICategoryDistillery":
            return .foodDrink

        case MKPointOfInterestCategory.hotel.rawValue,
             MKPointOfInterestCategory.campground.rawValue,
             MKPointOfInterestCategory.airport.rawValue,
             MKPointOfInterestCategory.carRental.rawValue,
             MKPointOfInterestCategory.marina.rawValue,
             "MKPOICategoryRVPark":
            return .staysTravel

        case MKPointOfInterestCategory.museum.rawValue,
             MKPointOfInterestCategory.movieTheater.rawValue,
             MKPointOfInterestCategory.theater.rawValue,
             MKPointOfInterestCategory.nightlife.rawValue,
             MKPointOfInterestCategory.amusementPark.rawValue,
             MKPointOfInterestCategory.zoo.rawValue,
             MKPointOfInterestCategory.aquarium.rawValue,
             "MKPOICategoryMusicVenue",
             "MKPOICategoryPlanetarium",
             "MKPOICategoryCastle",
             "MKPOICategoryFortress",
             "MKPOICategoryLandmark",
             "MKPOICategoryNationalMonument",
             "MKPOICategoryConventionCenter",
             "MKPOICategoryFairground":
            return .artsEntertainment

        case MKPointOfInterestCategory.park.rawValue,
             MKPointOfInterestCategory.beach.rawValue,
             MKPointOfInterestCategory.nationalPark.rawValue,
             MKPointOfInterestCategory.stadium.rawValue,
             MKPointOfInterestCategory.fitnessCenter.rawValue,
             "MKPOICategoryBaseball",
             "MKPOICategoryBasketball",
             "MKPOICategoryBowling",
             "MKPOICategoryGolf",
             "MKPOICategoryMiniGolf",
             "MKPOICategoryHiking",
             "MKPOICategoryKayaking",
             "MKPOICategoryRockClimbing",
             "MKPOICategorySkatePark",
             "MKPOICategorySkating",
             "MKPOICategorySkiing",
             "MKPOICategorySoccer",
             "MKPOICategorySurfing",
             "MKPOICategorySwimming",
             "MKPOICategoryTennis",
             "MKPOICategoryVolleyball",
             "MKPOICategoryFishing",
             "MKPOICategoryGoKart":
            return .sportsOutdoors

        case MKPointOfInterestCategory.store.rawValue,
             MKPointOfInterestCategory.bank.rawValue,
             MKPointOfInterestCategory.atm.rawValue,
             MKPointOfInterestCategory.laundry.rawValue,
             "MKPOICategoryBeauty",
             "MKPOICategorySpa",
             "MKPOICategoryAnimalService",
             "MKPOICategoryAutomotiveRepair":
            return .shoppingServices

        case MKPointOfInterestCategory.hospital.rawValue,
             MKPointOfInterestCategory.pharmacy.rawValue,
             MKPointOfInterestCategory.library.rawValue,
             MKPointOfInterestCategory.school.rawValue,
             MKPointOfInterestCategory.university.rawValue,
             MKPointOfInterestCategory.police.rawValue,
             MKPointOfInterestCategory.fireStation.rawValue,
             MKPointOfInterestCategory.postOffice.rawValue:
            return .civicEducationHealth

        case MKPointOfInterestCategory.publicTransport.rawValue,
             MKPointOfInterestCategory.gasStation.rawValue,
             MKPointOfInterestCategory.evCharger.rawValue,
             MKPointOfInterestCategory.parking.rawValue,
             MKPointOfInterestCategory.restroom.rawValue:
            return .utilitiesTransport

        default:
            return .other
        }
    }
}

/// Flow layout that keeps each chip at intrinsic width and wraps rows by available width.
private struct CategoryChipFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            contentWidth = max(contentWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let contentHeight = y + rowHeight
        let fittedWidth = proposal.width ?? contentWidth
        return CGSize(width: fittedWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
