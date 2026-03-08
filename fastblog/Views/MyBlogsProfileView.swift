//
//  MyBlogsProfileView.swift
//  Capper
//
//  My Blogs: dark blue background, vertical list of Country Cards, fixed search bar and My Map button.
//

import SwiftUI

// MARK: - Page enum
private enum MyBlogsPage: Equatable {
    case blogs
    case country(CountrySection)
    case places
}

private let searchBarHeight: CGFloat = 56
private let myMapButtonSize: CGFloat = 52
private let cardSpacing: CGFloat = 16
private let horizontalPadding: CGFloat = 20

private struct MyBlogsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct PlaceVisitedMiniCard: View {
    let place: VisitedPlaceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let hero = place.heroPhoto {
                    RecapPhotoThumbnail(photo: hero, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 520, height: 520))
                        .frame(width: 140, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Color.white.opacity(0.12)
                        .frame(width: 140, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.white.opacity(0.5))
                        }
                }

                if place.photos.count > 1 {
                    Text("+\(max(0, place.photos.count - 1))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(place.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(place.cityDisplay ?? place.country)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
        .padding(10)
        .background(Color.white.opacity(0.10))
        .cornerRadius(14)
    }
}

struct MyBlogsProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @StateObject private var viewModel = MyBlogsProfileViewModel()
    // Page navigation (ZStack-based, bottom bar persists across all pages)
    @State private var currentPage: MyBlogsPage = .blogs
    @State private var sharedSearchText: String = ""

    // Per-page map destinations
    @State private var showMyMap = false
    @State private var showCountryMap: Bool = false
    @State private var showPlacesMap: Bool = false

    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var showManage = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var selectedUnsavedTripPhotos: TripDraft?
    @State private var createBlogFlowTrip: TripDraft?
    @State private var scrollOffset: CGFloat = 0

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _selectedCreatedRecap = selectedCreatedRecap
    }

    private let backgroundBlue = Color(red: 0.05, green: 0.08, blue: 0.22)

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundBlue.ignoresSafeArea()

            // ── Active page content ──────────────────────────────────────
            pageContent

            // ── Persistent bottom bar (always visible) ───────────────────
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    MyMapButton {
                        isSearchFocused = false
                        switch currentPage {
                        case .blogs:   showMyMap = true
                        case .country: showCountryMap = true
                        case .places:  showPlacesMap.toggle()
                        }
                    }
                    .padding(.trailing, horizontalPadding)
                    .padding(.bottom, 16)
                }
                adaptiveSearchBar
            }
            .allowsHitTesting(true)
        }
        .simultaneousGesture(
            DragGesture().onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                if currentPage == .blogs {
                    // Swipe down to dismiss My Blogs
                    if !isHorizontal && scrollOffset >= -20 && value.translation.height > 60 {
                        dismiss()
                    }
                } else {
                    // Swipe right to go back to blogs page
                    if isHorizontal && value.translation.width > 60 {
                        switch currentPage {
                        case .country:
                            break
                        case .places:
                            withAnimation(.easeInOut(duration: 0.26)) { currentPage = .blogs }
                        case .blogs:
                            break
                        }
                    }
                }
            }
        )
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                switch currentPage {
                case .blogs:
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                case .country, .places:
                    Button {
                        isSearchFocused = false
                        withAnimation(.easeInOut(duration: 0.26)) {
                            currentPage = .blogs
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            // Manage — only on blogs page (sub-pages add their own toolbar items)
            if case .blogs = currentPage {
                ToolbarItem(placement: .primaryAction) {
                    Button("Manage") {
                        isSearchFocused = false
                        showManage = true
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(item: $selectedPlaceForModal) { place in
            placeModalSheet(place: place)
        }
        .navigationDestination(isPresented: $showMyMap) {
            MyMapView(selectedCreatedRecap: $selectedCreatedRecap)
        }
        .navigationDestination(item: $selectedCreatedRecap) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
            )
        }
        .navigationDestination(item: $createBlogFlowTrip) { trip in
            CreateBlogFlowView(trip: trip, startDirectlyCreating: true) { _ in
                createBlogFlowTrip = nil
                viewModel.loadUnsavedTrips()
            }
            .environmentObject(createdRecapStore)
        }
        .navigationDestination(item: $selectedUnsavedTripPhotos) { trip in
            UnsavedTripPhotosView(trip: trip) {
                selectedUnsavedTripPhotos = nil
                createBlogFlowTrip = trip
            }
        }
        .sheet(isPresented: $showManage) {
            MyBlogsManageSheet { recap in
                showManage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedCreatedRecap = recap
                }
            }
            .environmentObject(createdRecapStore)
        }
        .onAppear { viewModel.loadUnsavedTrips() }
        .onChange(of: currentPage) { _, _ in
            sharedSearchText = ""
            viewModel.searchText = ""
            isSearchActive = false
            showPlacesMap = false
        }
        .onChange(of: sharedSearchText) { _, newValue in
            if case .blogs = currentPage { viewModel.searchText = newValue }
        }
    }

    // MARK: - Page routing

    private var pageTitle: String {
        switch currentPage {
        case .blogs: return "My Blogs"
        case .country(let section): return section.countryName.isEmpty || section.countryName == "Unknown" ? "Other" : section.countryName
        case .places: return "Places Visited"
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .blogs:
            blogsScrollView
        case .country(let section):
            CountryBlogsView(
                section: section,
                selectedBlog: $selectedCreatedRecap,
                showMap: $showCountryMap,
                searchText: $sharedSearchText
            )
            .environmentObject(createdRecapStore)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .places:
            PlacesVisitedView(
                searchText: $sharedSearchText,
                showPlacesMap: $showPlacesMap
            )
            .environmentObject(createdRecapStore)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var blogsScrollView: some View {
        ScrollView(showsIndicators: false) {
            let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
            let sections = viewModel.filteredSections(from: allSections)
            Group {
                if false && !isSearchActive && !viewModel.unsavedTrips.isEmpty {
                    unsavedTripsSection
                }
                if !isSearchActive && !createdRecapStore.visitedPlaces.isEmpty {
                    placesVisitedSection
                }
                if false && !isSearchActive && !createdRecapStore.visibleRecents.isEmpty {
                    recentBlogsSection
                }
                if isSearchActive && !viewModel.isSearching {
                    VStack(spacing: 12) {
                        Text("Search by city or blog title")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else if sections.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: cardSpacing) {
                        ForEach(sections) { section in
                            CountryCardView(section: section) {
                                isSearchFocused = false
                                withAnimation(.easeInOut(duration: 0.26)) {
                                    currentPage = .country(section)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: MyBlogsScrollOffsetKey.self, value: proxy.frame(in: .named("MyBlogsScroll")).minY)
            })
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, searchBarHeight + myMapButtonSize + 24)
        }
        .coordinateSpace(name: "MyBlogsScroll")
        .onPreferenceChange(MyBlogsScrollOffsetKey.self) { value in scrollOffset = value }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    // MARK: - Persistent bottom bar

    private var adaptiveSearchBar: some View {
        let placeholder: String
        let isDark: Bool
        switch currentPage {
        case .blogs:   placeholder = "Search city or blog title"; isDark = true
        case .country: placeholder = "Search blog title";          isDark = false
        case .places:  placeholder = "Search places";               isDark = false
        }
        return HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isDark ? .white.opacity(0.7) : .secondary)
            TextField(placeholder, text: $sharedSearchText)
                .foregroundColor(isDark ? .white : .primary)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture { isSearchActive = true }
            if isSearchActive {
                Button {
                    sharedSearchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: searchBarHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 12)
    }

    // "Recent Blogs" horizontal scroll matching the home page style
    private var placesVisitedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Places Visited")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.26)) { currentPage = .places }
                } label: {
                    Text("View All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(createdRecapStore.visitedPlaces.prefix(10)) { place in
                        Button {
                            selectedPlaceForModal = place
                        } label: {
                            PlaceVisitedMiniCard(place: place)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(height: 178)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func placeModalSheet(place: VisitedPlaceSummary) -> some View {
        let photos = place.photos
        if let initialPhotoId = photos.first?.id {
            PlacePhotoModalView(
                placeTitle: Binding(
                    get: { place.displayName },
                    set: { _ in }
                ),
                placeSubtitle: place.cityDisplay ?? place.country,
                photos: photos,
                initialPhotoId: initialPhotoId,
                stopDigitizedTime: nil,
                blogIsEditMode: false,
                photoCaption: { photoId in
                    let caption = photos.first(where: { $0.id == photoId })?.caption ?? ""
                    return Binding(
                        get: { caption },
                        set: { _ in }
                    )
                },
                onDismiss: { selectedPlaceForModal = nil },
                onViewBlog: {
                    guard let blogId = place.relatedBlogs.first?.blogId,
                          let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == blogId }) else { return }
                    selectedPlaceForModal = nil
                    selectedCreatedRecap = recap
                },
                onRemovePhoto: { photoId in
                    createdRecapStore.removePhotoFromBlog(photoId: photoId)
                    selectedPlaceForModal = nil
                }
            )
            .presentationDetents([.large])
        } else {
            Color.clear.onAppear { selectedPlaceForModal = nil }
        }
    }

    private var recentBlogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Blogs")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(createdRecapStore.displayRecents.prefix(10)) { recap in
                        Button {
                            selectedCreatedRecap = recap
                        } label: {
                            RecentBlogCard(recap: recap)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(height: 128)
        }
        .padding(.bottom, 8)
    }

    private var unsavedTripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trips Not Saved Yet")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation { viewModel.dismissAllUnsavedTrips() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.unsavedTrips) { trip in
                        UnsavedTripCard(trip: trip) {
                            selectedUnsavedTripPhotos = trip
                        }
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No recap blogs yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
            Text("Create one from a trip to see it here by country.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

}

private struct MyMapButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "map.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: myMapButtonSize, height: myMapButtonSize)
                .background(Color.blue)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Blog Card (horizontal scroll item)

private struct RecentBlogCard: View {
    let recap: CreatedRecapBlog
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showRemoveCloudPopup = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                AssetPhotoView(
                    assetIdentifier: recap.coverAssetIdentifier ?? recap.coverImageName,
                    cornerRadius: 10,
                    targetSize: CGSize(width: 200, height: 200)
                )
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if recap.lastEditedAt == nil {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                } else {
                    if createdRecapStore.isBlogInCloud(blogId: recap.sourceTripId) {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.green))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showRemoveCloudPopup = true
                            }
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(4)
                            .background(Circle().fill(Color.white))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recap.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let dateText = recap.tripDateRangeText {
                    Text(dateText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .padding(10)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup) {
            Button("Yes", role: .destructive) {
                createdRecapStore.removeFromCloud(blogId: recap.sourceTripId)
            }
            Button("No", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove this blog from the cloud?")
        }
    }
}

// MARK: - Manage Sheet (all countries)

private struct MyBlogsManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    var onBlogSelected: (CreatedRecapBlog) -> Void
    @State private var blogPendingRemoval: CreatedRecapBlog?
    @State private var showRemoveAlert = false
    @State private var removedBlogIDs: Set<UUID> = []

    // Merge / Split navigation
    @State private var showMergeView = false
    @State private var showSplitView = false
    @State private var selectedCountryForAction: String?

    private var countryNames: [String] {
        sections.map(\.country).sorted()
    }

    private var sections: [(country: String, blogs: [CreatedRecapBlog])] {
        let active = createdRecapStore.visibleRecents.filter { !removedBlogIDs.contains($0.id) }
        let grouped = Dictionary(grouping: active) { $0.countryName ?? "Unknown" }
        return grouped.map { (country: $0.key, blogs: $0.value.sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }) }
            .sorted { $0.country < $1.country }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                            .padding(.bottom, 4)
                        Text("Manage Blogs")
                            .font(.system(.title2, design: .serif).weight(.medium))
                        Text("Remove blog from your device")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                    // Country sections
                    if sections.isEmpty {
                        Text("No local blogs to manage.")
                            .foregroundColor(.secondary)
                            .padding(.top, 24)
                    } else {
                        ForEach(sections, id: \.country) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.country)
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                LazyVStack(spacing: 10) {
                                    ForEach(section.blogs) { blog in
                                        Button {
                                            onBlogSelected(blog)
                                        } label: {
                                            CountryManageRow(
                                                blog: blog,
                                                isInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                                                isRemoved: removedBlogIDs.contains(blog.id),
                                                onRemove: {
                                                    blogPendingRemoval = blog
                                                    showRemoveAlert = true
                                                }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if countryNames.count == 1, let only = countryNames.first {
                            Button {
                                selectedCountryForAction = only
                                showMergeView = true
                            } label: {
                                Label("Merge Blogs", systemImage: "arrow.triangle.merge")
                            }
                            Button {
                                selectedCountryForAction = only
                                showSplitView = true
                            } label: {
                                Label("Split Blog", systemImage: "scissors")
                            }
                        } else {
                            Menu {
                                ForEach(countryNames, id: \.self) { country in
                                    Button(country) {
                                        selectedCountryForAction = country
                                        showMergeView = true
                                    }
                                }
                            } label: {
                                Label("Merge Blogs", systemImage: "arrow.triangle.merge")
                            }
                            Menu {
                                ForEach(countryNames, id: \.self) { country in
                                    Button(country) {
                                        selectedCountryForAction = country
                                        showSplitView = true
                                    }
                                }
                            } label: {
                                Label("Split Blog", systemImage: "scissors")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationDestination(isPresented: $showMergeView) {
                if let country = selectedCountryForAction {
                    MergeBlogsView(countryName: country)
                        .environmentObject(createdRecapStore)
                }
            }
            .navigationDestination(isPresented: $showSplitView) {
                if let country = selectedCountryForAction {
                    SplitBlogView(countryName: country)
                        .environmentObject(createdRecapStore)
                }
            }
            .alert(
                "Remove from this device?",
                isPresented: $showRemoveAlert,
                presenting: blogPendingRemoval
            ) { blog in
                Button("Remove", role: .destructive) {
                    createdRecapStore.removeLocalCopy(sourceTripId: blog.sourceTripId)
                    _ = withAnimation { removedBlogIDs.insert(blog.id) }
                    blogPendingRemoval = nil
                    let g = UINotificationFeedbackGenerator()
                    g.notificationOccurred(.success)
                }
                Button("Cancel", role: .cancel) { blogPendingRemoval = nil }
            } message: { _ in
                Text("This removes the blog from local storage. Your cloud blog stays available.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        MyBlogsProfileView(
            createdRecapStore: CreatedRecapBlogStore.shared,
            selectedCreatedRecap: .constant(nil)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
