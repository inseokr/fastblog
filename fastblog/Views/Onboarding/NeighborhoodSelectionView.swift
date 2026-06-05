//
//  NeighborhoodSelectionView.swift
//  Capper
//

import CoreLocation
import UIKit
import MapKit
import SwiftUI

struct NeighborhoodSelectionView: View {
    /// Matches common nav-bar control width so the title stays centered and baseline-aligned with the chevron.
    private static let navChromeSideSlot: CGFloat = 44

    var onSelect: () -> Void
    var onBack: (() -> Void)?
    
    @State private var mapRegion: MKCoordinateRegion
    @StateObject private var searchHelper = CitySearchHelper()
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var locationManager = LocationManagerForOnboarding()
    /// After tapping Select we store the circle center/span and resolve the place name; Done saves and advances.
    @State private var hasPendingSelection = false
    @State private var pendingCenter: CLLocationCoordinate2D?
    @State private var pendingSpan: MKCoordinateSpan?
    @State private var isResolvingPlace = false
    @State private var resolvePlaceTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @State private var isMapRevealed = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minFieldHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var fieldHorizontalInset: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var fieldVerticalInset: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var clearButtonTrailingInset: CGFloat = 12
    private var settingsBackground: Color {
        OnboardingConstants.Colors.background
    }
    private var titleTopPadding: CGFloat {
        // When embedded in the Settings navigation stack, a navigation bar back button exists
        // already, so we need less vertical padding to keep the search UI higher.
        onBack == nil ? 0 : OnboardingConstants.Layout.titleTopPadding
    }
    
    private var titleToSearchSpacing: CGFloat {
        // Pull Search + "Use Current Location" upward when we rely on the nav bar.
        onBack == nil ? 12 : OnboardingConstants.Layout.spacingBetweenTitleAndSearch
    }

    /// When embedded under `NavigationStack` with a system back button (`onBack == nil`), the title belongs in the bar.
    private var navigationBarTitleOverride: String {
        onBack == nil ? "Set Home" : ""
    }

