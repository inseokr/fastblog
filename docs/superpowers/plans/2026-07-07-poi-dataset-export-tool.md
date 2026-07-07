# POI Dataset Export Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS Command Line Tool (`poi-export`) that reads a folder of iPhone photos, extracts EXIF/GPS metadata, reverse-geocodes each location, and exports a labeled CSV/JSON dataset for POI accuracy testing.

**Architecture:** Four focused Swift files with no shared mutable state — `EXIFExtractor` reads metadata from disk, `ReverseGeocoder` wraps `CLGeocoder` sequentially, `DatasetExporter` writes all output files, and `main.swift` orchestrates the pipeline. The tool lives in `Tools/POIExport/` as a separate Xcode target — no code shared with the iOS app.

**Tech Stack:** Swift 5.9+, macOS 13.0+, ImageIO (EXIF), CoreLocation (CLGeocoder), Foundation (FileManager, JSONEncoder)

## Global Constraints

- macOS deployment target: 13.0 (Ventura) — required for CLGeocoder async/await
- No shared source files with the Bloggo iOS app target
- Source lives in `Tools/POIExport/` — never under `fastblog/`
- Rate limit: 1500ms sleep between CLGeocoder calls — never remove this
- Output dir is always named `POI_Test_Dataset/` — tool aborts if it already exists
- RFC 4180 CSV: nil → empty field; fields with comma/quote/newline wrapped in double-quotes; internal `"` → `""`
- JSON: nil fields encoded as `null` (not omitted)
- Log prefixes: `[OK]`, `[SKIP]`, `[WARN]`, `[ERROR]` — exact strings, no variations
- Swift IDs used in project.pbxproj (do not reuse): `BBCC0001`–`BBCC0011`, `BBCC000E`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Tools/POIExport/EXIFExtractor.swift` | `PhotoRecord` struct + EXIF scan of directory |
| Create | `Tools/POIExport/ReverseGeocoder.swift` | Sequential CLGeocoder wrapping with 1.5s throttle |
| Create | `Tools/POIExport/DatasetExporter.swift` | Write labels.csv, dataset.json, export_log.txt; copy photos |
| Create | `Tools/POIExport/main.swift` | CLI arg parsing, pipeline orchestration |
| Create | `fastblog.xcodeproj/xcshareddata/xcschemes/poi-export.xcscheme` | Shared scheme so xcodebuild -scheme poi-export works |
| Modify | `fastblog.xcodeproj/project.pbxproj` | Register new target, all source files, groups, build configs |

---

## Task 1: EXIFExtractor.swift

**Files:**
- Create: `Tools/POIExport/EXIFExtractor.swift`

**Interfaces:**
- Produces:
  - `struct PhotoRecord` — the data model shared by all 4 files
  - `EXIFExtractor.extractAll(from: URL) -> (records: [PhotoRecord], log: [String])` — scans a directory, returns records + log lines

- [ ] **Step 1: Create the source directory**

```bash
mkdir -p /Users/ybstudio/Desktop/Projects/Bloggo/Tools/POIExport
```

- [ ] **Step 2: Create `Tools/POIExport/EXIFExtractor.swift`**

```swift
import Foundation
import ImageIO

struct PhotoRecord {
    let filename: String
    let sourcePath: URL
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let cameraModel: String?

    var suggestedPlaceName: String?
    var suggestedCity: String?
    var suggestedCountry: String?

    let verifiedPlaceName: String = ""
    let notes: String = ""
}

struct EXIFExtractor {
    private static let supportedExtensions = ["jpg", "jpeg", "heic", "png"]

