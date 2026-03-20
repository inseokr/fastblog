// fastblog/Services/StoryPageLayout.swift
import CoreGraphics
import UIKit

/// Shared UIFont mapping so Story-mode layout estimation and rendering
/// stay in sync with the selected `FontTheme`.
enum StoryFontHelper {
    static func uiFont(for theme: FontTheme, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch theme {
        case .classic:
            return UIFont.systemFont(ofSize: size, weight: weight)

        case .serif:
            // Map weights to common Georgia variants.
            let isBold = (weight == .bold || weight == .semibold || weight == .heavy || weight == .black)
            let name = isBold ? "Georgia-Bold" : "Georgia"
            return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .rounded:
            // SF Rounded via font descriptor design.
            let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
            if let desc = baseFont.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
            return baseFont
        }
    }

    static func uiItalicFont(for theme: FontTheme, size: CGFloat) -> UIFont {
        switch theme {
        case .classic:
            return UIFont.italicSystemFont(ofSize: size)

        case .serif:
            return UIFont(name: "Georgia-Italic", size: size) ?? UIFont.italicSystemFont(ofSize: size)

        case .rounded:
            let baseFont = UIFont.systemFont(ofSize: size, weight: .regular)
            if let desc = baseFont.fontDescriptor.withDesign(.rounded) {
                let roundedFont = UIFont(descriptor: desc, size: size)
                if let italicDesc = roundedFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    return UIFont(descriptor: italicDesc, size: size)
                }
                return roundedFont
            }
            return UIFont.italicSystemFont(ofSize: size)
        }
    }
}

enum StoryPageLayout {

    // MARK: - Slot heights (points)
    static let footerHeight: CGFloat = 40
    // DayContentPageView structure:
    // - header HStack fixed height: 44
    // - VStack spacing (8) between header and Divider
    // - Divider thickness: 1
    // - VStack spacing (8) between Divider and first slot
    // So "day header block" effectively occupies 44 + 8 + 1 + 8 = 61pt.
    static let dayHeaderHeight: CGFloat = 61
    // Matches the StoryBook renderer's usable height between the top padding and the footer.
    // (DayContentPageView uses `.padding(.top, 12)` and a fixed 40pt footer.)
    static var pageContentHeight: CGFloat {
        max(0, UIScreen.main.bounds.height - footerHeight - 12)
    }
    static let dayCaptionShort: CGFloat = 56
    static let dayCaptionLong: CGFloat = 80

    // MARK: - Day Story Caption Box (yellow callout)
    // Keep all geometry deterministic so the packing algorithm matches SwiftUI rendering.
    /// Truncate day-level story captions so the day header + footer stay visible on screen.
    static let dayStoryCaptionMaxCharacters: Int = 215

    static let dayStoryCaptionFontSize: CGFloat = 14
    static let dayStoryBoxCornerRadius: CGFloat = 12
    static let dayStoryBoxDividerWidth: CGFloat = 4
    static let dayStoryBoxDividerInsetFromLeft: CGFloat = 10
    static let dayStoryBoxTextInsetFromLeft: CGFloat = dayStoryBoxDividerInsetFromLeft + dayStoryBoxDividerWidth + 12
    static let dayStoryBoxTextPaddingRight: CGFloat = 12
    static let dayStoryBoxTextPaddingTop: CGFloat = 10
    static let dayStoryBoxTextPaddingBottom: CGFloat = 10
    static let placeTitleHeight: CGFloat = 32
    static let placeCaptionShort: CGFloat = 40
    static let placeCaptionLong: CGFloat = 64
    static let overflowLabelHeight: CGFloat = 24
    /// TOC first page: matches `TOCPageView` — CONTENTS row + divider + trip title + date + spacing before first day row.
    static let tocHeaderHeight: CGFloat = 119
    /// Continuation TOC pages: invisible CONTENTS row + divider + 8pt gap before first day (matches gap before trip title on page 1).
    static func tocContinuationHeaderHeight(fontTheme: FontTheme) -> CGFloat {
        let contentsFont = StoryFontHelper.uiFont(for: fontTheme, size: 28, weight: .bold)
        return contentsFont.lineHeight + 8 + 1 + 8
    }
    /// Budget for one TOC entry when splitting across pages (worst case: two-line caption + two-line place list).
    /// `TOCPageView` lays out rows by intrinsic height with fixed gaps; this stays a safe upper bound for pagination.
    static let tocRowHeight: CGFloat = 128
    /// Matches `TOCPageView` `.padding(.top, 12)`.
    private static let tocTopPadding: CGFloat = 12
    /// Page number label + `.padding(.bottom, 12)` at the foot of `TOCPageView`.
    private static let tocBottomChrome: CGFloat = 28
    /// Max characters for the day story caption on the CONTENTS page (`daySubtitle`); longer text gets a trailing ellipsis.
    /// Higher than the yellow callout cap so more of the story shows in the list (caption can use two lines in `TOCPageView`).
    static let tocDayStoryCaptionMaxCharacters: Int = dayStoryCaptionMaxCharacters + 110

