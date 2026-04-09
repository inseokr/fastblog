//
//  CountryBlogsView.swift
//  Capper
//
//  Blogs for a single country: list/grid. Shown when user taps a Country Card.
//

import SwiftUI
import UIKit

/// Unselected year pill on country header: grouped secondary fill blended ~15% toward white.
private func countryYearFilterUnselectedFill() -> Color {
    Color(uiColor: UIColor { traits in
        let base = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return base }
        let t: CGFloat = 0.15
        return UIColor(red: r * (1 - t) + t, green: g * (1 - t) + t, blue: b * (1 - t) + t, alpha: a)
    })
}

/// PreferenceKey to report the first row's minY for "at top" detection (swipe-down-to-dismiss).
private struct CountryListScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CountryBlogsView: View {
    let section: CountrySection
    @Binding var selectedBlog: CreatedRecapBlog?
    /// When true, the next presentation of this blog should open in edit mode (kebab "Edit Blog").
    @Binding var openRecapInEditMode: Bool
    /// When true, the next presentation should show the Share Your Blog sheet (kebab "Share Blog").
    @Binding var openRecapPresentShareYourBlogSheet: Bool
    @Binding var showMap: Bool
    @Binding var searchText: String
    /// Reported to parent for swipe-down-to-dismiss when at top. Optional so callers can omit.
    @Binding var scrollOffset: CGFloat
    /// True when the shared bottom search field is focused (parent updates from `@FocusState`).
    var isBottomSearchFocused: Bool = false
    /// Clear keyboard focus when the user taps Done (parent owns `@FocusState`).
    var onDismissSearchKeyboard: (() -> Void)? = nil
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showManageSheet = false
    /// When true, reopen Manage Blogs after the recap overlay dismisses (opened blog from that sheet only).
    @State private var reopenManageSheetAfterRecapDismiss = false

    // Cloud removal
    @State private var showRemoveCloudPopup = false
    @State private var blogToRemove: CreatedRecapBlog?

    // Swipe / kebab delete flow
    @State private var blogToDelete: CreatedRecapBlog?
    @State private var showDeleteConfirmSheet = false

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

    /// Live blogs for this country, read from the store so edits (title, cover) propagate immediately.
    private var liveBlogs: [CreatedRecapBlog] {
        if let summary = createdRecapStore.countrySummaries.first(where: { $0.countryName == section.countryName }) {
            return summary.blogs
        }
        return section.blogs
    }

    private let darkNavy = Color(red: 5/255, green: 10/255, blue: 48/255)
    /// Swipe delete: explicit colors so parent `.tint(.primary)` (white in dark mode) does not wash out the icon.
    private let swipeDeleteRed = Color(red: 0.88, green: 0.38, blue: 0.40)

    // Search filter (driven by parent's shared search bar)
    // searchText is a @Binding — no local @State needed

    private let undoDuration: TimeInterval = 7

    private var availableYears: [Int] {
        let activeBlogs = liveBlogs.filter { createdRecapStore.hasCreatedBlog(sourceTripId: $0.sourceTripId) }
        let years = activeBlogs.compactMap { blog -> Int? in
            guard let date = blog.tripStartDate ?? blog.tripEndDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted(by: >)
    }

    private var isCountrySearchInteractionActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBottomSearchFocused
    }

