# Story Mode — Book Reader Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a horizontal, page-based book reader for Bloggo trip journals that launches from `RecapBlogPageView` as a full-screen cover.

**Architecture:** `StoryBookBuilder` (async) normalizes `RecapBlogDetail` → `StoryBookContent`. `StoryPageLayout` (pure sync) computes `[StoryPage]` using fixed slot heights. `StoryBookView` renders pages in a `TabView(.page)` — no vertical scrolling anywhere.

**Tech Stack:** Swift, SwiftUI, UIKit (image downsampling), `MapSnapshotHelper` (existing), `TabView` with `PageTabViewStyle`

---

## File Map

**New — Models**
- `fastblog/Models/StoryBookContent.swift` — all content structs
- `fastblog/Models/StoryPage.swift` — `StoryPage` enum, `DayContentPage`, `ContentSlot`

**New — Services**
- `fastblog/Services/StoryBookBuilder.swift` — `RecapBlogDetail` → `StoryBookContent`
- `fastblog/Services/StoryPageLayout.swift` — `StoryBookContent` → `[StoryPage]`

**New — ViewModel**
- `fastblog/ViewModels/StoryBookViewModel.swift` — async state machine

**New — Views**
- `fastblog/Views/StoryBook/StoryBookView.swift` — root container + close button
- `fastblog/Views/StoryBook/StoryPageView.swift` — page dispatcher
- `fastblog/Views/StoryBook/CoverPageView.swift`
- `fastblog/Views/StoryBook/TOCPageView.swift`
- `fastblog/Views/StoryBook/DayMapPageView.swift`
- `fastblog/Views/StoryBook/DayContentPageView.swift`
- `fastblog/Views/StoryBook/PlaceBlockView.swift`
- `fastblog/Views/StoryBook/PhotoContinuationBlockView.swift`
- `fastblog/Views/StoryBook/PhotoCardView.swift`
- `fastblog/Views/StoryBook/PageFooterView.swift`

**Modified**
- `fastblog/Views/RecapBlogPageView.swift` — add `@State private var showStoryMode = false` + `.fullScreenCover` + Story Mode button

---

## Task 1: Data Models

**Files:**
- Create: `fastblog/Models/StoryBookContent.swift`
- Create: `fastblog/Models/StoryPage.swift`

- [ ] **Step 1: Create `StoryBookContent.swift`**

```swift
// fastblog/Models/StoryBookContent.swift
import UIKit

struct StoryBookContent {
    let cover: CoverContent
    let overview: BlogOverviewContent
    let days: [StoryDay]
}

struct CoverContent {
    let title: String
    let subtitle: String        // e.g. "March 12–19, 2025"
    let coverPhoto: UIImage?    // nil → gradient placeholder (EC-5)
}

struct BlogOverviewContent {
    let dateRange: String
    let dayCount: Int
    let entries: [TOCEntry]
}

struct TOCEntry {
    let dayNumber: Int
    let date: String
    let firstPlaceName: String
}

struct StoryDay {
    let dayNumber: Int
    let date: Date
    let dayCaption: String?     // nil → skip caption block (EC-3)
    let mapSnapshot: UIImage?   // nil → skip map page (EC-7)
    let places: [PlaceContent]
}

struct PlaceContent {
    let title: String
    let timestamp: String?
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
    let photos: [PhotoContent]
}

struct PhotoContent {
    let image: UIImage          // pre-downsampled to screen resolution
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
}
```

- [ ] **Step 2: Create `StoryPage.swift`**

```swift
// fastblog/Models/StoryPage.swift

enum StoryPage {
    case cover(CoverContent)
    case tableOfContents(entries: [TOCEntry], overview: BlogOverviewContent, pageIndex: Int, totalPages: Int)
    case dayMap(StoryDay)
    case dayContent(DayContentPage)
}

struct DayContentPage {
    let day: StoryDay
    let isFirstPage: Bool
    let slots: [ContentSlot]
    let isLastPageOfDay: Bool
    let isLastPageOfTrip: Bool
    // Non-nil only when isLastPageOfDay == true && isLastPageOfTrip == false
    let nextDayName: String?
}

enum ContentSlot {
    case dayCaption(String)
    case placeBlock(PlaceContent, photoSlice: ClosedRange<Int>)
    case photoOverflowContinuation(placeName: String, PlaceContent, photoSlice: ClosedRange<Int>)
}
```

