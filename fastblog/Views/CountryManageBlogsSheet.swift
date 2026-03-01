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

    private var sortedBlogs: [CreatedRecapBlog] {
        let activeBlogs = blogs.filter { blog in
            removedBlogIDs.contains(blog.id) || createdRecapStore.hasCreatedBlog(sourceTripId: blog.sourceTripId)
        }
        return activeBlogs.sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }
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
                }
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
    }

    // MARK: - Helpers

    private func commitRemove(blog: CreatedRecapBlog) {
        createdRecapStore.removeLocalCopy(sourceTripId: blog.sourceTripId)
        withAnimation {
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
    let isRemoved: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {

            // ── Thumbnail ────────────────────────────────────────────────
            AssetPhotoView(
                assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                cornerRadius: 12,
                targetSize: CGSize(width: 180, height: 180)
            )
            .frame(width: 60, height: 60)

            // ── Info ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(blog.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(blog.tripDateRangeText ?? "Unknown Date")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Cloud status chip
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
            }

            Spacer()

            // ── Trailing Action Button ───────────────────────────────────
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRemoved ? Color.secondary.opacity(0.1) : Color.red.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRemoved)
            .animation(.easeInOut(duration: 0.2), value: isRemoved)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isRemoved ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isRemoved)
    }
}
