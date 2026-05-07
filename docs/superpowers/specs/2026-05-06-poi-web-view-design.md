# POI Web View — Design Spec
**Date:** 2026-05-06

## Overview

When a user is viewing the Places Visited full-screen map or the Blog full-screen day map, they can tap any native MapKit POI (restaurant, museum, park, etc.) to see a Google Maps place page in a bottom sheet. This lets users explore what's around the places they actually visited without leaving the app.

## Scope

- **In scope:** `PlacesVisitedMapView` (inside `PlacesVisitedView.swift`) and the full-screen blog day map (`FullScreenMapView` inside `MapDayView.swift`)
- **Out of scope:** StoryBook/slideshow map pages (`DayMapPageView`), the thumbnail `MapDayView` used inline in blog timelines, `ProfileMapView`

## Architecture

### POI Selection

Both target maps use SwiftUI's `Map` view. Add a `@State private var selectedPOIFeature: MapFeature?` to each view and pass it via `Map(position:, selection:)`. MapKit fires this binding automatically when the user taps a native POI — no gesture recognizers needed. Requires iOS 17+, which is already the project's minimum deployment target.

### URL Construction

When `selectedPOIFeature` becomes non-nil, build a Google Maps search URL:

```
https://www.google.com/maps/search/?api=1&query=<encoded-place-name>&center=<lat>,<lng>
```

- `query` = `selectedPOIFeature.title` (URL-encoded)
- `center` = `selectedPOIFeature.coordinate.latitude`,`longitude`

This opens Google Maps in search mode focused on that place name near those coordinates — no API key required, works in WKWebView.

### POIInfoSheet

A new `POIInfoSheet` view (new file: `fastblog/Views/POIInfoSheet.swift`) presented via `.sheet(isPresented:)`. It contains:

- **Drag handle** — standard pill at top
- **Place name header** — `selectedPOIFeature.title` in bold, styled per the dark palette (`Color(white: 0.14)` background, `.white` text)
- **Done button** — top-right, dismisses the sheet
- **`GoogleSearchEmbeddedWebView`** — fills remaining space, loads the Google Maps URL. Reuses the existing component unchanged.

Sheet detent: `.medium` by default, with `.large` available via drag. This keeps the map visible in the medium state.

### Dismissal

- Tapping "Done" or dragging the sheet down sets `selectedPOIFeature = nil` and dismisses the sheet.
- `.onChange(of: selectedPOIFeature)` drives `showPOISheet`: set to `true` when non-nil, and clear `selectedPOIFeature` on sheet dismiss via `onDismiss:`.

## Components

| Component | Change |
|-----------|--------|
| `PlacesVisitedMapView` | Add `selectedPOIFeature` state + `selection:` param to `Map`; add `.sheet` for `POIInfoSheet` |
| `FullScreenMapView` (in `MapDayView.swift`) | Same as above |
| `POIInfoSheet` | New file — header + `GoogleSearchEmbeddedWebView` |
| `GoogleSearchEmbeddedWebView` | No changes — reused as-is |
| `fastblog.xcodeproj/project.pbxproj` | Register `POIInfoSheet.swift` per CLAUDE.md instructions |

## Data Flow

```
User taps POI on Map
  → MapKit sets selectedPOIFeature (MapFeature)
    → .onChange fires → showPOISheet = true
      → POIInfoSheet presented as .sheet
        → Builds google.com/maps URL from feature.title + coordinate
          → GoogleSearchEmbeddedWebView loads URL
User dismisses sheet (Done or drag)
  → onDismiss: selectedPOIFeature = nil, showPOISheet = false
```

## Error Handling

- If `selectedPOIFeature.title` is empty, use "Nearby Place" as the fallback query string.
- `GoogleSearchEmbeddedWebView` already handles navigation errors gracefully (WKNavigationDelegate).
- No offline handling needed — if there's no network, WKWebView shows its own error page.

## iOS Version

`MapFeature` and `Map(selection:)` require **iOS 17+**. Both target maps are already behind iOS 17 contexts in this codebase (they use other iOS 17 Map APIs), so no availability guard is needed.