- [ ] **Step 3: Verify the project builds**

Open Xcode and build (⌘B). Fix any compile errors before proceeding.

- [ ] **Step 4: Commit**

```bash
git add fastblog/Models/StoryBookContent.swift fastblog/Models/StoryPage.swift
git commit -m "feat(story-mode): add StoryBookContent and StoryPage data models"
```

---

## Task 2: Layout Engine — `StoryPageLayout`

**Files:**
- Create: `fastblog/Services/StoryPageLayout.swift`

This is a pure synchronous value-type engine. No UIKit/SwiftUI. All decisions use fixed slot heights.

- [ ] **Step 1: Create `StoryPageLayout.swift` with constants and TOC logic**

```swift
// fastblog/Services/StoryPageLayout.swift

enum StoryPageLayout {

    // MARK: - Slot heights (points)
    static let pageContentHeight: CGFloat = 680
    static let footerHeight: CGFloat = 40
    static let dayHeaderHeight: CGFloat = 44
    static let dayCaptionShort: CGFloat = 56
    static let dayCaptionLong: CGFloat = 80
    static let placeTitleHeight: CGFloat = 32
    static let placeCaptionShort: CGFloat = 40
    static let placeCaptionLong: CGFloat = 64
    static let photoRowHeight: CGFloat = 200        // 1 or 2 photos
    static let overflowSlotHeight: CGFloat = 224    // label(24) + photos(200)
    static let tocHeaderHeight: CGFloat = 72
    static let tocRowHeight: CGFloat = 36

    // MARK: - Entry point
    static func buildPages(from content: StoryBookContent) -> [StoryPage] {
        var pages: [StoryPage] = []

        // 1. Cover
        pages.append(.cover(content.cover))

        // 2. TOC pages
        pages.append(contentsOf: buildTOCPages(overview: content.overview))

        // 3. Days
        let dayCount = content.days.count
        for (dayIdx, day) in content.days.enumerated() {
            let isLastDay = dayIdx == dayCount - 1

            // Map page (skip if no snapshot)
            if day.mapSnapshot != nil {
                pages.append(.dayMap(day))
            }

            // Content pages
            let nextDayName: String? = isLastDay ? nil : {
                let nextDay = content.days[dayIdx + 1]
                return nextDay.places.first?.title ?? "Day \(nextDay.dayNumber)"
            }()

            let contentPages = buildDayContentPages(
                day: day,
                isLastDay: isLastDay,
                nextDayName: nextDayName
            )
            pages.append(contentsOf: contentPages.map { .dayContent($0) })
        }

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
    private static func buildTOCPages(overview: BlogOverviewContent) -> [StoryPage] {
        // First pass: count pages
        let firstPageCapacity = Int((pageContentHeight - tocHeaderHeight) / tocRowHeight)
        let remaining = max(0, overview.entries.count - firstPageCapacity)
        let continuationCapacity = Int(pageContentHeight / tocRowHeight)
        let extraPages = remaining > 0 ? 1 + (remaining - 1) / continuationCapacity : 0
        let totalPages = 1 + extraPages

        // Second pass: emit pages
        var result: [StoryPage] = []
        var entryIndex = 0
        var pageIndex = 1

        while entryIndex < overview.entries.count {
            let capacity = pageIndex == 1 ? firstPageCapacity : continuationCapacity
            let slice = Array(overview.entries[entryIndex..<min(entryIndex + capacity, overview.entries.count)])
            result.append(.tableOfContents(
                entries: slice,
                overview: overview,
                pageIndex: pageIndex,
                totalPages: totalPages
            ))
            entryIndex += capacity
            pageIndex += 1
        }

        // Edge case: zero days
        if result.isEmpty {
            result.append(.tableOfContents(entries: [], overview: overview, pageIndex: 1, totalPages: 1))
        }

        return result
    }
}
```

- [ ] **Step 2: Add day content page builder**

Append this inside the `StoryPageLayout` enum, after `buildTOCPages`:

