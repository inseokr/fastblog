//
//  TripPhotoFilterTests.swift
//  Capper
//
//  Unit tests for Trip photo inclusion: no photos within 50 mi of home; no photos without location.
//  Boundary: exactly 50.0 miles → included; 49.99 miles → excluded.

import CoreLocation
import Foundation

#if DEBUG
enum TripPhotoFilterTests {
    static func runAll() {
        testNilAssetLocationExcluded()
        testExactly50MilesIncluded()
        test49_99MilesExcluded()
        test200MilesIncluded()
        testCoordinateSanity()
    }

    /// Nil location must be excluded from trips (no valid metadata).
    static func testNilAssetLocationExcluded() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        assert(TripPhotoFilter.shouldIncludeInTrips(assetLocation: nil, home: home, minMiles: 50) == false)
    }

    /// Boundary: exactly 50.0 miles from home must be included (requirement: 50.0 → included).
    static func testExactly50MilesIncluded() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        // ~50 miles north: lat + 50/69 (approx 69 mi per degree lat).
        let fiftyMilesNorth = CLLocation(latitude: 37.7749 + 50 / 69.0, longitude: -122.4194)
        let miles = TripPhotoFilter.distanceMiles(from: home, to: fiftyMilesNorth)
        assert(miles >= 49.9 && miles <= 50.5, "distance should be ~50 mi, got \(miles)")
        assert(TripPhotoFilter.shouldIncludeInTrips(assetLocation: fiftyMilesNorth, home: home, minMiles: 50) == true)
    }

    /// Just under 50 miles must be excluded (49.99 → excluded).
    static func test49_99MilesExcluded() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let under50 = CLLocation(latitude: 37.7749 + 49.99 / 69.0, longitude: -122.4194)
        let miles = TripPhotoFilter.distanceMiles(from: home, to: under50)
        assert(miles < 50, "distance should be < 50 mi, got \(miles)")
        assert(TripPhotoFilter.shouldIncludeInTrips(assetLocation: under50, home: home, minMiles: 50) == false)
    }

    /// Far away (200 mi) must be included.
    static func test200MilesIncluded() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let far = CLLocation(latitude: 37.7749 + 200 / 69.0, longitude: -122.4194)
        assert(TripPhotoFilter.shouldIncludeInTrips(assetLocation: far, home: home, minMiles: 50) == true)
    }

    /// Sanity: valid lat/lon (e.g. catch swapped coordinates). abs(lat) <= 90, abs(lon) <= 180.
    static func testCoordinateSanity() {
        assert(TripPhotoFilter.isValidCoordinate(lat: 37, lon: -122) == true)
        assert(TripPhotoFilter.isValidCoordinate(lat: 90, lon: 180) == true)
        assert(TripPhotoFilter.isValidCoordinate(lat: -90, lon: -180) == true)
        assert(TripPhotoFilter.isValidCoordinate(lat: 91, lon: 0) == false)
        assert(TripPhotoFilter.isValidCoordinate(lat: 0, lon: 181) == false)
        assert(TripPhotoFilter.isValidCoordinate(lat: 37, lon: -122) == true)
    }
}
#endif
