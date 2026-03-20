// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI

struct DayMapPageView: View {
    let day: StoryDay

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Map snapshot — top 70%
                ZStack(alignment: .bottom) {
                    if let snapshot = day.mapSnapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height * 0.70)
                            .clipped()
                    } else {
                        Color.gray.opacity(0.2)
                            .frame(height: geo.size.height * 0.70)
                    }

                    // Subtle bottom-edge gradient bleeding into white strip
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.70 * 0.15)
                }

                // Day header strip — bottom 30%
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(day.dayNumber)")
                        .font(.system(size: 22, weight: .bold))
                    Text(day.shortDateText)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.30, alignment: .leading)
                .padding(.horizontal, 20)
                .background(Color.white)
            }
        }
        .ignoresSafeArea()
    }
}

private extension StoryDay {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}
