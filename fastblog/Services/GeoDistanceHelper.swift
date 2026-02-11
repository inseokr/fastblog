//
//  GeoDistanceHelper.swift
//  Capper
//
//  Haversine distance in miles for Day→Trip clustering. Deterministic.
//

import CoreLocation
import Foundation

enum GeoDistanceHelper {
    private static let earthRadiusMiles: Double = 3958.8

    /// Haversine distance between two coordinates in miles.
    static func haversineMiles(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMiles * c
    }

    static func haversineMiles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        haversineMiles(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    static func haversineMiles(_ a: PhotoCoordinate, _ b: PhotoCoordinate) -> Double {
        haversineMiles(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    /// Max pairwise distance in miles between coordinates (for multi-city day validation).
    static func maxPairwiseDistanceMiles(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var maxD: Double = 0
        for i in 0..<coords.count {
            for j in (i + 1)..<coords.count {
                let d = haversineMiles(coords[i], coords[j])
                if d > maxD { maxD = d }
            }
        }
        return maxD
    }
}
