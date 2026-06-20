//
//  MomentVideoTrimSheet.swift
//  fastblog
//
//  Full-screen reel trimmer with filmstrip handles, loop preview, and quick nudges.
//

import AVFoundation
import Combine
import SwiftUI

struct MomentVideoTrimSheet: View {
    let sourceURL: URL
    var onApply: (URL) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var totalDuration: TimeInterval = 0
    @State private var startSeconds: TimeInterval = 0
    @State private var endSeconds: TimeInterval = 0
    @State private var filmstripFrames: [UIImage] = []
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var errorMessage: String?

    @State private var player: AVPlayer?
    @State private var itemObserver: AnyCancellable?
    @State private var loopObserver: Any?
    @State private var isPlayingPreview = false
    @State private var previewFocus: PreviewFocus = .start
    @State private var activeDragHandle: TrimHandle?
    @State private var audioVolume: Double = 1.0

    private let originalAudioVolume: Double = 1.0
    private let minimumAudioVolume: Double = 0.1

    private enum TrimHandle {
        case start
        case end
    }

    private enum PreviewFocus {
        case start
        case end
    }

    @State private var dragAnchorSeconds: TimeInterval = 0
    @State private var playbackRange = TrimPlaybackRange()
    @State private var seekGeneration = 0

    private let loopFrameEpsilon: TimeInterval = 1.0 / 30.0

    private var selectedDuration: TimeInterval {
        max(0, endSeconds - startSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 8)

                videoPreviewSection
                    .padding(.horizontal, 20)

                Spacer(minLength: 20)

                controlsPanel
                    .padding(.horizontal, 20)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                Spacer(minLength: 16)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: sourceURL) {
            await loadAsset()
        }
        .onChange(of: startSeconds) { _, _ in
            if activeDragHandle == nil {
                if isPlayingPreview {
                    refreshLoopPlaybackIfNeeded()
                } else {
                    updateScrubPreview(focus: .start)
                }
            }
        }
        .onChange(of: endSeconds) { _, _ in
            if activeDragHandle == nil {
                if isPlayingPreview {
                    refreshLoopPlaybackIfNeeded()
                } else {
                    updateScrubPreview(focus: .end)
                }
            }
        }
        .onChange(of: audioVolume) { _, _ in
            applyPreviewVolume()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                stopPlayback()
                onCancel()
                dismiss()
            }
            .font(.body)
            .foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Trim Reel")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .center)

