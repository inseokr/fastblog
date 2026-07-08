# POI Export — MapKit Geocoder Addition
**Date:** 2026-07-07

## Overview

Add `MKLocalPointsOfInterestRequest` as a second geocoding pass in `poi-export`, running after the existing CLGeocoder pass. Both sets of results appear as distinct columns in the same `labels.csv` and `dataset.json` row, enabling direct accuracy comparison between Apple's address geocoder and MapKit's POI database.

**Purpose:** Woo-Hyuk runs one tool invocation and gets CLGeocoder suggestions alongside MapKit POI suggestions. After Yoobin fills in `verified_place_name`, both geocoders can be benchmarked against ground truth in the same spreadsheet.

---

## Target Setup

- Same `poi-export` macOS Command Line Tool target — no new Xcode targets
- New source file: `Tools/POIExport/MapKitGeocoder.swift`
- `MapKit.framework` linked to the poi-export target (system framework, same pattern as `PhotosUI.framework` in the Bloggo iOS target)
- Minimum macOS version unchanged: 13.0

---

## Architecture

### Pipeline (updated)

```
EXIFExtractor.extractAll(from:)
  → ReverseGeocoder.geocode(records:log:)     ← CLGeocoder, unchanged
  → MapKitGeocoder.geocode(records:log:)      ← NEW: MKLocalPointsOfInterestRequest
  → DatasetExporter.export(records:logLines:)
  → DatasetExporter.copyPhotos(records:)
```

`main.swift` adds one `await MapKitGeocoder.geocode(records: &mutableRecords, log: &allLog)` call between the two existing geocoder calls. No other changes to `main.swift`.

### Components

| File | Change |
|------|--------|
| `Tools/POIExport/MapKitGeocoder.swift` | New — `MKLocalPointsOfInterestRequest` wrapping |
| `Tools/POIExport/EXIFExtractor.swift` | Add 4 new `var` fields to `PhotoRecord` |
| `Tools/POIExport/DatasetExporter.swift` | Add 4 new columns to CSV + JSON |
| `Tools/POIExport/main.swift` | Add one `await MapKitGeocoder.geocode(...)` call |
| `fastblog.xcodeproj/project.pbxproj` | Register `MapKitGeocoder.swift`; add `MapKit.framework` to poi-export framework phase |

`ReverseGeocoder.swift` is untouched.

---

## Data Model

Four new optional fields added to `PhotoRecord` in `EXIFExtractor.swift`:

```swift
var mapkitPlaceName: String?
var mapkitCategory: String?   // e.g. "Restaurant", "Cafe"
var mapkitCity: String?
var mapkitCountry: String?
```

---

## MapKit Geocoder (`MapKitGeocoder.swift`)

### Signature

```swift
import Foundation
import MapKit
import CoreLocation

struct MapKitGeocoder {
    static let searchRadiusMeters: Double = 75

    static func geocode(records: inout [PhotoRecord], log: inout [String]) async
}
```

### Per-record logic

1. If `latitude`/`longitude` are nil → skip silently (ReverseGeocoder already logged `[SKIP] — no GPS` for this photo)
2. Build `MKLocalPointsOfInterestRequest(center: coordinate, radius: searchRadiusMeters)`
3. `try await MKLocalSearch(request: request).start()`
4. From `response.mapItems`, pick the closest item where `item.name` is non-nil and non-empty, and whose distance from the photo's coordinate is ≤ `searchRadiusMeters`
5. If no qualifying item found → leave four MapKit fields nil, no log line (null fields in output communicate this)
6. If a qualifying item found → populate:
   - `mapkitPlaceName`: `item.name`
   - `mapkitCategory`: `item.pointOfInterestCategory?.rawValue` with `MKPOICategory` prefix stripped (e.g. `"MKPOICategoryRestaurant"` → `"Restaurant"`); nil if no category
   - `mapkitCity`: `item.placemark.locality ?? item.placemark.administrativeArea`
   - `mapkitCountry`: `item.placemark.country`
7. On `MKLocalSearch` error → log `[WARN-MK] <filename> — MapKit search failed: <error.localizedDescription>`, leave four fields nil, continue
8. Sleep 500ms before the next call (skip after the last record)

