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
    let countryName: String
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBlog: CreatedRecapBlog?
    @State private var loadedDays: [RecapBlogDay] = []
    @State private var selectedSplitIndex: Int?
    @State private var showSplitAlert = false
    @State private var showUndoBanner = false

    /// When non-nil, skip the blog-selection step and go directly to the split-point picker.
    private let preloadedBlog: CreatedRecapBlog?
    private let preloadedDays: [RecapBlogDay]
    /// Called after a successful split so the presenting view can react (e.g. show its own undo banner).
    var onSplitCompleted: (() -> Void)?

    init(countryName: String,
         preloadedBlog: CreatedRecapBlog? = nil,
         preloadedDays: [RecapBlogDay] = [],
         onSplitCompleted: (() -> Void)? = nil) {
        self.countryName = countryName
        self.preloadedBlog = preloadedBlog
        self.preloadedDays = preloadedDays
        self.onSplitCompleted = onSplitCompleted
    }


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
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            if selectedBlog == nil {
                blogSelectionView
            } else {
                splitPointView
            }

            // Undo banner — shown after a successful split
            if showUndoBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("Blog split into two parts")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)

                        Spacer()

                        Button("Undo") {
                            createdRecapStore.undoSplit()
                            withAnimation {
                                showUndoBanner = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                dismiss()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .label).opacity(0.88))
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onAppear {
            loadPreloadedBlogIfNeeded()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(preloadedBlog != nil ? "Cancel" : "Cancel") {
                    if preloadedBlog != nil {
                        // In preloaded mode, Cancel just dismisses the sheet
                        dismiss()
                    } else if selectedBlog != nil {
                        withAnimation {
                            selectedBlog = nil
                            loadedDays = []
                        }
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
            if preloadedBlog == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .alert(
            "Split Blog?",
            isPresented: $showSplitAlert
        ) {
            Button("Split") {
                guard let blog = selectedBlog, let splitIdx = selectedSplitIndex else { return }
                createdRecapStore.splitBlog(blogId: blog.sourceTripId, afterDayIndex: splitIdx)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                onSplitCompleted?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                selectedSplitIndex = nil
            }
        } message: {
            if let splitIdx = selectedSplitIndex {
                let part1Count = splitIdx + 1
                let part2Count = loadedDays.count - part1Count
                Text("This will create two separate blogs:\n\nPart 1: Day 1–\(part1Count) (\(part1Count) day\(part1Count == 1 ? "" : "s"))\nPart 2: Day \(part1Count + 1)–\(loadedDays.count) (\(part2Count) day\(part2Count == 1 ? "" : "s"))")
            } else {
                Text("Split this blog into two separate blogs.")
            }
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
                        daySummaryCard(day: day, dayNumber: index + 1)
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

    private func selectBlog(_ blog: CreatedRecapBlog) {
        if let detail = createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) {
            loadedDays = detail.days.sorted { $0.date < $1.date }
        }
        withAnimation {
            selectedBlog = blog
        }
    }

    private func loadPreloadedBlogIfNeeded() {
        guard let blog = preloadedBlog, selectedBlog == nil else { return }
        if !preloadedDays.isEmpty {
            loadedDays = preloadedDays
        } else if let detail = createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) {
            loadedDays = detail.days.sorted { $0.date < $1.date }
        }
        selectedBlog = blog
    }
}
