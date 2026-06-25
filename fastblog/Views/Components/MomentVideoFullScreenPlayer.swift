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
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                FillVideoPlayerView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: dismissPlayer) {
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
            await startPlayback()
        }
    }

    @MainActor
    private func startPlayback() async {
        stopPlayback()
        loadError = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "This reel file is missing."
            print("[ReelPlay] file missing: \(url.path)")
            return
        }

        configureAudioSessionForMomentVideoPlayback()

        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable else {
            loadError = "Couldn't play this reel."
            print("[ReelPlay] asset not playable: \(url.path)")
            return
        }

        let item = AVPlayerItem(asset: asset)
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
                    loadError = "Couldn't play this reel."
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

    private func dismissPlayer() {
        stopPlayback()
        onDismiss()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        itemObserver = nil
    }

    /// Routes reel audio to the speaker for playback.
    private func configureAudioSessionForMomentVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker])
        } catch {
            try? session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
        }
        try? session.setActive(true)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
