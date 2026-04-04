//
//  PlacePOICategoryPresentation.swift
//  fastblog
//
//  Single source for POI category label, SF Symbol, and accent color (blog rows, picker, maps, Places Visited).
//

import MapKit
import SwiftUI

enum PlacePOICategoryPresentation {

    struct Info: Equatable {
        let symbol: String
        let label: String
        let color: Color
    }

    /// Resolved style for a stored `PlaceStop.placeCategory` raw string, map filter key, or `"Others"`.
    static func presentation(forRaw rawValue: String?) -> Info {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("Others") == .orderedSame {
            return Info(
                symbol: "square.grid.3x3.fill",
                label: "Others",
                color: Color(red: 0.58, green: 0.58, blue: 0.62)
            )
        }

        let mk = MKPointOfInterestCategory(rawValue: trimmed)
        if let info = info(forMKCategory: mk) {
            return info
        }

        if let info = heuristicInfo(forTrimmed: trimmed) {
            return info
        }

        return Info(
            symbol: "mappin.circle.fill",
            label: displayLabel(forRaw: trimmed),
            color: Color(red: 0.48, green: 0.5, blue: 0.56)
        )
    }

    /// Human-readable label (picker, chips, maps) — stable for any stored raw string.
    static func displayLabel(forRaw rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Others" { return "Others" }

        let mk = MKPointOfInterestCategory(rawValue: trimmed)
        if let info = info(forMKCategory: mk) {
            return info.label
        }

        if trimmed.hasPrefix("MKPOICategory") {
            let remainder = String(trimmed.dropFirst("MKPOICategory".count))
            if remainder.isEmpty { return trimmed }
            return remainder.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }

        if trimmed.count <= 4 { return trimmed.uppercased() }
        return trimmed
    }

    // MARK: - MK category → symbol / label / color

    private static func info(forMKCategory cat: MKPointOfInterestCategory) -> Info? {
        switch cat {
        case .restaurant:
            return Info(symbol: "fork.knife", label: "Restaurant", color: Color(red: 1, green: 0.45, blue: 0.18))
        case .cafe:
            return Info(symbol: "cup.and.saucer.fill", label: "Café", color: Color(red: 0.52, green: 0.34, blue: 0.2))
        case .bakery:
            return Info(symbol: "birthday.cake.fill", label: "Bakery", color: Color(red: 0.95, green: 0.62, blue: 0.32))
        case .winery:
            return Info(symbol: "wineglass.fill", label: "Winery", color: Color(red: 0.55, green: 0.22, blue: 0.48))
        case .brewery:
            return Info(symbol: "mug.fill", label: "Brewery", color: Color(red: 0.78, green: 0.52, blue: 0.18))
        case .nightlife:
            return Info(symbol: "moon.stars.fill", label: "Nightlife", color: Color(red: 0.42, green: 0.32, blue: 0.78))
        case .hotel:
            return Info(symbol: "bed.double.fill", label: "Hotel", color: Color(red: 0.28, green: 0.48, blue: 0.88))
        case .campground:
            return Info(symbol: "tent.fill", label: "Campground", color: Color(red: 0.32, green: 0.68, blue: 0.38))
        case .museum:
            return Info(symbol: "building.columns.fill", label: "Museum", color: Color(red: 0.62, green: 0.4, blue: 0.28))
        case .movieTheater:
            return Info(symbol: "film.fill", label: "Movie Theater", color: Color(red: 0.78, green: 0.28, blue: 0.52))
        case .theater:
            return Info(symbol: "theatermasks.fill", label: "Theater", color: Color(red: 0.82, green: 0.32, blue: 0.55))
        case .amusementPark:
            return Info(symbol: "ticket.fill", label: "Amusement Park", color: Color(red: 0.62, green: 0.32, blue: 0.88))
        case .zoo:
            return Info(symbol: "pawprint.fill", label: "Zoo", color: Color(red: 0.38, green: 0.58, blue: 0.32))
        case .aquarium:
            return Info(symbol: "fish.fill", label: "Aquarium", color: Color(red: 0.18, green: 0.62, blue: 0.78))
        case .park:
            return Info(symbol: "leaf.fill", label: "Park", color: Color(red: 0.32, green: 0.72, blue: 0.4))
        case .beach:
            return Info(symbol: "beach.umbrella.fill", label: "Beach", color: Color(red: 0.28, green: 0.76, blue: 0.85))
        case .nationalPark:
            return Info(symbol: "tree.fill", label: "National Park", color: Color(red: 0.22, green: 0.52, blue: 0.34))
        case .airport:
            return Info(symbol: "airplane", label: "Airport", color: Color(red: 0.42, green: 0.54, blue: 0.74))
        case .publicTransport:
            return Info(symbol: "tram.fill", label: "Transit", color: Color(red: 0.2, green: 0.46, blue: 0.82))
        case .gasStation:
            return Info(symbol: "fuelpump.fill", label: "Gas Station", color: Color(red: 0.88, green: 0.52, blue: 0.18))
        case .hospital:
            return Info(symbol: "cross.fill", label: "Hospital", color: Color(red: 0.92, green: 0.26, blue: 0.3))
        case .pharmacy:
            return Info(symbol: "cross.case.fill", label: "Pharmacy", color: Color(red: 0.86, green: 0.34, blue: 0.48))
        case .fitnessCenter:
            return Info(symbol: "dumbbell.fill", label: "Fitness", color: Color(red: 0.92, green: 0.34, blue: 0.34))
        case .store:
            return Info(symbol: "bag.fill", label: "Store", color: Color(red: 0.52, green: 0.38, blue: 0.78))
        case .foodMarket:
            return Info(symbol: "cart.fill", label: "Market", color: Color(red: 0.38, green: 0.66, blue: 0.44))
        case .library:
            return Info(symbol: "books.vertical.fill", label: "Library", color: Color(red: 0.52, green: 0.44, blue: 0.32))
        case .school:
            return Info(symbol: "graduationcap.fill", label: "School", color: Color(red: 0.28, green: 0.5, blue: 0.78))
        case .university:
            return Info(symbol: "graduationcap.fill", label: "University", color: Color(red: 0.24, green: 0.42, blue: 0.68))
        case .marina:
            return Info(symbol: "sailboat.fill", label: "Marina", color: Color(red: 0.22, green: 0.56, blue: 0.74))
        case .stadium:
            return Info(symbol: "sportscourt.fill", label: "Stadium", color: Color(red: 0.88, green: 0.38, blue: 0.22))
        case .bank:
            return Info(symbol: "banknote.fill", label: "Bank", color: Color(red: 0.2, green: 0.58, blue: 0.46))
        default:
            // New or unrecognized MapKit POI kinds — fall back to heuristic / generic styling upstream.
            return nil
        }
    }

