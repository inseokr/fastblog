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
    var onRemove: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var totalDuration: TimeInterval = 0
    @State private var startSeconds: TimeInterval = 0
    @State private var endSeconds: TimeInterval = 0
    @State private var filmstripFrames: [UIImage] = []
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var showRemoveConfirm = false

    @State private var player: AVPlayer?
    @State private var itemObserver: AnyCancellable?
    @State private var loopObserver: Any?
    @State private var activeDragHandle: TrimHandle?
    @State private var dragAnchorSeconds: TimeInterval = 0
    @State private var playbackRange = TrimPlaybackRange()

    private enum TrimHandle {
        case start
        case end
    }

    private var selectedDuration: TimeInterval {
        max(0, endSeconds - startSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                ZStack {
                    if let player {
                        TrimFillVideoPlayerView(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .padding(.horizontal, 16)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 16)

                timelineSection
                    .padding(.horizontal, 16)

                quickNudgeRow
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: sourceURL) {
            await loadAsset()
        }
        .onChange(of: startSeconds) { _, _ in
            playbackRange.start = startSeconds
            playbackRange.end = endSeconds
            installLoopObserver()
            seekPlayer(to: startSeconds, shouldPlay: true)
        }
        .onChange(of: endSeconds) { _, _ in
            playbackRange.start = startSeconds
            playbackRange.end = endSeconds
            installLoopObserver()
            seekPlayer(to: endPreviewTime, shouldPlay: false)
        }
        .onDisappear {
            stopPlayback()
        }
        .alert("Remove this reel?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                stopPlayback()
                onRemove()
                dismiss()
            }
        } message: {
            Text("The short video clip will be removed from this moment. The photo stays.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") {
                stopPlayback()
                onCancel()
                dismiss()
            }
            .font(.body.weight(.medium))
            .foregroundColor(.white)

            Spacer()

            Text("Trim reel")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Button("Use clip") {
                Task { await applyTrim() }
            }
            .font(.body.weight(.semibold))
            .foregroundColor(canApply ? .yellow : .white.opacity(0.35))
            .disabled(!canApply || isExporting)
        }
    }

    private var canApply: Bool {
        !isLoading && selectedDuration >= MomentVideoTrimmer.minimumClipDuration - 0.01
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(MomentVideoTrimmer.formattedDuration(startSeconds))
                Spacer()
                Text(MomentVideoTrimmer.formattedDuration(selectedDuration))
                    .foregroundColor(.yellow)
                Spacer()
                Text(MomentVideoTrimmer.formattedDuration(endSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.white.opacity(0.82))

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let startX = xPosition(for: startSeconds, width: width)
                let endX = xPosition(for: endSeconds, width: width)

                ZStack(alignment: .leading) {
                    Group {
                        filmstripBackground(width: width)

                        Rectangle()
                            .fill(Color.black.opacity(0.62))
                            .frame(width: max(0, startX), height: geo.size.height)

                        Rectangle()
                            .fill(Color.black.opacity(0.62))
                            .frame(width: max(0, width - endX), height: geo.size.height)
                            .offset(x: endX)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: geo.size.height)
                            .offset(x: startX)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
            .frame(height: 56)
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
                case .end:
                    endSeconds = clampedEnd(dragAnchorSeconds + deltaSeconds)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeDragHandle = nil
                beginLoopPreview()
            }
    }

    // MARK: - Quick nudges

    private var quickNudgeRow: some View {
        HStack(spacing: 10) {
            nudgeButton(title: "Trim start", systemImage: "arrow.right.to.line") {
                startSeconds = clampedStart(startSeconds + MomentVideoTrimmer.nudgeStep)
            }
            nudgeButton(title: "Trim end", systemImage: "arrow.left.to.line") {
                endSeconds = clampedEnd(endSeconds - MomentVideoTrimmer.nudgeStep)
            }
        }
    }

    private func nudgeButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isExporting)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Remove reel") {
                showRemoveConfirm = true
            }
            .font(.body.weight(.medium))
            .foregroundColor(.red.opacity(0.92))
            .disabled(isExporting)

            Spacer()

            if isExporting {
                ProgressView()
                    .tint(.white)
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
        filmstripFrames = await MomentVideoTrimmer.generateFilmstrip(from: sourceURL)

        isLoading = false
        configurePlayback()
    }

    @MainActor
    private func applyTrim() async {
        guard canApply else { return }
        isExporting = true
        errorMessage = nil
        stopPlayback()

        if startSeconds <= 0.05, abs(endSeconds - totalDuration) <= 0.05 {
            onApply(sourceURL)
            isExporting = false
            dismiss()
            return
        }

        guard let trimmedURL = await MomentVideoTrimmer.exportTrimmed(
            from: sourceURL,
            startSeconds: startSeconds,
            endSeconds: endSeconds
        ) else {
            errorMessage = "Couldn’t trim this clip. Try again."
            isExporting = false
            configurePlayback()
            return
        }

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

        onApply(trimmedURL)
        isExporting = false
        dismiss()
    }

    // MARK: - Playback

    private func configurePlayback() {
        stopPlayback()
        configureAudioSessionForMomentVideoPlayback()

        let item = AVPlayerItem(url: sourceURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.volume = 1.0
        self.player = player

        itemObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                guard status == .readyToPlay else { return }
                beginLoopPreview()
            }

        if item.status == .readyToPlay {
            beginLoopPreview()
        }
    }

    private func beginLoopPreview() {
        playbackRange.start = startSeconds
        playbackRange.end = endSeconds
        installLoopObserver()
        seekPlayer(to: startSeconds, shouldPlay: true)
    }

    private var endPreviewTime: TimeInterval {
        max(startSeconds, endSeconds - 0.04)
    }

    private func seekPlayer(to seconds: TimeInterval, shouldPlay: Bool) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }

    private func installLoopObserver() {
        guard let player else { return }

        if let loopObserver {
            player.removeTimeObserver(loopObserver)
            self.loopObserver = nil
        }

        let range = playbackRange
        loopObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak player] time in
            guard let player else { return }
            if time.seconds >= range.end - 0.04 {
                let restart = CMTime(seconds: range.start, preferredTimescale: 600)
                player.seek(to: restart, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }
    }

    private func stopPlayback() {
        if let loopObserver, let player {
            player.removeTimeObserver(loopObserver)
        }
        loopObserver = nil
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
