// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI

struct DayMapPageView: View {
    let day: StoryDay

    var body: some View {
        ZStack(alignment: .bottom) {
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

            // Day label overlay at the bottom
            VStack(alignment: .leading, spacing: 4) {
                Text("Day \(day.dayNumber)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text(day.shortDateText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
