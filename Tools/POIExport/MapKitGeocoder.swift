import Foundation
import MapKit
import CoreLocation

struct MapKitGeocoder {
    static let searchRadiusMeters: Double = 75

    static func geocode(records: inout [PhotoRecord], log: inout [String]) async {
        for i in records.indices {
            guard let lat = records[i].latitude, let lon = records[i].longitude else {
                continue
            }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: searchRadiusMeters)
            do {
                let response = try await MKLocalSearch(request: request).start()
                if let match = closestQualifyingItem(in: response.mapItems, to: coordinate) {
                    records[i].mapkitPlaceName = match.name
                    records[i].mapkitCategory = category(for: match)
                    records[i].mapkitCity = match.placemark.locality ?? match.placemark.administrativeArea
                    records[i].mapkitCountry = match.placemark.country
                }
            } catch {
                log.append("[WARN-MK] \(records[i].filename) — MapKit search failed: \(error.localizedDescription)")
            }
            if i < records.count - 1 {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Private

    private static func closestQualifyingItem(
        in items: [MKMapItem],
        to coordinate: CLLocationCoordinate2D
    ) -> MKMapItem? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let qualifying = items.compactMap { item -> (MKMapItem, CLLocationDistance)? in
            guard let name = item.name, !name.isEmpty else { return nil }
            let itemLocation = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            let distance = origin.distance(from: itemLocation)
            guard distance <= searchRadiusMeters else { return nil }
            return (item, distance)
        }
        return qualifying.min(by: { $0.1 < $1.1 })?.0
    }

    // MKPointOfInterestCategory.rawValue returns e.g. "MKPOICategoryRestaurant";
    // strip the prefix for a readable dataset column.
    private static func category(for item: MKMapItem) -> String? {
        guard let category = item.pointOfInterestCategory else { return nil }
        let raw = category.rawValue
        let prefix = "MKPOICategory"
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }
}