    // Must match the padding/gap used by StoryBook views.
    private static let storyHorizontalPadding: CGFloat = 32
    private static let photoGap: CGFloat = 8

    private struct Metrics {
        let pageWidth: CGFloat
        let twoPhotoWidth: CGFloat
        let singlePhotoWidth: CGFloat
        let minSinglePhotoImageHeight: CGFloat
        let minTwoPhotoImageHeight: CGFloat
    }

    private static func makeMetrics() -> Metrics {
        let screenWidth = UIScreen.main.bounds.width
        let pageWidth = max(0, screenWidth - storyHorizontalPadding)
        let twoPhotoWidth = max(0, (pageWidth - photoGap) / 2)
        let singlePhotoWidth = pageWidth
        // PhotoCardView uses a 3:4 portrait aspect ratio (height = width * 4/3) for its image frame
        // when `imageHeight` is not overridden.
        let imageHeightForTwoPhotoAspect = twoPhotoWidth * (4 / 3)

        return Metrics(
            pageWidth: pageWidth,
            twoPhotoWidth: twoPhotoWidth,
            singlePhotoWidth: singlePhotoWidth,
            minSinglePhotoImageHeight: imageHeightForTwoPhotoAspect,
            minTwoPhotoImageHeight: imageHeightForTwoPhotoAspect
        )
    }

    /// Estimated extra height added by the *short* photo caption below the image.
    /// Long captions are drawn inside the image frame so they do not add extra vertical space.
    private static func shortPhotoCaptionExtraHeight(
        _ photo: PhotoContent,
        photoWidth: CGFloat,
        fontTheme: FontTheme
    ) -> CGFloat {
        guard let caption = photo.caption,
              !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              photo.captionIsLong == false
        else { return 0 }

        // PhotoCardView's internal stack spacing between image ZStack and caption Text.
        let stackSpacing: CGFloat = 4

        let font = StoryFontHelper.uiFont(for: fontTheme, size: 10)
        let maxLines: CGFloat = 2
        let maxCaptionHeight = font.lineHeight * maxLines

        let rect = caption.boundingRect(
            with: CGSize(width: photoWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        let cappedTextHeight = min(rect.height, maxCaptionHeight)
        return stackSpacing + cappedTextHeight
    }

    private static func estimateTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 0 else { return 0 }

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = trimmed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return max(0, rect.height)
    }

    // MARK: - TOC pagination (matches `TOCPageView` intrinsic heights)

    private static func tocDayTitleString(for entry: TOCEntry) -> String {
        entry.daySubtitle ?? entry.placeNames.first ?? "Day \(entry.dayNumber)"
    }

    /// Vertical space available for day rows (everything below the optional CONTENTS header, above the page number).
    private static func tocAvailableHeightForRows(isFirstPage: Bool, fontTheme: FontTheme) -> CGFloat {
        let h = StoryRenderMetrics.clampedScreenHeight
        var used = tocTopPadding + tocBottomChrome
        if isFirstPage {
            used += tocHeaderHeight
        } else {
            used += tocContinuationHeaderHeight(fontTheme: fontTheme)
        }
        return max(0, h - used)
    }

    /// Mirrors `TOCPageView` row structure: optional separator, inner stack, bottom padding.
    private static func estimatedTOCRowHeight(
        entry: TOCEntry,
        contentWidth: CGFloat,
        fontTheme: FontTheme,
        includeSeparatorAbove: Bool
    ) -> CGFloat {
        var h: CGFloat = 0
        if includeSeparatorAbove {
            h += 1 + 12
        }

        let dayFont = StoryFontHelper.uiFont(for: fontTheme, size: 13, weight: .bold)
        let pageFont = StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .bold)
        let titleFont = StoryFontHelper.uiFont(for: fontTheme, size: 18, weight: .bold)
        let dateFont = StoryFontHelper.uiFont(for: fontTheme, size: 12)
        let momentsFont = StoryFontHelper.uiItalicFont(for: fontTheme, size: 10)
        let placesFont = StoryFontHelper.uiFont(for: fontTheme, size: 11)

        h += max(dayFont.lineHeight, pageFont.lineHeight)

        let innerGap: CGFloat = 2
        h += innerGap * 3

        let titleText = tocDayTitleString(for: entry)
        let titleH = min(
            estimateTextHeight(titleText, font: titleFont, width: contentWidth),
            titleFont.lineHeight * 2 + 1
        )
        h += titleH

        h += dateFont.lineHeight + innerGap + momentsFont.lineHeight

        let placesText = entry.placeNames.joined(separator: ", ")
        h += 2
        let placesH = min(
            estimateTextHeight(placesText, font: placesFont, width: contentWidth),
            placesFont.lineHeight * 2 + 1
        )
        h += placesH

        h += 8
        // Small cushion so we don’t pack slightly tighter than Text layout.
        return h + 3
    }

