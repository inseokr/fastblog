//
//  CitySearchHelper.swift
//  Capper
//

import Combine
import MapKit
import SwiftUI

/// Wraps MKLocalSearchCompleter for city/location suggestions with debouncing.
final class CitySearchHelper: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    var onRegionSelected: ((MKCoordinateRegion, String?) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()
    private let debounceInterval: TimeInterval

    init(debounceInterval: TimeInterval = OnboardingConstants.Search.debounceInterval) {
        self.debounceInterval = debounceInterval
        super.init()
        completer.delegate = self
        completer.resultTypes = .address

        $query
            .debounce(for: .seconds(debounceInterval), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                self?.updateCompleter(query: newQuery)
            }
            .store(in: &cancellables)
    }

    private func updateCompleter(query: String) {
        if query.isEmpty {
            suggestions = []
            return
        }
        completer.queryFragment = query
    }

    func selectSuggestion(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        isSearching = true
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.isSearching = false
                guard let item = response?.mapItems.first else { return }
                let center = item.placemark.coordinate
                let name = item.name
                let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                let region = MKCoordinateRegion(center: center, span: span)
                self?.onRegionSelected?(region, name)
            }
        }
    }

    func clearQuery() {
        query = ""
        suggestions = []
    }
}

extension CitySearchHelper: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
