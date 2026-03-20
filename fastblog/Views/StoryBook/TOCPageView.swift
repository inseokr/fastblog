// fastblog/Views/StoryBook/TOCPageView.swift
import SwiftUI

struct TOCPageView: View {
    let entries: [TOCEntry]
    let overview: BlogOverviewContent
    /// Which TOC spread this is (1-based); used for the CONTENTS header on the first TOC page only.
    let pageIndex: Int
    /// How many TOC spreads exist (for multi-page TOC).
    let totalPages: Int
    /// Position in the full story book (same numbering as other pages).
    let bookPageIndex: Int
    let bookPageCount: Int
    let blogColor: BlogColor
    let fontTheme: FontTheme
    /// When set, tapping a day row jumps to that day’s start page (1-based book page, same as `TOCEntry.dayStartPageNumber`).
    var onTapDayStartPage: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (first page only)
            if pageIndex == 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTENTS")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 28, weight: .bold)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    tocSeparatorLine

                    Text(overview.tripTitle)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 24, weight: .bold)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)

                    Text(overview.dateRange)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 13)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                }
                .padding(.bottom, 14)
            } else {
                // Continuation pages: same top structure as page 1 up through the divider under "CONTENTS",
                // then the first day row starts where the trip title sat on page 1 (logo overlays top-trailing).
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTENTS")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 28, weight: .bold)))
                        .foregroundColor(.clear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    tocSeparatorLine
                }
                Color.clear
                    .frame(height: 8)
                    .accessibilityHidden(true)
            }

            // Entry rows — intrinsic height per day; fixed divider + bottom padding so spacing is uniform
            // whether place names use one or two lines (no extra blank flex inside the row).
            ForEach(Array(entries.enumerated()), id: \.element.dayNumber) { index, entry in
                let row = VStack(alignment: .leading, spacing: 0) {
                    if index > 0 {
                        tocSeparatorLine
                            .padding(.vertical, 6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Day \(entry.dayNumber)")
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 13, weight: .bold)))
                                .foregroundColor(blogColor == .black ? Color.white : Color.black)

                            Spacer(minLength: 0)

                            Text("\(entry.dayStartPageNumber)")
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .bold)))
                                .foregroundColor(blogColor == .black ? Color.white : Color.black)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Text(dayTitleText(for: entry))
                            .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 18, weight: .bold)))
                            .foregroundColor(blogColor == .black ? Color.white : Color.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date)
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12)))
                                .foregroundColor(blogColor == .black ? Color.white : Color.black)

                            Text("\(entry.placeNames.count) moment\(entry.placeNames.count == 1 ? "" : "s")")
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 10)))
                                .foregroundColor(blogColor == .black ? Color.white.opacity(0.6) : Color.gray)
                                .italic()
                        }

                        Text(entry.placeNames.joined(separator: ", "))
                            .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
                            .foregroundColor(blogColor == .black ? Color.white.opacity(0.6) : Color.gray)
                            .padding(.top, 2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

                Group {
                    if let onTapDayStartPage {
                        Button {
                            onTapDayStartPage(entry.dayStartPageNumber)
                        } label: {
                            row
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Day \(entry.dayNumber), \(dayTitleText(for: entry))")
                        .accessibilityHint("Opens this day in the story")
                    } else {
                        row
                    }
                }
            }

            Spacer()

            StoryBookPageNumberLabel(
                bookPageIndex: bookPageIndex,
                bookPageCount: bookPageCount,
                fontTheme: fontTheme,
                surface: .content(blogColor)
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.clampedScreenHeight,
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(blogColor == .black ? Color.black : Color.white)
    }

    private func dayTitleText(for entry: TOCEntry) -> String {
        entry.daySubtitle ?? entry.placeNames.first ?? "Day \(entry.dayNumber)"
    }

    private var tocSeparatorLine: some View {
        Rectangle()
            .fill(blogColor == .black ? Color.white.opacity(0.22) : Color.black.opacity(0.14))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