    /// Greedy page breaks using measured row heights (avoids pushing short days to the next page when fixed 128pt rows underestimate capacity).
    private static func splitTOCEntriesIntoPages(_ entries: [TOCEntry], fontTheme: FontTheme) -> [[TOCEntry]] {
        guard !entries.isEmpty else { return [[]] }

        let contentWidth = max(0, StoryRenderMetrics.clampedScreenWidth - 32)
        var slices: [[TOCEntry]] = []
        var i = 0
        var tocPageNumber = 1

        while i < entries.count {
            let isFirstTOCPage = (tocPageNumber == 1)
            var available = tocAvailableHeightForRows(isFirstPage: isFirstTOCPage, fontTheme: fontTheme)
            var page: [TOCEntry] = []
            var rowIndexInPage = 0

            while i < entries.count {
                let includeSeparator = rowIndexInPage > 0
                let rowH = estimatedTOCRowHeight(
                    entry: entries[i],
                    contentWidth: contentWidth,
                    fontTheme: fontTheme,
                    includeSeparatorAbove: includeSeparator
                )

                if page.isEmpty {
                    page.append(entries[i])
                    available -= rowH
                    i += 1
                    rowIndexInPage += 1
                    continue
                }

                if rowH <= available {
                    page.append(entries[i])
                    available -= rowH
                    i += 1
                    rowIndexInPage += 1
                } else {
                    break
                }
            }

            slices.append(page)
            tocPageNumber += 1
        }

        return slices
    }

