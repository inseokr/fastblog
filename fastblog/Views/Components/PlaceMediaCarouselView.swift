//
//  PlaceMediaCarouselView.swift
//  fastblog
//
//  Full-width 5:4 vertical stack for recap place media (top 3 photos).
//

import SwiftUI

// MARK: - Vertical media stack

struct PlaceMediaCarouselView<SlideContent: View>: View {
    let photos: [RecapPhoto]
    let isEditMode: Bool
    let reportsReelCandidates: Bool
    let cornerRadius: CGFloat
    var rowSpacing: CGFloat = 14
    @ViewBuilder let slideContent: (RecapPhoto) -> SlideContent

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(photos) { photo in
                slideContent(photo)
            }
        }
    }
}

// MARK: - Control bar

struct PlaceMediaControlBar: View {
    let photos: [RecapPhoto]
    let focusedPhotoId: UUID?
    @ObservedObject var reelAutoplay: BlogReelAutoplayCoordinator
    let momentVideoURL: (RecapPhoto) -> URL?
    let vibeURL: (RecapPhoto) -> URL?
    let voiceMemoURL: (RecapPhoto) -> URL?
    let playingVibePhotoId: UUID?
    let playingVoiceMemoPhotoId: UUID?
    let vibeIsPlaying: Bool
    let voiceMemoIsPlaying: Bool
    let onToggleVibe: (RecapPhoto) -> Void
    let onToggleVoiceMemo: (RecapPhoto) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var focusedPhoto: RecapPhoto? {
        guard let id = focusedPhotoId else { return photos.first }
        return photos.first(where: { $0.id == id }) ?? photos.first
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            if let photo = focusedPhoto {
                mediaControls(for: photo)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func mediaControls(for photo: RecapPhoto) -> some View {
        HStack(spacing: 10) {
            if momentVideoURL(photo) != nil {
                Button {
                    reelAutoplay.toggleUserMuted()
                } label: {
                    Image(systemName: reelAutoplay.isUserMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reelAutoplay.isUserMuted ? "Unmute video" : "Mute video")

                Button {
                    reelAutoplay.togglePlayPause()
                } label: {
                    Image(systemName: reelAutoplay.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reelAutoplay.isPlaying ? "Pause video" : "Play video")
            }

            if vibeURL(photo) != nil {
                let isPlaying = playingVibePhotoId == photo.id && vibeIsPlaying
                Button {
                    onToggleVibe(photo)
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
                        )
                        .symbolEffect(.variableColor.iterative.reversing, isActive: isPlaying)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.green.opacity(isPlaying ? 0.85 : 0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop vibe" : "Play vibe")
            }

            if voiceMemoURL(photo) != nil {
                let isPlaying = playingVoiceMemoPhotoId == photo.id && voiceMemoIsPlaying
                Button {
                    onToggleVoiceMemo(photo)
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop voice memo" : "Play voice memo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var controlBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }
}
