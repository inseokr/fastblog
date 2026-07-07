# POI Dataset Export Tool — Design Spec
**Date:** 2026-07-07

## Overview

A macOS Command Line Tool (`poi-export`) that reads a folder of original iPhone photos, extracts EXIF metadata and GPS coordinates, reverse-geocodes each location via `CLGeocoder`, and exports a labeled dataset template for POI accuracy testing.

**Purpose:** Woo-Hyuk uses this to build a ground-truth dataset for testing Bloggo's POI detection accuracy. Yoobin manually fills in `verified_place_name` after export.

---

## Target Setup

- New **macOS Command Line Tool** Xcode target named `poi-export` inside `Bloggo.xcodeproj`
- Source lives in `Tools/POIExport/` at the project root (not inside `fastblog/`)
- No shared code with the iOS app target
- Minimum macOS version: 13.0 (Ventura) — required for `CLGeocoder` async/await APIs

---

## Architecture

### Components

| File | Responsibility |
|------|---------------|
| `main.swift` | CLI entry: parse argument, orchestrate pipeline, print summary |
| `EXIFExtractor.swift` | Read image files via `ImageIO`, extract GPS + timestamp + camera model |
| `ReverseGeocoder.swift` | Wrap `CLGeocoder` with sequential rate-limiting (1.5s delay between calls) |
| `DatasetExporter.swift` | Write `labels.csv`, `dataset.json`, `export_log.txt`, copy photos |

No shared mutable state between components. `main.swift` calls them in sequence.

### Data Model

```swift
struct PhotoRecord {
    let filename: String
    let sourcePath: URL
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?      // ISO 8601 from DateTimeOriginal
    let cameraModel: String?    // e.g. "iPhone 15 Pro"

    // filled in after geocoding
    var suggestedPlaceName: String?
    var suggestedCity: String?
    var suggestedCountry: String?

    // left blank for manual ground-truth entry
    let verifiedPlaceName: String = ""
    let notes: String = ""
}
```

---

## Invocation

```
poi-export /path/to/photos
```

- Input: path to a folder of images (passed as the first CLI argument)
- Output: `POI_Test_Dataset/` created in the same parent directory as the input folder
- If `POI_Test_Dataset/` already exists at the destination, the tool aborts with a clear error — no silent overwrite

---

## EXIF Extraction (`EXIFExtractor.swift`)

Uses `ImageIO` (`CGImageSourceCreateWithURL` + `CGImageSourceCopyPropertiesAtIndex`) to read raw metadata dictionaries without decoding pixel data. A 50 MB ProRAW file costs essentially no memory.

**Supported extensions:** `.jpg`, `.jpeg`, `.heic`, `.png`

**Keys extracted:**
- GPS: `kCGImagePropertyGPSDictionary` → latitude, latitudeRef, longitude, longitudeRef (ref applied to produce signed decimal)
- Timestamp: `kCGImagePropertyExifDictionary` → `kCGImagePropertyExifDateTimeOriginal` → formatted as ISO 8601
- Camera model: `kCGImagePropertyTIFFDictionary` → `kCGImagePropertyTIFFModel`

Files with unreadable/corrupt metadata still produce a `PhotoRecord` with nil GPS, timestamp, and camera fields — they are not skipped. Truly unreadable files (corrupt container, unsupported format) are skipped entirely and logged.

---

## Geocoding Pipeline (`ReverseGeocoder.swift`)

Sequential `async` function called from `main.swift` inside `Task { }.value`.

For each `PhotoRecord`:
1. If `latitude`/`longitude` are nil → skip geocoding, log `[SKIP] <filename> — no GPS`
2. Call `CLGeocoder().reverseGeocodeLocation(_:)` with `async/await`
3. Extract from the first `CLPlacemark`:
   - `suggestedPlaceName`: `pm.name` if it looks like a venue (not a street address), else `pm.subLocality`, else `pm.locality`
   - `suggestedCity`: `pm.locality ?? pm.administrativeArea`
   - `suggestedCountry`: `pm.country`
4. Sleep 1.5 seconds before the next geocoding call (`Task.sleep(for: .milliseconds(1500))`)
5. On geocoding failure: log `[WARN] <filename> — geocoding failed: <CLError>`, leave three fields nil, continue

**Venue name heuristic:** re-implements the same logic as `GeocodingService.bestPlaceLabel` inline (the CLI cannot import the iOS app's service). Prefer `pm.name` only if it is non-empty, distinct from `subLocality`/`locality`, and does not look like a street address (no leading digit). This ensures the suggested labels reflect what the app itself would produce, making accuracy comparison meaningful.

**Rate limit:** Apple enforces ~50 CLGeocoder requests/minute. At 1.5s per call, the tool caps at 40/minute — safely under the limit with headroom for slow responses.

---

## Export (`DatasetExporter.swift`)

### Output folder structure
```
POI_Test_Dataset/
├── photos/           ← verbatim copies of original images
├── labels.csv
├── dataset.json
└── export_log.txt
```

### labels.csv
RFC 4180 compliant. One header row, then one row per photo. Fields containing commas or double-quotes are wrapped in double-quotes; internal quotes escaped as `""`. Nil values written as empty fields.

Column order:
```
filename,latitude,longitude,timestamp,camera_model,suggested_place_name,suggested_city,suggested_country,verified_place_name,notes
```

`verified_place_name` and `notes` are always blank — left for manual entry.

### dataset.json
JSON array of objects with the same fields. Encoded with `JSONEncoder` set to `.prettyPrinted`. Nil fields are written as `null` (not omitted) so schema is consistent across all rows.

### export_log.txt
One line per event. Prefix codes:
- `[OK]` — file processed successfully
- `[SKIP]` — unsupported extension or no GPS (included in output with blank fields)
- `[WARN]` — geocoding failed (included in output with blank geocode fields)
- `[ERROR]` — file unreadable, skipped entirely

Final line: `Summary: X photos processed, Y geocoded, Z skipped (no GPS), W errors`

### Photo copying
`FileManager.copyItem(at:to:)` — verbatim copy, no recompression, no metadata stripping, no rename. Destination filename matches source filename exactly.

---

## Error Handling Summary

| Scenario | Behavior |
|----------|----------|
| No CLI argument | Print usage and exit with code 1 |
| Input path doesn't exist or isn't a directory | Print error and exit with code 1 |
| Output folder already exists | Print error and exit with code 1 |
| Unsupported file extension | Skip, log `[SKIP]` |
| Corrupt/unreadable image | Skip entirely, log `[ERROR]` |
| Photo has no GPS | Include in output with blank GPS/geocode fields, log `[SKIP]` |
| CLGeocoder failure | Include with blank geocode fields, log `[WARN]`, continue |
| File copy failure | Log `[ERROR]`, continue with remaining files |

---

## Xcode Project Registration

New target requires additions to `fastblog.xcodeproj/project.pbxproj`:
- New `PBXNativeTarget` for `poi-export` (macOS Command Line Tool)
- `PBXBuildFile` + `PBXFileReference` entries for each `.swift` file under `Tools/POIExport/`
- `PBXGroup` entry for `Tools/POIExport/`
- Separate `PBXSourcesBuildPhase` scoped to the new target only

The new target must **not** include any `fastblog/` source files in its build phase.

---

## Build & Run

```bash
# Build
xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build

# Run (binary lands in Xcode's derived data products dir; find it with:)
find ~/Library/Developer/Xcode/DerivedData -name poi-export -type f | head -1
```
