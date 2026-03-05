//
//  ScanConfig.swift
//  Capper
//

import Foundation

/// Central config for trip scan: window, local exclusion, and segmentation thresholds.
enum ScanConfig {
    /// Default scan window in days (e.g. last 90 days = ~3 months). Restored to 90 days to include older trips like December.
    static let windowDays = 90

    /// Photos within this many miles of neighborhood center are excluded from trips (non-trip / local).
    static let localExclusionMiles = 50.0

    /// Hours of gap to start a new temporal segment.
    static let gapHoursNewSegment = 12

    /// Hours of gap below which segments can be merged.
    static let mergeGapHours = 18

    /// Place clustering radius in meters (configurable). Reduced to 150m for tighter clusters (Accuracy-First PRD).
    static let placeClusterMeters = 150.0

    /// Meters per mile for distance checks.
    static let metersPerMile: Double = 1609.34

    // MARK: - Day → Trip clustering

    /// Max calendar-day gap allowed to bridge: merge days into same trip if gap ≤ this and same country (when country separation applies).
    static let maxGapDaysToBridge: Int = 2
    
    /// Country-based separation applies only when the current trip has more than this many days. Trips of ≤ 3 days can merge with a day in another country (if gap allows).
    static let minTripDaysForCountrySeparation: Int = 3
    
    /// Max hours after midnight (e.g. 2 AM) where photos can be grouped with the previous day (if gap <= 2h).
    static let midnightBridgeHours: Int = 2
    
    /// Hard limit: max days per trip (1 week). Trips longer than this are split into Part 1, Part 2, etc. as separate blogs.
    static let maxTripDays: Int = 7
}
