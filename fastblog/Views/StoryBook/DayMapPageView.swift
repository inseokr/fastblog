// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI
import UIKit

struct DayMapPageView: View {
    let day: StoryDay
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let bookPageIndex: Int
    let bookPageCount: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Map fills the entire page (edge-to-edge; labels respect safe area).
                Group {
                    if let snapshot = day.mapSnapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: StoryRenderMetrics.clampedScreenWidth,
                                height: StoryRenderMetrics.clampedScreenHeight
                            )
                            .clipped()
                    } else {
                        Color.gray.opacity(0.15)
                            .frame(
                                width: StoryRenderMetrics.clampedScreenWidth,
                                height: StoryRenderMetrics.clampedScreenHeight
                            )
                    }
                }
                .ignoresSafeArea()

                // Day label + date — use the same top scrim treatment as CoverPageView.
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(
                    width: StoryRenderMetrics.clampedScreenWidth,
                    height: UIScreen.main.bounds.height * 0.38
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(day.dayNumber)")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 26, weight: .bold)))
                        .foregroundColor(.white)
                    Text(day.shortDateText)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 15, weight: .medium)))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                .padding(.leading, 20)
                .padding(.top, geo.safeAreaInsets.top + 21)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack {
                    Spacer()
                    StoryBookPageNumberLabel(
                        bookPageIndex: bookPageIndex,
                        bookPageCount: bookPageCount,
                        fontTheme: fontTheme,
                        surface: .photoOverlay
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                }
            }
        }
    }
}

private extension StoryDay {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}
