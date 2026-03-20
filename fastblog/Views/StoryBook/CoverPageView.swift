// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI

struct CoverPageView: View {
    let cover: CoverContent

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top 65% — photo or gradient
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let photo = cover.coverPhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height * 0.65)
                                .clipped()
                        } else {
                            LinearGradient(
                                colors: [Color(hex: "#1a1a2e"), Color(hex: "#2d3561")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: geo.size.width, height: geo.size.height * 0.65)
                        }
                    }

                    // Gradient overlay on bottom 40% of photo area
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.65 * 0.4)

                    // Title & subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cover.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text(cover.subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Bottom 35% — white, app icon centered
                VStack(spacing: 8) {
                    Spacer()
                    if let appIcon = UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Bloggo")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.35)
                .background(Color.white)
            }
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
