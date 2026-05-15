# Unused Photo Triage Flow — Design Spec
Date: 2026-05-05

## Overview

When a user taps a photo in the Unused Photos gallery, they enter a sequential triage mode where they swipe or tap to decide the fate of each photo (delete or keep). The flow loops through all visible unused photos starting from the tapped photo and auto-dismisses back to the gallery when the loop completes.

## Architecture

### New component: `UnusedPhotoTriageView`

A new `private struct` added to `StorageManagementView.swift`. It does NOT replace `UnusedPhotosSlideshowView` — both coexist.

**Parameters:**

| Parameter | Type | Purpose |
|---|---|---|
| `photos` | `[RecapPhoto]` | Snapshot of visible unused photos at triage start |
| `startingPhotoId` | `UUID` | The photo the user tapped |
| `onDelete` | `(RecapPhoto) -> Void` | Delegates to existing delete flow in `StorageManagementView` |
| `onDismiss` | `() -> Void` | Called on loop complete or early exit |

### Changes to `StorageManagementView`

- Add `@State private var triageStartPhotoId: UUID?`
- In `photoCell`, on tap (non-select mode): set `triageStartPhotoId = photo.id`
- In the body `ZStack`, present `UnusedPhotoTriageView` (zIndex 40) when `triageStartPhotoId != nil`
- `onDismiss` sets `triageStartPhotoId = nil`
- The existing `UnusedPhotosSlideshowView` block (keyed on `fullScreenPhotoId`) is removed; `fullScreenPhotoId` state is no longer needed
- The existing slideshow struct itself remains in the file, unused for now

## Loop Logic

### Triage queue

On init, compute `triageQueue: [UUID]` — photo IDs ordered from the tapped photo's index, wrapping around to cover all photos exactly once:

```
photos[startIndex], photos[startIndex+1], ..., photos[last], photos[0], ..., photos[startIndex-1]
```

Example: 10 photos, user taps index 3 → queue indices = [3,4,5,6,7,8,9,0,1,2]

### Advancement

- `currentQueueIndex: Int` tracks position in `triageQueue`
- Keep action: `currentQueueIndex += 1` (no mutation to draft)
- Delete action: delegate to `onDelete`, then `currentQueueIndex += 1`
- When `currentQueueIndex == triageQueue.count`: loop complete, brief fade-out, call `onDismiss`

### Handling mid-loop deletions

When a photo is deleted, its UUID remains in `triageQueue` but will not resolve in the (now-updated) photos array passed from the parent. The view detects this and auto-advances to the next queue entry without showing a blank frame.

### Progress display

`"Photo \(currentQueueIndex + 1) of \(triageQueue.count)"` shown in the navigation bar center.

## Visual Layout

```
┌─────────────────────────────────┐
│ [X]          3 of 10            │  nav bar: X (dismiss early), progress center
├─────────────────────────────────┤
│                                 │
│                                 │
│         [  PHOTO  ]             │  full-width, aspectRatio(.fit)
│                                 │  draggable, offsets horizontally on drag
│                                 │  red tint overlay on left drag
│                                 │  green tint overlay on right drag
│                                 │  slight rotation: up to ±5 degrees
│   <- delete       keep ->       │  hint text, white.opacity(0.45), .footnote
├─────────────────────────────────┤
│  [ trash  Delete ] [ check Keep]│  two pill buttons, side by side
└─────────────────────────────────┘
```

### Swipe gesture (DragGesture)

- `minimumDistance: 20`
- `.onChanged`: offset photo horizontally, fade in color overlay (red left / green right), apply rotation up to ±5°
- `.onEnded`: if `|translation.width| > 80pt` → commit action (delete or keep); else spring back to center
- Direction: left = delete, right = keep

### CTA buttons

| Button | Style | Action |
|---|---|---|
| Delete | Red tint (`#FF4539`), `.ultraThinMaterial` bg, trash icon | Triggers `onDelete` then advances |
| Keep | White glass, `.ultraThinMaterial` bg, checkmark icon | Advances only |

Both buttons are full-width split (equal width), `56pt` tall, `cornerRadius: 14`.

### Animations

- Photo offset/color/rotation: `.interactiveSpring(response: 0.3, dampingFraction: 0.7)`
- Spring-back on cancelled drag: `.spring(response: 0.4, dampingFraction: 0.75)`
- Transition between photos: cross-fade `.easeInOut(duration: 0.2)`
- Loop complete: `.easeInOut(duration: 0.3)` fade-out before `onDismiss`

## First-time Tooltip

- `@AppStorage("bloggo.hasSeenUnusedPhotosTriageTooltip")` — separate key from existing gallery tooltip
- Shown on first entry to triage mode, over a dimming scrim
- Same `.ultraThinMaterial` card style as `UnusedPhotosIntroTooltipOverlay`
- **Title**: "Review Your Photos"
- **Body**: "Swipe left to delete or right to keep. We'll go through each one."
- **CTA**: "Got it" button — sets AppStorage to true, dismisses with `.easeInOut(duration: 0.25)`

## Out of Scope

- Re-including photos back into the blog (Keep = stay as unused, nothing more)
- Changing the existing `UnusedPhotosSlideshowView` behavior
- Batch keep/delete — decisions are per-photo, sequential
