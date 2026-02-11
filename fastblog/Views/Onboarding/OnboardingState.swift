//
//  OnboardingState.swift
//  Capper
//

import Combine
import CoreLocation
import Foundation

/// In-memory (and optional UserDefaults) state for onboarding selection.
final class OnboardingState: ObservableObject {
    @Published private(set) var neighborhoodSelection: NeighborhoodSelection?

    private static let neighborhoodKey = "blogify.neighborhoodSelection"

    init() {
        loadFromUserDefaults()
    }

    func saveSelection(_ selection: NeighborhoodSelection) {
        neighborhoodSelection = selection
        saveToUserDefaults(selection)
    }

    func clearSelection() {
        neighborhoodSelection = nil
        UserDefaults.standard.removeObject(forKey: Self.neighborhoodKey)
        NeighborhoodStore.saveCenter(nil)
    }

    private func saveToUserDefaults(_ selection: NeighborhoodSelection) {
        let dict: [String: Any] = [
            "cityName": selection.cityName as Any,
            "centerLatitude": selection.centerLatitude,
            "centerLongitude": selection.centerLongitude,
            "spanLatitudeDelta": selection.spanLatitudeDelta,
            "spanLongitudeDelta": selection.spanLongitudeDelta
        ]
        UserDefaults.standard.set(dict, forKey: Self.neighborhoodKey)
        NeighborhoodStore.saveCenter(selection.center)
        NeighborhoodStore.saveDisplayName(selection.cityName)
    }

    private func loadFromUserDefaults() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.neighborhoodKey),
              let lat = dict["centerLatitude"] as? Double,
              let lon = dict["centerLongitude"] as? Double else {
            return
        }
        let cityName = dict["cityName"] as? String
        let spanLat = dict["spanLatitudeDelta"] as? Double ?? OnboardingConstants.Map.defaultSpanLat
        let spanLon = dict["spanLongitudeDelta"] as? Double ?? OnboardingConstants.Map.defaultSpanLon
        neighborhoodSelection = NeighborhoodSelection(
            cityName: cityName,
            centerLatitude: lat,
            centerLongitude: lon,
            spanLatitudeDelta: spanLat,
            spanLongitudeDelta: spanLon
        )
    }
}
