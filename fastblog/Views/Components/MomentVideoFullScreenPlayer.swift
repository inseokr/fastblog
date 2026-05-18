//
//  MomentVideoFullScreenPlayer.swift
//  fastblog
//
//  Full-screen moment-video playback with autoplay on present.
//

import AVFoundation
import AVKit
import SwiftUI

/// Presents a local moment-video file full screen and starts playback immediately.
struct MomentVideoFullScreenPlayer: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
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
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let p = AVPlayer(url: url)
        player = p
        p.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
    }
}
