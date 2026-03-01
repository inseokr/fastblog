//
//  CountryBlogsView.swift
//  Capper
//
//  Blogs for a single country: list/grid. Shown when user taps a Country Card.
//

import SwiftUI

struct CountryBlogsView: View {
    let section: CountrySection
    @Binding var selectedBlog: CreatedRecapBlog?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var localSelectedBlog: CreatedRecapBlog?
    @State private var showMap = false
    @State private var showManageSheet = false

    // Cloud removal
    @State private var showRemoveCloudPopup = false
    @State private var blogToRemove: CreatedRecapBlog?

    // Swipe / kebab delete flow
    @State private var blogToDelete: CreatedRecapBlog?
    @State private var showDeleteConfirmSheet = false

    // Edit
    @State private var blogToEdit: CreatedRecapBlog?

    // Soft-delete + Undo state
    /// The blog is hidden from the list immediately; deletion is only committed when the timer fires.
    @State private var pendingDeleteBlog: CreatedRecapBlog?
    /// Whether the pending delete also includes the cloud copy.
    @State private var pendingDeleteCloud = false
    @State private var showUndoBanner = false
    @State private var isUndoBannerMinimized = false
    @State private var undoTask: Task<Void, Never>?

    // Year filter support
    @State private var selectedYear: Int? = nil

    // Search filter
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchActive = false

    private let undoDuration: TimeInterval = 7

