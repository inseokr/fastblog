# poi-export — POI Dataset Export Tool

A macOS command-line tool that reads a folder of iPhone photos, extracts their GPS and EXIF metadata, reverse-geocodes each location, and writes a labeled dataset template for POI accuracy testing.

**Who uses this:** Woo-Hyuk runs the tool to generate the initial dataset. Yoobin then opens `labels.csv` and fills in the `verified_place_name` column by hand, creating the ground truth used to benchmark Bloggo's POI detection accuracy.

---

## Build

```bash
xcodebuild -project fastblog.xcodeproj -scheme poi-export -sdk macosx build
```

Find the binary after building:

```bash
find ~/Library/Developer/Xcode/DerivedData -name poi-export -type f | grep -v dSYM | head -1
```

---

## Usage

```
poi-export <path-to-photos>
```

**Input:** a folder of original iPhone photos (`.jpg`, `.jpeg`, `.heic`, `.png`).

**Output:** a folder named `POI_Test_Dataset/` created as a sibling of the input folder (not inside it).

```
/path/to/
├── my-photos/          ← input
└── POI_Test_Dataset/   ← output created here
    ├── photos/         ← verbatim copies of original images
    ├── labels.csv
    ├── dataset.json
    └── export_log.txt
```

If `POI_Test_Dataset/` already exists at the destination, the tool aborts — it never silently overwrites.

---

## What it does

**Step 1 — EXIF extraction**

Reads each image using `ImageIO` without decoding pixel data, so a 50 MB ProRAW file costs essentially no memory. Pulls GPS coordinates (signed decimal, applying N/S/E/W ref), capture timestamp (ISO 8601), and camera model from the raw metadata dictionaries.

Files with unreadable or missing metadata still produce a row — they appear in the output with blank GPS/timestamp/camera fields. Only files that can't be opened at all are skipped.

**Step 2 — Reverse geocoding**

Calls Apple's `CLGeocoder` once per photo, sequentially with a 1.5-second delay between requests (safely under Apple's ~50 req/minute limit). For each photo with GPS coordinates, it derives:

- `suggested_place_name` — the venue name if it looks like one (non-empty, not a street address, not equal to the locality name), otherwise the neighbourhood or city name
- `suggested_city` — locality or administrative area
- `suggested_country`

Photos without GPS are kept in the output with blank geocode fields.

**Step 3 — Export**

Writes three files and copies the photos:

- `labels.csv` — RFC 4180 compliant; `verified_place_name` and `notes` columns are always blank for manual entry
- `dataset.json` — same fields as CSV, pretty-printed; `null` for missing values (never omitted)
- `export_log.txt` — one line per photo with a status prefix, plus a summary line at the end
- `photos/` — verbatim copies, original filenames, no recompression

---

## Output format

### labels.csv

Column order:

```
filename, latitude, longitude, timestamp, camera_model,
suggested_place_name, suggested_city, suggested_country,
verified_place_name, notes
```

`verified_place_name` and `notes` are always empty — fill these in to create ground truth.

### dataset.json

Same fields as CSV. Every row has all keys; missing values are `null` so the schema is consistent across rows.

```json
[
  {
    "filename": "IMG_0042.heic",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": "2026-06-15T14:23:01",
    "camera_model": "iPhone 15 Pro",
    "suggested_place_name": "Blue Bottle Coffee",
    "suggested_city": "San Francisco",
    "suggested_country": "United States",
    "verified_place_name": "",
    "notes": ""
  },
  {
    "filename": "IMG_0043.heic",
    "latitude": null,
    "longitude": null,
    "timestamp": "2026-06-15T15:01:44",
    "camera_model": "iPhone 15 Pro",
    "suggested_place_name": null,
    "suggested_city": null,
    "suggested_country": null,
    "verified_place_name": "",
    "notes": ""
  }
]
```

### export_log.txt

One line per event:

| Prefix | Meaning |
|--------|---------|
| `[OK]` | Photo processed successfully |
| `[SKIP]` | Unsupported file extension, or no GPS (photo still in output) |
| `[WARN]` | Geocoding failed for this photo (photo still in output with blank geocode fields) |
| `[ERROR]` | File unreadable — skipped entirely, not in output |

Final line:

```
Summary: 47 photos processed, 43 geocoded, 3 skipped (no GPS), 1 errors
```

---

## Error behaviour

| Situation | What happens |
|-----------|-------------|
| No argument | Prints usage, exits 1 |
| Input path doesn't exist or isn't a folder | Prints error, exits 1 |
| `POI_Test_Dataset/` already exists | Prints error, exits 1 — remove it first |
| Unsupported file extension | `[SKIP]` in log, not in output |
| Corrupt or unreadable image | `[ERROR]` in log, not in output |
| Photo has no GPS | `[SKIP]` in log, row in output with blank GPS/geocode fields |
| CLGeocoder failure | `[WARN]` in log, row in output with blank geocode fields, continues |
| Individual photo copy failure | Logs to stderr, continues with remaining photos |

---

## Workflow for ground-truth labelling

1. Build the tool (once — rebuild when source changes).
2. Point it at a folder of representative iPhone photos:
   ```bash
   poi-export ~/Desktop/test-photos
   ```
3. Open `POI_Test_Dataset/labels.csv` in any spreadsheet app.
4. For each row, look at the photo in `POI_Test_Dataset/photos/`, decide what the correct place name is, and type it into `verified_place_name`.
5. Use `notes` for anything ambiguous — "could be either X or Y", "chain restaurant", etc.
6. Save. The completed CSV is the ground-truth dataset.

To test Bloggo's accuracy against it, compare `suggested_place_name` with `verified_place_name` across all rows.

---

## Source files

All source lives in `Tools/POIExport/` — completely separate from the iOS app, no shared code.

| File | Responsibility |
|------|---------------|
| [main.swift](../../Tools/POIExport/main.swift) | Argument parsing and pipeline orchestration |
| [EXIFExtractor.swift](../../Tools/POIExport/EXIFExtractor.swift) | `PhotoRecord` model + ImageIO-based metadata extraction |
| [ReverseGeocoder.swift](../../Tools/POIExport/ReverseGeocoder.swift) | Sequential CLGeocoder wrapping with rate throttle |
| [DatasetExporter.swift](../../Tools/POIExport/DatasetExporter.swift) | CSV, JSON, log writing + photo copying |
