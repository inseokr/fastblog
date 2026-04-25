//
//  PlaceSuggestion.swift
//  fastblog
//

import CoreLocation
import MapKit

/// Which backend produced a suggestion — determines how coordinate and category are resolved when the user picks it.
enum PlaceSuggestionSource {
    /// Apple Maps autocomplete. Coordinate and category require a round-trip MKLocalSearch to resolve.
    case mapKit(MKLocalSearchCompletion)
    /// Kakao Local API result. Coordinate and category are already available from the initial search response.
    case kakao(coordinate: CLLocationCoordinate2D?, categoryRaw: String?)
}

/// A unified place suggestion displayed in the autocomplete list, regardless of the underlying data source.
struct PlaceSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let source: PlaceSuggestionSource
}
