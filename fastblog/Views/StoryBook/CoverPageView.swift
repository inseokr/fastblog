// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI

struct CoverPageView: View {
    let cover: CoverContent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-screen photo or gradient fallback
            if let photo = cover.coverPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: UIScreen.main.bounds.width,
                        height: UIScreen.main.bounds.height
                    )
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(hex: "#1a1a2e"), Color(hex: "#2d3561")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(
                    width: UIScreen.main.bounds.width,
                    height: UIScreen.main.bounds.height
                )
            }

            // Gradient scrim so text is readable over any photo
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.height * 0.5
            )

            // Trip name + duration — bottom left
            VStack(alignment: .leading, spacing: 6) {
                Text(cover.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Text(cover.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
        .ignoresSafeArea()
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
