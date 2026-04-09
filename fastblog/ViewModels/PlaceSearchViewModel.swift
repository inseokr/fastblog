//
//  PlaceSearchViewModel.swift
//  fastblog
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

/// A named POI returned for a map tap when several places are too close to pick automatically.
struct MapTapPOICandidate: Identifiable {
    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
    let name: String
    let category: String?
    let coordinate: CLLocationCoordinate2D
    /// Distance from the user’s tap to this POI’s placemark (meters).
    let distanceMeters: Double
}

/// Result of resolving a bare map tap (no `MKMapFeatureAnnotation`) to a place.
enum MapTapPOIResult {
    case none
    case single(name: String, category: String?, coordinate: CLLocationCoordinate2D)
    case ambiguous(candidates: [MapTapPOICandidate])
}

/// Wraps MKLocalSearchCompleter for place suggestions, biased by a specific location.
final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    var onPlaceSelected: ((String) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()
    private let debounceInterval: TimeInterval = 0.3

    /// If set, search results are biased towards this region.
    var biasRegion: MKCoordinateRegion? {
        didSet {
            if let region = biasRegion {
                completer.region = region
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]

        $query
            .debounce(for: .seconds(debounceInterval), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                self?.updateCompleter(query: newQuery)
            }
            .store(in: &cancellables)
    }

    func setBiasLocation(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate = coordinate else { return }
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        self.biasRegion = region
    }

    private func updateCompleter(query: String) {
        if query.isEmpty {
            suggestions = []
            return
        }
        completer.queryFragment = query
    }

    func clearQuery() {
        query = ""
        suggestions = []
    }

    /// Resolves a search completion to its MKPointOfInterestCategory raw value.
    /// Performs a single MKLocalSearch round-trip; returns nil if no POI category is available.
    func fetchCategory(for completion: MKLocalSearchCompletion) async -> String? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let mapItem = response.mapItems.first else {
            debugPrint("[Category] fetchCategory(autocomplete) '\(completion.title)' → nil (no mapItems)")
            return nil
        }
        let raw = mapItem.pointOfInterestCategory?.rawValue
        debugPrint("[Category] fetchCategory(autocomplete) '\(completion.title)' → \(raw ?? "nil")")
        return raw
    }

    /// Search radius for POIs around a map tap (meters). Scales with zoom so we don’t pull in far-away DB hits.
    private static func tapSearchRadiusMeters(mapRegion: MKCoordinateRegion?) -> Double {
        if let region = mapRegion {
            let metersPerPoint = region.span.latitudeDelta * 111_000.0 / 500.0
            return max(25.0, min(80.0, metersPerPoint * 22.0))
        }
        return 80.0
    }

    /// Resolves a bare map tap (coordinate only) to a POI. Uses **closest placemark distance** only—no category
    /// bias, so the tapped building wins over a farther “parent” campus. If two or more POIs are almost
    /// equally close, returns `.ambiguous` so the UI can ask which one.
    func resolveMapTapPOI(near coordinate: CLLocationCoordinate2D, mapRegion: MKCoordinateRegion? = nil) async -> MapTapPOIResult {
        let tapRadius = Self.tapSearchRadiusMeters(mapRegion: mapRegion)
        debugPrint("[POI] resolveMapTapPOI radius=\(Int(tapRadius))m latDelta=\(mapRegion?.span.latitudeDelta ?? -1)")

        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: tapRadius)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !response.mapItems.isEmpty else { return .none }

        let withName = response.mapItems.filter { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let scored: [(item: MKMapItem, distance: Double)] = withName.compactMap { item in
            let loc = item.placemark.location
                ?? CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let d = tapLocation.distance(from: loc)
            guard d <= tapRadius else { return nil }
            return (item, d)
        }
        .sorted { $0.distance < $1.distance }

        guard let first = scored.first else {
            debugPrint("[POI] no named POI within tap radius")
            return .none
        }

        let gapToSecond = scored.count >= 2 ? scored[1].distance - first.distance : Double.greatestFiniteMagnitude
        /// If the #2 POI is almost as close as #1, auto-picking is often wrong—let the user choose.
        let ambiguousGapMeters: Double = 22

        if scored.count >= 2, gapToSecond < ambiguousGapMeters {
            let capped = scored.prefix(8).map { pair in
                MapTapPOICandidate(
                    name: (pair.item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    category: pair.item.pointOfInterestCategory?.rawValue,
                    coordinate: pair.item.placemark.coordinate,
                    distanceMeters: pair.distance
                )
            }
            debugPrint("[POI] ambiguous tap: \(capped.count) candidates (gap \(Int(gapToSecond))m)")
            return .ambiguous(candidates: Array(capped))
        }

        let name = (first.item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .none }
        debugPrint("[POI] single POI '\(name)' dist=\(Int(first.distance))m")
        return .single(
            name: name,
            category: first.item.pointOfInterestCategory?.rawValue,
            coordinate: first.item.placemark.coordinate
        )
    }

    /// Resolves POI category at a coordinate by searching for the place name in a small region.
    /// Use after reverse geocoding to get the MKPointOfInterestCategory for a map-tapped location.
    func fetchCategory(at coordinate: CLLocationCoordinate2D, name: String) async -> String? {
        guard !name.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let mapItem = response.mapItems.first else {
            debugPrint("[Category] fetchCategory(geocode fallback) '\(name)' → nil (no mapItems)")
            return nil
        }
        let raw = mapItem.pointOfInterestCategory?.rawValue
        debugPrint("[Category] fetchCategory(geocode fallback) '\(name)' → \(raw ?? "nil")")
        return raw
    }
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
