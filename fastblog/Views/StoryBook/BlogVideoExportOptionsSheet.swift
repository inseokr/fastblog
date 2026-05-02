// fastblog/Views/StoryBook/BlogVideoExportOptionsSheet.swift
import SwiftUI

/// Options sheet for exporting a blog as a video.
/// Supports two styles:
/// - **Cinematic Journey** (default): map animations + full-frame photo slides built from `RecapBlogDetail`.
/// - **Story Pages**: renders the full blog layout pages (original PDF-page style).
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
                        videoStyleSection
                        if options.videoStyle == .cinematic {
                            mapAnimationQualitySection
                        }
                        durationSection
                        if options.videoStyle == .storyPages {
                            colorStyleSection
                            fontThemeSection
                        }
                        musicSection
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
                    progressStepLabelOverride: { p in Self.exportProgressSubtitle(progress: p, videoStyle: options.videoStyle) },
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
        }
    }

    // MARK: - Video Style Section

    private var videoStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Video Style", icon: "film.stack")
            VStack(spacing: 0) {
                ForEach(VideoStyle.allCases, id: \.self) { style in
                    optionRow(
                        title: style.label,
                        subtitle: style.subtitle,
                        isSelected: options.videoStyle == style
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            options.videoStyle = style
                        }
                    }
                    if style != VideoStyle.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Map motion (Cinematic only)

    private var mapAnimationQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Map motion", icon: "map")
            VStack(spacing: 0) {
                ForEach(MapAnimationQuality.allCases, id: \.self) { quality in
                    optionRow(
                        title: quality.label,
                        subtitle: quality.subtitle,
                        isSelected: options.mapAnimationQuality == quality
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            options.mapAnimationQuality = quality
                        }
                    }
                    if quality != MapAnimationQuality.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                options.videoStyle == .cinematic ? "Seconds Per Photo" : "Slide Duration",
                icon: "timer"
            )
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

    // MARK: - Color Style Section (Story Pages only)

    private var colorStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Color Style", icon: "circle.lefthalf.filled")
            VStack(spacing: 0) {
                ForEach(BlogColor.allCases, id: \.self) { style in
                    optionRow(title: style.label, subtitle: style.subtitle,
                              isSelected: options.colorStyle == style) {
                        options.colorStyle = style
                    }
                    if style != BlogColor.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    // MARK: - Font Theme Section (Story Pages only)

    private var fontThemeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Font Style", icon: "textformat")
            VStack(spacing: 0) {
                ForEach(FontTheme.allCases, id: \.self) { theme in
                    optionRow(title: theme.label, subtitle: theme.subtitle,
                              isSelected: options.fontTheme == theme) {
                        options.fontTheme = theme
                    }
                    if theme != FontTheme.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
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

    /// Subtitle under “Creating Video…” — matches trip-style progress bands (driven by 0…1 export progress).
    private static func exportProgressSubtitle(progress p: Double, videoStyle: VideoStyle) -> String {
        if videoStyle == .cinematic {
            if p < 0.1  { return "Building journey…" }
            if p < 0.50 { return "Loading places & photos…" }
            if p < 0.72 { return "Rendering map frames…" }
            if p < 0.86 { return "Writing video…" }
            return "Adding music…"
        } else {
            if p < 0.1  { return "Building slideshow…" }
            if p < 0.72 { return "Rendering slides…" }
            if p < 0.86 { return "Writing video…" }
            return "Adding music…"
        }
    }

    private var exportButton: some View {
        Button { startExport() } label: {
            HStack(spacing: 8) {
                Image(systemName: options.videoStyle == .cinematic ? "map.fill" : "video.badge.checkmark")
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
                var pages: [StoryPage] = []

                if options.videoStyle == .storyPages {
                    // Story-pages mode: build the full page layout (same as story mode / PDF export).
                    let content = await StoryBookBuilder.build(from: draft)
                    try Task.checkCancellation()
                    pages = StoryPageLayout.buildPages(from: content, fontTheme: options.fontTheme)
                    guard !pages.isEmpty else { throw BlogVideoExportService.ExportError.noPages }
                }
                progress = 0.1

                let url = try await BlogVideoExportService.exportVideo(
                    pages: pages,
                    draft: draft,
                    options: options,
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