    private var availableYears: [Int] {
        let activeBlogs = section.blogs.filter { createdRecapStore.hasCreatedBlog(sourceTripId: $0.sourceTripId) }
        let years = activeBlogs.compactMap { blog -> Int? in
            guard let date = blog.tripStartDate ?? blog.tripEndDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted(by: >)
    }

    private var filteredAndSortedBlogs: [CreatedRecapBlog] {
        let activeBlogs = section.blogs.filter { createdRecapStore.hasCreatedBlog(sourceTripId: $0.sourceTripId) }
        let sorted = activeBlogs.sorted {
            ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt)
        }

        // Hide the blog that is pending soft-delete (not yet committed).
        let filtered: [CreatedRecapBlog]
        if let pending = pendingDeleteBlog {
            filtered = sorted.filter { $0.id != pending.id }
        } else {
            filtered = sorted
        }

        let yearFiltered: [CreatedRecapBlog]
        if let year = selectedYear {
            yearFiltered = filtered.filter { blog in
                guard let date = blog.tripStartDate ?? blog.tripEndDate else { return false }
                return Calendar.current.component(.year, from: date) == year
            }
        } else {
            yearFiltered = filtered
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return yearFiltered
        } else {
            return yearFiltered.filter { blog in
                blog.title.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Year Filter Header
                if availableYears.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterPill(label: "All", isSelected: selectedYear == nil) {
                                selectedYear = nil
                            }
                            ForEach(availableYears, id: \.self) { year in
                                filterPill(label: String(year), isSelected: selectedYear == year) {
                                    selectedYear = year
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(uiColor: .systemBackground))

                    Divider()
                }

                List {
                    ForEach(filteredAndSortedBlogs) { blog in
                        Button {
                            localSelectedBlog = blog
                        } label: {
                            CountryBlogRowView(
                                blog: blog,
                                isBlogInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                                isDraft: createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) == nil,
                                onRemoveFromCloud: {
                                    blogToRemove = blog
                                    showRemoveCloudPopup = true
                                },
                                onEditBlog: {
                                    blogToEdit = blog
                                },
                                onDeleteBlog: {
                                    blogToDelete = blog
                                    showDeleteConfirmSheet = true
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        // ─── Swipe-left trailing action ───────────────────
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                blogToDelete = blog
                                showDeleteConfirmSheet = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .padding(.top, 4)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 80)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            // ─── Undo Banner ──────────────────────────────────────────────
            if showUndoBanner, let pending = pendingDeleteBlog {
                let bannerText = pendingDeleteCloud
                    ? "Blog removed from device & cloud"
                    : "Blog removed"

                UndoOverlayView(
                    text: bannerText,
                    isMinimized: $isUndoBannerMinimized,
                    onUndo: {
                        performUndo()
                    },
                    onDismiss: {
                        withAnimation {
                            showUndoBanner = false
                            isUndoBannerMinimized = false
                        }
                        commitDelete(blog: pending, includeCloud: pendingDeleteCloud)
                        pendingDeleteBlog = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
            // ─── Floating Controls (bottom) ──────────────────────
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        isSearchFocused = false
                        showMap = true
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                }
                
                searchBar
            }
            .allowsHitTesting(true)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showUndoBanner)
        .navigationTitle(displayCountryName(section.countryName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Manage") {
                    showManageSheet = true
                }
                .fontWeight(.medium)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            CountryManageBlogsSheet(
                countryName: section.countryName,
                blogs: section.blogs
            )
            .environmentObject(createdRecapStore)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showMap) {
            CountryMapView(
                countryName: section.countryName,
                blogs: filteredAndSortedBlogs,
                selectedCreatedRecap: $localSelectedBlog
            )
            .environmentObject(createdRecapStore)
        }
        .navigationDestination(item: $localSelectedBlog) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
            )
        }
        // ─── Confirmation Sheet for Delete ────────────────────────────────
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirmSheet,
            titleVisibility: .visible
        ) {
            if let blog = blogToDelete {
                let isInCloud = createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId)

                if isInCloud {
                    Button("Delete from device only") {
                        startSoftDelete(blog: blog, includeCloud: false)
                    }
                    Button("Delete from device and cloud", role: .destructive) {
                        startSoftDelete(blog: blog, includeCloud: true)
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        startSoftDelete(blog: blog, includeCloud: false)
                    }
                }

                Button("Cancel", role: .cancel) {
                    blogToDelete = nil
                }
            }
        } message: {
            if let blog = blogToDelete,
               createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId) {
                Text("This blog is also saved in the cloud. Choose whether to delete it locally or from both places.")
            } else {
                Text("This will permanently delete this blog and all its local data.")
            }
        }
        // ─── Remove from Cloud Alert ─────────────────────────────────────
        .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup, presenting: blogToRemove) { blog in
            Button("Yes", role: .destructive) {
                createdRecapStore.removeFromCloud(blogId: blog.sourceTripId)
            }
            Button("No", role: .cancel) {
                blogToRemove = nil
            }
        } message: { _ in
            Text("Are you sure you want to remove this blog from the cloud? Your local copy will remain.")
        }
        .navigationDestination(item: $blogToEdit) { blog in
            RecapBlogPageView(
                blogId: blog.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: blog.sourceTripId)
            )
        }
    }

    // MARK: – Delete helpers

    private var deleteDialogTitle: String {
        guard let blog = blogToDelete else { return "Delete Blog?" }
        return "Delete \"\(blog.title)\"?"
    }

    /// Hides the blog from the list, starts the 7-second commit timer, and shows the undo banner.
    private func startSoftDelete(blog: CreatedRecapBlog, includeCloud: Bool) {
        // Cancel any previous pending delete (commit it immediately).
        if let prev = pendingDeleteBlog {
            undoTask?.cancel()
            commitDelete(blog: prev, includeCloud: pendingDeleteCloud)
        }

        pendingDeleteBlog = blog
        pendingDeleteCloud = includeCloud
        blogToDelete = nil

        withAnimation {
            showUndoBanner = true
            isUndoBannerMinimized = false
        }

        undoTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(undoDuration))
            } catch {
                return // Task was cancelled — either undo tapped or a new delete started.
            }
            guard let pending = pendingDeleteBlog, pending.id == blog.id else { return }
            withAnimation {
                showUndoBanner = false
                isUndoBannerMinimized = false
            }
            commitDelete(blog: pending, includeCloud: includeCloud)
            pendingDeleteBlog = nil
        }
    }

    /// Cancels the pending delete and restores the blog to the visible list.
    private func performUndo() {
        undoTask?.cancel()
        undoTask = nil
        withAnimation {
            pendingDeleteBlog = nil
            showUndoBanner = false
            isUndoBannerMinimized = false
        }
    }

    /// Actually calls the store to delete. Called either when the timer fires or the user dismisses the banner.
    private func commitDelete(blog: CreatedRecapBlog, includeCloud: Bool) {
        if includeCloud {
            createdRecapStore.deleteBlog(sourceTripId: blog.sourceTripId)
        } else {
            createdRecapStore.removeLocalCopy(sourceTripId: blog.sourceTripId)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search blog title", text: $searchText)
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture {
                    isSearchActive = true
                }
            if isSearchActive {
                Button {
                    searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: – Helpers

    private func displayCountryName(_ name: String) -> String {
        name.isEmpty || name == "Unknown" ? "Other" : name
    }

    private func filterPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Blog Row View

struct CountryBlogRowView: View {
    let blog: CreatedRecapBlog
    let isBlogInCloud: Bool
    let isDraft: Bool
    let onRemoveFromCloud: () -> Void
    let onEditBlog: () -> Void
    let onDeleteBlog: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TripCoverImage(theme: blog.coverImageName, coverAssetIdentifier: blog.coverAssetIdentifier)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if !isDraft {
                        if isBlogInCloud {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.green))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                .padding(12)
                                .onTapGesture(perform: onRemoveFromCloud)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.body)
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Circle().fill(Color.white))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                .padding(12)
                        }
                    }
                }
                .overlay(alignment: .center) {
                    if isDraft {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.45))
                            VStack(spacing: 6) {
                                Image(systemName: "pencil.line")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("DRAFT")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundColor(.white)
                                    .tracking(2)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(blog.tripDateRangeText ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Menu {
                        Button {
                            onEditBlog()
                        } label: {
                            Label("Edit Blog", systemImage: "pencil")
                        }

                        if isBlogInCloud {
                            Button {
                                onRemoveFromCloud()
                            } label: {
                                Label("Remove from Cloud", systemImage: "icloud.slash")
                            }
                        }

                        Button(role: .destructive) {
                            onDeleteBlog()
                        } label: {
                            Label("Delete Blog", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { })
                }

                Text(blog.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text("\(blog.totalPlaceVisitCount) Place\(blog.totalPlaceVisitCount == 1 ? "" : "s") • \(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Edited \(Self.dateFormatter.string(from: blog.lastEditedAt ?? blog.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }
}