```swift
    // MARK: - Day content pages
    private static func buildDayContentPages(
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?
    ) -> [DayContentPage] {

        var allSlots: [ContentSlot] = []

        // Day caption (only emitted once — DayContentPageView shows it only on isFirstPage)
        if let caption = day.dayCaption {
            allSlots.append(.dayCaption(caption))
        }

        // Place slots
        for place in day.places {
            allSlots.append(contentsOf: slotsForPlace(place))
        }

        // Pack slots into pages
        return packSlots(allSlots, day: day, isLastDay: isLastDay, nextDayName: nextDayName)
    }

    private static func slotsForPlace(_ place: PlaceContent) -> [ContentSlot] {
        let photoCount = place.photos.count
        if photoCount == 0 {
            // Zero photos — renderer shows title + caption only; photoSlice is irrelevant
            // but ClosedRange requires lowerBound <= upperBound, so use 0...0 and guard in renderer
            return [.placeBlock(place, photoSlice: 0...0)]
        } else if photoCount <= 2 {
            return [.placeBlock(place, photoSlice: 0...(photoCount - 1))]
        } else {
            var result: [ContentSlot] = [.placeBlock(place, photoSlice: 0...1)]
            var idx = 2
            while idx < photoCount {
                let end = min(idx + 1, photoCount - 1)
                result.append(.photoOverflowContinuation(placeName: place.title, place, photoSlice: idx...end))
                idx += 2
            }
            return result
        }
    }

    // slotHeight: checks place.photos.isEmpty for zero-photo places to avoid adding photoRowHeight
    private static func slotHeight(_ slot: ContentSlot) -> CGFloat {
        switch slot {
        case .dayCaption(let text):
            return text.count > 80 ? dayCaptionLong : dayCaptionShort
        case .placeBlock(let place, _):
            var h: CGFloat = placeTitleHeight
            if let caption = place.caption {
                h += caption.count > 80 ? placeCaptionLong : placeCaptionShort
            }
            // Only add photo row height if the place actually has photos
            if !place.photos.isEmpty { h += photoRowHeight }
            return h
        case .photoOverflowContinuation:
            return overflowSlotHeight
        }
    }

    private static func packSlots(
        _ slots: [ContentSlot],
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?
    ) -> [DayContentPage] {

        var pages: [DayContentPage] = []
        var currentSlots: [ContentSlot] = []
        var usedHeight: CGFloat = dayHeaderHeight  // header is always on first page
        var isFirstPage = true
        var slotIdx = 0

        while slotIdx < slots.count {
            let slot = slots[slotIdx]
            let h = slotHeight(slot)

            if usedHeight + h > pageContentHeight && !currentSlots.isEmpty {
                // Close page
                pages.append(DayContentPage(
                    day: day,
                    isFirstPage: isFirstPage,
                    slots: currentSlots,
                    isLastPageOfDay: false,
                    isLastPageOfTrip: false,
                    nextDayName: nil
                ))
                currentSlots = []
                usedHeight = 0
                isFirstPage = false
            } else if usedHeight + h > pageContentHeight {
                // Single slot overflows fresh page — DEBUG safeguard
                #if DEBUG
                assertionFailure("StoryPageLayout: slot overflows fresh page — \(slot)")
                #endif
            }

            currentSlots.append(slot)
            usedHeight += h
            slotIdx += 1
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

        return pages
    }
```

- [ ] **Step 3: Build and fix any compile errors (⌘B)**

- [ ] **Step 4: Commit**

```bash
git add fastblog/Services/StoryPageLayout.swift
git commit -m "feat(story-mode): add StoryPageLayout pure layout engine"
```

---

## Task 2b: EC-2 Peek-Ahead Borrow (Space Optimization)

**Files:**
- Modify: `fastblog/Services/StoryPageLayout.swift`

The spec requires that when a first page of a day has room to spare after place 1, the engine borrows place 2's name/caption/photos onto that same page. This task adds that logic inside `packSlots`.

- [ ] **Step 1: Add a borrow helper inside `StoryPageLayout`**

In `StoryPageLayout.swift`, add this method after `slotsForPlace`:

