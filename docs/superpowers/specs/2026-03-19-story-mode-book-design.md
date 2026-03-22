# Story Mode — Book Reader Design Spec

**Date:** 2026-03-19
**Branch:** pdfstyle
**Status:** Approved for implementation

---

## Overview

Story Mode is a horizontal, page-based book reader for Bloggo trip journals. It is a separate product experience from PDF Mode. Both modes share the same source data (`RecapBlogDetail`) but use entirely different rendering systems.

| Mode | Job | Output |
|------|-----|--------|
| PDF Mode | Export artifact | Shareable vertical PDF via existing `PDFExportService` (unchanged) |
| Story Mode | Immersive reading | In-app horizontal book reader (SwiftUI `TabView` with `.page` style) |

`StoryBookContent` is Story Mode's internal normalized model. It is **not** consumed by `PDFExportService`. PDF Mode continues using `RecapBlogDetail` directly. Future integration of the shared model into PDF Mode is out of scope.

---

## Architecture

Data flows in one direction:

```
RecapBlogDetail
    ↓  StoryBookBuilder (async)
StoryBookContent
    ↓  StoryPageLayout (synchronous, pure value types)
[StoryPage]
    ↓  StoryBookView / StoryPageView
SwiftUI rendered pages
```

---

### 1. Story Content Model — `StoryBookContent`

```swift
struct StoryBookContent {
    let cover: CoverContent
    let overview: BlogOverviewContent
    let days: [StoryDay]
}

struct CoverContent {
    let title: String
    let subtitle: String           // e.g. "March 12–19, 2025"
    let coverPhoto: UIImage?       // nil → gradient placeholder (EC-5)
}

struct BlogOverviewContent {
    let dateRange: String          // e.g. "March 12–19, 2025"
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
    let dayCaption: String?        // nil → skip caption block (EC-3)
    let mapSnapshot: UIImage?      // nil → skip map page (EC-7)
    let places: [PlaceContent]
}

struct PlaceContent {
    let title: String
    let timestamp: String?
    let caption: String?
    let captionIsLong: Bool        // caption.count > 80 chars
    let photos: [PhotoContent]
}

struct PhotoContent {
    let image: UIImage             // pre-downsampled to screen resolution
    let caption: String?
    let captionIsLong: Bool        // caption.count > 80 chars
}
```

#### Caption length rule

Computed once in `StoryBookBuilder` and stored in `captionIsLong`: **long** if `caption.count > 80`, **short** otherwise. Both the layout engine and the renderer use this pre-computed flag — neither re-measures text.

- Short place caption: plain text above photos, `lineLimit(2)`
- Long place caption: plain text above photos, `lineLimit(2)` (same display; `captionIsLong` only matters for slot height calculation in the engine)
- Short photo caption: plain text below the photo
- Long photo caption: white text overlaid on a `LinearGradient(.clear → .black.opacity(0.7))` on the bottom 40% of the photo

#### Image loading strategy

`StoryBookBuilder` downsamples all `UIImage` values to `UIScreen.main.bounds` × `UIScreen.main.scale` via `UIGraphicsImageRenderer` (`.aspectFit`) before storing. **Known limitation**: all visited images remain in memory simultaneously; image eviction is out of scope for v1. `TabView(.page)` on iOS 16+ renders pages lazily, which mitigates this for unvisited pages.

---

### 2. Layout Engine — `StoryPageLayout`

Pure synchronous value-type engine. Input: `StoryBookContent`. Output: `[StoryPage]`. No UIKit/SwiftUI calls.

#### Fixed slot heights (points)

| Slot | Height (pt) |
|------|------------|
| Page content area (footer excluded) | 680 |
| Page footer | 40 |
| **Total page height** | **720** |
| Day content header (day number + date) | 44 |
| Day caption — short (≤80 chars) | 56 |
| Day caption — long (>80 chars) | 80 |
| Place title row | 32 |
| Place caption — short (≤80 chars) | 40 |
| Place caption — long (>80 chars) | 64 |
| Single photo (3:4, left-aligned) | 200 |
| Two photos side-by-side (3:4) | 200 |
| Photo overflow label | 24 |
| `photoOverflowContinuation` slot (label + 1–2 photos) | 224 |
| TOC entry row | 36 |
| TOC header (title + date range) | 72 |

Engine tracks `usedHeight` per page. When adding the next slot would push `usedHeight > 680`, close the page and open a new one.

