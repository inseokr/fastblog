// fastblog/ViewModels/StoryBookViewModel.swift
import Foundation
import PDFKit
import SwiftUI
import UIKit

@MainActor
final class StoryBookViewModel: ObservableObject {
    enum State {
        case loading
        case ready([StoryPage])
        case failed(Error)
    }

    @Published var state: State = .loading
    private var buildTask: Task<Void, Never>?

    func build(from detail: RecapBlogDetail) {
        buildTask?.cancel()
        state = .loading
        buildTask = Task {
            do {
                let content = try await StoryBookBuilder.build(from: detail)
                guard !Task.isCancelled else { return }
                let displayScale = await MainActor.run { UIScreen.main.scale }
                var pages = StoryPageLayout.buildPages(from: content, fontTheme: .classic)
                StoryBookBuilder.applyHeroPhotoQuality(to: &pages, displayScale: displayScale)
                state = .ready(pages)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error)
            }
        }
    }

    func cancel() {
        buildTask?.cancel()
    }
}

/// Generates the "Story mode" multi-page PDF for a given `RecapBlogDetail`.
///
/// Note: this lives in `StoryBookViewModel.swift` (an existing compiled source file)
/// so it's always part of the app target. Otherwise, new standalone Swift files
/// sometimes aren't included in `project.pbxproj`.
@MainActor
enum StoryModePDFExportService {
    struct ExportResult {
        let pdfURL: URL
        let shareURL: URL
    }

    static func exportStoryModePDF(
        from detail: RecapBlogDetail,
        options: PDFExportOptions = PDFExportOptions(),
        onPDFGenerationComplete: (@MainActor () async -> Void)? = nil
    ) async throws -> ExportResult {
        // Build the internal normalized story-book model, then convert to page view models.
        let content = try await StoryBookBuilder.build(from: detail)
        let displayScale = await MainActor.run { UIScreen.main.scale }
                var pages = StoryPageLayout.buildPages(from: content, fontTheme: options.fontTheme, layoutMode: options.layoutMode)
        StoryBookBuilder.applyHeroPhotoQuality(to: &pages, displayScale: displayScale)

        let rawPageSize = UIScreen.main.bounds.size
        let pageSize = (rawPageSize.width > 0 && rawPageSize.height > 0)
            ? rawPageSize
            : CGSize(width: 390, height: 844)
        let pageRect = CGRect(origin: .zero, size: pageSize)

        let safeTitle = detail.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let multiPageURL = documentsDir.appendingPathComponent("\(safeTitle)_StoryBook.pdf")

        // Phase 1: render each page to UIImage, yielding between pages so animations stay alive
        var pageImages: [UIImage] = []
        pageImages.reserveCapacity(pages.count)
        for (idx, page) in pages.enumerated() {
            await Task.yield()
            let image = Self.renderPageToImage(
                page: page,
                bookPageIndex: idx + 1,
                bookPageCount: pages.count,
                options: options,
                pageRect: pageRect
            )
            pageImages.append(image)
        }

        // Phase 2: assemble PDF from pre-rendered images (fast — no SwiftUI layout overhead)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: multiPageURL) { pdfContext in
            for image in pageImages {
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                image.draw(in: pageRect)
            }
        }

        try addGoogleSearchLinkAnnotationsToStoryModePDF(
            pdfURL: multiPageURL,
            storyPages: pages,
            pageSize: pageSize,
            fontTheme: options.fontTheme,
            layoutMode: options.layoutMode
        )

        if let onPDFGenerationComplete {
            await onPDFGenerationComplete()
        }

        return ExportResult(pdfURL: multiPageURL, shareURL: multiPageURL)
    }

    @MainActor
    private static func renderPageToImage(
        page: StoryPage,
        bookPageIndex: Int,
        bookPageCount: Int,
        options: PDFExportOptions,
        pageRect: CGRect
    ) -> UIImage {
        autoreleasepool {
            let hosting = UIHostingController(
                rootView: StoryPageView(
                    page: page,
                    bookPageIndex: bookPageIndex,
                    bookPageCount: bookPageCount,
                    showNextDayLabel: false,
                    photoShapeOptions: options.photoShapeOptions,
                    blogColor: options.blogColor,
                    fontTheme: options.fontTheme,
                    layoutMode: options.layoutMode
                )
            )
            hosting.view.bounds = pageRect
            hosting.view.backgroundColor = options.blogColor == .black ? .black : .white

            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: \.isKeyWindow)

            if let window = keyWindow {
                window.addSubview(hosting.view)
                hosting.view.frame = pageRect
            } else {
                hosting.view.frame = pageRect
            }

            hosting.view.layoutIfNeeded()

            let imageRenderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = imageRenderer.image { _ in
                hosting.view.drawHierarchy(in: pageRect, afterScreenUpdates: true)
            }

            if keyWindow != nil {
                hosting.view.removeFromSuperview()
            }

            return image
        }
    }

    /// Rasterized story PDFs don't preserve SwiftUI `Link`s; add PDF link annotations over place titles.
    private static func addGoogleSearchLinkAnnotationsToStoryModePDF(
        pdfURL: URL,
        storyPages: [StoryPage],
        pageSize: CGSize,
        fontTheme: FontTheme,
        layoutMode: PDFLayoutMode
    ) throws {
        guard let doc = PDFDocument(url: pdfURL) else { return }
        guard doc.pageCount == storyPages.count else { return }

        for i in 0..<doc.pageCount {
            guard let pdfPage = doc.page(at: i) else { continue }
            let mediaBox = pdfPage.bounds(for: .mediaBox)
            let pageH = mediaBox.height

            let pairs = StoryPageLayout.storyModePDFPlaceLinkRects(
                storyPage: storyPages[i],
                pageSize: pageSize,
                fontTheme: fontTheme,
                layoutMode: layoutMode
            )
            for (uiRect, url) in pairs {
                let pdfRect = CGRect(
                    x: uiRect.origin.x + mediaBox.origin.x,
                    y: pageH - uiRect.origin.y - uiRect.height + mediaBox.origin.y,
                    width: uiRect.width,
                    height: uiRect.height
                )
                let annotation = PDFAnnotation(bounds: pdfRect, forType: .link, withProperties: nil)
                annotation.url = url
                pdfPage.addAnnotation(annotation)
            }
        }

        guard doc.write(to: pdfURL) else {
            throw NSError(
                domain: "StoryModePDFExport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not save PDF with link annotations."]
            )
        }
    }
}
