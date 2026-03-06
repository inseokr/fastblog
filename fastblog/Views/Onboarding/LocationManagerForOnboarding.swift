//
//  LocationManagerForOnboarding.swift
//  Capper
//

import Combine
import CoreLocation
import Foundation

final class LocationManagerForOnboarding: NSObject, ObservableObject {
    @Published var lastCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .notDetermined {
            AppAnalytics.shared.trackEvent(name: "location_permission_prompted")
            manager.requestWhenInUseAuthorization()
        }
    }
}

extension LocationManagerForOnboarding: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        DispatchQueue.main.async {
            self.lastCoordinate = coord
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastCoordinate = nil
        }
    }
}
