import UIKit
import MapKit
import Photos

// MARK: - PDF Export Options

enum BlogColor: String, CaseIterable, Codable {
    case white = "White"
    case black = "Black"

    var label: String { rawValue }
    var subtitle: String {
        switch self {
        case .white: return "Light background, dark text"
        case .black: return "Dark background, light text"
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

/// Per-position photo shapes for the 2-column PDF grid.
/// - `leftShape`   — left column in a paired row
/// - `rightShape`  — right column in a paired row
/// - `singleShape` — a photo that occupies its row alone (only 1 total, or last odd photo)
struct PDFPhotoShapeOptions: Codable, Equatable {
    var leftShape:   PhotoShape = .rounded
    var rightShape:  PhotoShape = .rounded
    var singleShape: PhotoShape = .rounded
}

struct PDFExportOptions: Codable, Equatable {
    var blogColor:         BlogColor            = .white
    var fontTheme:         FontTheme            = .classic
    var photoShapeOptions: PDFPhotoShapeOptions = PDFPhotoShapeOptions()
    var layoutMode:        PDFLayoutMode        = .normal
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

    /// Base64-encoded link icon shown beside place titles in the PDF.
    private static let linkIconBase64: String = "iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAACtWK6eAAALOklEQVR4Aeydy44kRxVAc3qFhJBgg8RDNt7ZX8GwAARfYYQQCD6C4SdAIITgC9iBZC/G/gUvLHvlx8iWJW9sybLkTY/v7a5qZ2VFZUZGxePeiDOKqMzKioy499w8VdXVj7mZ+AcBCFwkgCAX0fAABKYJQbgKILBCAEFW4PAQBBCEawACKwQKCrKyKg9BwAkBBHFSKMJsQwBB2nBnVScEEMRJoQizDQEEacOdVZ0Q8CmIE7iE6Z8AgvivIRkUJIAgBeEytX8CCOK/hmRQkACCFITL1P4JIMiihtyFwJwAgsxpsA+BBQEEWQDhLgTmBBBkToN9CCwIIMgCCHchMCeAIHMaZfeZ3SEBBHFYNEKuRwBB6rFmJYcEEMRh0Qi5HgEEqcealRwSsCLIK8LuqfTng3XNWVLe1QKMplGP7QKXMri1IL+SoLW4b8v2sXQaBEwRaCnI+0Lif9JpwxJ4ZD7zVoLcCpkXpdOGJqBvHmwDaCGIymH/qcN23YpGR3G+wVtbkGey9ED8faZ68rwuBRu51RTk5wL6x9IHap1eaj69T7ruagryWlKEnGSPQKfeh0DXEuSl0OIcs0WgzAtDmVlrkaslyL9qJcQ66QTKvDCUmTU9y31n1hJk9k1A388o+/A6Gt2gLB7o1BJkxsL3M8oskb52KUuwng0ECcaxPPiGHPiLhS6ASsbxH8lxb8sbz810P9/Nzf12OtzPu/333iStjJf6WwnlJI435d4TC12+q1kyjpQLJ288t9P9fLe299vpcD/fVr/+fHVy+s+UILwNdnoVXQ77BXnoA+mumilBeBvs9joKBd5SjlA8ScdMCZKUASdZJNCFHAoWQZQCPSeBbuRQKAiiFOi5CHQlh0IxJQhfpGtJ3PaLcniuqylB+CK9Pzk0I891PRdEM6JDIJ7AxVeO+CnuRr51d2vsBkGMFcRZOLnk+K3k/V/p5hqCmCuJm4ByyqHfbT9L3MLXLghyVhYORBAoLofGYOFrFwTRStD3EKgiRyigFq8oVQUJJc0xVwSayaGUWryiIIiSp8cQaCpHTIAlxiBICar9zZkgR/ANkX5aFfyC3CoyBLFaGTtxJcihwZ+9IXInh2aBIEqBfolAohxn07mUQ7PoRRDNhZ6XwLYcwXdRZ0G4lUMzQRClQF8S2JZDzzh7F6UHT7prOTQTBFEK9DmBODnmZ4T33cuhaSGIUqAfCRiSI+792zHwUtumgthAUAqtu3kNyaHsNt6/Vbp4mgqygUApGehDhGBMjgjmlS6epoJEYGBIeQL+5CjP5GEFBHlAMeQOcmyUHUE2AHX8MHJEFBdBIiB1OAQ5IouKIJGgigxrMyly7OCOIDtgdTAUOXYWEUF2AnM8HDkSiocgCdAcnqL/u3COv7LexY+P7Kkfguyh5XOsyvEsQ+jDyaHMEEQpdNgPKSHHAUTqBkFSydk/Dzky1AhBMkA0OAVyZCoKgmQCaWga5MhYDATJCNPAVMiRuQgIkhlow+lqydEgxUq//BHIDEECUBwe6lgOrUalX/7QpRa9mSDtnhMWBPzf3ZQjkvXvBIWrP+om8RZvzQRp95xQnGnNBTbl0GDOWJ8b83sZ90/ptAWBZoIs4uDufgJRcgSnPTVG5fhHcBwHJwTxeRGky3GarzE5ToOzcK+ZIOev8hZwuIgBOSqWqZkgp6/yFTP2vRRyVK5fM0Eq59nDcsjRoIoI0gB6wpLIkQAtxykIkoNi2TmQIwffxDkQJBFcpdOQoxLoS8sgyCUy7Y8jR/saWP0+yPDeIocBOTQEo1fircY2akcOQ5U3KoghQnVDQY66vDdXixFkcxIGZCEwuhxPhKL+gMWeLqeUbQhSlm/s7KPLEcup+jgEqY78bEHkOENi5wCCtK0FcrTlv7k6gmwiKjYAOYqhzTdxY0HyJeJsJuRwUjAEqV8o5KnPPHlFBElGl3QicopIWgaecSsM/M+L3IJBCp8cQaSzZnx9TbntBNYRYGbCnILkzXd4Y5EBt5SjpHFJMgJIZAB0OQIyGAE5M5REGQLGGaHTDkEMF5cVNqBkEIJQFDeBFmAKITECQRAtRYMrQKY5lSMBVEKgZBgqMIJCcijhBQ8kDhfbdCoKkWHIF0oiZAiDAkGQQJBXkSYIIijhBQ0LUVpKZvNTIDqBv+U3MEKrKMG9rNIKCRPWiSPqBSG44nWJxQJBxl4AGIiNiPFJkM+9Gh10G8CcBIkCF1lYRa6VDjqUmqfFnLKSHIDMBbhAGm1AAIJBVkEH4lcpfb8OGT2NUWVfIKegAAAAASUVORK5CYII="

    // MARK: - Page Constants (US Letter: 8.5 x 11 in @ 72 dpi)

    static let pageW: CGFloat = 612
    static let pageH: CGFloat = 792
    static let margin: CGFloat = 36
    static let contentW: CGFloat = 540 // pageW - margin*2

    // Card styling (light gray on white paper ≈ app's Color(white: 0.12) on black)
    static let cardBg = UIColor(white: 0.92, alpha: 1.0)
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16

    // Photo grid — sized to fit INSIDE the card (not full contentW)
    // Card interior = contentW - cardPadding*2 = 508
    static let cardInteriorW: CGFloat = contentW - cardPadding * 2 // 508
    static let photoGap: CGFloat = 10 // app's HStack spacing between photos
    static let photoSize: CGFloat = (cardInteriorW - photoGap) / 2 // ~249pt per photo

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
        let url = URL.documentsDirectory.appendingPathComponent("\(safeTitle)_Blog.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Preload the app logo once
        let appLogo = UIImage(named: "PDFLogo") ?? UIImage(named: "SplashIcon") ?? UIImage(named: "Blogo")

        // Derive palette from blogColor
        let isDark = options.blogColor == .black
        let pageBg:       UIColor = isDark ? .black                              : .white
        let cardBgColor:  UIColor = isDark ? UIColor(white: 0.15, alpha: 1.0)   : cardBg
        let primaryText:  UIColor = isDark ? .white                              : .black
        let secondaryText: UIColor = isDark ? UIColor(white: 0.65, alpha: 1.0)  : .darkGray
        let brandingText: UIColor = isDark ? UIColor(white: 0.55, alpha: 1.0)   : .darkGray
        let separatorColor: UIColor = isDark ? UIColor(white: 0.3, alpha: 1.0)  : UIColor(white: 0.85, alpha: 1.0)

        try renderer.writePDF(to: url) { pdfContext in
            var pen = Pen(ctx: pdfContext, margin: margin, pageW: pageW, pageH: pageH,
                          logo: appLogo, pageBackground: pageBg)

            // ── Cover Page ──────────────────────────────────────────
            pen.newPage()

            let coverH = contentW * 1.1
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

            // Draw title, duration, stats OVER the cover photo (bottom-center)
            let placeCount = draft.days.flatMap(\.placeStops).count
            let durationStr = Self.durationText(draft)
            let statsStr = "\(placeCount) place\(placeCount == 1 ? "" : "s")"

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.7)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = CGSize(width: 0, height: 2)

            let titleFont = Self.font(for: options.fontTheme, size: 28, weight: .bold)
            let subFont = Self.font(for: options.fontTheme, size: 15, weight: .medium)

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: UIColor.white, .shadow: shadow
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont, .foregroundColor: UIColor.white.withAlphaComponent(0.92), .shadow: shadow
            ]

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center
            var titleAttrsC = titleAttrs
            titleAttrsC[.paragraphStyle] = centerStyle
            var subAttrsC = subAttrs
            subAttrsC[.paragraphStyle] = centerStyle

            // Measure text heights
            let titleH = draft.title.boundingRect(
                with: CGSize(width: contentW - 32, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrsC, context: nil
            ).height
            let durationH = durationStr.boundingRect(
                with: CGSize(width: contentW - 32, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrsC, context: nil
            ).height
            let statsH = statsStr.boundingRect(
                with: CGSize(width: contentW - 32, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrsC, context: nil
            ).height

            // Position text block 24pt from bottom of cover, centered
            let textBlockH = titleH + 4 + durationH + 2 + statsH
            var textY = pen.y - 24 - textBlockH

            draft.title.draw(
                with: CGRect(x: margin + 16, y: textY, width: contentW - 32, height: titleH),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrsC, context: nil
            )
            textY += titleH + 4

            durationStr.draw(
                with: CGRect(x: margin + 16, y: textY, width: contentW - 32, height: durationH),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrsC, context: nil
            )
            textY += durationH + 2

            statsStr.draw(
                with: CGRect(x: margin + 16, y: textY, width: contentW - 32, height: statsH),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrsC, context: nil
            )

            pen.skip(12)

            // App icon + "Created with Bloggo" — left-aligned under cover
            if let appIcon = appLogo {
                let iconSize: CGFloat = 22
                let createdText = "Created with Bloggo"
                let createdFont = Self.font(for: options.fontTheme, size: 13, weight: .medium)
                let createdAttrs: [NSAttributedString.Key: Any] = [
                    .font: createdFont,
                    .foregroundColor: brandingText
                ]

                let iconRect = CGRect(x: margin, y: pen.y, width: iconSize, height: iconSize)
                if let gc = UIGraphicsGetCurrentContext() {
                    gc.saveGState()
                    UIBezierPath(roundedRect: iconRect, cornerRadius: 5).addClip()
                    appIcon.draw(in: iconRect)
                    gc.restoreGState()
                }

                let textSize = createdText.size(withAttributes: createdAttrs)
                createdText.draw(
                    at: CGPoint(x: margin + iconSize + 6,
                                y: pen.y + (iconSize - textSize.height) / 2),
                    withAttributes: createdAttrs
                )
                pen.y += iconSize
            }

            // ── Table of Contents Page ───────────────────────────────
            pen.newPage()

            let tocHeaderFont = Self.font(for: options.fontTheme, size: 28, weight: .bold)
            let tocRowFont    = Self.font(for: options.fontTheme, size: 15, weight: .medium)
            let tocSubFont    = Self.font(for: options.fontTheme, size: 13)

            pen.drawLeft("CONTENTS", font: tocHeaderFont, color: primaryText)
            pen.skip(10)

            // Horizontal rule under "CONTENTS"
            if let gc = UIGraphicsGetCurrentContext() {
                gc.saveGState()
                gc.setStrokeColor(separatorColor.cgColor)
                gc.setLineWidth(1.0)
                gc.move(to: CGPoint(x: margin, y: pen.y))
                gc.addLine(to: CGPoint(x: margin + contentW, y: pen.y))
                gc.strokePath()
                gc.restoreGState()
            }
            pen.skip(20)

            for (tocIndex, tocDay) in draft.days.enumerated() {
                let dayLabel = "Day \(tocIndex + 1)"
                let placesCount = tocDay.placeStops.count
                let placesLabel = "\(placesCount) place\(placesCount == 1 ? "" : "s")"

                let dayLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: tocRowFont, .foregroundColor: primaryText
                ]
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: tocRowFont, .foregroundColor: secondaryText
                ]
                let placesAttrs: [NSAttributedString.Key: Any] = [
                    .font: tocSubFont, .foregroundColor: secondaryText
                ]

                // Keep each TOC entry on its own vertical "row" to prevent overlap.
                pen.ensureRoom(StoryPageLayout.tocRowHeight)
                let rowTopY = pen.y

                dayLabel.draw(at: CGPoint(x: margin, y: rowTopY), withAttributes: dayLabelAttrs)
                tocDay.shortDateText.draw(at: CGPoint(x: margin + 72, y: rowTopY), withAttributes: dateAttrs)

                let placesSize = placesLabel.size(withAttributes: placesAttrs)
                placesLabel.draw(
                    at: CGPoint(x: margin + contentW - placesSize.width, y: rowTopY + 2),
                    withAttributes: placesAttrs
                )

                // Divider between day rows (so the "CONTENT" page reads clearly).
                if let gc = UIGraphicsGetCurrentContext() {
                    gc.saveGState()
                    gc.setStrokeColor(separatorColor.cgColor)
                    gc.setLineWidth(0.5)
                    let dividerY = rowTopY + StoryPageLayout.tocRowHeight - 6
                    gc.move(to: CGPoint(x: margin, y: dividerY))
                    gc.addLine(to: CGPoint(x: margin + contentW, y: dividerY))
                    gc.strokePath()
                    gc.restoreGState()
                }

                pen.skip(StoryPageLayout.tocRowHeight)
            }

            // ── Day Sections — each day starts on a fresh page ─────────
            for (dayIndex, day) in draft.days.enumerated() {
                // Always start a new page for each day
                pen.newPage()

                // "Day N" label — top-left of the day content page
                pen.drawLeft("Day \(dayIndex + 1)",
                             font: Self.font(for: options.fontTheme, size: 13, weight: .semibold), color: primaryText)
                pen.skip(2)

                // Day header date
                pen.drawLeft(day.shortDateText,
                             font: Self.font(for: options.fontTheme, size: 20, weight: .bold), color: primaryText)

                // Day caption
                if let caption = day.dayCaption,
                   !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pen.skip(4)
                    pen.drawLeft(caption,
                                 font: Self.font(for: options.fontTheme, size: 15),
                                 color: primaryText)
                    pen.skip(8)
                } else {
                    pen.skip(8)
                }

                // Map snapshot — right below day header
                if let mapImg = assets.maps[day.id] {
                    let mapH = min(contentW * (mapImg.size.height / mapImg.size.width), 280)
                    pen.drawImageFit(mapImg, width: contentW, height: mapH, cornerRadius: 12)
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
                        options: options,
                        cardBgColor: cardBgColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        separatorColor: separatorColor
                    )
                    pen.skip(24) // gap between cards
                }
            }
        }

        return url
    }