### Rate limiting

500ms between calls. MapKit is a local on-device framework (not a remote API), so the strict 1500ms CLGeocoder limit does not apply. A shorter delay still prevents hammering the local search index on large batches.

### Category string trimming

`MKPointOfInterestCategory.rawValue` returns strings like `"MKPOICategoryRestaurant"`, `"MKPOICategoryCafe"`. Strip the leading `"MKPOICategory"` prefix for readability in the dataset.

```swift
let raw = category.rawValue   // "MKPOICategoryRestaurant"
let trimmed = raw.hasPrefix("MKPOICategory")
    ? String(raw.dropFirst("MKPOICategory".count))
    : raw
// → "Restaurant"
```

---

## Output Format

### labels.csv — updated column order

```
filename, latitude, longitude, timestamp, camera_model,
suggested_place_name, suggested_city, suggested_country,
mapkit_place_name, mapkit_category, mapkit_city, mapkit_country,
verified_place_name, notes
```

`verified_place_name` and `notes` remain at the end — no change to Yoobin's manual entry workflow.

Nil MapKit fields → empty CSV field (same rule as existing nil fields).

### dataset.json — updated schema

Four new keys added to every JSON object. Nil → `null` (not omitted), consistent with existing fields.

```json
{
  "filename": "IMG_0042.heic",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "timestamp": "2026-06-15T14:23:01",
  "camera_model": "iPhone 15 Pro",
  "suggested_place_name": "Blue Bottle Coffee",
  "suggested_city": "San Francisco",
  "suggested_country": "United States",
  "mapkit_place_name": "Blue Bottle Coffee",
  "mapkit_category": "Cafe",
  "mapkit_city": "San Francisco",
  "mapkit_country": "United States",
  "verified_place_name": "",
  "notes": ""
}
```

### export_log.txt — unchanged format

The summary line and existing `[OK]` / `[SKIP]` / `[WARN]` / `[ERROR]` prefixes are unchanged. MapKit errors use `[WARN-MK]` as a distinct prefix so they can be grepped separately if needed. The summary line does not add a MapKit count — the quality of MapKit results is visible in the data itself.

---

## Xcode Registration

New UUIDs (all `BBCC0XXX` range, continuing from the original target registration — verified not used in existing project):

| ID | Purpose |
|----|---------|
| `BBCC0012` | PBXFileReference — `MapKit.framework` |
| `BBCC0013` | PBXBuildFile — `MapKit.framework` in poi-export Frameworks phase |
| `BBCC0014` | PBXFileReference — `MapKitGeocoder.swift` |
| `BBCC0015` | PBXBuildFile — `MapKitGeocoder.swift` in poi-export Sources phase |

**`project.pbxproj` changes:**
1. Add `BBCC0012` PBXFileReference: `{lastKnownFileType = wrapper.framework; name = MapKit.framework; path = System/Library/Frameworks/MapKit.framework; sourceTree = SDKROOT;}`
2. Add `BBCC0013` PBXBuildFile referencing `BBCC0012`
3. Add `BBCC0014` PBXFileReference for `MapKitGeocoder.swift`
4. Add `BBCC0015` PBXBuildFile referencing `BBCC0014`
5. Add `BBCC0015` to `BBCC000B` (poi-export PBXSourcesBuildPhase)
6. Add `BBCC0013` to `BBCC000C` (poi-export PBXFrameworksBuildPhase)
7. Add `BBCC0014` to `BBCC000A` (POIExport PBXGroup)

---

## Error Handling Summary

| Scenario | Behaviour |
|----------|-----------|
| Photo has no GPS | Skip silently — no duplicate log (already logged by ReverseGeocoder) |
| No POI within 75m | MapKit fields null in output; no log line |
| `MKLocalSearch` throws | `[WARN-MK] <filename> — MapKit search failed: <error>`, continue |
| Item found but name is nil or empty | Skip that item, continue to next closest; if none qualify, leave MapKit fields nil |

---

## Build & Verify

```bash
# Build
xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build

# Bloggo iOS regression
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build
```

Both must pass. The Bloggo target is unaffected by these changes.
