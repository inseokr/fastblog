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
    /// Reserve space above the floating Cancel/Share bar in `StoryBookView` so slots/footer aren’t covered.
    /// Kept in sync with `storyModeBottomBar`’s bottom padding + button row height (~56–58pt to bar top).
    static let storyChromeBottomOverlayHeight: CGFloat = 64
    // DayContentPageView structure:
    // - header HStack fixed height: 44
    // - VStack spacing (8) between header and Divider
    // - Divider thickness: 1
    // - VStack spacing (8) between Divider and first slot
    // So "day header block" effectively occupies 44 + 8 + 1 + 8 = 61pt.
    static let dayHeaderHeight: CGFloat = 61
    // Matches the StoryBook renderer: TabView respects safe areas; subtract top padding and bottom chrome.
    // The footer ("The End") is an overlay outside the VStack flow, so its height is NOT deducted here —
    // that frees ~40pt of extra photo space on every page.
    static var pageContentHeight: CGFloat {
        max(
            0,
            StoryRenderMetrics.effectiveStoryViewportHeight - 12 - storyChromeBottomOverlayHeight
        )
    }
    static let dayCaptionShort: CGFloat = 56
    static let dayCaptionLong: CGFloat = 80

    // MARK: - Day Story Caption Box (yellow callout)
    // Keep all geometry deterministic so the packing algorithm matches SwiftUI rendering.
    /// Truncate day-level story captions so the day header + footer stay visible on screen.
    static let dayStoryCaptionMaxCharacters: Int = 215

    static let dayStoryCaptionFontSize: CGFloat = 14
    static let dayStoryBoxCornerRadius: CGFloat = 10
    static let dayStoryBoxDividerWidth: CGFloat = 4
    /// Inset of the accent bar from the page content edge; 0 aligns with day header / place titles.
    static let dayStoryBoxDividerInsetFromLeft: CGFloat = 0
    static let dayStoryBoxTextInsetFromLeft: CGFloat = dayStoryBoxDividerInsetFromLeft + dayStoryBoxDividerWidth + 12
    static let dayStoryBoxTextPaddingRight: CGFloat = 12
    static let dayStoryBoxTextPaddingTop: CGFloat = 10
    static let dayStoryBoxTextPaddingBottom: CGFloat = 10
    static let placeTitleHeight: CGFloat = 32
    static let placeCaptionShort: CGFloat = 48
    static let placeCaptionLong: CGFloat = 72
    /// Place story body above photos; keep layout estimates aligned with `PlaceBlockView`.
    static let placeStoryBodyFontSize: CGFloat = 16
    /// Font size for the per-photo caption drawn below each image; keep in sync with `PhotoCardView`.
    static let photoCaptionFontSize: CGFloat = 13
    /// Spacing between the photo image and its caption text; keep in sync with `PhotoCardView`.
    static let photoCaptionToImageSpacing: CGFloat = 8
    /// When a stop has two photos and the place story reaches this many wrapped lines, lay the story in two columns.
    private static let placeStoryLineCountSplitTwoPhotosThreshold: Int = 4
    /// When a stop has two photos and the place story reaches this many wrapped lines, use two single-photo slots instead of one stacked pair.
    private static let placeStoryLineCountSinglePhotoThreshold: Int = 2
    static let overflowLabelHeight: CGFloat = 24
    /// SwiftUI `VStack` spacing between place title row, place caption, and photos (not the photo grid `photoGap`).
    static let placeBlockRowSpacing: CGFloat = 6

    /// Gaps **inside** the place-caption vertical budget (`placeCaptionShort` / `placeCaptionLong`), aligned with `PlaceBlockView`.
    static func placeCaptionGaps(layoutMode: PDFLayoutMode, hasPhotosInSlot: Bool) -> (top: CGFloat, bottom: CGFloat) {
        let s = placeBlockRowSpacing
        if layoutMode == .normal {
            return (s, hasPhotosInSlot ? s : 0)
        }
        // Story: one `s` gap before the caption (from photos or title); no row below the caption in the block.
        return (s, 0)
    }
    /// TOC first page: matches `TOCPageView` — CONTENTS row + divider + trip title + date + spacing before first day row.
    static let tocHeaderHeight: CGFloat = 119
    /// Hero strip above CONTENTS on the first TOC page (cover photo + page indicator).
    static let tocCoverStripHeight: CGFloat = 88
    /// First TOC page: small inset below the last row (page numbers sit on the cover strip, not here).
    static let tocFirstPageBottomChrome: CGFloat = 12
    /// Continuation TOC pages: invisible CONTENTS row + divider + 8pt gap before first day (matches gap before trip title on page 1).
    static func tocContinuationHeaderHeight(fontTheme: FontTheme) -> CGFloat {
        let contentsFont = StoryFontHelper.uiFont(for: fontTheme, size: 28, weight: .bold)
        return contentsFont.lineHeight + 8 + 1 + 8
    }
    /// Budget for one TOC entry when splitting across pages (worst case: two-line caption + two-line place list).
    /// `TOCPageView` lays out rows by intrinsic height with fixed gaps; this stays a safe upper bound for pagination.
    static let tocRowHeight: CGFloat = 128
    /// Matches `TOCPageView` `.padding(.top, 12)` on continuation TOC pages (first page uses 0).
    static let tocTopPadding: CGFloat = 12
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
        let screenWidth = StoryRenderMetrics.clampedScreenWidth
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

    // MARK: - Feasible photo heights (never exceed one story page)

    private static func splitBalancedForTwoColumns(_ text: String) -> (String, String) {
        let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init).filter { !$0.isEmpty }
        guard words.count >= 2 else { return (text, "") }
        let mid = words.count / 2
        let left = words[..<mid].joined(separator: " ")
        let right = words[mid...].joined(separator: " ")
        return (left, right)
    }

    private static func boundedPlaceCaptionBlockHeight(
        place: PlaceContent,
        metrics: Metrics,
        fontTheme: FontTheme,
        hasPhotosInSlot: Bool = true,
        storyUsesTwoColumns: Bool = false,
        showPlaceStory: Bool = true
    ) -> CGFloat {
        guard showPlaceStory else { return 0 }
        guard let caption = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty else { return 0 }
        let gaps = placeCaptionGaps(layoutMode: .normal, hasPhotosInSlot: hasPhotosInSlot)
        let minCaptionTextH = max(0, (place.captionIsLong ? placeCaptionLong : placeCaptionShort) - gaps.top - gaps.bottom)
        let font = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
        let raw: CGFloat
        if storyUsesTwoColumns {
            let colGap: CGFloat = 10
            let colW = max(40, (metrics.pageWidth - colGap) / 2)
            let (l, r) = splitBalancedForTwoColumns(caption)
            let hl = estimateTextHeight(l, font: font, width: colW) + font.lineHeight * 0.35
            let hr = r.isEmpty ? 0 : estimateTextHeight(r, font: font, width: colW) + font.lineHeight * 0.35
            raw = max(hl, hr)
        } else {
            raw = estimateTextHeight(caption, font: font, width: metrics.pageWidth) + font.lineHeight * 0.35
        }
        let body = max(minCaptionTextH, raw)
        let maxBody = max(40, pageContentHeight * 0.38)
        return gaps.top + gaps.bottom + min(body, maxBody)
    }

    private static func feasibleSinglePhotoImageHeight(
        metrics: Metrics,
        place: PlaceContent,
        fontTheme: FontTheme,
        storyUsesTwoColumns: Bool = false,
        showPlaceStory: Bool = true
    ) -> CGFloat {
        let placeBlk = boundedPlaceCaptionBlockHeight(
            place: place,
            metrics: metrics,
            fontTheme: fontTheme,
            storyUsesTwoColumns: storyUsesTwoColumns,
            showPlaceStory: showPlaceStory
        )
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let captionBelow = min(f.lineHeight * 40 + photoCaptionToImageSpacing, 340)
        let fixed = dayHeaderHeight + placeTitleHeight + placeBlk + captionBelow + 8
        return min(metrics.minSinglePhotoImageHeight, max(100, pageContentHeight - fixed))
    }

    private static func feasibleStackedRowImageHeight(
        metrics: Metrics,
        place: PlaceContent,
        fontTheme: FontTheme,
        storyUsesTwoColumns: Bool = false,
        showPlaceStory: Bool = true
    ) -> CGFloat {
        let placeBlk = boundedPlaceCaptionBlockHeight(
            place: place,
            metrics: metrics,
            fontTheme: fontTheme,
            storyUsesTwoColumns: storyUsesTwoColumns,
            showPlaceStory: showPlaceStory
        )
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let rowCap = min(f.lineHeight * 10 + photoCaptionToImageSpacing, 150)
        let fixed = dayHeaderHeight + placeTitleHeight + placeBlk + photoGap + rowCap * 2 + 8
        let per = (pageContentHeight - fixed) / 2
        return min(metrics.minSinglePhotoImageHeight, max(96, per))
    }

    private static func feasibleTwoColumnRowImageHeight(
        metrics: Metrics,
        place: PlaceContent,
        fontTheme: FontTheme,
        storyUsesTwoColumns: Bool = false,
        showPlaceStory: Bool = true
    ) -> CGFloat {
        let placeBlk = boundedPlaceCaptionBlockHeight(
            place: place,
            metrics: metrics,
            fontTheme: fontTheme,
            storyUsesTwoColumns: storyUsesTwoColumns,
            showPlaceStory: showPlaceStory
        )
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let rowCap = min(f.lineHeight * 10 + photoCaptionToImageSpacing, 150)
        let fixed = dayHeaderHeight + placeTitleHeight + placeBlk + rowCap + 8
        return min(metrics.minTwoPhotoImageHeight, max(100, pageContentHeight - fixed))
    }

    private static func feasibleOverflowSingleImageHeight(metrics: Metrics, fontTheme: FontTheme, showHeader: Bool) -> CGFloat {
        let hd = showHeader ? overflowLabelHeight : 0
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let capB = min(f.lineHeight * 12 + photoCaptionToImageSpacing, 200)
        let fixed = dayHeaderHeight + hd + capB + 8
        return min(metrics.minSinglePhotoImageHeight, max(96, pageContentHeight - fixed))
    }

    private static func feasibleOverflowStackedRowImageHeight(metrics: Metrics, fontTheme: FontTheme, showHeader: Bool) -> CGFloat {
        let hd = showHeader ? overflowLabelHeight : 0
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let rowCap = min(f.lineHeight * 10 + photoCaptionToImageSpacing, 150)
        let fixed = dayHeaderHeight + hd + photoGap + rowCap * 2 + 8
        let per = (pageContentHeight - fixed) / 2
        return min(metrics.minSinglePhotoImageHeight, max(96, per))
    }

    private static func feasibleOverflowTwoColumnRowImageHeight(metrics: Metrics, fontTheme: FontTheme, showHeader: Bool) -> CGFloat {
        let hd = showHeader ? overflowLabelHeight : 0
        let f = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let rowCap = min(f.lineHeight * 10 + photoCaptionToImageSpacing, 150)
        let fixed = dayHeaderHeight + hd + rowCap + 8
        return min(metrics.minTwoPhotoImageHeight, max(96, pageContentHeight - fixed))
    }

    /// Extra height for photo caption text drawn **below** the image (`PhotoCardView`).
    private static func photoCaptionBelowImageExtraHeight(
        _ photo: PhotoContent,
        photoWidth: CGFloat,
        fontTheme: FontTheme,
        maxLines: Int
    ) -> CGFloat {
        let caption = photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !caption.isEmpty else { return 0 }

        let stackSpacing = photoCaptionToImageSpacing
        let font = StoryFontHelper.uiFont(for: fontTheme, size: photoCaptionFontSize)
        let maxCaptionHeight = font.lineHeight * CGFloat(max(1, maxLines))

        let rect = caption.boundingRect(
            with: CGSize(width: photoWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        let cappedTextHeight = min(rect.height, maxCaptionHeight)
        return stackSpacing + cappedTextHeight
    }

    // MARK: - Photo caption pagination (single-photo rows only)

    private static func takePrefixFittingHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> (head: String, tail: String) {
        let t = text
        guard !t.isEmpty, width > 0, maxHeight > 0 else { return ("", t) }

        var lo = 0
        var hi = t.count
        var best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            let idx = t.index(t.startIndex, offsetBy: mid)
            let sub = String(t[..<idx])
            let h = estimateTextHeight(sub, font: font, width: width)
            if h <= maxHeight {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if best == 0 {
            let first = String(t.prefix(1))
            return (first, String(t.dropFirst()))
        }

        var breakIdx = t.index(t.startIndex, offsetBy: best)
        while breakIdx > t.startIndex {
            let prev = t.index(before: breakIdx)
            if t[prev].isWhitespace || t[prev].isNewline { break }
            breakIdx = prev
        }
        if breakIdx == t.startIndex {
            breakIdx = t.index(t.startIndex, offsetBy: best)
        }

        let head = String(t[..<breakIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(t[breakIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, tail)
    }

    private static func splitCaptionIntoPaginatedChunks(
        _ raw: String,
        font: UIFont,
        width: CGFloat,
        firstChunkMaxHeight: CGFloat,
        continuationMaxHeight: CGFloat
    ) -> [String] {
        var remaining = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return [] }

        var chunks: [String] = []
        var useFirstBudget = true

        while !remaining.isEmpty {
            let maxH = useFirstBudget ? firstChunkMaxHeight : continuationMaxHeight
            useFirstBudget = false

            if estimateTextHeight(remaining, font: font, width: width) <= maxH {
                chunks.append(remaining)
                break
            }

            var (head, tail) = takePrefixFittingHeight(remaining, font: font, width: width, maxHeight: maxH)
            if head.isEmpty {
                let ch = String(remaining.prefix(1))
                chunks.append(ch)
                remaining = String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            chunks.append(head)
            remaining = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return chunks
    }

    private static func placeContentReplacingPhotos(_ place: PlaceContent, photos: [PhotoContent]) -> PlaceContent {
        PlaceContent(
            title: place.title,
            subtitle: place.subtitle,
            markerNumber: place.markerNumber,
            markerType: place.markerType,
            timestamp: place.timestamp,
            caption: place.caption,
            captionIsLong: place.captionIsLong,
            photos: photos
        )
    }

    private static func placeContentReplacingCaption(_ place: PlaceContent, caption: String?) -> PlaceContent {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let final: String? = {
            guard let t = trimmed, !t.isEmpty else { return nil }
            return t
        }()
        let c = final ?? ""
        return PlaceContent(
            title: place.title,
            subtitle: place.subtitle,
            markerNumber: place.markerNumber,
            markerType: place.markerType,
            timestamp: place.timestamp,
            caption: final,
            captionIsLong: c.count > 80,
            photos: place.photos
        )
    }

    private static func estimatedStoryLineCount(caption: String, metrics: Metrics, fontTheme: FontTheme) -> Int {
        let t = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return 0 }
        let font = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
        let h = estimateTextHeight(t, font: font, width: metrics.pageWidth) + font.lineHeight * 0.35
        let lh = max(1, font.lineHeight)
        return max(1, Int(ceil(h / lh)))
    }

    private static func shouldUseTwoColumnPlaceStory(caption: String, lineCount: Int) -> Bool {
        let t = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let (l, r) = splitBalancedForTwoColumns(t)
        guard !l.isEmpty, !r.isEmpty else { return false }
        if lineCount >= placeStoryLineCountSplitTwoPhotosThreshold { return true }
        if t.count >= 100 && lineCount >= 3 { return true }
        return false
    }

    private static func twoPhotoPlaceSlots(place: PlaceContent, metrics: Metrics, fontTheme: FontTheme) -> [ContentSlot] {
        let cap = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lines = estimatedStoryLineCount(caption: cap, metrics: metrics, fontTheme: fontTheme)
        let twoCol = shouldUseTwoColumnPlaceStory(caption: cap, lineCount: lines)
        if lines >= placeStoryLineCountSinglePhotoThreshold {
            let h0 = feasibleSinglePhotoImageHeight(
                metrics: metrics,
                place: place,
                fontTheme: fontTheme,
                storyUsesTwoColumns: twoCol,
                showPlaceStory: true
            )
            let h1 = feasibleSinglePhotoImageHeight(
                metrics: metrics,
                place: place,
                fontTheme: fontTheme,
                storyUsesTwoColumns: false,
                showPlaceStory: false
            )
            return [
                .placeBlock(
                    place,
                    photoSlice: 0...0,
                    photoImageHeight: h0,
                    photoGridLayout: .single,
                    storyUsesTwoColumns: twoCol,
                    showPlaceStory: true
                ),
                .placeBlock(
                    place,
                    photoSlice: 1...1,
                    photoImageHeight: h1,
                    photoGridLayout: .single,
                    storyUsesTwoColumns: false,
                    showPlaceStory: false
                )
            ]
        }
        let h = feasibleStackedRowImageHeight(
            metrics: metrics,
            place: place,
            fontTheme: fontTheme,
            storyUsesTwoColumns: twoCol,
            showPlaceStory: true
        )
        return [
            .placeBlock(
                place,
                photoSlice: 0...1,
                photoImageHeight: h,
                photoGridLayout: .stackedSingles,
                storyUsesTwoColumns: twoCol,
                showPlaceStory: true
            )
        ]
    }

    private static func photosBlockHeightInPlaceSlot(
        place: PlaceContent,
        photoSlice: ClosedRange<Int>,
        photoImageHeight: CGFloat,
        photoGridLayout: PhotoGridLayout,
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> CGFloat {
        guard !place.photos.isEmpty else { return 0 }
        let lo = photoSlice.lowerBound
        let hi = min(photoSlice.upperBound, place.photos.count - 1)
        guard lo <= hi else { return 0 }
        let photos = Array(place.photos[lo...hi])
        switch photoGridLayout {
        case .single:
            let photoWidth = metrics.singlePhotoWidth
            let extra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 48) }.max() ?? 0
            return photoImageHeight + extra
        case .twoColumn:
            let photoWidth = metrics.twoPhotoWidth
            let maxExtra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 10) }.max() ?? 0
            return photoImageHeight + maxExtra
        case .stackedSingles:
            let photoWidth = metrics.singlePhotoWidth
            let extras = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 10) }
            if extras.count >= 2 {
                return photoImageHeight + extras[0] + photoGap + photoImageHeight + extras[1]
            }
            let maxExtra = extras.max() ?? 0
            return photoImageHeight + maxExtra
        }
    }

    private static func placeStoryBlockTextHeight(
        caption: String,
        pageWidth: CGFloat,
        fontTheme: FontTheme,
        storyUsesTwoColumns: Bool
    ) -> CGFloat {
        let font = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
        if storyUsesTwoColumns {
            let colGap: CGFloat = 10
            let colW = max(40, (pageWidth - colGap) / 2)
            let (l, r) = splitBalancedForTwoColumns(caption)
            let hl = estimateTextHeight(l, font: font, width: colW) + font.lineHeight * 0.35
            let hr = r.isEmpty ? 0 : estimateTextHeight(r, font: font, width: colW) + font.lineHeight * 0.35
            return max(hl, hr)
        }
        return estimateTextHeight(caption, font: font, width: pageWidth) + font.lineHeight * 0.35
    }

    /// Splits long place stories into a first chunk above photos plus `.placeStoryContinuation` slots.
    private static func expandPlaceStoryPagination(
        _ slots: [ContentSlot],
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [ContentSlot] {
        let bodyFont = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
        let lh = max(1, bodyFont.lineHeight)
        let continuationTextMax = max(56, pageContentHeight - dayHeaderHeight - 56)

        var out: [ContentSlot] = []
        for slot in slots {
            guard case let .placeBlock(place, slice, imgH, grid, storyTwoCols, showStory) = slot else {
                out.append(slot)
                continue
            }
            guard showStory,
                  let capRaw = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !capRaw.isEmpty else {
                out.append(slot)
                continue
            }

            let hasPhotosInSlot: Bool = {
                guard !place.photos.isEmpty else { return false }
                let lo = slice.lowerBound
                let hi = min(slice.upperBound, place.photos.count - 1)
                return lo <= hi
            }()

            let photosBlockH = photosBlockHeightInPlaceSlot(
                place: place,
                photoSlice: slice,
                photoImageHeight: imgH,
                photoGridLayout: grid,
                metrics: metrics,
                fontTheme: fontTheme
            )
            let captionHeadroom = max(0, pageContentHeight - dayHeaderHeight - placeTitleHeight - photosBlockH - 8)
            let gaps = placeCaptionGaps(layoutMode: .normal, hasPhotosInSlot: hasPhotosInSlot)
            let maxBody = max(40, pageContentHeight * 0.38)
            let innerBudget = min(maxBody, max(0, captionHeadroom - gaps.top - gaps.bottom))

            var fullH = placeStoryBlockTextHeight(
                caption: capRaw,
                pageWidth: metrics.pageWidth,
                fontTheme: fontTheme,
                storyUsesTwoColumns: storyTwoCols
            )

            if fullH <= innerBudget {
                out.append(slot)
                continue
            }

            if storyTwoCols {
                let hSingle = placeStoryBlockTextHeight(
                    caption: capRaw,
                    pageWidth: metrics.pageWidth,
                    fontTheme: fontTheme,
                    storyUsesTwoColumns: false
                )
                if hSingle <= innerBudget {
                    out.append(
                        .placeBlock(
                            place,
                            photoSlice: slice,
                            photoImageHeight: imgH,
                            photoGridLayout: grid,
                            storyUsesTwoColumns: false,
                            showPlaceStory: true
                        )
                    )
                    continue
                }
                fullH = hSingle
            }

            let chunks = splitCaptionIntoPaginatedChunks(
                capRaw,
                font: bodyFont,
                width: metrics.pageWidth,
                firstChunkMaxHeight: max(lh, innerBudget - lh * 0.35),
                continuationMaxHeight: continuationTextMax
            )
            guard chunks.count > 1 else {
                out.append(slot)
                continue
            }

            let firstPlace = placeContentReplacingCaption(place, caption: chunks[0])
            out.append(
                .placeBlock(
                    firstPlace,
                    photoSlice: slice,
                    photoImageHeight: imgH,
                    photoGridLayout: grid,
                    storyUsesTwoColumns: false,
                    showPlaceStory: true
                )
            )
            for i in 1..<chunks.count {
                out.append(.placeStoryContinuation(text: chunks[i]))
            }
        }
        return out
    }

    /// Splits long **single-photo** captions into a first chunk under the image plus `.photoCaptionContinuation` slots.
    private static func expandPaginatedPhotoCaptions(
        _ slots: [ContentSlot],
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [ContentSlot] {
        let captionFont = StoryFontHelper.uiFont(for: fontTheme, size: 11)
        let w = metrics.singlePhotoWidth

        // Leave room for the "Continued" label + padding in `PhotoCaptionContinuationView` / `slotHeight`.
        let continuationTextMax = max(56, pageContentHeight - dayHeaderHeight - 56)
        let photoPageOverhead = placeTitleHeight + placeCaptionLong + metrics.minSinglePhotoImageHeight + 96
        let firstChunkMax = max(72, pageContentHeight - dayHeaderHeight - photoPageOverhead)

        var out: [ContentSlot] = []

        for slot in slots {
            switch slot {
            case .placeBlock(let place, let slice, let imgH, let grid, let storyTC, let showPS):
                guard grid == .single else {
                    out.append(slot)
                    continue
                }
                let lo = slice.lowerBound
                let hi = min(slice.upperBound, place.photos.count - 1)
                guard lo == hi, lo < place.photos.count else {
                    out.append(slot)
                    continue
                }
                let photo = place.photos[lo]
                let cap = photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !cap.isEmpty else {
                    out.append(slot)
                    continue
                }

                let fullH = estimateTextHeight(cap, font: captionFont, width: w)
                guard fullH > firstChunkMax else {
                    out.append(slot)
                    continue
                }

                let chunks = splitCaptionIntoPaginatedChunks(
                    cap,
                    font: captionFont,
                    width: w,
                    firstChunkMaxHeight: firstChunkMax,
                    continuationMaxHeight: continuationTextMax
                )
                guard chunks.count > 1 else {
                    out.append(slot)
                    continue
                }

                var photos = place.photos
                let c0 = chunks[0]
                photos[lo] = PhotoContent(
                    image: photo.image,
                    caption: c0,
                    captionIsLong: c0.count > 80
                )
                out.append(
                    .placeBlock(
                        placeContentReplacingPhotos(place, photos: photos),
                        photoSlice: slice,
                        photoImageHeight: imgH,
                        photoGridLayout: grid,
                        storyUsesTwoColumns: storyTC,
                        showPlaceStory: showPS
                    )
                )
                for i in 1..<chunks.count {
                    out.append(.photoCaptionContinuation(text: chunks[i]))
                }

            case .photoOverflowContinuation(let name, let place, let slice, let imgH, let grid, let show):
                guard grid == .single else {
                    out.append(slot)
                    continue
                }
                let lo = slice.lowerBound
                let hi = min(slice.upperBound, place.photos.count - 1)
                guard lo == hi, lo < place.photos.count else {
                    out.append(slot)
                    continue
                }
                let photo = place.photos[lo]
                let cap = photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !cap.isEmpty else {
                    out.append(slot)
                    continue
                }

                let fullH = estimateTextHeight(cap, font: captionFont, width: w)
                guard fullH > firstChunkMax else {
                    out.append(slot)
                    continue
                }

                let chunks = splitCaptionIntoPaginatedChunks(
                    cap,
                    font: captionFont,
                    width: w,
                    firstChunkMaxHeight: firstChunkMax,
                    continuationMaxHeight: continuationTextMax
                )
                guard chunks.count > 1 else {
                    out.append(slot)
                    continue
                }

                var photos = place.photos
                let c0 = chunks[0]
                photos[lo] = PhotoContent(
                    image: photo.image,
                    caption: c0,
                    captionIsLong: c0.count > 80
                )
                let newPlace = placeContentReplacingPhotos(place, photos: photos)
                out.append(
                    .photoOverflowContinuation(
                        placeName: name,
                        newPlace,
                        photoSlice: slice,
                        photoImageHeight: imgH,
                        photoGridLayout: grid,
                        showOverflowHeader: show
                    )
                )
                for i in 1..<chunks.count {
                    out.append(.photoCaptionContinuation(text: chunks[i]))
                }

            default:
                out.append(slot)
            }
        }

        return out
    }

    /// Any `.photoCaptionContinuation` taller than one page is split again (defensive — e.g. font metrics drift).
    private static func refineOversizedPhotoCaptionContinuations(
        _ slots: [ContentSlot],
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [ContentSlot] {
        let font = StoryFontHelper.uiFont(for: fontTheme, size: 11)
        let lh = max(1, font.lineHeight)
        let chrome: CGFloat = 4 + 18 + 6 + 8
        let maxTextH = max(32, pageContentHeight - dayHeaderHeight - chrome - lh * 0.35)

        var out: [ContentSlot] = []
        for slot in slots {
            guard case .photoCaptionContinuation(let text) = slot else {
                out.append(slot)
                continue
            }
            let rawTextH = estimateTextHeight(text, font: font, width: metrics.pageWidth) + lh * 0.35
            if rawTextH <= maxTextH {
                out.append(slot)
                continue
            }
            let sub = splitCaptionIntoPaginatedChunks(
                text,
                font: font,
                width: metrics.pageWidth,
                firstChunkMaxHeight: maxTextH,
                continuationMaxHeight: maxTextH
            )
            for s in sub {
                out.append(.photoCaptionContinuation(text: s))
            }
        }
        return out
    }

    /// Any `.placeStoryContinuation` taller than one page is split again (defensive).
    private static func refineOversizedPlaceStoryContinuations(
        _ slots: [ContentSlot],
        metrics: Metrics,
        fontTheme: FontTheme
    ) -> [ContentSlot] {
        let font = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
        let lh = max(1, font.lineHeight)
        let chrome: CGFloat = 4 + 18 + 6 + 8
        let maxTextH = max(32, pageContentHeight - dayHeaderHeight - chrome - lh * 0.35)

        var out: [ContentSlot] = []
        for slot in slots {
            guard case .placeStoryContinuation(let text) = slot else {
                out.append(slot)
                continue
            }
            let rawTextH = estimateTextHeight(text, font: font, width: metrics.pageWidth) + lh * 0.35
            if rawTextH <= maxTextH {
                out.append(slot)
                continue
            }
            let sub = splitCaptionIntoPaginatedChunks(
                text,
                font: font,
                width: metrics.pageWidth,
                firstChunkMaxHeight: maxTextH,
                continuationMaxHeight: maxTextH
            )
            for s in sub {
                out.append(.placeStoryContinuation(text: s))
            }
        }
        return out
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
        let h = StoryRenderMetrics.effectiveStoryViewportHeight - storyChromeBottomOverlayHeight
        var used: CGFloat = 0
        if isFirstPage {
            used += tocCoverStripHeight + tocHeaderHeight + tocFirstPageBottomChrome
        } else {
            used += tocTopPadding + tocContinuationHeaderHeight(fontTheme: fontTheme) + tocBottomChrome
        }
        return max(0, h - used)
    }

    /// Mirrors `TOCPageView` row structure: optional separator (14 + 1pt line + 14), inner stack, layout cushion.
    private static func estimatedTOCRowHeight(
        entry: TOCEntry,
        contentWidth: CGFloat,
        fontTheme: FontTheme,
        includeSeparatorAbove: Bool
    ) -> CGFloat {
        var h: CGFloat = 0
        if includeSeparatorAbove {
            // Matches `TOCPageView.tocDaySeparator` vertical padding + 1pt hairline.
            h += 14 + 1 + 14
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

        // Small cushion so we don’t pack slightly tighter than Text layout (row bottom padding removed; spacing is in separator).
        return h + 4
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
            coverPhoto: content.overview.coverPhoto,
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
                allSlots.append(.dayCaption(trimmed))
            }
        }

        // Place slots
        for place in day.places {
            allSlots.append(contentsOf: slotsForPlace(place, metrics: metrics, fontTheme: fontTheme))
        }

        let storyPaginated = expandPlaceStoryPagination(allSlots, metrics: metrics, fontTheme: fontTheme)
        let expandedSlots = expandPaginatedPhotoCaptions(storyPaginated, metrics: metrics, fontTheme: fontTheme)
        let refinedPhoto = refineOversizedPhotoCaptionContinuations(expandedSlots, metrics: metrics, fontTheme: fontTheme)
        let refinedSlots = refineOversizedPlaceStoryContinuations(refinedPhoto, metrics: metrics, fontTheme: fontTheme)

        // Pack slots into pages (place story always above photos)
        return packSlots(
            refinedSlots,
            day: day,
            isLastDay: isLastDay,
            nextDayName: nextDayName,
            metrics: metrics,
            fontTheme: fontTheme,
            layoutMode: .normal
        )
    }

    private static func slotsForPlace(_ place: PlaceContent, metrics: Metrics, fontTheme: FontTheme) -> [ContentSlot] {
        let photoCount = place.photos.count
        if photoCount == 0 {
            return [
                .placeBlock(
                    place,
                    photoSlice: 0...0,
                    photoImageHeight: 0,
                    photoGridLayout: .single,
                    storyUsesTwoColumns: false,
                    showPlaceStory: true
                )
            ]
        } else if photoCount <= 2 {
            if photoCount == 1 {
                let cap = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let lines = estimatedStoryLineCount(caption: cap, metrics: metrics, fontTheme: fontTheme)
                let twoCol = shouldUseTwoColumnPlaceStory(caption: cap, lineCount: lines)
                let h = feasibleSinglePhotoImageHeight(
                    metrics: metrics,
                    place: place,
                    fontTheme: fontTheme,
                    storyUsesTwoColumns: twoCol,
                    showPlaceStory: true
                )
                return [
                    .placeBlock(
                        place,
                        photoSlice: 0...0,
                        photoImageHeight: h,
                        photoGridLayout: .single,
                        storyUsesTwoColumns: twoCol,
                        showPlaceStory: true
                    )
                ]
            } else {
                return twoPhotoPlaceSlots(place: place, metrics: metrics, fontTheme: fontTheme)
            }
        } else {
            let cap = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lines = estimatedStoryLineCount(caption: cap, metrics: metrics, fontTheme: fontTheme)
            let twoColLead = shouldUseTwoColumnPlaceStory(caption: cap, lineCount: lines)
            let leadH = feasibleTwoColumnRowImageHeight(
                metrics: metrics,
                place: place,
                fontTheme: fontTheme,
                storyUsesTwoColumns: twoColLead,
                showPlaceStory: true
            )
            var result: [ContentSlot] = [
                .placeBlock(
                    place,
                    photoSlice: 0...1,
                    photoImageHeight: leadH,
                    photoGridLayout: .twoColumn,
                    storyUsesTwoColumns: twoColLead,
                    showPlaceStory: true
                )
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
                    let oh = feasibleOverflowSingleImageHeight(metrics: metrics, fontTheme: fontTheme, showHeader: showHeader)
                    result.append(
                        .photoOverflowContinuation(
                            placeName: place.title,
                            place,
                            photoSlice: slice,
                            photoImageHeight: oh,
                            photoGridLayout: .single,
                            showOverflowHeader: showHeader
                        )
                    )
                } else {
                    // Two photos in continuation: only the 3rd + 4th (indices 2…3) use stacked full-width rows;
                    // later pairs (5th+6th, …) stay side-by-side in two columns.
                    let isThirdAndFourthOnly = (idx == 2 && end == 3)
                    let showHeader = photoCount != 4
                    let rowH = isThirdAndFourthOnly
                        ? feasibleOverflowStackedRowImageHeight(metrics: metrics, fontTheme: fontTheme, showHeader: showHeader)
                        : feasibleOverflowTwoColumnRowImageHeight(metrics: metrics, fontTheme: fontTheme, showHeader: showHeader)
                    result.append(
                        .photoOverflowContinuation(
                            placeName: place.title,
                            place,
                            photoSlice: slice,
                            photoImageHeight: rowH,
                            photoGridLayout: isThirdAndFourthOnly ? .stackedSingles : .twoColumn,
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
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode
    ) -> CGFloat {
        switch slot {
        case .dayCaption(let text):
            return dayStoryCaptionBoxHeight(for: text, pageWidth: metrics.pageWidth, fontTheme: fontTheme)

        case .placeBlock(let place, let photoSlice, let photoImageHeight, let photoGridLayout, let storyUsesTwoColumns, let showPlaceStory):
            var h: CGFloat = placeTitleHeight
            let hasPhotosInSlot: Bool = {
                guard !place.photos.isEmpty else { return false }
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                return lo <= hi
            }()

            var captionBlockH: CGFloat = 0
            if showPlaceStory,
               let caption = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                let captionSlotH = place.captionIsLong ? placeCaptionLong : placeCaptionShort
                let gaps = placeCaptionGaps(layoutMode: layoutMode, hasPhotosInSlot: hasPhotosInSlot)
                let minCaptionTextH = max(0, captionSlotH - gaps.top - gaps.bottom)

                let captionFont = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
                let estimatedCaptionTextH: CGFloat
                if storyUsesTwoColumns {
                    let colGap: CGFloat = 10
                    let colW = max(40, (metrics.pageWidth - colGap) / 2)
                    let (l, r) = splitBalancedForTwoColumns(caption)
                    let hl = estimateTextHeight(l, font: captionFont, width: colW) + captionFont.lineHeight * 0.35
                    let hr = r.isEmpty ? 0 : estimateTextHeight(r, font: captionFont, width: colW) + captionFont.lineHeight * 0.35
                    estimatedCaptionTextH = max(hl, hr)
                } else {
                    estimatedCaptionTextH = estimateTextHeight(caption, font: captionFont, width: metrics.pageWidth) + captionFont.lineHeight * 0.35
                }
                let usedCaptionTextH = max(minCaptionTextH, estimatedCaptionTextH)

                captionBlockH = gaps.top + gaps.bottom + usedCaptionTextH
            }

            var photosBlockH: CGFloat = 0
            if !place.photos.isEmpty {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                if lo <= hi {
                    let photos = Array(place.photos[lo...hi])
                    switch photoGridLayout {
                    case .single:
                        let photoWidth = metrics.singlePhotoWidth
                        let extra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 48) }.max() ?? 0
                        photosBlockH += photoImageHeight + extra

                    case .twoColumn:
                        let photoWidth = metrics.twoPhotoWidth
                        let maxExtra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 10) }.max() ?? 0
                        photosBlockH += photoImageHeight + maxExtra

                    case .stackedSingles:
                        let photoWidth = metrics.singlePhotoWidth
                        let extras = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: photoWidth, fontTheme: fontTheme, maxLines: 10) }
                        if extras.count >= 2 {
                            photosBlockH += photoImageHeight + extras[0]
                            photosBlockH += photoGap
                            photosBlockH += photoImageHeight + extras[1]
                        } else {
                            let maxExtra = extras.max() ?? 0
                            photosBlockH += photoImageHeight + maxExtra
                        }
                    }
                }
            }

            let captionHeadroom = max(0, pageContentHeight - dayHeaderHeight - placeTitleHeight - photosBlockH - 8)
            if captionBlockH > captionHeadroom {
                captionBlockH = captionHeadroom
            }

            h += captionBlockH
            h += photosBlockH
            return h

        case .photoCaptionContinuation(let text):
            let font = StoryFontHelper.uiFont(for: fontTheme, size: 11)
            let lh = max(1, font.lineHeight)
            let labelBand: CGFloat = 18
            let maxTextH = max(0, pageContentHeight - dayHeaderHeight - 4 - labelBand - 6 - 8)
            let rawTextH = estimateTextHeight(text, font: font, width: metrics.pageWidth) + lh * 0.35
            let textH = min(rawTextH, maxTextH)
            return 4 + labelBand + textH + 6

        case .placeStoryContinuation(let text):
            let font = StoryFontHelper.uiFont(for: fontTheme, size: placeStoryBodyFontSize)
            let lh = max(1, font.lineHeight)
            let labelBand: CGFloat = 18
            let maxTextH = max(0, pageContentHeight - dayHeaderHeight - 4 - labelBand - 6 - 8)
            let rawTextH = estimateTextHeight(text, font: font, width: metrics.pageWidth) + lh * 0.35
            let textH = min(rawTextH, maxTextH)
            return 4 + labelBand + textH + 6

        case .photoOverflowContinuation(_, let place, let photoSlice, let photoImageHeight, let photoGridLayout, let showOverflowHeader):
            // photoSlice length corresponds to 1 or 2 photos for this block.
            let lo = photoSlice.lowerBound
            let hi = min(photoSlice.upperBound, place.photos.count - 1)
            guard lo <= hi, !place.photos.isEmpty else { return showOverflowHeader ? overflowLabelHeight : 0 }

            let headerH: CGFloat = showOverflowHeader ? overflowLabelHeight : 0

            let photos = Array(place.photos[lo...hi])
            switch photoGridLayout {
            case .single:
                let extra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: metrics.singlePhotoWidth, fontTheme: fontTheme, maxLines: 48) }.max() ?? 0
                return headerH + photoImageHeight + extra

            case .twoColumn:
                let maxExtra = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: metrics.twoPhotoWidth, fontTheme: fontTheme, maxLines: 10) }.max() ?? 0
                return headerH + photoImageHeight + maxExtra

            case .stackedSingles:
                let extras = photos.map { photoCaptionBelowImageExtraHeight($0, photoWidth: metrics.singlePhotoWidth, fontTheme: fontTheme, maxLines: 10) }
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
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode
    ) -> [ContentSlot] {
        let photoCount = place.photos.count

        let fullBorrowCandidate: [ContentSlot]
        switch photoCount {
        case 0:
            fullBorrowCandidate = [
                .placeBlock(
                    place,
                    photoSlice: 0...0,
                    photoImageHeight: 0,
                    photoGridLayout: .single,
                    storyUsesTwoColumns: false,
                    showPlaceStory: true
                )
            ]
        case 1:
            let cap = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lines = estimatedStoryLineCount(caption: cap, metrics: metrics, fontTheme: fontTheme)
            let twoCol = shouldUseTwoColumnPlaceStory(caption: cap, lineCount: lines)
            let h = feasibleSinglePhotoImageHeight(
                metrics: metrics,
                place: place,
                fontTheme: fontTheme,
                storyUsesTwoColumns: twoCol,
                showPlaceStory: true
            )
            fullBorrowCandidate = [
                .placeBlock(
                    place,
                    photoSlice: 0...0,
                    photoImageHeight: h,
                    photoGridLayout: .single,
                    storyUsesTwoColumns: twoCol,
                    showPlaceStory: true
                )
            ]
        case 2:
            fullBorrowCandidate = twoPhotoPlaceSlots(place: place, metrics: metrics, fontTheme: fontTheme)
        default:
            let cap = place.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lines = estimatedStoryLineCount(caption: cap, metrics: metrics, fontTheme: fontTheme)
            let twoColLead = shouldUseTwoColumnPlaceStory(caption: cap, lineCount: lines)
            let h = feasibleTwoColumnRowImageHeight(
                metrics: metrics,
                place: place,
                fontTheme: fontTheme,
                storyUsesTwoColumns: twoColLead,
                showPlaceStory: true
            )
            fullBorrowCandidate = [
                .placeBlock(
                    place,
                    photoSlice: 0...1,
                    photoImageHeight: h,
                    photoGridLayout: .twoColumn,
                    storyUsesTwoColumns: twoColLead,
                    showPlaceStory: true
                )
            ]
        }

        let fullBorrowCandidateHeight = fullBorrowCandidate.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode) }
        if remainingSpace >= fullBorrowCandidateHeight {
            return fullBorrowCandidate
        }
        return []
    }

    /// Grows `photoImageHeight` for one photo slot by `slotShare` total vertical budget (stacked rows split `slotShare` across two rows).
    private static func applyPhotoSlotVerticalStretch(_ slot: ContentSlot, slotShare: CGFloat) -> ContentSlot {
        switch slot {
        case .placeBlock(let place, let slice, let h, let layout, let stc, let sps):
            let extraPerRow: CGFloat
            switch layout {
            case .stackedSingles:
                extraPerRow = slotShare / 2
            case .single, .twoColumn:
                extraPerRow = slotShare
            }
            return .placeBlock(
                place,
                photoSlice: slice,
                photoImageHeight: h + extraPerRow,
                photoGridLayout: layout,
                storyUsesTwoColumns: stc,
                showPlaceStory: sps
            )

        case .photoOverflowContinuation(let name, let place, let slice, let h, let layout, let show):
            let extraPerRow: CGFloat
            switch layout {
            case .stackedSingles:
                extraPerRow = slotShare / 2
            case .single, .twoColumn:
                extraPerRow = slotShare
            }
            return .photoOverflowContinuation(
                placeName: name,
                place,
                photoSlice: slice,
                photoImageHeight: h + extraPerRow,
                photoGridLayout: layout,
                showOverflowHeader: show
            )

        case .dayCaption, .photoCaptionContinuation, .placeStoryContinuation:
            return slot
        }
    }

    /// When a day page shows **exactly two photos** total, prefer a vertical stack (full-width rows) over a
    /// side-by-side pair — e.g. the first two photos of a 3+ stop are normally `twoColumn`, but if nothing
    /// else shares the page they read as a standalone pair and should match the two-photo stop layout.
    /// Skips conversion if the taller stacked layout would exceed `pageContentHeight` (same height sum as `packSlots`).
    private static func applyTwoPhotoPageStackingIfNeeded(
        _ pages: [DayContentPage],
        metrics: Metrics,
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode
    ) -> [DayContentPage] {
        func photoCountInSlot(_ slot: ContentSlot) -> Int {
            switch slot {
            case .placeBlock(let place, let slice, _, _, _, _):
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
            case .dayCaption, .photoCaptionContinuation, .placeStoryContinuation:
                return 0
            }
        }

        func totalPhotos(_ slots: [ContentSlot]) -> Int {
            slots.reduce(0) { $0 + photoCountInSlot($1) }
        }

        func pageBaseUsedHeight(_ slots: [ContentSlot]) -> CGFloat {
            dayHeaderHeight + slots.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode) }
        }

        func convertTwoColumnPairToStacked(_ slot: ContentSlot) -> ContentSlot {
            switch slot {
            case .placeBlock(let place, let slice, _, let layout, let stc, let sps):
                guard layout == .twoColumn else { return slot }
                let lo = slice.lowerBound
                let hi = min(slice.upperBound, place.photos.count - 1)
                guard lo <= hi, hi - lo + 1 == 2 else { return slot }
                return .placeBlock(
                    place,
                    photoSlice: slice,
                    photoImageHeight: metrics.minSinglePhotoImageHeight,
                    photoGridLayout: .stackedSingles,
                    storyUsesTwoColumns: stc,
                    showPlaceStory: sps
                )
            case .photoOverflowContinuation(let name, let place, let slice, _, let layout, let show):
                guard layout == .twoColumn else { return slot }
                let lo = slice.lowerBound
                let hi = min(slice.upperBound, place.photos.count - 1)
                guard lo <= hi, hi - lo + 1 == 2 else { return slot }
                return .photoOverflowContinuation(
                    placeName: name,
                    place,
                    photoSlice: slice,
                    photoImageHeight: metrics.minSinglePhotoImageHeight,
                    photoGridLayout: .stackedSingles,
                    showOverflowHeader: show
                )
            default:
                return slot
            }
        }

        return pages.map { page in
            let slots = page.slots
            guard totalPhotos(slots) == 2 else { return page }

            let newSlots = slots.map { convertTwoColumnPairToStacked($0) }
            guard pageBaseUsedHeight(newSlots) <= pageContentHeight else { return page }

            return DayContentPage(
                day: page.day,
                isFirstPage: page.isFirstPage,
                slots: newSlots,
                isLastPageOfDay: page.isLastPageOfDay,
                isLastPageOfTrip: page.isLastPageOfTrip,
                nextDayName: page.nextDayName
            )
        }
    }

    private static func packSlots(
        _ slots: [ContentSlot],
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?,
        metrics: Metrics,
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode
    ) -> [DayContentPage] {

        var pages: [DayContentPage] = []
        var currentSlots: [ContentSlot] = []
        var usedHeight: CGFloat = dayHeaderHeight
        var isFirstPage = true
        var slotIdx = 0
        var didBorrowOnFirstPage = false

        while slotIdx < slots.count {
            let slot = slots[slotIdx]
            let h = slotHeight(slot, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode)

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
            }

            currentSlots.append(slot)
            usedHeight += h
            slotIdx += 1

            // Peek-ahead borrow: after place 1's last slot on the first page, try to borrow place 2
            if isFirstPage && !didBorrowOnFirstPage,
               case .placeBlock(let place1, _, _, _, _, _) = slot,
               slotIdx < slots.count,
               case .placeBlock(let place2, _, _, _, _, _) = slots[slotIdx] {

                let p1PhotoCount = place1.photos.count
                guard p1PhotoCount <= 2 else { continue }

                let remaining = pageContentHeight - usedHeight
                let borrowed = borrowSlots(for: place2, remainingSpace: remaining, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode)

                if !borrowed.isEmpty {
                let borrowedHeight = borrowed.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode) }
                    // Ensure the next page has room for at least two minimal place blocks.
                    let minNextPageHeight: CGFloat = (placeTitleHeight + metrics.minSinglePhotoImageHeight) * 2
                    let remainingAfterBorrow = pageContentHeight - borrowedHeight
                    if remainingAfterBorrow >= minNextPageHeight {
                        currentSlots.append(contentsOf: borrowed)
                        usedHeight += borrowedHeight
                        didBorrowOnFirstPage = true
                        // `borrowed` can be multiple `.placeBlock`s (e.g. two-photo stop with a long story);
                        // skip the same number of matching upcoming slots so place 2 is not laid out twice.
                        var scan = slotIdx
                        var matched = 0
                        while scan < slots.count, matched < borrowed.count {
                            if case .placeBlock(let p, _, _, _, _, _) = slots[scan],
                               p.markerNumber == place2.markerNumber,
                               p.title == place2.title {
                                matched += 1
                                scan += 1
                            } else {
                                break
                            }
                        }
                        slotIdx = matched > 0 ? scan : slotIdx + 1
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

        pages = applyTwoPhotoPageStackingIfNeeded(
            pages,
            metrics: metrics,
            fontTheme: fontTheme,
            layoutMode: layoutMode
        )

        // After packing with minimum photo heights, fill leftover vertical space by stretching
        // photo row heights. Multiple photo blocks on a page split leftover evenly between blocks;
        // within a block, two-column rows share one height and stacked singles split across two rows.
        for pageIndex in 0..<pages.count {
            let page = pages[pageIndex]
            var slots = page.slots

            let baseUsedHeight = dayHeaderHeight + slots.reduce(0) { $0 + slotHeight($1, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode) }
            var leftover = max(0, pageContentHeight - baseUsedHeight)
            guard leftover > 0 else { continue }

            func photoCount(in slot: ContentSlot) -> Int {
                switch slot {
                case .placeBlock(let place, let slice, _, _, _, _):
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
                case .dayCaption, .photoCaptionContinuation, .placeStoryContinuation:
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
                   case let .placeBlock(p0, s0, h0, layout0, stc0, sps0) = slots[i0],
                   case let .placeBlock(p1, _, _, layout1, _, _) = slots[i1],
                   layout0 == .single,
                   (layout1 == .twoColumn || layout1 == .stackedSingles),
                   p0.markerNumber != p1.markerNumber {
                    slots[i0] = .placeBlock(
                        p0,
                        photoSlice: s0,
                        photoImageHeight: h0 + leftover,
                        photoGridLayout: .single,
                        storyUsesTwoColumns: stc0,
                        showPlaceStory: sps0
                    )
                    leftover = 0
                }
            }

            // Rule 3: consume remaining whitespace by stretching photo rows.
            // Multiple photo blocks on one page share leftover **evenly** so earlier two-column rows grow too,
            // not only the last block. A single photo block still receives the full leftover.
            if leftover > 0, !photoSlotIndices.isEmpty {
                if photoSlotIndices.count >= 2 {
                    let share = leftover / CGFloat(photoSlotIndices.count)
                    for idx in photoSlotIndices {
                        slots[idx] = applyPhotoSlotVerticalStretch(slots[idx], slotShare: share)
                    }
                } else if let only = photoSlotIndices.first {
                    slots[only] = applyPhotoSlotVerticalStretch(slots[only], slotShare: leftover)
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

    // MARK: - Story mode PDF link annotations

    /// UIKit-style rects (origin top-left, +y down) for PDF link annotations over place titles on a day content page.
    /// Matches `DayContentPageView` padding, `dayHeaderHeight`, `VStack(spacing: 8)` between slots, and `PlaceBlockView` / `PhotoContinuationBlockView` top padding.
    static func storyModePDFPlaceLinkRects(
        storyPage: StoryPage,
        pageSize: CGSize,
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode = .normal
    ) -> [(CGRect, URL)] {
        guard case .dayContent(let dayPage) = storyPage else { return [] }
        let metrics = makeMetrics()
        let horizontalPadding: CGFloat = 16
        let contentWidth = max(0, pageSize.width - horizontalPadding * 2)
        var y: CGFloat = 12 + dayHeaderHeight
        var results: [(CGRect, URL)] = []

        for (idx, slot) in dayPage.slots.enumerated() {
            switch slot {
            case .dayCaption, .photoCaptionContinuation, .placeStoryContinuation:
                break
            case .placeBlock(let place, _, _, _, _, _):
                if let url = StoryPlaceGoogleSearch.url(placeName: place.title, placeSubtitle: place.subtitle) {
                    let titleY = y + 4
                    results.append(
                        (CGRect(x: horizontalPadding, y: titleY, width: contentWidth, height: placeTitleHeight), url)
                    )
                }
            case .photoOverflowContinuation(let name, let place, _, _, _, let showOverflowHeader):
                if showOverflowHeader,
                   let url = StoryPlaceGoogleSearch.url(placeName: name, placeSubtitle: place.subtitle) {
                    let headerY = y + 4
                    results.append(
                        (CGRect(x: horizontalPadding, y: headerY, width: contentWidth, height: overflowLabelHeight), url)
                    )
                }
            }

            y += slotHeight(slot, metrics: metrics, fontTheme: fontTheme, layoutMode: layoutMode)
            if idx < dayPage.slots.count - 1 {
                y += 8
            }
        }

        return results
    }

    /// Rects and 0-based PDF page indices for in-document jumps when the user taps a TOC day row (Day N through “N moments”, excluding the gray places line — those keep Google links from `storyModePDFTOCLinkRects`).
    /// Matches `TOCPageView`’s `Button` wrapping `tocEntryRow` minus the places line overlap.
    static func storyModePDFTOCDayJumpRects(
        storyPage: StoryPage,
        pageSize: CGSize,
        fontTheme: FontTheme
    ) -> [(CGRect, Int)] {
        guard case .tableOfContents(let entries, _, let pageIndex, _) = storyPage else { return [] }
        guard !entries.isEmpty else { return [] }

        let horizontalInset: CGFloat = 16
        let contentWidth = max(0, pageSize.width - horizontalInset * 2)

        let dayFont = StoryFontHelper.uiFont(for: fontTheme, size: 13, weight: .bold)
        let pageNumFont = StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .bold)
        let titleFont = StoryFontHelper.uiFont(for: fontTheme, size: 18, weight: .bold)
        let dateFont = StoryFontHelper.uiFont(for: fontTheme, size: 12)
        let momentsFont = StoryFontHelper.uiItalicFont(for: fontTheme, size: 10)

        var y: CGFloat
        if pageIndex == 1 {
            y = tocCoverStripHeight + tocHeaderHeight
        } else {
            y = tocTopPadding + tocContinuationHeaderHeight(fontTheme: fontTheme)
        }

        var results: [(CGRect, Int)] = []

        for (rowIdx, entry) in entries.enumerated() {
            if rowIdx > 0 {
                y += 14 + 1 + 14
            }

            let rowTop = y
            let titleText = tocDayTitleString(for: entry)
            let titleH = min(
                estimateTextHeight(titleText, font: titleFont, width: contentWidth),
                titleFont.lineHeight * 2 + 1
            )

            let innerGap: CGFloat = 2
            var placesLineTop = rowTop
            placesLineTop += max(dayFont.lineHeight, pageNumFont.lineHeight)
            placesLineTop += innerGap * 3
            placesLineTop += titleH
            placesLineTop += dateFont.lineHeight + innerGap + momentsFont.lineHeight
            placesLineTop += 2

            let dayRectHeight = placesLineTop - rowTop
            if entry.dayStartPageNumber > 0, dayRectHeight > 0 {
                let destIndex = entry.dayStartPageNumber - 1
                results.append(
                    (
                        CGRect(x: horizontalInset, y: rowTop, width: contentWidth, height: dayRectHeight),
                        destIndex
                    )
                )
            }

            y += estimatedTOCRowHeight(
                entry: entry,
                contentWidth: contentWidth,
                fontTheme: fontTheme,
                includeSeparatorAbove: false
            )
        }

        return results
    }

    /// Google link rects for each place name on the TOC gray “places” line (matches `TOCPageView` + `estimatedTOCRowHeight`).
    static func storyModePDFTOCLinkRects(
        storyPage: StoryPage,
        pageSize: CGSize,
        fontTheme: FontTheme
    ) -> [(CGRect, URL)] {
        guard case .tableOfContents(let entries, _, let pageIndex, _) = storyPage else { return [] }
        guard !entries.isEmpty else { return [] }

        let horizontalInset: CGFloat = 16
        let contentWidth = max(0, pageSize.width - horizontalInset * 2)

        let dayFont = StoryFontHelper.uiFont(for: fontTheme, size: 13, weight: .bold)
        let pageFont = StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .bold)
        let titleFont = StoryFontHelper.uiFont(for: fontTheme, size: 18, weight: .bold)
        let dateFont = StoryFontHelper.uiFont(for: fontTheme, size: 12)
        let momentsFont = StoryFontHelper.uiItalicFont(for: fontTheme, size: 10)
        let placesFont = StoryFontHelper.uiFont(for: fontTheme, size: 11)

        var y: CGFloat
        if pageIndex == 1 {
            y = tocCoverStripHeight + tocHeaderHeight
        } else {
            y = tocTopPadding + tocContinuationHeaderHeight(fontTheme: fontTheme)
        }

        var results: [(CGRect, URL)] = []

        for (rowIdx, entry) in entries.enumerated() {
            if rowIdx > 0 {
                y += 14 + 1 + 14
            }

            let rowTop = y
            let titleText = tocDayTitleString(for: entry)
            let titleH = min(
                estimateTextHeight(titleText, font: titleFont, width: contentWidth),
                titleFont.lineHeight * 2 + 1
            )

            let innerGap: CGFloat = 2
            var placesLineTop = rowTop
            placesLineTop += max(dayFont.lineHeight, pageFont.lineHeight)
            placesLineTop += innerGap * 3
            placesLineTop += titleH
            placesLineTop += dateFont.lineHeight + innerGap + momentsFont.lineHeight
            placesLineTop += 2

            let localRects = tocPlaceLineCharacterRangeLinkRects(
                placeNames: entry.placeNames,
                containerWidth: contentWidth,
                font: placesFont
            )
            for (r, url) in localRects {
                results.append((r.offsetBy(dx: horizontalInset, dy: placesLineTop), url))
            }

            y += estimatedTOCRowHeight(
                entry: entry,
                contentWidth: contentWidth,
                fontTheme: fontTheme,
                includeSeparatorAbove: false
            )
        }

        return results
    }

    /// Lays out the comma-separated places string with `NSLayoutManager` (2-line cap) and returns one rect per place name.
    private static func tocPlaceLineCharacterRangeLinkRects(
        placeNames: [String],
        containerWidth: CGFloat,
        font: UIFont
    ) -> [(CGRect, URL)] {
        var segments: [(NSRange, URL)] = []
        var full = ""
        var needsComma = false
        for raw in placeNames {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let u = StoryPlaceGoogleSearch.url(placeName: t, placeSubtitle: nil) else { continue }
            if needsComma { full += ", " }
            needsComma = true
            let start = (full as NSString).length
            full += t
            let len = (t as NSString).length
            segments.append((NSRange(location: start, length: len), u))
        }
        guard !full.isEmpty, !segments.isEmpty, containerWidth > 0 else { return [] }

        let attr = NSAttributedString(string: full, attributes: [.font: font])
        let storage = NSTextStorage(attributedString: attr)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: containerWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.maximumNumberOfLines = 2
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        var out: [(CGRect, URL)] = []
        for (range, url) in segments {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            guard rect.width > 0, rect.height > 0 else { continue }
            out.append((rect, url))
        }
        return out
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

    /// Safe area from the key window (notch / status bar / home indicator). `.zero` if unavailable (e.g. early launch).
    static var windowSafeAreaInsets: UIEdgeInsets {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return .zero
        }
        return window.safeAreaInsets
    }

    /// Matches `TabView` when it does **not** use `ignoresSafeArea()`: full screen minus top/bottom safe insets.
    static var effectiveStoryViewportHeight: CGFloat {
        let h = clampedScreenHeight
        let top = windowSafeAreaInsets.top
        let bottom = windowSafeAreaInsets.bottom
        return max(0, h - top - bottom)
    }
}
