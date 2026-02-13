//
//  NeighborhoodSearchView.swift
//  fastblog
//

import MapKit
import SwiftUI

struct NeighborhoodSearchView: View {
    var onDismiss: () -> Void

    @StateObject private var searchHelper = CitySearchHelper()
    @StateObject private var locationManager = LocationManagerForOnboarding()
    @FocusState private var isFocused: Bool

    @State private var navigateToRefinement = false
    @State private var selectedRegion: MKCoordinateRegion?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))

                        TextField("", text: $searchHelper.query, prompt: Text("Search for your city or neighborhood").foregroundColor(.white.opacity(0.3)))
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .focused($isFocused)
                            .autocorrectionDisabled()

                        if !searchHelper.query.isEmpty {
                            Button {
                                searchHelper.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)

                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                if searchHelper.suggestions.isEmpty && searchHelper.query.isEmpty {
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
                        .cornerRadius(16)
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
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()

                } else {
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
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            isFocused = true
            locationManager.requestLocation()

            searchHelper.onRegionSelected = { region, name in
                if let name = name {
                    NeighborhoodStore.addRecentSearch(name)
                }
                self.selectedRegion = region
                self.navigateToRefinement = true
            }
        }
        .navigationDestination(isPresented: $navigateToRefinement) {
            if let region = selectedRegion {
                NeighborhoodMapRefinementView(initialRegion: region, onDismiss: onDismiss)
            }
        }
    }

    private func useCurrentLocation() {
        if let location = locationManager.lastCoordinate {
            let region = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            self.selectedRegion = region
            self.navigateToRefinement = true
        } else {
            locationManager.requestLocation()
        }
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        searchHelper.selectSuggestion(suggestion)
    }
}
