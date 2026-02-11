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
        testAdjacentSameCountryOutsideNeighborhoodMerges()
        testGap1To2DaysMergesWhenRulesPass()
        testMultiCityDayOver100MilesForcesSplit()
        testDifferentCountriesSplitEvenIfClose()
        testHaversineSanity()
    }

    /// Adjacent days, same country, distance 60 mi (outside 50 mi neighborhood, within 100 mi) → should merge via country fallback.
    static func testAdjacentSameCountryOutsideNeighborhoodMerges() {
        let d1 = makeDay(dayOffset: 0, lat: 37.77, lon: -122.42, countryCode: "US", countryName: "United States", cityName: "SF")
        let d2 = makeDay(dayOffset: 1, lat: 38.35, lon: -122.18, countryCode: "US", countryName: "United States", cityName: "Napa")
        let miles = GeoDistanceHelper.haversineMiles(d1.dayCentroid, d2.dayCentroid)
        assert(miles > 50 && miles <= 100, "distance should be ~60 mi, got \(miles)")
        let result = DayToTripGrouper.groupDaysIntoTrips(
            days: [d1, d2],
            neighborhoodRadiusMiles: 50,
            countryFallbackMaxMiles: 100,
            maxGapDaysToBridge: 2,
            multiCityDayMaxMiles: 100
        )
        assert(result.trips.count == 1, "expected 1 trip, got \(result.trips.count)")
        assert(result.trips[0].count == 2, "expected 2 days in trip")
    }

    /// Gap of 1 day and 2 days between days, same country, within 100 mi → should merge (bridge rule).
    static func testGap1To2DaysMergesWhenRulesPass() {
        let d1 = makeDay(dayOffset: 0, lat: 35.68, lon: 139.65, countryCode: "JP", cityName: "Tokyo")
        let d2 = makeDay(dayOffset: 2, lat: 35.68, lon: 139.70, countryCode: "JP", cityName: "Tokyo")
        let gap = d1.dayGap(to: d2)
        assert(gap == 2, "gap should be 2, got \(gap)")
        let result = DayToTripGrouper.groupDaysIntoTrips(
            days: [d1, d2],
            neighborhoodRadiusMiles: 50,
            countryFallbackMaxMiles: 100,
            maxGapDaysToBridge: 2,
            multiCityDayMaxMiles: 100
        )
        assert(result.trips.count == 1, "expected 1 trip with gap=2 bridge, got \(result.trips.count)")
    }

    /// A day with maxDistanceWithinDayMiles > 100 (multi-city day) should not merge via country fallback → new trip.
    static func testMultiCityDayOver100MilesForcesSplit() {
        let d1 = makeDay(dayOffset: 0, lat: 35.68, lon: 139.65, countryCode: "JP", cityName: "Tokyo", maxDistanceWithinDayMiles: 0)
        let d2 = makeDay(dayOffset: 1, lat: 34.69, lon: 135.50, countryCode: "JP", cityName: "Osaka", maxDistanceWithinDayMiles: 250)
        let result = DayToTripGrouper.groupDaysIntoTrips(
            days: [d1, d2],
            neighborhoodRadiusMiles: 50,
            countryFallbackMaxMiles: 100,
            maxGapDaysToBridge: 2,
            multiCityDayMaxMiles: 100
        )
        assert(result.trips.count == 2, "expected 2 trips (multi-city day forces split), got \(result.trips.count)")
    }

    /// Two days in different countries, even if close in distance → should split.
    static func testDifferentCountriesSplitEvenIfClose() {
        let d1 = makeDay(dayOffset: 0, lat: 48.85, lon: 2.35, countryCode: "FR", cityName: "Paris")
        let d2 = makeDay(dayOffset: 1, lat: 48.90, lon: 2.40, countryCode: "DE", cityName: "Strasbourg")
        let result = DayToTripGrouper.groupDaysIntoTrips(
            days: [d1, d2],
            neighborhoodRadiusMiles: 50,
            countryFallbackMaxMiles: 100,
            maxGapDaysToBridge: 2,
            multiCityDayMaxMiles: 100
        )
        assert(result.trips.count == 2, "expected 2 trips (different countries), got \(result.trips.count)")
    }

    static func testHaversineSanity() {
        let a = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)
        let b = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)
        let miles = GeoDistanceHelper.haversineMiles(a, b)
        assert(miles > 0 && miles < 2, "~1 degree lat ≈ 69 mi; 0.01 deg ≈ 0.69 mi, got \(miles)")
    }
}
#endif