    // MARK: - Place Stop Card Drawing

    private static func drawPlaceStopCard(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        photos: [UUID: UIImage],
        options: PDFExportOptions,
        cardBgColor: UIColor,
        primaryText: UIColor,
        secondaryText: UIColor,
        separatorColor: UIColor
    ) {
        let includedPhotos = stop.photos.filter(\.isIncluded)
        let photosWithImages = includedPhotos.compactMap { p -> (RecapPhoto, UIImage)? in
            guard let img = photos[p.id] else { return nil }
            return (p, img)
        }

        switch options.layoutMode {
        case .normal:
            drawNormalStopCard(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                               photos: photosWithImages, options: options, cardBgColor: cardBgColor,
                               primaryText: primaryText, secondaryText: secondaryText,
                               separatorColor: separatorColor)
        case .story:
            drawStoryStopCard(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                              photos: photosWithImages, options: options, cardBgColor: cardBgColor,
                              primaryText: primaryText, secondaryText: secondaryText,
                              separatorColor: separatorColor)
        }
    }

    // MARK: - Shared: Stop Header

    /// Draws badge + title (with Google search link) + location subtitle.
    /// Advances pen.y to the bottom of the location line.
    private static func drawStopHeader(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        options: PDFExportOptions,
        primaryText: UIColor,
        secondaryText: UIColor
    ) {
        let badgeSize: CGFloat = 32
        let cardLeft = pen.margin + cardPadding
        let titleW = cardInteriorW - badgeSize - 10

        let titleFont = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
        let subFont   = Self.font(for: options.fontTheme, size: 12)

        // ── Badge ──
        pen.drawBadge(number: number, color: badgeColor, size: badgeSize)

        // ── Title with link icon ──
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: primaryText
        ]

