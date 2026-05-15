# UI Skill: Component Library & Reuse

## Before building a new UI component, check these first

### Shared components in `Views/Components/`

| Component | File | Variants / Notes |
|-----------|------|-----------------|
| `PlaceCardView` | `PlaceCardView.swift` | `.minimal`, `.editorial`, `.voyage` (glassmorphic) |
| `PlaceCardCarousel` | — | Horizontal scroll with peek affordance, snap-to-item |
| `KeyboardCaptionToolbar` | — | Custom keyboard accessory: Cancel / Clear / Done |
| `RecapPhotoThumbnail` | — | Photo tile with optional quality badge; supports cloud URL or local PHAsset |
| `CloudPhotoView` | — | Async cloud image loading with placeholder |
| `MockPhotoView` | — | Local PHAsset image rendering |
| `RankBadge` | — | Ordinal rank (1st, 2nd…); gold style for #1 |
| `AtmosphericWaveformView` | — | Audio waveform (for audio-backed features) |
| `ReminderCardView` | — | Draft reminder / notification card |
| `RecallCard` | — | Memory trigger card |

### Chrome helpers (`AppChromeMetrics.swift`)
- `AppChromeShapes.pullUpTopSurface()` — bottom sheet top surface with drag handle
- `AppChromeMetrics` — shared corner radii, toolbar heights, surface sizing

## Carousel pattern
Use `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)` + `ScrollViewReader` for snap carousels.
- Add peek affordance via `.padding(.horizontal, peekAmount)` on the scroll view and negative padding on items
- Preserve scroll position via `lastSelectedVisibleTripID` / `scrollPosition(id:)` across view recreation

## Photo rendering decision tree
```
Is the photo from cloud?  →  CloudPhotoView (async URL load)
Is it a local PHAsset?    →  MockPhotoView or RecapPhotoThumbnail
Does it need quality badge? → RecapPhotoThumbnail
```

## TabView paging
Use `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` for:
- StoryBook cover/day/map pages
- Storage management photo carousel
Do NOT use it for primary app navigation (use ZStack overlay system instead).
