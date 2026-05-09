import UIKit
import MapKit

// MARK: - PDF Export Options

enum BlogColor: String, CaseIterable, Codable {
    case white = "White"
    case black = "Black"

    var label: String {
        switch self {
        case .white: return "Light Mode"
        case .black: return "Dark Mode"
        }
    }
    var subtitle: String {
        switch self {
        case .white: return "White background, dark text"
        case .black: return "Black background, white text"
        }
    }
}

enum PDFLayoutMode: String, CaseIterable, Codable {
    case normal = "Normal"
    case story  = "Story"

    var label: String { rawValue }
    var subtitle: String {
        switch self {
        case .normal: return "Caption above photos"
        case .story:  return "Photos first, caption below"
        }
    }
}

enum FontTheme: String, CaseIterable, Codable {
    case classic  = "Classic"
    case serif    = "Serif"
    case rounded  = "Rounded"

    var label: String { rawValue }
    var subtitle: String {
        switch self {
        case .classic: return "Clean & modern"
        case .serif:   return "Editorial & print"
        case .rounded: return "Friendly & soft"
        }
    }
}

enum PhotoShape: String, CaseIterable, Codable {
    case rounded   = "Rounded"
    case squircle  = "Squircle"
    case circle    = "Circle"
    case rectangle = "Rectangle"
    case arch      = "Arch"
    case diamond   = "Diamond"
    case hexagon   = "Hexagon"

    var label: String { rawValue }
    var subtitle: String {
        switch self {
        case .rounded:   return "Light corners"
        case .squircle:  return "Smooth corners"
        case .circle:    return "Circular crop"
        case .rectangle: return "Sharp edges"
        case .arch:      return "Dome top"
        case .diamond:   return "Angular gem"
        case .hexagon:   return "Honeycomb"
        }
    }

    func next() -> PhotoShape {
        let all = PhotoShape.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Per-position photo shapes for the recap PDF photo rows.
/// - `leftShape`   — left column when two photos share a row
/// - `rightShape`  — right column when two photos share a row
/// - `singleShape` — one photo spanning the full card width
struct PDFPhotoShapeOptions: Codable, Equatable {
    var leftShape:   PhotoShape = .rounded
    var rightShape:  PhotoShape = .rounded
    var singleShape: PhotoShape = .rounded
}

struct PDFExportOptions: Codable, Equatable {
    var fontTheme: FontTheme = .classic
    /// Default to dark story / PDF chrome; users can switch to light in export settings.
    var colorStyle: BlogColor = .black
    var photoShapeOptions: PDFPhotoShapeOptions = PDFPhotoShapeOptions()
}

extension PDFExportOptions {
    var primaryTextColor: UIColor {
        colorStyle == .black ? .white : .black
    }
    var secondaryTextColor: UIColor {
        colorStyle == .black ? UIColor(white: 0.72, alpha: 1) : .darkGray
    }
    var cardBackgroundColor: UIColor {
        colorStyle == .black ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.92, alpha: 1)
    }
    var pageBackgroundColor: UIColor {
        colorStyle == .black ? .black : .white
    }
}

@MainActor
class PDFExportService {

    enum ExportError: Error, LocalizedError {
        case failedToRender
        case photosAccessDenied

        var errorDescription: String? {
            switch self {
            case .failedToRender: return "Failed to generate the PDF."
            case .photosAccessDenied: return "Photo access is required to generate the PDF."
            }
        }
    }

    // MARK: - Page Constants (US Letter: 8.5 x 11 in @ 72 dpi)

    static let pageW: CGFloat = 612
    static let pageH: CGFloat = 792
    static let margin: CGFloat = 36
    static let contentW: CGFloat = 540 // pageW - margin*2

    // Card styling (light gray on white paper ≈ app's Color(white: 0.12) on black)
    static let cardBg = UIColor(white: 0.92, alpha: 1.0)
    static let cardRadius: CGFloat = 12
    nonisolated static let cardPadding: CGFloat = 16

    // Photo grid — sized to fit INSIDE the card (not full contentW)
    // Card interior = contentW - cardPadding*2 = 508
    static let cardInteriorW: CGFloat = contentW - cardPadding * 2 // 508
    static let photoGap: CGFloat = 10 // app's HStack spacing between photos
    /// Half-column width when two photos sit in one row (also the square row height).
    static let photoSize: CGFloat = (cardInteriorW - photoGap) / 2 // ~249pt per photo
    /// Never place more than this many photos on a single PDF page within one place card.
    private static let maxPhotosPerPDFPage = 2

    // MARK: - Font Helper

    static func font(for theme: FontTheme, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch theme {
        case .classic:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            // Map common weights to Georgia variants (bold / regular)
            let isBold = (weight == .bold || weight == .semibold || weight == .heavy || weight == .black)
            let name = isBold ? "Georgia-Bold" : "Georgia"
            return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        case .rounded:
            // SF Rounded via font descriptor
            let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
            if let desc = baseFont.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
            return baseFont
        }
    }

    // MARK: - Public Entry Point

