// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI

struct CoverPageView: View {
    let cover: CoverContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Avoid white letterboxing when TabView lays out in the safe-area inset (fixed UIScreen frames no longer match).
            Color.black
                .ignoresSafeArea(edges: .all)

            // Full-bleed photo or gradient — fill the tab’s bounds, then extend into safe areas.
            Group {
                if let photo = cover.coverPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(hex: "#1a1a2e"), Color(hex: "#2d3561")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .all)

            // Gradient scrim so text is readable over any photo (top ~half of screen).
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(280, UIScreen.main.bounds.height * 0.5))
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .vertical)

            // Trip name + duration — top left
            VStack(alignment: .leading, spacing: 6) {
                Text(cover.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Text(cover.subtitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
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
