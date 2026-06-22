# Tab Swipe Navigation — Design Spec
**Date:** 2026-06-22
**Status:** Approved

## Overview

Add live-drag horizontal swipe navigation between the three home tabs:

```
[My Blogs] ←——— [Camera] ———→ [My Places]
```

- From Camera: swipe left → My Places, swipe right → My Blogs
- From My Blogs: swipe left → Camera
- From My Places: swipe right → Camera

"Live drag" means content physically follows the finger (pager feel), with a spring commit or snap-back on release.

---

## Scope

**Only `fastblog/ContentView.swift` changes.** No child view files are touched.

---

## Architecture

### Current (opacity switching)
The three home tabs sit in a `ZStack` and toggle via `opacity(homeTab == .x ? 1 : 0)` + `allowsHitTesting(homeTab == .x)`.

### New (offset pager)
Replace the opacity switch with `offset(x:)` so the three tab views physically live side by side:

```
position:  [-W]        [0]        [+W]
tab:    My Blogs    Camera    My Places
```

`swipeDragOffset` shifts all three simultaneously during a drag, producing the live pager feel. The `ZStack` gains `.clipped()` to keep off-screen content invisible.

**Overlays** (Trips, Blog Detail, Scan, toasts) stay at `x: 0` — they receive no tab offset and are completely unaffected.

---

## New State (ContentView)

```swift
@State private var swipeDragOffset: CGFloat = 0
@State private var swipeDragIsActive = false

private let tabOrder: [BottomNavTab] = [.myBlogs, .camera, .myPlaces]
```

### Tab offset helper

```swift
private func tabVisualOffset(for tab: BottomNavTab, screenWidth: CGFloat) -> CGFloat {
    let myIdx    = tabOrder.firstIndex(of: tab)     ?? 0
    let activeIdx = tabOrder.firstIndex(of: homeTab) ?? 1
    return CGFloat(myIdx - activeIdx) * screenWidth + swipeDragOffset
}
```

---

## homeTabsLayer Changes

Wrap the ZStack in a `GeometryReader` to obtain `screenWidth`. For each of the three tab views:

| Was | Becomes |
|-----|---------|
| `.opacity(homeTab == .x ? 1 : 0)` | `.offset(x: tabVisualOffset(for: .x, screenWidth: geo.size.width))` |
| `.allowsHitTesting(homeTab == .x)` | `.allowsHitTesting(homeTab == .x && !swipeDragIsActive)` |
| `.zIndex(homeTab == .x ? N : 0)` | `.zIndex(1)` (simplified — offset tabs never overlap) |

Add to the ZStack:
```swift
.clipped()
.simultaneousGesture(swipeGesture(screenWidth: geo.size.width))
```

Overlays retain their existing `if`-conditional rendering, x:0 position, and high z-indices (5, 10, 14, 15, 20).

---

## Gesture Logic

Attached with `.simultaneousGesture` (fires alongside child scroll views, not competing).

### onChanged
1. **Overlay guard:** if `!showsHomeChrome`, ignore entirely.
2. **Direction filter:** only activate if `|dx| > |dy| * 1.5` (clearly horizontal) or `swipeDragIsActive` is already true.
3. **Camera edge restriction:** if `homeTab == .camera && !swipeDragIsActive`, only proceed if `startLocation.x < 50 || startLocation.x > screenWidth - 50`. Protects tap-to-focus, pinch-to-zoom, and shutter controls.
4. Set `swipeDragIsActive = true`.
5. **Rubber-band at ends:** if dragging past My Blogs (left end) or My Places (right end), damp offset to `dx * 0.15`.
6. Otherwise: `swipeDragOffset = dx`.

### onEnded
1. Set `swipeDragIsActive = false`.
2. Compute `shouldCommit = |dx| > screenWidth * 0.35 || |predictedVelocityX| > 200`.
3. Determine `newTabIndex` (clamp to `0...2`).
4. **If committing to a new tab:**
   - `swipeDragOffset += (newTabIndex - oldTabIndex) * screenWidth` — preserves visual positions
   - Set `homeTab = tabOrder[newTabIndex]` with `disablesAnimations: true`
   - Animate `swipeDragOffset → 0` with `.spring(response: 0.35, dampingFraction: 0.85)`
5. **If snapping back:**
   - Animate `swipeDragOffset → 0` with same spring.

---

## selectHomeTab Safety Update

Add two resets at the top of `selectHomeTab(_:)` so any in-flight drag is cancelled before a programmatic tab switch:

```swift
private func selectHomeTab(_ tab: BottomNavTab) {
    swipeDragOffset = 0
    swipeDragIsActive = false
    // existing logic unchanged below
    cancelHomeBottomNavAutoHide()
    ...
}
```

---

## What Doesn't Change

- All three views remain always-mounted (no remounting on tab switch)
- Trips / Blog Detail / Scan overlays and their z-indices
- Camera bottom-nav auto-hide (`isHomeBottomNavRevealed`, `homeBottomNavAutoHideTask`)
- `suppressHomeBottomNav` logic
- `showsHomeChrome` and `isHomeBottomNavVisible` computed properties
- `BottomNavBar` component — unchanged; taps remain instant
- Every child view file — untouched

---

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Overlay appears mid-drag | `showsHomeChrome` becomes false; next `.onChanged` is ignored; on `.onEnded` snap back |
| Tap BottomNavBar tab | `selectHomeTab` resets offset to 0 instantly; switch is instant as before |
| Drag past end (e.g., left from My Blogs) | Rubber-band to 15% of drag; always snaps back |
| Horizontal carousel inside My Blogs/My Places | Carousel's gesture wins naturally; tab swipe not triggered |
| Camera UI (focus ring, zoom) | Edge-restriction (50pt) prevents activation from center of screen |
