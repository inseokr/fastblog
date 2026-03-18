# Vibe First-Time Tooltip — Design Spec

**Date:** 2026-03-17
**Status:** Approved

---

## Overview

Show a two-slide pull-up modal the first time a user enables the Vibe feature in the in-app camera. The modal explains what Vibe is (slide 1) and how it works (slide 2). It is shown exactly once — never again after dismissal.

---

## Trigger

**File:** `fastblog/Views/TripsView.swift`
**Struct:** `CameraCaptureView` (private struct)

Add an `.onChange(of: vibeEnabled)` modifier on the camera view using the iOS 17 two-parameter closure form:

```swift
.onChange(of: vibeEnabled) { _, newValue in
    if newValue && !hasSeenVibeTooltip {
        showVibeTooltip = true
    }
}
```

The one-parameter form is deprecated on this project's iOS 17 deployment target and must not be used.

> **Note:** The existing `showCameraTooltip` / `hasSeenCameraTooltip` variables in `CameraCaptureView` can be referenced for the sheet layout structure only — the camera tooltip's trigger (`showCameraTooltip = true`) is never actually set anywhere in the file and is non-functional. The `.onChange` approach here is the authoritative trigger pattern.

**New state properties on `CameraCaptureView`:**
```swift
@AppStorage("bloggo.hasSeenVibeTooltip") private var hasSeenVibeTooltip = false
@State private var showVibeTooltip = false
@State private var vibeTooltipPage = 0
```

`hasSeenVibeTooltip` is set to `true` in the sheet's `onDismiss` closure. `vibeTooltipPage` resets to `0` on dismiss so the sheet always starts at slide 1 if somehow re-triggered. Both the slide 2 CTA (which sets `showVibeTooltip = false` programmatically) and a manual drag-dismiss will invoke `onDismiss`; both paths are safe because all assignments in `onDismiss` are idempotent.

---

## Modal

Presented as a `.sheet` with:
- `.presentationDetents([.medium])`
- `.presentationDragIndicator(.visible)`
- `.preferredColorScheme(.dark)`

### Layout (both slides)

```
┌─────────────────────────────────────┐
│ 1/2  (or 2/2)                       │  ← .caption, .secondary, top-left
│                                     │
│         [ waveform icon ]           │  ← SF Symbol "waveform", cyan, 50×50
│                                     │
│           Title                     │  ← .title2, .bold, .primary, centered
│           Body text                 │  ← .body, .secondary, centered
│                                     │
│  [         Continue          ]      │  ← full-width blue button
└─────────────────────────────────────┘
```

Outer padding: `.horizontal 24`, `.top 24`, `.bottom 24`.

### Slide 1

- Counter: `"1/2"`
- Icon: `waveform`, `.foregroundColor(.cyan)`
- Title: `"Capture the Vibe"`
- Body: `"Record the sounds and atmosphere around your moment. From ocean waves to busy city streets, Bloggo helps preserve the feeling of where you were."`
- CTA: `"Continue"` → sets `vibeTooltipPage = 1`

### Slide 2

- Counter: `"2/2"`
- Icon: `waveform`, `.foregroundColor(.cyan)`
- Title: `"How It Works"`
- Body: `"We're constantly listening when you open the camera, so start capturing the vibe today!"`
- CTA: `"Continue"` → sets `showVibeTooltip = false`

---

## Content Swap Animation

When advancing from slide 1 to slide 2, the content swaps using `.animation(.easeInOut(duration: 0.25), value: vibeTooltipPage)` with a `.transition(.opacity)` on the content block. No `TabView` — clean state-driven swap.

---

## Implementation

**File to modify:** `fastblog/Views/TripsView.swift` only. No new files.

1. Add three state properties to `CameraCaptureView` (after existing vibe state vars, ~line 1835).
2. Add `.onChange(of: vibeEnabled)` modifier to the camera view body.
3. Add `.sheet(isPresented: $showVibeTooltip, onDismiss: { ... })` modifier with the two-slide content.
4. Extract slide content into a private `vibeTooltipContent` view property to keep `body` readable.

---

## Non-Goals

- No re-showing the tooltip after dismissal
- No skip button — user must tap Continue on both slides
- No network calls
- No different content for signed-in vs signed-out users
