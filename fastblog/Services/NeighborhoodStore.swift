//
//  NeighborhoodStore.swift
//  Capper
//

import CoreLocation
import Foundation
import Photos

/// Single source of truth for the user's neighborhood (map-centered coordinate from onboarding).
/// Used for "non trip" exclusion: photos within localExclusionMiles of the center are excluded from trip building.
enum NeighborhoodStore {
    private static let latKey = "blogify.neighborhoodLat"
    private static let lonKey = "blogify.neighborhoodLon"
    private static let radiusMilesKey = "blogify.neighborhoodRadiusMiles"
    private static let tripExclusionRadiusOverrideKey = "blogify.tripExclusionRadiusMiles"
    private static let displayNameKey = "blogify.neighborhoodDisplayName"
    private static let recentSearchesKey = "blogify.neighborhood.recentSearches"

    /// Returns the list of recent search queries.
    static var recentSearches: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: recentSearchesKey)
        }
    }

    /// Adds a search query to the recent searches list, keeping only the unique last 5.
    static func addRecentSearch(_ query: String) {
        var searches = recentSearches
        if let index = searches.firstIndex(of: query) {
            searches.remove(at: index)
        }
        searches.insert(query, at: 0)
        if searches.count > 5 {
            searches = Array(searches.prefix(5))
        }
        recentSearches = searches
    }

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
    /// Used as the fallback for `tripExclusionRadiusMiles` until the user adjusts trip settings.
    static var localExclusionMiles: Double {
        get {
            let v = UserDefaults.standard.double(forKey: radiusMilesKey)
            return v > 0 ? v : 25
        }
        set { UserDefaults.standard.set(newValue, forKey: radiusMilesKey) }
    }

    /// Miles from home to exclude from trip detection. Clamped to 5...200.
    /// If the user has never set this override, uses `localExclusionMiles` (neighborhood radius / 50 mi default).
    /// With **limited** photo library access, the override is ignored; `localExclusionMiles` always applies.
    static var tripExclusionRadiusMiles: Double {
        get {
            if UserDefaults.standard.object(forKey: tripExclusionRadiusOverrideKey) != nil {
                let v = UserDefaults.standard.double(forKey: tripExclusionRadiusOverrideKey)
                return min(max(v, 5), 200)
            }
            return localExclusionMiles
        }
        set {
            let clamped = min(max(newValue, 5), 200)
            UserDefaults.standard.set(clamped, forKey: tripExclusionRadiusOverrideKey)
            PhotoLibraryTripService.invalidateScanCache()
        }
    }

    /// Minimum miles from home for trip photo inclusion. Uses `tripExclusionRadiusMiles` for full library access;
    /// for **limited** access, always `localExclusionMiles` (custom distance is not used).
    static var effectiveTripMinMilesFromHome: Double {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            return localExclusionMiles
        }
        return tripExclusionRadiusMiles
    }

    /// Rounded coordinate for cache keys (4 decimal places ~11 m precision).
    static func neighborhoodCenterCacheKey() -> String {
        guard let loc = getNeighborhoodCenter() else { return "none" }
        let lat = (loc.coordinate.latitude * 10000).rounded() / 10000
        let lon = (loc.coordinate.longitude * 10000).rounded() / 10000
        return "\(lat),\(lon)"
    }
}