    static func generatePDF(from draft: RecapBlogDetail, options: PDFExportOptions = PDFExportOptions()) async throws -> URL {
        let assets = await preloadAssets(from: draft)

        let safeTitle = draft.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        // Include blog id so two trips with the same title never overwrite each other (fixes wrong PDF when sharing).
        let url = URL.documentsDirectory.appendingPathComponent("\(safeTitle)_\(draft.id.uuidString)_Blog.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Preload the app logo once
        let appLogo = UIImage(named: "PDFLogo") ?? UIImage(named: "SplashIcon") ?? UIImage(named: "Blogo")

        try renderer.writePDF(to: url) { pdfContext in
            var pen = Pen(ctx: pdfContext, margin: margin, pageW: pageW, pageH: pageH,
                          logo: appLogo, backgroundColor: options.pageBackgroundColor)

            // ── Cover Page ──────────────────────────────────────────
            pen.newPage()

            let coverH = contentW * 1.1
            let coverTopY = pen.y
            if let cover = assets.coverImage {
                pen.drawImageFill(cover, width: contentW, height: coverH, cornerRadius: 16)
            } else {
                // Fallback gray rectangle if no cover
                if let gc = UIGraphicsGetCurrentContext() {
                    gc.saveGState()
                    let rect = CGRect(x: margin, y: pen.y, width: contentW, height: coverH)
                    UIBezierPath(roundedRect: rect, cornerRadius: 16).addClip()
                    gc.setFillColor(UIColor(white: 0.9, alpha: 1.0).cgColor)
                    gc.fill(rect)
                    gc.restoreGState()
                }
                pen.y += coverH
            }

            let coverRect = CGRect(x: margin, y: coverTopY, width: contentW, height: coverH)
            Self.drawPDFTopEdgeGradientOverlay(in: coverRect, maxHeight: min(112, coverH * 0.42))

            // Title, duration, stats over the cover (top-left) with subtle shadow for legibility
            let placeCount = draft.days.flatMap(\.placeStops).count
            let durationStr = Self.durationText(draft)
            let statsStr = "\(placeCount) place\(placeCount == 1 ? "" : "s")"

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 5
            shadow.shadowOffset = CGSize(width: 0, height: 1.5)

            let titleFont = Self.font(for: options.fontTheme, size: 28, weight: .bold)
            let subFont = Self.font(for: options.fontTheme, size: 15, weight: .medium)

            let leftStyle = NSMutableParagraphStyle()
            leftStyle.alignment = .left

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .shadow: shadow,
                .paragraphStyle: leftStyle
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .shadow: shadow,
                .paragraphStyle: leftStyle
            ]

            let textInset: CGFloat = 20
            let textWidth = contentW - textInset * 2

            let titleH = draft.title.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrs, context: nil
            ).height
            let durationH = durationStr.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            ).height
            let statsH = statsStr.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            ).height

            var textY = coverTopY + textInset

            draft.title.draw(
                with: CGRect(x: margin + textInset, y: textY, width: textWidth, height: titleH),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrs, context: nil
            )
            textY += titleH + 4

            durationStr.draw(
                with: CGRect(x: margin + textInset, y: textY, width: textWidth, height: durationH),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )
            textY += durationH + 2

            statsStr.draw(
                with: CGRect(x: margin + textInset, y: textY, width: textWidth, height: statsH),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )

            pen.skip(12)

            // ── Day Sections — each day starts on a fresh page ─────────
            for (dayIndex, day) in draft.days.enumerated() {
                let dayNumber = dayIndex + 1
                // Always start a new page for each day
                pen.newPage()
                pen.drawLogoTopRight(size: 24, cornerRadius: 6)

                let hasMap = assets.maps[day.id] != nil

                // When there is no map, keep a conventional day header above the body text.
                if !hasMap {
                    let dayLine = "DAY \(dayNumber)"
                    pen.drawLeft(dayLine,
                                 font: Self.font(for: options.fontTheme, size: 11, weight: .semibold),
                                 color: options.primaryTextColor)
                    pen.skip(2)
                    pen.drawLeft(day.shortDateText,
                                 font: Self.font(for: options.fontTheme, size: 20, weight: .bold), color: options.primaryTextColor)
                }

                // Day caption — on the page only when there is no map; with a map it’s overlaid on the tile bottom.
                if !hasMap {
                    if let caption = day.dayCaption,
                       !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pen.skip(4)
                        pen.drawLeft(caption,
                                     font: Self.font(for: options.fontTheme, size: 15),
                                     color: options.secondaryTextColor)
                        pen.skip(8)
                    } else {
                        pen.skip(8)
                    }
                } else {
                    pen.skip(8)
                }