```swift
    /// Returns borrow slots for place 2 if it fits on the current page after place 1.
    /// Only called on the first page of a day (isFirstPage == true) when place 1 has 0, 1, or 2 photos.
    private static func borrowSlots(for place: PlaceContent, remainingSpace: CGFloat) -> [ContentSlot] {
        let photoCount = place.photos.count
        let captionIsLong = (place.caption?.count ?? 0) > 80

        // Threshold: full borrow (name + caption + 2 photos = 32+40+200 = 272pt)
        let fullBorrowThreshold: CGFloat = 272
        // Threshold: name only (32pt)
        let nameOnlyThreshold: CGFloat = 32

        if remainingSpace >= fullBorrowThreshold {
            // Borrow name + caption + up to 2 photos
            if photoCount == 0 {
                return [.placeBlock(place, photoSlice: 0...0)]
            } else if photoCount <= 2 {
                return [.placeBlock(place, photoSlice: 0...(photoCount - 1))]
            } else {
                // Show 2, overflow continues on next page
                return [.placeBlock(place, photoSlice: 0...1)]
            }
        } else if remainingSpace >= nameOnlyThreshold && !captionIsLong {
            // Name only — create a name-only PlaceContent with no caption and no photos
            let nameOnly = PlaceContent(
                title: place.title,
                timestamp: place.timestamp,
                caption: nil,
                captionIsLong: false,
                photos: []
            )
            return [.placeBlock(nameOnly, photoSlice: 0...0)]
        }
        return []
    }
```

- [ ] **Step 2: Wire borrow into `packSlots`**

Inside `packSlots`, after the first place block's slots are added for the first page, add borrow logic. Replace the `while slotIdx < slots.count` loop with this updated version:

```swift
        var slotIdx = 0
        var didBorrowOnFirstPage = false

        while slotIdx < slots.count {
            let slot = slots[slotIdx]
            let h = slotHeight(slot)

            if usedHeight + h > pageContentHeight && !currentSlots.isEmpty {
                // Close page
                pages.append(DayContentPage(
                    day: day,
                    isFirstPage: isFirstPage,
                    slots: currentSlots,
                    isLastPageOfDay: false,
                    isLastPageOfTrip: false,
                    nextDayName: nil
                ))
                currentSlots = []
                usedHeight = 0
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
            // Only when: this is still the first page, we haven't already borrowed, and there is a next place
            if isFirstPage && !didBorrowOnFirstPage,
               case .placeBlock(let place1, _) = slot,
               slotIdx < slots.count,
               case .placeBlock(let place2, _) = slots[slotIdx] {

                // Only borrow for places with ≤ 2 photos on place 1 (not overflow slots)
                let p1PhotoCount = place1.photos.count
                guard p1PhotoCount <= 2 else { continue }

                let remaining = pageContentHeight - usedHeight
                let borrowed = borrowSlots(for: place2, remainingSpace: remaining)

                if !borrowed.isEmpty {
                    // Check that the next page (after borrow) can still fit ≥ 2 full place blocks
                    let borrowedHeight = borrowed.reduce(0) { $0 + slotHeight($1) }
                    // Skip borrow if it would leave the next page unable to fit two basic place blocks
                    let minNextPageHeight: CGFloat = (placeTitleHeight + photoRowHeight) * 2
                    let remainingAfterBorrow = pageContentHeight - borrowedHeight
                    if remainingAfterBorrow >= minNextPageHeight {
                        currentSlots.append(contentsOf: borrowed)
                        usedHeight += borrowedHeight
                        didBorrowOnFirstPage = true
                        // Advance past the borrowed place's first slot in the main slot list
                        slotIdx += 1
                    }
                }
            }
        }
```

- [ ] **Step 3: Build (⌘B) and fix any compile errors**

- [ ] **Step 4: Commit**

```bash
git add fastblog/Services/StoryPageLayout.swift
git commit -m "feat(story-mode): implement EC-2 peek-ahead borrow space optimization"
```

---

## Task 3: `StoryBookBuilder` — Content Builder

**Files:**
- Create: `fastblog/Services/StoryBookBuilder.swift`

Accesses `RecapBlogDetail` directly (including `placeStops` for map snapshots). Downsamples images.

- [ ] **Step 1: Create `StoryBookBuilder.swift`**

