//
//  DayCluster.swift
//  Capper
//
//  A single calendar day of photos with derived geo for Day→Trip clustering.
//

import CoreLocation
import Foundation
import Photos

/// One day of photos with centroid and place metadata for clustering.
struct DayCluster {
    /// Start of this calendar day (local timezone when available).
    var dayDate: Date
    /// Centroid of photo coordinates (weighted by count; or median).
    var dayCentroid: CLLocationCoordinate2D
    /// ISO country code from geocoding (e.g. "US").
    var countryCode: String
    var countryName: String
    /// Primary city name (e.g. locality or subAdministrativeArea).
    var cityName: String
    /// Representative city centroids when day has multiple cities (for max-distance check).
    var cityCentroids: [CLLocationCoordinate2D]
    /// Max distance in miles between any two city centroids (or photo clusters) in this day.
    var maxDistanceWithinDayMiles: Double
    /// Assets for this day (kept so we can build TripDraft after grouping).
    var assets: [PHAsset]

    /// Calendar-day gap from this day to the other's date. 1 = next day, 2 = one day in between, etc. Used for bridge rule (gap ≤ maxGapDaysToBridge).
    func dayGap(to other: DayCluster) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: dayDate)
        let end = cal.startOfDay(for: other.dayDate)
        let comps = cal.dateComponents([.day], from: start, to: end)
        return max(0, comps.day ?? 0)
    }
}
