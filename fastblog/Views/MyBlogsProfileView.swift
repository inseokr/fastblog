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

struct MyBlogsProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialDayIndexForRecap: Int?
    /// Passed to `CountryBlogsView` for kebab "Edit Blog"; consumed by root `RecapBlogPageView` as `forceEditMode`.
    @Binding var openRecapInEditMode: Bool
    /// Passed to `CountryBlogsView` for kebab "Share Blog"; consumed by `RecapBlogPageView` as `forcePresentShareYourBlogSheet`.
    @Binding var openRecapPresentShareYourBlogSheet: Bool
    @ObservedObject var tripsViewModel: TripsViewModel
    /// Called when user taps "View" on new-moments alert so the parent can dismiss the fullScreenCover.
    var onDismissCover: (() -> Void)? = nil
    /// Reports whether the visible scroll is at top (for swipe-to-dismiss gating).
    var onTopScrollStateChange: ((Bool) -> Void)? = nil
    @StateObject private var viewModel = MyBlogsProfileViewModel()
    // Page navigation (ZStack-based, bottom bar persists across all pages)
    @State private var currentPage: MyBlogsPage = .blogs
    @State private var sharedSearchText: String = ""

    // Per-page map destinations
    @State private var showMyMap = false
    @State private var showCountryMap: Bool = false
    @State private var showManage = false
    /// When true, reopen Manage Blogs (all countries) after the recap overlay dismisses.
    @State private var reopenManageSheetAfterRecapDismiss = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var selectedUnsavedTripPhotos: TripDraft?
    @State private var createBlogFlowTrip: TripDraft?
    @State private var scrollOffset: CGFloat = 0
    /// Scroll offset for country page — used for swipe-down-to-dismiss when at top.
    @State private var countryScrollOffset: CGFloat = 0
    /// Mirrors search field focus while on a country page (Manage → Done in `CountryBlogsView`).
    @State private var countrySearchBarFocused = false

    // On-the-go new-moments popup
    @State private var showNewMomentsAlert = false
    @State private var newMomentsAlertBlogTitle = ""
    @State private var newMomentsAlertBlogId: UUID? = nil
    @State private var newMomentsDayIndex: Int? = nil

    init(
        createdRecapStore: CreatedRecapBlogStore,
        selectedCreatedRecap: Binding<CreatedRecapBlog?>,
        initialDayIndexForRecap: Binding<Int?> = .constant(nil),
        openRecapInEditMode: Binding<Bool> = .constant(false),
        openRecapPresentShareYourBlogSheet: Binding<Bool> = .constant(false),
        tripsViewModel: TripsViewModel,
        onDismissCover: (() -> Void)? = nil,
        onTopScrollStateChange: ((Bool) -> Void)? = nil
    ) {
        _selectedCreatedRecap = selectedCreatedRecap
        _initialDayIndexForRecap = initialDayIndexForRecap
        _openRecapInEditMode = openRecapInEditMode
        _openRecapPresentShareYourBlogSheet = openRecapPresentShareYourBlogSheet
        _tripsViewModel = ObservedObject(wrappedValue: tripsViewModel)
        self.onDismissCover = onDismissCover
        self.onTopScrollStateChange = onTopScrollStateChange
    }

    private let backgroundBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

    /// If on-the-go new moments exist for a blog we have, show the alert.
    private func checkForNewMoments() {
        guard OnTheGoTripStore.hasNewMoments,
              let blogId = OnTheGoTripStore.activeBlogId,
              let title = OnTheGoTripStore.activeBlogTitle,
              createdRecapStore.visibleRecents.contains(where: { $0.sourceTripId == blogId }) else { return }
        newMomentsAlertBlogId = blogId
        newMomentsAlertBlogTitle = title
        newMomentsDayIndex = OnTheGoTripStore.newMomentsDayIndex
        showNewMomentsAlert = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundBlue.ignoresSafeArea()

            // ── Active page content ──────────────────────────────────────
            pageContent
                .opacity(isSearchActive && isOnBlogsPage ? 0 : 1)
                .animation(.easeInOut(duration: 0.22), value: isSearchActive)

            // ── Search focus overlay + full blog list (My Blogs only) ─────
            if isSearchActive && isOnBlogsPage {
                // Deep navy background, visually aligned with My Blogs.
                backgroundBlue
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 24) {
                            let results = autocompleteBlogs
                            if results.isEmpty {
                                VStack(spacing: 8) {
                                    Text("Search by city, country, or blog title")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("Start typing to quickly jump into a blog.")
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                            } else {
                                ForEach(results) { blog in
                                    Button {
                                        isSearchFocused = false
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            isSearchActive = false
                                        }
                                        openRecapInEditMode = false
                                        openRecapPresentShareYourBlogSheet = false
                                        selectedCreatedRecap = blog
                                    } label: {
                                        CountryBlogRowView(
                                            blog: blog,
                                            isBlogInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                                            isDraft: !blog.hasCommittedRecapSave,
                                            onRemoveFromCloud: {},
                                            onShareBlog: {},
                                            onEditBlog: {},
                                            onDeleteBlog: {}
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 16)
                        // Leave room for the bottom search bar + map button
                        .padding(.bottom, searchBarHeight + myMapButtonSize + 40)
                    }
                }
                .transition(.opacity)
            }

            // ── Persistent bottom bar (always visible) ───────────────────
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    MyMapButton {
                        isSearchFocused = false
                        switch currentPage {
                        case .blogs:   showMyMap = true
                        case .country: showCountryMap = true
                        }
                    }
                    .padding(.trailing, horizontalPadding)
                    .padding(.bottom, 16)
                }
                adaptiveSearchBar
            }
            .allowsHitTesting(true)
        }
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                switch currentPage {
                case .blogs:
                    Button {
                        isSearchFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onDismissCover?()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                case .country:
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
            // Right-side actions for My Blogs page
            if case .blogs = currentPage {
                ToolbarItem(placement: .primaryAction) {
                    if isSearchActive {
                        Button("Done") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSearchActive = false
                            }
                            sharedSearchText = ""
                            isSearchFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                    } else {
                        Button("Manage") {
                            isSearchFocused = false
                            showManage = true
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showMyMap) {
            MyMapView(selectedCreatedRecap: $selectedCreatedRecap)
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
                reopenManageSheetAfterRecapDismiss = true
                openRecapInEditMode = false
                openRecapPresentShareYourBlogSheet = false
                selectedCreatedRecap = recap
                showManage = false
            }
            .environmentObject(createdRecapStore)
            .presentationDetents([.fraction(1)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedCreatedRecap?.id) { oldValue, newValue in
            guard reopenManageSheetAfterRecapDismiss, oldValue != nil, newValue == nil else { return }
            reopenManageSheetAfterRecapDismiss = false
            showManage = true
        }
        .onAppear {
            viewModel.loadUnsavedTrips()
            checkForNewMoments()
            reportTopScrollState()
        }
        .alert(
            "New moments added to \"\(newMomentsAlertBlogTitle)\"",
            isPresented: $showNewMomentsAlert
        ) {
            Button("View") {
                if let blogId = newMomentsAlertBlogId {
                    createdRecapStore.injectPhotos(
                        tripsViewModel.newlyScannedPhotos,
                        intoSourceTripId: blogId
                    )
                }
                tripsViewModel.clearNewMomentsSignal()
                OnTheGoTripStore.clearNewMoments()
                if let blogId = newMomentsAlertBlogId,
                   let recap = createdRecapStore.displayRecents.first(where: { $0.sourceTripId == blogId }) {
                    initialDayIndexForRecap = newMomentsDayIndex
                    openRecapInEditMode = false
                    selectedCreatedRecap = recap
                    onDismissCover?()
                }
            }
            Button("Ok", role: .cancel) {
                OnTheGoTripStore.clearNewMoments()
            }
        } message: {
            Text("Your trip has new content since you last looked. Tap View to go to the latest day.")
        }
        .onChange(of: currentPage) { _, newPage in
            sharedSearchText = ""
            viewModel.searchText = ""
            isSearchActive = false
            countrySearchBarFocused = false
            if case .country = newPage {
                countryScrollOffset = 0
            }
            reportTopScrollState()
        }
        .onChange(of: sharedSearchText) { _, newValue in
            if case .blogs = currentPage { viewModel.searchText = newValue }
        }
        .onChange(of: scrollOffset) { _, _ in reportTopScrollState() }
        .onChange(of: countryScrollOffset) { _, _ in reportTopScrollState() }
    }

    // MARK: - Page routing

    private var pageTitle: String {
        switch currentPage {
        case .blogs: return "My Blogs"
        case .country(let section): return section.countryName.isEmpty || section.countryName == "Unknown" ? "Other" : section.countryName
        }
    }

    private var isOnBlogsPage: Bool {
        if case .blogs = currentPage { return true }
        return false
    }

    private var isCurrentPageAtTop: Bool {
        switch currentPage {
        case .blogs:
            return scrollOffset >= -2
        case .country:
            return countryScrollOffset >= -2
        }
    }

    private func reportTopScrollState() {
        onTopScrollStateChange?(isCurrentPageAtTop)
    }

    private func attemptCreateBlog(trip: TripDraft) {
        selectedUnsavedTripPhotos = trip
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
                openRecapInEditMode: $openRecapInEditMode,
                openRecapPresentShareYourBlogSheet: $openRecapPresentShareYourBlogSheet,
                showMap: $showCountryMap,
                searchText: $sharedSearchText,
                scrollOffset: $countryScrollOffset,
                isBottomSearchFocused: countrySearchBarFocused,
                onDismissSearchKeyboard: {
                    isSearchFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
            .environmentObject(createdRecapStore)
            .transition(.opacity)
        }
    }

    private var blogsScrollView: some View {
        ScrollView(showsIndicators: false) {
            let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
            let searched = viewModel.filteredSections(from: allSections)
            let sections = searched
            Group {
                if false && !isSearchActive && !viewModel.unsavedTrips.isEmpty {
                    unsavedTripsSection
                }
                if false && !isSearchActive && !createdRecapStore.visibleRecents.isEmpty {
                    recentBlogsSection
                }
                if sections.isEmpty {
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
        .transition(.opacity)
    }

    // MARK: - Persistent bottom bar

    private var adaptiveSearchBar: some View {
        let placeholder: String
        let isDark: Bool
        switch currentPage {
        case .blogs:   placeholder = "Search city or blog title"; isDark = true
        case .country: placeholder = "Search blog title";          isDark = false
        }
        return HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isDark ? .white.opacity(0.7) : .secondary)
            TextField(placeholder, text: $sharedSearchText)
                .foregroundColor(isDark ? .white : .primary)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onChange(of: isSearchFocused) { _, focused in
                    if isOnBlogsPage {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchActive = focused
                        }
                    } else if case .country = currentPage {
                        withAnimation(.easeOut(duration: 0.22)) {
                            countrySearchBarFocused = focused
                        }
                    }
                }
            if isSearchActive {
                Button {
                    sharedSearchText = ""
                    isSearchFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchActive = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: searchBarHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 12)
    }

    /// Autocomplete results used while the bottom search bar is active.
    /// Returns a flat list of blogs across all countries, newest → oldest.
    /// When search is empty, all blogs are shown; otherwise we filter.
    private var autocompleteBlogs: [CreatedRecapBlog] {
        let query = sharedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Use the same underlying data as the My Blogs country view:
        // flatten all country sections into a single newest→oldest list.
        let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
        let allBlogs = allSections.flatMap { $0.blogs }
        let sorted = allBlogs.sorted {
            ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt)
        }

        guard !query.isEmpty else {
            // No text yet → show all blogs, newest first
            return sorted
        }

        return sorted.filter { blog in
            blog.title.lowercased().contains(query)
            || (blog.countryName?.lowercased().contains(query) ?? false)
            || (blog.caption?.lowercased().contains(query) ?? false)
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
                            attemptCreateBlog(trip: trip)
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                AssetPhotoView(
                    assetIdentifier: recap.coverAssetIdentifier ?? recap.coverImageName,
                    cornerRadius: 10,
                    targetSize: CGSize(width: 200, height: 200)
                )
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(appChromeBaseRadius: 10))

                if recap.lastEditedAt == nil {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .appChromeCornerRadius(4)
                        .padding(4)
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
        .appChromeCornerRadius(12)
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
    @State private var selectedCountryFilter: String?

    // Merge / Split — push inside this sheet’s NavigationStack (same as CountryManageBlogsSheet).
    @State private var mergeCountryNav: String?
    @State private var splitCountryNav: String?

    private var countryNames: [String] {
        allSections.map(\.country).sorted()
    }

    private var canSplit: Bool { !countryNames.isEmpty }
    private var canMerge: Bool { allSections.contains { $0.blogs.count >= 2 } }

    private var allSections: [(country: String, blogs: [CreatedRecapBlog])] {
        let active = createdRecapStore.visibleRecents.filter { !removedBlogIDs.contains($0.id) }
        let grouped = Dictionary(grouping: active) { $0.countryName ?? "Unknown" }
        return grouped.map { (country: $0.key, blogs: $0.value.sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }) }
            .sorted { $0.country < $1.country }
    }

    private var sections: [(country: String, blogs: [CreatedRecapBlog])] {
        guard let filter = selectedCountryFilter else { return allSections }
        return allSections.filter { $0.country == filter }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 38))
                                .foregroundColor(.blue)
                                .padding(.bottom, 4)
                            Text("Manage Blogs")
                                .font(.system(.title2, design: .serif).weight(.medium))
                            Text("Remove blogs from this device")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 28)
                        .padding(.bottom, 4)

                        // Country sections
                        if sections.isEmpty {
                            Text("No blogs to manage.")
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
                                            CountryManageRow(
                                                blog: blog,
                                                isInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                                                isDraft: !blog.hasCommittedRecapSave,
                                                isRemoved: removedBlogIDs.contains(blog.id),
                                                onRemove: {
                                                    blogPendingRemoval = blog
                                                    showRemoveAlert = true
                                                },
                                                onOpenBlog: {
                                                    onBlogSelected(blog)
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        Spacer(minLength: 80)
                    }
                }

                // ── Bottom Action Bar ──────────────────────────────────
                VStack {
                    Spacer()
                    HStack {
                        Group {
                            if countryNames.count == 1, let only = countryNames.first {
                                Button { splitCountryNav = only } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "scissors")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                        Text("Split")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                    }
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                                }
                            } else {
                                Menu {
                                    ForEach(countryNames, id: \.self) { country in
                                        Button(country) { splitCountryNav = country }
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "scissors")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                        Text("Split")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                    }
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                                }
                            }
                        }
                        Spacer()
                        Group {
                            if countryNames.count == 1, let only = countryNames.first {
                                Button { mergeCountryNav = only } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.merge")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Color.blue.opacity(canMerge ? 1.0 : 0.38))
                                        Text("Merge")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.blue.opacity(canMerge ? 1.0 : 0.38))
                                    }
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                                }
                            } else {
                                Menu {
                                    ForEach(countryNames, id: \.self) { country in
                                        Button(country) { mergeCountryNav = country }
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.merge")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Color.blue.opacity(canMerge ? 1.0 : 0.38))
                                        Text("Merge")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.blue.opacity(canMerge ? 1.0 : 0.38))
                                    }
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            selectedCountryFilter = nil
                        } label: {
                            Label("All Countries", systemImage: selectedCountryFilter == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(countryNames, id: \.self) { country in
                            Button {
                                selectedCountryFilter = country
                            } label: {
                                Label(country, systemImage: selectedCountryFilter == country ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: selectedCountryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(selectedCountryFilter == nil ? .primary : .blue)
                    }
                }
            }
            .navigationDestination(item: $mergeCountryNav) { country in
                MergeBlogsView(countryName: country)
                    .environmentObject(createdRecapStore)
            }
            .navigationDestination(item: $splitCountryNav) { country in
                SplitBlogView(countryName: country)
                    .environmentObject(createdRecapStore)
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
                Text("This removes the blog from local storage.")
            }
        }
        .tint(.primary)
    }
}

#Preview {
    NavigationStack {
        MyBlogsProfileView(
            createdRecapStore: CreatedRecapBlogStore.shared,
            selectedCreatedRecap: .constant(nil),
            initialDayIndexForRecap: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
