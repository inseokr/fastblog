//
//  MyBlogsProfileView.swift
//  Capper
//
//  My Blogs: dark blue background, vertical list of Country Cards, fixed search bar and My Map button.
//

import SwiftUI

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
    @StateObject private var viewModel = MyBlogsProfileViewModel()
    @State private var selectedSection: CountrySection?
    @State private var showMyMap = false
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
            backgroundBlue
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {

                let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
                let sections = viewModel.filteredSections(from: allSections)
                Group {
                    if !isSearchActive && !viewModel.unsavedTrips.isEmpty {
                        unsavedTripsSection
                    }

                    // Recent Blogs horizontal scroll (only when not in search mode)
                    if !isSearchActive && !createdRecapStore.visibleRecents.isEmpty {
                        recentBlogsSection
                    }

                    if isSearchActive && !viewModel.isSearching {
                        // Search mode active but nothing typed yet
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
                                    selectedSection = section
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MyBlogsScrollOffsetKey.self, value: proxy.frame(in: .named("MyBlogsScroll")).minY)
                    }
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, searchBarHeight + myMapButtonSize + 24)
            }
            .coordinateSpace(name: "MyBlogsScroll")
            .onPreferenceChange(MyBlogsScrollOffsetKey.self) { value in
                scrollOffset = value
            }

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    MyMapButton {
                        isSearchFocused = false
                        showMyMap = true
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                }
                searchBar
            }
            .allowsHitTesting(true)
        }
        .simultaneousGesture(
            DragGesture()
                .onEnded { value in
                    if scrollOffset >= -20 && value.translation.height > 60 && abs(value.translation.height) > abs(value.translation.width) {
                        dismiss()
                    }
                }
        )
        .navigationTitle("My Blogs")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Manage") {
                    isSearchFocused = false
                    showManage = true
                }
                .foregroundColor(.white)
            }
        }
        .navigationDestination(item: $selectedSection) { section in
            CountryBlogsView(section: section, selectedBlog: $selectedCreatedRecap)
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
            CreateBlogFlowView(trip: trip, startDirectlyCreating: true) { createdTripId in
                createBlogFlowTrip = nil
                viewModel.loadUnsavedTrips() // Refresh after creation
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
        .onAppear {
            viewModel.loadUnsavedTrips()
        }
    }

    // "Recent Blogs" horizontal scroll matching the home page style
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

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("Search city or blog title", text: $viewModel.searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture {
                    isSearchActive = true
                }
            if isSearchActive {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
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
            }
            .alert(
                "Remove from this device?",
                isPresented: $showRemoveAlert,
                presenting: blogPendingRemoval
            ) { blog in
                Button("Remove", role: .destructive) {
                    createdRecapStore.removeLocalCopy(sourceTripId: blog.sourceTripId)
                    withAnimation { removedBlogIDs.insert(blog.id) }
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
