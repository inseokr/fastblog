//
//  OnboardingStore.swift
//  Capper
//

import CoreLocation
import Foundation

/// Tracks onboarding completion and neighborhood selection (50 mile radius).
enum OnboardingStore {
    private static let hasCompletedOnboardingKey = "blogify.hasCompletedOnboarding"
    private static let neighborhoodLatKey = "blogify.neighborhoodLat"
    private static let neighborhoodLonKey = "blogify.neighborhoodLon"
    private static let neighborhoodRadiusMilesKey = "blogify.neighborhoodRadiusMiles"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    static var neighborhoodCenter: CLLocationCoordinate2D? {
        get {
            let lat = UserDefaults.standard.double(forKey: neighborhoodLatKey)
            let lon = UserDefaults.standard.double(forKey: neighborhoodLonKey)
            guard lat != 0 || lon != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        set {
            if let c = newValue {
                UserDefaults.standard.set(c.latitude, forKey: neighborhoodLatKey)
                UserDefaults.standard.set(c.longitude, forKey: neighborhoodLonKey)
            } else {
                UserDefaults.standard.removeObject(forKey: neighborhoodLatKey)
                UserDefaults.standard.removeObject(forKey: neighborhoodLonKey)
            }
        }
    }

    static var neighborhoodRadiusMiles: Double {
        get {
            let v = UserDefaults.standard.double(forKey: neighborhoodRadiusMilesKey)
            return v > 0 ? v : 50
        }
        set { UserDefaults.standard.set(newValue, forKey: neighborhoodRadiusMilesKey) }
    }

    static func isWithinNeighborhood(_ location: CLLocation) -> Bool {
        guard let center = neighborhoodCenter else { return true }
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let metersPerMile: Double = 1609.34
        let radiusMeters = neighborhoodRadiusMiles * metersPerMile
        return centerLoc.distance(from: location) <= radiusMeters
    }
}
