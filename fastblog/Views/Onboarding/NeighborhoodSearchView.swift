//
//  NeighborhoodSearchView.swift
//  fastblog
//

import MapKit
import SwiftUI

struct NeighborhoodSearchView: View {
    /// Wide enough for "Cancel" / "Save" so the title stays centered in one row.
    private static let navChromeSideSlot: CGFloat = 76

    var onDismiss: () -> Void

    @StateObject private var searchHelper = CitySearchHelper()
    @StateObject private var locationManager = LocationManagerForOnboarding()
    @StateObject private var onboardingState = OnboardingState()
    @FocusState private var isFocused: Bool

    // Pending selection (from city search or map Select)
    @State private var hasPendingSelection = false
    @State private var pendingCenter: CLLocationCoordinate2D?
    @State private var pendingSpan: MKCoordinateSpan?
    @State private var pendingCityName: String?

    // Map state (for "Use Current Location" path)
    @State private var showMap = false
    @State private var mapRegion = MKCoordinateRegion(
        center: OnboardingConstants.Map.defaultCenter,
        span: MKCoordinateSpan(
            latitudeDelta: OnboardingConstants.Map.defaultSpanLat,
            longitudeDelta: OnboardingConstants.Map.defaultSpanLon
        )
    )

    // Save confirmation
    @State private var showSuccess = false
    @State private var isResolvingPlace = false

    var body: some View {
        ZStack {
            OnboardingConstants.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Pull-up handle indicator
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)

                // Header row: single HStack (title vertically aligned with Cancel / Save).
                HStack(alignment: .center, spacing: 0) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: Self.navChromeSideSlot, height: 44, alignment: .leading)

                    Text("Set Home")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Group {
                        if hasPendingSelection {
                            Button {
                                saveAndDismiss()
                            } label: {
                                Text("Save")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(OnboardingConstants.Colors.doneButtonBlue)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: Self.navChromeSideSlot, height: 44, alignment: .trailing)
                }
                .padding(.top, 8)
                .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))

                    TextField("", text: $searchHelper.query, prompt: Text("Search for your neighborhood").foregroundColor(.white.opacity(0.3)))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .focused($isFocused)
                        .autocorrectionDisabled()

                    if !searchHelper.query.isEmpty {
                        Button {
                            searchHelper.query = ""
                            hasPendingSelection = false
                            pendingCenter = nil
                            pendingSpan = nil
                            pendingCityName = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .appChromeCornerRadius(OnboardingConstants.Layout.searchCornerRadius)
                .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
                .padding(.top, 10)

                // Content area
                if showMap {
                    // MapWithCenterSelector (onboarding-style map)
                    MapWithCenterSelector(
                        region: $mapRegion,
                        selectedAreaName: hasPendingSelection ? pendingCityName : nil,
                        onDeselect: {
                            hasPendingSelection = false
                            pendingCenter = nil
                            pendingSpan = nil
                            pendingCityName = nil
                        },
                        onSelect: { center, span in
                            handleMapSelect(center: center, span: span)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16)
                } else if !searchHelper.suggestions.isEmpty {
                    // Autocomplete suggestions
                    List {
                        ForEach(Array(searchHelper.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                selectSuggestion(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title)
                                        .font(.body)
                                        .foregroundColor(.white)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.white.opacity(0.1))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 10)
                } else if !hasPendingSelection {
                    // Default state: Use Current Location + Recent Searches
                    VStack(spacing: 20) {
                        Button {
                            useCurrentLocation()
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use Current Location")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Find neighborhood near you")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .appChromeCornerRadius(16)
                        }
                        .padding(.horizontal)

                        if !NeighborhoodStore.recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent Searches")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal)

                                ForEach(NeighborhoodStore.recentSearches, id: \.self) { search in
                                    Button {
                                        searchHelper.query = search
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock")
                                                .foregroundColor(.white.opacity(0.5))
                                            Text(search)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color.white.opacity(0.05))
                                        .appChromeCornerRadius(12)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 10)
                } else {
                    // City selected from search — just show spacer below the search field
                    Spacer()
                }
            }

            // Success overlay
            if showSuccess {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .symbolEffect(.bounce, value: showSuccess)
                    Text("Neighborhood Saved")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(40)
                .background(.ultraThinMaterial)
                .appChromeCornerRadius(20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            locationManager.requestLocation()

            searchHelper.onRegionSelected = { region, name in
                if let name = name {
                    NeighborhoodStore.addRecentSearch(name)
                }
                // Store selection directly — no map needed for city search
                isFocused = false
                hasPendingSelection = true
                pendingCenter = region.center
                pendingSpan = region.span
                pendingCityName = name
                if let name = name {
                    searchHelper.query = name
                }
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }

    // MARK: - Actions

    private func useCurrentLocation() {
        isFocused = false
        if let location = locationManager.lastCoordinate {
            mapRegion = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        } else {
            locationManager.requestLocation()
        }
        showMap = true
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        searchHelper.selectSuggestion(suggestion)
    }

    private func handleMapSelect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        hasPendingSelection = true
        pendingCenter = center
        pendingSpan = span
        isResolvingPlace = true
        Task { @MainActor in
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let place = await GeocodingService.shared.place(for: location)
            isResolvingPlace = false
            pendingCityName = place.areaName
            searchHelper.query = place.areaName
        }
    }

    private func saveAndDismiss() {
        guard let center = pendingCenter, let span = pendingSpan else { return }
        let selection = NeighborhoodSelection(
            cityName: pendingCityName,
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            spanLatitudeDelta: span.latitudeDelta,
            spanLongitudeDelta: span.longitudeDelta
        )
        onboardingState.saveSelection(selection)
        NeighborhoodStore.saveCenter(center)
        withAnimation {
            showSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onDismiss()
        }
    }
}
