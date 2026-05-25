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

    private var canSplit: Bool { !sortedBlogs.isEmpty }
    private var canMerge: Bool { sortedBlogs.count >= 2 }

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
                            VStack(spacing: 3) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                                Text("Split")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.orange.opacity(canSplit ? 1.0 : 0.38))
                            }
                            .frame(width: 64, height: 64)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Spacer()
                        Button {
                            showMergeView = true
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

    /// Hero aspect ratio aligned with profile `BlogCard` covers.
    private let heroAspect: CGFloat = 16 / 9

    var body: some View {
        Color.clear
            .aspectRatio(heroAspect, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let target = CGSize(width: proxy.size.width * 2, height: proxy.size.height * 2)
                    ZStack {
                        AssetPhotoView(
                            assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                            cornerRadius: 0,
                            targetSize: target
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                        LinearGradient(
                            colors: [
                                .black.opacity(0.35),
                                .black.opacity(0.15),
                                .clear,
                                .black.opacity(0.5),
                                .black.opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if isDraft {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                removeControl
                    .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(blog.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

                    Text(blog.tripDateRangeText ?? "Unknown Date")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

                    cloudBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
                guard !isRemoved else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenBlog?()
            }
            .opacity(isRemoved ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isRemoved)
    }

    @ViewBuilder
    private var cloudBadge: some View {
        if isInCloud {
            Text("In Cloud")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.65, green: 0.95, blue: 0.72))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    private var removeControl: some View {
        Button(action: onRemove) {
            Group {
                if isRemoved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Removed")
                    }
                } else {
                    Image(systemName: "trash")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isRemoved ? Color.white : Color.red)
            .padding(.horizontal, isRemoved ? 12 : 11)
            .padding(.vertical, isRemoved ? 9 : 11)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.48))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemoved)
        .animation(.easeInOut(duration: 0.2), value: isRemoved)
    }
}
