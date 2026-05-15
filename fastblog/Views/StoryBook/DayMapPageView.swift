// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI

struct DayMapPageView: View {
    let day: StoryDay
    @Environment(\.storyFontTheme) private var fontTheme

    private var trimmedDayStory: String? {
        guard let raw = day.dayCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    private var storyBottomReservedPadding: CGFloat {
        // `StoryPageLayout.storyChromeBottomOverlayHeight` reserves the bar's *internal* height,
        // but the bar also adds the window safe-area inset in `StoryBookView.storyModeBottomBar`.
        StoryPageLayout.storyChromeBottomOverlayHeight + StoryRenderMetrics.windowSafeAreaInsets.bottom + 18
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea(edges: .all)

            // Map fills the tab edge-to-edge (avoid fixed UIScreen size vs TabView safe-area letterboxing).
            Group {
                if let snapshot = day.mapSnapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .all)

            // Top scrim + day header (aligned with recap PDF map overlay)
            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.38), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            // Bottom scrim + day story (story mode + story PDF match this full-bleed map page)
            if let story = trimmedDayStory {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.48), .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 260)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text(story)
                        .italic()
                        .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: StoryPageLayout.dayStoryCaptionFontSize)))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .lineLimit(8)
                        .minimumScaleFactor(0.88)
                        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .padding(.bottom, storyBottomReservedPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("DAY \(day.dayNumber)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                Text(day.shortDateText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
    }
}

private extension StoryDay {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}
