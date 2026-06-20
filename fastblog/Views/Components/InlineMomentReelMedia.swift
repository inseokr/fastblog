//
//  InlineMomentReelMedia.swift
//  fastblog
//
//  Still thumbnail with an inline muted reel layer when focused by `BlogReelAutoplayCoordinator`.
//

import AVFoundation
import SwiftUI

struct InlineMomentReelMedia: View {
    let photo: RecapPhoto
    let videoURL: URL
    var cornerRadius: CGFloat = 8
    var targetSize: CGSize = CGSize(width: 480, height: 480)
    var photoId: UUID

    @EnvironmentObject private var reelAutoplay: BlogReelAutoplayCoordinator

    private var isFocused: Bool { reelAutoplay.focusedPhotoId == photoId }

    var body: some View {
        ZStack {
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: cornerRadius,
                showIcon: false,
                targetSize: targetSize
            )

            if isFocused, let player = reelAutoplay.player {
                InlineMomentReelPlayerLayer(player: player)
            }
        }
        .onAppear {
            reelAutoplay.registerPhotoURL(videoURL, for: photoId)
        }
        .onChange(of: videoURL) { _, url in
            reelAutoplay.registerPhotoURL(url, for: photoId)
        }
        .onDisappear {
            reelAutoplay.registerPhotoURL(nil, for: photoId)
        }
    }
}

// MARK: - AVPlayerLayer host

private struct InlineMomentReelPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> InlineMomentReelPlayerUIView {
        let view = InlineMomentReelPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: InlineMomentReelPlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class InlineMomentReelPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
