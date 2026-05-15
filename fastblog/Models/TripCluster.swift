// fastblog/Models/TripCluster.swift

import MapKit

/// One or more trips grouped together at a map position.
struct TripCluster: Identifiable {
    /// Derived from the representative blog's ID so SwiftUI can diff cluster annotations
    /// across recomputations without treating every cluster as new.
    var id: UUID { representative.sourceTripId }
    /// Blog whose cover photo represents the group visually.
    let representative: CreatedRecapBlog
    /// Map position for the annotation (first trip's coordinate for greedy clustering).
    let coordinate: CLLocationCoordinate2D
    /// All trips in this group (count ≥ 1).
    let blogs: [CreatedRecapBlog]

    init(representative: CreatedRecapBlog, coordinate: CLLocationCoordinate2D, blogs: [CreatedRecapBlog]) {
        self.representative = representative
        self.coordinate = coordinate
        self.blogs = blogs
    }

    var count: Int { blogs.count }
    var isCluster: Bool { blogs.count > 1 }
}

/// Groups `items` into spatial clusters based on the current map `span`.
///
/// - When `span.latitudeDelta < 0.15` (neighborhood zoom) every item becomes its own cluster,
///   so individual `TripAnnotationView` markers appear exactly as before.
/// - At larger spans the cluster radius scales with 12 % of the visible latitude range,
///   so clusters feel spatially consistent at every zoom level.
///
/// Uses greedy nearest-center assignment: O(n²) but trip counts are small in practice.
func clusterTrips(
    _ items: [(blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)],
    span: MKCoordinateSpan
) -> [TripCluster] {
    // Zoomed in enough — no clustering; return each trip as its own single-item cluster.
    guard span.latitudeDelta >= 0.15 else {
        return items.map {
            TripCluster(representative: $0.blog, coordinate: $0.coordinate, blogs: [$0.blog])
        }
    }

    // Cluster radius in degrees latitude. Minimum 0.05° so nothing clusters at city level unexpectedly.
    let radiusDeg = max(0.05, span.latitudeDelta * 0.12)

    // Each entry: seed coordinate for proximity matching, accumulated (blog, coordinate) pairs.
    var centers: [CLLocationCoordinate2D] = []
    var groups: [[(blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)]] = []

    for item in items {
        let coord = item.coordinate
        // Correct longitude tolerance for latitude distortion.
        let lonFactor = max(0.01, cos(coord.latitude * .pi / 180))

        if let idx = centers.indices.first(where: { i in
            abs(centers[i].latitude - coord.latitude) < radiusDeg &&
            abs(centers[i].longitude - coord.longitude) < radiusDeg / lonFactor
        }) {
            groups[idx].append(item)
        } else {
            centers.append(coord)
            groups.append([item])
        }
    }

    return groups.compactMap { group in
        guard let first = group.first else {
            assertionFailure("TripCluster invariant violated: cluster group is empty")
            return nil
        }
        // Use the geographic centroid so the pin sits in the middle of the cluster.
        let centroid = CLLocationCoordinate2D(
            latitude: group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count),
            longitude: group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
        )
        return TripCluster(representative: first.blog, coordinate: centroid, blogs: group.map(\.blog))
    }
}

// MARK: - VisitedPlaceCluster

/// One or more visited places grouped at a map position.
struct VisitedPlaceCluster: Identifiable {
    /// Derived from the representative place's id so SwiftUI can stable-diff across recomputations.
    var id: String { representative.id }
    let representative: VisitedPlaceSummary
    let coordinate: CLLocationCoordinate2D
    let places: [VisitedPlaceSummary]
    var count: Int { places.count }
    var isCluster: Bool { places.count > 1 }

    init(representative: VisitedPlaceSummary, coordinate: CLLocationCoordinate2D, places: [VisitedPlaceSummary]) {
        self.representative = representative
        self.coordinate = coordinate
        self.places = places
    }
}

/// Groups visited-place `items` into spatial clusters based on the current map `span`.
/// Same greedy nearest-center algorithm as `clusterTrips`.
func clusterVisitedPlaces(
    _ items: [(place: VisitedPlaceSummary, coordinate: CLLocationCoordinate2D)],
    span: MKCoordinateSpan
) -> [VisitedPlaceCluster] {
    guard span.latitudeDelta >= 0.15 else {
        return items.map {
            VisitedPlaceCluster(representative: $0.place, coordinate: $0.coordinate, places: [$0.place])
        }
    }

    let radiusDeg = max(0.05, span.latitudeDelta * 0.12)
    var centers: [CLLocationCoordinate2D] = []
    var groups: [[(place: VisitedPlaceSummary, coordinate: CLLocationCoordinate2D)]] = []

    for item in items {
        let coord = item.coordinate
        let lonFactor = max(0.01, cos(coord.latitude * .pi / 180))
        if let idx = centers.indices.first(where: { i in
            abs(centers[i].latitude - coord.latitude) < radiusDeg &&
            abs(centers[i].longitude - coord.longitude) < radiusDeg / lonFactor
        }) {
            groups[idx].append(item)
        } else {
            centers.append(coord)
            groups.append([item])
        }
    }

    return groups.compactMap { group in
        guard let first = group.first else {
            assertionFailure("VisitedPlaceCluster invariant violated: group is empty")
            return nil
        }
        // Use the geographic centroid so the pin sits in the middle of the cluster.
        let centroid = CLLocationCoordinate2D(
            latitude: group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count),
            longitude: group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
        )
        return VisitedPlaceCluster(representative: first.place, coordinate: centroid, places: group.map(\.place))
    }
}
