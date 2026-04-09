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

    @State private var namePickPair: MergePair?
    @State private var showMergeNameSheet = false
    @State private var mergeNameSheetPhase: MergeNameSheetPhase = .choose
    @State private var customMergeTitleText = ""
    @State private var mergeNameSheetDetent: PresentationDetent = .medium
    @State private var showMergeUndoBanner = false
    @FocusState private var isCustomTitleFocused: Bool

    private enum MergeNameSheetPhase {
        case choose
        case editCustom
    }

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

            if showMergeUndoBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("Blogs have been merged")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button("Undo") {
                            createdRecapStore.undoMerge()
                            withAnimation {
                                showMergeUndoBanner = false
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(appChromeBaseRadius: 14, style: .continuous)
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
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Back")
            }
        }
        .sheet(isPresented: $showMergeNameSheet, onDismiss: {
            namePickPair = nil
            mergeNameSheetPhase = .choose
            customMergeTitleText = ""
            mergeNameSheetDetent = .medium
        }) {
            mergeBlogNameSheetContent
                .presentationDetents([.medium, .large], selection: $mergeNameSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var mergeBlogNameSheetContent: some View {
        if let pair = namePickPair {
            VStack(spacing: 0) {
                switch mergeNameSheetPhase {
                case .choose:
                    mergeNameChoosePane(pair: pair)
                case .editCustom:
                    mergeNameEditPane(pair: pair)
                }
            }
            .padding(.top, 24)
        }
    }

    private func mergeNameChoosePane(pair: MergePair) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "textformat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Blog Name")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("Which name do you prefer, or do you want to give it a different name?")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                mergeNameChoiceButton(title: pair.earlier.title) {
                    completeMerge(pair: pair, pickedFullTitle: pair.earlier.title)
                }
                mergeNameChoiceButton(title: pair.later.title) {
                    completeMerge(pair: pair, pickedFullTitle: pair.later.title)
                }

                Button {
                    primeCustomMergeTitle(for: pair)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mergeNameSheetPhase = .editCustom
                    }
                    mergeNameSheetDetent = .large
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isCustomTitleFocused = true
                    }
                } label: {
                    Text("Edit Blog Title")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(appChromeBaseRadius: 12)
                                .strokeBorder(Color.blue, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func mergeNameEditPane(pair: MergePair) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mergeNameSheetPhase = .choose
                    }
                    mergeNameSheetDetent = .medium
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom title")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Enter a name for the merged blog.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                TextField("Blog title", text: $customMergeTitleText)
                    .focused($isCustomTitleFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                    .onSubmit {
                        let t = customMergeTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty {
                            completeMerge(pair: pair, pickedFullTitle: t)
                        }
                    }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                let t = customMergeTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                completeMerge(pair: pair, pickedFullTitle: t)
            } label: {
                Text("Use this title")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func mergeNameChoiceButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func primeCustomMergeTitle(for pair: MergePair) {
        let a = CreatedRecapBlogStore.titleByStrippingSplitPartSuffix(pair.earlier.title)
        customMergeTitleText = a.isEmpty ? pair.earlier.title : a
    }

    private func completeMerge(pair: MergePair, pickedFullTitle: String) {
        var merged = CreatedRecapBlogStore.titleByStrippingSplitPartSuffix(pickedFullTitle)
        if merged.isEmpty { merged = pickedFullTitle }
        createdRecapStore.mergeBlogs(
            keepId: pair.earlier.sourceTripId,
            absorbId: pair.later.sourceTripId,
            mergedTitle: merged
        )
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        namePickPair = nil
        showMergeNameSheet = false
        mergeNameSheetPhase = .choose
        customMergeTitleText = ""
        mergeNameSheetDetent = .medium
        withAnimation {
            showMergeUndoBanner = true
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
                namePickPair = pair
                mergeNameSheetPhase = .choose
                mergeNameSheetDetent = .medium
                showMergeNameSheet = true
            } label: {
                Text("Merge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(appChromeBaseRadius: 16))
    }

    private func photoCount(for blog: CreatedRecapBlog) -> Int {
        createdRecapStore.getBlogDetail(blogId: blog.sourceTripId)?.allIncludedPhotos.count ?? 0
    }

    private func blogMiniCard(_ blog: CreatedRecapBlog) -> some View {
        let photoSide: CGFloat = 88
        let textWidth = photoSide + 12
        let photoCornerRadius: CGFloat = 16

        return VStack(spacing: 6) {
            AssetPhotoView(
                assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                cornerRadius: 0,
                targetSize: CGSize(width: photoSide * 2, height: photoSide * 2)
            )
            .frame(width: photoSide, height: photoSide)
            .clipShape(RoundedRectangle(appChromeBaseRadius: photoCornerRadius, style: .continuous))

            Text(blog.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textWidth)

            let count = photoCount(for: blog)
            Text("\(blog.tripDateRangeText ?? "") \(count) Photos")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textWidth)
        }
    }
}
