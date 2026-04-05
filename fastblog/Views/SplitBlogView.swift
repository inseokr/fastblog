//
//  SplitBlogView.swift
//  fastblog
//
//  Allows users to split one blog into two independent blogs.
//  Two-step flow: select a blog, then choose the split point.
//  Pushed within CountryManageBlogsSheet's NavigationStack.
//

import SwiftUI

struct SplitBlogView: View {
    /// Pushed destination: open the full blog recap starting on this day (back returns to split-point list).
    private struct DayPreviewRoute: Hashable {
        let blogId: UUID
        let dayIndex: Int
    }

    let countryName: String
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBlog: CreatedRecapBlog?
    @State private var loadedDays: [RecapBlogDay] = []
    @State private var selectedSplitIndex: Int?
    @State private var showSplitAlert = false
    @State private var showUndoBanner = false
    @State private var dayPreviewRoute: DayPreviewRoute?

    // MARK: - Splittable Blogs

    private var splittableBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
            .filter { ($0.countryName ?? "Unknown") == countryName && $0.tripDurationDays >= 2 }
            .filter { createdRecapStore.processingDayIndexByBlogId[$0.sourceTripId] == nil }
            .sorted { ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Group {
                if selectedBlog == nil {
                    blogSelectionView
                } else {
                    splitPointView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())

            // Undo banner — shown after a successful split
            if showUndoBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("Blog split into two parts")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button("Undo") {
                            createdRecapStore.undoSplit()
                            withAnimation {
                                showUndoBanner = false
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if selectedBlog != nil {
                        withAnimation {
                            selectedBlog = nil
                            loadedDays = []
                            selectedSplitIndex = nil
                            dayPreviewRoute = nil
                        }
                    } else {
                        dismiss()
                    }
                } label: {
                    if selectedBlog != nil {
                        Text("Cancel")
                            .font(.body.weight(.semibold))
                    } else {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .accessibilityLabel(selectedBlog != nil ? "Cancel" : "Close")
            }
        }
        .navigationDestination(item: $dayPreviewRoute) { route in
            RecapBlogPageView(
                blogId: route.blogId,
                initialTrip: nil,
                initialDayIndex: route.dayIndex,
                forceEditMode: false,
                suppressPhotoGroupingTipOnAppear: true
            )
            .environmentObject(TripNearbyShareSessionController.shared)
        }
        .sheet(isPresented: $showSplitAlert) {
            splitConfirmSheet
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Step 1: Blog Selection

    private var blogSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.system(size: 38))
                        .foregroundColor(.orange)
                        .padding(.bottom, 4)

                    Text("Split Blog")
                        .font(.system(.title2, design: .serif).weight(.medium))
                        .foregroundColor(.primary)

                    Text("Divide one blog into two separate blogs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 4)

                if splittableBlogs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No blogs available to split")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Blogs must have at least 2 days to be split.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(splittableBlogs) { blog in
                            Button {
                                selectBlog(blog)
                            } label: {
                                splitBlogSelectRow(blog)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private func splitBlogSelectRow(_ blog: CreatedRecapBlog) -> some View {
        HStack(spacing: 16) {
            AssetPhotoView(
                assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                cornerRadius: 12,
                targetSize: CGSize(width: 180, height: 180)
            )
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(blog.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(blog.tripDateRangeText ?? "Unknown Date")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Step 2: Split Point Selection

    private var splitPointView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Choose where to split")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.top, 8)
                    if let blog = selectedBlog {
                        Text(blog.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

                // Day cards with split dividers
                VStack(spacing: 0) {
                    ForEach(Array(loadedDays.enumerated()), id: \.element.id) { index, day in
                        Button {
                            guard let blog = selectedBlog else { return }
                            dayPreviewRoute = DayPreviewRoute(blogId: blog.sourceTripId, dayIndex: index)
                        } label: {
                            daySummaryCard(day: day, dayNumber: index + 1)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        // Split divider between days (not after last)
                        if index < loadedDays.count - 1 {
                            splitDivider(afterIndex: index)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 40)
            }
        }
    }

    private func daySummaryCard(day: RecapBlogDay, dayNumber: Int) -> some View {
        let placeCount = day.placeStops.count
        let photoCount = day.placeStops.flatMap(\.photos).filter(\.isIncluded).count
        let cityNames = Array(Set(day.placeStops.compactMap { stop -> String? in
            guard let subtitle = stop.placeSubtitle, !subtitle.isEmpty else { return nil }
            return subtitle.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        })).sorted()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(dayNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if !cityNames.isEmpty {
                        Text(cityNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(day.shortDateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text("\(placeCount) place\(placeCount == 1 ? "" : "s") \u{2022} \(photoCount) photo\(photoCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func splitDivider(afterIndex: Int) -> some View {
        Button {
            selectedSplitIndex = afterIndex
            showSplitAlert = true
        } label: {
            HStack(spacing: 8) {
                dashedLine
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Split here")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.orange)
                dashedLine
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var dashedLine: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .foregroundColor(.orange.opacity(0.5))
        }
        .frame(height: 1)
    }

    // MARK: - Helpers

    private var splitConfirmSheet: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Split Blog?")
                    .font(.headline)
                if let splitIdx = selectedSplitIndex {
                    let part1Count = splitIdx + 1
                    let part2Count = loadedDays.count - part1Count
                    let part1Days = Self.daySpanLabel(startDay: 1, endDay: part1Count)
                    let part2Days = Self.daySpanLabel(startDay: part1Count + 1, endDay: loadedDays.count)
                    Text("Part 1: \(part1Days) (\(part1Count) day\(part1Count == 1 ? "" : "s"))  •  Part 2: \(part2Days) (\(part2Count) day\(part2Count == 1 ? "" : "s"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Split this blog into two separate blogs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                Button {
                    guard let blog = selectedBlog, let splitIdx = selectedSplitIndex else { return }
                    showSplitAlert = false
                    createdRecapStore.splitBlog(blogId: blog.sourceTripId, afterDayIndex: splitIdx)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    withAnimation {
                        selectedBlog = nil
                        loadedDays = []
                        dayPreviewRoute = nil
                        showUndoBanner = true
                    }
                } label: {
                    Text("Split")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    selectedSplitIndex = nil
                    showSplitAlert = false
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// Single day → `Day 3`; range → `Day 1–4` (avoids redundant `Day 1–1`).
    private static func daySpanLabel(startDay: Int, endDay: Int) -> String {
        if startDay == endDay {
            "Day \(startDay)"
        } else {
            "Day \(startDay)–\(endDay)"
        }
    }

    private func selectBlog(_ blog: CreatedRecapBlog) {
        if let detail = createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) {
            loadedDays = detail.days.sorted { $0.date < $1.date }
        }
        withAnimation {
            selectedBlog = blog
        }
    }
}
