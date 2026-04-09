//
//  PlacePOICategoryCatalog.swift
//  fastblog
//
//  Bloggo's selectable place categories for pickers and filter chips: Apple `MKPOICategory…` raw strings
//  stored on `PlaceStop.placeCategory` (and echoed by the API). This is the app’s canonical UI list;
//  it is not the same as `PlaceCategoryID` in StoryCaptionGenerator (coarse buckets for caption prompts).
//

import Foundation
import MapKit

enum PlacePOICategoryCatalog {

    private static let staticPOICategories: [MKPointOfInterestCategory] = [
        .restaurant, .cafe, .bakery, .winery, .brewery, .nightlife, .hotel, .campground,
        .museum, .movieTheater, .theater, .amusementPark, .zoo, .aquarium, .park, .beach,
        .nationalPark, .airport, .publicTransport, .gasStation, .hospital, .pharmacy,
        .fitnessCenter, .store, .foodMarket, .library, .school, .university, .marina, .stadium, .bank,
        .atm, .carRental, .evCharger, .fireStation, .laundry, .parking, .police, .postOffice, .restroom,
    ]

    /// iOS 18+ (and any) POI kinds referenced by raw string so we list them on all deployment targets.
    private static let stringOnlyPOICategoryRawValues: [String] = [
        "MKPOICategoryAnimalService",
        "MKPOICategoryAutomotiveRepair",
        "MKPOICategoryBaseball",
        "MKPOICategoryBasketball",
        "MKPOICategoryBeauty",
        "MKPOICategoryBowling",
        "MKPOICategoryCastle",
        "MKPOICategoryConventionCenter",
        "MKPOICategoryDistillery",
        "MKPOICategoryFairground",
        "MKPOICategoryFishing",
        "MKPOICategoryFortress",
        "MKPOICategoryGolf",
        "MKPOICategoryGoKart",
        "MKPOICategoryHiking",
        "MKPOICategoryKayaking",
        "MKPOICategoryLandmark",
        "MKPOICategoryMiniGolf",
        "MKPOICategoryMusicVenue",
        "MKPOICategoryNationalMonument",
        "MKPOICategoryPlanetarium",
        "MKPOICategoryRockClimbing",
        "MKPOICategoryRVPark",
        "MKPOICategorySkatePark",
        "MKPOICategorySkating",
        "MKPOICategorySkiing",
        "MKPOICategorySoccer",
        "MKPOICategorySpa",
        "MKPOICategorySurfing",
        "MKPOICategorySwimming",
        "MKPOICategoryTennis",
        "MKPOICategoryVolleyball",
    ]

    /// Every selectable POI raw value, A–Z by localized display label (shared by picker and filters).
    static func allSelectableCategoryRawValuesSortedByLabel() -> [String] {
        var seen = Set<String>()
        var r: [String] = []
        for c in staticPOICategories {
            let v = c.rawValue
            if seen.insert(v).inserted { r.append(v) }
        }
        for v in stringOnlyPOICategoryRawValues where seen.insert(v).inserted {
            r.append(v)
        }
        return r.sorted {
            PlacePOICategoryPresentation.displayLabel(forRaw: $0).localizedStandardCompare(
                PlacePOICategoryPresentation.displayLabel(forRaw: $1)
            ) == .orderedAscending
        }
    }

    /// Union of the full catalog with any raw values already stored (future MapKit strings, server quirks). `"Others"` is omitted here; pass `includeOthers` when the UI needs that chip.
    static func mergedCategoryRawsForFilters(dataRaws: Set<String>, includeOthers: Bool) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        func appendRaw(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            if t.caseInsensitiveCompare("Others") == .orderedSame { return }
            if seen.insert(t).inserted { merged.append(t) }
        }

        for raw in allSelectableCategoryRawValuesSortedByLabel() { appendRaw(raw) }
        for raw in dataRaws { appendRaw(raw) }

        merged.sort {
            PlacePOICategoryPresentation.displayLabel(forRaw: $0).localizedStandardCompare(
                PlacePOICategoryPresentation.displayLabel(forRaw: $1)
            ) == .orderedAscending
        }
        if includeOthers { merged.append("Others") }
        return merged
    }

    /// Category filter chips that only include raw values present in `dataRaws` (sorted by display label), plus `"Others"` when `includeOthers`. Unlike `mergedCategoryRawsForFilters`, the full selectable catalog is not prepended—empty categories are omitted.
    static func categoryRawsAppearingInDataForFilters(dataRaws: Set<String>, includeOthers: Bool) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for raw in dataRaws {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.caseInsensitiveCompare("Others") == .orderedSame { continue }
            if seen.insert(t).inserted { merged.append(t) }
        }
        merged.sort {
            PlacePOICategoryPresentation.displayLabel(forRaw: $0).localizedStandardCompare(
                PlacePOICategoryPresentation.displayLabel(forRaw: $1)
            ) == .orderedAscending
        }
        if includeOthers { merged.append("Others") }
        return merged
    }
}