```swift
// fastblog/Services/StoryBookBuilder.swift
import UIKit
import Photos

enum StoryBookBuilder {

    static func build(from detail: RecapBlogDetail) async throws -> StoryBookContent {
        let cover = buildCover(detail)
        let overview = buildOverview(detail)
        let days = try await buildDays(detail)
        return StoryBookContent(cover: cover, overview: overview, days: days)
    }

    // MARK: - Cover
    private static func buildCover(_ detail: RecapBlogDetail) -> CoverContent {
        let dateRange = dateRangeString(from: detail.days)
        var coverImage: UIImage? = nil
        if let identifier = detail.selectedCoverPhotoIdentifier {
            coverImage = loadAndDownsample(localIdentifier: identifier)
        }
        return CoverContent(title: detail.title, subtitle: dateRange, coverPhoto: coverImage)
    }

    // MARK: - Overview (TOC)
    private static func buildOverview(_ detail: RecapBlogDetail) -> BlogOverviewContent {
        let dateRange = dateRangeString(from: detail.days)
        let entries: [TOCEntry] = detail.days.enumerated().map { idx, day in
            TOCEntry(
                dayNumber: idx + 1,
                date: day.shortDateText,
                firstPlaceName: day.placeStops.first?.placeTitle ?? "Day \(idx + 1)"
            )
        }
        return BlogOverviewContent(dateRange: dateRange, dayCount: detail.days.count, entries: entries)
    }

    // MARK: - Days
    private static func buildDays(_ detail: RecapBlogDetail) async throws -> [StoryDay] {
        var storyDays: [StoryDay] = []
        for (idx, day) in detail.days.enumerated() {
            // Map snapshot — 10s timeout
            let snapshot = await withTimeout(seconds: 10) {
                await MapSnapshotHelper.generateSnapshot(
                    for: day.placeStops,
                    size: CGSize(width: 390, height: 280)
                )
            }

            let places = buildPlaces(from: day.placeStops)

            storyDays.append(StoryDay(
                dayNumber: idx + 1,
                date: day.date,
                dayCaption: day.dayCaption,
                mapSnapshot: snapshot,
                places: places
            ))
        }
        return storyDays
    }

    // MARK: - Places
    private static func buildPlaces(from stops: [PlaceStop]) -> [PlaceContent] {
        stops.map { stop in
            let caption = stop.overallStory ?? stop.noteText
            let captionIsLong = (caption?.count ?? 0) > 80
            let photos = stop.photos
                .filter { $0.isIncluded }
                .compactMap { photo -> PhotoContent? in
                    guard let image = loadAndDownsample(localIdentifier: photo.localIdentifier) else { return nil }
                    let photoCaption = photo.caption
                    return PhotoContent(
                        image: image,
                        caption: photoCaption,
                        captionIsLong: (photoCaption?.count ?? 0) > 80
                    )
                }
            return PlaceContent(
                title: stop.placeTitle,
                timestamp: formattedTimestamp(stop.visitedTimeDigitized),
                caption: caption,
                captionIsLong: captionIsLong,
                photos: photos
            )
        }
    }

    // MARK: - Helpers
    private static func loadAndDownsample(localIdentifier: String) -> UIImage? {
        let options = PHFetchOptions()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: options)
        guard let asset = result.firstObject else { return nil }
        let targetSize = UIScreen.main.bounds.size
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .highQualityFormat
        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: reqOptions
        ) { img, _ in image = img }
        return image
    }

    private static func formattedTimestamp(_ digitized: String?) -> String? {
        guard let digitized else { return nil }
        let parts = digitized.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let timePart = String(parts[1])
        let components = timePart.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        let ampm = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    private static func dateRangeString(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = ", yyyy"
        return "\(fmt.string(from: first.date)) – \(fmt.string(from: last.date))\(yearFmt.string(from: last.date))"
    }

    // MARK: - Timeout helper
    private static func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
```

- [ ] **Step 2: Check that `RecapPhoto` has `isIncluded` and `caption` properties**

```bash
grep -n "isIncluded\|var caption\|localIdentifier" fastblog/Models/RecapBlogDetail.swift | head -20
```

If `RecapPhoto` uses different property names, update `buildPlaces` accordingly.

- [ ] **Step 3: Build (⌘B) and fix any compile errors**

- [ ] **Step 4: Commit**

```bash
git add fastblog/Services/StoryBookBuilder.swift
git commit -m "feat(story-mode): add StoryBookBuilder async content builder"
```

---

## Task 4: ViewModel

**Files:**
- Create: `fastblog/ViewModels/StoryBookViewModel.swift`

- [ ] **Step 1: Create `StoryBookViewModel.swift`**

```swift
// fastblog/ViewModels/StoryBookViewModel.swift
import SwiftUI

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
                let pages = StoryPageLayout.buildPages(from: content)
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
```

- [ ] **Step 2: Build (⌘B)**

- [ ] **Step 3: Commit**

```bash
git add fastblog/ViewModels/StoryBookViewModel.swift
git commit -m "feat(story-mode): add StoryBookViewModel state machine"
```

---