**DEBUG safeguard**: If `usedHeight == 0` and a single slot already exceeds 680pt, emit `assertionFailure("StoryPageLayout: slot overflows fresh page")` and emit it anyway (prevent infinite loop).

#### Page data types

```swift
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
    let nextDayName: String?   // non-nil only when isLastPageOfDay == true && isLastPageOfTrip == false
}

enum ContentSlot {
    case dayCaption(String)
    case placeBlock(PlaceContent, photoSlice: ClosedRange<Int>)
    case photoOverflowContinuation(placeName: String, PlaceContent, photoSlice: ClosedRange<Int>)
}
```

**`isFirstPage` rule**: Set to `true` on the first `DayContentPage` emitted per day; `false` on all subsequent pages for the same day.

**`isLastPageOfDay` rule**: Set to `true` on the final `DayContentPage` emitted per day.

**`nextDayName` rule**: Always `nil` when `isLastPageOfTrip == true`. Set to the next day's first place name (or "Day N" if no places) only when `isLastPageOfDay == true && isLastPageOfTrip == false`.

#### Photo slot usage in PlaceBlockView

`placeBlock(placeContent, photoSlice: lo...hi)` means the renderer displays `placeContent.photos[lo...hi]`. The renderer accesses exactly those indices — no other photos from `placeContent.photos` are shown for this slot. `photoOverflowContinuation` works the same way using its embedded `PlaceContent` and `photoSlice`.

#### Page sequence

1. **Cover** — always first
2. **TOC** — paginated (see TOC pagination below)
3. **Per day** (in day order):
   a. Map page — omitted if `mapSnapshot == nil` (EC-7)
   b. First content page: day header (44) + optional day caption + first place block
   c. Additional pages: remaining place blocks + overflow continuations
4. `isLastPageOfTrip = true` on the final `DayContentPage`

#### TOC pagination

TOC header (72pt) is placed first. Then `TOCEntry` rows (36pt each) are added sequentially. When adding the next row would exceed 680pt, close the page, open a new TOC page (no header on continuation pages), and continue. `totalPages` is computed in a first pass before emitting.

#### Photo slots per place

- **0 photos**: title + caption slots; apply EC-2 borrow
- **1 photo**: `photoSlice: 0...0`, left-aligned (EC-1)
- **2 photos**: `photoSlice: 0...1`, side-by-side
- **3+ photos**: emit `placeBlock` with `photoSlice: 0...1`; emit one or more `photoOverflowContinuation` slots (each covering `photoSlice: n...(n+1)`, repeating until all photos are placed)

#### Space optimization — peek-ahead borrow

After placing place 1's slots, compute `remainingSpace = 680 - usedHeight`. Borrow place 2 onto this page only if `remainingSpace` meets the threshold AND the resulting next page can still fit at least two full place blocks (EC-2 guard).

| Place 1 photos | Place 1 caption | Minimum `remainingSpace` | Borrow action |
|---|---|---|---|
| 0 | Short/none | 272pt | Place 2: title(32) + caption(40) + 2 photos(200) |
| 0 | Long | 272pt | Place 2: title(32) + caption(40) + 2 photos(200) |
| 1 | Short | 272pt | Place 2: title(32) + caption(40) + 2 photos(200) |
| 1 | Long | 32pt | Place 2: title only (32) |
| 2 | Short | 32pt | Place 2: title only (32) |
| 2 | Long | — | No borrow |
| 3+ | Any | — | No borrow (overflow slots already fill the page) |

---

### 3. Renderer — `StoryBookView`

SwiftUI view hierarchy. No vertical scrolling within pages. All pages are fixed-height (`UIScreen.main.bounds.height`).

#### Entry point

"Story Mode" button in `RecapBlogPageView` presents `StoryBookView` as `.fullScreenCover`. Not accessible from `PDFExportOptionsSheet`.

#### State machine

```swift
@MainActor
class StoryBookViewModel: ObservableObject {
    enum State {
        case loading
        case ready([StoryPage])
        case failed(Error)
    }
    @Published var state: State = .loading
    func build(from detail: RecapBlogDetail) async { ... }
}
```

