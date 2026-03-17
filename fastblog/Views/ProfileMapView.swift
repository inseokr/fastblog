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
    
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = StateObject(wrappedValue: ProfileMapViewModel(createdRecapStore: createdRecapStore))
        _selectedCreatedRecap = selectedCreatedRecap
    }

    var body: some View {
        Group {
            if isSearchActive {
                // Full-screen navy search experience
                searchOverlay
            } else {
                ZStack(alignment: .bottom) {
                    profileMap
                    
                    VStack {
                        countryFilterBar
                        Spacer()
                    }
                    
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
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if isSearchActive {
                            // Back out of search mode
                            isSearchActive = false
                            viewModel.searchText = ""
                            isSearchFocused = false
                        } else {
                            // Enter search mode
                            isSearchActive = true
                            isSearchFocused = true
                        }
                    }
                } label: {
                    if isSearchActive {
                        Text("Back")
                            .font(.body.weight(.semibold))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.primary)
                    }
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
        .ignoresSafeArea(edges: .bottom)
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
                    // Already selected — second tap opens the blog via global overlay (fade).
                    selectedCreatedRecap = item.blog
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
    
    // MARK: - Search Overlay
    
    private var searchOverlay: some View {
        ZStack {
            // Deep navy background to create clean space for results
            Color(red: 5/255, green: 10/255, blue: 48/255)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Search field pinned near top
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))
                    TextField("Search city or blog title", text: $viewModel.searchText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                    
                    if !viewModel.searchText.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.searchText = ""
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
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Autocomplete results
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        let results = viewModel.visibleTrips
                        if results.isEmpty {
                            VStack(spacing: 8) {
                                Text("Search by city or blog title")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.75))
                                Text("Start typing to quickly jump into a blog on the map.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
                            .padding(.top, 24)
                        } else {
                            ForEach(results, id: \.sourceTripId) { trip in
                                Button {
                                    // Open selected blog and dismiss search
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        selectedCreatedRecap = trip
                                        isSearchFocused = false
                                        isSearchActive = false
                                    }
                                } label: {
                                    ProfileMapCardView(
                                        blog: trip,
                                        isSelected: false,
                                        onTap: {},
                                        onNavigate: {}
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
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
                                // Open blog via global overlay (fade)
                                selectedCreatedRecap = trip
                            },
                            onNavigate: {
                                selectedCreatedRecap = trip
                            }
                        )
                        .id(trip.sourceTripId)
                        .frame(width: cardWidth, height: cardHeight)
                        .scaleEffect(viewModel.selectedTripID == trip.sourceTripId ? 1.0 : 0.95)
                        .opacity(viewModel.selectedTripID == trip.sourceTripId ? 1.0 : 0.6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedTripID)
                    }
                }
                .padding(.vertical, 10)
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
        .frame(height: 144)
        .padding(.bottom, 24)
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
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 4) {
                if let country = blog.countryName {
                    Text(country)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.85))
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Trip duration (and places) directly under the country info
            Text("\(blog.totalPlaceVisitCount) Place\(blog.totalPlaceVisitCount == 1 ? "" : "s") • \(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            if let caption = blog.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
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
    let blogs: [CreatedRecapBlog]
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedTripID: UUID?
    @State private var scrolledTripID: UUID?
    @State private var isSearchActive = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    init(countryName: String, blogs: [CreatedRecapBlog], selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        self.countryName = countryName
        self.blogs = blogs
        _selectedCreatedRecap = selectedCreatedRecap
    }

    /// Sorted blogs (most recent first) — same order the list uses.
    private var sortedBlogs: [CreatedRecapBlog] {
        blogs.sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }
    }

    /// Blogs filtered by search text for the country map search overlay.
    private var filteredBlogs: [CreatedRecapBlog] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedBlogs }
        return sortedBlogs.filter { blog in
            blog.title.lowercased().contains(query)
                || (blog.countryName?.lowercased().contains(query) ?? false)
        }
    }

    private var tripsWithCoordinates: [(blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)] {
        sortedBlogs.compactMap { blog in
            guard let coord = createdRecapStore.coordinate(for: blog.sourceTripId) else { return nil }
            return (blog, coord)
        }
    }

    var body: some View {
        Group {
            if isSearchActive {
                countrySearchOverlay
            } else {
                ZStack(alignment: .bottom) {
                    // Full-screen map
                    Map(position: $mapPosition) {
                        ForEach(tripsWithCoordinates, id: \.blog.sourceTripId) { item in
                            annotation(for: item)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .ignoresSafeArea(edges: .bottom)

                    // Bottom blog card strip
                    if !sortedBlogs.isEmpty {
                        bottomBlogStrip
                    }
                }
            }
        }
        .navigationTitle(displayCountryName(countryName))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if isSearchActive {
                            // Back out of search mode
                            isSearchActive = false
                            searchText = ""
                            isSearchFocused = false
                        } else {
                            // Enter search mode
                            isSearchActive = true
                            isSearchFocused = true
                        }
                    }
                } label: {
                    if isSearchActive {
                        Text("Back")
                            .font(.body.weight(.semibold))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            let first = sortedBlogs.first
            if let first, let coord = createdRecapStore.coordinate(for: first.sourceTripId) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                ))
            } else if tripsWithCoordinates.isEmpty {
                mapPosition = .automatic
            }
            selectedTripID = first?.sourceTripId
            scrolledTripID = first?.sourceTripId
        }
    }

    // MARK: - Bottom blog card strip

    private var bottomBlogStrip: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.80, 340)
            let cardHeight: CGFloat = 104

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(sortedBlogs, id: \.sourceTripId) { blog in
                        ProfileMapCardView(
                            blog: blog,
                            isSelected: selectedTripID == blog.sourceTripId,
                            onTap: {
                                // Open blog via global overlay (fade) when card is tapped.
                                selectedCreatedRecap = blog
                            },
                            onNavigate: {
                                selectedCreatedRecap = blog
                            }
                        )
                        .id(blog.sourceTripId)
                        .frame(width: cardWidth, height: cardHeight)
                        .scaleEffect(selectedTripID == blog.sourceTripId ? 1.0 : 0.95)
                        .opacity(selectedTripID == blog.sourceTripId ? 1.0 : 0.6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTripID)
                    }
                }
                .padding(.vertical, 10)
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, (geo.size.width - cardWidth) / 2)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledTripID)
            // Scrolling a card → select it and re-center the map
            .onChange(of: scrolledTripID) { _, newID in
                guard let newID, selectedTripID != newID else { return }
                if let blog = sortedBlogs.first(where: { $0.sourceTripId == newID }),
                   let coord = createdRecapStore.coordinate(for: newID) {
                    withAnimation {
                        selectedTripID = newID
                        mapPosition = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                        ))
                    }
                    _ = blog // suppress unused warning if needed
                }
            }
            // Tapping a map annotation → scroll the card strip to match
            .onChange(of: selectedTripID) { _, newID in
                if let newID { scrolledTripID = newID }
            }
        }
        .frame(height: 144)
        .padding(.bottom, 24)
    }

    // MARK: - Country search overlay

    private var countrySearchOverlay: some View {
        ZStack {
            // Deep navy background, matching My Blogs search UX
            Color(red: 5/255, green: 10/255, blue: 48/255)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Search field at top
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))
                    TextField("Search blogs in \(displayCountryName(countryName))", text: $searchText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)

                    if !searchText.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                searchText = ""
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
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Filtered results for this country
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        let results = filteredBlogs
                        if results.isEmpty {
                            VStack(spacing: 8) {
                                Text("No blogs match your search")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                Text("Try a different city or title.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
                            .padding(.top, 24)
                        } else {
                            ForEach(results, id: \.sourceTripId) { blog in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        selectedCreatedRecap = blog
                                        isSearchFocused = false
                                        isSearchActive = false
                                    }
                                } label: {
                                    ProfileMapCardView(
                                        blog: blog,
                                        isSelected: false,
                                        onTap: {},
                                        onNavigate: {}
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Map annotation

    @MapContentBuilder
    private func annotation(for item: (blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)) -> some MapContent {
        Annotation("", coordinate: item.coordinate) {
            TripAnnotationView(
                blog: item.blog,
                isSelected: selectedTripID == item.blog.sourceTripId
            )
            .onTapGesture {
                if selectedTripID == item.blog.sourceTripId {
                    // Second tap → open blog via global overlay (fade).
                    selectedCreatedRecap = item.blog
                } else {
                    // First tap → select + re-center
                    withAnimation {
                        selectedTripID = item.blog.sourceTripId
                        mapPosition = .region(MKCoordinateRegion(
                            center: item.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                        ))
                    }
                }
            }
        }
    }

    private func displayCountryName(_ name: String) -> String {
        name.isEmpty || name == "Unknown" ? "Other" : name
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
