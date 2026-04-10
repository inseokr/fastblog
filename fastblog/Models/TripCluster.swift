// fastblog/Models/TripCluster.swift

import MapKit

/// One or more trips grouped together at a map position.
struct TripCluster: Identifiable {
    /// Stable identity; regenerated each time clusters are recomputed — intentional,
    /// because MapKit re-renders the annotation view when the cluster changes.
    let id: UUID
    /// Blog whose cover photo represents the group visually.
    let representative: CreatedRecapBlog
    /// Map position for the annotation (first trip's coordinate for greedy clustering).
    let coordinate: CLLocationCoordinate2D
    /// All trips in this group (count ≥ 1).
    let blogs: [CreatedRecapBlog]

    init(representative: CreatedRecapBlog, coordinate: CLLocationCoordinate2D, blogs: [CreatedRecapBlog]) {
        self.id = UUID()
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

    // Each entry: (cluster center, accumulated blogs)
    var centers: [CLLocationCoordinate2D] = []
    var groups: [[CreatedRecapBlog]] = []

    for item in items {
        let coord = item.coordinate
        // Correct longitude tolerance for latitude distortion.
        let lonFactor = max(0.01, cos(coord.latitude * .pi / 180))

        if let idx = centers.indices.first(where: { i in
            abs(centers[i].latitude - coord.latitude) < radiusDeg &&
            abs(centers[i].longitude - coord.longitude) < radiusDeg / lonFactor
        }) {
            groups[idx].append(item.blog)
        } else {
            centers.append(coord)
            groups.append([item.blog])
        }
    }

    return zip(centers, groups).compactMap { center, blogs in
        guard let first = blogs.first else {
            assertionFailure("TripCluster invariant violated: cluster group is empty")
            return nil
        }
        return TripCluster(representative: first, coordinate: center, blogs: blogs)
    }
}