    /// Alternate POI strings (server / legacy) → same visuals as a known MK category.
    private static func heuristicInfo(forTrimmed trimmed: String) -> Info? {
        let lower = trimmed.lowercased()
        let blob = lower + " " + displayLabel(forRaw: trimmed).lowercased()

        func firstMatch(_ pairs: [(String, MKPointOfInterestCategory)]) -> Info? {
            for (needle, mk) in pairs where blob.contains(needle) {
                return info(forMKCategory: mk)
            }
            return nil
        }

        return firstMatch([
            ("restaurant", .restaurant),
            ("fooddelivery", .restaurant),
            ("dining", .restaurant),
            ("cafe", .cafe),
            ("coffee", .cafe),
            ("bakery", .bakery),
            ("winery", .winery),
            ("brewery", .brewery),
            ("distillery", .brewery),
            ("nightlife", .nightlife),
            ("night club", .nightlife),
            ("bar", .nightlife),
            ("pub", .nightlife),
            ("hotel", .hotel),
            ("lodging", .hotel),
            ("campground", .campground),
            ("museum", .museum),
            ("artgallery", .museum),
            ("art gallery", .museum),
            ("movietheater", .movieTheater),
            ("movie theater", .movieTheater),
            ("theater", .theater),
            ("amusement", .amusementPark),
            ("carnival", .amusementPark),
            ("theme park", .amusementPark),
            ("zoo", .zoo),
            ("aquarium", .aquarium),
            ("nationalpark", .nationalPark),
            ("national park", .nationalPark),
            ("park", .park),
            ("garden", .park),
            ("beach", .beach),
            ("marina", .marina),
            ("surf", .beach),
            ("airport", .airport),
            ("publictransport", .publicTransport),
            ("transit", .publicTransport),
            ("gasstation", .gasStation),
            ("fuel", .gasStation),
            ("hospital", .hospital),
            ("pharmacy", .pharmacy),
            ("fitness", .fitnessCenter),
            ("gym", .fitnessCenter),
            ("store", .store),
            ("shopping", .store),
            ("market", .foodMarket),
            ("library", .library),
            ("school", .school),
            ("university", .university),
            ("college", .university),
            ("stadium", .stadium),
            ("bank", .bank),
        ])
    }
}

// MARK: - Compact badge (Places Visited cards, map cards)

struct PlacePOICategoryBadge: View {
    let rawCategory: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: rawCategory)
        HStack(spacing: 5) {
            Image(systemName: p.symbol)
                .font(.caption2)
            Text(p.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(p.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(p.color.opacity(colorScheme == .dark ? 0.22 : 0.14))
        )
    }
}