## Task 5: Leaf View Components

**Files:**
- Create: `fastblog/Views/StoryBook/PhotoCardView.swift`
- Create: `fastblog/Views/StoryBook/PageFooterView.swift`
- Create: `fastblog/Views/StoryBook/PlaceBlockView.swift`
- Create: `fastblog/Views/StoryBook/PhotoContinuationBlockView.swift`

- [ ] **Step 1: Create `PhotoCardView.swift`**

```swift
// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(3/4, contentMode: .fill)
                .clipped()

            if photo.captionIsLong, let caption = photo.caption {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            Group {
                if !photo.captionIsLong, let caption = photo.caption {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
            },
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Create `PageFooterView.swift`**

```swift
// fastblog/Views/StoryBook/PageFooterView.swift
import SwiftUI

struct PageFooterView: View {
    let isLastPageOfTrip: Bool
    let isLastPageOfDay: Bool
    let nextDayName: String?

    var body: some View {
        HStack {
            if let appIcon = UIImage(named: "AppIcon") {
                Image(uiImage: appIcon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            if isLastPageOfTrip {
                Text("The End")
                    .italic()
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if isLastPageOfDay, let nextDay = nextDayName {
                Text("\(nextDay) →")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("Next Page →")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}
```

- [ ] **Step 3: Create `PlaceBlockView.swift`**

```swift
// fastblog/Views/StoryBook/PlaceBlockView.swift
import SwiftUI

struct PlaceBlockView: View {
    let place: PlaceContent
    let photos: [PhotoContent]   // caller passes place.photos[photoSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                Text(place.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                Spacer()
                if let ts = place.timestamp {
                    Text(ts)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Caption
            if let caption = place.caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Photos
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        PhotoCardView(photo: photos[i])
                    }
                }
                .frame(
                    maxWidth: photos.count == 1 ? UIScreen.main.bounds.width * 0.5 : .infinity,
                    alignment: .leading
                )
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4: Create `PhotoContinuationBlockView.swift`**

```swift
// fastblog/Views/StoryBook/PhotoContinuationBlockView.swift
import SwiftUI

struct PhotoContinuationBlockView: View {
    let placeName: String
    let photos: [PhotoContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More from \(placeName)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(0..<photos.count, id: \.self) { i in
                    PhotoCardView(photo: photos[i])
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 5: Build (⌘B)**

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/StoryBook/PhotoCardView.swift \
        fastblog/Views/StoryBook/PageFooterView.swift \
        fastblog/Views/StoryBook/PlaceBlockView.swift \
        fastblog/Views/StoryBook/PhotoContinuationBlockView.swift
git commit -m "feat(story-mode): add leaf view components (PhotoCard, Footer, PlaceBlock, Continuation)"
```

---

## Task 6: Page Views

**Files:**
- Create: `fastblog/Views/StoryBook/CoverPageView.swift`
- Create: `fastblog/Views/StoryBook/TOCPageView.swift`
- Create: `fastblog/Views/StoryBook/DayMapPageView.swift`
- Create: `fastblog/Views/StoryBook/DayContentPageView.swift`

- [ ] **Step 1: Create `CoverPageView.swift`**

```swift
// fastblog/Views/StoryBook/CoverPageView.swift
import SwiftUI

struct CoverPageView: View {
    let cover: CoverContent

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top 65% — photo or gradient
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let photo = cover.coverPhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height * 0.65)
                                .clipped()
                        } else {
                            LinearGradient(
                                colors: [Color(hex: "#1a1a2e"), Color(hex: "#2d3561")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: geo.size.width, height: geo.size.height * 0.65)
                        }
                    }

                    // Gradient overlay on bottom 40% of photo area
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.65 * 0.4)

                    // Title & subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cover.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text(cover.subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Bottom 35% — white, app icon centered
                VStack(spacing: 8) {
                    Spacer()
                    if let appIcon = UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Bloggo")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.35)
                .background(Color.white)
            }
        }
        .ignoresSafeArea()
    }
}

// Hex color helper (if not already in the project)
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Check if a hex Color initializer already exists in the project**

```bash
grep -rn "init(hex" fastblog/ --include="*.swift" | head -5
```

If one already exists, remove the private extension from `CoverPageView.swift` to avoid duplication.

- [ ] **Step 3: Create `TOCPageView.swift`**

```swift
// fastblog/Views/StoryBook/TOCPageView.swift
import SwiftUI

struct TOCPageView: View {
    let entries: [TOCEntry]
    let overview: BlogOverviewContent
    let pageIndex: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (first page only)
            if pageIndex == 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip Overview")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(overview.dateRange)  ·  \(overview.dayCount) days")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(height: 72, alignment: .center)
                .padding(.horizontal, 16)
            }

            // Entry rows
            ForEach(entries, id: \.dayNumber) { entry in
                VStack(spacing: 0) {
                    HStack {
                        Text("Day \(entry.dayNumber)")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 50, alignment: .leading)
                        Text(entry.date)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(entry.firstPlaceName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 16)
                    Divider()
                }
            }

            Spacer()

            // Page indicator
            if totalPages > 1 {
                Text("\(pageIndex) / \(totalPages)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}
```

- [ ] **Step 4: Create `DayMapPageView.swift`**

```swift
// fastblog/Views/StoryBook/DayMapPageView.swift
import SwiftUI

struct DayMapPageView: View {
    let day: StoryDay

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Map snapshot — top 70%
                ZStack(alignment: .bottom) {
                    if let snapshot = day.mapSnapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height * 0.70)
                            .clipped()
                    } else {
                        Color.gray.opacity(0.2)
                            .frame(height: geo.size.height * 0.70)
                    }

                    // Subtle bottom-edge gradient bleeding into white strip
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.70 * 0.15)
                }

                // Day header strip — bottom 30%
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(day.dayNumber)")
                        .font(.system(size: 22, weight: .bold))
                    Text(day.shortDateText)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.30, alignment: .leading)
                .padding(.horizontal, 20)
                .background(Color.white)
            }
        }
        .ignoresSafeArea()
    }
}

