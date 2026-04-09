//
//  CountryManageBlogsSheet.swift
//  fastblog
//
//  Bottom-sheet modal for the Country Detail page.
//  Lets users remove locally-cached blogs for a single country without
//  touching the cloud copy.
//

import SwiftUI
import UIKit

// MARK: - Sheet Root

struct CountryManageBlogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    let countryName: String
    let blogs: [CreatedRecapBlog]
    /// Opens the recap overlay; parent dismisses this sheet first and re-presents it when the recap closes.
    var onOpenBlog: ((CreatedRecapBlog) -> Void)? = nil

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

                        Text("Remove blogs from this device")
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
                                isDraft: !blog.hasCommittedRecapSave,
                                isRemoved: removedBlogIDs.contains(blog.id),
                                onRemove: {
                                    blogPendingRemoval = blog
                                    showRemoveAlert = true
                                },
                                onOpenBlog: onOpenBlog.map { cb in { cb(blog) } }
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 80)
                    }
                }

                // ── Bottom Action Bar ──────────────────────────────────
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            showSplitView = true
                        } label: {
                            Image(systemName: "scissors")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Spacer()
                        Button {
                            showMergeView = true
                        } label: {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                Text("This blog will be removed from your device.")
            }
            .tint(.primary)
        }
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

// MARK: - Row

struct CountryManageRow: View {
    let blog: CreatedRecapBlog
    let isInCloud: Bool
    let isDraft: Bool
    let isRemoved: Bool
    let onRemove: () -> Void
    /// Tap the card (outside remove) to open the blog.
    var onOpenBlog: (() -> Void)? = nil

    /// Portrait (3:4) thumb so covers match My Blogs cards.
    /// Scales up on smaller iPhones and larger Dynamic Type to reduce
    /// the "empty space" below the thumbnails when text wraps taller.
    private var thumbnailWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let baseWidth: CGFloat
        if screenWidth <= 390 {
            baseWidth = 80
        } else if screenWidth >= 428 {
            baseWidth = 92
        } else {
            baseWidth = 84
        }
        return baseWidth
    }

    private var thumbnailHeight: CGFloat { thumbnailWidth * 4 / 3 }
    private var coverTargetSize: CGSize {
        // Keep the existing ~5x thumbnail-to-thumbnail-load-size ratio for sharpness.
        CGSize(width: thumbnailWidth * 5, height: thumbnailHeight * 5)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    AssetPhotoView(
                        assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                        cornerRadius: 0,
                        targetSize: coverTargetSize
                    )
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(minWidth: thumbnailWidth, maxWidth: thumbnailWidth, minHeight: thumbnailHeight, maxHeight: .infinity)
                    .clipped()

                    if isDraft {
                        Text("Draft")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(blog.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(blog.tripDateRangeText ?? "Unknown Date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    cloudBadge
                }
                .frame(maxWidth: .infinity, minHeight: thumbnailHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isRemoved else { return }
                onOpenBlog?()
            }

            VStack {
                Spacer(minLength: 0)
                removeControl
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(isRemoved ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isRemoved)
    }

    private var cloudBadge: some View {
        Text(isInCloud ? "In Cloud" : "Local Only")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isInCloud ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isInCloud ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
            )
    }

    private var removeControl: some View {
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
            .foregroundStyle(isRemoved ? Color.secondary : Color.red)
            .frame(minWidth: 40, minHeight: 36)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isRemoved ? Color.secondary.opacity(0.1) : Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemoved)
        .animation(.easeInOut(duration: 0.2), value: isRemoved)
    }
}
