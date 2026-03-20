// fastblog/Views/StoryBook/StoryPageView.swift
import SwiftUI

struct StoryPageView: View {
    let page: StoryPage

    var body: some View {
        switch page {
        case .cover(let cover):
            CoverPageView(cover: cover)
        case .tableOfContents(let entries, let overview, let pageIndex, let totalPages):
            TOCPageView(entries: entries, overview: overview, pageIndex: pageIndex, totalPages: totalPages)
        case .dayMap(let day):
            DayMapPageView(day: day)
        case .dayContent(let contentPage):
            DayContentPageView(page: contentPage)
        }
    }
}
