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
            VStack {
                Spacer()
                RecapBlogCarousel(
                    blogs: viewModel.orderedBlogs,
                    selectedBlog: $viewModel.selectedBlog,
                    centeredBlogID: $centeredBlogID,
                    onSelect: { blog in
                        viewModel.selectBlog(blog)
                    },
                    onNavigate: { blog in
                        selectedBlogForNavigation = blog
                    },
                    formatDateRange: viewModel.formatDateRange
                )
            }
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
            // Only update region if not animating from our selection
            if viewModel.animatedRegion == nil {
                 viewModel.mapRegion = context.region
            } else {
                // If we were animating, check if we reached target?
                // For simplicity, just update backing state.
                viewModel.mapRegion = context.region
            }
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

// MARK: - RecapBlogCarousel

struct RecapBlogCarousel: View {
    let blogs: [CreatedRecapBlog]
    @Binding var selectedBlog: CreatedRecapBlog?
    @Binding var centeredBlogID: UUID?
    let onSelect: (CreatedRecapBlog) -> Void
    let onNavigate: (CreatedRecapBlog) -> Void
    let formatDateRange: (Date?, Date?) -> String

    var body: some View {
        if blogs.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(blogs, id: \.sourceTripId) { blog in
                        RecapBlogCard(
                            blog: blog,
                            isSelected: selectedBlog?.sourceTripId == blog.sourceTripId,
                            formatDateRange: formatDateRange
                        )
                        .id(blog.sourceTripId)
                        .onTapGesture {
                            onSelect(blog)
                            onNavigate(blog)
                        }
                    }
                    // Spacer to allow the last item to be centered if needed, 
                    // though .viewAligned usually handles this well with content margins.
                    // Adding specific padding to center the first and last items if needed.
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24) // Initial padding
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredBlogID)
            .onChange(of: centeredBlogID) { _, newID in
                if let newID, let blog = blogs.first(where: { $0.sourceTripId == newID }) {
                    if selectedBlog?.sourceTripId != newID {
                        onSelect(blog)
                    }
                }
            }
            .frame(height: 140)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .offset(y: 20)
            )
        }
    }
}

// MARK: - RecapBlogCard

struct RecapBlogCard: View {
    let blog: CreatedRecapBlog
    let isSelected: Bool
    let formatDateRange: (Date?, Date?) -> String

    var body: some View {
        HStack(spacing: 12) {
            // Cover Photo
            TripCoverImage(
                theme: blog.coverImageName,
                coverAssetIdentifier: blog.coverAssetIdentifier
            )
            .frame(width: 80, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(blog.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(formatDateRange(blog.tripStartDate, blog.tripEndDate))
                    .font(.caption)
                    .foregroundColor(.gray)

                HStack(spacing: 8) {
                    Label("\(blog.totalPlaceVisitCount)", systemImage: "mappin.circle.fill")
                    Label("\(blog.tripDurationDays)d", systemImage: "clock.fill")
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(12)
        .frame(width: 280, height: 124)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial) // Glassmorphism
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
