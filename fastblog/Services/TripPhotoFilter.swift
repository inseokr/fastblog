//
//  TripPhotoFilter.swift
//  Capper
//
//  Single source of truth for whether a photo should appear in any Trip result.
//  No photos within minMiles of home, and no photos without valid location, are included.

import CoreLocation
import Foundation

/// Meters per mile (exact). Use for all distance-to-miles conversion.
private let metersPerMile: Double = 1609.344

/// Boundary: we EXCLUDE assets strictly closer than minMiles. Exactly minMiles is INCLUDED.
/// So: distance < 50 → excluded; distance >= 50 → included.

enum TripPhotoFilter {
    /// Returns true only if the asset should appear in Trip results.
    /// - Parameters:
    ///   - assetLocation: Photo location; nil → excluded (no valid metadata).
    ///   - home: Neighborhood center from onboarding (single source of truth at runtime).
    ///   - minMiles: Minimum distance from home in miles; default 50. Strict: distance < minMiles → excluded.
    /// - Returns: false if assetLocation is nil; false if distance(home, assetLocation) < minMiles; true otherwise.
    static func shouldIncludeInTrips(
        assetLocation: CLLocation?,
        home: CLLocation,
        minMiles: Double = 50
    ) -> Bool {
        guard let location = assetLocation else { return false }
        let distanceMeters = home.distance(from: location)
        let distanceMiles = distanceMeters / metersPerMile
        return distanceMiles >= minMiles
    }

    /// Distance in miles between two locations (for logging). Uses same metersPerMile.
    static func distanceMiles(from: CLLocation, to: CLLocation) -> Double {
        from.distance(from: to) / metersPerMile
    }

    /// Sanity check: valid latitude/longitude (e.g. catch swapped coords). lat in [-90,90], lon in [-180,180].
    static func isValidCoordinate(lat: Double, lon: Double) -> Bool {
        lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
    }
}
