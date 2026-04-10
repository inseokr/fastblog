// fastblog/Views/StoryBook/BlogVideoExportOptionsSheet.swift
import SwiftUI

/// Options sheet for exporting a blog as a slideshow video.
/// Mirrors the style of `StoryModePDFOptionsSheet` (storybook options layout).
/// When the user taps "Export & Share", it builds the story pages, renders each to a video
/// frame, and calls `onShare(url)` with the finished MP4 on the main actor.
struct BlogVideoExportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: RecapBlogDetail
    /// Called on the main actor with the exported video URL after the sheet dismisses.
    let onShare: (URL) -> Void

    @AppStorage("blogVideoExportOptions") private var optionsData: Data =
        (try? JSONEncoder().encode(BlogVideoExportOptions())) ?? Data()
    @State private var options   = BlogVideoExportOptions()
    @State private var isExporting  = false
    @State private var progress: Double = 0
    @State private var exportError: String? = nil
    @State private var showError = false
    @State private var showMusicPicker = false

    private var selectedTrack: SlideshowBundledTrack? {
        guard let fn = options.musicFilename else { return nil }
        return SlideshowBundledMusicLibrary.tracksInAppBundle().first { $0.filename == fn }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    durationSection
                    colorStyleSection
                    fontThemeSection
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
            .navigationTitle("Slideshow Video")
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
        .onAppear {
            options = (try? JSONDecoder().decode(BlogVideoExportOptions.self, from: optionsData))
                ?? BlogVideoExportOptions()
        }
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Slide Duration", icon: "timer")
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

    // MARK: - Color Style Section

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

    // MARK: - Font Theme Section

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

    private var progressLabel: String {
        if progress < 0.1  { return "Building slideshow…" }
        if progress < 0.62 { return "Rendering slides…" }
        if progress < 0.82 { return "Writing video…" }
        return "Adding music…"
    }

    private var exportButton: some View {
        Button { startExport() } label: {
            ZStack {
                HStack(spacing: 8) {
                    Image(systemName: "video.badge.checkmark")
                    Text("Export & Share")
                        .fontWeight(.semibold)
                }
                .opacity(isExporting ? 0 : 1)

                if isExporting {
                    HStack(spacing: 10) {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(width: 20, height: 20)
                        Text(progressLabel)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isExporting ? Color.accentColor.opacity(0.6) : Color.accentColor)
            .foregroundColor(.white)
            .appChromeCornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    // MARK: - Export Action

    @MainActor
    private func startExport() {
        if let data = try? JSONEncoder().encode(options) { optionsData = data }
        isExporting = true
        progress = 0.02

        Task { @MainActor in
            do {
                // Build story pages (same pipeline as Story Mode slideshow / storybook export).
                let content = await StoryBookBuilder.build(from: draft)
                let pages   = StoryPageLayout.buildPages(from: content, fontTheme: options.fontTheme)
                guard !pages.isEmpty else { throw BlogVideoExportService.ExportError.noPages }
                progress = 0.1

                let url = try await BlogVideoExportService.exportVideo(
                    pages: pages,
                    draft: draft,
                    options: options,
                    progressHandler: { p in
                        // Map service 0-1 range into 10-100 % of total progress.
                        progress = 0.1 + p * 0.9
                    }
                )

                isExporting = false
                dismiss()
                onShare(url)
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
