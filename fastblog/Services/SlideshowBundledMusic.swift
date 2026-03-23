import AVFoundation
import SwiftUI

// MARK: - Tracks (bundle)

/// Audio shipped inside the app: add `.m4a`, `.mp3`, `.wav`, or `.aac` to the **Bloggo** target (Copy Bundle Resources).
/// Optional `slideshow_` prefix on the filename is used only to build a nicer default title; any filename works.
/// Use royalty-free / licensed material only.
struct SlideshowBundledTrack: Identifiable, Hashable {
    /// Same as `filename` — unique in the bundle listing.
    var id: String { filename }
    let displayTitle: String
    let fileURL: URL
    var filename: String { fileURL.lastPathComponent }
}

enum SlideshowBundledMusicLibrary {
    private static let allowedExtensions = ["m4a", "mp3", "wav", "aac"]
    private static let namePrefix = "slideshow_"
    /// Also scan this bundle subdirectory when using a folder reference in Xcode.
    private static let subdirectoryName = "SlideshowMusic"

    static func tracksInAppBundle() -> [SlideshowBundledTrack] {
        var byFilename: [String: SlideshowBundledTrack] = [:]
        for ext in allowedExtensions {
            let root = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            let nested = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: subdirectoryName) ?? []
            for url in root + nested {
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { continue }
                byFilename[name] = SlideshowBundledTrack(displayTitle: displayTitle(for: url), fileURL: url)
            }
        }
        return byFilename.values.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private static func displayTitle(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix(namePrefix) {
            let suffix = String(stem.dropFirst(namePrefix.count))
            let raw = suffix.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? stem : raw.localizedCapitalized
        }
        let raw = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? stem : raw.localizedCapitalized
    }
}

// MARK: - Preview playback (picker sheet)

@MainActor
private final class BundledTrackPreviewPlayer: ObservableObject {
    @Published private(set) var playingTrackId: String?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ track: SlideshowBundledTrack) {
        if playingTrackId == track.id {
            pause()
            return
        }
        stop()
        let item = AVPlayerItem(url: track.fileURL)
        let p = AVPlayer(playerItem: item)
        player = p
        playingTrackId = track.id
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onPreviewFinished() }
        }
        configureSession()
        p.play()
    }

    func pause() {
        player?.pause()
        playingTrackId = nil
    }

    func stop() {
        if let o = endObserver {
            NotificationCenter.default.removeObserver(o)
            endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playingTrackId = nil
    }

    private func onPreviewFinished() {
        if let o = endObserver {
            NotificationCenter.default.removeObserver(o)
            endObserver = nil
        }
        player?.seek(to: .zero)
        player?.pause()
        playingTrackId = nil
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Best-effort preview.
        }
    }
}

// MARK: - Picker sheet

struct SlideshowBundledTrackPickerSheet: View {
    let tracks: [SlideshowBundledTrack]
    /// Filename of the bundled track in use, or `nil` if slideshow has no background music.
    let selectedFilename: String?
    var onPickTrack: (SlideshowBundledTrack) -> Void
    var onPickNone: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var previewPlayer = BundledTrackPreviewPlayer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        previewPlayer.stop()
                        onPickNone()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            selectionIndicator(isOn: selectedFilename == nil)
                            Text("No background music")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("No background music")
                    .accessibilityAddTraits(selectedFilename == nil ? .isSelected : [])
                } footer: {
                    if tracks.isEmpty {
                        Text("Add royalty-free .m4a, .mp3, .wav, or .aac files to the Bloggo target (Copy Bundle Resources).")
                            .font(.caption)
                    }
                }

                if !tracks.isEmpty {
                    Section("Music") {
                        ForEach(tracks) { track in
                            HStack(spacing: 10) {
                                Button {
                                    previewPlayer.toggle(track)
                                } label: {
                                    Group {
                                        if previewPlayer.playingTrackId == track.id {
                                            Image(systemName: "waveform.circle.fill")
                                                .font(.title2)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.35))
                                                .symbolEffect(.variableColor.iterative, options: .repeating)
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title2)
                                                .symbolRenderingMode(.hierarchical)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(previewPlayer.playingTrackId == track.id ? "Pause preview" : "Play preview")

                                Button {
                                    previewPlayer.stop()
                                    onPickTrack(track)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        selectionIndicator(isOn: selectedFilename == track.filename)
                                        Text(track.displayTitle)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(track.displayTitle)
                                .accessibilityAddTraits(selectedFilename == track.filename ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Slideshow music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        previewPlayer.stop()
                        onCancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                previewPlayer.stop()
            }
        }
    }

    @ViewBuilder
    private func selectionIndicator(isOn: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .frame(width: 28, alignment: .center)
            .accessibilityHidden(true)
    }
}
