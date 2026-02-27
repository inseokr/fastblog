//
//  PlaceSearchViewModel.swift
//  fastblog
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

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
              let mapItem = response.mapItems.first else { return nil }
        return mapItem.pointOfInterestCategory?.rawValue
    }

    /// Resolves the specific POI at the given coordinate (e.g. restaurant inside a mall) by fetching
    /// nearby points of interest and picking the one closest to the tap. Prefer this over reverse
    /// geocoding when the user taps a place on the map, so they get the venue name not the building/area.
    /// Returns (name, category) or nil if no POI found (caller can fall back to reverse geocode).
    func resolvePOIAtCoordinate(_ coordinate: CLLocationCoordinate2D) async -> (name: String, category: String?)? {
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 100)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !response.mapItems.isEmpty else { return nil }
        let withName = response.mapItems.filter { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard let closest = withName.min(by: { item1, item2 in
            let loc1 = item1.placemark.location ?? CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude)
            let loc2 = item2.placemark.location ?? CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude)
            return tapLocation.distance(from: loc1) < tapLocation.distance(from: loc2)
        }) else { return nil }
        let name = (closest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let category = closest.pointOfInterestCategory?.rawValue
        return (name, category)
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
              let mapItem = response.mapItems.first else { return nil }
        return mapItem.pointOfInterestCategory?.rawValue
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
