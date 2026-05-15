# POI Web View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user taps a native MapKit POI on the Places Visited full-screen map or the Blog full-screen day map, a bottom sheet slides up showing the Google Maps place page for that POI inside `GoogleSearchEmbeddedWebView`.

**Architecture:** Use SwiftUI `Map`'s `selection: $selectedMapFeature` binding (iOS 17+) to detect native POI taps. `MapDayView` gets an optional `onPOITapped` callback; when it fires, `FullScreenMapView` snapshots the feature and presents `POIInfoSheet` as a `.sheet`. `PlacesVisitedMapView` owns its own `selectedMapFeature` state and presents the same sheet directly.

**Tech Stack:** SwiftUI MapKit (iOS 17+ `MapFeature`), `WKWebView` via existing `GoogleSearchEmbeddedWebView`, SwiftUI `.sheet` with `.medium`/`.large` detents.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `fastblog/Views/POIInfoSheet.swift` | **Create** | Bottom sheet header + `GoogleSearchEmbeddedWebView` |
| `fastblog/Views/MapDayView.swift` | **Modify** | Add `onPOITapped` param + `selection:` binding to `MapDayView`; add POI sheet state to `FullScreenMapView` |
| `fastblog/Views/PlacesVisitedView.swift` | **Modify** | Add `selectedMapFeature` + `selection:` binding + sheet to `PlacesVisitedMapView` |
| `fastblog.xcodeproj/project.pbxproj` | **Modify** | Register `POIInfoSheet.swift` |

---

## Task 1: Create `POIInfoSheet.swift`

**Files:**
- Create: `fastblog/Views/POIInfoSheet.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  POIInfoSheet.swift
//  fastblog
//
//  Bottom sheet presenting a Google Maps place page for a tapped map POI.
//

import MapKit
import SwiftUI

struct POIInfoSheet: View {
    let feature: MapFeature
    @Environment(\.dismiss) private var dismiss
    @State private var currentPageURL: URL? = nil

    private var googleMapsURL: URL {
        let name = feature.title.isEmpty ? "Nearby Place" : feature.title
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let lat = feature.coordinate.latitude
        let lng = feature.coordinate.longitude
        let urlString = "https://www.google.com/maps/search/?api=1&query=\(encoded)&center=\(lat),\(lng)"
        return URL(string: urlString) ?? URL(string: "https://www.google.com/maps")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(white: 0.5).opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Header
            HStack(alignment: .center) {
                Text(feature.title.isEmpty ? "Nearby Place" : feature.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            GoogleSearchEmbeddedWebView(url: googleMapsURL, currentPageURL: $currentPageURL)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
```

- [ ] **Step 2: Verify the file was written correctly**

Open `fastblog/Views/POIInfoSheet.swift` and confirm it compiles (no red markers in Xcode if open, or proceed and let the build in Task 5 catch issues).

---

## Task 2: Register `POIInfoSheet.swift` in the Xcode project

**Files:**
- Modify: `fastblog.xcodeproj/project.pbxproj`

Use IDs `BB00040C` (PBXFileReference) and `BB00040D` (PBXBuildFile). These are the next available sequential IDs beyond `BB00040A`/`BB00040B`.

- [ ] **Step 1: Add PBXBuildFile entry**

In `project.pbxproj`, find the block around line 229–230 (the `PBXBuildFile` section). After the line:
```
BB0003E1 /* GoogleSearchEmbeddedWebView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0003E0 /* GoogleSearchEmbeddedWebView.swift */; };
```
Add:
```
		BB00040D /* POIInfoSheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB00040C /* POIInfoSheet.swift */; };
```

- [ ] **Step 2: Add PBXFileReference entry**

Find the block around line 486 (the `PBXFileReference` section). After the line:
```
BB0003E0 /* GoogleSearchEmbeddedWebView.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = GoogleSearchEmbeddedWebView.swift; sourceTree = "<group>"; };
```
Add:
```
		BB00040C /* POIInfoSheet.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = POIInfoSheet.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add to Views PBXGroup**

Find the Views group block (ends with `path = Views;`). The group contains `BB0003E0 /* GoogleSearchEmbeddedWebView.swift */` at line ~745. After that line, add:
```
				BB00040C /* POIInfoSheet.swift */,
