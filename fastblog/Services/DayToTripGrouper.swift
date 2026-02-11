//
//  DayToTripGrouper.swift
//  Capper
//
//  Groups Days into Trips using NEIGHBORHOOD, country fallback, multi-city rule, and gap bridging.
//  Deterministic: same input → same trips.
//

import CoreLocation
import Foundation

/// Why a day merged or started a new trip (for debug logging).
enum TripMergeReason: String {
    case neighborhoodPass = "neighborhood_pass"
    case countryFallbackPass = "country_fallback_pass"
    case distanceTooFar = "distance_too_far"
    case multiCityFail = "multi_city_fail"
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
    /// Groups `days` (must be sorted by dayDate ascending) into trips. Applies post-pass smoothing for 1-day trips.
    /// - Parameters:
    ///   - days: All day clusters sorted by dayDate.
    ///   - neighborhoodRadiusMiles: Max distance for NEIGHBORHOOD rule.
    ///   - countryFallbackMaxMiles: Max distance for same-country fallback.
    ///   - maxGapDaysToBridge: Max calendar-day gap to allow merge.
    ///   - multiCityDayMaxMiles: If day's max city-to-city > this, don't merge via country fallback.
    ///   - tripExclusionRadiusMiles: If a day is > this distance from current trip centroid, strict split.
    ///   - debugLogging: When true, mergeReasons are populated and reasons can be logged.
    static func groupDaysIntoTrips(
        days: [DayCluster],
        neighborhoodRadiusMiles: Double = ScanConfig.neighborhoodRadiusMiles,
        countryFallbackMaxMiles: Double = ScanConfig.countryFallbackMaxMiles,
        maxGapDaysToBridge: Int = ScanConfig.maxGapDaysToBridge,
        multiCityDayMaxMiles: Double = ScanConfig.multiCityDayMaxMiles,
        tripExclusionRadiusMiles: Double = ScanConfig.tripExclusionRadiusMiles,
        debugLogging: Bool = false
    ) -> DayToTripGroupingResult {
        guard !days.isEmpty else { return DayToTripGroupingResult(trips: [], mergeReasons: []) }

        var trips: [[DayCluster]] = []
        var reasons: [[TripMergeReason]] = []
        
        // State for current trip centroid calculation (running sum)
        var currentTripLatSum: Double = 0
        var currentTripLonSum: Double = 0
        var currentTripDayCount: Int = 0

        // Greedy: process in chronological order
        let sortedDays = days.sorted { $0.dayDate < $1.dayDate }

        for (idx, day) in sortedDays.enumerated() {
            if idx == 0 {
                trips.append([day])
                reasons.append([.firstDay])
                currentTripLatSum = day.dayCentroid.latitude
                currentTripLonSum = day.dayCentroid.longitude
                currentTripDayCount = 1
                continue
            }

            let lastTrip = trips.count - 1
            let currentTripDays = trips[lastTrip]
            let tripLastDay = currentTripDays.last!
            let tripCountryCode = tripLastDay.countryCode
            let tripLastDayCentroid = tripLastDay.dayCentroid
            let gap = tripLastDay.dayGap(to: day)
            
            // Calculate current trip centroid
            let tripCentroid = CLLocationCoordinate2D(
                latitude: currentTripLatSum / Double(currentTripDayCount),
                longitude: currentTripLonSum / Double(currentTripDayCount)
            )

            let (shouldMerge, reason) = shouldMergeDayIntoTrip(
                candidate: day,
                tripLastDay: tripLastDay,
                tripCountryCode: tripCountryCode,
                tripLastDayCentroid: tripLastDayCentroid,
                tripCentroid: tripCentroid,
                gap: gap,
                neighborhoodRadiusMiles: neighborhoodRadiusMiles,
                countryFallbackMaxMiles: countryFallbackMaxMiles,
                maxGapDaysToBridge: maxGapDaysToBridge,
                multiCityDayMaxMiles: multiCityDayMaxMiles,
                tripExclusionRadiusMiles: tripExclusionRadiusMiles
            )

            if shouldMerge {
                trips[lastTrip].append(day)
                if debugLogging { reasons[lastTrip].append(reason) }
                // Update running centroid
                currentTripLatSum += day.dayCentroid.latitude
                currentTripLonSum += day.dayCentroid.longitude
                currentTripDayCount += 1
            } else {
                trips.append([day])
                if debugLogging { reasons.append([reason]) }
                // Reset running centroid for new trip
                currentTripLatSum = day.dayCentroid.latitude
                currentTripLonSum = day.dayCentroid.longitude
                currentTripDayCount = 1
            }
        }

        if !debugLogging {
            reasons = trips.map { _ in [] }
        }

        // Post-pass: merge 1-day trips sandwiched between two trips in same country, within 100 mi and 2 days
        let smoothed = applyTripMergeSmoothing(
            trips: trips,
            countryFallbackMaxMiles: countryFallbackMaxMiles,
            maxGapDaysToBridge: maxGapDaysToBridge
        )

        return DayToTripGroupingResult(trips: smoothed, mergeReasons: reasons)
    }

