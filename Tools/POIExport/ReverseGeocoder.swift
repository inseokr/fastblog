import Foundation
import CoreLocation

struct ReverseGeocoder {
    static func geocode(records: inout [PhotoRecord], log: inout [String]) async {
        for i in records.indices {
            guard let lat = records[i].latitude, let lon = records[i].longitude else {
                log.append("[SKIP] \(records[i].filename) — no GPS")
                continue
            }
            let location = CLLocation(latitude: lat, longitude: lon)
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let pm = placemarks.first {
                    records[i].suggestedPlaceName = bestPlaceLabel(pm)
                    records[i].suggestedCity = pm.locality ?? pm.administrativeArea
                    records[i].suggestedCountry = pm.country
                }
            } catch {
                log.append("[WARN] \(records[i].filename) — geocoding failed: \(error.localizedDescription)")
            }
            if i < records.count - 1 {
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    // MARK: - Private

    // Mirrors GeocodingService.bestPlaceLabel logic for accuracy comparability.
    // Prefer pm.name only when it looks like a venue (non-empty, distinct from
    // locality fields, no leading digit). Falls back to subLocality then locality.
    private static func bestPlaceLabel(_ pm: CLPlacemark) -> String? {
        if let name = pm.name,
           !name.isEmpty,
           name != pm.subLocality,
           name != pm.locality,
           !(name.first?.isNumber ?? false) {
            return name
        }
        return pm.subLocality ?? pm.locality
    }
}