```

- [ ] **Step 4: Add to PBXSourcesBuildPhase**

Find the `PBXSourcesBuildPhase` block (around line 1178 where `BB0003E1` appears). After:
```
				BB0003E1 /* GoogleSearchEmbeddedWebView.swift in Sources */,
```
Add:
```
				BB00040D /* POIInfoSheet.swift in Sources */,
```

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/POIInfoSheet.swift fastblog.xcodeproj/project.pbxproj
git commit -m "feat: add POIInfoSheet for map POI web view bottom sheet"
```

---

## Task 3: Add POI tap support to `MapDayView` and `FullScreenMapView`

**Files:**
- Modify: `fastblog/Views/MapDayView.swift`

### Part A — `MapDayView`: add `onPOITapped` + `selection:` binding

- [ ] **Step 1: Add `onPOITapped` parameter to `MapDayView`**

In `MapDayView`'s property list (around line 32–38), add after `var hideStartEndMarkers: Bool = false`:

```swift
/// When set, called when the user taps a native MapKit POI. Only pass this in full-screen contexts.
var onPOITapped: ((MapFeature) -> Void)? = nil
```

- [ ] **Step 2: Add `selectedMapFeature` state**

In `MapDayView`'s `@State` block (around line 42, after `@State private var cameraPosition`), add:

```swift
@State private var selectedMapFeature: MapFeature?
```

- [ ] **Step 3: Update the `MapDayView` initializer**

The existing `init` (around line 44–51) takes explicit parameters. Add `onPOITapped` with a default:

```swift
init(placeStops: [PlaceStop], height: CGFloat = 220, onTap: (() -> Void)? = nil, focusedPlaceId: UUID? = nil, onAnnotationTap: ((UUID) -> Void)? = nil, hideStartEndMarkers: Bool = false, onPOITapped: ((MapFeature) -> Void)? = nil) {
    self.placeStops = placeStops
    self.height = height
    self.onTap = onTap
    self.focusedPlaceId = focusedPlaceId
    self.onAnnotationTap = onAnnotationTap
    self.hideStartEndMarkers = hideStartEndMarkers
    self.onPOITapped = onPOITapped
}
```

- [ ] **Step 4: Wire `selection:` into the `Map` call**

Find the line (around line 54):
```swift
        Map(position: $cameraPosition) {
```
Replace with:
```swift
        Map(position: $cameraPosition, selection: $selectedMapFeature) {
```

- [ ] **Step 5: Add `.onChange` to fire the callback**

Find the chain of modifiers on the `Map` view (around line 94–111, after `.mapStyle(...)`). Add after `.mapStyle(.standard(elevation: .flat))`:

```swift
        .onChange(of: selectedMapFeature) { _, newFeature in
            guard let newFeature, let onPOITapped else { return }
            onPOITapped(newFeature)
            selectedMapFeature = nil
        }
```

### Part B — `FullScreenMapView`: show `POIInfoSheet`

- [ ] **Step 6: Add state for the POI sheet in `FullScreenMapView`**

In `FullScreenMapView`'s `@State` block (around line 341–352), add:

```swift
@State private var activePOIFeature: MapFeature?
@State private var showPOISheet: Bool = false
```

- [ ] **Step 7: Pass `onPOITapped` to `MapDayView`**

Find the `MapDayView(...)` call inside `FullScreenMapView.body` (around line 445–454):
```swift
                    MapDayView(
                        placeStops: filteredStops,
                        height: geo.size.height,
                        onTap: nil,
                        focusedPlaceId: focusedPlaceId,
                        onAnnotationTap: { stopId in
                            guard let stop = filteredStops.first(where: { $0.id == stopId }) else { return }
                            openPhotoModal(for: stop)
                        },
                        hideStartEndMarkers: selectedCategory != nil
                    )
```
Replace with:
```swift
                    MapDayView(
                        placeStops: filteredStops,
                        height: geo.size.height,
                        onTap: nil,
                        focusedPlaceId: focusedPlaceId,
                        onAnnotationTap: { stopId in
                            guard let stop = filteredStops.first(where: { $0.id == stopId }) else { return }
                            openPhotoModal(for: stop)
                        },
                        hideStartEndMarkers: selectedCategory != nil,
                        onPOITapped: { feature in
                            activePOIFeature = feature
                            showPOISheet = true
                        }
                    )
```

