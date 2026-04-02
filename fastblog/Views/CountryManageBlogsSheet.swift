//
//  CountryManageBlogsSheet.swift
//  fastblog
//
//  Bottom-sheet modal for the Country Detail page.
//  Lets users remove locally-cached blogs for a single country without
//  touching the cloud copy.
//

import SwiftUI

// MARK: - Sheet Root

struct CountryManageBlogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    let countryName: String
    let blogs: [CreatedRecapBlog]

    // Alert state
    @State private var blogPendingRemoval: CreatedRecapBlog?
    @State private var showRemoveAlert = false

    // Track IDs that the user has already removed in this session so the
    // row can update its button immediately.
    @State private var removedBlogIDs: Set<UUID> = []

    // Merge / Split navigation
    @State private var showMergeView = false
    @State private var showSplitView = false

    /// Live blog list derived from the store so merge/split results reflect immediately.
    private var sortedBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
            .filter { ($0.countryName ?? "Unknown") == countryName }
            .filter { removedBlogIDs.contains($0.id) || createdRecapStore.hasCreatedBlog(sourceTripId: $0.sourceTripId) }
            .sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                            .padding(.bottom, 4)

                        Text("Manage Blogs")
                            .font(.system(.title2, design: .serif).weight(.medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        Text("Remove downloaded blogs from this device")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                    // ── Blog List ─────────────────────────────────────────
                    LazyVStack(spacing: 12) {
                        ForEach(sortedBlogs) { blog in
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
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
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
                        showMergeView = true
                    } label: {
                        Label("Merge Blogs", systemImage: "arrow.triangle.merge")
                    }
                    Button {
                        showSplitView = true
                    } label: {
                        Label("Split Blog", systemImage: "scissors")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .navigationDestination(isPresented: $showMergeView) {
            MergeBlogsView(countryName: countryName)
                .environmentObject(createdRecapStore)
        }
        .navigationDestination(isPresented: $showSplitView) {
            SplitBlogView(countryName: countryName)
                .environmentObject(createdRecapStore)
        }
        // ── Remove Confirmation Alert ──────────────────────────────
        .alert(
                "Remove from this device?",
                isPresented: $showRemoveAlert,
                presenting: blogPendingRemoval
            ) { blog in
                Button("Remove", role: .destructive) {
                    commitRemove(blog: blog)
                }
                Button("Cancel", role: .cancel) {
                    blogPendingRemoval = nil
                }
            } message: { _ in
                Text("This removes the downloaded blog from local storage. Your cloud blog stays available.")
            }
        }
        .tint(.primary)
    }

    // MARK: - Helpers

    private func commitRemove(blog: CreatedRecapBlog) {
        createdRecapStore.removeLocalCopy(sourceTripId: blog.sourceTripId)
        _ = withAnimation {
            removedBlogIDs.insert(blog.id)
        }
        blogPendingRemoval = nil
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Row layout

private struct CountryManageRowContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Row

struct CountryManageRow: View {
    let blog: CreatedRecapBlog
    let isInCloud: Bool
    let isRemoved: Bool
    let onRemove: () -> Void

    /// Inner width of the row (inside card padding). Photo column is weighted a bit wider than 1∶4 so text sits further right.
    @State private var contentWidth: CGFloat = 0

    private let columnGap: CGFloat = 12
    /// Inset between photo column edge and square thumbnail (smaller = larger thumb).
    private let coverOuterPadding: CGFloat = 5
    private let photoColumnWeight: CGFloat = 1.45
    private let descriptionColumnWeight: CGFloat = 4.0

    private var weightTotal: CGFloat { photoColumnWeight + descriptionColumnWeight }

    private var photoColumnWidth: CGFloat {
        guard contentWidth > 1 else {
            return 84
        }
        return (contentWidth - columnGap) * (photoColumnWeight / weightTotal)
    }

    private var descriptionColumnWidth: CGFloat {
        guard contentWidth > 1 else {
            return 260
        }
        return (contentWidth - columnGap) * (descriptionColumnWeight / weightTotal)
    }

    /// Square thumbnail inside the photo column, with even padding on all sides.
    private var thumbnailSide: CGFloat {
        max(52, photoColumnWidth - coverOuterPadding * 2)
    }

    var body: some View {
        HStack(alignment: .center, spacing: columnGap) {
            // ── Cover: fixed square crop, vertically centered with text column ─────────
            ZStack {
                AssetPhotoView(
                    assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                    cornerRadius: 0,
                    targetSize: CGSize(width: 400, height: 400)
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(width: photoColumnWidth, height: photoColumnWidth)

            // ── Description; delete on same row as cloud chip, full-width row ────────
            VStack(alignment: .leading, spacing: 4) {
                Text(blog.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(blog.tripDateRangeText ?? "Unknown Date")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: isInCloud ? "checkmark.icloud.fill" : "icloud.slash")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isInCloud ? "In Cloud" : "Local Only")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(isInCloud ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isInCloud ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    )

                    Spacer(minLength: 4)

                    Button(action: onRemove) {
                        Group {
                            if isRemoved {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                    Text("Removed")
                                }
                            } else {
                                Image(systemName: "trash")
                            }
                        }
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundColor(isRemoved ? .secondary : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isRemoved ? Color.secondary.opacity(0.1) : Color.red.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRemoved)
                    .animation(.easeInOut(duration: 0.2), value: isRemoved)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: descriptionColumnWidth, maxWidth: descriptionColumnWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: CountryManageRowContentWidthKey.self,
                    value: geometry.size.width
                )
            }
        )
        .onPreferenceChange(CountryManageRowContentWidthKey.self) { width in
            if abs(width - contentWidth) > 0.5 {
                contentWidth = width
            }
        }
        .padding(.top, 12)
        .padding(.leading, 12)
        .padding(.bottom, 12)
        .padding(.trailing, 6)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isRemoved ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isRemoved)
    }
}
