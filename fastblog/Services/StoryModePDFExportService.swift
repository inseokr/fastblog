import SwiftUI
import UIKit
import PDFKit

/// Renders the same SwiftUI story pages (`StoryPageView`) into a multi-page PDF — distinct from `PDFExportService`’s recap-style vertical PDF.
enum StoryModePDFExportService {

    enum ExportError: Error, LocalizedError {
        case noPages
        case failedToRenderPage(Int)
        case failedToEmbedLinks

        var errorDescription: String? {
            switch self {
            case .noPages: return "Nothing to export."
            case .failedToRenderPage(let i): return "Could not render story page \(i + 1)."
            case .failedToEmbedLinks: return "Could not add place links to the PDF."
            }
        }
    }

    /// Builds a PDF whose pages match the Story Mode book (cover, TOC, maps, day content).
    /// - Parameters:
    ///   - pages: Same `[StoryPage]` array as `StoryBookView` / `StoryPageLayout.buildPages`.
    ///   - draft: Used for filename uniquing; must match the blog being read.
    ///   - options: `fontTheme` affects TOC link layout math; photo shapes apply to recap PDF only.
    @MainActor
    static func exportStoryPDF(
        pages: [StoryPage],
        draft: RecapBlogDetail,
        options: PDFExportOptions
    ) async throws -> URL {
        guard !pages.isEmpty else { throw ExportError.noPages }

        let safeTitle = draft.title
            .replacingOccurrences(of: "/", with: "-")
        let url = URL.documentsDirectory.appendingPathComponent("\(safeTitle) | Storybook.pdf")

        // Use the effective story viewport (screen minus safe-area insets) so the PDF
        // page proportions match what the reader sees in Story Mode's TabView.
        let size = CGSize(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.effectiveStoryViewportHeight
        )

        var pageImages: [UIImage] = []
        pageImages.reserveCapacity(pages.count)

        for (idx, page) in pages.enumerated() {
            // Yield occasionally so chrome can animate; every-page yield adds a lot of latency on long books.
            if idx % 2 == 0 {
                await Task.yield()
            }
            let image = try autoreleasepool {
                try renderPageToImage(page: page, size: size, pageIndex: idx)
            }
            pageImages.append(image)
        }

        // One PDF write: build in memory with `PDFPage(image:)` + link annotations.
        // Avoids the old path (write raster PDF → PDFDocument re-open → full re-save), which roughly doubled export time.
        try buildPDFInMemoryWithPlaceLinks(
            pageImages: pageImages,
            storyPages: pages,
            pageSize: size,
            fontTheme: options.fontTheme,
            outputURL: url
        )

        return url
    }

    /// Assembles pages from rendered images, attaches link annotations, and writes once.
    private static func buildPDFInMemoryWithPlaceLinks(
        pageImages: [UIImage],
        storyPages: [StoryPage],
        pageSize: CGSize,
        fontTheme: FontTheme,
        outputURL: URL
    ) throws {
        let doc = PDFDocument()
        let n = min(pageImages.count, storyPages.count)

        for idx in 0..<n {
            let image = pageImages[idx]
            guard let pdfPage = PDFPage(image: image) else {
                throw ExportError.failedToEmbedLinks
            }

            let media = pdfPage.bounds(for: .mediaBox)
            let pageH = media.height

            let pairs =
                StoryPageLayout.storyModePDFPlaceLinkRects(
                    storyPage: storyPages[idx],
                    pageSize: pageSize,
                    fontTheme: fontTheme,
                    layoutMode: .normal
                )
                + StoryPageLayout.storyModePDFTOCLinkRects(
                    storyPage: storyPages[idx],
                    pageSize: pageSize,
                    fontTheme: fontTheme
                )

            for (uiRect, linkURL) in pairs {
                let pdfBounds = CGRect(
                    x: uiRect.minX,
                    y: pageH - uiRect.maxY,
                    width: uiRect.width,
                    height: uiRect.height
                )
                let ann = PDFAnnotation(bounds: pdfBounds, forType: .link, withProperties: nil)
                ann.url = linkURL
                pdfPage.addAnnotation(ann)
            }

            doc.insert(pdfPage, at: doc.pageCount)
        }

        // Internal TOC → day jumps need `PDFDestination`, which only works after target pages exist in the document.
        for idx in 0..<n {
            guard let pdfPage = doc.page(at: idx) else { continue }
            let jumps = StoryPageLayout.storyModePDFTOCDayJumpRects(
                storyPage: storyPages[idx],
                pageSize: pageSize,
                fontTheme: fontTheme
            )
            let pageH = pdfPage.bounds(for: .mediaBox).height
            for (uiRect, destIndex) in jumps {
                guard destIndex >= 0, destIndex < doc.pageCount, let targetPage = doc.page(at: destIndex) else { continue }
                let pdfBounds = CGRect(
                    x: uiRect.minX,
                    y: pageH - uiRect.maxY,
                    width: uiRect.width,
                    height: uiRect.height
                )
                let ann = PDFAnnotation(bounds: pdfBounds, forType: .link, withProperties: nil)
                let media = targetPage.bounds(for: .mediaBox)
                ann.destination = PDFDestination(page: targetPage, at: CGPoint(x: 0, y: media.height))
                pdfPage.addAnnotation(ann)
            }
        }

        guard doc.write(to: outputURL) else {
            throw ExportError.failedToEmbedLinks
        }
    }

    @MainActor
    private static func renderPageToImage(page: StoryPage, size: CGSize, pageIndex: Int) throws -> UIImage {
        let root = StoryPageView(page: page)
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
            .background(Color.white)

        let imageRenderer = ImageRenderer(content: root)
        imageRenderer.scale = 2.0  // Cap at 2× — 3× (device scale) triples pixel count with negligible visual gain in PDF
        imageRenderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)

        guard let image = imageRenderer.uiImage else {
            throw ExportError.failedToRenderPage(pageIndex)
        }
        return image
    }
}
