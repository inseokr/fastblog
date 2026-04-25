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
    /// Distance from the user's tap to this POI's placemark (meters).
    let distanceMeters: Double
}

/// Result of resolving a bare map tap (no `MKMapFeatureAnnotation`) to a place.
enum MapTapPOIResult {
    case none
    case single(name: String, category: String?, coordinate: CLLocationCoordinate2D)
    case ambiguous(candidates: [MapTapPOICandidate])
}

/// Which backend serves autocomplete suggestions and coordinate resolution.
enum PlaceSearchProvider {
    case mapKit
    case kakao
}

/// Wraps MKLocalSearchCompleter (MapKit) and Kakao Local API for place suggestions,
/// automatically routing to the right provider based on the place's country.
final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [PlaceSuggestion] = []
    @Published var isSearching = false

    var onPlaceSelected: ((String) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()
    private let debounceInterval: TimeInterval = 0.3

    private var activeProvider: PlaceSearchProvider = .mapKit
    private var kakaoSearchTask: Task<Void, Never>?

    /// Stored for Kakao distance-biased search.
    private var biasCoordinate: CLLocationCoordinate2D?

    /// If set, MapKit search results are biased towards this region.
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
                self?.updateSearch(query: newQuery)
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider selection

    /// Call this once the place's country is known. Switches to Kakao for KR when the API key is configured.
    func setProvider(isoCountryCode: String) {
        if isoCountryCode == "KR", KakaoLocalService.shared.isAvailable {
            activeProvider = .kakao
            completer.queryFragment = ""
            suggestions = []
            debugPrint("[PlaceSearch] provider → Kakao (KR)")
        } else {
            activeProvider = .mapKit
            kakaoSearchTask?.cancel()
            kakaoSearchTask = nil
            suggestions = []
            debugPrint("[PlaceSearch] provider → MapKit (\(isoCountryCode))")
        }
    }

    // MARK: - Bias location

    func setBiasLocation(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        biasCoordinate = coordinate
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        self.biasRegion = region
    }

    // MARK: - Search routing

    private func updateSearch(query: String) {
        switch activeProvider {
        case .mapKit:
            if query.isEmpty { suggestions = []; return }
            completer.queryFragment = query
        case .kakao:
            kakaoSearchTask?.cancel()
            if query.isEmpty { suggestions = []; return }
            let coord = biasCoordinate
            let q = query
            kakaoSearchTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                let places = await KakaoLocalService.shared.searchPlaces(query: q, near: coord)
                guard !Task.isCancelled else { return }
                self.suggestions = places.compactMap { place in
                    guard let coord = place.coordinate else { return nil }
                    return PlaceSuggestion(
                        id: place.id,
                        title: place.place_name,
                        subtitle: place.displaySubtitle,
                        source: .kakao(coordinate: coord, categoryRaw: place.poiCategoryRaw)
                    )
                }
            }
        }
    }

    func clearQuery() {
        query = ""
        suggestions = []
        kakaoSearchTask?.cancel()
        kakaoSearchTask = nil
    }

    // MARK: - Suggestion resolution

    /// Resolves a picked suggestion to its coordinate and POI category.
    /// For Kakao suggestions this returns immediately; for MapKit it does a network round-trip.
    func resolveDetails(for suggestion: PlaceSuggestion) async -> (coordinate: CLLocationCoordinate2D?, categoryRaw: String?) {
        switch suggestion.source {
        case .mapKit(let completion):
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            guard let response = try? await search.start(),
                  let mapItem = response.mapItems.first else {
                debugPrint("[PlaceSearch] resolveDetails(mapKit) '\(suggestion.title)' → no result")
                return (nil, nil)
            }
            let cat = mapItem.pointOfInterestCategory?.rawValue
            debugPrint("[PlaceSearch] resolveDetails(mapKit) '\(suggestion.title)' → category=\(cat ?? "nil")")
            return (mapItem.placemark.coordinate, cat)
        case .kakao(let coordinate, let categoryRaw):
            debugPrint("[PlaceSearch] resolveDetails(kakao) '\(suggestion.title)' → category=\(categoryRaw ?? "nil")")
            return (coordinate, categoryRaw)
        }
    }

    // MARK: - Coordinate → place name

    /// Returns the best human-readable place name for a coordinate.
    /// Uses Kakao reverse geocode in KR mode; falls back to CLGeocoder otherwise.
    func resolveCoordinateName(at coordinate: CLLocationCoordinate2D) async -> String {
        if activeProvider == .kakao {
            if let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coordinate) {
                let name = doc.bestPlaceName
                if !name.isEmpty {
                    debugPrint("[PlaceSearch] resolveCoordinateName(kakao) → '\(name)'")
                    return name
                }
            }
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let place = await GeocodingService.shared.place(for: location, precise: true)
        let name = !place.title.isEmpty ? place.title : place.bestPlaceLabel
        debugPrint("[PlaceSearch] resolveCoordinateName(geocoder) → '\(name)'")
        return name
    }

    // MARK: - MapKit POI tap resolution

    /// Search radius for POIs around a map tap (meters). Scales with zoom.
    private static func tapSearchRadiusMeters(mapRegion: MKCoordinateRegion?) -> Double {
        if let region = mapRegion {
            let metersPerPoint = region.span.latitudeDelta * 111_000.0 / 500.0
            return max(25.0, min(80.0, metersPerPoint * 22.0))
        }
        return 80.0
    }

    /// Resolves a bare map tap to a POI using MKLocalPointsOfInterestRequest.
    /// If two or more POIs are almost equally close, returns `.ambiguous` so the UI can let the user choose.
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

    // MARK: - Category helpers (MapKit)

    /// Resolves POI category at a coordinate by searching for the place name in a small region.
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
            debugPrint("[Category] fetchCategory '\(name)' → nil")
            return nil
        }
        let raw = mapItem.pointOfInterestCategory?.rawValue
        debugPrint("[Category] fetchCategory '\(name)' → \(raw ?? "nil")")
        return raw
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard activeProvider == .mapKit else { return }
        suggestions = completer.results.map { completion in
            PlaceSuggestion(
                id: "\(completion.title)|\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle,
                source: .mapKit(completion)
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
