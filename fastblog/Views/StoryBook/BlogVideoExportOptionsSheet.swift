// fastblog/Views/StoryBook/BlogVideoExportOptionsSheet.swift
import SwiftUI

/// Options sheet for stitching moment reels into a cinematic share video.
struct BlogVideoExportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: RecapBlogDetail
    /// Called on the main actor with the exported video URL after the sheet dismisses.
    let onShare: (URL) -> Void
    /// Opens the in-app camera in Reel mode when the blog has no reels to export.
    let onRequestReelCapture: () -> Void

    @AppStorage("blogVideoExportOptions") private var optionsData: Data =
        (try? JSONEncoder().encode(BlogVideoExportOptions())) ?? Data()
    @State private var options       = BlogVideoExportOptions()
    @State private var isExporting   = false
    @State private var progress: Double = 0
    @State private var exportError: String? = nil
    @State private var showError     = false
    @State private var showMusicPicker = false
    @State private var showNoReelsAlert = false
    @State private var exportTask: Task<Void, Never>?

    private var selectedReelCount: Int {
        BlogVideoExportService.exportableReelCount(draft: draft, options: effectiveExportOptions())
    }

    private var canExport: Bool { selectedReelCount > 0 }

    private var selectedTrack: SlideshowBundledTrack? {
        if options.musicDisabled { return nil }
        let fn = options.musicFilename ?? SlideshowMusicPreference.defaultFilename
        return SlideshowBundledMusicLibrary.tracksInAppBundle().first { $0.filename == fn }
    }

    private var musicSectionPrimaryLabel: String {
        if options.musicDisabled { return "No background music" }
        if let t = selectedTrack { return t.displayTitle }
        let stem = URL(fileURLWithPath: SlideshowMusicPreference.defaultFilename)
            .deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "Default music" : stem.localizedCapitalized
    }

    private var musicPickerSelectedFilename: String? {
        if options.musicDisabled { return nil }
        return options.musicFilename ?? SlideshowMusicPreference.defaultFilename
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        estimatedPlayTimeSection
                        if !canExport {
                            noReelsHintBanner
                        }
                        videoStyleSection
                        if options.videoStyle == .cinematic {
                            reelCaptionsSection
                            mapSegmentsSection
                            dayItineraryCardsSection
                        }
                        musicSection
                        reelsSection
                    }
                    .padding(20)
                    .padding(.bottom, 8)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider().opacity(0.35)
                        exportButton
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
                .navigationTitle("Video Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .disabled(isExporting)
                    }
                }
                .preferredColorScheme(.dark)
                .sheet(isPresented: $showMusicPicker) {
                    SlideshowBundledTrackPickerSheet(
                        tracks: SlideshowBundledMusicLibrary.tracksInAppBundle(),
                        selectedFilename: musicPickerSelectedFilename,
                        onPickTrack: {
                            options.musicDisabled = false
                            options.musicFilename = $0.filename
                        },
                        onPickNone: {
                            options.musicDisabled = true
                            options.musicFilename = nil
                        },
                        onCancel: {}
                    )
                }
                .alert("Export Failed", isPresented: $showError) {
                    Button("OK") {}
                } message: {
                    Text(exportError ?? "Unknown error.")
                }
                .alert("No reels to stitch", isPresented: $showNoReelsAlert) {
                    Button("Open Camera") {
                        dismiss()
                        onRequestReelCapture()
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Capture short moment reels with the in-app camera (Reel mode), then come back to create your video.")
                }
            }

            if isExporting {
                LoadingScanView(
                    message: "Creating Video…",
                    isOverlay: true,
                    overlayTint: .modalGrayGlass,
                    progress: progress,
                    onCancel: { cancelExport() },
                    progressStepLabelOverride: { p in exportProgressSubtitle(progress: p) },
                    useCenteredLayout: true,
                    showsTopTrailingActions: false
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.22)))
                .allowsHitTesting(true)
                .zIndex(1)
            }
        }
        .onAppear {
            options = (try? JSONDecoder().decode(BlogVideoExportOptions.self, from: optionsData))
                ?? BlogVideoExportOptions()
            options.exportMode = .video
            // Reset reel selection if it belongs to a different blog (stale UUIDs).
            if let ids = options.includedReelPhotoIDs {
                let currentIDs = CinematicBlogVideoBuilder.allExportableReelPhotoIDs(draft: draft)
                if ids.isDisjoint(with: currentIDs) {
                    options.includedReelPhotoIDs = nil
                }
            }
            if !canExport {
                showNoReelsAlert = true
            }
        }
    }

    private var noReelsHintBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "video.badge.plus")
                .font(.title3)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("No moment reels yet")
                    .font(.subheadline.weight(.semibold))
                Text("Use the in-app camera in Reel mode to capture short clips at each place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .appChromeCornerRadius(12)
    }

    // MARK: - Video Style Section

    private var isSimpleStitch: Bool { options.videoStyle == .simpleStitch }

    private var videoStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Video Style", icon: "film.stack")
            VStack(spacing: 0) {
                optionRow(
                    title: "Cinematic blog",
                    subtitle: "Cover, maps, place names & timestamps",
                    isSelected: options.videoStyle == .cinematic
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        options.videoStyle = .cinematic
                    }
                }
                Divider().padding(.leading, 46)
                optionRow(
                    title: "Simple stitch",
                    subtitle: "Selected reels concatenated — no title cards, maps, or overlays",
                    isSelected: options.videoStyle == .simpleStitch
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        options.videoStyle = .simpleStitch
                        options.showMapFrames = false
                        options.showDayItineraryCards = false
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Map Segments Section

    private var mapSegmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Map Segments", icon: "map")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include map in video")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(options.showMapFrames
                         ? "Map pan, zoom & iris transitions between reel clips"
                         : "Reels only — no map transitions between places")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $options.showMapFrames)
                    .labelsHidden()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Day Itinerary Cards Section

    private var dayItineraryCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Day Itinerary Cards", icon: "list.bullet.clipboard")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show day itinerary before each day")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(options.showMapFrames ? .primary : .secondary)
                    Text(options.showMapFrames
                         ? "Injects a 2-second card listing all places for each travel day"
                         : "Requires map segments to be enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $options.showDayItineraryCards)
                    .labelsHidden()
                    .disabled(!options.showMapFrames)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Reel Captions Section

    private var reelCaptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Reel Captions", icon: "text.bubble")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show captions on reels")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Overlay photo or place captions on each reel clip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $options.showPhotoCaptions)
                    .labelsHidden()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    private struct ReelPickerItem: Identifiable {
        let id: UUID
        let photo: RecapPhoto
        let stop: PlaceStop
        let dayLabel: String
    }

    // MARK: - Reels Section

    private var reelsSection: some View {
        let available = availableCategoryRawsForDraft()
        let items = visibleReelPickerItems()
        let highlightIDs = highlightStopIDsForVisibleReels()
        let highlightSelected = isHighlightsOnlyReelSelection(highlightStopIDs: highlightIDs)
        let isAllCategoriesSelected = options.includedPlaceCategoryRaws == nil
        let allReelsSelected = options.includedReelPhotoIDs == nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Reels", icon: "film")
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectHighlightReelsOnly(highlightStopIDs: highlightIDs)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: highlightSelected ? "checkmark.circle.fill" : "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Highlights")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(highlightSelected
                                      ? Color(red: 1.0, green: 0.84, blue: 0.0)
                                      : Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                        .foregroundColor(highlightSelected ? .black : Color(red: 1.0, green: 0.84, blue: 0.0))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if allReelsSelected {
                                options.includedReelPhotoIDs = []
                            } else {
                                options.includedReelPhotoIDs = nil
                            }
                        }
                    } label: {
                        Text(allReelsSelected ? "Deselect All" : "Select All")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
            }

            if !available.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" pill
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                options.includedPlaceCategoryRaws = nil
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.caption.weight(.semibold))
                                Text("All")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                if isAllCategoriesSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isAllCategoriesSelected
                                          ? Color.accentColor
                                          : Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.4))
                            )
                            .foregroundColor(isAllCategoriesSelected ? .white : Color.secondary.opacity(0.45))
                        }
                        .buttonStyle(.plain)

                        ForEach(available, id: \.self) { raw in
                            categoryPill(raw: raw)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .appChromeCornerRadius(12)
            }

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedReelPickerItems(items), id: \.dayLabel) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.dayLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            VStack(spacing: 8) {
                                ForEach(group.items) { item in
                                    reelCheckRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct ReelDayGroup {
        let dayLabel: String
        let items: [ReelPickerItem]
    }

    private func visibleReelPickerItems() -> [ReelPickerItem] {
        filteredDaysForPlacePicker().flatMap { day in
            let dayNumber = (draft.days.firstIndex(where: { $0.id == day.id }) ?? 0) + 1
            let dayLabel = "Day \(dayNumber) · \(day.dateText)"
            return day.placeStops.flatMap { stop in
                CinematicBlogVideoBuilder.exportableReelPhotos(for: stop).map { photo in
                    ReelPickerItem(id: photo.id, photo: photo, stop: stop, dayLabel: dayLabel)
                }
            }
        }
    }

    private func groupedReelPickerItems(_ items: [ReelPickerItem]) -> [ReelDayGroup] {
        var order: [String] = []
        var buckets: [String: [ReelPickerItem]] = [:]
        for item in items {
            if buckets[item.dayLabel] == nil {
                order.append(item.dayLabel)
                buckets[item.dayLabel] = []
            }
            buckets[item.dayLabel, default: []].append(item)
        }
        return order.map { ReelDayGroup(dayLabel: $0, items: buckets[$0] ?? []) }
    }

    private func allVisibleReelPhotoIDs() -> Set<UUID> {
        Set(visibleReelPickerItems().map(\.id))
    }

    private func highlightStopIDsForVisibleReels() -> Set<UUID> {
        let stops = filteredDaysForPlacePicker().flatMap(\.placeStops)
        let avg = stops.map(\.highlightMomentScore).reduce(0, +) / Double(max(stops.count, 1))
        return Set(stops.filter { $0.highlightMomentScore > avg }.map(\.id))
    }

    private func isHighlightsOnlyReelSelection(highlightStopIDs: Set<UUID>) -> Bool {
        guard let ids = options.includedReelPhotoIDs else { return false }
        let highlightReelIDs = Set(
            visibleReelPickerItems().filter { highlightStopIDs.contains($0.stop.id) }.map(\.id)
        )
        return ids == highlightReelIDs && !highlightReelIDs.isEmpty
    }

    private func selectHighlightReelsOnly(highlightStopIDs: Set<UUID>) {
        let highlightReelIDs = Set(
            visibleReelPickerItems().filter { highlightStopIDs.contains($0.stop.id) }.map(\.id)
        )
        options.includedReelPhotoIDs = highlightReelIDs.isEmpty ? [] : highlightReelIDs
    }

    private func isReelIncluded(_ photoID: UUID) -> Bool {
        guard let ids = options.includedReelPhotoIDs else { return true }
        return ids.contains(photoID)
    }

    private func toggleReel(_ photoID: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            let visible = allVisibleReelPhotoIDs()
            if options.includedReelPhotoIDs == nil {
                var all = visible
                all.remove(photoID)
                options.includedReelPhotoIDs = all
            } else if options.includedReelPhotoIDs!.contains(photoID) {
                options.includedReelPhotoIDs!.remove(photoID)
            } else {
                options.includedReelPhotoIDs!.insert(photoID)
                if options.includedReelPhotoIDs == visible {
                    options.includedReelPhotoIDs = nil
                }
            }
        }
    }

    private func reelCheckRow(item: ReelPickerItem) -> some View {
        let isIncluded = isReelIncluded(item.id)
        let thumbSide: CGFloat = 72
        let timeLabel = CinematicBlogVideoBuilder.photoSlideTimeDisplayText(for: item.photo, stop: item.stop)
        return Button { toggleReel(item.id) } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RecapPhotoThumbnail(
                        photo: item.photo,
                        cornerRadius: 10,
                        showIcon: false,
                        targetSize: CGSize(width: thumbSide * 2, height: thumbSide * 2)
                    )
                    .frame(width: thumbSide, height: thumbSide)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Image(systemName: "film.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .padding(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.stop.placeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    if let caption = item.photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(isIncluded ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: 26, height: 26)
                    if isIncluded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .opacity(isIncluded ? 1 : 0.55)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isIncluded ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .appChromeCornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Music Section

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Background Music", icon: "music.note")
            Button { showMusicPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(musicSectionPrimaryLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text("Tap to change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .appChromeCornerRadius(12)
            }
            .buttonStyle(.plain)

            if !options.musicDisabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Music volume")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int((options.musicVolume * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(options.musicVolume) },
                            set: { options.musicVolume = Float(min(1, max(0, $0))) }
                        ),
                        in: 0...1
                    )
                    .tint(.accentColor)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .appChromeCornerRadius(12)
            }
        }
    }

    // MARK: - Export Button

    private func exportProgressSubtitle(progress p: Double) -> String {
        if p < 0.1  { return "Preparing reel video…" }
        if p < 0.50 { return "Loading reels…" }
        if isSimpleStitch {
            if p < 0.86 { return "Stitching reels…" }
            return "Adding music…"
        }
        if p < 0.72 { return "Rendering map frames…" }
        if p < 0.86 { return "Stitching reels…" }
        return "Adding music…"
    }

    private var exportButton: some View {
        Button { startExport() } label: {
            HStack(spacing: 8) {
                Image(systemName: "film")
                Text("Export & Share")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor.opacity(isExporting || !canExport ? 0.45 : 1))
            .foregroundColor(.white)
            .appChromeCornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isExporting || !canExport)
    }

    // MARK: - Export Action

    @MainActor
    private func cancelExport() {
        exportTask?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            isExporting = false
            progress = 0
        }
    }

    @MainActor
    private func startExport() {
        guard canExport else {
            showNoReelsAlert = true
            return
        }
        options.exportMode = .video
        if let data = try? JSONEncoder().encode(options) { optionsData = data }
        exportTask?.cancel()
        isExporting = true
        progress = 0.02
        startVideoExport()
    }

    @MainActor
    private func startVideoExport() {
        exportTask = Task { @MainActor in
            defer {
                exportTask = nil
                BlogVideoExportService.releaseExportWorkingSet()
            }
            do {
                progress = 0.1
                let effective = effectiveExportOptions()
                let url = try await BlogVideoExportService.exportVideo(
                    draft: draft,
                    options: effective,
                    progressHandler: { p in
                        progress = 0.1 + p * 0.9
                    }
                )
                isExporting = false
                dismiss()
                onShare(url)
            } catch is CancellationError {
                isExporting = false
                progress = 0
            } catch {
                isExporting = false
                exportError = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Estimated Video Length

    private var estimatedPlayTimeSection: some View {
        let stats = estimatedPlaybackStats()
        return HStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.0, green: 0.85, blue: 1.0),
                                 Color(red: 0.2, green: 0.5, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated Video Length")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(stats.estimatedDurationText)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("\(stats.includedPlaceCount) places · \(stats.includedReelCount) reels")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func estimatedPlaybackStats() -> (includedPlaceCount: Int, includedReelCount: Int, estimatedSeconds: Double, estimatedDurationText: String) {
        let resolved = effectiveExportOptions()
        let placeCount = filteredDaysForPlacePicker().flatMap(\.placeStops).filter { stop in
            if let placeIDs = resolved.includedPlaceIDs, !placeIDs.contains(stop.id) { return false }
            return !CinematicBlogVideoBuilder.exportableReelPhotos(
                for: stop,
                includedReelPhotoIDs: resolved.includedReelPhotoIDs
            ).isEmpty
        }.count
        let reelCount = BlogVideoExportService.exportableReelCount(draft: draft, options: resolved)
        let seconds = BlogVideoExportService.estimatedExportedVideoDurationSeconds(draft: draft, options: resolved)
        return (
            includedPlaceCount: placeCount,
            includedReelCount: reelCount,
            estimatedSeconds: seconds,
            estimatedDurationText: formatDuration(seconds: seconds)
        )
    }

    private func formatDuration(seconds: Double) -> String {
        let clamped = max(0, seconds)
        let total = Int(clamped.rounded())
        let mins = total / 60
        let secs = total % 60
        if mins > 0 {
            return "\(mins)m \(String(format: "%02d", secs))s"
        }
        return "\(secs)s"
    }

    private func categoryPill(raw: String) -> some View {
        let isAllActive = options.includedPlaceCategoryRaws == nil
        // A pill is "on" only when specific categories are chosen AND this one is in the set
        let isSelected = !isAllActive && isCategoryIncluded(raw)
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        return Button {
            toggleCategory(raw)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                Text(p.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected
                          ? p.color
                          : Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.4))
            )
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary.opacity(0.45)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func availableCategoryRawsForDraft() -> [String] {
        let rawSet: Set<String> = Set(draft.days.flatMap(\.placeStops).compactMap { stop in
            stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        let hasOthers = draft.days.flatMap(\.placeStops).contains { stop in
            let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty
        }

        return PlacePOICategoryCatalog.categoryRawsAppearingInDataForFilters(
            dataRaws: rawSet,
            includeOthers: hasOthers
        )
    }

    private func isCategoryIncluded(_ raw: String) -> Bool {
        guard let set = options.includedPlaceCategoryRaws else { return true }
        return set.contains(raw)
    }

    private func toggleCategory(_ raw: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if options.includedPlaceCategoryRaws == nil {
                // "All" active → select just this category
                options.includedPlaceCategoryRaws = [raw]
            } else if options.includedPlaceCategoryRaws!.contains(raw) {
                // Already selected → deselect; revert to All if nothing left
                options.includedPlaceCategoryRaws!.remove(raw)
                if options.includedPlaceCategoryRaws!.isEmpty {
                    options.includedPlaceCategoryRaws = nil
                }
            } else {
                // Not selected → add to selection
                options.includedPlaceCategoryRaws!.insert(raw)
            }
        }
    }

    private func filteredDaysForPlacePicker() -> [RecapBlogDay] {
        let days = draft.days.filter { !$0.placeStops.isEmpty }
        guard let cats = options.includedPlaceCategoryRaws else { return days }
        return days.compactMap { day in
            let filteredStops = day.placeStops.filter { stop in
                let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (raw == nil || raw?.isEmpty == true) ? "Others" : raw!
                return cats.contains(key)
            }
            guard !filteredStops.isEmpty else { return nil }
            var d = day
            d.placeStops = filteredStops
            return d
        }
    }

    private func effectiveExportOptions() -> BlogVideoExportOptions {
        options.effectiveForExport(draft: draft)
    }

    // MARK: - Shared UI helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.0, green: 0.85, blue: 1.0),
                             Color(red: 0.2, green: 0.5, blue: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    private func optionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: 32, height: 32)
                    Image(systemName: isSelected ? "checkmark" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