        var urlToOpen: URL?
        if let query = stop.placeTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.google.com/search?q=\(query)") {
            urlToOpen = url
        }

        let attrTitle = NSMutableAttributedString(string: stop.placeTitle, attributes: titleAttrs)

        var customIcon: UIImage? = nil
        if let data = Data(base64Encoded: Self.linkIconBase64) {
            customIcon = UIImage(data: data)
        }

        if let linkIcon = customIcon {
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
            options: [.usesLineFragmentOrigin], context: nil
        )
        let drawRect = CGRect(
            x: cardLeft + badgeSize + 10,
            y: pen.y + (badgeSize - titleRectBounds.height) / 2,
            width: titleW, height: titleRectBounds.height
        )
        attrTitle.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)

        if let url = urlToOpen {
            let pdfRect = CGRect(x: drawRect.minX, y: pen.pageH - drawRect.maxY,
                                 width: drawRect.width, height: drawRect.height)
            pen.ctx.setURL(url, for: pdfRect)
        }

        pen.y += max(badgeSize, titleRectBounds.height)

        // ── Location subtitle ──
        let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty
        if hasSubtitle, let subtitle = stop.placeSubtitle {
            pen.skip(2)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont,
                .foregroundColor: primaryText
            ]
            let subSize = subtitle.boundingRect(
                with: CGSize(width: titleW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )
            subtitle.draw(
                with: CGRect(x: cardLeft + badgeSize + 10, y: pen.y,
                             width: titleW, height: subSize.height),
                options: [.usesLineFragmentOrigin],
                attributes: subAttrs, context: nil
            )
            pen.y += subSize.height
        }
    }

    // MARK: - Shared: Separator

    private enum SeparatorStyle {
        case thin   // 0.5pt line only
        case story  // lines flanking centered "STORY" label
    }

    /// Draws a separator and advances pen.y by 17pt (8 top + 1 line + 8 bottom).
    private static func drawSeparator(
        pen: inout Pen,
        style: SeparatorStyle,
        color: UIColor,
        cardLeft: CGFloat
    ) {
        let lineY = pen.y + 8
        guard let gc = UIGraphicsGetCurrentContext() else { pen.y += 17; return }

        switch style {
        case .thin:
            gc.saveGState()
            gc.setStrokeColor(color.cgColor)
            gc.setLineWidth(0.5)
            gc.move(to: CGPoint(x: cardLeft, y: lineY))
            gc.addLine(to: CGPoint(x: cardLeft + cardInteriorW, y: lineY))
            gc.strokePath()
            gc.restoreGState()

        case .story:
            let label = "STORY"
            let labelFont = UIFont.systemFont(ofSize: 9, weight: .medium)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: color
            ]
            let labelSize = label.size(withAttributes: labelAttrs)
            let labelX = cardLeft + (cardInteriorW - labelSize.width) / 2
            label.draw(at: CGPoint(x: labelX, y: lineY - labelSize.height / 2), withAttributes: labelAttrs)

            let lineEndX = labelX - 8
            let lineStartX2 = labelX + labelSize.width + 8

            gc.saveGState()
            gc.setStrokeColor(color.cgColor)
            gc.setLineWidth(0.5)
            gc.move(to: CGPoint(x: cardLeft, y: lineY))
            gc.addLine(to: CGPoint(x: lineEndX, y: lineY))
            gc.move(to: CGPoint(x: lineStartX2, y: lineY))
            gc.addLine(to: CGPoint(x: cardLeft + cardInteriorW, y: lineY))
            gc.strokePath()
            gc.restoreGState()
        }

        pen.y += 17
    }

    // MARK: - Shared: Photo Section Header

    /// Draws a compact [badge] Place Name row directly above the photo grid.
    /// Advances pen.y by the row height (24pt) + 4pt gap.
    private static func drawPhotoSectionHeader(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        options: PDFExportOptions,
        primaryText: UIColor,
        cardLeft: CGFloat
    ) {
        let badgeSize: CGFloat = 18
        let nameFont = Self.font(for: options.fontTheme, size: 12, weight: .medium)
        let rowH: CGFloat = 24

        pen.skip(8)

        // Small filled circle badge with number
        let badgeRect = CGRect(x: cardLeft, y: pen.y + (rowH - badgeSize) / 2,
                               width: badgeSize, height: badgeSize)
        if let gc = UIGraphicsGetCurrentContext() {
            gc.saveGState()
            gc.setFillColor(badgeColor.cgColor)
            gc.fillEllipse(in: badgeRect)
            let numText = "\(number)"
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let numSize = numText.size(withAttributes: numAttrs)
            numText.draw(at: CGPoint(x: badgeRect.midX - numSize.width / 2,
                                     y: badgeRect.midY - numSize.height / 2),
                         withAttributes: numAttrs)
            gc.restoreGState()
        }

        // Place name to the right of the badge
        let nameX = cardLeft + badgeSize + 6
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: primaryText]
        let nameSize = stop.placeTitle.size(withAttributes: nameAttrs)
        stop.placeTitle.draw(at: CGPoint(x: nameX, y: pen.y + (rowH - nameSize.height) / 2),
                             withAttributes: nameAttrs)

        pen.y += rowH
        pen.skip(4)
    }

    // MARK: - Shared: Photo Grid

    /// Draws the 2-column photo grid with per-photo captions.
    /// - indent: offset from cardLeft. Per spec, photos are always full-width — pass 0 in both Normal and Story modes.
    /// - cardLeft: pen.margin + cardPadding
    private static func drawPhotoGrid(
        pen: inout Pen,
        photos: [(RecapPhoto, UIImage)],
        indent: CGFloat,
        cardLeft: CGFloat,
        options: PDFExportOptions,
        secondaryText: UIColor,
        cardBgColor: UIColor
    ) {
        guard !photos.isEmpty else { return }
        let captionFont = Self.font(for: options.fontTheme, size: 11)
        let colW = photoSize
        let colH = photoSize
        let gridLeft = cardLeft + indent

        let pageBeforePhotos = pen.pageNumber
        pen.skip(8)
        if pen.pageNumber != pageBeforePhotos {
            let rowCount = (photos.count + 1) / 2
            let estRemaining = CGFloat(rowCount) * (photoSize + 45) + cardPadding + 8
            let contH = min(estRemaining, pen.maxY - pen.y)
            if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                gc.saveGState()
                gc.setFillColor(cardBgColor.cgColor)
                gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                gc.restoreGState()
            }
        }

        for row in stride(from: 0, to: photos.count, by: 2) {
            let pageBeforeEnsure = pen.pageNumber
            pen.ensureRoom(colH + 40)
            if pen.pageNumber != pageBeforeEnsure {
                let rowsLeft = (photos.count - row + 1) / 2
                let estRemaining = CGFloat(rowsLeft) * (colH + 45) + cardPadding + 8
                let contH = min(estRemaining, pen.maxY - pen.y)
                if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                    gc.saveGState()
                    gc.setFillColor(cardBgColor.cgColor)
                    gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                    gc.restoreGState()
                }
            }

            let (leftPhoto, leftImg) = photos[row]
            let hasPair = row + 1 < photos.count
            let leftShape = hasPair ? options.photoShapeOptions.leftShape : options.photoShapeOptions.singleShape
            // Solo photo fills the full row width; paired photos each get half
            let soloW = cardInteriorW - indent
            let leftW = hasPair ? colW : soloW
            let leftRect = CGRect(x: gridLeft, y: pen.y, width: leftW, height: colH)
            drawPhoto(leftImg, in: leftRect, shape: leftShape)

            if hasPair {
                let (_, rightImg) = photos[row + 1]
                let rightRect = CGRect(x: gridLeft + colW + photoGap, y: pen.y, width: colW, height: colH)
                drawPhoto(rightImg, in: rightRect, shape: options.photoShapeOptions.rightShape)
            }
            pen.y += colH

            // Per-photo captions
            var captionH: CGFloat = 0
            let leftCapW = hasPair ? colW : soloW
            if let cap = leftPhoto.caption, !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pen.skip(3)
                let capAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: secondaryText]
                let capSize = cap.boundingRect(
                    with: CGSize(width: leftCapW, height: 28),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: capAttrs, context: nil
                )
                let h = min(capSize.height, 28)
                cap.draw(with: CGRect(x: gridLeft, y: pen.y, width: leftCapW, height: h),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                         attributes: capAttrs, context: nil)
                captionH = max(captionH, h + 3)
            }
            if hasPair {
                let (rightPhoto, _) = photos[row + 1]
                if let cap = rightPhoto.caption, !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let capAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: secondaryText]
                    let capSize = cap.boundingRect(
                        with: CGSize(width: colW, height: 28),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        attributes: capAttrs, context: nil
                    )
                    let h = min(capSize.height, 28)
                    cap.draw(with: CGRect(x: gridLeft + colW + photoGap, y: pen.y, width: colW, height: h),
                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: capAttrs, context: nil)
                    captionH = max(captionH, h + 3)
                }
            }
            pen.y += captionH
            pen.skip(10)
        }
    }

    // MARK: - Normal Stop Card

    private static func drawNormalStopCard(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        photos: [(RecapPhoto, UIImage)],
        options: PDFExportOptions,
        cardBgColor: UIColor,
        primaryText: UIColor,
        secondaryText: UIColor,
        separatorColor: UIColor
    ) {
        let badgeSize: CGFloat = 32
        let cardLeft = pen.margin + cardPadding
        let textIndent: CGFloat = badgeSize + 10  // 42pt
        let captionMaxW = cardInteriorW - textIndent  // 466pt

        let titleFont    = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
        let subFont      = Self.font(for: options.fontTheme, size: 12)
        let captionFont  = Self.font(for: options.fontTheme, size: 14)

        let hasCaption = !(stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty

        // ── Pre-compute card height for background ──
        let estTitleH = max(badgeSize, estimateTextHeight(stop.placeTitle, font: titleFont, width: cardInteriorW - textIndent))
        var estContentH = estTitleH
        if hasSubtitle, let sub = stop.placeSubtitle {
            estContentH += 2 + estimateTextHeight(sub, font: subFont, width: cardInteriorW - textIndent)
        }
        if hasCaption, let caption = stop.overallStory {
            estContentH += 8 + estimateTextHeight(caption, font: captionFont, width: captionMaxW)
            estContentH += 17  // separator
        } else {
            estContentH += 8  // gap before photos
        }
        if !photos.isEmpty {
            let rowCount = (photos.count + 1) / 2
            estContentH += CGFloat(rowCount) * (photoSize + 10) + 8
        }
        let totalCardH = cardPadding + estContentH + cardPadding

        // Cohesion: keep header + separator + first photo row together
        let captionHForCohesion = hasCaption
            ? min(estimateTextHeight(stop.overallStory ?? "", font: captionFont, width: captionMaxW), 68)
            : 0
        let subHForCohesion = hasSubtitle
            ? 2 + estimateTextHeight(stop.placeSubtitle ?? "", font: subFont, width: cardInteriorW - textIndent)
            : 0
        let headerH = estTitleH + subHForCohesion + (hasCaption ? 8 + captionHForCohesion : 8)
        let separatorH: CGFloat = hasCaption ? 17 : 0
        let firstPhotoH: CGFloat = photos.isEmpty ? 0 : photoSize
        let cohesionH = cardPadding + headerH + separatorH + firstPhotoH + cardPadding
        pen.ensureRoom(min(cohesionH, (pen.pageH - pen.margin * 2) * 0.6))

        // ── Card background ──
        let bgH = min(totalCardH, pen.maxY - pen.y)
        if let gc = UIGraphicsGetCurrentContext() {
            gc.saveGState()
            let bgRect = CGRect(x: pen.margin, y: pen.y, width: contentW, height: bgH)
            gc.setFillColor(cardBgColor.cgColor)
            UIBezierPath(roundedRect: bgRect, cornerRadius: cardRadius).addClip()
            gc.fill(bgRect)
            gc.restoreGState()
        }
        pen.skip(cardPadding)

        // ── Header (badge + title + location) ──
        drawStopHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                       options: options, primaryText: primaryText, secondaryText: secondaryText)

        // ── Caption ──
        if hasCaption, let caption = stop.overallStory {
            pen.skip(8)
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: primaryText
            ]
            let captionSize = caption.boundingRect(
                with: CGSize(width: captionMaxW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: captionAttrs, context: nil
            )
            caption.draw(
                with: CGRect(x: cardLeft + textIndent, y: pen.y,
                             width: captionMaxW, height: captionSize.height),
                options: [.usesLineFragmentOrigin],
                attributes: captionAttrs, context: nil
            )
            pen.y += captionSize.height

            // Thin separator between caption and photos
            drawSeparator(pen: &pen, style: .thin, color: separatorColor, cardLeft: cardLeft)
        } else {
            pen.skip(8)
        }

        // ── Place name mini-header above photos ──
        if !photos.isEmpty {
            drawPhotoSectionHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                                   options: options, primaryText: primaryText, cardLeft: cardLeft)
        }

        // ── Photo grid (full width, indent = 0) ──
        drawPhotoGrid(pen: &pen, photos: photos, indent: 0, cardLeft: cardLeft,
                      options: options, secondaryText: primaryText, cardBgColor: cardBgColor)

        pen.skip(cardPadding)
    }

    // MARK: - Story Stop Card

    private static func drawStoryStopCard(
        pen: inout Pen,
        stop: PlaceStop,
        number: Int,
        badgeColor: UIColor,
        photos: [(RecapPhoto, UIImage)],
        options: PDFExportOptions,
        cardBgColor: UIColor,
        primaryText: UIColor,
        secondaryText: UIColor,
        separatorColor: UIColor
    ) {
        let badgeSize: CGFloat = 32
        let cardLeft = pen.margin + cardPadding

        let titleFont   = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
        let subFont     = Self.font(for: options.fontTheme, size: 12)
        let captionFont = Self.font(for: options.fontTheme, size: 14)

        let hasPhotos  = !photos.isEmpty
        let hasCaption = !(stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty

        // ── Pre-compute card height for background ──
        let estTitleH = max(badgeSize, estimateTextHeight(stop.placeTitle, font: titleFont, width: cardInteriorW - badgeSize - 10))
        var estContentH = estTitleH
        if hasSubtitle, let sub = stop.placeSubtitle {
            estContentH += 2 + estimateTextHeight(sub, font: subFont, width: cardInteriorW - badgeSize - 10)
        }
        if hasPhotos {
            let rowCount = (photos.count + 1) / 2
            estContentH += 8 + CGFloat(rowCount) * (photoSize + 10)
            if hasCaption, let caption = stop.overallStory {
                estContentH += 17  // STORY separator
                estContentH += estimateTextHeight(caption, font: captionFont, width: cardInteriorW)
            }
        } else if hasCaption, let caption = stop.overallStory {
            // No photos: fall through to Normal-style caption
            estContentH += 8 + estimateTextHeight(caption, font: captionFont, width: cardInteriorW - badgeSize - 10)
        }
        let totalCardH = cardPadding + estContentH + cardPadding

        // Cohesion: header + first photo row (or caption if no photos)
        let subHForCohesion = hasSubtitle
            ? 2 + estimateTextHeight(stop.placeSubtitle ?? "", font: subFont, width: cardInteriorW - badgeSize - 10)
            : 0
        let headerH = estTitleH + subHForCohesion
        let firstRowH: CGFloat = hasPhotos ? (photoSize + 10) : 0
        let cohesionH = cardPadding + headerH + 8 + firstRowH + cardPadding
        pen.ensureRoom(min(cohesionH, (pen.pageH - pen.margin * 2) * 0.6))

        // ── Card background ──
        let bgH = min(totalCardH, pen.maxY - pen.y)
        if let gc = UIGraphicsGetCurrentContext() {
            gc.saveGState()
            let bgRect = CGRect(x: pen.margin, y: pen.y, width: contentW, height: bgH)
            gc.setFillColor(cardBgColor.cgColor)
            UIBezierPath(roundedRect: bgRect, cornerRadius: cardRadius).addClip()
            gc.fill(bgRect)
            gc.restoreGState()
        }
        pen.skip(cardPadding)

        // ── Header ──
        drawStopHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                       options: options, primaryText: primaryText, secondaryText: secondaryText)

        if hasPhotos {
            // ── Place name mini-header above photos ──
            drawPhotoSectionHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                                   options: options, primaryText: primaryText, cardLeft: cardLeft)

            // ── Photos (full width) ──
            drawPhotoGrid(pen: &pen, photos: photos, indent: 0, cardLeft: cardLeft,
                          options: options, secondaryText: primaryText, cardBgColor: cardBgColor)

            // ── STORY divider + caption (only if caption exists) ──
            if hasCaption, let caption = stop.overallStory {
                drawSeparator(pen: &pen, style: .story, color: separatorColor, cardLeft: cardLeft)

                let captionAttrs: [NSAttributedString.Key: Any] = [
                    .font: captionFont,
                    .foregroundColor: primaryText
                ]
                let captionSize = caption.boundingRect(
                    with: CGSize(width: cardInteriorW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: captionAttrs, context: nil
                )
                pen.ensureRoom(captionSize.height)
                caption.draw(
                    with: CGRect(x: cardLeft, y: pen.y,
                                 width: cardInteriorW, height: captionSize.height),
                    options: [.usesLineFragmentOrigin],
                    attributes: captionAttrs, context: nil
                )
                pen.y += captionSize.height
            }
        } else if hasCaption, let caption = stop.overallStory {
            // No photos: render caption like Normal mode (indented)
            let textIndent: CGFloat = badgeSize + 10
            let captionMaxW = cardInteriorW - textIndent
            pen.skip(8)
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: primaryText
            ]
            let captionSize = caption.boundingRect(
                with: CGSize(width: captionMaxW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: captionAttrs, context: nil
            )
            caption.draw(
                with: CGRect(x: cardLeft + textIndent, y: pen.y,
                             width: captionMaxW, height: captionSize.height),
                options: [.usesLineFragmentOrigin],
                attributes: captionAttrs, context: nil
            )
            pen.y += captionSize.height
        }

        pen.skip(cardPadding)
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
        let coverID = draft.selectedCoverPhotoIdentifier ?? allIncluded.first?.localIdentifier

        var idsToFetch = Set<String>()
        if let c = coverID { idsToFetch.insert(c) }
        for p in allIncluded {
            if let id = p.localIdentifier { idsToFetch.insert(id) }
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
            for p in allIncluded where p.localIdentifier == identifier {
                result.photos[p.id] = image
            }
        }

        guard !phAssetIds.isEmpty else {
            if result.coverImage == nil, let first = allIncluded.first {
                result.coverImage = result.photos[first.id]
            }
            return result
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(phAssetIds), options: nil)
        let manager = PHImageManager.default()
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .exact

        var phAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in phAssets.append(asset) }

        await withTaskGroup(of: (String, UIImage?).self) { group in
            for asset in phAssets {
                group.addTask {
                    await withCheckedContinuation { cont in
                        manager.requestImage(
                            for: asset,
                            targetSize: CGSize(width: 1200, height: 1200),
                            contentMode: .aspectFit,
                            options: opts
                        ) { image, info in
                            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                            if !isDegraded {
                                cont.resume(returning: (asset.localIdentifier, image))
                            }
                        }
                    }
                }
            }

            for await (id, image) in group {
                guard let image else { continue }
                if id == coverID { result.coverImage = image }
                for p in allIncluded where p.localIdentifier == id {
                    result.photos[p.id] = image
                }
            }
        }

        if result.coverImage == nil, let first = allIncluded.first {
            result.coverImage = result.photos[first.id]
        }

        // Fetch cloud photos for any included photos that have no local asset.
        let cloudPhotos = allIncluded.filter { $0.localIdentifier == nil && $0.cloudURL != nil }
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
    let pageBackground: UIColor
    var y: CGFloat = 0
    var pageNumber: Int = 0

    var contentW: CGFloat { pageW - margin * 2 }
    var maxY: CGFloat { pageH - margin }

    mutating func newPage() {
        ctx.beginPage()
        y = margin
        pageNumber += 1
        // Fill page background (default PDF background is white; fill explicitly for dark mode).
        if pageBackground != .white {
            if let gc = UIGraphicsGetCurrentContext() {
                gc.saveGState()
                gc.setFillColor(pageBackground.cgColor)
                gc.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
                gc.restoreGState()
            }
        }
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
