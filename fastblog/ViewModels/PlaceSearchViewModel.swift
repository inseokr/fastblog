//
//  PlaceSearchViewModel.swift
//  fastblog
//

import Combine
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
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
