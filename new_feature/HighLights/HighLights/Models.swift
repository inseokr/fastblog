import Foundation
import CoreLocation
import UIKit

/// One photo = EXIF metadata + analysis scores
struct PhotoItem: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D
    let hasGPS: Bool               // whether EXIF actually contained GPS
    var placeName: String = ""     // injected after clustering + reverse geocoding

    // Filled in by the analysis pipeline
    var sharpness: Double = 0      // Laplacian variance
    var aestheticScore: Double = 0 // Vision Aesthetics (-1...1) or fallback
    var hasSaliency: Bool = true   // whether a salient subject exists

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// DBSCAN result: one visited place
struct PlaceCluster: Identifiable {
    let id = UUID()
    var name: String
    var photos: [PhotoItem]

    var center: CLLocationCoordinate2D {
        let lat = photos.map(\.coordinate.latitude).reduce(0, +) / Double(photos.count)
        let lon = photos.map(\.coordinate.longitude).reduce(0, +) / Double(photos.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    var arrival: Date { photos.map(\.timestamp).min() ?? .now }
    var departure: Date { photos.map(\.timestamp).max() ?? .now }
    var dwellMinutes: Int { max(1, Int(departure.timeIntervalSince(arrival) / 60)) }
}

/// Per-stage result of the 5-stage curation funnel
struct FunnelStage: Identifiable {
    let id = UUID()
    let name: String
    let criterion: String
    let survivors: [PhotoItem]
}

/// One line of the data-journalism stats
struct TripStat: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let note: String
}

/// One hidden-moment insight
struct HiddenMoment: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let source: String
}
