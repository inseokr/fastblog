//
//  MergeBlogsView.swift
//  fastblog
//
//  Allows users to merge two consecutive blogs into a single blog.
//  Pushed within CountryManageBlogsSheet's NavigationStack.
//

import SwiftUI

struct MergeBlogsView: View {
    let countryName: String
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var pairToMerge: MergePair?
    @State private var showMergeAlert = false
    @State private var mergeCompleted = false

    // MARK: - Eligible Pairs

    private struct MergePair: Identifiable {
        let id = UUID()
        let earlier: CreatedRecapBlog
        let later: CreatedRecapBlog
    }

    private var sortedBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
            .filter { ($0.countryName ?? "Unknown") == countryName }
            .sorted { ($0.tripStartDate ?? $0.createdAt) < ($1.tripStartDate ?? $1.createdAt) }
    }

    private var eligiblePairs: [MergePair] {
        let blogs = sortedBlogs
        guard blogs.count >= 2 else { return [] }

        var pairs: [MergePair] = []
        let cal = Calendar.current

        for i in 0..<(blogs.count - 1) {
            let a = blogs[i]
            let b = blogs[i + 1]

            guard let aEnd = a.tripEndDate, let bStart = b.tripStartDate else { continue }

            // Gap check: ≤ 7 days between end of A and start of B
            let gap = cal.dateComponents([.day], from: aEnd, to: bStart).day ?? Int.max
            guard gap <= 7 else { continue }

            // Geographic proximity check (≤ 200 miles between centroids)
            if let centroidA = blogCentroid(for: a.sourceTripId),
               let centroidB = blogCentroid(for: b.sourceTripId) {
                let dist = GeoDistanceHelper.haversineMiles(centroidA, centroidB)
                guard dist <= 200 else { continue }
            }
            // If no location data, still allow (user is explicitly managing)

            // Don't allow merge if either blog is still processing
            if createdRecapStore.processingDayIndexByBlogId[a.sourceTripId] != nil ||
               createdRecapStore.processingDayIndexByBlogId[b.sourceTripId] != nil {
                continue
            }

            pairs.append(MergePair(earlier: a, later: b))
        }
        return pairs
    }

    private func blogCentroid(for blogId: UUID) -> PhotoCoordinate? {
        guard let detail = createdRecapStore.getBlogDetail(blogId: blogId) else { return nil }
        let coords = detail.days.flatMap(\.placeStops).compactMap(\.representativeLocation)
        guard !coords.isEmpty else { return nil }
        let avgLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
        let avgLon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
        return PhotoCoordinate(latitude: avgLat, longitude: avgLon)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                            .padding(.bottom, 4)

                        Text("Merge Blogs")
                            .font(.system(.title2, design: .serif).weight(.medium))
                            .foregroundColor(.primary)

                        Text("Combine two consecutive trips into one blog")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                    // Pairs list
                    if eligiblePairs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No eligible merge pairs")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Blogs must be consecutive in time and within the same area to merge.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(eligiblePairs) { pair in
                                mergePairRow(pair)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .alert(
            "Merge Blogs?",
            isPresented: $showMergeAlert,
            presenting: pairToMerge
        ) { pair in
            Button("Merge") {
                createdRecapStore.mergeBlogs(keepId: pair.earlier.sourceTripId, absorbId: pair.later.sourceTripId)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                mergeCompleted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {
                pairToMerge = nil
            }
        } message: { pair in
            Text("This will combine these trips into a single blog.")
        }
    }

    // MARK: - Pair Row

    private func mergePairRow(_ pair: MergePair) -> some View {
        HStack(spacing: 12) {
            // Earlier blog
            blogMiniCard(pair.earlier)

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.blue)

            // Later blog
            blogMiniCard(pair.later)

            Spacer()

            Button {
                pairToMerge = pair
                showMergeAlert = true
            } label: {
                Text("Merge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func blogMiniCard(_ blog: CreatedRecapBlog) -> some View {
        VStack(spacing: 4) {
            AssetPhotoView(
                assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                cornerRadius: 8,
                targetSize: CGSize(width: 120, height: 120)
            )
            .frame(width: 50, height: 50)
            .clipped()

            Text(blog.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: 70)

            Text(blog.tripDateRangeText ?? "")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
    }
}
