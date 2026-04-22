# Split Photo Action Menu — Design Spec
Date: 2026-04-20

## Overview
Replace the ambiguous "Reposition" toolbar button in Carousel Studio's SPLIT layout with a tap-to-select + contextual bottom action menu pattern, matching the visual style of the existing text block toolbar. Also fix two minor issues in `SplitBottomPhotoPickerSheet`.

---

## A — Split photo tap → bottom action toolbar

### Selection state
- Add `@State private var selectedSplitSlot: SplitRepositionSlot?` to `CarouselStudioSheet`.
- Tapping the **top half** of a split slide → `selectedSplitSlot = .top`; deselects any `selectedBlock`.
- Tapping the **bottom half** of a split slide → `selectedSplitSlot = .bottom`; deselects any `selectedBlock`. (No longer immediately opens the picker.)
- Changing slide, deselecting, or selecting a text block → `selectedSplitSlot = nil`.
- A subtle highlight ring (white, low opacity stroke) renders around the selected half.

### CarouselSlideView additions
- Add `onTapSplitTopSlot: (() -> Void)?` callback (mirrors existing `onTapSplitBottomSlot`).
- Add `selectedSplitSlot: SplitRepositionSlot?` param to render selection highlight.
- Wire `onTapSplitTopSlot` to a `TapGesture` on the top half (same pattern as the existing bottom-half tap target).

### Bottom toolbar (`splitPhotoActionToolbar`)
Shown when `selectedSplitSlot != nil` and `layout == .split`. Replaces no existing toolbar — appears as a new content branch in the bottom chrome's `safeAreaInset`.

Style: identical to `textFormattingToolbar` — `Color(white: 0.08)` background, capsule buttons with `.padding(.horizontal, 14).padding(.vertical, 7)`, `.font(.system(size: 13, weight: .semibold))`.

Three buttons in a single `HStack`:

| Button | Icon | Top slot | Bottom slot |
|--------|------|----------|-------------|
| Crop | `crop` | Open `SplitPhotoRepositionCover` for `.top` | Open `SplitPhotoRepositionCover` for `.bottom` |
| Replace | `photo.badge.arrow.up.fill` | Open hero-swap picker (`showsHeroPhotoSwapSheet`) | Open `SplitBottomPhotoPickerSheet` |
| Remove | `trash` | Disabled, grayed out (opacity 0.4) | Clear bottom slot (`clearSplitBottomPhoto`) |

### splitToolsRow changes
Remove the "Reposition" `Label` button. Keep Swap and Straight/Curve divider.

---

## B — "Clear" button position fix

`SplitBottomPhotoPickerSheet`: change Clear `ToolbarItem` placement from `.navigationBarLeading` → `.navigationBarTrailing`.

---

## C — Modal background color

`SplitBottomPhotoPickerSheet`:
- Replace `Color(red: 5/255, green: 10/255, blue: 48/255)` with `Color(uiColor: .systemGroupedBackground)` for both `.background(…)` and `.toolbarBackground(…, for: .navigationBar)`.
- Remove `.preferredColorScheme(.dark)` and `.tint(.white)`.
- Change explicit `white` / `white.opacity` text colors to `.primary` / `.secondary` so they adapt to the system appearance.
