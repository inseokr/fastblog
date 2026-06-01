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
        .onAppear(perform: startPlayback)
        .onDisappear(perform: stopPlayback)
    }

    private func startPlayback() {
        print("[ReelPlay] ═══ startPlayback ═══")
        print("[ReelPlay] file: \(url.lastPathComponent)  exists=\(FileManager.default.fileExists(atPath: url.path))")

        // Diagnose the audio session BEFORE we touch it
        let avs = AVAudioSession.sharedInstance()
        print("[ReelPlay] audioSession BEFORE: category=\(avs.category.rawValue) mode=\(avs.mode.rawValue) outputVol=\(avs.outputVolume)")

        configureAudioSessionForMomentVideoPlayback()

        // Diagnose AFTER our setup
        print("[ReelPlay] audioSession AFTER:  category=\(avs.category.rawValue) mode=\(avs.mode.rawValue) outputVol=\(avs.outputVolume)")
        print("[ReelPlay] audioSession outputRoutes: \(avs.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" })")

        // Check the actual asset tracks synchronously via URLAsset
        Task {
            let asset = AVURLAsset(url: url)
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video))?.count ?? -1
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio))?.count ?? -1
            print("[ReelPlay] asset tracks: video=\(videoTracks) audio=\(audioTracks)")
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        p.volume = 1.0
        item.audioMix = nil

        print("[ReelPlay] player isMuted=\(p.isMuted) volume=\(p.volume)")

        // Observe item status to catch load errors
        itemObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    print("[ReelPlay] item status=readyToPlay  tracks=\(item.tracks.map { "\($0.assetTrack?.mediaType.rawValue ?? "?")" })")
                    p.play()
                    print("[ReelPlay] play() called after readyToPlay, rate=\(p.rate)")
                case .failed:
                    print("[ReelPlay] item status=FAILED error=\(item.error?.localizedDescription ?? "nil")")
                case .unknown:
                    print("[ReelPlay] item status=unknown")
                @unknown default:
                    break
                }
            }

        player = p

        if item.status == .readyToPlay {
            p.play()
            print("[ReelPlay] play() called (already readyToPlay), rate=\(p.rate)")
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
        uiView.playerLayer.player = player
    }
}

private final class FillPlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
