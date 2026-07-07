# Fastblog — Software Design Document

## 1. Trip Scanning Algorithm

**Source:** `fastblog/Services/PhotoLibraryTripService.swift`, `fastblog/Services/ScanConfig.swift`

### Overview

Trips are identified from the device photo library by scanning the last 90 days of photos, filtering out local/home activity, then grouping photos into temporal clusters that represent distinct travel trips.

### Pipeline

```
PHAsset fetch (90-day window)
  │
  ├─ Filter: drop photos with no GPS data
  ├─ Filter: exclude date ranges already converted to blogs
  ├─ Filter: exclude within 50 miles of home neighborhood (TripPhotoFilter)
  │
  ↓ groupAssetsByDay()
     Sort by timestamp; assign each photo to a calendar day using
     EXIF OffsetTimeOriginal for timezone-aware bucketing.
     Photos between midnight–5 AM that are < 2h from the previous day's
     last photo are bridged into the prior day ("midnight bridge").
  │
  ↓ buildDayClusters()
     Per day: compute centroid, max intra-day distance (miles),
     collect all PHAssets → DayCluster struct.
  │
  ↓ Merge days into trips
     Adjacent days separated by ≤ 2 calendar days are merged into
     the same TripDraft.
  │
  ↓ splitTripsByCountryBoundary()
     If consecutive day centroids are > 400 miles apart, split into
     separate trips. Fast-path: skip geocoding if no large gaps detected.
  │
  ↓ splitTripsByMaxDays()
     Trips > 7 calendar days are split into "Part 1", "Part 2", etc.
  │
  ↓ Geocode one representative asset per trip (first GPS-tagged photo)
     → Attach city/country display name to TripDraft
  │
  ↓ Return [TripDraft]
```

### Key Thresholds

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Scan window | 90 days | Default lookback |
| Home exclusion radius | 50 miles | Suppress local activity |
| New-segment time gap | 12 hours | Separate same-day clusters |
| Max day-merge gap | 2 calendar days | Bridge short gaps (overnight, layover) |
| Midnight bridge window | 5 AM + 2 h gap | Merge late arrivals to prior day |
| Country-split distance | 400 miles | Detect international flight boundary |
| Max trip duration | 7 days | Split long trips into parts |

---

## 2. Place / Photo-Group Algorithm

**Source:** `fastblog/Services/PlaceStopClusteringService.swift`

### Overview

Within a single calendar day's photos, a time-and-distance heuristic clusters photos into PlaceStops — the named locations visited that day.

### Clustering Logic

Photos are sorted by timestamp. For each incoming photo, the algorithm checks whether it belongs to the **current open group** or starts a **new group**.

**Both conditions must be satisfied to stay in the current group:**

**Condition 1** — Spatial/temporal proximity to group start:
- Time from group start < 5 min, **OR**
- Distance < 50 m **AND** time from group start < 5 h **AND** this is the last group

**Condition 2** — Temporal relationship to previous photo:
- Time gap > expected walking time (`distance / 1.34 m·s⁻¹ × 1.3`), **OR**
- Time gap < 5 min

If either condition fails → close current group, open new group.

**Fallback for GPS-less photos:** Group by time only — gap ≤ 30 min stays in the same group.

### Key Constants

| Constant | Value |
|----------|-------|
| Same-place distance | 50 m |
| Short-time threshold | 5 min (300 s) |
| Max group open window | 5 h (18 000 s) |
| Walking speed | 1.34 m/s |
| Walking time fudge factor | 1.3× |
| Time-only gap threshold | 30 min |

### Output

Each cluster becomes a `PlaceStop`. Place titles are resolved via reverse geocoding (`GeocodingService.shared`) after clustering.

---

## 3. Auto Photo Selection

**Source:** `fastblog/Services/PhotoQualityScorer.swift`

### Scoring Formula

```
totalScore = aesthetics × 0.6 + sharpness × 0.4
```

**Aesthetics score (0–1):**
- iOS 18+: `VNCalculateImageAestheticsScoresRequest.overallScore`
  - Screenshots / documents / receipts: penalized to 0.1 (utility image)
- Pre-iOS 18 fallback: saliency-based
  - Ideal salient area = 25% of frame
  - `score = max(0.1, 1.0 − |salient_area − 0.25| × 2)`

**Sharpness score (0–1):**
- Contour detection via `VNDetectContoursRequest`
- `score = min(1.0, contour_count / 120.0)`
- < 15 contours → near-zero (blurry/flat); 120+ contours → 1.0

Scoring runs at 300×300 px thumbnails with max 6 concurrent `PHImageManager` requests to avoid XPC flakes.

### Auto-Include Count Per Place

| Photos at place | Auto-included |
|-----------------|---------------|
| 1–2 | 1 |
| 3–5 | 2 |
| > 5 | 3 |

### Selection Priority

