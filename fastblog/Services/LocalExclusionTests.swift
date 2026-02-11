//
//  LocalExclusionTests.swift
//  Capper
//
//  Unit tests for local (non-trip) exclusion. Run in a test target, or call LocalExclusionTests.runAll() in Debug.

import CoreLocation
import Foundation

#if DEBUG
enum LocalExclusionTests {
    /// Run all tests; use in test target or call from app in Debug to verify exclusion logic.
    static func runAll() {
        testPhotoWithin50MilesIsExcluded()
        testPhotoOutside50MilesIsNotExcluded()
        testPhotoWithoutGPSIsNotExcluded()
        testNilNeighborhoodCenterExcludesNoOne()
    }

    static func testPhotoWithin50MilesIsExcluded() {
        let center = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let nearby = CLLocation(latitude: 37.8, longitude: -122.4) // ~20 mi
        assert(LocalExclusion.shouldExclude(assetLocation: nearby, neighborhoodCenter: center, radiusMiles: 50) == true)
    }

    static func testPhotoOutside50MilesIsNotExcluded() {
        let center = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let far = CLLocation(latitude: 38.5, longitude: -122.4) // ~50+ mi
        assert(LocalExclusion.shouldExclude(assetLocation: far, neighborhoodCenter: center, radiusMiles: 50) == false)
    }

    static func testPhotoWithoutGPSIsNotExcluded() {
        let center = CLLocation(latitude: 37.7749, longitude: -122.4194)
        assert(LocalExclusion.shouldExclude(assetLocation: nil, neighborhoodCenter: center, radiusMiles: 50) == false)
    }

    static func testNilNeighborhoodCenterExcludesNoOne() {
        let somewhere = CLLocation(latitude: 37.7749, longitude: -122.4194)
        assert(LocalExclusion.shouldExclude(assetLocation: somewhere, neighborhoodCenter: nil, radiusMiles: 50) == false)
    }
}
#endif
