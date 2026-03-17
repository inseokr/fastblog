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

    private var player: AVAudioPlayer?

    // MARK: - Public API

    func play(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
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
    }
}

// MARK: - AVAudioPlayerDelegate

extension VibePlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.player = nil
        }
    }
}