            Button(isExporting ? "Saving…" : "Save") {
                Task { await applyTrim() }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(canApply ? Color.yellow : Color.white.opacity(0.35))
            .disabled(!canApply || isExporting)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var videoPreviewSection: some View {
        ZStack {
            if let player {
                TrimFillVideoPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if isLoading {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                ProgressView()
                    .tint(.white)
            }

            if !isLoading, player != nil {
                previewPlayButton
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)

                durationLabels

                HStack(spacing: 10) {
                    trimNudgeButton(
                        systemImage: "arrow.right.to.line.compact",
                        accessibilityLabel: "Nudge start later by 0.25 seconds"
                    ) {
                        startSeconds = clampedStart(startSeconds + MomentVideoTrimmer.nudgeStep)
                        playLoopingTrimRange()
                    }

                    timelineFilmstrip
                        .frame(height: 52)

                    trimNudgeButton(
                        systemImage: "arrow.left.to.line.compact",
                        accessibilityLabel: "Nudge end earlier by 0.25 seconds"
                    ) {
                        endSeconds = clampedEnd(endSeconds - MomentVideoTrimmer.nudgeStep)
                        playLoopingTrimRange()
                    }
                }

                Text("Drag the yellow handles, or use the arrows for 0.25s steps.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            audioVolumeSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var durationLabels: some View {
        HStack {
            durationLabel(title: "Start", value: MomentVideoTrimmer.formattedDuration(startSeconds), alignment: .leading)

            Spacer(minLength: 8)

            durationLabel(
                title: "Clip",
                value: MomentVideoTrimmer.formattedDuration(selectedDuration),
                alignment: .center,
                valueColor: .yellow
            )

            Spacer(minLength: 8)

            durationLabel(
                title: "End",
                value: MomentVideoTrimmer.formattedDuration(endSeconds),
                alignment: .trailing
            )
        }
    }

    private func durationLabel(
        title: String,
        value: String,
        alignment: HorizontalAlignment,
        valueColor: Color = .white.opacity(0.88)
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(valueColor)
        }
    }

    private var hasTrimChanges: Bool {
        !(startSeconds <= 0.05 && abs(endSeconds - totalDuration) <= 0.05)
    }

    private var hasVolumeChanges: Bool {
        audioVolume < originalAudioVolume - 0.001
    }

    private var canApply: Bool {
        !isLoading
            && selectedDuration >= MomentVideoTrimmer.minimumClipDuration - 0.01
            && (hasTrimChanges || hasVolumeChanges)
    }

    // MARK: - Timeline

    private var trimExcludedOverlay: some View {
        Rectangle()
            .fill(Color.black.opacity(0.68))
    }

    private var timelineFilmstrip: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let startX = xPosition(for: startSeconds, width: width)
            let endX = xPosition(for: endSeconds, width: width)
            let selectedWidth = max(0, endX - startX)

            ZStack(alignment: .leading) {
                filmstripBackground(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 0) {
                    trimExcludedOverlay
                        .frame(width: max(0, startX))
                    Color.clear
                        .frame(width: selectedWidth)
                    trimExcludedOverlay
                        .frame(width: max(0, width - endX))
                }
                .frame(width: width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: selectedWidth, height: geo.size.height)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                trimHandleVisual(at: startX, height: geo.size.height)
                trimHandleVisual(at: endX, height: geo.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                timelineDragGesture(
                    width: width,
                    startX: startX,
                    endX: endX
                )
            )
        }
    }

    @ViewBuilder
    private func filmstripBackground(width: CGFloat) -> some View {
        if filmstripFrames.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.12))
        } else {
            HStack(spacing: 0) {
                ForEach(Array(filmstripFrames.enumerated()), id: \.offset) { _, frame in
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(filmstripFrames.count))
                        .clipped()
                }
            }
        }
    }

    private func trimHandleVisual(at x: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.yellow)
            .frame(width: 6, height: height - 8)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
            }
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
    }

    private func timelineDragGesture(width: CGFloat, startX: CGFloat, endX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeDragHandle == nil {
                    let touchX = min(max(value.startLocation.x, 0), width)
                    let startDistance = abs(touchX - startX)
                    let endDistance = abs(touchX - endX)
                    let handle: TrimHandle = startDistance <= endDistance ? .start : .end
                    activeDragHandle = handle
                    dragAnchorSeconds = handle == .start ? startSeconds : endSeconds
                }

                let deltaSeconds = Double(value.translation.width / width) * totalDuration
                switch activeDragHandle {
                case .start:
                    startSeconds = clampedStart(dragAnchorSeconds + deltaSeconds)
                    updateScrubPreview(focus: .start)
                case .end:
                    endSeconds = clampedEnd(dragAnchorSeconds + deltaSeconds)
                    updateScrubPreview(focus: .end)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeDragHandle = nil
                playLoopingTrimRange()
            }
    }

    private var previewPlayButton: some View {
        Button {
            togglePreviewPlayback()
        } label: {
            Image(systemName: isPlayingPreview ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlayingPreview ? "Pause preview" : "Play trimmed clip")
    }

    private func trimNudgeButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isExporting)
        .accessibilityLabel(accessibilityLabel)
    }

    private var audioVolumeLabel: String {
        if audioVolume >= originalAudioVolume - 0.001 {
            return "Original"
        }
        return "\(Int((audioVolume * 100).rounded()))%"
    }

    private var audioVolumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                    Text("Too much wind or background noise? Drag left to save a quieter clip.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(audioVolumeLabel)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(audioVolume >= originalAudioVolume - 0.001 ? .white.opacity(0.55) : .yellow)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .accessibilityHidden(true)
                Slider(
                    value: $audioVolume,
                    in: minimumAudioVolume...originalAudioVolume,
                    step: 0.05
                )
                .tint(.yellow)
                .disabled(isLoading || isExporting)
                .accessibilityLabel("Clip volume")
                .accessibilityValue(audioVolumeLabel)
                Text("Original")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Loading / export

    @MainActor
    private func loadAsset() async {
        isLoading = true
        errorMessage = nil
        stopPlayback()

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorMessage = "Video file is missing."
            isLoading = false
            return
        }

        guard let duration = await MomentVideoTrimmer.loadDuration(of: sourceURL) else {
            errorMessage = "Couldn’t read this clip."
            isLoading = false
            return
        }

        totalDuration = duration
        startSeconds = 0
        endSeconds = duration
        audioVolume = originalAudioVolume
        filmstripFrames = await MomentVideoTrimmer.generateFilmstrip(from: sourceURL)

        isLoading = false
        preparePreviewPlayer()
    }

    @MainActor
    private func applyTrim() async {
        guard canApply else { return }
        isExporting = true
        errorMessage = nil
        stopPlayback()

        let needsTrim = !(startSeconds <= 0.05 && abs(endSeconds - totalDuration) <= 0.05)
        let needsVolumeAdjust = audioVolume < originalAudioVolume - 0.001
        var outputURL = sourceURL

        if needsTrim {
            guard let trimmedURL = await MomentVideoTrimmer.exportTrimmed(
                from: sourceURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            ) else {
                errorMessage = "Couldn’t trim this clip. Try again."
                isExporting = false
                preparePreviewPlayer()
                return
            }
            outputURL = trimmedURL

            let originalDuration = Int(totalDuration.rounded())
            let trimmedDuration = Int(selectedDuration.rounded())
            let trimmedFromStart = Int(startSeconds.rounded())
            let trimmedFromEnd = Int((totalDuration - endSeconds).rounded())
            AppAnalytics.track(.appInAppCameraReelTrimmed(
                originalDuration: originalDuration,
                trimmedDuration: trimmedDuration,
                trimmedFromStart: trimmedFromStart,
                trimmedFromEnd: trimmedFromEnd
            ))
        }

        if needsVolumeAdjust {
            guard let adjustedURL = await MomentVideoVolumeAdjuster.export(
                at: outputURL,
                volume: Float(audioVolume)
            ) else {
                errorMessage = "Couldn’t adjust audio volume. Try again."
                isExporting = false
                preparePreviewPlayer()
                return
            }
            if outputURL.path != sourceURL.path {
                try? FileManager.default.removeItem(at: outputURL)
            }
            outputURL = adjustedURL
            AppAnalytics.track(.appInAppCameraReelVolumeAdjusted(
                duration: Int(selectedDuration.rounded()),
                volumePercent: Int((audioVolume * 100).rounded())
            ))
        }

        if !needsTrim && !needsVolumeAdjust {
            onApply(sourceURL)
        } else {
            onApply(outputURL)
        }
        isExporting = false
        dismiss()
    }

    private func previewTime(for focus: PreviewFocus) -> TimeInterval {
        switch focus {
        case .start:
            return MomentVideoTrimmer.filmstripPreviewTime(for: startSeconds, totalDuration: totalDuration)
        case .end:
            return MomentVideoTrimmer.filmstripPreviewTime(for: endSeconds, totalDuration: totalDuration)
        }
    }

    private func loopPlaybackStartTime() -> TimeInterval {
        MomentVideoTrimmer.filmstripPreviewTime(for: startSeconds, totalDuration: totalDuration)
    }

    private func loopPlaybackEndTime() -> TimeInterval {
        endSeconds
    }

    private func refreshLoopPlaybackIfNeeded() {
        guard isPlayingPreview else { return }
        playbackRange.start = loopPlaybackStartTime()
        playbackRange.end = loopPlaybackEndTime()
        installLoopObserver()
    }

    // MARK: - Playback

    private func preparePreviewPlayer() {
        stopPlayback()
        configureAudioSessionForMomentVideoPlayback()

        let item = AVPlayerItem(url: sourceURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.volume = 1.0
        player.actionAtItemEnd = .pause
        self.player = player

        itemObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak player] status in
                guard status == .readyToPlay else { return }
                applyPreviewVolume()
                updateScrubPreview(focus: previewFocus)
            }

        if item.status == .readyToPlay {
            applyPreviewVolume()
            updateScrubPreview(focus: previewFocus)
        }
    }

    private func applyPreviewVolume() {
        guard let player, let item = player.currentItem else { return }

        if audioVolume >= originalAudioVolume - 0.001 {
            item.audioMix = nil
            player.volume = 1.0
            return
        }

        let volume = Float(audioVolume)
        let asset = item.asset
        Task { @MainActor in
            guard player.currentItem === item else { return }
            item.audioMix = await MomentVideoVolumeAdjuster.makePreviewMix(for: asset, volume: volume)
            player.volume = 1.0
        }
    }

    private func togglePreviewPlayback() {
        if isPlayingPreview {
            pausePreviewPlayback()
        } else {
            playLoopingTrimRange()
        }
    }

    private func updateScrubPreview(focus: PreviewFocus) {
        previewFocus = focus
        if isPlayingPreview {
            pausePreviewPlayback()
            return
        }
        seekPlayer(to: previewTime(for: focus), shouldPlay: false)
    }

    private func playLoopingTrimRange() {
        guard let player else { return }
        isPlayingPreview = true
        player.actionAtItemEnd = .none
        playbackRange.start = loopPlaybackStartTime()
        playbackRange.end = loopPlaybackEndTime()
        installLoopObserver()
        seekPlayer(to: loopPlaybackStartTime(), shouldPlay: true)
    }

    private func pausePreviewPlayback() {
        isPlayingPreview = false
        player?.actionAtItemEnd = .pause
        removeLoopObserver()
        player?.pause()
        seekPlayer(to: previewTime(for: previewFocus), shouldPlay: false)
    }

    private func seekPlayer(to seconds: TimeInterval, shouldPlay: Bool) {
        guard let player else { return }
        seekGeneration += 1
        let generation = seekGeneration
        let clampedSeconds = min(max(0, seconds), max(0, totalDuration - 0.001))
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.pause()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished, generation == self.seekGeneration else { return }
            if shouldPlay {
                player.play()
            } else {
                player.pause()
                player.rate = 0
            }
        }
    }

    private func installLoopObserver() {
        guard let player else { return }
        removeLoopObserver()

        let range = playbackRange
        let epsilon = loopFrameEpsilon
        loopObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600),
            queue: .main
        ) { [weak player] time in
            guard let player else { return }
            if time.seconds >= range.end - epsilon {
                let restart = CMTime(seconds: range.start, preferredTimescale: 600)
                player.seek(to: restart, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    guard finished else { return }
                    player.play()
                }
            }
        }
    }

    private func removeLoopObserver() {
        if let loopObserver, let player {
            player.removeTimeObserver(loopObserver)
        }
        loopObserver = nil
    }

    private func stopPlayback() {
        removeLoopObserver()
        isPlayingPreview = false
        player?.actionAtItemEnd = .pause
        player?.pause()
        player = nil
        itemObserver = nil
    }

    private func configureAudioSessionForMomentVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker])
        try? session.setActive(true)
    }

    // MARK: - Range math

    private func xPosition(for seconds: TimeInterval, width: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        let fraction = seconds / totalDuration
        return CGFloat(fraction) * width
    }

    private func clampedStart(_ proposed: TimeInterval) -> TimeInterval {
        let maxStart = max(0, endSeconds - MomentVideoTrimmer.minimumClipDuration)
        return min(max(proposed, 0), maxStart)
    }

    private func clampedEnd(_ proposed: TimeInterval) -> TimeInterval {
        let minEnd = min(totalDuration, startSeconds + MomentVideoTrimmer.minimumClipDuration)
        return max(min(proposed, totalDuration), minEnd)
    }
}

/// Mutable trim range read by the AVPlayer loop observer (avoids stale closure captures).
private final class TrimPlaybackRange {
    var start: TimeInterval = 0
    var end: TimeInterval = 0
}

// MARK: - Video layer

private struct TrimFillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TrimFillPlayerUIView {
        TrimFillPlayerUIView(player: player)
    }

    func updateUIView(_ uiView: TrimFillPlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class TrimFillPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
