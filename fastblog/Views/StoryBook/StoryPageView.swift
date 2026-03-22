// fastblog/Views/StoryBook/StoryPageView.swift
import SwiftUI

// MARK: - Environment Keys for Story rendering

private struct StoryFontThemeKey: EnvironmentKey {
    static let defaultValue: FontTheme = .classic
}

private struct StoryBlogColorKey: EnvironmentKey {
    static let defaultValue: BlogColor = .white
}

extension EnvironmentValues {
    var storyFontTheme: FontTheme {
        get { self[StoryFontThemeKey.self] }
        set { self[StoryFontThemeKey.self] = newValue }
    }
    var storyBlogColor: BlogColor {
        get { self[StoryBlogColorKey.self] }
        set { self[StoryBlogColorKey.self] = newValue }
    }
}

// MARK: - StoryPageView

struct StoryPageView: View {
    let page: StoryPage
    var onTOCDayTap: ((TOCEntry) -> Void)? = nil

    var body: some View {
        switch page {
        case .cover(let cover):
            CoverPageView(cover: cover)
        case .tableOfContents(let entries, let overview, let pageIndex, _):
            TOCPageView(entries: entries, overview: overview, pageIndex: pageIndex, onDayTap: onTOCDayTap)
        case .dayMap(let day):
            DayMapPageView(day: day)
        case .dayContent(let contentPage):
            DayContentPageView(page: contentPage)
        }
    }
}
