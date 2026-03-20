# PDF Stop Card Redesign

**Date:** 2026-03-19
**Scope:** Per-stop card layout improvements in `PDFExportService.swift` and `PDFExportOptionsSheet.swift`
**Out of scope:** Trip summary page, cover page changes, map snapshot changes

---

## Goals

- Fix text running full card width (unreadable on long captions)
- Add meaningful typography hierarchy (title / location / caption)
- Introduce two user-selectable layout modes: Normal and Story
- Improve photo grid rules for 1, 2, 3, 4+ photos
- Keep photos square (1:1) — no change to aspect ratio
- Tighten page-break cohesion so header + first photo row never split

---

## New Data Model

Add `layoutMode` to `PDFExportOptions`:

```swift
enum PDFLayoutMode: String, CaseIterable, Codable {
    case normal = "Normal"
    case story  = "Story"
}

struct PDFExportOptions: Codable, Equatable {
    var blogColor:         BlogColor            = .white
    var fontTheme:         FontTheme            = .classic
    var photoShapeOptions: PDFPhotoShapeOptions = PDFPhotoShapeOptions()
    var layoutMode:        PDFLayoutMode        = .normal   // NEW
}
```

---

## PDF Options Sheet

Add a new **Layout Style** section to `PDFExportOptionsSheet` (between Font Style and Photo Style) with two radio rows:

- **Normal** — "Caption above photos"
- **Story** — "Photos first, caption below"

Uses the same `optionRow` component already in the sheet.

---

## Typography Hierarchy

Applied identically in both modes:

| Element        | Size | Weight   | Color         |
|---------------|------|----------|---------------|
| Place title   | 17pt | semibold | primaryText   |
| Location      | 12pt | regular  | secondaryText |
| Caption/story | 14pt | regular  | secondaryText |
| Photo caption | 11pt | regular  | secondaryText |

Badge: 32pt circular (up from 28pt), colors unchanged (green/blue/orange).

---

## Card Structure — Normal Mode

```
[badge 32pt] [title 17pt bold]
             [location 12pt gray]
             [caption 14pt, max-width = cardInteriorW - 42]
─────────────────────────── thin separator (0.5pt) ───────────────────
[photo grid, indented 42pt from cardLeft]
```

Dimensions:
- `cardLeft = pen.margin + cardPadding` — the interior left edge of the card
- Badge is 32pt wide; gap between badge and title text is 10pt → text indent = 42pt
- Caption is indented 42pt from `cardLeft` to align with title text
- Caption max-width: `cardInteriorW - 42 = 466pt`
- Thin separator (0.5pt line, separatorColor) between caption block and photos; vertical spacing: 8pt above, 8pt below the line — total separator block = 17pt
- If no caption: omit separator, photos follow header directly with 8pt gap
- **Photo grid is NOT indented** — photos always start at `cardLeft` with full `cardInteriorW = 508pt` available, preserving `photoSize = 249pt`. The 42pt indent applies to text blocks only (title, location, caption). `indent = 0` is passed to `drawPhotoGrid` in Normal mode.

---

## Card Structure — Story Mode

```
[badge 32pt] [title 17pt bold]
             [location 12pt gray]

[photo grid — full card width, no indent]

────────────── STORY ──────────────  (centered label + rules)

[caption block, full card width, 14pt, no line limit]
```

- Photos render immediately below header at full `cardInteriorW` width; `indent = 0` passed to `drawPhotoGrid`
- Per-photo captions appear below each photo row as in Normal mode (before the STORY rule)
- If a stop has **zero photos**: skip the photo grid and STORY separator; render the caption block directly below the header (same as Normal mode). The STORY separator never renders without photos.
- If a stop has photos but **no `overallStory` caption**: render photos normally, skip the STORY separator and caption block entirely.
- Separator after photos (only when both photos and caption exist): `drawSeparator(pen:style:.story, color:separatorColor)` — thin lines flanking a centered "STORY" label in 9pt gray caps; total height = 17pt
- Caption below separator, full `cardInteriorW` width, no line limit

---

## Photo Grid Rules

Applies inside both modes (indented in Normal, full-width in Story):

| Photo count | Layout |
|-------------|--------|
| 1           | Half-width, left-aligned (same `photoSize` as paired column) |
| 2           | Side-by-side pair |
| 3           | Pair on row 1, single (half-width left) on row 2 |
| 4+          | Rows of 2; last row follows rule above if odd count |

`photoSize` unchanged: `(cardInteriorW - photoGap) / 2 ≈ 249pt` width and height (1:1 square).

---

## Page-Break Cohesion

`ensureRoom` cohesion block must include: `cardPadding + headerHeight + separatorHeight + firstPhotoRowHeight + cardPadding`.

- `separatorHeight = 17pt` in both modes (1pt line + 8pt top + 8pt bottom)
- **Normal mode:** `headerHeight = titleH + 2 + locationH + 8 + captionH`; caption height capped at 68pt for cohesion purposes (same cap the existing code uses for story snippets), using `estimateTextHeight`. The cohesion sum is `cardPadding + headerHeight + separatorHeight + firstPhotoRowHeight + cardPadding` — `separatorHeight` appears only here, not embedded in `headerHeight`.
- **Story mode:** `headerHeight = titleH + 2 + locationH`; `firstPhotoRowHeight = photoSize + 10`. The STORY-label separator comes after photos so it is excluded from the cohesion block.
- Cap total cohesion height at 60% of usable page height (existing rule, keep as-is)

---

## Implementation Plan

### Files to change

- `fastblog/Services/PDFExportService.swift`
- `fastblog/Views/PDFExportOptionsSheet.swift`

### Approach: two dedicated draw functions

`drawPlaceStopCard` becomes a router:

```swift
private static func drawPlaceStopCard(...) {
    switch options.layoutMode {
    case .normal: drawNormalStopCard(...)
    case .story:  drawStoryStopCard(...)
    }
}
```

Each function is self-contained and reads top-to-bottom. Shared helpers:

```swift
// Badge + title + location text block
private static func drawStopHeader(
    pen: inout Pen, stop: PlaceStop, number: Int,
    badgeColor: UIColor, options: PDFExportOptions,
    primaryText: UIColor, secondaryText: UIColor
)

// Photo grid rows + per-photo captions
// indent: CGFloat offset from cardLeft (42 in Normal, 0 in Story)
private static func drawPhotoGrid(
    pen: inout Pen, photos: [(RecapPhoto, UIImage)],
    indent: CGFloat, cardLeft: CGFloat,
    options: PDFExportOptions, secondaryText: UIColor
)

enum SeparatorStyle {
    case thin   // 0.5pt line only — used between caption and photos in Normal mode
    case story  // lines + centered "STORY" label — used in Story mode
}

// total vertical advance: thin = 1 + 8 + 8 = 17pt; story = 1 + 8 + 8 = 17pt
private static func drawSeparator(
    pen: inout Pen, style: SeparatorStyle, color: UIColor,
    cardLeft: CGFloat
)
```

All helpers take the full color/option parameter set rather than a subset, to avoid signature churn as the feature evolves. The `cardBgColor` parameter stays on the two top-level draw functions for the continuation-background logic (not passed to helpers).

---

## What Does Not Change

- Cover page
- Day header + day caption
- Map snapshot
- Photo shapes (rounded/circle/etc.)
- Blog color (white/black) palette
- Font themes (classic/serif/rounded)
- `photoSize` (square 1:1)
