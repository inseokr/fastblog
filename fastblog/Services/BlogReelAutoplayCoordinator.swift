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

    private var candidates: [UUID: BlogReelCandidateFrame] = [:]
    private var photoURLs: [UUID: URL] = [:]
    private var autoplayEnabled = false
    private var userPlaybackSuspended = false
    private var loopObserver: NSObjectProtocol?
    private var repickTask: Task<Void, Never>?
    private var currentURL: URL?

    deinit {
        repickTask?.cancel()
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
        candidates = next
        scheduleRepick()
    }

    func scheduleRepick() {
        repickTask?.cancel()
        repickTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
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
        guard let photoId, let url = photoURLs[photoId] else {
            clearPlayback()
            return
        }

        if focusedPhotoId == photoId, currentURL == url {
            player?.play()
            return
        }

        focusedPhotoId = photoId
        currentURL = url

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none
        player = newPlayer

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])

        newPlayer.play()
    }

    private func pausePlayback() {
        player?.pause()
    }

    private func clearPlayback() {
        repickTask?.cancel()
        repickTask = nil
        focusedPhotoId = nil
        currentURL = nil
        player?.pause()
        player = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
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
