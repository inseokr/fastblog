# Carousel Composite Thumbnails — Design Spec
Date: 2026-06-24

## Problem

The download picker and slides management page both show slide thumbnails using `CarouselSlideView` with `showsBackgroundOnly: true`. This flag strips every overlay — text blocks, PIP photo clusters, split-slot photos, gradient scrims — leaving only the bare hero/map image. Slides with multi-photo PIP layouts appear as a single photo. Text is invisible.

The goal is Canva-style slide navigation: each thumbnail is a miniature but accurate composite of the full slide — hero photo, text, and layered inset photo cluster at their correct positions.

## Why the Architecture Already Supports This

All dimensions in `CarouselSlideView` are `width`-relative (e.g. `.font(.system(size: width * 0.085))`). All text block and PIP cluster offsets are stored as normalized fractions of `slideBounds` and multiplied back to points at render time (`savedPointOffset = CGSize(width: offset.width * slideBounds.width, height: offset.height * slideBounds.height)`). The same view already renders correctly at any size — from the full-screen editor to export — the flag was just telling it not to.

## What Was Tried Before (and Why It Broke)

Removing `showsBackgroundOnly` alone brings in `DraggableTextBlock` and `DraggablePIPCluster` with their full gesture machinery (drag, pinch, `@GestureState`, `naturalRect` capture via `GeometryReader`). In a `LazyVGrid` with many simultaneous thumbnails this causes scroll jank and mis-fires. That is why past attempts felt broken even when the visuals were right.

## Solution: `isStaticThumbnail` Mode

Add a single `isStaticThumbnail: Bool = false` flag that propagates from `CarouselSlideView` down to `DraggableTextBlock` and `DraggablePIPCluster`. When true, each draggable wrapper short-circuits its body to a plain display-only path — same content, same offset math, zero gestures.

## Changes

### 1. `DraggableTextBlock` (private struct)

Add `var isStaticThumbnail: Bool = false`.

```swift
var body: some View {
    if isStaticThumbnail {
        content()
            .offset(x: savedPointOffset.width, y: savedPointOffset.height)
    } else {
        // existing full interactive body — untouched
    }
}
```

`savedPointOffset` is already defined as `CGSize(width: savedOffset.width * slideBounds.width, height: savedOffset.height * slideBounds.height)`. The static branch reuses it directly, omitting the `liveDrag` addend (no in-flight gesture in this context). All `@State` / `@GestureState` vars remain declared but are never read in the static branch.

### 2. `DraggablePIPCluster` (private struct)

Add `var isStaticThumbnail: Bool = false`.

```swift
var body: some View {
    if isStaticThumbnail {
        PIPClusterView(
            images: images,
            pipPhotoIDs: pipPhotoIDs,
            slideWidth: slideWidth,
            borderColor: borderColor,
            visibleCount: visibleCount,
            stackStyle: stackStyle,
            pipSizeScale: pipSizeScale,
            thumbMaskStyle: thumbMaskStyle
        )
        .offset(x: savedPointOffset.width, y: savedPointOffset.height)
    } else {
        // existing full interactive body — untouched
    }
}
```

`PIPClusterView` is already the pure display layer inside `DraggablePIPCluster`. The static path calls it directly with the committed position — no cluster tap, no pinch, no selection ring.

### 3. `CarouselSlideView` (struct)

Add `var isStaticThumbnail: Bool = false`.

Thread it through to every `DraggableTextBlock` and `DraggablePIPCluster` instantiation inside `carouselSlideRoot` by adding `isStaticThumbnail: isStaticThumbnail` to each call site. No logic changes — pure pass-through.

### 4. `CarouselStudioDownloadStylePickCard` (private struct)

Both `CarouselSlideView` calls change from:
```swift
showsBackgroundOnly: true
```
to:
```swift
isStaticThumbnail: true
// showsBackgroundOnly removed — defaults to false
```

`showsBackgroundOnly` is left untouched everywhere else. The two flags are orthogonal: `showsBackgroundOnly` is for contexts that genuinely want background-only; `isStaticThumbnail` is for full-composite non-interactive display.

## Affected Pages

- **Download picker** — slides now show full composite with text + PIP cluster
- **Slides management page** — same; the existing `slidesManagementPIPStrip` workaround can be removed once confirmed working

## Out of Scope

- Export rendering (`BlogCarouselExportService`) — unaffected, uses `UIGraphicsImageRenderer` not `CarouselSlideView`
- Full-screen editor — unaffected, `isStaticThumbnail` defaults to `false`
- `showsBackgroundOnly` — flag and all its existing call sites are left as-is
