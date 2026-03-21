import SwiftUI
import UIKit

/// Renders the same SwiftUI story pages (`StoryPageView`) into a multi-page PDF — distinct from `PDFExportService`’s recap-style vertical PDF.
enum StoryModePDFExportService {

    enum ExportError: Error, LocalizedError {
        case noPages
        case failedToRenderPage(Int)

        var errorDescription: String? {
            switch self {
            case .noPages: return "Nothing to export."
            case .failedToRenderPage(let i): return "Could not render story page \(i + 1)."
            }
        }
    }

    /// Builds a PDF whose pages match the Story Mode book (cover, TOC, maps, day content).
    /// - Parameters:
    ///   - pages: Same `[StoryPage]` array as `StoryBookView` / `StoryPageLayout.buildPages`.
    ///   - draft: Used for filename uniquing; must match the blog being read.
    ///   - options: Reserved for future parity with PDF options (fonts/shapes); currently unused for layout.
    @MainActor
    static func exportStoryPDF(
        pages: [StoryPage],
        draft: RecapBlogDetail,
        options: PDFExportOptions
    ) async throws -> URL {
        _ = options
        guard !pages.isEmpty else { throw ExportError.noPages }

        let safeTitle = draft.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = URL.documentsDirectory.appendingPathComponent("\(safeTitle)_\(draft.id.uuidString)_Story.pdf")

        let size = StoryRenderMetrics.clampedScreenSize
        let pageRect = CGRect(origin: .zero, size: size)

        var pageImages: [UIImage] = []
        pageImages.reserveCapacity(pages.count)

        for (idx, page) in pages.enumerated() {
            await Task.yield()
            let image = try autoreleasepool {
                try renderPageToImage(page: page, size: size, pageIndex: idx)
            }
            pageImages.append(image)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { pdfContext in
            for image in pageImages {
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                image.draw(in: pageRect)
            }
        }

        return url
    }

    @MainActor
    private static func renderPageToImage(page: StoryPage, size: CGSize, pageIndex: Int) throws -> UIImage {
        let root = StoryPageView(page: page)
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
            .background(Color.white)

        let imageRenderer = ImageRenderer(content: root)
        imageRenderer.scale = UIScreen.main.scale
        imageRenderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)

        guard let image = imageRenderer.uiImage else {
            throw ExportError.failedToRenderPage(pageIndex)
        }
        return image
    }
}
