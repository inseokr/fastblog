//
//  NeighborhoodSelectionView.swift
//  Capper
//

import CoreLocation
import MapKit
import SwiftUI

struct NeighborhoodSelectionView: View {
    var onSelect: () -> Void

    @State private var mapRegion: MKCoordinateRegion
    @StateObject private var searchHelper = CitySearchHelper()
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var locationManager = LocationManagerForOnboarding()
    /// After tapping Select we store the circle center/span and resolve the place name; Done saves and advances.
    @State private var hasPendingSelection = false
    @State private var pendingCenter: CLLocationCoordinate2D?
    @State private var pendingSpan: MKCoordinateSpan?
    @State private var isResolvingPlace = false

    init(onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        _mapRegion = State(initialValue: MKCoordinateRegion(
            center: OnboardingConstants.Map.defaultCenter,
            span: MKCoordinateSpan(
                latitudeDelta: OnboardingConstants.Map.defaultSpanLat,
                longitudeDelta: OnboardingConstants.Map.defaultSpanLon
            )
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topSection
                mapSection
            }
            if hasPendingSelection {
                doneButtonAtBottom
            }
        }
        .background(OnboardingConstants.Colors.background)
        .preferredColorScheme(.dark)
        .onAppear {
            locationManager.requestLocation()
            searchHelper.onRegionSelected = { region, name in
                mapRegion = region
                if let name = name {
                    searchHelper.query = name
                }
            }
        }
        .onChange(of: locationManager.lastCoordinate?.latitude) { _, _ in
            guard let coord = locationManager.lastCoordinate else { return }
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(
                    latitudeDelta: OnboardingConstants.Map.defaultSpanLat,
                    longitudeDelta: OnboardingConstants.Map.defaultSpanLon
                )
            )
            mapRegion = region
        }
    }

    private var topSection: some View {
        VStack(spacing: OnboardingConstants.Layout.spacingBetweenTitleAndSearch) {
            Text("Neighborhood")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, OnboardingConstants.Layout.titleTopPadding)

            searchField
            if isResolvingPlace {
                Text("Finding area…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            // Only show suggestion list when not showing a pending selection (avoid extra white box with same name)
            if !hasPendingSelection {
                suggestionList
            }
        }
        .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            if searchHelper.query.isEmpty {
                Text("Select Area On Map")
                    .font(.body)
                    .foregroundColor(Color(white: 0.45))
                    .padding(.leading, 16)
            }
            TextField("", text: $searchHelper.query)
                .textFieldStyle(.plain)
                .foregroundColor(.black.opacity(0.85))
                .padding(12)
        }
        .background(OnboardingConstants.Colors.searchBackground)
        .cornerRadius(OnboardingConstants.Layout.searchCornerRadius)
        .accessibilityLabel("Select area on map")
        .accessibilityHint("Type to see suggestions, or pan the map and tap Select to choose an area")
    }

    @ViewBuilder
    private var suggestionList: some View {
        if !searchHelper.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(searchHelper.suggestions.enumerated()), id: \.element.uniqueKey) { _, completion in
                    Button {
                        searchHelper.selectSuggestion(completion)
                    } label: {
                        Text(suggestionDisplayText(completion))
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OnboardingConstants.Colors.background)
            .cornerRadius(OnboardingConstants.Layout.searchCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingConstants.Layout.searchCornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }

    /// One-line text for a suggestion row: "Title" or "Title, Subtitle".
    private func suggestionDisplayText(_ completion: MKLocalSearchCompletion) -> String {
        if completion.subtitle.isEmpty {
            return completion.title
        }
        return "\(completion.title), \(completion.subtitle)"
    }

    private var mapSection: some View {
        MapWithCenterSelector(region: $mapRegion) { center, span in
            handleSelect(center: center, span: span)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingConstants.Colors.mapBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    private var doneButtonAtBottom: some View {
        Button(action: commitSelectionAndContinue) {
            Text("Done")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OnboardingConstants.Layout.selectButtonVerticalPadding)
                .background(OnboardingConstants.Colors.doneButtonBlue)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
        .padding(.bottom, 32)
        .padding(.top, 16)
        .background(OnboardingConstants.Colors.background)
        .accessibilityLabel("Done")
        .accessibilityHint("Save neighborhood and continue")
    }

    /// Called when user taps Select: capture center/span and reverse geocode to update the text field. Does not navigate.
    private func handleSelect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        hasPendingSelection = true
        pendingCenter = center
        pendingSpan = span
        isResolvingPlace = true
        Task { @MainActor in
            defer { isResolvingPlace = false }
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let place = await GeocodingService.shared.place(for: location)
            searchHelper.query = place.areaName
        }
    }

    /// Save the pending selection and advance to the next onboarding step.
    private func commitSelectionAndContinue() {
        guard let center = pendingCenter, let span = pendingSpan else { return }
        let cityName = searchHelper.query.isEmpty ? nil : searchHelper.query
        let selection = NeighborhoodSelection(
            cityName: cityName,
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            spanLatitudeDelta: span.latitudeDelta,
            spanLongitudeDelta: span.longitudeDelta
        )
        onboardingState.saveSelection(selection)
        NeighborhoodStore.saveCenter(selection.center)
        onSelect()
    }
}

// MARK: - MKLocalSearchCompletion doesn't conform to Identifiable; use a key

private extension MKLocalSearchCompletion {
    var uniqueKey: String { "\(title)-\(subtitle)" }
}
