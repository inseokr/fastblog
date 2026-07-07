# Bug: "Setting up place details…" — In-App Camera Place Editor

## What's happening

When you tap the place name in the camera preview to correct the location, you sometimes see **"Setting up place details…"** instead of the editor opening. Reproducible near dense areas (Fisherman's Wharf) and intermittent/weak signal zones (bay, ferry).

## Root cause

`canOpenCaptionModePlaceEditor` ([TripsView.swift:4442](fastblog/Views/TripsView.swift#L4442)) gates the editor on two conditions:
- `moment.injectedPhotoId != nil`
- `moment.localIdentifier != nil`

`injectedPhotoId` is set **inside an async Task**, only **after** `GeocodingService.shared.place(for:)` resolves. If the user taps before geocoding finishes, the gate blocks them.

### What geocoding does here
Reverse-geocodes the GPS coordinate to get a human-readable `locationName` (e.g. "Fisherman's Wharf") and `countryName` to attach to the `MockPhoto` in the blog. It has nothing to do with saving the photo, rendering the map, or the GPS coordinate itself.

### Why it's worse in certain conditions

| Condition | Race window |
|---|---|
| Intermittent signal (bay, ferry) | Several seconds — geocoder hangs waiting |
| Dense urban area + rapid shots | 1–3s — serial geocode queue backs up |
| Normal connectivity, single shot | 300–800ms — normal async round trip |
| Airplane mode | < 100ms — geocoder fails fast |

## The fix (Option C — agreed approach)

**Set `injectedPhotoId` before the geocoding await**, not after. Decouple the gate from geocoding completion.

The `EditPlaceStopNameSheet` only needs:
1. `CLLocationCoordinate2D` — from device GPS, available immediately ✅
2. `localIdentifier` — set synchronously before the async Task ✅
3. `injectedPhotoId` — only used in `onSave` to write back to the store

By the time the user opens the editor, browses the map, edits the name, and taps Save (typically 5–30s), the geocoding + injection Task will have completed. The save write is always safe in practice.

### Behaviour after fix
- Map loads correctly (GPS coordinate, no geocoding dependency)
- Pin placed at exact photo location
- Place name may briefly say "Captured Moment" if tapped < 1s after shooting — the sheet auto-resolves this itself via `PlacePlaceholderNaming.isResolvablePlaceholder` in `handleOnAppear`
- Save writes correctly to the blog store

## Files to change

- [TripsView.swift:6400–6426](fastblog/Views/TripsView.swift#L6400) — `injectCapturedImageIntoBlog`: move `m.injectedPhotoId = momentId` to before the `await GeocodingService` call
- [TripsView.swift:6444–6471](fastblog/Views/TripsView.swift#L6444) — `injectCapturedPhotoIntoCameraDraft`: same move for `m.injectedPhotoId = photoId`
- [TripsView.swift:4442](fastblog/Views/TripsView.swift#L4442) — `canOpenCaptionModePlaceEditor`: verify gate still makes sense after restructure
