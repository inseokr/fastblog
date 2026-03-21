# PDF Export Animation Freeze Fix Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5+ second main-thread freeze during Story Mode PDF export so the `ExportingPDFView` animation stays alive while the PDF generates.

**Architecture:** Split the single synchronous render loop inside `UIGraphicsPDFRenderer.writePDF` into two phases: (1) render each page to a `UIImage` one at a time with `await Task.yield()` between pages, then (2) assemble the PDF from pre-rendered images synchronously. The yield lets Core Animation and SwiftUI animations tick between page renders.

**Tech Stack:** Swift, SwiftUI, UIKit (`UIHostingController`, `UIGraphicsImageRenderer`, `UIGraphicsPDFRenderer`), Swift Concurrency (`@MainActor`, `Task.yield()`)

---

### Task 1: Replace single-phase render loop with two-phase async approach

**Files:**
- Modify: `fastblog/ViewModels/StoryBookViewModel.swift` — `StoryModePDFExportService.exportStoryModePDF` function and its enclosing enum

**Context:** The function is `@MainActor async throws`. The current render loop is inside `renderer.writePDF { ... }` which is synchronous. The fix extracts a `renderPageToImage` helper and adds a `for` loop with `await Task.yield()` before Phase 2 PDF assembly.

---

- [ ] **Step 1: Add the `renderPageToImage` helper to `StoryModePDFExportService`**

Open `fastblog/ViewModels/StoryBookViewModel.swift`. After the closing brace of `exportStoryModePDF`, add this private static helper inside the `StoryModePDFExportService` enum:

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
```

- [ ] **Step 2: Replace the render loop inside `exportStoryModePDF`**

In the same file, find this block inside `exportStoryModePDF` (lines ~76–118):

```swift
let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
try renderer.writePDF(to: multiPageURL) { pdfContext in
    for (idx, page) in pages.enumerated() {
        pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
        autoreleasepool {
            let hosting = UIHostingController(
                rootView: StoryPageView(
                    page: page,
                    bookPageIndex: idx + 1,
                    bookPageCount: pages.count,
                    showNextDayLabel: false,
                    photoShapeOptions: options.photoShapeOptions,
                    blogColor: options.blogColor,
                    fontTheme: options.fontTheme,
                    layoutMode: options.layoutMode
                )
            )
            hosting.view.bounds = pageRect
            hosting.view.backgroundColor = options.blogColor == .black ? .black : .white

            var attached = false
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: \.isKeyWindow) {
                window.addSubview(hosting.view)
                attached = true
                hosting.view.frame = pageRect
            } else {
                hosting.view.frame = pageRect
            }

            defer {
                if attached {
                    hosting.view.removeFromSuperview()
                }
            }

            hosting.view.layoutIfNeeded()
            hosting.view.drawHierarchy(in: pageRect, afterScreenUpdates: true)
        }
    }
}
```

Replace it with:

```swift
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
```

- [ ] **Step 3: Build the project**

In Xcode, press `Cmd+B`. Expected: build succeeds with no errors or warnings related to the changed file.

If build fails, check:
- `Self.renderPageToImage` must be called inside an `@MainActor` context — it is, since `exportStoryModePDF` is `@MainActor`
- `await Task.yield()` requires the function to be `async` — it is

- [ ] **Step 4: Manual verification — animation stays alive**

Run on a device or simulator with a multi-day trip (3+ days recommended):

1. Open Story Mode for a trip
2. Tap the **Share** button
3. Observe: the `ExportingPDFView` animation (spinning ring, pulsing logo) should remain visually active — it may stutter briefly per page but should not freeze completely
4. The share sheet should appear once generation completes
5. Share to Files or Mail and open the PDF — verify all pages have correct content (no white pages, photos present)

- [ ] **Step 5: Commit**

```bash
git add fastblog/ViewModels/StoryBookViewModel.swift
git commit -m "fix(story-mode): yield between pages during PDF export to keep animation alive"
```
