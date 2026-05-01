// fastblog/Views/StoryBook/BlogVideoExportOptionsSheet.swift
import SwiftUI

/// Options sheet for exporting a blog as a slideshow video (same photo sequence as the recap slideshow).
/// Mirrors the style of `StoryModePDFOptionsSheet` (grouped options layout).
/// When the user taps "Export & Share", it loads photos, renders each slide full-bleed, and calls `onShare(url)` with the finished MP4 on the main actor.
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
                    musicSection
                    dayMapSection
                    timestampSection
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
                    Button {
                        persistOptions()
                        dismiss()
                    } label: {
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
        .onDisappear {
            // Persist edits even when user closes settings without exporting.
            persistOptions()
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

    private var timestampSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Timestamps", icon: "clock")
            Toggle(isOn: $options.includeTimestamps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include timestamps")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Show centered 24-hour capture time on each exported slide.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    private var dayMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Daily Map Intro", icon: "map")
            Toggle(isOn: $options.includeDailyMapIntro) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show day route maps")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Add a zoomed-out map slide before each day's photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .appChromeCornerRadius(12)
        }
    }

    private var progressLabel: String {
        if progress < 0.1  { return "Loading photos…" }
        if progress < 0.62 { return "Rendering slideshow…" }
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
        persistOptions()
        isExporting = true
        progress = 0.02

        Task { @MainActor in
            do {
                progress = 0.06
                let url = try await BlogVideoExportService.exportVideo(
                    draft: draft,
                    options: options,
                    progressHandler: { p in
                        progress = 0.06 + p * 0.94
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

    private func persistOptions() {
        if let data = try? JSONEncoder().encode(options) {
            optionsData = data
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
}
