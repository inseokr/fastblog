# Code Skill: Data Models

## Model hierarchy

```
RecapBlogDetail          (the blog — what gets saved and shared)
  └─ [RecapBlogDay]      (one entry per calendar day of the trip)
       └─ [PlaceStop]    (a named place visited that day)
            └─ [RecapPhoto]  (individual photos at that place)

TripDraft                (raw scan result — not yet a blog)
  └─ [TripDay]
       └─ [MockPhoto]    (PHAsset-backed photo with EXIF metadata)
```

## Key model fields

### RecapPhoto
```swift
var id: String
var cloudURL: String?          // nil until uploaded
var localIdentifier: String?   // PHAsset identifier
var isIncluded: Bool           // false = hidden from blog
var qualityScore: PhotoScore?  // AI scoring result
var caption: String
var timestamp: Date
```

### PlaceStop
```swift
var id: String
var placeTitle: String
var placeSubtitle: String
var photos: [RecapPhoto]       // ALL photos; filter by isIncluded for display
var noteText: String
var placeCategory: String
var visitedTimeDigitized: Date?
```

### RecapBlogDetail
```swift
var id: String
var title: String
var days: [RecapBlogDay]
var selectedCoverPhotoIdentifier: String?
var tripNarrative: String
var removedPlaceStops: [PlaceStop]  // undo buffer for soft-deleted places
```

## Protocol conformances required
Every model struct should have:
- `Identifiable` — enables ForEach diffing; use `var id: String` (UUID string)
- `Codable` — JSON persistence to disk and API
- `Equatable` — required by `.onChange(of:)` and list diffing
- `Hashable` — when used in Sets or as NavigationPath values

## Rules
- Models are plain `struct`s — no `class`, no `ObservableObject`
- No service calls inside models — computed properties only
- IDs are `String` (UUID string), not `UUID` type, for Codable compatibility
- Optional fields use `?` — do not use sentinel values like `""` or `-1`

## Creating new models
Follow this template:
```swift
struct FeatureModel: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var createdAt: Date
    // computed props at bottom
    var displayTitle: String { title.isEmpty ? "Untitled" : title }
}
```