    init(onSelect: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.onSelect = onSelect
        self.onBack = onBack
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
                if isFocused && !hasPendingSelection && !searchHelper.suggestions.isEmpty {
                    ScrollView {
                        suggestionList
                    }
                    .scrollDismissesKeyboard(.never)
                    .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
                } else if isMapRevealed {
                    mapSection
                } else {
                    Spacer()
                }
            }
            if hasPendingSelection {
                doneButtonAtBottom
            }
        }
        .background(settingsBackground)
        .preferredColorScheme(.dark)
        // Settings → NeighborhoodIntroView passes `onBack: nil` and relies on the **system** nav bar
        // back control. Putting "Set Home" only in the bar row avoids a second title line below the back button.
        .navigationTitle(navigationBarTitleOverride)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            locationManager.refreshAuthorizationStatus()
            searchHelper.onRegionSelected = { region, name in
                isFocused = false
                searchHelper.suggestions = []
                hasPendingSelection = true
                pendingCenter = region.center
                pendingSpan = region.span
                mapRegion = region
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
        .onDisappear {
            resolvePlaceTask?.cancel()
            resolvePlaceTask = nil
        }
    }

    private var topSection: some View {
        VStack(spacing: titleToSearchSpacing) {
            // Onboarding uses an in-content back chevron (`onBack != nil`). Settings uses the system
            // nav bar back + `.navigationTitle("Set Home")` — do not duplicate the title in-body.
            if onBack != nil {
                inlineSetHomeNavRow
                    .padding(.top, titleTopPadding)
            }

            searchField
            if isResolvingPlace {
                Text("Finding area…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
        .padding(.bottom, onBack == nil ? 14 : 24)
    }

    /// Custom nav row for onboarding only (system bar handles title when `onBack == nil`).
    private var inlineSetHomeNavRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if let onBack = onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.navChromeSideSlot, height: Self.navChromeSideSlot, alignment: .center)

            Text("Set Home")
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: Self.navChromeSideSlot, height: Self.navChromeSideSlot)
        }
    }

    private var searchField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    if searchHelper.query.isEmpty {
                        Text("Search for your neighborhood")
                            .font(.body)
                            .foregroundColor(Color(white: 0.45))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, fieldHorizontalInset)
                            .padding(.trailing, clearButtonTrailingInset)
                    }
                    TextField("", text: $searchHelper.query)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.black.opacity(0.85))
                        .focused($isFocused)
                        .padding(.horizontal, fieldHorizontalInset)
                        .padding(.vertical, fieldVerticalInset)
                        .onChange(of: isFocused) { _, focused in
                            if focused && hasPendingSelection {
                                // User re-tapped the field after a confirmed selection —
                                // clear pending so autocomplete can reappear as they type.
                                hasPendingSelection = false
                                pendingCenter = nil
                                pendingSpan = nil
                                resolvePlaceTask?.cancel()
                                resolvePlaceTask = nil
                                searchHelper.retriggerSuggestions()
                            }
                            if !focused {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if !isFocused { searchHelper.suggestions = [] }
                                }
                            }
                        }
                }

                if !searchHelper.query.isEmpty {
                    Button {
                        clearSelection()
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(white: 0.45))
                            .padding(.trailing, clearButtonTrailingInset)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: minFieldHeight)
            .background(OnboardingConstants.Colors.searchBackground)
            .appChromeCornerRadius(OnboardingConstants.Layout.searchCornerRadius)
            .accessibilityLabel("Select area on map")
            .accessibilityHint("Type to see suggestions, or pan the map and tap Select to choose an area")

            if searchHelper.query.isEmpty && !hasPendingSelection && !isMapRevealed {
                useCurrentLocationButton
            }
        }
    }

    private func clearSelection() {
        searchHelper.clearQuery()
        hasPendingSelection = false
        pendingCenter = nil
        pendingSpan = nil
        resolvePlaceTask?.cancel()
        resolvePlaceTask = nil
        isResolvingPlace = false
    }

    @ViewBuilder
    private var suggestionList: some View {
        if !searchHelper.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(searchHelper.suggestions.enumerated()), id: \.element.uniqueKey) { _, completion in
                    Button {
                        isFocused = false
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
            .appChromeCornerRadius(OnboardingConstants.Layout.searchCornerRadius)
            .overlay(
                RoundedRectangle(appChromeBaseRadius: OnboardingConstants.Layout.searchCornerRadius)
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
        MapWithCenterSelector(
            region: $mapRegion,
            selectedAreaName: hasPendingSelection ? searchHelper.query : nil,
            onDeselect: {
                hasPendingSelection = false
                pendingCenter = nil
                pendingSpan = nil
                resolvePlaceTask?.cancel()
                resolvePlaceTask = nil
                searchHelper.clearQuery()  // clears both query + suggestions synchronously, preventing the flash
            },
            onSelect: { center, span in
                handleSelect(center: center, span: span)
            }
        )
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
        .disabled(isResolvingPlace)
        .opacity(isResolvingPlace ? 0.7 : 1)
        .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
        .padding(.bottom, 32)
        .padding(.top, 16)
        .background(OnboardingConstants.Colors.background)
        .accessibilityLabel("Done")
        .accessibilityHint("Save neighborhood and continue")
    }

    private var useCurrentLocationButton: some View {
        Button {
            isFocused = false
            isMapRevealed = true
            if let coord = locationManager.lastCoordinate {
                mapRegion = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(
                        latitudeDelta: OnboardingConstants.Map.defaultSpanLat,
                        longitudeDelta: OnboardingConstants.Map.defaultSpanLon
                    )
                )
            } else {
                locationManager.requestLocationWhenUserInitiated()
            }
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
        .padding(.top, 4)
    }

    /// Called when user taps Select: capture center/span and reverse geocode to update the text field. Does not navigate.
    private func handleSelect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        hasPendingSelection = true
        pendingCenter = center
        pendingSpan = span
        isResolvingPlace = true
        resolvePlaceTask?.cancel()
        resolvePlaceTask = Task { @MainActor in
            defer {
                isResolvingPlace = false
                resolvePlaceTask = nil
            }
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let place = await GeocodingService.shared.place(for: location)
            guard !Task.isCancelled else { return }
            searchHelper.query = place.areaName
        }
    }

    /// Save the pending selection and advance to the next onboarding step.
    private func commitSelectionAndContinue() {
        guard !isResolvingPlace else { return }
        guard let center = pendingCenter, let span = pendingSpan else { return }
        resolvePlaceTask?.cancel()
        resolvePlaceTask = nil
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
