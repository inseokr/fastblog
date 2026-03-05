//
//  DayToTripGrouper.swift
//  Capper
//
//  Groups Days into Trips by same country and calendar-day gap (no spatial distance). Deterministic: same input → same trips.
//

import CoreLocation
import Foundation

/// Why a day merged or started a new trip (for debug logging).
enum TripMergeReason: String {
    case sameCountryPass = "same_country_pass"
    case gapTooLarge = "gap_too_large"
    case differentCountry = "different_country"
    case firstDay = "first_day"
}

/// Result of grouping: trips as arrays of DayCluster, and optional per-decision debug reasons.
struct DayToTripGroupingResult {
    let trips: [[DayCluster]]
    /// [tripIndex][dayIndexInTrip] → reason for merging that day into the trip (or splitting).
    let mergeReasons: [[TripMergeReason]]
}

/// Groups days into trips. Process days in chronological order; extend current trip if merge conditions pass.
enum DayToTripGrouper {
    /// Groups `days` (must be sorted by dayDate ascending) into trips. Merge only by same country and gap ≤ maxGapDaysToBridge (no spatial distance). Applies post-pass smoothing for 1-day trips.
    /// - Parameters:
    ///   - days: All day clusters sorted by dayDate.
    ///   - maxGapDaysToBridge: Max calendar-day gap to allow merge (same country only).
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
            let tripCountryCode = tripLastDay.countryCode
            let gap = tripLastDay.dayGap(to: day)
            let currentTripDayCount = currentTripDays.count

            let (shouldMerge, reason) = shouldMergeDayIntoTrip(
                candidate: day,
                tripCountryCode: tripCountryCode,
                gap: gap,
                currentTripDayCount: currentTripDayCount,
                maxGapDaysToBridge: maxGapDaysToBridge,
                minTripDaysForCountrySeparation: ScanConfig.minTripDaysForCountrySeparation
            )

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

        // Post-pass: merge 1-day trips sandwiched between two trips in same country, gap ≤ maxGapDaysToBridge
        let smoothed = applyTripMergeSmoothing(trips: trips, maxGapDaysToBridge: maxGapDaysToBridge)

        return DayToTripGroupingResult(trips: smoothed, mergeReasons: reasons)
    }

    /// Merge decision: should we add candidate day to the current trip? Country-based separation applies only when current trip has more than minTripDaysForCountrySeparation days.
    /// - Returns: (merge: Bool, reason: TripMergeReason)
    static func shouldMergeDayIntoTrip(
        candidate: DayCluster,
        tripCountryCode: String,
        gap: Int,
        currentTripDayCount: Int,
        maxGapDaysToBridge: Int,
        minTripDaysForCountrySeparation: Int = ScanConfig.minTripDaysForCountrySeparation
    ) -> (Bool, TripMergeReason) {
        if gap > maxGapDaysToBridge {
            return (false, .gapTooLarge)
        }
        // Only split by country when the current trip already has more than minTripDaysForCountrySeparation days.
        if currentTripDayCount > minTripDaysForCountrySeparation && candidate.countryCode != tripCountryCode {
            return (false, .differentCountry)
        }
        return (true, .sameCountryPass)
    }

    /// If a trip is only 1 day and is sandwiched between two trips in the same country with gap ≤ maxGapDaysToBridge, merge into previous trip.
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

                let canMergePrev = prevLast.map { p in p.countryCode == single.countryCode && p.dayGap(to: single) <= maxGapDaysToBridge } ?? false
                let canMergeNext = nextFirst.map { n in n.countryCode == single.countryCode && single.dayGap(to: n) <= maxGapDaysToBridge } ?? false

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
