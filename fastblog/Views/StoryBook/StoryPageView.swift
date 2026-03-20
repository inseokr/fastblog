// fastblog/Views/StoryBook/StoryPageView.swift
import SwiftUI

struct StoryPageView: View {
    let page: StoryPage
    /// 1-based index of this page in the full story book.
    let bookPageIndex: Int
    let bookPageCount: Int
    let showNextDayLabel: Bool
    let photoShapeOptions: PDFPhotoShapeOptions
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let layoutMode: PDFLayoutMode
    /// Story mode only: jump to a 1-based book page (e.g. from the table of contents).
    var onNavigateToBookPage: ((Int) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch page {
            case .cover(let cover):
                CoverPageView(
                    cover: cover,
                    blogColor: blogColor,
                    fontTheme: fontTheme,
                    bookPageIndex: bookPageIndex,
                    bookPageCount: bookPageCount
                )
            case .tableOfContents(let entries, let overview, let pageIndex, let totalPages):
                TOCPageView(
                    entries: entries,
                    overview: overview,
                    pageIndex: pageIndex,
                    totalPages: totalPages,
                    bookPageIndex: bookPageIndex,
                    bookPageCount: bookPageCount,
                    blogColor: blogColor,
                    fontTheme: fontTheme,
                    onTapDayStartPage: onNavigateToBookPage
                )
            case .dayMap(let day):
                DayMapPageView(
                    day: day,
                    blogColor: blogColor,
                    fontTheme: fontTheme,
                    bookPageIndex: bookPageIndex,
                    bookPageCount: bookPageCount
                )
            case .dayContent(let contentPage):
                DayContentPageView(
                    page: contentPage,
                    showNextDayLabel: showNextDayLabel,
                    photoShapeOptions: photoShapeOptions,
                    blogColor: blogColor,
                    fontTheme: fontTheme,
                    layoutMode: layoutMode,
                    bookPageIndex: bookPageIndex,
                    bookPageCount: bookPageCount
                )
            }

            if showsStoryModeLogo {
                // Logo rendered inside the page canvas (not in the outer StoryBook overlay).
                Image("StoryModeLogo")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    // Align logo center with Day header text row in Story pages.
                    .padding(.top, 24)
                    .padding(.trailing, 16)
                    .accessibilityLabel("App logo")
            }
        }
    }

    /// Cover and map pages omit the mark so title / map stay uncluttered.
    private var showsStoryModeLogo: Bool {
        switch page {
        case .cover, .dayMap:
            return false
        case .tableOfContents, .dayContent:
            return true
        }
    }
}
