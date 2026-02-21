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
    @State private var selectedBlogForNavigation: CreatedRecapBlog?
    
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = StateObject(wrappedValue: ProfileMapViewModel(createdRecapStore: createdRecapStore))
        _selectedCreatedRecap = selectedCreatedRecap
    }

    var body: some View {
        ZStack(alignment: .top) {
            profileMap
            
            if !isSearchActive {
                countryFilterBar
            }
            
            // Bottom UI
            VStack {
                Spacer()
                if isSearchActive {
                    searchBar
                        .padding(.bottom, 20)
                } else {
                    bottomTripList
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle("My Map")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        isSearchActive.toggle()
                        if isSearchActive {
                            isSearchFocused = true
                        } else {
                            viewModel.searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.primary)
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
            // mapPosition is set reactively via onChange(of: mapRegionChangeCounter),
            // but seed it here too so there's no blank frame.
            mapPosition = .region(viewModel.mapRegion)
            // Seed scroll position synchronously — onChange(of: selectedTripID)
            // may not fire in the same run loop tick as the view appearing.
            scrolledTripID = viewModel.visibleTrips.first?.sourceTripId
        }
        .onChange(of: viewModel.mapRegionChangeCounter) { _, _ in
            withAnimation {
                mapPosition = .region(viewModel.mapRegion)
            }
        }
        .navigationDestination(item: $selectedBlogForNavigation) { blog in
            RecapBlogPageView(
                blogId: blog.sourceTripId,
                initialTrip: _createdRecapStore.wrappedValue.tripDraft(for: blog.sourceTripId)
            )
        }
    }

    private var profileMap: some View {
        Map(position: $mapPosition) {
            ForEach(viewModel.tripsWithCoordinates, id: \.blog.sourceTripId) { item in
                annotation(for: item)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.mapRegion = context.region
        }
        .ignoresSafeArea(.keyboard)
    }

    @MapContentBuilder
    private func annotation(for item: (blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)) -> some MapContent {
        Annotation("", coordinate: item.coordinate) {
            TripAnnotationView(
                blog: item.blog,
                isSelected: viewModel.selectedTripID == item.blog.sourceTripId
            )
            .onTapGesture {
                if viewModel.selectedTripID == item.blog.sourceTripId {
                    // Already selected — second tap opens the blog
                    selectedBlogForNavigation = item.blog
                } else {
                    // First tap — select and scroll card into view
                    withAnimation {
                        viewModel.selectTrip(item.blog.sourceTripId)
                        viewModel.recenterToTrip(item.blog)
                    }
                }
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("Search city or blog title", text: $viewModel.searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
            
            if isSearchActive {
                Button {
                    withAnimation {
                        viewModel.searchText = ""
                        isSearchFocused = false
                        isSearchActive = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
    
    @State private var scrolledTripID: UUID?

    private var bottomTripList: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.80, 340)
            let cardHeight: CGFloat = 104
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.visibleTrips, id: \.sourceTripId) { trip in
                        ProfileMapCardView(
                            blog: trip,
                            isSelected: viewModel.selectedTripID == trip.sourceTripId,
                            onTap: {
                                // Card tap always navigates to the blog
                                selectedBlogForNavigation = trip
                            },
                            onNavigate: {
                                selectedBlogForNavigation = trip
                            }
                        )
                        .id(trip.sourceTripId)
                        .frame(width: cardWidth, height: cardHeight)
                        .scaleEffect(viewModel.selectedTripID == trip.sourceTripId ? 1.0 : 0.95)
                        .opacity(viewModel.selectedTripID == trip.sourceTripId ? 1.0 : 0.6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedTripID)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, (geo.size.width - cardWidth) / 2)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledTripID)
            .onChange(of: scrolledTripID) { _, newID in
                if let id = newID, viewModel.selectedTripID != id {
                    if let trip = viewModel.visibleTrips.first(where: { $0.sourceTripId == id }) {
                        withAnimation {
                            viewModel.selectTrip(id)
                            viewModel.recenterToTrip(trip)
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedTripID) { _, newID in
                if let id = newID {
                    scrolledTripID = id
                }
            }
        }
        .frame(height: 124)
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

// MARK: - Safe Collection Subscript (shared by map views)

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - ProfileMapCardView (Bottom List Item)
private struct ProfileMapCardView: View {
    let blog: CreatedRecapBlog
    let isSelected: Bool
    let onTap: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                coverImage
                
                VStack(alignment: .leading, spacing: 4) {
                    tripInfo
                }
                .padding(.vertical, 12)
                
                Spacer()
                
                chevronButton
                    .padding(.trailing, 12)
            }
            .frame(height: 104)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var coverImage: some View {
        TripCoverImage(
            theme: blog.coverImageName,
            coverAssetIdentifier: blog.coverAssetIdentifier,
            targetSize: CGSize(width: 200, height: 200)
        )
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipped()
    }

    private var tripInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(blog.title)
                .font(.system(.subheadline, design: .serif))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 4) {
                if let country = blog.countryName {
                    Text(country)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(blog.tripDateRangeText ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            if let caption = blog.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private var chevronButton: some View {
        Button(action: onNavigate) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
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
                coverAssetIdentifier: blog.coverAssetIdentifier,
                targetSize: CGSize(width: 104, height: 144)
            )
            .frame(width: Self.width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.6), lineWidth: isSelected ? 3 : 1.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)

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
    @State private var selectedBlogForNavigation: CreatedRecapBlog?

    init(countryName: String, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        self.countryName = countryName
        _selectedCreatedRecap = selectedCreatedRecap
        _viewModel = StateObject(wrappedValue: ProfileMapViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        Map(position: $mapPosition) {
            ForEach(viewModel.tripsWithCoordinates, id: \.blog.sourceTripId) { item in
                annotation(for: item)
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
            withAnimation {
                mapPosition = .region(viewModel.mapRegion)
            }
        }
        .navigationDestination(item: $selectedBlogForNavigation) { blog in
            RecapBlogPageView(
                blogId: blog.sourceTripId,
                initialTrip: _createdRecapStore.wrappedValue.tripDraft(for: blog.sourceTripId)
            )
        }
    }

    @MapContentBuilder
    private func annotation(for item: (blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)) -> some MapContent {
        Annotation("", coordinate: item.coordinate) {
            TripAnnotationView(
                blog: item.blog,
                isSelected: viewModel.selectedTripID == item.blog.sourceTripId
            )
            .onTapGesture {
                viewModel.selectTrip(item.blog.sourceTripId)
                selectedBlogForNavigation = item.blog
            }
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
