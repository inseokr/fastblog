# Undo Button in Toolbar — Design Spec

**Date:** 2026-04-06
**Scope:** `RecapBlogPageView` edit mode only

---

## Overview

Move the undo affordance from a persistent bottom overlay into a toolbar button that lives next to the Save button. The existing `UndoOverlayView` is repurposed as a simple 3-second confirmation toast shown only after the user taps Undo.

---

## Toolbar

In edit mode, the trailing toolbar contains two items (left to right): **Undo** then **Save**.

### Undo Button
- Icon: `arrow.uturn.backward` SF Symbol, `.body.weight(.semibold)`
- **Enabled** (when `lastUndoAction != nil`): foreground color `.white`
- **Disabled** (when `lastUndoAction == nil`): foreground `.white.opacity(0.3)`, `.disabled(true)` — visually dead, non-tappable
- Placement: `ToolbarItem(placement: .topBarTrailing)` — inserted before the existing Save `ToolbarItem`

### Save Button
- Unchanged from current implementation.

---

## Undo Action Flow

When the Undo button is tapped:
1. Capture `lastUndoAction?.text` into a local variable before clearing state
2. Call `performUndo()` (existing logic, unchanged)
3. Clear `showUndoOverlay` and `lastUndoAction`
4. Set `showUndoToast = true` with the captured description text
5. `DispatchQueue.main.asyncAfter(deadline: .now() + 3)` sets `showUndoToast = false`

---

## Toast Component

`UndoOverlayView` is simplified into a new `UndoToastView`:
- Displays only the description text (e.g. "Place deleted", "Photo removed")
- No internal Undo button
- No minimized/expanded state
- Same capsule visual style as the existing expanded `UndoOverlayView`
- Same bottom positioning, same `.move(edge: .bottom).combined(with: .opacity)` transition
- Auto-dismissed after 3 seconds — no manual dismiss needed

---

## Removals

- The `if showUndoOverlay { UndoOverlayView(...) }` block is removed from `RecapBlogPageView`'s overlay stack in edit mode
- `isUndoMinimized` state variable can be removed
- `UndoOverlayView` (the original component) remains for `CountryBlogsView` and `SplitBlogView` — only its usage in `RecapBlogPageView` is replaced by `UndoToastView`

---

## Out of Scope

- `CountryBlogsView` and `SplitBlogView` undo overlays — untouched
- Any undo stack beyond single-action (current behavior preserved)