    static func extractAll(from directory: URL) -> (records: [PhotoRecord], log: [String]) {
        var records: [PhotoRecord] = []
        var log: [String] = []

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                log.append("[SKIP] \(url.lastPathComponent) — unsupported extension")
                continue
            }
            guard let record = extract(from: url) else {
                log.append("[ERROR] \(url.lastPathComponent) — unreadable")
                continue
            }
            records.append(record)
            log.append("[OK] \(url.lastPathComponent)")
        }

        return (records, log)
    }

    static func extract(from url: URL) -> PhotoRecord? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let gpsDic = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let exifDic = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiffDic = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let (lat, lon) = extractCoordinates(from: gpsDic)
        let timestamp = extractTimestamp(from: exifDic)
        let cameraModel = tiffDic?[kCGImagePropertyTIFFModel] as? String

        return PhotoRecord(
            filename: url.lastPathComponent,
            sourcePath: url,
            latitude: lat,
            longitude: lon,
            timestamp: timestamp,
            cameraModel: cameraModel
        )
    }

    // MARK: - Private

    private static func extractCoordinates(from gps: [CFString: Any]?) -> (Double?, Double?) {
        guard let gps,
              let latValue = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lonValue = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return (nil, nil)
        }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        return (latRef == "S" ? -latValue : latValue, lonRef == "W" ? -lonValue : lonValue)
    }

    private static func extractTimestamp(from exif: [CFString: Any]?) -> String? {
        guard let exif,
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              raw.count >= 19 else { return nil }
        // "YYYY:MM:DD HH:MM:SS" → "YYYY-MM-DDTHH:MM:SS"
        var chars = Array(raw)
        chars[4] = "-"; chars[7] = "-"; chars[10] = "T"
        return String(chars)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Tools/POIExport/EXIFExtractor.swift
git commit -m "feat(poi-export): add PhotoRecord model and EXIFExtractor"
```

---

## Task 2: ReverseGeocoder.swift

**Files:**
- Create: `Tools/POIExport/ReverseGeocoder.swift`

**Interfaces:**
- Consumes: `PhotoRecord` from Task 1 (`.latitude`, `.longitude`, `.filename`, `.suggestedPlaceName`, `.suggestedCity`, `.suggestedCountry`)
- Produces: `ReverseGeocoder.geocode(records:log:) async` — mutates records in place, appends [SKIP]/[WARN] lines to log

- [ ] **Step 1: Create `Tools/POIExport/ReverseGeocoder.swift`**

```swift
import Foundation
import CoreLocation

struct ReverseGeocoder {
    static func geocode(records: inout [PhotoRecord], log: inout [String]) async {
        for i in records.indices {
            guard let lat = records[i].latitude, let lon = records[i].longitude else {
                log.append("[SKIP] \(records[i].filename) — no GPS")
                continue
            }
            let location = CLLocation(latitude: lat, longitude: lon)
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let pm = placemarks.first {
                    records[i].suggestedPlaceName = bestPlaceLabel(pm)
                    records[i].suggestedCity = pm.locality ?? pm.administrativeArea
                    records[i].suggestedCountry = pm.country
                }
            } catch {
                log.append("[WARN] \(records[i].filename) — geocoding failed: \(error.localizedDescription)")
            }
            if i < records.count - 1 {
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    // MARK: - Private

    // Mirrors GeocodingService.bestPlaceLabel logic for accuracy comparability.
    // Prefer pm.name only when it looks like a venue (non-empty, distinct from
    // locality fields, no leading digit). Falls back to subLocality then locality.
    private static func bestPlaceLabel(_ pm: CLPlacemark) -> String? {
        if let name = pm.name,
           !name.isEmpty,
           name != pm.subLocality,
           name != pm.locality,
           !(name.first?.isNumber ?? false) {
            return name
        }
        return pm.subLocality ?? pm.locality
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Tools/POIExport/ReverseGeocoder.swift
git commit -m "feat(poi-export): add ReverseGeocoder with CLGeocoder throttling"
```

---

## Task 3: DatasetExporter.swift

**Files:**
- Create: `Tools/POIExport/DatasetExporter.swift`

**Interfaces:**
- Consumes: `[PhotoRecord]` from Tasks 1+2, `[String]` log lines, `URL` outputDir
- Produces: `DatasetExporter.export(records:logLines:) throws` — writes all 4 output items; `DatasetExporter.copyPhotos(records:) throws`

- [ ] **Step 1: Create `Tools/POIExport/DatasetExporter.swift`**

```swift
import Foundation

struct DatasetExporter {
    let outputDir: URL

    // MARK: - Public

    func export(records: [PhotoRecord], logLines: [String]) throws {
        try writeCSV(records: records)
        try writeJSON(records: records)
        try writeLog(records: records, logLines: logLines)
    }

    func copyPhotos(records: [PhotoRecord]) throws {
        let photosDir = outputDir.appendingPathComponent("photos")
        for record in records {
            let dest = photosDir.appendingPathComponent(record.filename)
            do {
                try FileManager.default.copyItem(at: record.sourcePath, to: dest)
            } catch {
                fputs("[ERROR] copy failed for \(record.filename): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - CSV

    private func writeCSV(records: [PhotoRecord]) throws {
        let header = "filename,latitude,longitude,timestamp,camera_model,suggested_place_name,suggested_city,suggested_country,verified_place_name,notes"
        var lines = [header]
        for r in records {
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
            lines.append(row)
        }
        let content = lines.joined(separator: "\r\n") + "\r\n"
        try content.write(to: outputDir.appendingPathComponent("labels.csv"), atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - JSON

    private func writeJSON(records: [PhotoRecord]) throws {
        let jsonRecords = records.map(JSONRecord.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(jsonRecords)
        try data.write(to: outputDir.appendingPathComponent("dataset.json"))
    }

    // MARK: - Log

    private func writeLog(records: [PhotoRecord], logLines: [String]) throws {
        let processed = records.count
        let geocoded = records.filter { $0.suggestedCity != nil || $0.suggestedPlaceName != nil }.count
        let skippedNoGPS = logLines.filter { $0.contains("no GPS") }.count
        let errors = logLines.filter { $0.hasPrefix("[ERROR]") }.count

        let summary = "Summary: \(processed) photos processed, \(geocoded) geocoded, \(skippedNoGPS) skipped (no GPS), \(errors) errors"
        let content = (logLines + [summary]).joined(separator: "\n") + "\n"
        try content.write(to: outputDir.appendingPathComponent("export_log.txt"), atomically: true, encoding: .utf8)
    }
}

// MARK: - JSON record

// Separate Codable type so sourcePath is excluded and nil fields encode as null.
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

- [ ] **Step 2: Commit**

```bash
git add Tools/POIExport/DatasetExporter.swift
git commit -m "feat(poi-export): add DatasetExporter (CSV, JSON, log, photo copy)"
```

---

## Task 4: main.swift

**Files:**
- Create: `Tools/POIExport/main.swift`

**Interfaces:**
- Consumes: `EXIFExtractor.extractAll(from:)`, `ReverseGeocoder.geocode(records:log:)`, `DatasetExporter.export(records:logLines:)` + `copyPhotos(records:)`

- [ ] **Step 1: Create `Tools/POIExport/main.swift`**

Note: `main.swift` is special in Swift — top-level `try await` is valid here and the compiler wraps it in an async entry point automatically (Swift 5.5+, macOS 13+ guaranteed).

```swift
import Foundation

// MARK: - Validate arguments

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: poi-export <path-to-photos>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let inputURL = URL(fileURLWithPath: inputPath)
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDir), isDir.boolValue else {
    fputs("Error: '\(inputPath)' does not exist or is not a directory\n", stderr)
    exit(1)
}

let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("POI_Test_Dataset")
guard !FileManager.default.fileExists(atPath: outputURL.path) else {
    fputs("Error: Output directory '\(outputURL.path)' already exists — remove it first\n", stderr)
    exit(1)
}

// MARK: - Set up output directories

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputURL.appendingPathComponent("photos"), withIntermediateDirectories: true)
} catch {
    fputs("Error creating output directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// MARK: - Pipeline

let (records, extractLog) = EXIFExtractor.extractAll(from: inputURL)
print("Extracted metadata from \(records.count) photo(s). Starting geocoding…")

var mutableRecords = records
var allLog = extractLog
await ReverseGeocoder.geocode(records: &mutableRecords, log: &allLog)

let exporter = DatasetExporter(outputDir: outputURL)
do {
    try exporter.export(records: mutableRecords, logLines: allLog)
    try exporter.copyPhotos(records: mutableRecords)
} catch {
    fputs("Export failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

print("Done. Output: \(outputURL.path)")
```

- [ ] **Step 2: Commit**

```bash
git add Tools/POIExport/main.swift
git commit -m "feat(poi-export): add main.swift pipeline orchestration"
```

---

## Task 5: Xcode Registration + Build Verification

**Files:**
- Create: `fastblog.xcodeproj/xcshareddata/xcschemes/poi-export.xcscheme`
- Modify: `fastblog.xcodeproj/project.pbxproj`

**UUIDs assigned for this target** (all `BBCC0XXX` — verified not used in existing project):

| ID | Purpose |
|----|---------|
| `BBCC0001` | PBXBuildFile — main.swift |
| `BBCC0002` | PBXFileReference — main.swift |
| `BBCC0003` | PBXBuildFile — EXIFExtractor.swift |
| `BBCC0004` | PBXFileReference — EXIFExtractor.swift |
| `BBCC0005` | PBXBuildFile — ReverseGeocoder.swift |
| `BBCC0006` | PBXFileReference — ReverseGeocoder.swift |
| `BBCC0007` | PBXBuildFile — DatasetExporter.swift |
| `BBCC0008` | PBXFileReference — DatasetExporter.swift |
| `BBCC0009` | PBXGroup — Tools/ |
| `BBCC000A` | PBXGroup — Tools/POIExport/ |
| `BBCC000B` | PBXSourcesBuildPhase — poi-export |
| `BBCC000C` | PBXFrameworksBuildPhase — poi-export |
| `BBCC000D` | PBXNativeTarget — poi-export |
| `BBCC000E` | PBXFileReference — poi-export binary |
| `BBCC000F` | XCBuildConfiguration — Debug for poi-export |
| `BBCC0010` | XCBuildConfiguration — Release for poi-export |
| `BBCC0011` | XCConfigurationList — poi-export |

- [ ] **Step 1: Create the xcscheme directory**

```bash
mkdir -p /Users/ybstudio/Desktop/Projects/Bloggo/fastblog.xcodeproj/xcshareddata/xcschemes
```

- [ ] **Step 2: Create `fastblog.xcodeproj/xcshareddata/xcschemes/poi-export.xcscheme`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2650"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "BBCC000D"
               BuildableName = "poi-export"
               BlueprintName = "poi-export"
               ReferencedContainer = "container:fastblog.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "BBCC000D"
            BuildableName = "poi-export"
            BlueprintName = "poi-export"
            ReferencedContainer = "container:fastblog.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "BBCC000D"
            BuildableName = "poi-export"
            BlueprintName = "poi-export"
            ReferencedContainer = "container:fastblog.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: Edit `project.pbxproj` — add PBXBuildFile entries**

Find `/* End PBXBuildFile section */` and insert before it:

```
		BBCC0001 /* main.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0002 /* main.swift */; };
		BBCC0003 /* EXIFExtractor.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0004 /* EXIFExtractor.swift */; };
		BBCC0005 /* ReverseGeocoder.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0006 /* ReverseGeocoder.swift */; };
		BBCC0007 /* DatasetExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBCC0008 /* DatasetExporter.swift */; };
```

- [ ] **Step 4: Edit `project.pbxproj` — add PBXFileReference entries**

Find `/* End PBXFileReference section */` and insert before it:

```
		BBCC0002 /* main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
		BBCC0004 /* EXIFExtractor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EXIFExtractor.swift; sourceTree = "<group>"; };
		BBCC0006 /* ReverseGeocoder.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReverseGeocoder.swift; sourceTree = "<group>"; };
		BBCC0008 /* DatasetExporter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DatasetExporter.swift; sourceTree = "<group>"; };
		BBCC000E /* poi-export */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = "poi-export"; sourceTree = BUILT_PRODUCTS_DIR; };
```

- [ ] **Step 5: Edit `project.pbxproj` — add PBXGroup entries**

Find `/* End PBXGroup section */` and insert before it:

```
		BBCC0009 /* Tools */ = {
			isa = PBXGroup;
			children = (
				BBCC000A /* POIExport */,
			);
			path = Tools;
			sourceTree = "<group>";
		};
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

- [ ] **Step 6: Edit `project.pbxproj` — wire Tools group into mainGroup**

In `BB0001AD /* main */`, add `BBCC0009 /* Tools */,` after the closing mp3 file entries. Locate this exact block in the file:

Old:
```
				03B8B6572F7CA2EB0088C39F /* Recovered References */,
			);
			name = main;
			sourceTree = "<group>";
		};
		BB0001AE /* fastblog */
```

New:
```
				03B8B6572F7CA2EB0088C39F /* Recovered References */,
				BBCC0009 /* Tools */,
			);
			name = main;
			sourceTree = "<group>";
		};
		BB0001AE /* fastblog */
```

- [ ] **Step 7: Edit `project.pbxproj` — add poi-export to Products group**

Old:
```
		BB0001AF /* Products */ = {
			isa = PBXGroup;
			children = (
				AA000003 /* Bloggo.app */,
			);
```

New:
```
		BB0001AF /* Products */ = {
			isa = PBXGroup;
			children = (
				AA000003 /* Bloggo.app */,
				BBCC000E /* poi-export */,
			);
```

- [ ] **Step 8: Edit `project.pbxproj` — add PBXNativeTarget**

Find `/* End PBXNativeTarget section */` and insert before it:

```
		BBCC000D /* poi-export */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BBCC0011 /* Build configuration list for PBXNativeTarget "poi-export" */;
			buildPhases = (
				BBCC000B /* Sources */,
				BBCC000C /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = "poi-export";
			productName = "poi-export";
			productReference = BBCC000E /* poi-export */;
			productType = "com.apple.product-type.tool";
		};
```

- [ ] **Step 9: Edit `project.pbxproj` — add Sources + Frameworks build phases**

Find `/* End PBXSourcesBuildPhase section */` and insert before it:

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

Find `/* End PBXFrameworksBuildPhase section */` and insert before it:

```
		BBCC000C /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] **Step 10: Edit `project.pbxproj` — add build configurations**

Find `/* End XCBuildConfiguration section */` and insert before it:

```
		BBCC000F /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = N3L5LBGNK2;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;
				GCC_OPTIMIZATION_LEVEL = 0;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				DEBUG_INFORMATION_FORMAT = dwarf;
			};
			name = Debug;
		};
		BBCC0010 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = N3L5LBGNK2;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_COMPILATION_MODE = wholemodule;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
			};
			name = Release;
		};
```

- [ ] **Step 11: Edit `project.pbxproj` — add XCConfigurationList**

Find `/* End XCConfigurationList section */` and insert before it:

```
		BBCC0011 /* Build configuration list for PBXNativeTarget "poi-export" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BBCC000F /* Debug */,
				BBCC0010 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 12: Edit `project.pbxproj` — register target in PBXProject**

Old:
```
			targets = (
				AA000020 /* Bloggo */,
			);
```

New:
```
			targets = (
				AA000020 /* Bloggo */,
				BBCC000D /* poi-export */,
			);
```

- [ ] **Step 13: Build the new target to verify**

```bash
cd /Users/ybstudio/Desktop/Projects/Bloggo
xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

If you see `BUILD FAILED`, look for the first `error:` line in the output. Common fixes:
- "Unknown type" → check that all 4 source files are in `Tools/POIExport/` and IDs in pbxproj match the correct paths
- "No such module" → verify `SDKROOT = macosx` is set in both Debug and Release configs
- PBXFrameworksBuildPhase missing → check `/* End PBXFrameworksBuildPhase section */` exists (grep for it)

- [ ] **Step 14: Smoke test — run on a folder of photos**

```bash
# Find the built binary
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -name poi-export -type f 2>/dev/null | grep -v dSYM | head -1)
echo "Binary: $BINARY"

# Create a test folder with at least one .jpg (copy any photo you have)
mkdir -p /tmp/poi_test_input
cp ~/Desktop/*.jpg /tmp/poi_test_input/ 2>/dev/null || true

# Run (expects POI_Test_Dataset/ to appear at /tmp/)
"$BINARY" /tmp/poi_test_input
```

Expected output:
```
Extracted metadata from N photo(s). Starting geocoding…
Done. Output: /tmp/POI_Test_Dataset
```

Verify output structure:
```bash
ls /tmp/POI_Test_Dataset/
# → photos/  labels.csv  dataset.json  export_log.txt

head -3 /tmp/POI_Test_Dataset/labels.csv
# → header row + data rows

cat /tmp/POI_Test_Dataset/export_log.txt | tail -1
# → "Summary: N photos processed, ..."
```

- [ ] **Step 15: Commit**

```bash
git add fastblog.xcodeproj/project.pbxproj \
        fastblog.xcodeproj/xcshareddata/xcschemes/poi-export.xcscheme
git commit -m "feat(poi-export): register poi-export macOS CLI target in Xcode project"
```

---

## Spec Coverage Self-Check

| Spec requirement | Task |
|-----------------|------|
| macOS Command Line Tool target `poi-export` | Task 5 |
| Source in `Tools/POIExport/`, no iOS shared code | Tasks 1–5 |
| EXIF via ImageIO (no pixel decode) | Task 1 |
| Supported extensions: jpg, jpeg, heic, png | Task 1 |
| GPS signed decimal via latRef/lonRef | Task 1 |
| Timestamp → ISO 8601 from DateTimeOriginal | Task 1 |
| Camera model from TIFF dict | Task 1 |
| Corrupt metadata → record with nil fields, not skipped | Task 1 |
| Unreadable file → [ERROR], skipped entirely | Task 1 |
| Sequential geocoding, 1500ms delay | Task 2 |
| Venue name heuristic matching GeocodingService | Task 2 |
| No GPS → [SKIP], record kept in output | Tasks 2, 4 |
| Geocoding failure → [WARN], continue | Task 2 |
| Output dir abort if already exists | Task 4 |
| photos/ subfolder, verbatim copy, no rename | Task 3 |
| labels.csv RFC 4180, nil = empty field | Task 3 |
| dataset.json prettyPrinted, nil = null | Task 3 |
| export_log.txt with [OK]/[SKIP]/[WARN]/[ERROR] + summary | Task 3 |
| Summary line format | Task 3 |
| No CLI arg → usage + exit 1 | Task 4 |
| Bad input path → error + exit 1 | Task 4 |
| Output dir exists → error + exit 1 | Task 4 |
| `xcodebuild -scheme poi-export -sdk macosx` works | Task 5 |
| `poi-export` not in Bloggo build phase | Task 5 — new PBXSourcesBuildPhase scoped to BBCC000D only |
