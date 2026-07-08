# POI Export — MapKit Geocoder Addition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second geocoding pass to the `poi-export` CLI tool using `MKLocalPointsOfInterestRequest`, so `labels.csv` / `dataset.json` carry both CLGeocoder and MapKit POI suggestions in the same row for accuracy comparison.

**Architecture:** New `MapKitGeocoder.swift` runs after the existing `ReverseGeocoder` pass in `main.swift`, mutating the same `[PhotoRecord]` array in place. `PhotoRecord` gets four new optional fields; `DatasetExporter` gains four new CSV/JSON columns. No existing geocoder code changes.

**Tech Stack:** Swift, Foundation, MapKit (`MKLocalSearch`, `MKLocalPointsOfInterestRequest`), CoreLocation. macOS Command Line Tool target, no third-party dependencies, no test target exists for this tool — verification is via `xcodebuild` compilation and manual smoke-run, matching the existing pattern for this target.

## Global Constraints

- Same `poi-export` macOS Command Line Tool target — no new Xcode targets.
- Minimum macOS version unchanged: 13.0.
- `ReverseGeocoder.swift` is untouched.
- Search radius: 75 meters (`MapKitGeocoder.searchRadiusMeters`).
- Rate limit between `MKLocalSearch` calls: 500ms (not CLGeocoder's 1500ms — MapKit is local, not remote).
- MapKit errors log with `[WARN-MK]` prefix (distinct from CLGeocoder's `[WARN]`), so they're separately greppable.
- No GPS → skip silently, no new log line (ReverseGeocoder already logged `[SKIP] — no GPS` for that photo).
- No qualifying POI within radius → leave four fields `nil`, no log line.
- Nil MapKit fields render as empty string in CSV and `null` in JSON (never omitted).
- `verified_place_name` and `notes` stay as the last two CSV/JSON columns — Yoobin's manual workflow is unaffected.
- Xcode UUIDs for new entries: `BBCC0012` (MapKit.framework file ref), `BBCC0013` (MapKit.framework build file), `BBCC0014` (MapKitGeocoder.swift file ref), `BBCC0015` (MapKitGeocoder.swift build file) — confirmed unused in current `project.pbxproj`.

---

### Task 1: Add MapKit fields to `PhotoRecord`

**Files:**
- Modify: `Tools/POIExport/EXIFExtractor.swift:12-17`

**Interfaces:**
- Produces: four new `var` fields on `PhotoRecord` — `mapkitPlaceName: String?`, `mapkitCategory: String?`, `mapkitCity: String?`, `mapkitCountry: String?` — consumed by `MapKitGeocoder` (Task 2) and `DatasetExporter` (Task 3).

- [ ] **Step 1: Add the four fields to `PhotoRecord`**

In `Tools/POIExport/EXIFExtractor.swift`, change:

```swift
    var suggestedPlaceName: String?
    var suggestedCity: String?
    var suggestedCountry: String?

    let verifiedPlaceName: String = ""
    let notes: String = ""
```

to:

```swift
    var suggestedPlaceName: String?
    var suggestedCity: String?
    var suggestedCountry: String?

    var mapkitPlaceName: String?
    var mapkitCategory: String?
    var mapkitCity: String?
    var mapkitCountry: String?

    let verifiedPlaceName: String = ""
    let notes: String = ""
```

- [ ] **Step 2: Verify the tool still compiles**

Run: `xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build`
Expected: `** BUILD SUCCEEDED **` (DatasetExporter and main.swift don't reference the new fields yet, so nothing else changes)

- [ ] **Step 3: Commit**

```bash
git add Tools/POIExport/EXIFExtractor.swift
git commit -m "feat(poi-export): add MapKit fields to PhotoRecord"
```

---

### Task 2: Create `MapKitGeocoder.swift`

**Files:**
- Create: `Tools/POIExport/MapKitGeocoder.swift`

**Interfaces:**
- Consumes: `PhotoRecord` fields `latitude: Double?`, `longitude: Double?`, `filename: String`, and the four MapKit fields from Task 1.
- Produces: `MapKitGeocoder.geocode(records: inout [PhotoRecord], log: inout [String]) async` — called from `main.swift` (Task 4) with the exact same signature shape as `ReverseGeocoder.geocode`.

- [ ] **Step 1: Write `MapKitGeocoder.swift`**

```swift
import Foundation
import MapKit
import CoreLocation

struct MapKitGeocoder {
    static let searchRadiusMeters: Double = 75

    static func geocode(records: inout [PhotoRecord], log: inout [String]) async {
        for i in records.indices {
            guard let lat = records[i].latitude, let lon = records[i].longitude else {
                continue
            }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: searchRadiusMeters)
            do {
                let response = try await MKLocalSearch(request: request).start()
                if let match = closestQualifyingItem(in: response.mapItems, to: coordinate) {
                    records[i].mapkitPlaceName = match.name
                    records[i].mapkitCategory = category(for: match)
                    records[i].mapkitCity = match.placemark.locality ?? match.placemark.administrativeArea
                    records[i].mapkitCountry = match.placemark.country
                }
            } catch {
                log.append("[WARN-MK] \(records[i].filename) — MapKit search failed: \(error.localizedDescription)")
            }
            if i < records.count - 1 {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Private

    private static func closestQualifyingItem(
        in items: [MKMapItem],
        to coordinate: CLLocationCoordinate2D
    ) -> MKMapItem? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let qualifying = items.compactMap { item -> (MKMapItem, CLLocationDistance)? in
            guard let name = item.name, !name.isEmpty else { return nil }
            let itemLocation = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            let distance = origin.distance(from: itemLocation)
            guard distance <= searchRadiusMeters else { return nil }
            return (item, distance)
        }
        return qualifying.min(by: { $0.1 < $1.1 })?.0
    }

    // MKPointOfInterestCategory.rawValue returns e.g. "MKPOICategoryRestaurant";
    // strip the prefix for a readable dataset column.
    private static func category(for item: MKMapItem) -> String? {
        guard let category = item.pointOfInterestCategory else { return nil }
        let raw = category.rawValue
        let prefix = "MKPOICategory"
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }
}
```

- [ ] **Step 2: Verify it compiles standalone**

This file alone won't build via `xcodebuild` yet — it isn't registered in `project.pbxproj` (Task 5) or referenced from `main.swift` (Task 4). Just confirm the file has no obvious syntax errors by eye; full build verification happens in Task 5 Step 2.

- [ ] **Step 3: Commit**

```bash
git add Tools/POIExport/MapKitGeocoder.swift
git commit -m "feat(poi-export): add MapKitGeocoder for MKLocalPointsOfInterestRequest pass"
```

---

### Task 3: Add MapKit columns to `DatasetExporter`

**Files:**
- Modify: `Tools/POIExport/DatasetExporter.swift:29` (CSV header)
- Modify: `Tools/POIExport/DatasetExporter.swift:32-44` (CSV row)
- Modify: `Tools/POIExport/DatasetExporter.swift:84-129` (`JSONRecord`)

**Interfaces:**
- Consumes: `PhotoRecord.mapkitPlaceName`, `.mapkitCategory`, `.mapkitCity`, `.mapkitCountry` (Task 1).

- [ ] **Step 1: Update the CSV header**

In `Tools/POIExport/DatasetExporter.swift`, change:

```swift
        let header = "filename,latitude,longitude,timestamp,camera_model,suggested_place_name,suggested_city,suggested_country,verified_place_name,notes"
```

to:

```swift
        let header = "filename,latitude,longitude,timestamp,camera_model,suggested_place_name,suggested_city,suggested_country,mapkit_place_name,mapkit_category,mapkit_city,mapkit_country,verified_place_name,notes"
```

- [ ] **Step 2: Update the CSV row**

Change:

```swift
            let row = [
                csvEscape(r.filename),
                r.latitude.map { String($0) } ?? "",
                r.longitude.map { String($0) } ?? "",
                csvEscape(r.timestamp),
                csvEscape(r.cameraModel),
                csvEscape(r.suggestedPlaceName),
                csvEscape(r.suggestedCity),
                csvEscape(r.suggestedCountry),
                csvEscape(r.verifiedPlaceName),
                csvEscape(r.notes)
            ].joined(separator: ",")
```

to:

```swift
            let row = [
                csvEscape(r.filename),
                r.latitude.map { String($0) } ?? "",
                r.longitude.map { String($0) } ?? "",
                csvEscape(r.timestamp),
                csvEscape(r.cameraModel),
                csvEscape(r.suggestedPlaceName),
                csvEscape(r.suggestedCity),
                csvEscape(r.suggestedCountry),
                csvEscape(r.mapkitPlaceName),
                csvEscape(r.mapkitCategory),
                csvEscape(r.mapkitCity),
                csvEscape(r.mapkitCountry),
                csvEscape(r.verifiedPlaceName),
                csvEscape(r.notes)
            ].joined(separator: ",")
```

- [ ] **Step 3: Update `JSONRecord`**

Change the whole `JSONRecord` struct:

```swift
private struct JSONRecord: Encodable {
    let filename: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let camera_model: String?
    let suggested_place_name: String?
    let suggested_city: String?
    let suggested_country: String?
    let verified_place_name: String
    let notes: String

    init(_ r: PhotoRecord) {
        filename = r.filename
        latitude = r.latitude
        longitude = r.longitude
        timestamp = r.timestamp
        camera_model = r.cameraModel
        suggested_place_name = r.suggestedPlaceName
        suggested_city = r.suggestedCity
        suggested_country = r.suggestedCountry
        verified_place_name = r.verifiedPlaceName
        notes = r.notes
    }

    // Explicit encode so Optional fields write as null, not omitted.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filename, forKey: .filename)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(camera_model, forKey: .camera_model)
        try c.encode(suggested_place_name, forKey: .suggested_place_name)
        try c.encode(suggested_city, forKey: .suggested_city)
        try c.encode(suggested_country, forKey: .suggested_country)
        try c.encode(verified_place_name, forKey: .verified_place_name)
        try c.encode(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case filename, latitude, longitude, timestamp
        case camera_model, suggested_place_name, suggested_city, suggested_country
        case verified_place_name, notes
    }
}
```

to:

```swift
private struct JSONRecord: Encodable {
    let filename: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let camera_model: String?
    let suggested_place_name: String?
    let suggested_city: String?
    let suggested_country: String?
    let mapkit_place_name: String?
    let mapkit_category: String?
    let mapkit_city: String?
    let mapkit_country: String?
    let verified_place_name: String
    let notes: String

    init(_ r: PhotoRecord) {
        filename = r.filename
        latitude = r.latitude
        longitude = r.longitude
        timestamp = r.timestamp
        camera_model = r.cameraModel
        suggested_place_name = r.suggestedPlaceName
        suggested_city = r.suggestedCity
        suggested_country = r.suggestedCountry
        mapkit_place_name = r.mapkitPlaceName
        mapkit_category = r.mapkitCategory
        mapkit_city = r.mapkitCity
        mapkit_country = r.mapkitCountry
        verified_place_name = r.verifiedPlaceName
        notes = r.notes
    }

    // Explicit encode so Optional fields write as null, not omitted.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filename, forKey: .filename)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(camera_model, forKey: .camera_model)
        try c.encode(suggested_place_name, forKey: .suggested_place_name)
        try c.encode(suggested_city, forKey: .suggested_city)
        try c.encode(suggested_country, forKey: .suggested_country)
        try c.encode(mapkit_place_name, forKey: .mapkit_place_name)
        try c.encode(mapkit_category, forKey: .mapkit_category)
        try c.encode(mapkit_city, forKey: .mapkit_city)
        try c.encode(mapkit_country, forKey: .mapkit_country)
        try c.encode(verified_place_name, forKey: .verified_place_name)
        try c.encode(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case filename, latitude, longitude, timestamp
        case camera_model, suggested_place_name, suggested_city, suggested_country
        case mapkit_place_name, mapkit_category, mapkit_city, mapkit_country
        case verified_place_name, notes
    }
}
```

Note: `writeLog`'s summary line is unchanged — no MapKit count is added (per spec, MapKit result quality is visible in the data itself).

- [ ] **Step 4: Verify the tool still compiles**

Run: `xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Tools/POIExport/DatasetExporter.swift
git commit -m "feat(poi-export): add MapKit columns to labels.csv and dataset.json"
```

---

### Task 4: Wire `MapKitGeocoder` into the pipeline

**Files:**
- Modify: `Tools/POIExport/main.swift:41`

**Interfaces:**
- Consumes: `MapKitGeocoder.geocode(records:log:)` (Task 2).

- [ ] **Step 1: Add the pipeline call**

In `Tools/POIExport/main.swift`, change:

```swift
var mutableRecords = records
var allLog = extractLog
await ReverseGeocoder.geocode(records: &mutableRecords, log: &allLog)

let exporter = DatasetExporter(outputDir: outputURL)
```

to:

```swift
var mutableRecords = records
var allLog = extractLog
await ReverseGeocoder.geocode(records: &mutableRecords, log: &allLog)
await MapKitGeocoder.geocode(records: &mutableRecords, log: &allLog)

let exporter = DatasetExporter(outputDir: outputURL)
```

- [ ] **Step 2: Commit**

```bash
git add Tools/POIExport/main.swift
git commit -m "feat(poi-export): run MapKit geocoding pass after CLGeocoder pass"
```

(Build verification for this task happens together with Task 5, since `main.swift` won't compile against `MapKitGeocoder` until it's registered in the Xcode project.)

---

### Task 5: Register `MapKitGeocoder.swift` and `MapKit.framework` in `project.pbxproj`

**Files:**
- Modify: `fastblog.xcodeproj/project.pbxproj`

**Interfaces:**
- None — this task only wires existing files (Tasks 1-4) into the build graph.

- [ ] **Step 1: Add PBXBuildFile entries**

Find (around line 297):

```
		BBCC0007 /* DatasetExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0008 /* DatasetExporter.swift */; };
```

Change to:

```
		BBCC0007 /* DatasetExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0008 /* DatasetExporter.swift */; };
		BBCC0013 /* MapKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = BBCC0012 /* MapKit.framework */; };
		BBCC0015 /* MapKitGeocoder.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0014 /* MapKitGeocoder.swift */; };
```

- [ ] **Step 2: Add PBXFileReference entries**

Find (around line 592-593):

```
		BBCC0008 /* DatasetExporter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DatasetExporter.swift; sourceTree = "<group>"; };
		BBCC000E /* poi-export */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = "poi-export"; sourceTree = BUILT_PRODUCTS_DIR; };
```

Change to:

```
		BBCC0008 /* DatasetExporter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DatasetExporter.swift; sourceTree = "<group>"; };
		BBCC0012 /* MapKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = MapKit.framework; path = System/Library/Frameworks/MapKit.framework; sourceTree = SDKROOT; };
		BBCC0014 /* MapKitGeocoder.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MapKitGeocoder.swift; sourceTree = "<group>"; };
		BBCC000E /* poi-export */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = "poi-export"; sourceTree = BUILT_PRODUCTS_DIR; };
```

- [ ] **Step 3: Add `MapKit.framework` to the poi-export Frameworks build phase**

Find (around line 608-614):

```
		BBCC000C /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Change to:

```
		BBCC000C /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BBCC0013 /* MapKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] **Step 4: Add `MapKitGeocoder.swift` to the POIExport group**

Find (around line 1011-1021):

```
		BBCC000A /* POIExport */ = {
			isa = PBXGroup;
			children = (
				BBCC0002 /* main.swift */,
				BBCC0004 /* EXIFExtractor.swift */,
				BBCC0006 /* ReverseGeocoder.swift */,
				BBCC0008 /* DatasetExporter.swift */,
			);
			path = POIExport;
			sourceTree = "<group>";
		};
```

Change to:

```
		BBCC000A /* POIExport */ = {
			isa = PBXGroup;
			children = (
				BBCC0002 /* main.swift */,
				BBCC0004 /* EXIFExtractor.swift */,
				BBCC0006 /* ReverseGeocoder.swift */,
				BBCC0008 /* DatasetExporter.swift */,
				BBCC0014 /* MapKitGeocoder.swift */,
			);
			path = POIExport;
			sourceTree = "<group>";
		};
```

- [ ] **Step 5: Add `MapKitGeocoder.swift` to the poi-export Sources build phase**

Find (around line 1395-1405):

```
		BBCC000B /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BBCC0001 /* main.swift in Sources */,
				BBCC0003 /* EXIFExtractor.swift in Sources */,
				BBCC0005 /* ReverseGeocoder.swift in Sources */,
				BBCC0007 /* DatasetExporter.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Change to:

```
		BBCC000B /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BBCC0001 /* main.swift in Sources */,
				BBCC0003 /* EXIFExtractor.swift in Sources */,
				BBCC0005 /* ReverseGeocoder.swift in Sources */,
				BBCC0007 /* DatasetExporter.swift in Sources */,
				BBCC0015 /* MapKitGeocoder.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] **Step 6: Build poi-export**

Run: `xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add fastblog.xcodeproj/project.pbxproj
git commit -m "feat(poi-export): register MapKitGeocoder.swift and link MapKit.framework"
```

---

### Task 6: Full verification and Bloggo regression check

**Files:** none (verification only)

- [ ] **Step 1: Build poi-export**

Run: `xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Build Bloggo (regression check — must be unaffected)**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Smoke-run against a small folder of GPS-tagged photos**

Run: `.build`-produced binary or the Xcode-built product against a test directory, e.g.:

```bash
/path/to/DerivedData/.../poi-export /path/to/folder-with-gps-photos
```

Expected: `POI_Test_Dataset/labels.csv` has 14 columns in the order `filename, latitude, longitude, timestamp, camera_model, suggested_place_name, suggested_city, suggested_country, mapkit_place_name, mapkit_category, mapkit_city, mapkit_country, verified_place_name, notes`; `dataset.json` entries include the four new `mapkit_*` keys (populated or `null`); `export_log.txt` contains no unexpected `[WARN-MK]` lines for photos with real GPS data in a well-covered area (occasional misses are fine — sparse-POI areas won't have a qualifying match).

- [ ] **Step 4: No commit for this task** — it's verification only, nothing to stage.

---

## Self-Review Notes

- **Spec coverage:** Data model (Task 1), `MapKitGeocoder.swift` signature/logic/rate-limit/category-trimming (Task 2), `DatasetExporter` CSV+JSON (Task 3), `main.swift` wiring (Task 4), Xcode registration with the exact spec'd UUIDs (Task 5), build+regression verification (Task 6). All spec sections are covered.
- **Placeholder scan:** No TBD/TODO markers; every step has literal code or exact `Find`/`Change to` text.
- **Type consistency:** `MapKitGeocoder.geocode(records: inout [PhotoRecord], log: inout [String]) async` matches the call site in Task 4 and the spec signature exactly. Field names (`mapkitPlaceName`, `mapkitCategory`, `mapkitCity`, `mapkitCountry`) match across Task 1, Task 2, and Task 3.
