//
//  NeighborhoodStore.swift
//  Capper
//

import CoreLocation
import Foundation

/// Single source of truth for the user's neighborhood (map-centered coordinate from onboarding).
/// Used for "non trip" exclusion: photos within localExclusionMiles of the center are excluded from trip building.
enum NeighborhoodStore {
    private static let latKey = "blogify.neighborhoodLat"
    private static let lonKey = "blogify.neighborhoodLon"
    private static let radiusMilesKey = "blogify.neighborhoodRadiusMiles"
    private static let displayNameKey = "blogify.neighborhoodDisplayName"

    /// Returns the neighborhood center as a CLLocation, or nil if not set (exclusion disabled).
    static func getNeighborhoodCenter() -> CLLocation? {
        let lat = UserDefaults.standard.double(forKey: latKey)
        let lon = UserDefaults.standard.double(forKey: lonKey)
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    /// Saves the neighborhood center (e.g. from onboarding). Pass nil to clear. Next scan uses a new cache key so results are fresh.
    static func saveCenter(_ coordinate: CLLocationCoordinate2D?) {
        if let c = coordinate {
            UserDefaults.standard.set(c.latitude, forKey: latKey)
            UserDefaults.standard.set(c.longitude, forKey: lonKey)
        } else {
            UserDefaults.standard.removeObject(forKey: latKey)
            UserDefaults.standard.removeObject(forKey: lonKey)
            UserDefaults.standard.removeObject(forKey: displayNameKey)
        }
        PhotoLibraryTripService.invalidateScanCache()
    }

    /// Display name for the selected neighborhood (e.g. city or area name). Nil if not set or cleared.
    static func getDisplayName() -> String? {
        UserDefaults.standard.string(forKey: displayNameKey)
    }

    /// Saves the neighborhood display name. Call when saving the center so Settings can show it.
    static func saveDisplayName(_ name: String?) {
        if let name = name, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: displayNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: displayNameKey)
        }
    }

    /// Radius in miles within which photos are considered "local" and excluded from trips. Default 50.
    static var localExclusionMiles: Double {
        get {
            let v = UserDefaults.standard.double(forKey: radiusMilesKey)
            return v > 0 ? v : 50
        }
        set { UserDefaults.standard.set(newValue, forKey: radiusMilesKey) }
    }

    /// Rounded coordinate for cache keys (4 decimal places ~11 m precision).
    static func neighborhoodCenterCacheKey() -> String {
        guard let loc = getNeighborhoodCenter() else { return "none" }
        let lat = (loc.coordinate.latitude * 10000).rounded() / 10000
        let lon = (loc.coordinate.longitude * 10000).rounded() / 10000
        return "\(lat),\(lon)"
    }
}
