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
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
}

extension LocationManagerForOnboarding: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
}
