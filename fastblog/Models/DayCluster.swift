//
//  DayCluster.swift
//  Capper
//
//  A single calendar day of photos with geometry for day-to-trip clustering.
//

import CoreLocation
import Foundation
import Photos

/// One day of photos with centroid and lightweight metadata for clustering.
struct DayCluster {
    /// Start of this calendar day (local timezone when available).
    var dayDate: Date
    /// Centroid of photo coordinates (weighted by count; or median).
    var dayCentroid: CLLocationCoordinate2D
    /// Optional trip-level geocoded country code can be copied here when needed.
    var countryCode: String
    var countryName: String
    /// Optional trip-level city name.
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