**Loading**: centered `ProgressView` + trip title. `StoryBookBuilder` accepts the original `RecapBlogDetail` as input and accesses `recapBlogDetail.days[n].placeStops` directly to call `MapSnapshotHelper.generateSnapshot(for placeStops:size:)` (existing at `fastblog/Services/MapSnapshotHelper.swift`) before constructing the normalized `StoryDay`. GPS/coordinate data is never stored in `StoryBookContent` — it is only used transiently during the build phase to produce `mapSnapshot: UIImage?`. Each snapshot has a **10-second per-day timeout**; timeout → `mapSnapshot = nil` (EC-7 applies).

**Error**: message *"Could not load your trip. Please try again."* + **Retry** button + **Close** button.

#### View hierarchy

```
StoryBookView
├── Close button (×) — top-right, zIndex above TabView
└── TabView(.page, indexDisplayMode: .never)
    └── ForEach(pages) { StoryPageView($0) }
```

`interactiveDismissDisabled(true)` on the `.fullScreenCover` to prevent swipe-down conflicting with horizontal paging.

#### StoryPageView

Switches on `StoryPage`:
- `.cover` → `CoverPageView`
- `.tableOfContents` → `TOCPageView`
- `.dayMap` → `DayMapPageView`
- `.dayContent` → `DayContentPageView`

---

### 4. Page Layout Specs

#### CoverPageView

Full-screen, no footer.

- **With cover photo**: photo fills the top 65% of the screen (full-width, `.aspectFill`, clipped). A `LinearGradient(.black.opacity(0) → .black.opacity(0.85))` overlays the bottom 40% of the photo. Trip title in white, bold, 28pt, bottom-left of photo area. Subtitle (date range) in white, 14pt, below title.
- **Without cover photo (EC-5)**: top 65% is a `LinearGradient` using the app's primary brand color (deep navy `#1a1a2e` → `#2d3561`). Title and subtitle positioned the same way, in white.
- Bottom 35%: white background. App icon (40×40) centered horizontally, vertically centered in this region. Small tagline "Bloggo" in secondary color below icon.

#### TOCPageView

- **Header** (72pt): "Trip Overview" — bold, 20pt. Date range and day count on a second line — 13pt, secondary color.
- **Entry rows** (36pt each): `HStack` — left: `"Day \(N)"` bold 13pt, center/right: date in secondary color 12pt, rightmost: `firstPlaceName` in secondary color 12pt, truncated with `lineLimit(1)`. Subtle divider line between rows.
- **Page indicator**: bottom-center, `"\(pageIndex) / \(totalPages)"` in 11pt secondary color. Hidden if `totalPages == 1`.

#### DayMapPageView

Full-screen map page, no footer.

- **Map snapshot**: fills the top 70% of the screen, full-width, `.aspectFill`, clipped.
- **Day header strip** (bottom 30%, white background): "Day \(dayNumber)" — bold, 22pt. Date below in secondary color, 15pt. Left-padded 20pt.
- A subtle `LinearGradient(.clear → .black.opacity(0.3))` overlays the bottom 15% of the map image, bleeding into the white strip.

#### DayContentPageView

```
VStack(spacing: 0) {
    if isFirstPage { DayContentHeaderView }
    ForEach(slots) {
        switch slot {
        case .dayCaption(let text): DayCaptionView(text)   // engine emits this only on isFirstPage
        case .placeBlock(let place, let photoSlice): PlaceBlockView(place, photos: place.photos[photoSlice])
        case .photoOverflowContinuation(let name, let place, let photoSlice): PhotoContinuationBlockView(name, place, photos: place.photos[photoSlice])
        }
    }
    Spacer()
    PageFooterView
}
.padding(.horizontal, 16)
.padding(.top, 12)
```

**DayContentHeaderView**: "Day \(N)" in bold 18pt + date in secondary color 13pt, displayed as a single row at the top.

**DayCaptionView**: Italic, 14pt, secondary color. `lineLimit(4)` with truncation. Only rendered via the `ForEach(slots)` path below — never rendered directly in the VStack. The layout engine always emits a `.dayCaption` slot when `isFirstPage == true && dayCaption != nil`. The VStack does not contain a separate `DayCaptionView` guard; all slot rendering goes through `ForEach(slots)`.

#### PlaceBlockView