    // MARK: - Entry point
    static func buildPages(
        from content: StoryBookContent,
        fontTheme: FontTheme = .classic
    ) -> [StoryPage] {
        var pages: [StoryPage] = []
        let metrics = makeMetrics()

        // 1. Cover
        pages.append(.cover(content.cover))

        // How many TOC pages we will render (must match `buildTOCPages` so day start indices are correct).
        let tocSlices = splitTOCEntriesIntoPages(content.overview.entries, fontTheme: fontTheme)
        let tocTotalPages = max(1, tocSlices.count)

        // 2. Days (built off to the side, but indices assume TOC is inserted after cover).
        var dayPages: [StoryPage] = []
        var dayStartPageNumberByDayNumber: [Int: Int] = [:]

        let dayCount = content.days.count
        for (dayIdx, day) in content.days.enumerated() {
            let isLastDay = dayIdx == dayCount - 1

            // Book page numbers are 1-based.
            let dayStartIndex0Based = (1 + tocTotalPages) + dayPages.count
            dayStartPageNumberByDayNumber[day.dayNumber] = dayStartIndex0Based + 1

            // Map page (skip if no snapshot)
            if day.mapSnapshot != nil {
                dayPages.append(.dayMap(day))
            }

            // Content pages
            let nextDayName: String? = isLastDay ? nil : {
                let nextDay = content.days[dayIdx + 1]
                return nextDay.places.first?.title ?? "Day \(nextDay.dayNumber)"
            }()

            let contentPages = buildDayContentPages(
                day: day,
                isLastDay: isLastDay,
                nextDayName: nextDayName,
                metrics: metrics,
                fontTheme: fontTheme
            )
            dayPages.append(contentsOf: contentPages.map { .dayContent($0) })
        }

        // Inject the computed page numbers into the TOC model.
        let updatedEntries: [TOCEntry] = content.overview.entries.map { entry in
            var e = entry
            e.dayStartPageNumber = dayStartPageNumberByDayNumber[entry.dayNumber] ?? 0
            return e
        }
        let updatedOverview = BlogOverviewContent(
            tripTitle: content.overview.tripTitle,
            dateRange: content.overview.dateRange,
            dayCount: content.overview.dayCount,
            entries: updatedEntries
        )

        // 3. TOC pages (now that entries have accurate day start page numbers)
        pages.append(contentsOf: buildTOCPages(overview: updatedOverview, fontTheme: fontTheme))

        // 4. Append day pages
        pages.append(contentsOf: dayPages)

        // Mark last page of trip
        if case .dayContent(let last) = pages.last {
            let marked = DayContentPage(
                day: last.day,
                isFirstPage: last.isFirstPage,
                slots: last.slots,
                isLastPageOfDay: last.isLastPageOfDay,
                isLastPageOfTrip: true,
                nextDayName: nil
            )
            pages[pages.count - 1] = .dayContent(marked)
        }

        return pages
    }

    // MARK: - TOC
    private static func buildTOCPages(overview: BlogOverviewContent, fontTheme: FontTheme) -> [StoryPage] {
        let slices = splitTOCEntriesIntoPages(overview.entries, fontTheme: fontTheme)
        let totalPages = max(1, slices.count)

        var result: [StoryPage] = []
        for (idx, slice) in slices.enumerated() {
            result.append(.tableOfContents(
                entries: slice,
                overview: overview,
                pageIndex: idx + 1,
                totalPages: totalPages
            ))
        }

        if result.isEmpty {
            result.append(.tableOfContents(entries: [], overview: overview, pageIndex: 1, totalPages: 1))
        }

        return result
    }