// Give StoryDay access to shortDateText (already on RecapBlogDay — we need a helper here)
private extension StoryDay {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}
```

- [ ] **Step 5: Create `DayContentPageView.swift`**

```swift
// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI

struct DayContentPageView: View {
    let page: DayContentPage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header — only on first page of the day
            if page.isFirstPage {
                HStack {
                    Text("Day \(page.day.dayNumber)")
                        .font(.system(size: 18, weight: .bold))
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(page.day.shortDateText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(height: 44, alignment: .center)
            }

            // Slots
            ForEach(0..<page.slots.count, id: \.self) { i in
                slotView(page.slots[i])
            }

            Spacer()

            PageFooterView(
                isLastPageOfTrip: page.isLastPageOfTrip,
                isLastPageOfDay: page.isLastPageOfDay,
                nextDayName: page.nextDayName
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slotView(_ slot: ContentSlot) -> some View {
        switch slot {
        case .dayCaption(let text):
            Text(text)
                .italic()
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineLimit(4)

        case .placeBlock(let place, let photoSlice):
            let photos: [PhotoContent] = place.photos.isEmpty ? [] : {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PlaceBlockView(place: place, photos: photos)

        case .photoOverflowContinuation(let name, let place, let photoSlice):
            let photos: [PhotoContent] = {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PhotoContinuationBlockView(placeName: name, photos: photos)
        }
    }
}

private extension DayContentPage {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day.date)
    }
}
```

- [ ] **Step 6: Build (⌘B) and fix compile errors**

- [ ] **Step 7: Commit**

```bash
git add fastblog/Views/StoryBook/CoverPageView.swift \
        fastblog/Views/StoryBook/TOCPageView.swift \
        fastblog/Views/StoryBook/DayMapPageView.swift \
        fastblog/Views/StoryBook/DayContentPageView.swift
git commit -m "feat(story-mode): add page views (Cover, TOC, DayMap, DayContent)"
```

---

## Task 7: Root Container — `StoryBookView` and `StoryPageView`

**Files:**
- Create: `fastblog/Views/StoryBook/StoryPageView.swift`
- Create: `fastblog/Views/StoryBook/StoryBookView.swift`

- [ ] **Step 1: Create `StoryPageView.swift`**

```swift
// fastblog/Views/StoryBook/StoryPageView.swift
import SwiftUI

struct StoryPageView: View {
    let page: StoryPage

    var body: some View {
        switch page {
        case .cover(let cover):
            CoverPageView(cover: cover)
        case .tableOfContents(let entries, let overview, let pageIndex, let totalPages):
            TOCPageView(entries: entries, overview: overview, pageIndex: pageIndex, totalPages: totalPages)
        case .dayMap(let day):
            DayMapPageView(day: day)
        case .dayContent(let contentPage):
            DayContentPageView(page: contentPage)
        }
    }
}
```

- [ ] **Step 2: Create `StoryBookView.swift`**

```swift
// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI

struct StoryBookView: View {
    let detail: RecapBlogDetail
    @StateObject private var viewModel = StoryBookViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch viewModel.state {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text(detail.title)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

            case .ready(let pages):
                TabView {
                    ForEach(0..<pages.count, id: \.self) { i in
                        StoryPageView(page: pages[i])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

            case .failed:
                VStack(spacing: 20) {
                    Text("Could not load your trip.\nPlease try again.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        viewModel.build(from: detail)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }

            // Close button — always on top
            Button {
                viewModel.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(radius: 4)
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        .task {
            viewModel.build(from: detail)
        }
    }
}
```

- [ ] **Step 3: Build (⌘B)**

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/StoryBook/StoryPageView.swift \
        fastblog/Views/StoryBook/StoryBookView.swift
git commit -m "feat(story-mode): add StoryBookView and StoryPageView root container"
```

---

## Task 8: Wire Up Entry Point in `RecapBlogPageView`

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`

- [ ] **Step 1: Identify the `RecapBlogDetail` variable name and `@State` block**

Run this to confirm the variable that holds the blog detail in `RecapBlogPageView`:

```bash
grep -n "@State private var draft\|@State private var blog\|@State private var recap" fastblog/Views/RecapBlogPageView.swift | head -10
```

The variable is named `draft`. Confirm this before proceeding.

- [ ] **Step 2: Add the `@State` variable**

In `RecapBlogPageView`, add alongside the other `@State private var show...` properties (around line 112):

```swift
@State private var showStoryMode = false
```

- [ ] **Step 3: Add the `.fullScreenCover` modifier**

Find the block near line 250 where `.sheet(isPresented: $showPDFExportOptions)` is declared. Add the Story Mode cover **immediately after** that `.sheet` block:

```swift
.fullScreenCover(isPresented: $showStoryMode) {
    StoryBookView(detail: draft)
        .interactiveDismissDisabled(true)
}
```

`draft` is the `@State private var draft: RecapBlogDetail` property confirmed in Step 1.

- [ ] **Step 4: Add the Story Mode button**

Find the PDF export button (search for `showPDFExportOptions = true` — there is one around line 982 in the toolbar/action bar area). Add a Story Mode button **in the same HStack or menu** as the PDF export button, immediately before or after it:

```bash
grep -n "showPDFExportOptions = true" fastblog/Views/RecapBlogPageView.swift
```

Add adjacent to the PDF button:

```swift
Button {
    showStoryMode = true
} label: {
    Label("Story Mode", systemImage: "book.pages")
}
```

- [ ] **Step 5: Build (⌘B) and run on simulator**

Launch the app → open a blog → tap Story Mode. Verify:
- Loading spinner appears
- Pages load and are swipeable horizontally
- Close button dismisses

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat(story-mode): wire Story Mode entry point in RecapBlogPageView"
```

---

## Task 9: Polish and Edge Case Verification

- [ ] **Step 1: Test EC-3 (no day caption)** — open a blog day with no caption. Verify no caption block appears on the content page.

- [ ] **Step 2: Test EC-5 (no cover photo)** — remove the cover photo selection. Verify gradient placeholder shows on the cover page.

- [ ] **Step 3: Test EC-7 (no GPS)** — use a day with no place locations. Verify map page is skipped.

- [ ] **Step 4: Test EC-4 (last page footer)** — swipe to the very last page of the trip. Verify "The End" appears in the footer.

- [ ] **Step 5: Test EC-8 (long place name)** — verify a long place name wraps to 2 lines and timestamp stays top-right.

- [ ] **Step 6: Test single-photo alignment (EC-1)** — verify a place with 1 photo renders the card left-aligned (≤50% page width), not centered.

- [ ] **Step 7: Commit any polish fixes**

```bash
git add -u
git commit -m "feat(story-mode): polish and edge case fixes"
```

---

## Task 10: Final Integration Commit

- [ ] **Step 1: Full build + smoke test on device or simulator**

- [ ] **Step 2: Final commit**

```bash
git add .
git commit -m "feat(story-mode): complete horizontal book reader implementation"
```
