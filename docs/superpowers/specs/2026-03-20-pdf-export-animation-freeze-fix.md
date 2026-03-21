# PDF Export Animation Freeze Fix

**Date:** 2026-03-20
**Branch:** pdfstyle
**File:** `fastblog/ViewModels/StoryBookViewModel.swift`

---

## Problem

When the user taps Share in Story Mode, the `ExportingPDFView` animation freezes for 5+ seconds before the share sheet appears. The main thread is blocked because `StoryModePDFExportService.exportStoryModePDF` runs all page rendering inside a synchronous `UIGraphicsPDFRenderer.writePDF` closure. Each page calls `drawHierarchy(in:afterScreenUpdates:true)`, which forces a compositing pass. N pages in a tight loop = N blocking compositing waits = total freeze.

A prior attempt to fix this by switching to `afterScreenUpdates: false` caused white pages because SwiftUI async image loading had not completed before capture. That change was reverted, leaving the freeze issue unsolved.

---

## Design

Split `exportStoryModePDF` into two phases:

### Phase 1 — Page Rendering (async, with run-loop yields)

```swift
var pageImages: [UIImage] = []
pageImages.reserveCapacity(pages.count)

for (idx, page) in pages.enumerated() {
    await Task.yield()  // return control to run loop; animations tick here
    let image = Self.renderPageToImage(
        page: page,
        bookPageIndex: idx + 1,
        bookPageCount: pages.count,
        options: options,
        pageRect: pageRect
    )
    pageImages.append(image)
}
```

`Task.yield()` on a `@MainActor` async function suspends the current task and enqueues a continuation on the main actor's executor. This allows the main run loop to process pending work — including Core Animation commits and SwiftUI animation frame updates — before the next page render starts. One yield per page is sufficient to keep the animation visually alive.

Images are accumulated into `[UIImage]`, one per page, in order.

### Phase 2 — PDF Assembly (synchronous, fast)

```swift
let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
try renderer.writePDF(to: multiPageURL) { pdfContext in
    for image in pageImages {
        pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
        image.draw(in: pageRect)
    }
}
```

Drawing pre-rendered `UIImage`s into a PDF context is trivially fast (no SwiftUI layout, no UIKit view hierarchy). This replaces the previous rendering loop that was embedded inside `writePDF`.

### `renderPageToImage` Helper

```swift
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

        // Attach to the key window so SwiftUI can resolve the environment properly.
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

        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { _ in
            hosting.view.drawHierarchy(in: pageRect, afterScreenUpdates: true)
        }

        // Always remove before returning so we don't hold the view hierarchy.
        if keyWindow != nil {
            hosting.view.removeFromSuperview()
        }

        return image
    }
}
```

Key notes on the helper:
- **`autoreleasepool`** wraps the entire body so the `UIHostingController` and its view tree are released immediately after each page. This prevents N fully-rendered SwiftUI hierarchies from accumulating in memory during Phase 1.
- **Window attachment**: uses the key window, same strategy as the current code. Fallback (no window) does not attach but still lays out and captures — matches existing behavior.
- **Return type is `UIImage` (non-optional)**: `UIGraphicsImageRenderer.image` always returns a valid `UIImage`. If the view hasn't rendered fully, the image may be partially blank, but this is identical to the existing behavior with `afterScreenUpdates: true`.
- **No throws**: render failures are silent (blank image), matching the existing contract.

---

## Scope

**Changes:**
- `StoryModePDFExportService.exportStoryModePDF`: replace single-phase sync loop with two-phase async loop
- New private static `renderPageToImage(page:bookPageIndex:bookPageCount:options:pageRect:) -> UIImage` helper

**No changes:**
- `ExportingPDFView` — animation view unchanged
- `StoryBookView` — share sheet flow and error handling unchanged
- PDF output fidelity — identical render path, same `afterScreenUpdates: true`
- Error handling — if `renderer.writePDF` throws in Phase 2, the existing `catch` in `exportStoryModePDFAndShare` handles it as before

**Memory note:** Phase 1 holds `[UIImage]` (one per page) in memory simultaneously before Phase 2 runs. Each image is ~screen-size (390×844 points × display scale). For a typical trip of 10–20 pages at 3× scale, this is ~10–20 × ~4MB ≈ 40–80MB peak. The `autoreleasepool` in the helper ensures the UIHostingController memory is released per-page; only the final `UIImage` remains. This is an acceptable trade-off given the existing large PDF generation.

---

## Trade-offs

- Each page still blocks the main thread for its `drawHierarchy` call (~100–300ms). The animation ticks during yields *between* pages, not during each render. This is a meaningful improvement over the current full freeze.
- Total generation time is marginally longer due to an extra `image.draw(in:)` pass in Phase 2 and the overhead of `UIGraphicsImageRenderer`, but this is negligible (<1ms/page).
- Peak memory usage during Phase 1 is higher than the current approach (holding N UIImages vs. assembling the PDF incrementally). See Memory note above.

---

## Acceptance Criteria

- The `ExportingPDFView` animation visibly continues to play while the PDF is generating (no full freeze).
- The share sheet still appears after full PDF generation completes.
- The generated PDF is visually identical to before (no white pages, all images present).
- No changes to other screens or flows.
