import Foundation
import CoreLocation

/// Feature ④: travel data journalism — stats from EXIF/GPS.
/// HealthKit has no data in the simulator, so we use GPS-trajectory distance estimation as fallback
/// (Prof. Kim 📌: fall back to estimation without consent — that fallback is the default here).
enum StatsEngine {

    static func compute(photos: [PhotoItem], clusters: [PlaceCluster],
                        curated: Int) -> [TripStat] {
        var stats: [TripStat] = []
        let calendar = Calendar.current

        // Places visited (GPS clustering)
        let uniquePlaces = Set(clusters.map(\.name))
        stats.append(TripStat(icon: "mappin.and.ellipse", label: "Places visited",
                              value: "\(uniquePlaces.count)",
                              note: uniquePlaces.sorted().joined(separator: " · ")))

        // Shots → selected ratio (5-stage filter)
        let ratio = photos.isEmpty ? 0 : Double(curated) / Double(photos.count) * 100
        stats.append(TripStat(icon: "camera", label: "Shots → selected",
                              value: "\(photos.count) → \(curated)",
                              note: String(format: "%.1f%% — 5-stage AI filter", ratio)))

        // Distance: sum of GPS trajectory (HealthKit fallback)
        let gpsPhotos = photos.filter(\.hasGPS)
        let days = max(1, tripDays(photos))
        if gpsPhotos.count > 1 {
            let km = trajectoryKm(gpsPhotos)
            stats.append(TripStat(icon: "figure.walk", label: "Distance (GPS estimate)",
                                  value: String(format: "%.1f km", km),
                                  note: String(format: "%.1f km/day avg · replace with HealthKit for measured", km / Double(days))))
        }

        // Longest stay
        if let longest = clusters.max(by: { $0.dwellMinutes < $1.dwellMinutes }) {
            stats.append(TripStat(icon: "clock", label: "Longest stay",
                                  value: "\(longest.name)",
                                  note: "\(longest.dwellMinutes / 60)h \(longest.dwellMinutes % 60)m"))
        }

        // Revisited place
        let names = clusters.map(\.name)
        let revisited = Set(names.filter { name in names.filter { $0 == name }.count > 1 })
        if let place = revisited.first {
            stats.append(TripStat(icon: "arrow.triangle.2.circlepath", label: "Revisited",
                                  value: "\(place) (\(names.filter { $0 == place }.count)×)",
                                  note: "When the light changes, the same place tells a different story"))
        }

        // Peak shooting hour
        let hourCounts = Dictionary(grouping: photos) { calendar.component(.hour, from: $0.timestamp) }
            .mapValues(\.count)
        if let peak = hourCounts.max(by: { $0.value < $1.value }) {
            stats.append(TripStat(icon: "chart.bar", label: "Peak shooting time",
                                  value: "\(peak.key)–\(peak.key + 2)h",
                                  note: "\(peak.value) photos · \(peak.value * 100 / max(1, photos.count))% of total"))
        }

        // Golden-hour shots (network-free sun-altitude formula — Prof. Kim ③) — GPS photos only
        if !gpsPhotos.isEmpty {
            let golden = gpsPhotos.filter { isGoldenHour(date: $0.timestamp, gps: $0.coordinate) }
            stats.append(TripStat(icon: "sunrise", label: "Golden-hour shots",
                                  value: "\(golden.count)",
                                  note: "Sun altitude -6°…+6° · offline formula"))
        }
        return stats
    }

    /// Sun altitude approximation (J2000) — the formula from Prof. Kim's doc, fully offline, ±minutes
    static func isGoldenHour(date: Date, gps: CLLocationCoordinate2D) -> Bool {
        let lat = gps.latitude * .pi / 180
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let decl = 23.45 * sin((360.0 / 365.0 * Double(day - 81)) * .pi / 180) * .pi / 180
        let h = Double(Calendar.current.component(.hour, from: date))
              + Double(Calendar.current.component(.minute, from: date)) / 60.0
        // Demo simplification: use local clock time with no timezone correction.
        // Production should apply longitude-based solar-time correction.
        let ha = (h - 12.0) * 15.0 * .pi / 180
        let alt = asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)) * 180 / .pi
        return alt >= -6.0 && alt <= 6.0
    }

    private static func trajectoryKm(_ photos: [PhotoItem]) -> Double {
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<sorted.count {
            let a = CLLocation(latitude: sorted[i - 1].coordinate.latitude,
                               longitude: sorted[i - 1].coordinate.longitude)
            let b = CLLocation(latitude: sorted[i].coordinate.latitude,
                               longitude: sorted[i].coordinate.longitude)
            let d = a.distance(from: b)
            if d < 30_000 { total += d }   // cut ±50m error / abnormal jumps (mirrors map ⑥ downsampling)
        }
        return total / 1000
    }

    private static func tripDays(_ photos: [PhotoItem]) -> Int {
        let calendar = Calendar.current
        let days = Set(photos.map { calendar.startOfDay(for: $0.timestamp) })
        return days.count
    }
}
