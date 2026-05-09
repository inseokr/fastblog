// fastblog/Views/StoryBook/TOCPageView.swift
import SwiftUI

struct TOCPageView: View {
    let entries: [TOCEntry]
    let overview: BlogOverviewContent
    /// Which slice of the TOC this is (1-based). Used for first-page vs continuation layout.
    let pageIndex: Int
    /// When set (e.g. story book), tapping a day row jumps to that day’s first page.
    var onDayTap: ((TOCEntry) -> Void)? = nil

    @Environment(\.storyBlogColor) private var blogColor
    @Environment(\.storyRasterizesForExport) private var rasterizesForExport

    private var primaryColor: Color { blogColor == .black ? .white : .black }
    private var bgColor: Color { blogColor == .black ? .black : .white }
    private var separatorColor: Color { blogColor == .black ? Color.white.opacity(0.2) : Color.gray.opacity(0.35) }

    /// Space above/below each inter-day hairline so text never crowds the rule.
    private static let separatorVerticalPadding: CGFloat = 14
    private static let horizontalInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let topSafeInset = geo.safeAreaInsets.top
            VStack(alignment: .leading, spacing: 0) {
                if pageIndex == 1 {
                    coverStrip(topSafeInset: topSafeInset)
                    contentsTitleBlock
                        .padding(.horizontal, Self.horizontalInset)
                } else {
                    Color.clear
                        .frame(height: StoryPageLayout.tocContinuationHeaderHeight(fontTheme: .classic))
                }

                ForEach(Array(entries.enumerated()), id: \.element.dayNumber) { idx, entry in
                    if idx > 0 {
                        tocDaySeparator()
                    }
                    tocEntryRowContainer(entry)
                        .padding(.horizontal, Self.horizontalInset)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, pageIndex == 1 ? 0 : StoryPageLayout.tocTopPadding)
            // Exported story PDFs do not have the reader's bottom bar; avoid the odd empty band.
            .padding(.bottom, rasterizesForExport ? 0 : StoryPageLayout.storyChromeBottomOverlayHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(bgColor.ignoresSafeArea())
    }

    // MARK: - Header

    /// Full-bleed trip cover: height matches `StoryPageLayout.tocCoverStripHeight` (~20% of story viewport).
    /// Trip name/dates live under “CONTENTS” below — no duplicate summary beside the image.
    private func coverStrip(topSafeInset: CGFloat) -> some View {
        let stripH = StoryPageLayout.tocCoverStripHeight

        return VStack(spacing: 0) {
            bgColor
                .frame(height: topSafeInset)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            Group {
                if let img = overview.coverPhoto {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: stripH)
            .frame(maxWidth: .infinity)
            .clipped()
            /// Soft edge so the photo meets the CONTENTS block without a hard seam.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.clear, bgColor.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(28, stripH * 0.22))
                .allowsHitTesting(false)
            }
        }
    }

    private var contentsTitleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONTENTS")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(primaryColor)
                Spacer(minLength: 8)
                if !rasterizesForExport {
                    Image("PDFLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 6, style: .continuous))
                }
            }
            .padding(.top, 8)

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .padding(.top, 8)

            Text(overview.tripTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(primaryColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text(overview.dateRange)
                .font(.system(size: 14))
                .foregroundColor(primaryColor.opacity(0.75))
                .padding(.top, 4)

            // Fixed gap only — a flexible `Spacer` here steals vertical space inside `GeometryReader` and pushes TOC rows off-page / under the chrome.
            Color.clear
                .frame(height: 12)
        }
    }

    // MARK: - Rows

    private func tocDaySeparator() -> some View {
        Rectangle()
            .fill(separatorColor)
            .frame(height: 1)
            .padding(.vertical, Self.separatorVerticalPadding)
            .padding(.horizontal, Self.horizontalInset)
    }

    private func tocDayTitle(for entry: TOCEntry) -> String {
        if let sub = entry.daySubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            return sub
        }
        if let first = entry.placeNames.first, !first.isEmpty {
            return first
        }
        return "Day \(entry.dayNumber)"
    }

    @ViewBuilder
    private func tocEntryRowContainer(_ entry: TOCEntry) -> some View {
        if let onDayTap = onDayTap, entry.dayStartPageNumber > 0 {
            Button {
                onDayTap(entry)
            } label: {
                tocEntryRow(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Day \(entry.dayNumber), \(entry.date)")
            .accessibilityHint("Go to this day in the story")
        } else {
            tocEntryRow(entry)
        }
    }

    private func tocEntryRow(_ entry: TOCEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(entry.dayNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(primaryColor)
                Spacer(minLength: 8)
                if entry.dayStartPageNumber > 0 {
                    Text("\(entry.dayStartPageNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(primaryColor)
                }
            }

            Text(tocDayTitle(for: entry))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(primaryColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.date)
                .font(.system(size: 12))
                .foregroundColor(primaryColor)

            Text("\(entry.momentCount) moments")
                .font(.system(size: 10))
                .italic()
                .foregroundColor(primaryColor.opacity(0.75))

            tocPlacesList(entry: entry)
        }
    }

    /// One line per stop (up to 2 lines each if the name is long). Avoids comma-wrapped text fighting `lineLimit` + export clipping.
    @ViewBuilder
    private func tocPlacesList(entry: TOCEntry) -> some View {
        let names = entry.placeNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if names.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, placeName in
                    Text(placeName)
                        .font(.system(size: 11))
                        .foregroundColor(primaryColor.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
    }
}
