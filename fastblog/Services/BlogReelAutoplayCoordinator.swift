//
//  BlogReelAutoplayCoordinator.swift
//  fastblog
//
//  Picks one inline moment-video reel to play at a time based on viewport center
//  proximity and visible area (larger cells win ties in the same row).
//

import AVFoundation
import Combine
import SwiftUI

/// Global frame of a photo cell that can host an inline reel.
struct BlogReelCandidateFrame: Equatable {
    let photoId: UUID
    let frame: CGRect
}

struct BlogReelCandidatePreferenceKey: PreferenceKey {
    static var defaultValue: [BlogReelCandidateFrame] = []

    static func reduce(value: inout [BlogReelCandidateFrame], nextValue: () -> [BlogReelCandidateFrame]) {
        value.append(contentsOf: nextValue())
    }
}

/// Tracks which blog photo reel should autoplay and owns a single shared `AVPlayer`.
@MainActor
final class BlogReelAutoplayCoordinator: ObservableObject {
    @Published private(set) var focusedPhotoId: UUID?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isUserMuted = true
    @Published private(set) var isPlaying = false

    private var candidates: [UUID: BlogReelCandidateFrame] = [:]
    private var photoURLs: [UUID: URL] = [:]
    private var autoplayEnabled = false
    private var userPlaybackSuspended = false
    private var userPausedManually = false
    private var loopObserver: NSObjectProtocol?
    private var repickTask: Task<Void, Never>?
    private var itemLoadTask: Task<Void, Never>?
    private var currentURL: URL?

    deinit {
        repickTask?.cancel()
        itemLoadTask?.cancel()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }

    func setAutoplayEnabled(_ enabled: Bool) {
        guard autoplayEnabled != enabled else { return }
        autoplayEnabled = enabled
        if enabled {
            scheduleRepick()
        } else {
            clearPlayback()
        }
    }

    func setUserPlaybackSuspended(_ suspended: Bool) {
        guard userPlaybackSuspended != suspended else { return }
        userPlaybackSuspended = suspended
        if suspended {
            pausePlayback()
        } else if autoplayEnabled {
            scheduleRepick()
        }
    }

    func setUserMuted(_ muted: Bool) {
        guard isUserMuted != muted else { return }
        isUserMuted = muted
        player?.isMuted = muted
        if !muted {
            configureAudioSessionForPlayback()
        }
    }

    func toggleUserMuted() {
        setUserMuted(!isUserMuted)
    }

    func togglePlayPause() {
        guard player != nil, focusedPhotoId != nil else { return }
        if isPlaying {
            userPausedManually = true
            player?.pause()
            isPlaying = false
        } else {
            userPausedManually = false
            if !isUserMuted {
                configureAudioSessionForPlayback()
            }
            player?.play()
            isPlaying = true
        }
    }

    func pauseForAlternateAudio() {
        userPausedManually = true
        pausePlayback()
    }

    func registerPhotoURL(_ url: URL?, for photoId: UUID) {
        if let url {
            photoURLs[photoId] = url
        } else {
            photoURLs.removeValue(forKey: photoId)
        }
    }

    func updateCandidates(_ frames: [BlogReelCandidateFrame]) {
        var next: [UUID: BlogReelCandidateFrame] = [:]
        next.reserveCapacity(frames.count)
        for frame in frames {
            next[frame.photoId] = frame
        }
        guard !framesAreSimilar(candidates, next) else { return }
        candidates = next
        scheduleRepick()
    }

    func scheduleRepick() {
        repickTask?.cancel()
        repickTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            repickFocusedReel()
        }
    }

    private func repickFocusedReel() {
        guard autoplayEnabled, !userPlaybackSuspended else {
            clearPlayback()
            return
        }

        let viewport = UIScreen.main.bounds
        guard viewport.width > 1, viewport.height > 1 else {
            clearPlayback()
            return
        }

        let centerY = viewport.midY
        let centerBand = viewport.height * 0.42
        let minVisibleArea = viewport.width * viewport.height * 0.018

        var bestId: UUID?
        var bestScore: CGFloat = 0

        for candidate in candidates.values {
            let visible = candidate.frame.intersection(viewport)
            guard visible.width > 2, visible.height > 2 else { continue }

            let visibleArea = visible.width * visible.height
            guard visibleArea >= minVisibleArea else { continue }

            let dist = abs(candidate.frame.midY - centerY)
            guard dist <= centerBand else { continue }

            let centerWeight = max(0, 1 - dist / centerBand)
            let score = visibleArea * (0.35 + 0.65 * centerWeight)
            if score > bestScore {
                bestScore = score
                bestId = candidate.photoId
            }
        }

        applyFocus(photoId: bestId)
    }

    private func applyFocus(photoId: UUID?) {
        itemLoadTask?.cancel()

        guard let photoId, let url = photoURLs[photoId] else {
            clearPlayback()
            return
        }

        if focusedPhotoId == photoId, currentURL == url, player?.currentItem != nil {
            player?.isMuted = isUserMuted
            if !userPausedManually {
                player?.play()
                isPlaying = true
            }
            return
        }

        focusedPhotoId = photoId
        currentURL = url
        userPausedManually = false
        player?.pause()
        isPlaying = false

        itemLoadTask = Task { @MainActor in
            let asset = AVURLAsset(url: url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            guard !Task.isCancelled, self.currentURL == url, playable else { return }
            self.attachPlayerItem(AVPlayerItem(asset: asset))
        }
    }

    private func attachPlayerItem(_ item: AVPlayerItem) {
        removeLoopObserver()

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }

        guard let player else { return }

        player.isMuted = isUserMuted
        player.actionAtItemEnd = .none

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        if isUserMuted {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            configureAudioSessionForPlayback()
        }

        player.play()
        isPlaying = true
    }

    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .defaultToSpeaker])
        try? session.setActive(true)
    }

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
    }

    private func clearPlayback() {
        repickTask?.cancel()
        repickTask = nil
        itemLoadTask?.cancel()
        itemLoadTask = nil
        focusedPhotoId = nil
        currentURL = nil
        userPausedManually = false
        player?.pause()
        player = nil
        isPlaying = false
        removeLoopObserver()
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    private func framesAreSimilar(
        _ lhs: [UUID: BlogReelCandidateFrame],
        _ rhs: [UUID: BlogReelCandidateFrame]
    ) -> Bool {
        guard lhs.keys == rhs.keys else { return false }
        for (id, frame) in rhs {
            guard let old = lhs[id] else { return false }
            let a = old.frame
            let b = frame.frame
            if abs(a.midX - b.midX) > 6
                || abs(a.midY - b.midY) > 6
                || abs(a.width - b.width) > 6
                || abs(a.height - b.height) > 6 {
                return false
            }
        }
        return true
    }
}

// MARK: - Visibility reporting

private struct BlogReelCandidateReporter: ViewModifier {
    let photoId: UUID
    let isActive: Bool

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: BlogReelCandidatePreferenceKey.self,
                    value: isActive
                        ? [BlogReelCandidateFrame(photoId: photoId, frame: geo.frame(in: .global))]
                        : []
                )
            }
        }
    }
}

extension View {
    /// Reports this thumbnail’s global frame when it can host an inline reel.
    func blogReelCandidate(photoId: UUID, isActive: Bool) -> some View {
        modifier(BlogReelCandidateReporter(photoId: photoId, isActive: isActive))
    }
}
