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
    @State private var mapPosition: MapCameraPosition

    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        let vm = ProfileMapViewModel(createdRecapStore: createdRecapStore)
        _viewModel = StateObject(wrappedValue: vm)
        _mapPosition = State(initialValue: .region(vm.mapRegion))
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
                            if isSearchFocused {
                                isSearchFocused = false
                            } else {
                                isSearchActive = false
                                viewModel.searchText = ""
                            }
                        } else {
                            isSearchActive = true
                        }
                    }
                } label: {
                    if isSearchActive {
                        Text(isSearchFocused ? "Done" : "Back")
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
            // Use the trip selectedTripID that onAppear() just resolved (first trip
            // with a coordinate), so the card strip scrolls to match the map center.
            scrolledTripID = viewModel.selectedTripID ?? viewModel.visibleTrips.first?.sourceTripId
        }
        .onChange(of: viewModel.mapRegionChangeCounter) { _, _ in
            withAnimation {
                mapPosition = .region(viewModel.mapRegion)
            }
        }
    }

    private var profileMap: some View {
        Map(position: $mapPosition) {
            ForEach(viewModel.clusteredMapItems) { cluster in
                clusterAnnotation(for: cluster)
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
    private func clusterAnnotation(for cluster: TripCluster) -> some MapContent {
        Annotation("", coordinate: cluster.coordinate) {
            if cluster.isCluster {
                TripClusterAnnotationView(
                    cluster: cluster,
                    isSelected: cluster.blogs.contains(where: { $0.sourceTripId == viewModel.selectedTripID })
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        viewModel.mapRegion = MKCoordinateRegion(
                            center: cluster.coordinate,
                            span: MKCoordinateSpan(
                                latitudeDelta: viewModel.mapRegion.span.latitudeDelta / 3,
                                longitudeDelta: viewModel.mapRegion.span.longitudeDelta / 3
                            )
                        )
                        viewModel.mapRegionChangeCounter += 1
                    }
                }
            } else {
                TripAnnotationView(
                    blog: cluster.representative,
                    isSelected: viewModel.selectedTripID == cluster.representative.sourceTripId
                )
                .onTapGesture {
                    let blog = cluster.representative
                    if viewModel.selectedTripID == blog.sourceTripId {
                        selectedCreatedRecap = blog
                    } else {
                        withAnimation {
                            viewModel.selectTrip(blog.sourceTripId)
                            viewModel.recenterToTrip(blog)
                        }
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
                .background(Color.white.opacity(0.09), in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
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
                                ProfileMapCardView(
                                    blog: trip,
                                    isSelected: false,
                                    onTap: {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            selectedCreatedRecap = trip
                                            isSearchFocused = false
                                            isSearchActive = false
                                        }
                                    },
                                    onNavigate: {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            selectedCreatedRecap = trip
                                            isSearchFocused = false
                                            isSearchActive = false
                                        }
                                    },
                                    showsTrailingNavigateButton: false
                                )
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
            let cardWidth = min(geo.size.width * 0.90, 384)
            let cardHeight = ProfileMapCarouselLayout.cardHeight

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
        .frame(height: ProfileMapCarouselLayout.stripHeight)
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

// MARK: - Profile map bottom carousel layout

private enum ProfileMapCarouselLayout {
    static let cardHeight: CGFloat = 126
    /// Vertical padding inside the horizontal `ScrollView` (10 × 2) plus card height.
    static let stripHeight: CGFloat = cardHeight + 40
}

// MARK: - Safe Collection Subscript (shared by map views)

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Map card location (city / country)

private func profileMapTrimmedLine(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

/// City for map cards: from the linked trip draft’s photo-location vote; omits placeholders and duplicates of country.
private func profileMapCardCityLine(blog: CreatedRecapBlog, trip: TripDraft?) -> String? {
    guard let trip else { return nil }
    let raw = trip.cityWithMostPhotosDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    let placeholders: Set<String> = ["New Place", "Unknown Place"]
    if placeholders.contains(raw) { return nil }
    if let country = profileMapTrimmedLine(blog.countryName),
       raw.caseInsensitiveCompare(country) == .orderedSame {
        return nil
    }
    return raw
}

// MARK: - ProfileMapCardView (Bottom List Item)
private struct ProfileMapCardView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    let blog: CreatedRecapBlog
    let isSelected: Bool
    let onTap: () -> Void
    let onNavigate: () -> Void
    /// Map search rows open the blog from the outer `Button`; hide the non-functional chevron-in-circle affordance.
    var showsTrailingNavigateButton: Bool = true

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                coverImage

                VStack(alignment: .leading, spacing: 4) {
                    tripInfo
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)

                if showsTrailingNavigateButton {
                    chevronButton
                }
            }
            .padding(.horizontal, 12)
            .frame(height: ProfileMapCarouselLayout.cardHeight)
            .background(.ultraThinMaterial)
            .appChromeCornerRadius(20)
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 20)
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
        .clipShape(RoundedRectangle(appChromeBaseRadius: 20, style: .continuous))
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

            let trip = createdRecapStore.tripDraft(for: blog.sourceTripId)
            let cityLine = profileMapCardCityLine(blog: blog, trip: trip)
            let countryLine = profileMapTrimmedLine(blog.countryName)

            Group {
                if let cityLine, let countryLine, cityLine.caseInsensitiveCompare(countryLine) != .orderedSame {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cityLine)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(countryLine)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let cityLine {
                    Text(cityLine)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let countryLine {
                    Text(countryLine)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Trip duration (and places) directly under the country info
            Text("\(blog.totalPlaceVisitCount) Place\(blog.totalPlaceVisitCount == 1 ? "" : "s") • \(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let caption = blog.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
            .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.6), lineWidth: isSelected ? 3 : 1.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)

            Text(blog.title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 118)
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
    /// Cleared whenever a blog is opened from this map (read-only), so a prior "Edit Blog" flag is not reused.
    @Binding var openRecapInEditMode: Bool
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedTripID: UUID?
    @State private var scrolledTripID: UUID?
    @State private var isSearchActive = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var mapSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    @State private var mapCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    init(
        countryName: String,
        blogs: [CreatedRecapBlog],
        selectedCreatedRecap: Binding<CreatedRecapBlog?>,
        openRecapInEditMode: Binding<Bool> = .constant(false)
    ) {
        self.countryName = countryName
        self.blogs = blogs
        _selectedCreatedRecap = selectedCreatedRecap
        _openRecapInEditMode = openRecapInEditMode
    }

    private func openBlogFromMap(_ blog: CreatedRecapBlog) {
        openRecapInEditMode = false
        selectedCreatedRecap = blog
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
            if blog.title.lowercased().contains(query) { return true }
            if blog.countryName?.lowercased().contains(query) ?? false { return true }
            guard let trip = createdRecapStore.tripDraft(for: blog.sourceTripId) else { return false }
            let city = trip.cityWithMostPhotosDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let drop: Set<String> = ["", "new place", "unknown place"]
            guard !drop.contains(city) else { return false }
            return city.contains(query)
        }
    }

    private var tripsWithCoordinates: [(blog: CreatedRecapBlog, coordinate: CLLocationCoordinate2D)] {
        sortedBlogs.compactMap { blog in
            guard let coord = createdRecapStore.coordinate(for: blog.sourceTripId) else { return nil }
            return (blog, coord)
        }
    }

    private var clusteredItems: [TripCluster] {
        clusterTrips(tripsWithCoordinates, span: mapSpan)
    }

    var body: some View {
        Group {
            if isSearchActive {
                countrySearchOverlay
            } else {
                ZStack(alignment: .bottom) {
                    // Full-screen map
                    Map(position: $mapPosition) {
                        ForEach(clusteredItems) { cluster in
                            countryClusterAnnotation(for: cluster)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .ignoresSafeArea(edges: .bottom)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        mapSpan = context.region.span
                        mapCenter = context.region.center
                    }
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
                            if isSearchFocused {
                                isSearchFocused = false
                            } else {
                                isSearchActive = false
                                searchText = ""
                            }
                        } else {
                            isSearchActive = true
                        }
                    }
                } label: {
                    if isSearchActive {
                        Text(isSearchFocused ? "Done" : "Back")
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
            let cardWidth = min(geo.size.width * 0.90, 384)
            let cardHeight = ProfileMapCarouselLayout.cardHeight

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(sortedBlogs, id: \.sourceTripId) { blog in
                        ProfileMapCardView(
                            blog: blog,
                            isSelected: selectedTripID == blog.sourceTripId,
                            onTap: {
                                // Open blog via global overlay (fade) when card is tapped.
                                openBlogFromMap(blog)
                            },
                            onNavigate: {
                                openBlogFromMap(blog)
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
        .frame(height: ProfileMapCarouselLayout.stripHeight)
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
                .background(Color.white.opacity(0.09), in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
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
                                ProfileMapCardView(
                                    blog: blog,
                                    isSelected: false,
                                    onTap: {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            openBlogFromMap(blog)
                                            isSearchFocused = false
                                            isSearchActive = false
                                        }
                                    },
                                    onNavigate: {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            openBlogFromMap(blog)
                                            isSearchFocused = false
                                            isSearchActive = false
                                        }
                                    },
                                    showsTrailingNavigateButton: false
                                )
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
                    openBlogFromMap(item.blog)
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

    @MapContentBuilder
    private func countryClusterAnnotation(for cluster: TripCluster) -> some MapContent {
        Annotation("", coordinate: cluster.coordinate) {
            if cluster.isCluster {
                TripClusterAnnotationView(
                    cluster: cluster,
                    isSelected: cluster.blogs.contains(where: { $0.sourceTripId == selectedTripID })
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        mapPosition = .region(MKCoordinateRegion(
                            center: cluster.coordinate,
                            span: MKCoordinateSpan(
                                latitudeDelta: max(0.001, mapSpan.latitudeDelta / 3),
                                longitudeDelta: max(0.001, mapSpan.longitudeDelta / 3)
                            )
                        ))
                    }
                }
            } else {
                TripAnnotationView(
                    blog: cluster.representative,
                    isSelected: selectedTripID == cluster.representative.sourceTripId
                )
                .onTapGesture {
                    let blog = cluster.representative
                    if selectedTripID == blog.sourceTripId {
                        openBlogFromMap(blog)
                    } else {
                        withAnimation {
                            selectedTripID = blog.sourceTripId
                            if let coord = createdRecapStore.coordinate(for: blog.sourceTripId) {
                                mapPosition = .region(MKCoordinateRegion(
                                    center: coord,
                                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Zoom Controls (CountryMapView)

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
