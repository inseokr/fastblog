//
//  DayToTripGrouper.swift
//  Capper
//
//  Groups days into trips by calendar-day gap only. Deterministic: same input → same trips.
//

import CoreLocation
import Foundation

/// Why a day merged or started a new trip (for debug logging).
enum TripMergeReason: String {
    case gapPass = "gap_pass"
    case gapTooLarge = "gap_too_large"
    case firstDay = "first_day"
}

/// Result of grouping: trips as arrays of DayCluster, and optional per-decision debug reasons.
struct DayToTripGroupingResult {
    let trips: [[DayCluster]]
    /// [tripIndex][dayIndexInTrip] → reason for merging that day into the trip (or splitting).
    let mergeReasons: [[TripMergeReason]]
}

/// Groups days into trips. Process days in chronological order; extend current trip if the gap rule passes.
enum DayToTripGrouper {
    /// Groups `days` (must be sorted by dayDate ascending) into trips. Merge when gap ≤ maxGapDaysToBridge. Applies post-pass smoothing for 1-day trips.
    /// - Parameters:
    ///   - days: All day clusters sorted by dayDate.
    ///   - maxGapDaysToBridge: Max calendar-day gap to allow merge.
    ///   - debugLogging: When true, mergeReasons are populated and reasons can be logged.
    static func groupDaysIntoTrips(
        days: [DayCluster],
        maxGapDaysToBridge: Int = ScanConfig.maxGapDaysToBridge,
        debugLogging: Bool = false
    ) -> DayToTripGroupingResult {
        guard !days.isEmpty else { return DayToTripGroupingResult(trips: [], mergeReasons: []) }

        var trips: [[DayCluster]] = []
        var reasons: [[TripMergeReason]] = []

        // Greedy: process in chronological order
        let sortedDays = days.sorted { $0.dayDate < $1.dayDate }

        for (idx, day) in sortedDays.enumerated() {
            if idx == 0 {
                trips.append([day])
                reasons.append([.firstDay])
                continue
            }

            let lastTrip = trips.count - 1
            let currentTripDays = trips[lastTrip]
            let tripLastDay = currentTripDays.last!
            let gap = tripLastDay.dayGap(to: day)

            let (shouldMerge, reason) = shouldMergeDayIntoTrip(gap: gap, maxGapDaysToBridge: maxGapDaysToBridge)

            if shouldMerge {
                trips[lastTrip].append(day)
                if debugLogging { reasons[lastTrip].append(reason) }
            } else {
                trips.append([day])
                if debugLogging { reasons.append([reason]) }
            }
        }

        if !debugLogging {
            reasons = trips.map { _ in [] }
        }

        // Post-pass: merge 1-day trips when adjacent trip gaps also satisfy the bridge rule.
        let smoothed = applyTripMergeSmoothing(trips: trips, maxGapDaysToBridge: maxGapDaysToBridge)

        return DayToTripGroupingResult(trips: smoothed, mergeReasons: reasons)
    }

    /// Merge decision: should we add the candidate day to the current trip?
    /// - Returns: (merge: Bool, reason: TripMergeReason)
    static func shouldMergeDayIntoTrip(
        gap: Int,
        maxGapDaysToBridge: Int
    ) -> (Bool, TripMergeReason) {
        if gap > maxGapDaysToBridge {
            return (false, .gapTooLarge)
        }
        return (true, .gapPass)
    }

    /// If a trip is only 1 day and is adjacent to another trip within the bridge gap, merge it.
    static func applyTripMergeSmoothing(
        trips: [[DayCluster]],
        maxGapDaysToBridge: Int
    ) -> [[DayCluster]] {
        guard trips.count >= 2 else { return trips }

        var result = trips
        var changed = true
        while changed {
            changed = false
            for i in 0..<result.count {
                guard result[i].count == 1 else { continue }
                let single = result[i][0]
                let prevTrip: [DayCluster]? = i > 0 ? result[i - 1] : nil
                let nextTrip: [DayCluster]? = i < result.count - 1 ? result[i + 1] : nil

                let prevLast = prevTrip?.last
                let nextFirst = nextTrip?.first

                let canMergePrev = prevLast.map { p in p.dayGap(to: single) <= maxGapDaysToBridge } ?? false
                let canMergeNext = nextFirst.map { n in single.dayGap(to: n) <= maxGapDaysToBridge } ?? false

                if canMergePrev, let p = prevTrip {
                    result[i - 1] = p + [single]
                    result.remove(at: i)
                    changed = true
                    break
                } else if canMergeNext, let n = nextTrip {
                    result[i] = [single] + n
                    result.remove(at: i + 1)
                    changed = true
                    break
                }
            }
        }
        return result
    }
}
