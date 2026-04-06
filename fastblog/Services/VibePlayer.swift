//
//  VibePlayer.swift
//  fastblog
//
//  Manages playback of a single Vibe audio clip from a local file URL.
//

import AVFoundation
import Foundation

/// Wraps AVAudioPlayer for Vibe clip playback. Publish `isPlaying` for UI binding.
final class VibePlayer: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false

    /// Increments only when a clip reaches the end (not when `stop()` is called). Observe to reset “playing” UI after a single full play.
    @Published private(set) var naturalFinishCount: UInt = 0

    private var player: AVAudioPlayer?

    // MARK: - Public API

    func play(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()

            // Preflight: stop any previous recording/playback session cleanly.
            try? session.setActive(false)

            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: url, fileTypeHint: "m4a")
            p.volume = 1.0
            p.prepareToPlay()
            p.delegate = self
            p.play()
            player = p
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        // Release the audio session to avoid conflicts with other audio (recording).
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - AVAudioPlayerDelegate

extension VibePlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.player = nil
            self.naturalFinishCount += 1
        }
    }
}
