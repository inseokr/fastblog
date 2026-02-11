//
//  ScanConfig.swift
//  Capper
//

import Foundation

/// Central config for trip scan: window, local exclusion, and segmentation thresholds.
enum ScanConfig {
    /// Default scan window in days (e.g. last 60 days = ~2 months). Reduced to lower geocoding rate limit usage.
    static let windowDays = 60

    /// Photos within this many miles of neighborhood center are excluded from trips (non-trip / local).
    static let localExclusionMiles = 50.0

    /// Hours of gap to start a new temporal segment.
    static let gapHoursNewSegment = 12

    /// Hours of gap below which segments can be merged.
    static let mergeGapHours = 18

    /// Distance in km beyond which we split by geography.
    static let geoSplitDistanceKm = 150.0

    /// Place clustering radius in meters (configurable). Reduced to 150m for tighter clusters (Accuracy-First PRD).
    static let placeClusterMeters = 150.0

    /// Meters per mile for distance checks.
    static let metersPerMile: Double = 1609.34

    // MARK: - Day → Trip clustering

    /// Radius in miles: two days within this distance (and passing other rules) merge into same trip (NEIGHBORHOOD rule).
    static let neighborhoodRadiusMiles: Double = 50.0

    /// Country fallback: max distance in miles between day centroids to merge same-country days (gap ≤ maxGapDaysToBridge).
    static let countryFallbackMaxMiles: Double = 100.0

    /// Max calendar-day gap allowed to bridge: merge days into same trip if gap ≤ this (and other rules pass).
    static let maxGapDaysToBridge: Int = 2

    /// Multi-city day: if a day's farthest city-to-city distance exceeds this (miles), do not merge that day into current trip via country fallback.
    static let multiCityDayMaxMiles: Double = 100.0
    
    /// Max hours after midnight (e.g. 2 AM) where photos can be grouped with the previous day (if gap <= 2h).
    static let midnightBridgeHours: Int = 2
    
    /// Exclusion rule: if a day is > 100 miles from the *trip centroid*, it must start a new trip.
    static let tripExclusionRadiusMiles: Double = 100.0
}
