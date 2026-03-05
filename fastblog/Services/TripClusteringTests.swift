//
//  TripClusteringTests.swift
//  Capper
//
//  Unit-like tests for Day→Trip clustering: merge/split rules and post-pass smoothing.
//

import CoreLocation
import Foundation
import Photos

#if DEBUG
enum TripClusteringTests {
    private static let cal = Calendar.current
    private static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private static func makeDay(
        dayOffset: Int,
        lat: Double, lon: Double,
        countryCode: String,
        countryName: String = "",
        cityName: String = "",
        maxDistanceWithinDayMiles: Double = 0
    ) -> DayCluster {
        DayCluster(
            dayDate: day(dayOffset),
            dayCentroid: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            countryCode: countryCode,
            countryName: countryName.isEmpty ? countryCode : countryName,
            cityName: cityName,
            cityCentroids: [CLLocationCoordinate2D(latitude: lat, longitude: lon)],
            maxDistanceWithinDayMiles: maxDistanceWithinDayMiles,
            assets: []
        )
    }

    static func runAll() {
        testAdjacentSameCountryMergesRegardlessOfDistance()
        testGap1To2DaysMergesWhenRulesPass()
        testSameCountryMergesEvenIfFarApart()
        testDifferentCountriesMergeWhenTripHasThreeOrFewerDays()
        testDifferentCountriesSplitWhenTripHasMoreThanThreeDays()
        testHaversineSanity()
    }

    /// Adjacent days, same country → should merge (no distance check).
    static func testAdjacentSameCountryMergesRegardlessOfDistance() {
        let d1 = makeDay(dayOffset: 0, lat: 37.77, lon: -122.42, countryCode: "US", countryName: "United States", cityName: "SF")
        let d2 = makeDay(dayOffset: 1, lat: 38.35, lon: -122.18, countryCode: "US", countryName: "United States", cityName: "Napa")
        let result = DayToTripGrouper.groupDaysIntoTrips(days: [d1, d2], maxGapDaysToBridge: 2)
        assert(result.trips.count == 1, "expected 1 trip, got \(result.trips.count)")
        assert(result.trips[0].count == 2, "expected 2 days in trip")
    }

    /// Gap of 1 day and 2 days between days, same country → should merge (bridge rule).
    static func testGap1To2DaysMergesWhenRulesPass() {
        let d1 = makeDay(dayOffset: 0, lat: 35.68, lon: 139.65, countryCode: "JP", cityName: "Tokyo")
        let d2 = makeDay(dayOffset: 2, lat: 35.68, lon: 139.70, countryCode: "JP", cityName: "Tokyo")
        let gap = d1.dayGap(to: d2)
        assert(gap == 2, "gap should be 2, got \(gap)")
        let result = DayToTripGrouper.groupDaysIntoTrips(days: [d1, d2], maxGapDaysToBridge: 2)
        assert(result.trips.count == 1, "expected 1 trip with gap=2 bridge, got \(result.trips.count)")
    }

    /// Same country, adjacent days, even far apart (e.g. Tokyo vs Osaka) → merge (no spatial split).
    static func testSameCountryMergesEvenIfFarApart() {
        let d1 = makeDay(dayOffset: 0, lat: 35.68, lon: 139.65, countryCode: "JP", cityName: "Tokyo", maxDistanceWithinDayMiles: 0)
        let d2 = makeDay(dayOffset: 1, lat: 34.69, lon: 135.50, countryCode: "JP", cityName: "Osaka", maxDistanceWithinDayMiles: 250)
        let result = DayToTripGrouper.groupDaysIntoTrips(days: [d1, d2], maxGapDaysToBridge: 2)
        assert(result.trips.count == 1, "expected 1 trip (same country, no distance split), got \(result.trips.count)")
    }

    /// Two days in different countries with trip length ≤3 → merge (country separation only when trip > 3 days).
    static func testDifferentCountriesMergeWhenTripHasThreeOrFewerDays() {
        let d1 = makeDay(dayOffset: 0, lat: 48.85, lon: 2.35, countryCode: "FR", cityName: "Paris")
        let d2 = makeDay(dayOffset: 1, lat: 48.90, lon: 2.40, countryCode: "DE", cityName: "Strasbourg")
        let result = DayToTripGrouper.groupDaysIntoTrips(days: [d1, d2], maxGapDaysToBridge: 2)
        assert(result.trips.count == 1, "expected 1 trip (country separation only when > 3 days), got \(result.trips.count)")
    }

    /// Four days in FR then one in DE → split (current trip has > 3 days so country separation applies).
    static func testDifferentCountriesSplitWhenTripHasMoreThanThreeDays() {
        let d1 = makeDay(dayOffset: 0, lat: 48.85, lon: 2.35, countryCode: "FR", cityName: "Paris")
        let d2 = makeDay(dayOffset: 1, lat: 48.86, lon: 2.36, countryCode: "FR", cityName: "Paris")
        let d3 = makeDay(dayOffset: 2, lat: 48.87, lon: 2.37, countryCode: "FR", cityName: "Paris")
        let d4 = makeDay(dayOffset: 3, lat: 48.88, lon: 2.38, countryCode: "FR", cityName: "Paris")
        let d5 = makeDay(dayOffset: 4, lat: 52.52, lon: 13.40, countryCode: "DE", cityName: "Berlin")
        let result = DayToTripGrouper.groupDaysIntoTrips(days: [d1, d2, d3, d4, d5], maxGapDaysToBridge: 2)
        assert(result.trips.count == 2, "expected 2 trips (4 days FR then DE → split), got \(result.trips.count)")
        assert(result.trips[0].count == 4, "expected 4 days in first trip")
        assert(result.trips[1].count == 1, "expected 1 day in second trip")
    }

    static func testHaversineSanity() {
        let a = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)
        let b = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)
        let miles = GeoDistanceHelper.haversineMiles(a, b)
        assert(miles > 0 && miles < 2, "~1 degree lat ≈ 69 mi; 0.01 deg ≈ 0.69 mi, got \(miles)")
    }
}
#endif