    /// Merge decision: should we add candidate day to the current trip?
    /// - Returns: (merge: Bool, reason: TripMergeReason)
    static func shouldMergeDayIntoTrip(
        candidate: DayCluster,
        tripLastDay: DayCluster,
        tripCountryCode: String,
        tripLastDayCentroid: CLLocationCoordinate2D,
        tripCentroid: CLLocationCoordinate2D,
        gap: Int,
        neighborhoodRadiusMiles: Double,
        countryFallbackMaxMiles: Double,
        maxGapDaysToBridge: Int,
        multiCityDayMaxMiles: Double,
        tripExclusionRadiusMiles: Double
    ) -> (Bool, TripMergeReason) {
        if gap > maxGapDaysToBridge {
            return (false, .gapTooLarge)
        }
        
        // EXCLUSION RULE: Check distance from TRIP centroid
        let distFromTripCentroid = GeoDistanceHelper.haversineMiles(tripCentroid, candidate.dayCentroid)
        if distFromTripCentroid > tripExclusionRadiusMiles {
            return (false, .distanceTooFar) // Or specific reason .tripCentroidExclusion
        }

        let distanceMiles = GeoDistanceHelper.haversineMiles(tripLastDayCentroid, candidate.dayCentroid)

        // NEIGHBORHOOD rule: within radius
        if distanceMiles <= neighborhoodRadiusMiles {
            return (true, .neighborhoodPass)
        }

        // Country fallback: same country and within 100 mi
        if candidate.countryCode != tripCountryCode {
            return (false, .differentCountry)
        }

        if distanceMiles > countryFallbackMaxMiles {
            return (false, .distanceTooFar)
        }

        // Multi-city rule: if candidate day spans cities > 100 mi apart, do not merge via fallback (start new trip)
        if candidate.maxDistanceWithinDayMiles > multiCityDayMaxMiles {
            return (false, .multiCityFail)
        }

        return (true, .countryFallbackPass)
    }

    /// If a trip is only 1 day and is sandwiched between two trips in the same country, within 100 mi and 2 days gap, merge into the neighbor that yields the smaller centroid distance.
    static func applyTripMergeSmoothing(
        trips: [[DayCluster]],
        countryFallbackMaxMiles: Double,
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

                var mergeIntoPrev: Bool? = nil
                if let p = prevLast, p.countryCode == single.countryCode {
                    let gapP = p.dayGap(to: single)
                    let distP = GeoDistanceHelper.haversineMiles(p.dayCentroid, single.dayCentroid)
                    if gapP <= maxGapDaysToBridge && distP <= countryFallbackMaxMiles {
                        mergeIntoPrev = true
                    }
                }
                var mergeIntoNext: Bool? = nil
                if let n = nextFirst, n.countryCode == single.countryCode {
                    let gapN = single.dayGap(to: n)
                    let distN = GeoDistanceHelper.haversineMiles(single.dayCentroid, n.dayCentroid)
                    if gapN <= maxGapDaysToBridge && distN <= countryFallbackMaxMiles {
                        mergeIntoNext = true
                    }
                }

                if mergeIntoPrev == true || mergeIntoNext == true {
                    let distPrev = prevLast.map { GeoDistanceHelper.haversineMiles($0.dayCentroid, single.dayCentroid) } ?? .infinity
                    let distNext = nextFirst.map { GeoDistanceHelper.haversineMiles(single.dayCentroid, $0.dayCentroid) } ?? .infinity
                    if distPrev <= distNext, let p = prevTrip {
                        result[i - 1] = p + [single]
                        result.remove(at: i)
                        changed = true
                        break
                    } else if let n = nextTrip {
                        result[i] = [single] + n
                        result.remove(at: i + 1)
                        changed = true
                        break
                    }
                }
            }
        }
        return result
    }
}
