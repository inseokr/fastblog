//
//  LocalExclusion.swift
//  Capper
//

import CoreLocation
import Foundation

/// Legacy exclusion helper. For Trip filtering the app uses TripPhotoFilter.shouldIncludeInTrips (single source of truth).
/// This enum remains for tests and any non-trip use; trip pipeline uses TripPhotoFilter only.
enum LocalExclusion {
    static let metersPerMile: Double = 1609.34

    /// Returns true if the asset should be excluded (not used in trips). Photos without location are not excluded (return false).
    /// - Parameters:
    ///   - assetLocation: The photo's location; nil means do not exclude.
    ///   - neighborhoodCenter: The user's neighborhood center; nil means exclusion disabled (return false for everyone).
    ///   - radiusMiles: Radius in miles (e.g. 50).
    static func shouldExclude(
        assetLocation: CLLocation?,
        neighborhoodCenter: CLLocation?,
        radiusMiles: Double
    ) -> Bool {
        guard let center = neighborhoodCenter else { return false }
        guard let location = assetLocation else { return false }
        let radiusMeters = radiusMiles * metersPerMile
        return center.distance(from: location) <= radiusMeters
    }
}
