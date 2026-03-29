//
//  PlaceLibraryPhotoImport.swift
//  fastblog
//
//  Resolves timestamp, GPS, and timezone when importing Photos library assets into a place stop,
//  using the stop (and day) as fallbacks when asset metadata is missing.
//

import CoreLocation
import Foundation
import Photos

enum PlaceLibraryPhotoImport {
    /// Representative coordinate for the place (for assets missing GPS).
    static func defaultCoordinate(for stop: PlaceStop) -> PhotoCoordinate? {
        stop.representativeLocation ?? stop.photos.compactMap(\.location).first
    }

    /// Capture instant when `PHAsset.creationDate` is missing: parse `visitedTimeDigitized` in the place timezone, else noon on the trip day in that zone.
    static func resolvedTimestamp(asset: PHAsset, stop: PlaceStop, day: RecapBlogDay, placeTimeZone: TimeZone) -> Date {
        if let d = asset.creationDate { return d }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = placeTimeZone
        if let vtd = stop.visitedTimeDigitized, let d = parser.date(from: vtd) {
            return d
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = placeTimeZone
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day.date) ?? day.date
    }

    static func resolvedCoordinate(asset: PHAsset, stop: PlaceStop) -> PhotoCoordinate? {
        if let loc = asset.location {
            return PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        }
        return defaultCoordinate(for: stop)
    }

    /// Timezone for digitized-time strings when EXIF / asset GPS are unavailable: reverse-geocode the place coordinate, else device timezone.
    @MainActor
    static func placeTimeZone(for stop: PlaceStop) async -> TimeZone {
        if let coord = defaultCoordinate(for: stop) {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let tz = await GeocodingService.shared.timeZone(for: loc) {
                return tz
            }
        }
        return .current
    }
}
