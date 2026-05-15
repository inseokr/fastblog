# Video Cover Page + Map Day Overlay — Design Spec

**Date:** 2026-05-01
**File:** `fastblog/Services/CinematicBlogVideoBuilder.swift`

---

## Summary

Two changes to the cinematic video builder:

1. **Add a cover page** as the very first frame of the video — full-bleed cover photo with centered blog metadata overlay.
2. **Remove the day intro card** and move day info (day number, date, city) to the bottom-left of the route overview map.

---

## Change 1 — Cover Page

### Location
`CinematicBlogVideoBuilder.buildFrames` — called once before the day loop.

### New method: `drawCoverPage(draft:pixelSize:coverImage:)`

**Frame duration:** 2.0 seconds (matches day intro card convention).

**Background:**
- If cover photo loads: full-bleed aspect-fill of the photo.
- Fallback (no cover photo): dark navy gradient — `#050A30` → `#02051E` top-to-bottom (same as day intro card).

**Scrim layers (when photo present):**
- Top: `black 0.45 → clear`, from top down ~20% of height.
- Bottom: `black 0.65 → clear`, from bottom up ~45% of height.

**Centered overlay stack (vertically + horizontally centered):**
1. "TRAVEL BLOG" — `w * 0.028` monospaced font, `#C8EBFF` at 70% opacity, letter-spacing `w * 0.006`.
2. `draft.title` — `w * 0.072` system font weight `.black`, white.
3. Thin divider — 40pt wide, `white 0.30`, 6pt vertical margin.
4. Date range — `w * 0.036` medium weight, `white 0.75`. Format: first day `monthDayStringForStoryBookRange()` → last day `monthDayStringForStoryBookRange() + yearSuffixForStoryBookRange()`. Example: "Jan 15 – Jan 22, 2025".
5. Stats row (16pt gap between items, with `white 0.20` vertical separators):
   - **N Moments** — count of all `PlaceStop`s across all days with `!placeStops.isEmpty`.
   - **N Photos** — count of `draft.allIncludedPhotos`.
   - Font: `w * 0.034` semibold for the number, `w * 0.026` regular for the label below it.

**Cover photo loading:**
- Use `draft.selectedCoverPhotoIdentifier` as `localIdentifier`.
- Load via the existing `loadPhoto` helper with a dummy `RecapPhoto` constructed from the identifier.
- If `selectedCoverPhotoIdentifier` is nil or photo fails to load, use the gradient fallback.

---

## Change 2 — Remove Day Intro Card, Move Info to Map

### Remove
- The `drawDayIntroCard` call and its 2.0s `frameHandler` emit in `buildFrames` (currently the first thing inside the day loop).
- `drawDayIntroCard` method itself can be deleted.

### Update `drawDayHeaderOverlay`

**Remove:**
- The top scrim gradient (currently `black 0.65 → clear` from top).

**Add:**
- Bottom scrim: `black 0.65 → clear`, from `h` up to `h * 0.72` (covers ~28% of height from bottom).

**Move text to bottom-left:**
- `bottomPad`: `h * 0.085` — air between the bottom edge and the text block.
- Draw order (bottom-up, so calculate from bottom):
  1. City/country line (optional): `day.placeStops.first?.placeSubtitle` — `w * 0.030` regular, `#C8EBFF` at 70% opacity.
  2. Date line: `day.shortDateText` — `w * 0.034` regular, `white 0.82`.
  3. "DAY N" label: `w * 0.052` bold, white.
- Left anchor: `x = 22`.
- Stack top-to-bottom: DAY N → date → city/country (if present).
- Total text block bottom edge sits at `h - bottomPad`.

---

## Data Used

| Field | Source |
|-------|--------|
| Cover photo | `draft.selectedCoverPhotoIdentifier` → `loadPhoto` |
| Blog title | `draft.title` |
| Date range | `draft.days.first` / `draft.days.last` → `monthDayStringForStoryBookRange()` + `yearSuffixForStoryBookRange()` |
| Moments count | `draft.days.filter { !$0.placeStops.isEmpty }.flatMap(\.placeStops).count` |
| Photos count | `draft.allIncludedPhotos.count` |
| Day number | Loop index + 1 (existing) |
| Day date | `day.shortDateText` (existing) |
| City/country | `day.placeStops.first?.placeSubtitle` |

---

## Video Sequence After Changes

```
[Cover page — 2.0s]
  For each day:
    [Route overview map with day info bottom-left — 2.5s]  ← day intro card removed
    For each place:
      [Pan frames — 14 × 0.18s]
      [Zoom blend frames — 14 × 0.14s]
      [Focused reveal with place overlay — 2.5s]
      [Photo slides — up to 5 × secondsPerPhoto]
```

---

## Files Changed

- `fastblog/Services/CinematicBlogVideoBuilder.swift` — only file touched.