    private var filteredAndSortedBlogs: [CreatedRecapBlog] {
        let activeBlogs = liveBlogs.filter { createdRecapStore.hasCreatedBlog(sourceTripId: $0.sourceTripId) }
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
                // Year filter: show whenever any blog has a trip year (not only when 2+ years — device size is irrelevant).
                if !availableYears.isEmpty {
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
                    .background(darkNavy)

                    Divider()
                }

                List {
                    ForEach(Array(filteredAndSortedBlogs.enumerated()), id: \.element.id) { index, blog in
                        Button {
                            openRecapInEditMode = false
                            openRecapPresentShareYourBlogSheet = false
                            selectedBlog = blog
                        } label: {
                            CountryBlogRowView(
                                blog: blog,
                                isBlogInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                                isDraft: !blog.hasCommittedRecapSave,
                                onRemoveFromCloud: {
                                    blogToRemove = blog
                                    showRemoveCloudPopup = true
                                },
                                onShareBlog: {
                                    openRecapInEditMode = false
                                    openRecapPresentShareYourBlogSheet = true
                                    selectedBlog = blog
                                },
                                onEditBlog: {
                                    openRecapPresentShareYourBlogSheet = false
                                    openRecapInEditMode = true
                                    selectedBlog = blog
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
                        .listRowBackground(Group {
                            if index == 0 {
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: CountryListScrollOffsetKey.self,
                                        value: g.frame(in: .named("countryList")).minY
                                    )
                                }
                            }
                        })
                        // ─── Swipe-left trailing action ───────────────────
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                let captured = blog
                                DispatchQueue.main.async {
                                    blogToDelete = captured
                                    showDeleteConfirmSheet = true
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(swipeDeleteRed)
                            .accessibilityLabel("Delete")
                        }
                    }
                }
                .listStyle(.plain)
                .padding(.top, 4)
                .coordinateSpace(name: "countryList")
                .onPreferenceChange(CountryListScrollOffsetKey.self) { scrollOffset = $0 }
                .onChange(of: filteredAndSortedBlogs.isEmpty) { _, isEmpty in
                    if isEmpty { scrollOffset = 0 }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 132)
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
        } // end ZStack
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showUndoBanner)
        .background(darkNavy)
        .background(InteractivePopGestureDisabler())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isCountrySearchInteractionActive {
                    Button("Done") {
                        searchText = ""
                        onDismissSearchKeyboard?()
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                } else {
                    Button("Manage") {
                        showManageSheet = true
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $showManageSheet) {
            CountryManageBlogsSheet(
                countryName: section.countryName,
                blogs: liveBlogs,
                onOpenBlog: { blog in
                    reopenManageSheetAfterRecapDismiss = true
                    showManageSheet = false
                    openRecapInEditMode = false
                    openRecapPresentShareYourBlogSheet = false
                    selectedBlog = blog
                }
            )
            .environmentObject(createdRecapStore)
            .presentationDetents([.fraction(1)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedBlog?.id) { oldValue, newValue in
            guard reopenManageSheetAfterRecapDismiss, oldValue != nil, newValue == nil else { return }
            reopenManageSheetAfterRecapDismiss = false
            showManageSheet = true
        }
        .navigationDestination(isPresented: $showMap) {
            CountryMapView(
                countryName: section.countryName,
                blogs: filteredAndSortedBlogs,
                selectedCreatedRecap: $selectedBlog,
                openRecapInEditMode: $openRecapInEditMode
            )
            .environmentObject(createdRecapStore)
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
    } // end body

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

    // MARK: - Search happens via parent's shared search bar now
    // (searchText is a @Binding passed in from MyBlogsProfileView)

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
                .background(isSelected ? Color.blue : countryYearFilterUnselectedFill())
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

// MARK: – Blog Row View

struct CountryBlogRowView: View {
    let blog: CreatedRecapBlog
    let isBlogInCloud: Bool
    /// Matches `!blog.hasCommittedRecapSave`: still a recap draft (incl. after “Save as draft”); hides Share Blog.
    let isDraft: Bool
    let onRemoveFromCloud: () -> Void
    let onShareBlog: () -> Void
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
                .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if isDraft {
                        Text("Draft")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            .padding(8)
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
                        if !isDraft {
                            Button {
                                onShareBlog()
                            } label: {
                                Label("Share Blog", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button {
                            onEditBlog()
                        } label: {
                            Label("Edit Blog", systemImage: "pencil")
                        }

                        if isBlogInCloud {
                            Button {
                                onRemoveFromCloud()
                            } label: {
                                Text("Remove from Cloud")
                            }
                        }

                        Button(role: .destructive) {
                            onDeleteBlog()
                        } label: {
                            Label("Delete Blog", systemImage: "trash")
                        }
                        .tint(.red)
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