```
VStack(alignment: .leading, spacing: 6) {
    HStack(alignment: .top) {
        Image(systemName: "mappin") — 10pt
        Text(title).font(.system(size: 13, weight: .bold)).lineLimit(2)
        Spacer()
        Text(timestamp).font(.system(size: 11)).foregroundColor(.secondary)  // top-aligned
    }
    if let caption { Text(caption).font(.system(size: 12)).lineLimit(2) }
    HStack(spacing: 8) {
        ForEach(photos) { PhotoCardView($0) }  // 1 card left-aligned (EC-1), 2 side-by-side
    }
    .frame(maxWidth: photos.count == 1 ? UIScreen.main.bounds.width * 0.5 : .infinity,
           alignment: .leading)
}
```

#### PhotoContinuationBlockView

Renders a `photoOverflowContinuation` slot:

```
VStack(alignment: .leading, spacing: 6) {
    Text("More from \(placeName)")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
    HStack(spacing: 8) {
        ForEach(photos) { PhotoCardView($0) }
    }
}
```

#### PhotoCardView

3:4 aspect ratio. Rounded corners (8pt radius). `.aspectFill` image. If `captionIsLong`: overlay a `ZStack` with `LinearGradient(.clear → .black.opacity(0.7))` on the bottom 40%, then caption text in white 10pt. If `!captionIsLong`: plain `Text` below, 10pt secondary color.

#### PageFooterView

40pt fixed height. `HStack`:

- Left: app icon from `Assets.xcassets/AppIcon` — 20×20, `RoundedRectangle(cornerRadius: 4)` clip
- Spacer
- Right (evaluated in order):
  1. `isLastPageOfTrip == true` → `Text("The End").italic().foregroundColor(.secondary)` (EC-4)
  2. `isLastPageOfDay == true` (and `!isLastPageOfTrip`) → `Text("\(nextDayName!) →").font(.system(size: 12, weight: .medium))`
  3. Otherwise → `Text("Next Page →").font(.system(size: 12)).foregroundColor(.secondary)`

---

## Edge Cases Reference

| EC | Scenario | Behavior |
|----|----------|----------|
| EC-1 | 1 photo for a place | Left-aligned, max 50% page width |
| EC-2 | 0 photos + space ≥ threshold | Borrow next place: title + caption + ≤2 photos |
| EC-2b | Borrowed place has 3+ photos | Show 2 + `photoOverflowContinuation` |
| EC-3 | No day caption | Skip caption slot |
| EC-4 | Last page of trip | Footer: icon + *"The End"* |
| EC-5 | No cover photo | Gradient placeholder in brand colors |
| EC-6 | TOC overflows | Additional TOC pages with page index indicator |
| EC-7 | Day has no GPS | `mapSnapshot == nil` → skip map page |
| EC-8 | Long place name | `lineLimit(2)`, timestamp top-right |

---

## What Is NOT Changing

- `PDFExportService`, `PDFExportOptionsSheet`, `PDFPreviewSheet`
- `MapSnapshotHelper` — used as-is (`fastblog/Services/MapSnapshotHelper.swift`)
- `RecapBlogDetail` and all existing models

---

## New Files

| File | Purpose |
|------|---------|
| `Models/StoryBookContent.swift` | `StoryBookContent`, `StoryDay`, `PlaceContent`, `PhotoContent`, `CoverContent`, `BlogOverviewContent`, `TOCEntry` |
| `Models/StoryPage.swift` | `StoryPage`, `DayContentPage`, `ContentSlot` |
| `Services/StoryBookBuilder.swift` | Async builder: `RecapBlogDetail` → `StoryBookContent` |
| `Services/StoryPageLayout.swift` | Synchronous layout engine: `StoryBookContent` → `[StoryPage]` |
| `ViewModels/StoryBookViewModel.swift` | `@MainActor ObservableObject`; state machine |
| `Views/StoryBook/StoryBookView.swift` | Root `.fullScreenCover`; close button; state routing |
| `Views/StoryBook/StoryPageView.swift` | Dispatches to correct page view |
| `Views/StoryBook/CoverPageView.swift` | Cover page |
| `Views/StoryBook/TOCPageView.swift` | Table of contents |
| `Views/StoryBook/DayMapPageView.swift` | Day map page |
| `Views/StoryBook/DayContentPageView.swift` | Day content pages |
| `Views/StoryBook/PlaceBlockView.swift` | Place title + caption + photos |
| `Views/StoryBook/PhotoContinuationBlockView.swift` | "More from [Place]" overflow block |
| `Views/StoryBook/PhotoCardView.swift` | Single photo card with caption |
| `Views/StoryBook/PageFooterView.swift` | App icon + navigation label |
