//
//  ProfileMapViewModel.swift
//  Capper
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

/// Manages state for the map-first Profile: trips, country summaries, selection, and map region.
@MainActor
final class ProfileMapViewModel: ObservableObject {
    @Published var selectedCountryID: String?
    @Published var selectedTripID: UUID?
    @Published var searchText: String = ""
    @Published var mapRegion: MKCoordinateRegion
    @Published var animatedRegion: MKCoordinateRegion?
    /// Incremented whenever mapRegion is set; use in onChange since MKCoordinateRegion is not Equatable.
    @Published var mapRegionChangeCounter: Int = 0

    private let store: CreatedRecapBlogStore
    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )

    init(createdRecapStore: CreatedRecapBlogStore) {
        self.store = createdRecapStore
        self.mapRegion = defaultRegion
    }

    /// Only cloud-published blogs appear on the Profile map, matching the Profile page list.
    var allTrips: [CreatedRecapBlog] {
        store.cloudPublishedBlogs
    }

    /// Country summaries for the filter bar — only cloud-published blogs.
    var countrySummaries: [CountryRecapSummary] {
        store.cloudCountrySummaries
    }

    /// Trips to show on map and in modal; filtered by selected country and search text when set. Sorted newest to oldest.
    var visibleTrips: [CreatedRecapBlog] {
        var trips = selectedCountryID == nil ? allTrips : allTrips.filter { ($0.countryName ?? "Unknown") == selectedCountryID }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            trips = trips.filter { blog in
                blog.title.lowercased().contains(query) || (blog.countryName?.lowercased().contains(query) ?? false)
            }
        }
        
        return trips.sorted { $0.createdAt > $1.createdAt }
    }
    
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Latest trip overall (for initial map center and "back to all" recenter).
    /// Uses visibleTrips which is already sorted newest → oldest.
    var latestTripOverall: CreatedRecapBlog? {
        visibleTrips.first
    }

    /// Latest trip in the selected country (for recenter when country is selected).
    var latestTripForSelectedCountry: CreatedRecapBlog? {
        guard selectedCountryID != nil else { return nil }
        return visibleTrips.first
    }

    /// Representative coordinate for a blog; nil if no location data.
    func coordinate(for blog: CreatedRecapBlog) -> CLLocationCoordinate2D? {
        store.coordinate(for: blog.sourceTripId)
    }

    /// Trips that have a valid coordinate (for map annotations only).
    var tripsWithCoordinates: [(blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)] {
        visibleTrips.compactMap { blog in
            guard let coord = coordinate(for: blog) else { return nil }
            return (blog, coord)
        }
    }

    /// Set country filter and recenter map + scroll card list to latest trip in that country.
    func selectCountry(_ countryID: String?) {
        selectedCountryID = countryID
        if countryID != nil {
            recenterToLatestInCountry()
        } else {
            recenterToLatestTrip()
        }
        // Always select the first (latest) visible trip so the card list scrolls to it.
        selectedTripID = visibleTrips.first?.sourceTripId
    }

    /// Select a trip (from map or list); used for highlight and optional callout.
    func selectTrip(_ sourceTripId: UUID?) {
        selectedTripID = sourceTripId
    }

    /// Recenter map to latest trip overall (with animation).
    func recenterToLatestTrip() {
        guard let trip = latestTripOverall, let coord = coordinate(for: trip) else {
            mapRegion = defaultRegion
            mapRegionChangeCounter += 1
            return
        }
        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        animatedRegion = region
        mapRegion = region
        mapRegionChangeCounter += 1
    }

    /// Recenter map to latest trip in selected country (with animation).
    func recenterToLatestInCountry() {
        guard let trip = latestTripForSelectedCountry ?? visibleTrips.first,
              let coord = coordinate(for: trip) else {
            recenterToLatestTrip()
            return
        }
        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        animatedRegion = region
        mapRegion = region
        mapRegionChangeCounter += 1
    }

    /// Recenter map to a specific trip (e.g. when user taps a trip in the list).
    func recenterToTrip(_ blog: CreatedRecapBlog) {
        guard let coord = coordinate(for: blog) else { return }
        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        animatedRegion = region
        mapRegion = region
        mapRegionChangeCounter += 1
    }

    /// Call when view appears to center on latest trip and select it in the card list.
    func onAppear() {
        if selectedCountryID == nil {
            // Select the latest (newest) trip first so the card scroll receives it
            // via onChange(of: selectedTripID), then recenter the map.
            selectedTripID = visibleTrips.first?.sourceTripId
            recenterToLatestTrip()
        }
    }
}