    // MARK: - Day content pages
    private static func buildDayContentPages(
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?,
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [DayContentPage] {

        var allSlots: [ContentSlot] = []

        // Day caption (only emitted once — DayContentPageView shows it only on isFirstPage)
        if let caption = day.dayCaption {
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let maxLen = dayStoryCaptionMaxCharacters
                let capped: String
                if trimmed.count <= maxLen {
                    capped = trimmed
                } else {
                    capped = String(trimmed.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }
                allSlots.append(.dayCaption(capped))
            }
        }

        // Place slots
        for place in day.places {
            allSlots.append(contentsOf: slotsForPlace(place, metrics: metrics))
        }

        // Pack slots into pages
        return packSlots(
            allSlots,
            day: day,
            isLastDay: isLastDay,
            nextDayName: nextDayName,
            metrics: metrics,
            fontTheme: fontTheme
        )
    }

    private static func slotsForPlace(_ place: PlaceContent, metrics: Metrics) -> [ContentSlot] {
        let photoCount = place.photos.count
        if photoCount == 0 {
            return [.placeBlock(place, photoSlice: 0...0, photoImageHeight: 0, photoGridLayout: .single)]
        } else if photoCount <= 2 {
            if photoCount == 1 {
                return [.placeBlock(place, photoSlice: 0...0, photoImageHeight: metrics.minSinglePhotoImageHeight, photoGridLayout: .single)]
            } else {
                // One place, two photos: stacked full-width rows (not side-by-side). Leftover vertical space
                // is stretched per row in packSlots (half to each stacked photo).
                return [.placeBlock(place, photoSlice: 0...1, photoImageHeight: metrics.minSinglePhotoImageHeight, photoGridLayout: .stackedSingles)]
            }
        } else {
            var result: [ContentSlot] = [
                .placeBlock(place, photoSlice: 0...1, photoImageHeight: metrics.minTwoPhotoImageHeight, photoGridLayout: .twoColumn)
            ]
            var idx = 2
            while idx < photoCount {
                let end = min(idx + 1, photoCount - 1)
                let slice = idx...end
                let photosInSlot = slice.count
                if photosInSlot == 1 {
                    // Rule: if the place’s 3rd photo (index 2) is the only one in this continuation,
                    // hide the "More Photos" header so it feels like it sits under the first 2.
                    let showHeader = !(idx == 2 && end == 2)
                    result.append(
                        .photoOverflowContinuation(
                            placeName: place.title,
                            place,
                            photoSlice: slice,
                            photoImageHeight: metrics.minSinglePhotoImageHeight,
                            photoGridLayout: .single,
                            showOverflowHeader: showHeader
                        )
                    )
                } else {
                    // Two more photos in a second two-column row. For exactly four photos total, skip the
                    // duplicate place name + "More Photos" line — the first block already shows the place header.
                    let showHeader = photoCount != 4
                    result.append(
                        .photoOverflowContinuation(
                            placeName: place.title,
                            place,
                            photoSlice: slice,
                            photoImageHeight: metrics.minTwoPhotoImageHeight,
                            photoGridLayout: .twoColumn,
                            showOverflowHeader: showHeader
                        )
                    )
                }
                idx += 2
            }
            return result
        }
    }

    private static func slotHeight(
        _ slot: ContentSlot,
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> CGFloat {
        switch slot {
        case .dayCaption(let text):
            return dayStoryCaptionBoxHeight(for: text, pageWidth: metrics.pageWidth, fontTheme: fontTheme)

        case .placeBlock(let place, let photoSlice, let photoImageHeight, let photoGridLayout):
            var h: CGFloat = placeTitleHeight
            let hasPhotosInSlot: Bool = {
                guard !place.photos.isEmpty else { return false }
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                return lo <= hi
            }()

            if let caption = place.caption {
                // Reserve a minimum caption height (to keep spacing consistent),
                // but allow it to grow with the actual text height so long captions
                // don't get truncated with "...".
                let captionSlotH = place.captionIsLong ? placeCaptionLong : placeCaptionShort
                let topGap: CGFloat = 6 // VStack(spacing:) between title row and caption
                let bottomGap: CGFloat = hasPhotosInSlot ? 6 : 0 // caption -> photos gap

                let minCaptionTextH = max(0, captionSlotH - topGap - bottomGap)

                let captionFont = StoryFontHelper.uiFont(for: fontTheme, size: 12)
                let estimatedCaptionTextH = estimateTextHeight(caption, font: captionFont, width: metrics.pageWidth)
                let usedCaptionTextH = max(minCaptionTextH, estimatedCaptionTextH)

                h += topGap + bottomGap + usedCaptionTextH
            }
            if !place.photos.isEmpty {
                let photosInSlot = photoSlice.count
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return h }

                let photos = Array(place.photos[lo...hi])
                switch photoGridLayout {
                case .single:
                    // Exactly one photo.
                    let photoWidth = metrics.singlePhotoWidth
                    let extra = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme) }.max() ?? 0
                    h += photoImageHeight + extra

                case .twoColumn:
                    // Two photos in one row; row height is the max caption height.
                    let photoWidth = metrics.twoPhotoWidth
                    let maxExtra = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme) }.max() ?? 0
                    h += photoImageHeight + maxExtra

                case .stackedSingles:
                    // Two photos stacked; total height is sum of both photo cards.
                    // (Vertical spacing between rows matches the photo gap used elsewhere.)
                    let photoWidth = metrics.singlePhotoWidth
                    let extras = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme) }
                    guard extras.count >= 2 else {
                        let maxExtra = extras.max() ?? 0
                        h += photoImageHeight + maxExtra
                        break
                    }
                    h += photoImageHeight + extras[0]
                    h += photoGap
                    h += photoImageHeight + extras[1]
                }
            }
            return h

        case .photoOverflowContinuation(_, let place, let photoSlice, let photoImageHeight, let photoGridLayout, let showOverflowHeader):
            // photoSlice length corresponds to 1 or 2 photos for this block.
            let lo = photoSlice.lowerBound
            let hi = min(photoSlice.upperBound, place.photos.count - 1)
            guard lo <= hi, !place.photos.isEmpty else { return showOverflowHeader ? overflowLabelHeight : 0 }

            let headerH: CGFloat = showOverflowHeader ? overflowLabelHeight : 0

            let photos = Array(place.photos[lo...hi])
            switch photoGridLayout {
            case .single:
                let extra = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: metrics.singlePhotoWidth, fontTheme: fontTheme) }.max() ?? 0
                return headerH + photoImageHeight + extra

            case .twoColumn:
                let maxExtra = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: metrics.twoPhotoWidth, fontTheme: fontTheme) }.max() ?? 0
                return headerH + photoImageHeight + maxExtra

            case .stackedSingles:
                let extras = photos.map { shortPhotoCaptionExtraHeight($0, photoWidth: metrics.singlePhotoWidth, fontTheme: fontTheme) }
                guard extras.count >= 2 else {
                    let maxExtra = extras.max() ?? 0
                    return headerH + photoImageHeight + maxExtra
                }
                let stackedH = (photoImageHeight + extras[0]) + photoGap + (photoImageHeight + extras[1])
                return headerH + stackedH
            }
        }
    }

    // Computes the *full* box height (including padding), capped so it never consumes more
    // than the existing story-mode day caption slot budget.
    static func dayStoryCaptionBoxHeight(
        for text: String,
        pageWidth: CGFloat,
        fontTheme: FontTheme
    ) -> CGFloat {
        // Font matches the view's day story caption style.
        let font = StoryFontHelper.uiItalicFont(for: fontTheme, size: dayStoryCaptionFontSize)

        // The day caption text sits inside the yellow box with a left inset (after the divider)
        // and a right padding.
        let textWidth = max(
            0,
            pageWidth - dayStoryBoxTextInsetFromLeft - dayStoryBoxTextPaddingRight
        )
        let estimatedTextH = estimateTextHeight(text, font: font, width: textWidth)

        // SwiftUI Text line wrapping can be slightly taller than `boundingRect` estimates.
        // Add a small safety fraction so the yellow box height doesn't under-estimate
        // and clip the last line, which would effectively prioritize later slots.
        let lh = max(1, font.lineHeight)
        let conservativeEstimatedTextH = estimatedTextH + lh * 0.35
        let lineCount = max(1, Int(ceil(conservativeEstimatedTextH / lh)))
        let snappedTextH = CGFloat(lineCount) * lh

        let rawBoxH = snappedTextH + dayStoryBoxTextPaddingTop + dayStoryBoxTextPaddingBottom

        // Cap by the maximum space available for the day-capture slot on a page.
        // This ensures "max lines == page limit" behavior: if the caption is too tall,
        // it will be clipped in the view but won't push other slots off-canvas.
        // Cap by the maximum space available for the day-capture slot on a page.
        // We intentionally avoid being overly conservative here because the day caption
        // is expected to show fully (or at least all text that fits in the page).
        let maxH = max(0, pageContentHeight - dayHeaderHeight)
        return min(max(rawBoxH, 0), maxH)
    }

    /// Returns borrow slots for place 2 if it fits on the current page after place 1.
    /// Only the **full** first block (title + photos) is borrowed — never a title-only teaser, so the next
    /// place always starts on the following page with its name and photos together when there isn’t room.
    private static func borrowSlots(
        for place: PlaceContent,
        remainingSpace: CGFloat,
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [ContentSlot] {
        let photoCount = place.photos.count

        let fullBorrowCandidate: [ContentSlot] = if photoCount == 0 {
            [.placeBlock(place, photoSlice: 0...0, photoImageHeight: 0, photoGridLayout: .single)]
        } else if photoCount == 1 {
            [.placeBlock(place, photoSlice: 0...0, photoImageHeight: metrics.minSinglePhotoImageHeight, photoGridLayout: .single)]
        } else if photoCount == 2 {
            [.placeBlock(place, photoSlice: 0...1, photoImageHeight: metrics.minSinglePhotoImageHeight, photoGridLayout: .stackedSingles)]
        } else {
            [.placeBlock(place, photoSlice: 0...1, photoImageHeight: metrics.minTwoPhotoImageHeight, photoGridLayout: .twoColumn)]
        }

        let fullBorrowCandidateHeight = fullBorrowCandidate.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme) }
        if remainingSpace >= fullBorrowCandidateHeight {
            return fullBorrowCandidate
        }
        return []
    }

    private static func packSlots(
        _ slots: [ContentSlot],
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?,
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [DayContentPage] {

        var pages: [DayContentPage] = []
        var currentSlots: [ContentSlot] = []
        var usedHeight: CGFloat = dayHeaderHeight
        var isFirstPage = true
        var slotIdx = 0
        var didBorrowOnFirstPage = false

        while slotIdx < slots.count {
            let slot = slots[slotIdx]
            let h = slotHeight(slot, metrics: metrics, fontTheme: fontTheme)

            if usedHeight + h > pageContentHeight && !currentSlots.isEmpty {
                pages.append(DayContentPage(
                    day: day,
                    isFirstPage: isFirstPage,
                    slots: currentSlots,
                    isLastPageOfDay: false,
                    isLastPageOfTrip: false,
                    nextDayName: nil
                ))
                currentSlots = []
                usedHeight = dayHeaderHeight
                isFirstPage = false
            } else if usedHeight + h > pageContentHeight {
                #if DEBUG
                assertionFailure("StoryPageLayout: slot overflows fresh page")
                #endif
            }

            currentSlots.append(slot)
            usedHeight += h
            slotIdx += 1

            // Peek-ahead borrow: after place 1's last slot on the first page, try to borrow place 2
            if isFirstPage && !didBorrowOnFirstPage,
               case .placeBlock(let place1, _, _, _) = slot,
               slotIdx < slots.count,
               case .placeBlock(let place2, _, _, _) = slots[slotIdx] {

                let p1PhotoCount = place1.photos.count
                guard p1PhotoCount <= 2 else { continue }

                let remaining = pageContentHeight - usedHeight
                let borrowed = borrowSlots(for: place2, remainingSpace: remaining, metrics: metrics, fontTheme: fontTheme)

                if !borrowed.isEmpty {
                let borrowedHeight = borrowed.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme) }
                    // Ensure the next page has room for at least two minimal place blocks.
                    let minNextPageHeight: CGFloat = (placeTitleHeight + metrics.minSinglePhotoImageHeight) * 2
                    let remainingAfterBorrow = pageContentHeight - borrowedHeight
                    if remainingAfterBorrow >= minNextPageHeight {
                        currentSlots.append(contentsOf: borrowed)
                        usedHeight += borrowedHeight
                        didBorrowOnFirstPage = true
                        slotIdx += 1
                    }
                }
            }
        }

        // Final page
        pages.append(DayContentPage(
            day: day,
            isFirstPage: isFirstPage,
            slots: currentSlots,
            isLastPageOfDay: true,
            isLastPageOfTrip: false,
            nextDayName: isLastDay ? nil : nextDayName
        ))

        // After packing with minimum photo heights, fill leftover vertical space by stretching
        // photo row heights. Two-column rows share one height (both photos grow equally);
        // stacked singles split leftover evenly across the two rows.
        for pageIndex in 0..<pages.count {
            let page = pages[pageIndex]
            var slots = page.slots

            let baseUsedHeight = dayHeaderHeight + slots.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme) }
            var leftover = max(0, pageContentHeight - baseUsedHeight)
            guard leftover > 0 else { continue }

            func photoCount(in slot: ContentSlot) -> Int {
                switch slot {
                case .placeBlock(let place, let slice, _, _):
                    guard !place.photos.isEmpty else { return 0 }
                    let lo = slice.lowerBound
                    let hi = min(slice.upperBound, place.photos.count - 1)
                    guard lo <= hi else { return 0 }
                    return hi - lo + 1
                case .photoOverflowContinuation(_, let place, let slice, _, _, _):
                    guard !place.photos.isEmpty else { return 0 }
                    let lo = slice.lowerBound
                    let hi = min(slice.upperBound, place.photos.count - 1)
                    guard lo <= hi else { return 0 }
                    return hi - lo + 1
                case .dayCaption:
                    return 0
                }
            }

            let photoSlotIndices = slots.indices.filter { photoCount(in: slots[$0]) > 0 }
            let totalPhotosOnPage = photoSlotIndices.reduce(0) { $0 + photoCount(in: slots[$1]) }

            // Rule 2b: two places with 1 photo (top) + 2 photos (bottom), 3 photos on the page total.
            // Rule 3 would send all leftover to the *last* slot (the two-column row), leaving the lone
            // top photo at minimum height — the opposite of [2 + 1] where the bottom single gets the stretch.
            // Stretch the *first* (single) slot instead so the top hero is taller and the bottom pair stays shorter.
            // (A single place with 3 photos on one page is always [2,1] from `slotsForPlace`, never [1,2].)
            if leftover > 0,
               totalPhotosOnPage == 3,
               photoSlotIndices.count == 2 {
                let i0 = photoSlotIndices[0]
                let i1 = photoSlotIndices[1]
                if photoCount(in: slots[i0]) == 1,
                   photoCount(in: slots[i1]) == 2,
                   case let .placeBlock(p0, s0, h0, layout0) = slots[i0],
                   case let .placeBlock(p1, _, _, layout1) = slots[i1],
                   layout0 == .single,
                   (layout1 == .twoColumn || layout1 == .stackedSingles),
                   p0.markerNumber != p1.markerNumber {
                    slots[i0] = .placeBlock(p0, photoSlice: s0, photoImageHeight: h0 + leftover, photoGridLayout: .single)
                    leftover = 0
                }
            }

            // Rule 3: stretch the last photo slot to consume remaining whitespace.
            // For `.twoColumn`, one shared row height grows (both photos equally). For `.stackedSingles`,
            // leftover is split evenly across the two stacked rows.
            if leftover > 0, let lastPhotoIndex = photoSlotIndices.last {
                let slot = slots[lastPhotoIndex]
                switch slot {
                case .placeBlock(let place, let slice, let photoImageHeight, let layout):
                    let extraPerRow: CGFloat = (layout == .stackedSingles) ? leftover / 2 : leftover
                    slots[lastPhotoIndex] = .placeBlock(place, photoSlice: slice, photoImageHeight: photoImageHeight + extraPerRow, photoGridLayout: layout)

                case .photoOverflowContinuation(let name, let place, let slice, let photoImageHeight, let layout, let showOverflowHeader):
                    let extraPerRow: CGFloat = (layout == .stackedSingles) ? leftover / 2 : leftover
                    slots[lastPhotoIndex] = .photoOverflowContinuation(
                        placeName: name,
                        place,
                        photoSlice: slice,
                        photoImageHeight: photoImageHeight + extraPerRow,
                        photoGridLayout: layout,
                        showOverflowHeader: showOverflowHeader
                    )
                case .dayCaption:
                    break
                }
            }

            pages[pageIndex] = DayContentPage(
                day: page.day,
                isFirstPage: page.isFirstPage,
                slots: slots,
                isLastPageOfDay: page.isLastPageOfDay,
                isLastPageOfTrip: page.isLastPageOfTrip,
                nextDayName: page.nextDayName
            )
        }

        return pages
    }
}

/// Clamps screen size used by Story-mode SwiftUI rendering.
/// Helps avoid crashes / invalid Metal drawable sizes during PDF export
/// when UIKit sometimes reports zero bounds.
enum StoryRenderMetrics {
    static var clampedScreenBounds: CGRect {
        let raw = UIScreen.main.bounds
        if raw.width > 0 && raw.height > 0 {
            return raw
        }
        // Typical iPhone portrait fallback.
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    static var clampedScreenSize: CGSize {
        clampedScreenBounds.size
    }

    static var clampedScreenWidth: CGFloat {
        clampedScreenSize.width
    }

    static var clampedScreenHeight: CGFloat {
        clampedScreenSize.height
    }
}
