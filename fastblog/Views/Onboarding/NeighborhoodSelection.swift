//
//  NeighborhoodSelection.swift
//  Capper
//

import CoreLocation
import Foundation

/// User's chosen neighborhood area for trip filtering.
struct NeighborhoodSelection {
    var cityName: String?
    var centerLatitude: Double
    var centerLongitude: Double
    var spanLatitudeDelta: Double
    var spanLongitudeDelta: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    init(
        cityName: String? = nil,
        centerLatitude: Double,
        centerLongitude: Double,
        spanLatitudeDelta: Double = OnboardingConstants.Map.defaultSpanLat,
        spanLongitudeDelta: Double = OnboardingConstants.Map.defaultSpanLon
    ) {
        self.cityName = cityName
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.spanLatitudeDelta = spanLatitudeDelta
        self.spanLongitudeDelta = spanLongitudeDelta
    }
}
