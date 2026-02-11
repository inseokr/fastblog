//
//  TripClusteringDebug.swift
//  Capper
//
//  Debug switch for Day→Trip merge/split logging. When enabled, scan logs why each day merged or split.
//

import Foundation

enum TripClusteringDebug {
    private static let key = "capper.tripClustering.debugLogging"

    /// When true, clustering logs merge reasons (neighborhood_pass, country_fallback_pass, distance_too_far, etc.).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
