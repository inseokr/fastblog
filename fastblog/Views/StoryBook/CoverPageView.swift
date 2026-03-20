// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI
import UIKit

struct CoverPageView: View {
    let cover: CoverContent
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let bookPageIndex: Int
    let bookPageCount: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Full-screen photo or gradient fallback (edge-to-edge only — text uses safe area below).
                Group {
                    if let photo = cover.coverPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: StoryRenderMetrics.clampedScreenWidth,
                                height: StoryRenderMetrics.clampedScreenHeight
                            )
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color(hex: "#1a1a2e"), Color(hex: "#2d3561")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(
                            width: StoryRenderMetrics.clampedScreenWidth,
                            height: StoryRenderMetrics.clampedScreenHeight
                        )
                    }
                }
                .ignoresSafeArea()

                // Gradient scrim — dark at top so title/subtitle read over any photo.
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(
                    width: StoryRenderMetrics.clampedScreenWidth,
                    height: UIScreen.main.bounds.height * 0.5
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

                // Trip name + duration — top left. TabView ignores safe area, so use geometry insets explicitly.
                VStack(alignment: .leading, spacing: 6) {
                    Text(cover.title)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 30, weight: .bold)))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    Text(cover.subtitle)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 15, weight: .medium)))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .padding(.horizontal, 24)
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

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
