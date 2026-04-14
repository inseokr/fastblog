// fastblog/Views/Components/VideoThumbnailCardView.swift
import AVFoundation
import Photos
import SwiftUI

/// A card that displays a video clip's first-frame thumbnail with a play-icon overlay
/// and a duration badge. Tapping it opens a full-screen `InlineVideoPlayerView`.
///
/// Used by `PhotoCardView` whenever `PhotoContent.isVideo` is true.
struct VideoThumbnailCardView: View {
    let localIdentifier: String
    let width: CGFloat
    let imageHeight: CGFloat
    let caption: String?
    var fontTheme: FontTheme = .classic
    var blogColor: BlogColor = .white

    @State private var thumbnail: UIImage?
    @State private var duration: TimeInterval = 0
    @State private var showPlayer = false

    private var captionColor: Color {
        blogColor == .black ? Color.white.opacity(0.78) : Color.black.opacity(0.55)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryPageLayout.photoCaptionToImageSpacing) {
            thumbnailView
                .frame(width: width, height: imageHeight)
                .clipped()
                .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { showPlayer = true }
                .fullScreenCover(isPresented: $showPlayer) {
                    InlineVideoPlayerView(localIdentifier: localIdentifier)
                        .ignoresSafeArea()
                        .overlay(alignment: .topLeading) {
                            Button { showPlayer = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white, Color.black.opacity(0.5))
                                    .padding(16)
                            }
                            .accessibilityLabel("Close video")
                        }
                }

            if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                Text(caption)
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: StoryPageLayout.photoCaptionFontSize)))
                    .foregroundColor(captionColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width, alignment: .leading)
        .task { await loadMetadata() }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.opacity(0.85)
                    .overlay(
                        ProgressView().tint(.white)
                    )
            }

            // Play icon
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 52, height: 52)
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: 2)
            }

            // Duration badge (bottom-right)
            if duration > 0 {
                Text(formattedDuration(duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    // MARK: - Metadata loading

    private func loadMetadata() async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        let assetDuration = asset.duration
        await MainActor.run { duration = assetDuration }

        let pixelSize = CGSize(
            width: width * UIScreen.main.scale,
            height: imageHeight * UIScreen.main.scale
        )
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat

        let frame = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PHCachingImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset else { continuation.resume(returning: nil); return }
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = pixelSize
                do {
                    let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        await MainActor.run { thumbnail = frame }
    }

    private func formattedDuration(_ d: TimeInterval) -> String {
        let total = Int(d)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
