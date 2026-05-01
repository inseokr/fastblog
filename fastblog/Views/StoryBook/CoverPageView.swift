// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI

struct CoverPageView: View {
    let cover: CoverContent

    private var momentsLabel: String {
        "\(cover.momentCount) \(cover.momentCount == 1 ? "Moment" : "Moments")"
    }

    private var daysLabel: String {
        "\(cover.dayCount) \(cover.dayCount == 1 ? "Day" : "Days")"
    }

    var body: some View {
        ZStack {
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

            // Full-page scrim so center text remains legible over bright cover photos.
            LinearGradient(
                colors: [.black.opacity(0.56), .black.opacity(0.25), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .all)

            // Extra top fade for notched areas and status text contrast.
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

            // Centered title, date range, and trip metadata.
            VStack(spacing: 14) {
                Text(cover.title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                Text(cover.subtitle)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                HStack(spacing: 10) {
                    metadataPill(text: daysLabel)
                    metadataPill(text: momentsLabel)
                }
                .padding(.top, 4)

                if let narrative = cover.tripNarrative, !narrative.isEmpty {
                    Text(narrative)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.white.opacity(0.92))
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: min(620, UIScreen.main.bounds.width - 56))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
    }

    @ViewBuilder
    private func metadataPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.34), lineWidth: 0.9)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
