//
//  MomentVideoFullScreenPlayer.swift
//  fastblog
//
//  Full-screen moment-video playback with autoplay on present.
//

import AVFoundation
import AVKit
import Combine
import SwiftUI

/// Presents a local moment-video file full screen and starts playback immediately.
struct MomentVideoFullScreenPlayer: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var itemObserver: AnyCancellable?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                FillVideoPlayerView(player: player)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .task(id: url) {
            startPlayback()
        }
        .onDisappear(perform: stopPlayback)
    }

    private func startPlayback() {
        stopPlayback()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[ReelPlay] file missing: \(url.path)")
            return
        }

        configureAudioSessionForMomentVideoPlayback()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        p.volume = 1.0
        item.audioMix = nil
        player = p

        itemObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    p.play()
                case .failed:
                    print("[ReelPlay] item failed: \(item.error?.localizedDescription ?? "unknown")")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }

        if item.status == .readyToPlay {
            p.play()
        }
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        itemObserver = nil
    }

    /// Routes reel audio to the speaker for playback.
    /// The AVCaptureSession is always stopped by `enterInPlaceCaptionMode()` before this view
    /// appears, so `.playback` is always available. We do NOT stay in `.playAndRecord` here —
    /// AVPlayer's audio output works correctly in `.playback` mode.
    private func configureAudioSessionForMomentVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        // Release the camera's `.playAndRecord` session before switching to playback.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker])
            print("[ReelPlay] setCategory(.playback, .moviePlayback, .defaultToSpeaker) ✓")
        } catch {
            print("[ReelPlay] setCategory(.playback) FAILED: \(error) — falling back to playAndRecord")
            try? session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
        }
        do {
            try session.setActive(true)
            print("[ReelPlay] setActive(true) ✓")
        } catch {
            print("[ReelPlay] setActive(true) FAILED: \(error)")
        }
    }
}

/// UIViewRepresentable that renders an AVPlayer edge-to-edge using resizeAspectFill.
private struct FillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> FillPlayerUIView {
        FillPlayerUIView(player: player)
    }

    func updateUIView(_ uiView: FillPlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class FillPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
