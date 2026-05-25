import AVFoundation
import Foundation

/// Looped playback of bundled slideshow audio via `AVPlayer`.
@MainActor
final class SlideshowMusicPlaybackCoordinator {
    private var player: AVPlayer?
    private var loopEndObserver: NSObjectProtocol?
    private(set) var playbackVolume: Float = 1

    /// Background music level (0…1). Applied immediately to the active player.
    func setVolume(_ volume: Float) {
        let clamped = min(1, max(0, volume))
        playbackVolume = clamped
        player?.volume = clamped
    }

    func stopAll() async {
        removeLoopObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func pause() async {
        player?.pause()
    }

    func resume() async {
        configureAudioSessionForPlayback()
        player?.play()
    }

    func play(url: URL, startPlayback: Bool) async {
        await stopAll()
        if startPlayback {
            configureAudioSessionForPlayback()
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = playbackVolume
        player = p

        loopEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let pl = self.player else { return }
                pl.seek(to: .zero)
                pl.play()
            }
        }

        if startPlayback {
            p.play()
        }
    }

    private func removeLoopObserver() {
        if let o = loopEndObserver {
            NotificationCenter.default.removeObserver(o)
            loopEndObserver = nil
        }
    }

    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Best-effort.
        }
    }
}
