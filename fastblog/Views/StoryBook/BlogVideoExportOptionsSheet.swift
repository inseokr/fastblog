// fastblog/Views/StoryBook/BlogVideoExportOptionsSheet.swift
import SwiftUI

/// Options sheet for exporting a blog as a Cinematic Journey video.
/// Controls captions, seconds-per-photo, photos per place, and which places to include.
struct BlogVideoExportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: RecapBlogDetail
    /// Called on the main actor with the exported video URL after the sheet dismisses.
    let onShare: (URL) -> Void

    @AppStorage("blogVideoExportOptions") private var optionsData: Data =
        (try? JSONEncoder().encode(BlogVideoExportOptions())) ?? Data()
    @State private var options      = BlogVideoExportOptions()
    @State private var isExporting  = false
    @State private var progress: Double = 0
    @State private var exportError: String? = nil
    @State private var showError = false
    @State private var showMusicPicker = false
    @State private var exportTask: Task<Void, Never>?

    private var selectedTrack: SlideshowBundledTrack? {
        guard let fn = options.musicFilename else { return nil }
        return SlideshowBundledMusicLibrary.tracksInAppBundle().first { $0.filename == fn }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        estimatedPlayTimeSection
                        photosPerPlaceSection
                        durationSection
                        photoCaptionsSection
                        musicSection
                        categoryFilterSection
                        placesSection
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
                        selectedFilename: options.musicFilename,
                        onPickTrack: { options.musicFilename = $0.filename },
                        onPickNone: { options.musicFilename = nil },
                        onCancel: {}
                    )
                }
                .alert("Export Failed", isPresented: $showError) {
                    Button("OK") {}
                } message: {
                    Text(exportError ?? "Unknown error.")
                }
            }

            if isExporting {
                LoadingScanView(
                    message: "Creating Video…",
                    isOverlay: true,
                    overlayTint: .modalGrayGlass,
                    progress: progress,
                    onCancel: { cancelExport() },
                    progressStepLabelOverride: { p in Self.exportProgressSubtitle(progress: p) },
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
            // Reset place selection if it belongs to a different blog (stale UUIDs).
            if let ids = options.includedPlaceIDs {
                let currentIDs = Set(draft.days.flatMap { $0.placeStops.map { $0.id } })
                if ids.isDisjoint(with: currentIDs) {
                    options.includedPlaceIDs = nil
                }
            }
        }
    }

    // MARK: - Photo Captions Section

    private var photoCaptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Photo Captions", icon: "text.bubble")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show captions on photos")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Display photo captions as text overlays on slides")
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

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Seconds Per Photo", icon: "timer")
            HStack(spacing: 8) {
                ForEach([2.0, 3.0, 5.0], id: \.self) { secs in
                    durationPill(seconds: secs)
                }
            }
        }
    }

    private func durationPill(seconds: Double) -> some View {
        let selected = options.secondsPerSlide == seconds
        return Button { options.secondsPerSlide = seconds } label: {
            Text("\(Int(seconds))s")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                .foregroundColor(selected ? .white : .primary)
                .appChromeCornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photos Per Place Section

    private var photosPerPlaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Maximum Photos Per Place", icon: "photo.stack")
            HStack(spacing: 8) {
                ForEach([1, 2, 3, 5], id: \.self) { count in
                    photosPerPlacePill(count: count)
                }
            }
        }
    }

    private func photosPerPlacePill(count: Int) -> some View {
        let selected = options.maxPhotosPerPlace == count
        return Button { options.maxPhotosPerPlace = count } label: {
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                .foregroundColor(selected ? .white : .primary)
                .appChromeCornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Places Section

    private var placesSection: some View {
        let days = filteredDaysForPlacePicker()
        let highlightIDs = highlightIDsForVisibleStops()
        let highlightSelected = isHighlightsOnlySelected(highlightIDs: highlightIDs)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Places", icon: "mappin.and.ellipse")
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectHighlightsOnly()
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
                            if options.includedPlaceIDs == nil {
                                options.includedPlaceIDs = []
                            } else {
                                options.includedPlaceIDs = nil
                            }
                        }
                    } label: {
                        Text(options.includedPlaceIDs == nil ? "Deselect All" : "Select All")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { dayOffset, day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Day \(dayOffset + 1) · \(day.dateText)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            VStack(spacing: 8) {
                                ForEach(day.placeStops) { stop in
                                    placeCheckRow(stop: stop)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func highlightIDsForVisibleStops() -> Set<UUID> {
        let stops = filteredDaysForPlacePicker().flatMap(\.placeStops)
        let avg = stops.map(\.highlightMomentScore).reduce(0, +) / Double(max(stops.count, 1))
        return Set(stops.filter { $0.highlightMomentScore > avg }.map(\.id))
    }

    private func isHighlightsOnlySelected(highlightIDs: Set<UUID>) -> Bool {
        guard let ids = options.includedPlaceIDs else { return false }
        return ids == highlightIDs
    }

    private func placeCheckRow(stop: PlaceStop) -> some View {
        let isIncluded = isPlaceIncluded(stop.id)
        let photos = Array(stop.includedPhotos.prefix(options.maxPhotosPerPlace))
        let gap: CGFloat = 2
        let cardW = UIScreen.main.bounds.width - 40
        let cellW = floor((cardW - gap) / 2)
        let gridH = placeGridHeight(count: photos.count, cardW: cardW, cellW: cellW, gap: gap)
        let overflowCount = max(0, stop.includedPhotos.count - photos.count)
        return Button { togglePlace(stop.id) } label: {
            ZStack(alignment: .bottomLeading) {
                placePhotoGrid(photos: photos, overflowCount: overflowCount, cardW: cardW, cellW: cellW, gap: gap)

                if !isIncluded {
                    Color.black.opacity(0.5)
                        .frame(width: cardW, height: gridH)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    if let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !raw.isEmpty {
                        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
                        HStack(spacing: 4) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(p.label)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(p.color.opacity(0.85)))
                        .foregroundColor(.white)
                    }
                    Text(stop.placeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.trailing, 40)
                }
                .padding(10)

                ZStack {
                    Circle()
                        .fill(isIncluded ? Color.accentColor : Color.black.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isIncluded ? 0 : 0.6), lineWidth: 1.5)
                        )
                    if isIncluded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            }
            .frame(width: cardW, height: gridH)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isIncluded ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeGridHeight(count: Int, cardW: CGFloat, cellW: CGFloat, gap: CGFloat) -> CGFloat {
        switch count {
        case 0:       return 120
        case 1:       return cardW
        case 2:       return cellW
        case 3, 4:    return cellW * 2 + gap
        default:      return cellW * 3 + gap * 2
        }
    }

    @ViewBuilder
    private func placePhotoGrid(photos: [RecapPhoto], overflowCount: Int, cardW: CGFloat, cellW: CGFloat, gap: CGFloat) -> some View {
        switch photos.count {
        case 0:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: cardW, height: 120)
        case 1:
            placePhotoCell(photos[0], width: cardW, height: cardW)
        case 2:
            HStack(spacing: gap) {
                placePhotoCell(photos[0], width: cellW, height: cellW)
                placePhotoCell(photos[1], width: cellW, height: cellW)
            }
        case 3:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    placePhotoCell(photos[0], width: cellW, height: cellW)
                    placePhotoCell(photos[1], width: cellW, height: cellW)
                }
                placePhotoCell(photos[2], width: cardW, height: cellW)
            }
        case 4:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    placePhotoCell(photos[0], width: cellW, height: cellW)
                    placePhotoCell(photos[1], width: cellW, height: cellW)
                }
                HStack(spacing: gap) {
                    placePhotoCell(photos[2], width: cellW, height: cellW)
                    placePhotoCell(photos[3], width: cellW, height: cellW)
                }
            }
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    placePhotoCell(photos[0], width: cellW, height: cellW)
                    placePhotoCell(photos[1], width: cellW, height: cellW)
                }
                HStack(spacing: gap) {
                    placePhotoCell(photos[2], width: cellW, height: cellW)
                    placePhotoCell(photos[3], width: cellW, height: cellW)
                }
                ZStack {
                    placePhotoCell(photos[4], width: cardW, height: cellW)
                    if overflowCount > 0 {
                        Color.black.opacity(0.45)
                            .frame(width: cardW, height: cellW)
                        Text("+\(overflowCount)")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private func placePhotoCell(_ photo: RecapPhoto, width: CGFloat, height: CGFloat) -> some View {
        RecapPhotoThumbnail(
            photo: photo,
            cornerRadius: 0,
            showIcon: false,
            targetSize: CGSize(width: 300, height: 300)
        )
        .frame(width: width, height: height)
        .clipped()
    }

    private func selectHighlightsOnly() {
        let highlightIDs = highlightIDsForVisibleStops()
        options.includedPlaceIDs = highlightIDs.isEmpty ? nil : highlightIDs
    }

    private func isPlaceIncluded(_ id: UUID) -> Bool {
        guard let ids = options.includedPlaceIDs else { return true }
        return ids.contains(id)
    }

    private func togglePlace(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if options.includedPlaceIDs == nil {
                var all = Set(draft.days.flatMap { $0.placeStops.map { $0.id } })
                all.remove(id)
                options.includedPlaceIDs = all.isEmpty ? nil : all
            } else if options.includedPlaceIDs!.contains(id) {
                options.includedPlaceIDs!.remove(id)
            } else {
                options.includedPlaceIDs!.insert(id)
                let allIDs = Set(draft.days.flatMap { $0.placeStops.map { $0.id } })
                if options.includedPlaceIDs == allIDs {
                    options.includedPlaceIDs = nil
                }
            }
        }
    }

    // MARK: - Music Section

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Background Music", icon: "music.note")
            Button { showMusicPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTrack?.displayTitle ?? "No background music")
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
        }
    }

    // MARK: - Export Button

    private static func exportProgressSubtitle(progress p: Double) -> String {
        if p < 0.1  { return "Building journey…" }
        if p < 0.50 { return "Loading places & photos…" }
        if p < 0.72 { return "Rendering map frames…" }
        if p < 0.86 { return "Writing video…" }
        return "Adding music…"
    }

    private var exportButton: some View {
        Button { startExport() } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                Text("Export & Share")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor.opacity(isExporting ? 0.45 : 1))
            .foregroundColor(.white)
            .appChromeCornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
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
        if let data = try? JSONEncoder().encode(options) { optionsData = data }
        exportTask?.cancel()
        isExporting = true
        progress = 0.02

        exportTask = Task { @MainActor in
            defer { exportTask = nil }
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
            Text("\(stats.includedPlaceCount) places · \(stats.includedPhotoCount) photos")
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

    private func estimatedPlaybackStats() -> (includedPlaceCount: Int, includedPhotoCount: Int, estimatedSeconds: Double, estimatedDurationText: String) {
        let stops = filteredDaysForPlacePicker().flatMap(\.placeStops).filter { isPlaceIncluded($0.id) }
        let photoCount = stops.reduce(0) { acc, stop in
            acc + min(options.maxPhotosPerPlace, stop.includedPhotos.count)
        }
        let seconds = Double(photoCount) * options.secondsPerSlide
        return (
            includedPlaceCount: stops.count,
            includedPhotoCount: photoCount,
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

    // MARK: - Category Filter

    private var categoryFilterSection: some View {
        let available = availableCategoryRawsForDraft()
        guard !available.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("Categories", icon: "line.3.horizontal.decrease.circle")
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if options.includedPlaceCategoryRaws == nil {
                                options.includedPlaceCategoryRaws = []
                            } else {
                                options.includedPlaceCategoryRaws = nil
                            }
                        }
                    } label: {
                        Text(options.includedPlaceCategoryRaws == nil ? "Deselect All" : "Select All")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
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
        )
    }

    private func categoryPill(raw: String) -> some View {
        let isSelected = isCategoryIncluded(raw)
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        return Button {
            toggleCategory(raw)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : p.color)
                Text(p.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? p.color : p.color.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(p.color.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
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
            let all = Set(availableCategoryRawsForDraft())
            if options.includedPlaceCategoryRaws == nil {
                options.includedPlaceCategoryRaws = all.subtracting([raw])
            } else if options.includedPlaceCategoryRaws!.contains(raw) {
                options.includedPlaceCategoryRaws!.remove(raw)
            } else {
                options.includedPlaceCategoryRaws!.insert(raw)
                if options.includedPlaceCategoryRaws == all {
                    options.includedPlaceCategoryRaws = nil
                }
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
        guard let cats = options.includedPlaceCategoryRaws else { return options }
        let allowedIDs: Set<UUID> = Set(
            draft.days.flatMap(\.placeStops).filter { stop in
                let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (raw == nil || raw?.isEmpty == true) ? "Others" : raw!
                return cats.contains(key)
            }.map(\.id)
        )
        var effective = options
        effective.includedPlaceIDs = {
            if let ids = options.includedPlaceIDs {
                let filtered = ids.intersection(allowedIDs)
                return filtered.isEmpty ? [] : filtered
            }
            return allowedIDs
        }()
        return effective
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
