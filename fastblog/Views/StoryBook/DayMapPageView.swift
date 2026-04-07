// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI

struct DayMapPageView: View {
    let day: StoryDay

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
                .frame(height: 120)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text("DAY \(day.dayNumber)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .tracking(1.2)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                Text(day.shortDateText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
            }
            .padding(.leading, 20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaPadding(.top, 8)
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
