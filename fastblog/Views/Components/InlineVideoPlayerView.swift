// fastblog/Views/Components/InlineVideoPlayerView.swift
import AVKit
import Photos
import SwiftUI

/// Full-screen video player for a PHAsset-backed video clip.
/// Intended to be presented via `.fullScreenCover` from `VideoThumbnailCardView`.
struct InlineVideoPlayerView: View {
    let localIdentifier: String

    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Unable to load video")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.subheadline)
                }
            }
        }
        .task {
            player = await loadPlayer(identifier: localIdentifier)
            isLoading = false
        }
    }

    // MARK: - Private

    private func loadPlayer(identifier: String) async -> AVPlayer? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        return await withCheckedContinuation { continuation in
            PHCachingImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                let item = AVPlayerItem(asset: avAsset)
                continuation.resume(returning: AVPlayer(playerItem: item))
            }
        }
    }
}
