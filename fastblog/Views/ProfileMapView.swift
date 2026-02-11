//
//  ProfileMapView.swift
//  Capper
//

import MapKit
import SwiftUI

// MARK: - ProfileMapView (map + country filter buttons)

/// Map-first Profile: full-screen map with trip markers and country filter pills at top.
struct ProfileMapView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @StateObject private var viewModel: ProfileMapViewModel
    @State private var mapPosition: MapCameraPosition = .automatic

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = StateObject(wrappedValue: ProfileMapViewModel(createdRecapStore: createdRecapStore))
        _selectedCreatedRecap = selectedCreatedRecap
    }

    var body: some View {
        ZStack(alignment: .top) {
            profileMap
            countryFilterBar
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("My Map")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.onAppear()
            mapPosition = .region(viewModel.mapRegion)
        }
        .onChange(of: viewModel.mapRegionChangeCounter) { _, _ in
            mapPosition = .region(viewModel.mapRegion)
        }
    }

    private var profileMap: some View {
        Map(position: $mapPosition) {
            ForEach(viewModel.tripsWithCoordinates, id: \.blog.sourceTripId) { item in
                Annotation("", coordinate: item.coordinate) {
                    TripAnnotationView(
                        blog: item.blog,
                        isSelected: viewModel.selectedTripID == item.blog.sourceTripId
                    )
                    .onTapGesture {
                        viewModel.selectTrip(item.blog.sourceTripId)
                        selectedCreatedRecap = item.blog
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.mapRegion = context.region
        }
    }

    // MARK: - Country Filter Bar

    private var countryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                countryPill(label: "All", isSelected: viewModel.selectedCountryID == nil) {
                    viewModel.selectCountry(nil)
                }
                ForEach(viewModel.countrySummaries) { summary in
                    countryPill(
                        label: summary.countryName,
                        isSelected: viewModel.selectedCountryID == summary.countryName
                    ) {
                        viewModel.selectCountry(summary.countryName)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func countryPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TripAnnotationView (portrait thumbnail marker)

/// Portrait rounded-rectangle trip cover thumbnail for map annotations.
struct TripAnnotationView: View {
    let blog: CreatedRecapBlog
    var isSelected: Bool = false

    private static let width: CGFloat = 52
    private static let height: CGFloat = 72

    var body: some View {
        VStack(spacing: 4) {
            TripCoverImage(
                theme: blog.coverImageName,
                coverAssetIdentifier: blog.coverAssetIdentifier
            )
            .frame(width: Self.width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.6), lineWidth: isSelected ? 3 : 1.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)

            Text(blog.title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
    }
}

// MARK: - CountryMapView (map filtered to a single country)

/// Map showing only trips for a specific country. Reached from CountryBlogsView toolbar.
struct CountryMapView: View {
    let countryName: String
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @StateObject private var viewModel: ProfileMapViewModel
    @State private var mapPosition: MapCameraPosition = .automatic

    init(countryName: String, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        self.countryName = countryName
        _selectedCreatedRecap = selectedCreatedRecap
        _viewModel = StateObject(wrappedValue: ProfileMapViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        Map(position: $mapPosition) {
            ForEach(viewModel.tripsWithCoordinates, id: \.blog.sourceTripId) { item in
                Annotation("", coordinate: item.coordinate) {
                    TripAnnotationView(
                        blog: item.blog,
                        isSelected: viewModel.selectedTripID == item.blog.sourceTripId
                    )
                    .onTapGesture {
                        viewModel.selectTrip(item.blog.sourceTripId)
                        selectedCreatedRecap = item.blog
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.mapRegion = context.region
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(countryName)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.selectCountry(countryName)
            mapPosition = .region(viewModel.mapRegion)
        }
        .onChange(of: viewModel.mapRegionChangeCounter) { _, _ in
            mapPosition = .region(viewModel.mapRegion)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileMapView(
            createdRecapStore: CreatedRecapBlogStore.shared,
            selectedCreatedRecap: .constant(nil)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