                // Map snapshot — day label + date overlaid at top-left; day story at bottom (scrim + opacity)
                if let mapImg = assets.maps[day.id] {
                    let mapH = min(contentW * (mapImg.size.height / mapImg.size.width), 280)
                    let mapOriginY = pen.y
                    pen.drawImageFit(mapImg, width: contentW, height: mapH, cornerRadius: 12)
                    let mapFrame = CGRect(x: margin, y: mapOriginY, width: contentW, height: mapH)
                    Self.drawPDFMapDayHeaderOverlay(
                        mapFrame: mapFrame,
                        dayNumber: dayNumber,
                        dateText: day.shortDateText,
                        fontTheme: options.fontTheme
                    )
                    if let cap = day.dayCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                        Self.drawPDFMapDayStoryBottomOverlay(
                            mapFrame: mapFrame,
                            caption: cap,
                            fontTheme: options.fontTheme
                        )
                    }
                    pen.skip(8)
                }

                // Place stops — each in a card (app: VStack spacing 16 between cards)
                for (i, stop) in day.placeStops.enumerated() {
                    let isFirst = (i == 0)
                    let isLast = (i == day.placeStops.count - 1)
                    let badgeColor: UIColor = isFirst ? .systemGreen : (isLast ? .systemOrange : .systemBlue)

                    drawPlaceStopCard(
                        pen: &pen,
                        stop: stop,
                        number: i + 1,
                        badgeColor: badgeColor,
                        photos: assets.photos,
                        options: options
                    )
                    pen.skip(24) // gap between cards
                }
            }
        }

        return url
    }

    // MARK: - Photo row layout (1 full-width or up to 2 half-width; max 2 photos per page)

    private enum PDFPhotoRowLayout {
        case single(Int)
        case pair(Int, Int)

        var photoCount: Int {
            switch self {
            case .single: return 1
            case .pair: return 2
            }
        }
    }

    /// Caps caption height the same way drawing does (two lines max in practice).
    private static func pdfCaptionDisplayHeight(_ caption: String?, font: UIFont, width: CGFloat) -> CGFloat {
        guard let c = caption, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return min(estimateTextHeight(c, font: font, width: width), 32)
    }

    /// Long place stories get more vertical breathing room: prefer one photo per row at full width.
    private static func pdfStoryIsLongForPairing(_ story: String?, bodyFont: UIFont, cardContentW: CGFloat) -> Bool {
        guard let s = story?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return false }
        return estimateTextHeight(s, font: bodyFont, width: cardContentW) > 88
    }

    /// Builds rows of either one full-width photo or two side-by-side, from caption length and story size.
    private static func buildPDFPhotoRows(
        photosWithImages: [(RecapPhoto, UIImage)],
        overallStory: String?,
        bodyFont: UIFont,
        captionFont: UIFont,
        cardContentW: CGFloat,
        photoGap: CGFloat
    ) -> [PDFPhotoRowLayout] {
        let halfW = (cardContentW - photoGap) / 2
        let storyLong = pdfStoryIsLongForPairing(overallStory, bodyFont: bodyFont, cardContentW: cardContentW)
        var rows: [PDFPhotoRowLayout] = []
        var i = 0
        let n = photosWithImages.count
        while i < n {
            if storyLong || i + 1 >= n {
                rows.append(.single(i))
                i += 1
                continue
            }
            let h0 = pdfCaptionDisplayHeight(photosWithImages[i].0.caption, font: captionFont, width: halfW)
            let h1 = pdfCaptionDisplayHeight(photosWithImages[i + 1].0.caption, font: captionFont, width: halfW)
            // Pair when both captions stay short in a half column; otherwise give each more width.
            if max(h0, h1) <= 30 {
                rows.append(.pair(i, i + 1))
                i += 2
            } else {
                rows.append(.single(i))
                i += 1
            }
        }
        return rows
    }

    private static func pdfHeightOfPhotoRow(
        _ row: PDFPhotoRowLayout,
        photosWithImages: [(RecapPhoto, UIImage)],
        captionFont: UIFont,
        cardContentW: CGFloat,
        photoSize: CGFloat
    ) -> CGFloat {
        switch row {
        case .single(let idx):
            let h = pdfCaptionDisplayHeight(photosWithImages[idx].0.caption, font: captionFont, width: cardContentW)
            return photoSize + (h > 0 ? 3 + h : 0)
        case .pair(let a, let b):
            let h0 = pdfCaptionDisplayHeight(photosWithImages[a].0.caption, font: captionFont, width: photoSize)
            let h1 = pdfCaptionDisplayHeight(photosWithImages[b].0.caption, font: captionFont, width: photoSize)
            let b0 = h0 > 0 ? 3 + h0 : 0
            let b1 = h1 > 0 ? 3 + h1 : 0
            return photoSize + max(b0, b1)
        }
    }

    // MARK: - Place Stop Card Drawing

    private static func drawPlaceStopCard(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        photos: [UUID: UIImage],
        options: PDFExportOptions
    ) {
        let includedPhotos = stop.photos.filter(\.isIncluded)
        let photosWithImages = includedPhotos.compactMap { p -> (RecapPhoto, UIImage)? in
            guard let img = photos[p.id] else { return nil }
            return (p, img)
        }

        let badgeSize: CGFloat = 28
        let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty
        let hasStory = !(stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let cardLeft = pen.margin + cardPadding
        let cardContentW = cardInteriorW
        let titleW = cardContentW - badgeSize - 12
        let titleFont = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
        let subFont12 = Self.font(for: options.fontTheme, size: 12)
        let bodyFont15 = Self.font(for: options.fontTheme, size: 15)
        let captionFont = Self.font(for: options.fontTheme, size: 12)

        let photoRows = buildPDFPhotoRows(
            photosWithImages: photosWithImages,
            overallStory: stop.overallStory,
            bodyFont: bodyFont15,
            captionFont: captionFont,
            cardContentW: cardContentW,
            photoGap: photoGap
        )

        // ── Pre-compute card height for background and cohesion ──
        let estTitleH = max(badgeSize, estimateTextHeight(stop.placeTitle, font: titleFont, width: titleW))
        var estContentH: CGFloat = estTitleH
        if hasSubtitle, let sub = stop.placeSubtitle {
            estContentH += 2 + estimateTextHeight(sub, font: subFont12, width: titleW)
        }
        if hasStory, let story = stop.overallStory {
            estContentH += 8 + estimateTextHeight(story, font: bodyFont15, width: cardContentW)
        }
        if !photosWithImages.isEmpty {
            estContentH += 8
            for row in photoRows {
                estContentH += pdfHeightOfPhotoRow(
                    row,
                    photosWithImages: photosWithImages,
                    captionFont: captionFont,
                    cardContentW: cardContentW,
                    photoSize: photoSize
                ) + 10
            }
        }
        let totalCardH = cardPadding + estContentH + cardPadding

        // Cohesion: keep header + first photo row on the same page
        let firstPhotoH: CGFloat = {
            guard !photosWithImages.isEmpty, let first = photoRows.first else { return 0 }
            return 8 + pdfHeightOfPhotoRow(
                first,
                photosWithImages: photosWithImages,
                captionFont: captionFont,
                cardContentW: cardContentW,
                photoSize: photoSize
            )
        }()
        let storySnippetH: CGFloat = hasStory
            ? min(8 + estimateTextHeight(stop.overallStory ?? "", font: bodyFont15, width: cardContentW), 68)
            : 0
        let cohesionH = cardPadding + estTitleH
            + (hasSubtitle ? 17 : 0)
            + storySnippetH + firstPhotoH + cardPadding
        let maxCohesion = (pen.pageH - pen.margin * 2) * 0.6
        pen.ensureRoom(min(cohesionH, maxCohesion))

        // ── Draw card background ──
        let bgH = min(totalCardH, pen.maxY - pen.y)
        if let gc = UIGraphicsGetCurrentContext() {
            gc.saveGState()
            let bgRect = CGRect(x: pen.margin, y: pen.y, width: contentW, height: bgH)
            gc.setFillColor(options.cardBackgroundColor.cgColor)
            UIBezierPath(roundedRect: bgRect, cornerRadius: cardRadius).addClip()
            gc.fill(bgRect)
            gc.restoreGState()
        }

        pen.skip(cardPadding) // top padding inside card

        // ── Badge + Title (app: HStack spacing 12) ──
        pen.drawBadge(number: number, color: badgeColor, size: badgeSize)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: options.primaryTextColor
        ]
        
        let urlToOpen = StoryPlaceGoogleSearch.url(placeName: stop.placeTitle, placeSubtitle: stop.placeSubtitle)
        
        let attrTitle = NSMutableAttributedString(string: stop.placeTitle, attributes: titleAttrs)
        
        let linkIconBase64 = "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"
        var customIcon: UIImage? = nil
        if let data = Data(base64Encoded: linkIconBase64) {
            customIcon = UIImage(data: data)
        }
        
        if urlToOpen != nil, let linkIcon = customIcon {
            let attachment = NSTextAttachment()
            attachment.image = linkIcon
            let iconSize: CGFloat = 13
            let yOffset = (titleFont.capHeight - iconSize) / 2
            attachment.bounds = CGRect(x: 0, y: yOffset, width: iconSize, height: iconSize)
            
            let noUnderlineAttrs: [NSAttributedString.Key: Any] = [.underlineStyle: 0]
            
            let spaceStr = NSAttributedString(string: " ", attributes: noUnderlineAttrs)
            let iconStr = NSMutableAttributedString(attachment: attachment)
            iconStr.addAttributes(noUnderlineAttrs, range: NSRange(location: 0, length: iconStr.length))
            
            attrTitle.append(spaceStr)
            attrTitle.append(iconStr)
        }

        let titleRectBounds = attrTitle.boundingRect(
            with: CGSize(width: titleW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        
        let drawRect = CGRect(x: cardLeft + badgeSize + 12, y: pen.y + (badgeSize - titleRectBounds.height) / 2,
                              width: titleW, height: titleRectBounds.height)
                              
        attrTitle.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        
        if let url = urlToOpen {
            // PDF links (annotations) strictly use the unflipped PDF coordinate space (bottom-left origin).
            let pdfRect = CGRect(x: drawRect.minX,
                                 y: pen.pageH - drawRect.maxY,
                                 width: drawRect.width,
                                 height: drawRect.height)
            pen.ctx.setURL(url, for: pdfRect)
        }

        pen.y += max(badgeSize, titleRectBounds.height)

        // ── Subtitle (app: .caption, .secondary) ──
        if hasSubtitle, let subtitle = stop.placeSubtitle {
            pen.skip(2)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont12,
                .foregroundColor: options.secondaryTextColor
            ]
            let subSize = subtitle.boundingRect(
                with: CGSize(width: titleW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )
            subtitle.draw(
                with: CGRect(x: cardLeft + badgeSize + 12, y: pen.y,
                             width: titleW, height: subSize.height),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )
            pen.y += subSize.height
        }

        // ── Story (app: .subheadline, padding h:16 v:8) ──
        if hasStory, let story = stop.overallStory {
            pen.skip(8)
            let storyAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont15,
                .foregroundColor: options.secondaryTextColor
            ]
            let storySize = story.boundingRect(
                with: CGSize(width: cardContentW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: storyAttrs, context: nil
            )
            story.draw(
                with: CGRect(x: cardLeft, y: pen.y,
                             width: cardContentW, height: storySize.height),
                options: [.usesLineFragmentOrigin],
                attributes: storyAttrs, context: nil
            )
            pen.y += storySize.height
        }

        // ── Photos — one full-width or two half-width per row; max 2 photos per PDF page
        if !photosWithImages.isEmpty {
            let colW = photoSize
            let colH = photoSize

            func estimatedRemainingPhotoHeights(from startIdx: Int) -> CGFloat {
                var h: CGFloat = 0
                for j in startIdx..<photoRows.count {
                    h += pdfHeightOfPhotoRow(
                        photoRows[j],
                        photosWithImages: photosWithImages,
                        captionFont: captionFont,
                        cardContentW: cardContentW,
                        photoSize: photoSize
                    ) + 10
                }
                return h + cardPadding + 8
            }

            let pageBeforePhotos = pen.pageNumber
            pen.skip(8) // app: photo strip top padding 8
            if pen.pageNumber != pageBeforePhotos {
                let estRemaining = estimatedRemainingPhotoHeights(from: 0)
                let contH = min(estRemaining, pen.maxY - pen.y)
                if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                    gc.saveGState()
                    gc.setFillColor(options.cardBackgroundColor.cgColor)
                    gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                    gc.restoreGState()
                }
            }

            var photosOnPage = 0
            var rowIndex = 0
            for row in photoRows {
                let need = row.photoCount
                if photosOnPage + need > maxPhotosPerPDFPage {
                    pen.newPage()
                    photosOnPage = 0
                    let estRemaining = estimatedRemainingPhotoHeights(from: rowIndex)
                    let contH = min(estRemaining, pen.maxY - pen.y)
                    if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                        gc.saveGState()
                        gc.setFillColor(options.cardBackgroundColor.cgColor)
                        gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                        gc.restoreGState()
                    }
                }

                let rowH = pdfHeightOfPhotoRow(
                    row,
                    photosWithImages: photosWithImages,
                    captionFont: captionFont,
                    cardContentW: cardContentW,
                    photoSize: photoSize
                )
                let pageBeforeEnsure = pen.pageNumber
                pen.ensureRoom(rowH + 4)

                if pen.pageNumber != pageBeforeEnsure {
                    let estRemaining = estimatedRemainingPhotoHeights(from: rowIndex)
                    let contH = min(estRemaining, pen.maxY - pen.y)
                    if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                        gc.saveGState()
                        gc.setFillColor(options.cardBackgroundColor.cgColor)
                        gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                        gc.restoreGState()
                    }
                    photosOnPage = 0
                }

                let captionColor = options.secondaryTextColor

                switch row {
                case .single(let idx):
                    let (photo, img) = photosWithImages[idx]
                    let rect = CGRect(x: cardLeft, y: pen.y, width: cardContentW, height: colH)
                    drawPhoto(img, in: rect, shape: options.photoShapeOptions.singleShape)
                    pen.y += colH

                    var captionH: CGFloat = 0
                    if let cap = photo.caption,
                       !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pen.skip(3)
                        let capAttrs: [NSAttributedString.Key: Any] = [
                            .font: captionFont, .foregroundColor: captionColor
                        ]
                        let capSize = cap.boundingRect(
                            with: CGSize(width: cardContentW, height: 32),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        let h = min(capSize.height, 32)
                        cap.draw(
                            with: CGRect(x: cardLeft, y: pen.y, width: cardContentW, height: h),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        captionH = h + 3
                    }
                    pen.y += captionH

                case .pair(let a, let b):
                    let (leftPhoto, leftImg) = photosWithImages[a]
                    let (_, rightImg) = photosWithImages[b]
                    let leftRect = CGRect(x: cardLeft, y: pen.y, width: colW, height: colH)
                    let rightRect = CGRect(x: cardLeft + colW + photoGap, y: pen.y,
                                           width: colW, height: colH)
                    drawPhoto(leftImg, in: leftRect, shape: options.photoShapeOptions.leftShape)
                    drawPhoto(rightImg, in: rightRect, shape: options.photoShapeOptions.rightShape)
                    pen.y += colH

                    var captionH: CGFloat = 0
                    if let cap = leftPhoto.caption,
                       !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pen.skip(3)
                        let capAttrs: [NSAttributedString.Key: Any] = [
                            .font: captionFont, .foregroundColor: captionColor
                        ]
                        let capSize = cap.boundingRect(
                            with: CGSize(width: colW, height: 32),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        let h = min(capSize.height, 32)
                        cap.draw(
                            with: CGRect(x: cardLeft, y: pen.y, width: colW, height: h),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        captionH = max(captionH, h + 3)
                    }

                    let (rightPhoto, _) = photosWithImages[b]
                    if let cap = rightPhoto.caption,
                       !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let capAttrs: [NSAttributedString.Key: Any] = [
                            .font: captionFont, .foregroundColor: captionColor
                        ]
                        let capSize = cap.boundingRect(
                            with: CGSize(width: colW, height: 32),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        let h = min(capSize.height, 32)
                        cap.draw(
                            with: CGRect(x: cardLeft + colW + photoGap, y: pen.y,
                                         width: colW, height: h),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: capAttrs, context: nil
                        )
                        captionH = max(captionH, h + 3)
                    }

                    pen.y += captionH
                }

                pen.skip(10)
                photosOnPage += need
                rowIndex += 1
            }
        }

        pen.skip(8)

        // Light separator line between place stops
        if let gc = UIGraphicsGetCurrentContext() {
            gc.saveGState()
            gc.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
            gc.setLineWidth(0.5)
            gc.move(to: CGPoint(x: pen.margin + 16, y: pen.y))
            gc.addLine(to: CGPoint(x: pen.margin + contentW - 16, y: pen.y))
            gc.strokePath()
            gc.restoreGState()
        }
    }

    // MARK: - Photo Drawing

    private static func drawPhoto(_ image: UIImage, in rect: CGRect, shape: PhotoShape) {
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        gc.saveGState()
        switch shape {
        case .rounded:
            UIBezierPath(roundedRect: rect, cornerRadius: 8).addClip()

        case .squircle:
            // Large continuous-feel corner radius (~25% of the shorter side)
            let cr = min(rect.width, rect.height) * 0.25
            UIBezierPath(roundedRect: rect, cornerRadius: cr).addClip()

        case .circle:
            UIBezierPath(ovalIn: rect).addClip()

        case .rectangle:
            UIBezierPath(rect: rect).addClip()

        case .arch:
            // Flat bottom + semicircle top (dome)
            // In UIKit (y+ down): arc from angle π→0 clockwise passes through 270° = top of view
            let path = UIBezierPath()
            let r = rect.width / 2
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addArc(withCenter: CGPoint(x: rect.midX, y: rect.midY),
                        radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.close()
            path.addClip()

        case .diamond:
            // Rotated 45° square — vertices at the four edge midpoints
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.close()
            path.addClip()

        case .hexagon:
            // Pointy-top hexagon inscribed in the bounding rect
            let path = UIBezierPath()
            let cx = rect.midX, cy = rect.midY
            let r = min(rect.width, rect.height) / 2
            for i in 0..<6 {
                let angle = CGFloat(-Double.pi / 2) + CGFloat(i) * CGFloat(Double.pi / 3)
                let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.close()
            path.addClip()
        }
        // Scale-to-fill (crop to square) — matching app's .fill + .clipped()
        let imgAspect = image.size.width / image.size.height
        let drawRect: CGRect
        if imgAspect > 1 {
            let w = rect.height * imgAspect
            drawRect = CGRect(x: rect.minX - (w - rect.width) / 2, y: rect.minY,
                              width: w, height: rect.height)
        } else {
            let h = rect.width / imgAspect
            drawRect = CGRect(x: rect.minX, y: rect.minY - (h - rect.height) / 2,
                              width: rect.width, height: h)
        }
        image.draw(in: drawRect)
        gc.restoreGState()
    }

    // MARK: - Cover / map overlays (legibility on photos & map tiles)

    /// Top-down gradient so white header text reads on bright imagery.
    private static func drawPDFTopEdgeGradientOverlay(in rect: CGRect, maxHeight: CGFloat) {
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        let h = min(maxHeight, rect.height)
        guard h > 1 else { return }
        let strip = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
        gc.saveGState()
        gc.clip(to: strip)
        let colors = [
            UIColor.black.withAlphaComponent(0.38).cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0, 1]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locs) else {
            gc.restoreGState()
            return
        }
        gc.drawLinearGradient(
            gradient,
            start: CGPoint(x: strip.midX, y: strip.minY),
            end: CGPoint(x: strip.midX, y: strip.maxY),
            options: []
        )
        gc.restoreGState()
    }

    /// Bottom-up gradient so day story text reads on the map (map remains visible through the fade).
    private static func drawPDFBottomEdgeGradientOverlay(in rect: CGRect, maxHeight: CGFloat) {
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        let h = min(maxHeight, rect.height)
        guard h > 1 else { return }
        let strip = CGRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)
        gc.saveGState()
        gc.clip(to: strip)
        let colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.38).cgColor,
            UIColor.black.withAlphaComponent(0.62).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0, 0.5, 1]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locs) else {
            gc.restoreGState()
            return
        }
        gc.drawLinearGradient(
            gradient,
            start: CGPoint(x: strip.midX, y: strip.minY),
            end: CGPoint(x: strip.midX, y: strip.maxY),
            options: []
        )
        gc.restoreGState()
    }

    private static func drawPDFMapDayStoryBottomOverlay(
        mapFrame: CGRect,
        caption: String,
        fontTheme: FontTheme
    ) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let scrimH = min(200, max(96, mapFrame.height * 0.48))
        drawPDFBottomEdgeGradientOverlay(in: mapFrame, maxHeight: scrimH)

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1)

        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.lineBreakMode = .byWordWrapping

        let storyFont = StoryFontHelper.uiItalicFont(for: fontTheme, size: StoryPageLayout.dayStoryCaptionFontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: storyFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .paragraphStyle: para,
            .shadow: shadow
        ]

        let padX: CGFloat = 14
        let padBottom: CGFloat = 12
        let padTopInScrim: CGFloat = 16
        let textW = mapFrame.width - padX * 2
        let maxTextH = max(24, scrimH - padTopInScrim - padBottom)

        let ns = trimmed as NSString
        let natural = ns.boundingRect(
            with: CGSize(width: textW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        ).height

        let drawH = min(ceil(natural), maxTextH)
        let textY = mapFrame.maxY - padBottom - drawH
        let textRect = CGRect(x: mapFrame.minX + padX, y: textY, width: textW, height: drawH)

        if natural > maxTextH + 0.5 {
            let truncPara = NSMutableParagraphStyle()
            truncPara.setParagraphStyle(para)
            truncPara.lineBreakMode = .byTruncatingTail
            var truncAttrs = attrs
            truncAttrs[.paragraphStyle] = truncPara
            ns.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                attributes: truncAttrs,
                context: nil
            )
        } else {
            ns.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
        }
    }

    private static func drawPDFMapDayHeaderOverlay(
        mapFrame: CGRect,
        dayNumber: Int,
        dateText: String,
        fontTheme: FontTheme
    ) {
        let scrimH = min(140, mapFrame.height * 0.45)
        drawPDFTopEdgeGradientOverlay(
            in: CGRect(x: mapFrame.minX, y: mapFrame.minY, width: mapFrame.width, height: scrimH),
            maxHeight: scrimH
        )

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = CGSize(width: 0, height: 1)

        let dayLabel = "DAY \(dayNumber)"
        let dayFont = font(for: fontTheme, size: 44, weight: .bold)
        let dateFont = font(for: fontTheme, size: 18, weight: .bold)

        let left = NSMutableParagraphStyle()
        left.alignment = .left

        let dayAttrs: [NSAttributedString.Key: Any] = [
            .font: dayFont,
            .foregroundColor: UIColor.white,
            .shadow: shadow,
            .paragraphStyle: left,
            .kern: 1.2
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: UIColor.white,
            .shadow: shadow,
            .paragraphStyle: left
        ]

        let padX: CGFloat = 14
        let padY: CGFloat = 20
        let textWidth = mapFrame.width - padX * 2

        let dayH = dayLabel.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: dayAttrs, context: nil
        ).height
        let dateH = dateText.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: dateAttrs, context: nil
        ).height

        var textY = mapFrame.minY + padY
        dayLabel.draw(
            with: CGRect(x: mapFrame.minX + padX, y: textY, width: textWidth, height: dayH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: dayAttrs, context: nil
        )
        textY += dayH + 3
        dateText.draw(
            with: CGRect(x: mapFrame.minX + padX, y: textY, width: textWidth, height: dateH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: dateAttrs, context: nil
        )
    }

    // MARK: - Height Estimation

    private static func estimateTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).height
    }

    // MARK: - Asset Preloading

    private struct PreloadedAssets {
        var coverImage: UIImage?
        var photos: [UUID: UIImage] = [:]
        var maps: [UUID: UIImage] = [:]
    }

    private static func preloadAssets(from draft: RecapBlogDetail) async -> PreloadedAssets {
        var result = PreloadedAssets()

        for day in draft.days {
            if let img = await MapSnapshotHelper.generateSnapshot(for: day.placeStops) {
                result.maps[day.id] = img
            }
        }

        let allIncluded = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        func normalizedLocalID(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        let coverID = normalizedLocalID(draft.selectedCoverPhotoIdentifier)
            ?? allIncluded.compactMap { normalizedLocalID($0.localIdentifier) }.first

        var idsToFetch = Set<String>()
        if let c = coverID { idsToFetch.insert(c) }
        for p in allIncluded {
            if let id = normalizedLocalID(p.localIdentifier) { idsToFetch.insert(id) }
        }
        guard !idsToFetch.isEmpty else { return result }

        // Split identifiers: app-captures load directly; PHAsset ids go through Photos.
        let appCaptureIds = idsToFetch.filter { $0.hasPrefix(AppCapturePhotoService.prefix) }
        let phAssetIds = idsToFetch.subtracting(appCaptureIds)

        // Load app-capture images
        for identifier in appCaptureIds {
            let image = AppCapturePhotoService.shared.loadImage(identifier: identifier)
            guard let image else { continue }
            if identifier == coverID { result.coverImage = image }
            for p in allIncluded where normalizedLocalID(p.localIdentifier) == identifier {
                result.photos[p.id] = image
            }
        }

        guard !phAssetIds.isEmpty else {
            if result.coverImage == nil, let first = allIncluded.first {
                result.coverImage = result.photos[first.id]
            }
            return result
        }

        // Use the same loading path as the UI (`ImageLoader`): retries when the library is briefly
        // empty, and accepts the image callback Photos actually delivers. The previous PDF-only
        // `PHImageManager` path used `.exact` resize and ignored degraded previews, which could
        // yield no image (or never resume) while thumbnails still appeared in the editor.
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for localId in phAssetIds {
                group.addTask {
                    let image = await ImageLoader.shared.loadImage(
                        assetIdentifier: localId,
                        targetSize: CGSize(width: 1200, height: 1200)
                    )
                    return (localId, image)
                }
            }

            for await (id, image) in group {
                guard let image else { continue }
                if id == coverID { result.coverImage = image }
                for p in allIncluded where normalizedLocalID(p.localIdentifier) == id {
                    result.photos[p.id] = image
                }
            }
        }

        if result.coverImage == nil, let first = allIncluded.first {
            result.coverImage = result.photos[first.id]
        }

        // Fetch cloud photos for any included photos that have no usable on-device asset id.
        let cloudPhotos = allIncluded.filter { normalizedLocalID($0.localIdentifier) == nil && $0.cloudURL != nil }
        if !cloudPhotos.isEmpty {
            await withTaskGroup(of: (UUID, UIImage?).self) { group in
                for photo in cloudPhotos {
                    guard let permanentURL = photo.cloudURL else { continue }
                    group.addTask {
                        do {
                            let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: permanentURL)
                            let (data, _) = try await URLSession.shared.data(from: signedURL)
                            return (photo.id, UIImage(data: data))
                        } catch {
                            return (photo.id, nil)
                        }
                    }
                }
                for await (photoId, image) in group {
                    guard let image else { continue }
                    result.photos[photoId] = image
                    if result.coverImage == nil {
                        result.coverImage = image
                    }
                }
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func durationText(_ draft: RecapBlogDetail) -> String {
        guard let first = draft.days.first?.date,
              let last = draft.days.last?.date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .year) {
            let yf = DateFormatter()
            yf.dateFormat = "yyyy"
            return "\(f.string(from: first)) – \(f.string(from: last)), \(yf.string(from: last))"
        }
        f.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

// MARK: - Pen (PDF Drawing Cursor)

private struct Pen {
    let ctx: UIGraphicsPDFRendererContext
    let margin: CGFloat
    let pageW: CGFloat
    let pageH: CGFloat
    let logo: UIImage?
    var backgroundColor: UIColor = .white
    var y: CGFloat = 0
    var pageNumber: Int = 0

    var contentW: CGFloat { pageW - margin * 2 }
    var maxY: CGFloat { pageH - margin }

    mutating func newPage() {
        ctx.beginPage()
        if backgroundColor != .white {
            if let gc = UIGraphicsGetCurrentContext() {
                gc.saveGState()
                gc.setFillColor(backgroundColor.cgColor)
                gc.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
                gc.restoreGState()
            }
        }
        y = margin
        pageNumber += 1
    }

    mutating func ensureRoom(_ h: CGFloat) {
        if y + h > maxY { newPage() }
    }

    mutating func skip(_ amount: CGFloat) {
        y += amount
    }

    // MARK: Text

    mutating func drawLeft(_ text: String, font: UIFont, color: UIColor) {
        let attrs = makeAttrs(font: font, color: color, alignment: .left)
        let size = text.boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).size
        ensureRoom(size.height)
        text.draw(
            with: CGRect(x: margin, y: y, width: contentW, height: size.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        )
        y += size.height
    }

    mutating func drawCentered(_ text: String, font: UIFont, color: UIColor) {
        let attrs = makeAttrs(font: font, color: color, alignment: .center)
        let size = text.boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).size
        ensureRoom(size.height)
        text.draw(
            with: CGRect(x: margin, y: y, width: contentW, height: size.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        )
        y += size.height
    }

    // MARK: Images

    mutating func drawImageFit(_ image: UIImage, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 0) {
        ensureRoom(height)
        let frame = CGRect(x: margin, y: y, width: width, height: height)
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        gc.saveGState()
        if cornerRadius > 0 {
            UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius).addClip()
        }
        let imgAspect = image.size.width / image.size.height
        let frameAspect = width / height
        let drawRect: CGRect
        if imgAspect > frameAspect {
            let h = width / imgAspect
            drawRect = CGRect(x: frame.minX, y: frame.minY + (height - h) / 2,
                              width: width, height: h)
        } else {
            let w = height * imgAspect
            drawRect = CGRect(x: frame.minX + (width - w) / 2, y: frame.minY,
                              width: w, height: height)
        }
        image.draw(in: drawRect)
        gc.restoreGState()
        y += height
    }

    mutating func drawImageFill(_ image: UIImage, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 0) {
        ensureRoom(height)
        let frame = CGRect(x: margin, y: y, width: width, height: height)
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        gc.saveGState()
        if cornerRadius > 0 {
            UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius).addClip()
        }
        let imgAspect = image.size.width / image.size.height
        let frameAspect = width / height
        let drawRect: CGRect
        if imgAspect > frameAspect {
            let w = height * imgAspect
            drawRect = CGRect(x: frame.minX - (w - width) / 2, y: frame.minY,
                              width: w, height: height)
        } else {
            let h = width / imgAspect
            drawRect = CGRect(x: frame.minX, y: frame.minY - (h - height) / 2,
                              width: width, height: h)
        }
        image.draw(in: drawRect)
        gc.restoreGState()
        y += height
    }

    // MARK: Logo

    /// Draws `logo` (if set) at the top-right of the page with rounded corners, at the current top margin.
    mutating func drawLogoTopRight(size: CGFloat = 24, cornerRadius: CGFloat = 6) {
        guard let img = logo else { return }
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        let x = pageW - margin - size
        let rect = CGRect(x: x, y: margin, width: size, height: size)
        gc.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        let aspect = img.size.width / img.size.height
        let drawRect: CGRect
        if aspect > 1 {
            let h = size / aspect
            drawRect = CGRect(x: rect.minX, y: rect.minY + (size - h) / 2, width: size, height: h)
        } else {
            let w = size * aspect
            drawRect = CGRect(x: rect.minX + (size - w) / 2, y: rect.minY, width: w, height: size)
        }
        img.draw(in: drawRect)
        gc.restoreGState()
    }

    // MARK: Badge

    mutating func drawBadge(number: Int, color: UIColor, size: CGFloat) {
        let badgeRect = CGRect(x: margin + PDFExportService.cardPadding, y: y,
                               width: size, height: size)
        guard let gc = UIGraphicsGetCurrentContext() else { return }
        gc.saveGState()
        gc.setFillColor(color.cgColor)
        gc.fillEllipse(in: badgeRect)
        gc.restoreGState()

        let numStr = "\(number)"
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let numSize = numStr.size(withAttributes: numAttrs)
        numStr.draw(
            in: CGRect(x: badgeRect.midX - numSize.width / 2,
                       y: badgeRect.midY - numSize.height / 2,
                       width: numSize.width, height: numSize.height),
            withAttributes: numAttrs
        )
    }

    private func makeAttrs(font: UIFont, color: UIColor, alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }
}
