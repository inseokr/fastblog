// fastblog/Views/StoryBook/TOCPageView.swift
import SwiftUI

struct TOCPageView: View {
    let entries: [TOCEntry]
    let overview: BlogOverviewContent
    let pageIndex: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (first page only)
            if pageIndex == 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip Overview")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(overview.dateRange)  ·  \(overview.dayCount) days")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
                .frame(height: 72, alignment: .center)
                .padding(.horizontal, 16)
            }

            // Entry rows
            ForEach(entries, id: \.dayNumber) { entry in
                VStack(spacing: 0) {
                    HStack {
                        Text("Day \(entry.dayNumber)")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 50, alignment: .leading)
                        Text(entry.date)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(entry.firstPlaceName)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 16)
                    Divider()
                }
            }

            Spacer()

            // Page indicator
            if totalPages > 1 {
                Text("\(pageIndex) / \(totalPages)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}