- [ ] **Step 8: Attach the POI sheet to `FullScreenMapView`**

Find the outer `ZStack` in `FullScreenMapView.body` (the one that wraps everything starting around line 442). Find the last modifier on it (likely `.ignoresSafeArea(...)` or similar) and add after it:

```swift
        .sheet(isPresented: $showPOISheet, onDismiss: {
            activePOIFeature = nil
        }) {
            if let feature = activePOIFeature {
                POIInfoSheet(feature: feature)
            }
        }
```

- [ ] **Step 9: Commit**

```bash
git add fastblog/Views/MapDayView.swift
git commit -m "feat: add POI tap → web sheet to FullScreenMapView"
```

---

## Task 4: Add POI tap support to `PlacesVisitedMapView`

**Files:**
- Modify: `fastblog/Views/PlacesVisitedView.swift`

`PlacesVisitedMapView` is the private struct starting at line 732. It has its own `Map(position: $mapPosition)` at line 1033 that it owns directly.

- [ ] **Step 1: Add state for POI sheet**

In `PlacesVisitedMapView`'s `@State` block (around lines 743–755), add:

```swift
@State private var selectedMapFeature: MapFeature?
@State private var activePOIFeature: MapFeature?
@State private var showPOISheet: Bool = false
```

- [ ] **Step 2: Wire `selection:` into the `Map` call**

Find (around line 1033):
```swift
                Map(position: $mapPosition) {
```
Replace with:
```swift
                Map(position: $mapPosition, selection: $selectedMapFeature) {
```

- [ ] **Step 3: Add `.onChange` after the map's `.mapStyle` modifier**

Find the chain of Map modifiers (around line 1059–1070). After `.mapStyle(.standard(elevation: .realistic))`, add:

```swift
                .onChange(of: selectedMapFeature) { _, newFeature in
                    guard let newFeature else { return }
                    activePOIFeature = newFeature
                    showPOISheet = true
                    selectedMapFeature = nil
                }
```

- [ ] **Step 4: Attach the POI sheet to `PlacesVisitedMapView`**

Find the outer `ZStack` of `PlacesVisitedMapView` (the one containing the `GeometryReader` and filter chips). Add `.sheet` as a modifier on it (after other trailing modifiers, before the end of `var body: some View`):

```swift
        .sheet(isPresented: $showPOISheet, onDismiss: {
            activePOIFeature = nil
        }) {
            if let feature = activePOIFeature {
                POIInfoSheet(feature: feature)
            }
        }
```

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/PlacesVisitedView.swift
git commit -m "feat: add POI tap → web sheet to PlacesVisitedMapView"
```

---

## Task 5: Build and verify

- [ ] **Step 1: Run the build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Troubleshoot if `.onTapGesture` conflicts with POI selection**

If tapping a POI on the map in the simulator triggers `onTap?()` (navigating away) instead of firing the `selectedMapFeature` binding, it means the SwiftUI tap gesture is consuming the event. Fix by making the `onTapGesture` conditional on `onPOITapped` being nil in `MapDayView.swift`:

Find (around line 100–102 in `MapDayView`):
```swift
        .onTapGesture {
            onTap?()
        }
```
Replace with:
```swift
        .onTapGesture {
            if onPOITapped == nil {
                onTap?()
            }
        }
```
Then rebuild.

- [ ] **Step 3: Manual smoke test in simulator**

1. Open Places Visited → tap the map button → full-screen map loads
2. Tap any native POI (restaurant, park, etc.) on the map — bottom sheet slides up with Google Maps place page
3. Drag sheet to expand — full page visible
4. Tap Done — sheet dismisses, map returns to normal state
5. Open a blog → tap the map icon to open the full-screen day map
6. Tap a native POI — same bottom sheet behavior

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: POI tap → Google Maps web sheet on Places Visited and Blog maps"
```