1. **Favorites first** (`PHAsset.isFavorite == true`): all favorites fill slots first; excess favorites ranked by quality score.
2. **Remainder by quality score**: highest `totalScore` fills remaining slots.
3. **Distinctness filter** applied to final set:
   - Min time separation: 90 s (hard cutoff: 10 s burst pairs rejected)
   - Min spatial separation: 35 m
   - If a photo fails distinctness: fall back to next by score.

**Large-place optimization:** If > 10 photos are unscored, sample evenly across the visit time window (10-photo limit) rather than scoring all.

---

## 4. Blog & Trip Storage

**Source:** `fastblog/Services/CreatedRecapBlogStore.swift`, `fastblog/Models/RecapBlogDetail.swift`, `fastblog/Models/TripDraft.swift`

### Disk Layout

```
~/Library/Application Support/CreatedBlogs/
├── recents.json       — [CreatedRecapBlog]     lightweight metadata list
├── tripDrafts.json    — [UUID: TripDraft]       photo selections pre-blog
└── blogDetails.json   — [UUID: RecapBlogDetail] full editable blog content
```

All files use ISO 8601 date encoding. Writes are `Task.detached(priority: .utility)` (non-blocking).

### Model Hierarchy

```
CreatedRecapBlog          (recents.json — metadata & ownership)
  └─ sourceTripId ──────→ TripDraft           (tripDrafts.json)
                               └─ TripDay
                                    └─ MockPhoto (PHAsset + EXIF)

  └─ id ───────────────→ RecapBlogDetail      (blogDetails.json)
         └─ RecapBlogDay
              └─ PlaceStop
                   └─ RecapPhoto
```

### Key Fields Per Layer

**CreatedRecapBlog** — lightweight index entry
- `sourceTripId`, `tripStartDate`, `tripEndDate`, `tripDateRangeText`
- `ownerScope: OwnerScope` — `.anonymous` or `.account`
- `cloudState: CloudState` — `.localOnly` / `.uploadedActive` / `.uploadedArchived`
- `syncStatus: SyncStatus` — `.clean` / `.needsUpload` / `.conflict`
- `hasCommittedRecapSave: Bool` — guest save-slot tracking

**TripDraft** — raw scan result, pre-editing
- `days: [TripDay]` — photos grouped by calendar day
- `coverAssetIdentifier: String?` — PHAsset localIdentifier or `bloggo-capture:UUID`
- `selectedPhotoCount: Int` — computed from `day.photos.filter(\.isSelected)`

**MockPhoto** — individual photo within a TripDraft
- `localIdentifier: String?` — PHAsset ID
- `timestamp: Date`, `location: PhotoCoordinate?`
- `isSelected: Bool` — user's selection state in trip picker

**RecapBlogDetail** — the canonical, editable blog object
- `days: [RecapBlogDay]`, `title`, `tripNarrative`
- `removedPlaceStops: [RemovedPlaceEntry]` — soft-delete undo buffer
- `blogKey: Int?` — server-assigned ID after upload

**RecapBlogDay**
- `placeStops: [PlaceStop]`, `dayCaption`, `dayNarrative`
- `isPlaceNamesResolved: Bool` — geocoding completion flag
- `weather: DayWeather?` — Open-Meteo forecast data

**PlaceStop**
- `placeTitle`, `placeSubtitle`, `placeCategory`
- `photos: [RecapPhoto]` — all photos; filter `isIncluded` for display
- `noteText`, `overallStory`, `placeNarrative` — user + AI text
- `visitedTimeDigitized: String?` — EXIF format, earliest photo time
- `sentiment: Int` — 1 = loved, 2 = neutral, 3 = terrible
- `cloudPlaceIndex: Int?` — server-assigned post-upload

**RecapPhoto**
- `cloudURL: String?` — nil until uploaded
- `localIdentifier: String?` — PHAsset ID
- `qualityScore: PhotoScore?` — aesthetics + sharpness components
- `caption: String?`, `isFavorite: Bool`
- `isIncluded: Bool` — false = hidden from rendered blog

### Create Blog Flow

```
addCreatedBlog(trip: TripDraft)
  ├─ buildBlogDetail(from: trip)
  │    ├─ PlaceStopClusteringService.placeStops(from: day.photos)
  │    ├─ PhotoQualityScorer.autoSelectedIds() → set isIncluded
  │    └─ GeocodingService: resolve placeTitle per cluster
  ├─ Insert CreatedRecapBlog at recents[0] (newest first)
  ├─ Cache blogDetail in memory
  ├─ Save scan cutoff timestamp (exclude these dates from next scan)
  └─ persistRecents() + persistTripDrafts() + persistBlogDetails()
```

### Cloud Sync States

```
localOnly ──(upload)──→ uploadedActive ──(archive)──→ uploadedArchived
                               ↑
                         syncStatus tracks:
                         .clean / .needsUpload / .conflict
```

Selection state is kept in sync between `TripDraft` and `RecapBlogDetail` via `tripDraftApplyingBlogSelection()` — ensuring the photo picker reflects any edits made inside the blog editor.
