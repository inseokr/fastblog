# Place Editor Offline UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to open the place editor and save a place name even when offline or before their photo has been injected into a trip blog.

**Architecture:** Relax the place editor gate to require only `localIdentifier` (set at photo save time, never requires network). Add a `NetworkMonitor` singleton so we can show a one-time "poor connection" alert before opening the editor. Store any name saved before injection in a `pendingPlaceNames` dict keyed by `CapturedMoment.id`, and flush it when injection eventually fires.

**Tech Stack:** Swift, SwiftUI, Network.framework (`NWPathMonitor`), `CLGeocoder` (existing), `GeocodingService` (existing)

## Global Constraints

- iOS deployment target: 14.0+ (NWPathMonitor is iOS 12+, safe)
- All `@Published` mutations must happen on `@MainActor`
- No new ViewModels — all state lives in `TripsView` as `@State`; `NetworkMonitor` is a Service singleton
- Follow naming conventions in `.ai/skills/code/naming.md` (service suffix, singleton `.shared`)
- Register every new `.swift` file in `fastblog.xcodeproj/project.pbxproj` following the four-step pattern in `CLAUDE.md`
- Next available pbxproj IDs: `BB00F011` (PBXFileReference), `BB00F012` (PBXBuildFile)
- Services PBXGroup UUID: `BB0001B4`
- Do not modify the normal (active trip, good connection) flow

---

### Task 1: NetworkMonitor Service

**Files:**
- Create: `fastblog/Services/NetworkMonitor.swift`
- Modify: `fastblog.xcodeproj/project.pbxproj` (register new file)

**Interfaces:**
- Produces: `NetworkMonitor.shared.isConnected: Bool` — synchronous, readable from any `@MainActor` context

- [ ] **Step 1: Create `NetworkMonitor.swift`**

```swift
import Network
import Foundation

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.bloggo.networkmonitor")

    private(set) var isConnected: Bool = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }
}
```

- [ ] **Step 2: Register in `project.pbxproj` — PBXBuildFile section**

Find the block that starts `/* Begin PBXBuildFile section */` and add this line (place near other BB00F0xx entries):
```
		BB00F012 /* NetworkMonitor.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB00F011 /* NetworkMonitor.swift */; };
```

- [ ] **Step 3: Register in `project.pbxproj` — PBXFileReference section**

Find the block that starts `/* Begin PBXFileReference section */` and add this line near other BB00F0xx entries:
```
		BB00F011 /* NetworkMonitor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NetworkMonitor.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: Register in `project.pbxproj` — PBXGroup (Services group)**

Find `BB0001B4 /* Services */ = {` and add `BB00F011 /* NetworkMonitor.swift */,` inside its `children` array, after the last BB00F00x entry:
```
				BB00F011 /* NetworkMonitor.swift */,
```

- [ ] **Step 5: Register in `project.pbxproj` — PBXSourcesBuildPhase**

Find the `isa = PBXSourcesBuildPhase;` section's `files` array and add the build file reference near other BB00F0xx entries:
```
					BB00F012 /* NetworkMonitor.swift in Sources */,
```

- [ ] **Step 6: Build to verify registration**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add fastblog/Services/NetworkMonitor.swift fastblog.xcodeproj/project.pbxproj
git commit -m "feat: add NetworkMonitor singleton for connectivity checks"
```

---

### Task 2: Gate Relaxation + Connection Alert

Removes the `injectedPhotoId` requirement from `canOpenCaptionModePlaceEditor` and replaces the "Setting up place details…" toast with a connection-aware alert that fires once before opening the editor when offline.

**Files:**
- Modify: `fastblog/Views/TripsView.swift`
  - Lines ~3060–3092: add two new `@State` vars
  - Lines ~4442–4445: relax `canOpenCaptionModePlaceEditor`
  - Lines ~4148–4153: replace toast guard with alert logic
  - After the existing `.sheet(isPresented: $showCaptionModeEditPlaceSheet)` modifier: add `.alert` modifier

**Interfaces:**
- Consumes: `NetworkMonitor.shared.isConnected: Bool` (Task 1)
- Produces: `showPlaceEditorConnectionAlert: Bool` state consumed by `.alert` modifier

- [ ] **Step 1: Add alert state var**

In `TripsView.swift`, find the block of `@State` vars near line 3069 (`@State private var showCaptionModeEditPlaceSheet`). Add directly below it:

```swift
@State private var showPlaceEditorConnectionAlert = false
```

- [ ] **Step 2: Relax `canOpenCaptionModePlaceEditor`**

Find (around line 4442):
```swift
    private var canOpenCaptionModePlaceEditor: Bool {
        guard let moment = captionModeResolvedMoment else { return false }
        return moment.injectedPhotoId != nil && moment.localIdentifier != nil
    }
```

Replace with:
```swift
    private var canOpenCaptionModePlaceEditor: Bool {
        guard let moment = captionModeResolvedMoment else { return false }
        return moment.localIdentifier != nil
    }
```

- [ ] **Step 3: Replace toast with alert logic in the button action**

Find (around line 4148):
```swift
                            Button {
                                guard canOpenCaptionModePlaceEditor else {
                                    showToast("Setting up place details…")
                                    return
                                }
                                showCaptionModeEditPlaceSheet = true
```

Replace with:
```swift
                            Button {
                                guard canOpenCaptionModePlaceEditor else { return }
                                if !NetworkMonitor.shared.isConnected {
                                    showPlaceEditorConnectionAlert = true
                                } else {
                                    showCaptionModeEditPlaceSheet = true
                                }
```

- [ ] **Step 4: Add `.alert` modifier**

Find the line:
```swift
            .sheet(isPresented: $showCaptionModeEditPlaceSheet) {
```

Add the following `.alert` modifier **directly before** that `.sheet` line:
```swift
            .alert("Poor Connection", isPresented: $showPlaceEditorConnectionAlert) {
                Button("Got it") { showCaptionModeEditPlaceSheet = true }
            } message: {
                Text("We couldn't fetch the place name. You can still name this place yourself and it'll save to your trip.")
            }
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: relax place editor gate and show offline alert instead of toast"
```

---

### Task 3: Pending Name Store + Sheet Guard Fix + onSave Branch

Adds the `PendingPlaceName` store for names saved before injection. Also fixes the sheet's inner `Group` guard which currently blocks rendering when `injectedPhotoId` is nil.

**Files:**
- Modify: `fastblog/Views/TripsView.swift`
  - After existing `@State` vars: add `PendingPlaceName` struct + `pendingPlaceNames` state
  - `.sheet(isPresented: $showCaptionModeEditPlaceSheet)` inner guard: drop `photoId` requirement
  - `onSave` closure: add pending-path branch

**Interfaces:**
- Consumes: `captionModeMomentId: UUID?` (existing state)
- Produces: `pendingPlaceNames: [UUID: PendingPlaceName]` — consumed by Tasks 4 and 5

- [ ] **Step 1: Add `PendingPlaceName` struct and state var**

Find the `@State private var showPlaceEditorConnectionAlert` line added in Task 2. Add the struct and state var directly after the `@State` block (before the next `private struct` or `private var` computed property). A good insertion point is just after the `showPlaceEditorConnectionAlert` line:

```swift
    private struct PendingPlaceName {
        let name: String
        let subtitle: String?
        let category: String?
        let coordinate: CLLocationCoordinate2D?
    }

    @State private var pendingPlaceNames: [UUID: PendingPlaceName] = [:]
```

- [ ] **Step 2: Fix the sheet inner guard — remove `photoId` requirement**

Find (around line 4801):
```swift
            .sheet(isPresented: $showCaptionModeEditPlaceSheet) {
            Group {
                if let moment = captionModeResolvedMoment,
                   let photoId = moment.injectedPhotoId,
                   let lid = moment.localIdentifier {
                    let coord = moment.location?.clCoordinate ?? cameraController.currentLocation?.coordinate
                    EditPlaceStopNameSheet(
                        placeTitle: $captionModePlaceTitle,
                        initialPlaceSubtitle: captionModePlaceSubtitle,
                        location: coord,
                        photos: [RecapPhoto(
                            id: photoId,
                            timestamp: moment.timestamp,
                            location: moment.location,
                            imageName: "camera.fill",
                            localIdentifier: lid,
                            caption: moment.caption
                        )],
                        onSave: { name, coord, category, subtitle in
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            captionModePlaceRefreshToken += 1
                            if !trimmedName.isEmpty {
                                captionModePlaceTitle = trimmedName
                            }
                            captionModePlaceSubtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
                            createdRecapStore.updatePlaceStopFromPlacesVisited(
                                photoId: photoId,
                                newName: name,
                                category: category,
                                coordinate: coord,
                                subtitle: subtitle
                            )
                        }
                    )
                }
            }
```

Replace with:
```swift
            .sheet(isPresented: $showCaptionModeEditPlaceSheet) {
            Group {
                if let moment = captionModeResolvedMoment,
                   let lid = moment.localIdentifier {
                    let photoId = moment.injectedPhotoId
                    let coord = moment.location?.clCoordinate ?? cameraController.currentLocation?.coordinate
                    EditPlaceStopNameSheet(
                        placeTitle: $captionModePlaceTitle,
                        initialPlaceSubtitle: captionModePlaceSubtitle,
                        location: coord,
                        photos: [RecapPhoto(
                            id: photoId ?? moment.id,
                            timestamp: moment.timestamp,
                            location: moment.location,
                            imageName: "camera.fill",
                            localIdentifier: lid,
                            caption: moment.caption
                        )],
                        onSave: { name, coord, category, subtitle in
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            captionModePlaceRefreshToken += 1
                            if !trimmedName.isEmpty { captionModePlaceTitle = trimmedName }
                            captionModePlaceSubtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle

                            if let pid = photoId {
                                createdRecapStore.updatePlaceStopFromPlacesVisited(
                                    photoId: pid,
                                    newName: name,
                                    category: category,
                                    coordinate: coord,
                                    subtitle: subtitle
                                )
                            } else if let momentId = captionModeMomentId {
                                pendingPlaceNames[momentId] = PendingPlaceName(
                                    name: trimmedName,
                                    subtitle: trimmedSubtitle.isEmpty ? nil : trimmedSubtitle,
                                    category: category,
                                    coordinate: coord
                                )
                            }
                        }
                    )
                }
            }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: add pending name store and fix sheet guard for offline place editing"
```

---

### Task 4: Geocoding Protection

Prevents `refreshCaptionModePlaceChrome` from overwriting a user-set pending name with "Captured Moment" or a geocoded result.

**Files:**
- Modify: `fastblog/Views/TripsView.swift` — `refreshCaptionModePlaceChrome` function (~line 3320)

**Interfaces:**
- Consumes: `pendingPlaceNames: [UUID: PendingPlaceName]` (Task 3), `captionModeMomentId: UUID?` (existing)

- [ ] **Step 1: Add pending-name guard at the top of `refreshCaptionModePlaceChrome`**

Find (around line 3320):
```swift
    private func refreshCaptionModePlaceChrome() {
        captionModePlaceRefreshToken += 1
        let refreshToken = captionModePlaceRefreshToken
        guard let moment = captionModeResolvedMoment else {
            captionModePlaceTitle = "Captured Moment"
            captionModePlaceSubtitle = nil
            return
        }

        // Fast default only — `getBlogDetail` can walk a huge in-memory blog graph and stall
        // the first frame after capture if we run it synchronously when opening the preview.
        captionModePlaceTitle = "Captured Moment"
        captionModePlaceSubtitle = nil
```

Replace with:
```swift
    private func refreshCaptionModePlaceChrome() {
        captionModePlaceRefreshToken += 1
        let refreshToken = captionModePlaceRefreshToken
        guard let moment = captionModeResolvedMoment else {
            captionModePlaceTitle = "Captured Moment"
            captionModePlaceSubtitle = nil
            return
        }

        // If the user already named this place (offline save), respect it — skip geocoding entirely.
        if let momentId = captionModeMomentId,
           let pending = pendingPlaceNames[momentId] {
            captionModePlaceTitle = pending.name
            captionModePlaceSubtitle = pending.subtitle
            return
        }

        // Fast default only — `getBlogDetail` can walk a huge in-memory blog graph and stall
        // the first frame after capture if we run it synchronously when opening the preview.
        captionModePlaceTitle = "Captured Moment"
        captionModePlaceSubtitle = nil
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: protect user-set place name from geocoding overwrite"
```

---

### Task 5: Flush Pending Name on Injection

When a photo is eventually injected into a blog (via `injectCapturedImageIntoBlog` or `injectCapturedPhotoIntoCameraDraft`), propagate the pending name into `MockPhoto.locationName` and then call `updatePlaceStopFromPlacesVisited` after injection to persist category/coordinate data.

**Files:**
- Modify: `fastblog/Views/TripsView.swift`
  - `injectCapturedImageIntoBlog` (~line 6385)
  - `injectCapturedPhotoIntoCameraDraft` (~line 6429)

**Interfaces:**
- Consumes: `pendingPlaceNames: [UUID: PendingPlaceName]` (Task 3), existing injection functions

- [ ] **Step 1: Update `injectCapturedImageIntoBlog`**

Find the Task block inside `injectCapturedImageIntoBlog` that creates `MockPhoto` (around line 6404):

```swift
        Task { @MainActor in
            var locationName: String? = nil
            var countryName: String? = nil
            if let geo = geoForPlace {
                let place = await GeocodingService.shared.place(for: geo)
                locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                countryName = place.countryName != "Unknown" ? place.countryName : nil
            }
            let photo = MockPhoto(
                id: momentId,
                imageName: "camera.fill",
                timestamp: timestamp,
                locationName: locationName ?? "Captured Moment",
                countryName: countryName,
                isSelected: true,
                localIdentifier: localId,
                location: photoLocation
            )
            createdRecapStore.injectPhotos([photo], intoSourceTripId: sourceTripId)
            sessionTripTitle = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId })?.title
            attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
        }
```

Replace with:
```swift
        let pendingName = pendingPlaceNames[momentId]
        Task { @MainActor in
            var locationName: String? = nil
            var countryName: String? = nil
            if pendingName == nil, let geo = geoForPlace {
                let place = await GeocodingService.shared.place(for: geo)
                locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                countryName = place.countryName != "Unknown" ? place.countryName : nil
            }
            let photo = MockPhoto(
                id: momentId,
                imageName: "camera.fill",
                timestamp: timestamp,
                locationName: pendingName?.name ?? locationName ?? "Captured Moment",
                countryName: pendingName?.subtitle ?? countryName,
                isSelected: true,
                localIdentifier: localId,
                location: photoLocation
            )
            createdRecapStore.injectPhotos([photo], intoSourceTripId: sourceTripId)
            if let pending = pendingName {
                createdRecapStore.updatePlaceStopFromPlacesVisited(
                    photoId: momentId,
                    newName: pending.name,
                    category: pending.category,
                    coordinate: pending.coordinate,
                    subtitle: pending.subtitle
                )
                pendingPlaceNames.removeValue(forKey: momentId)
            }
            sessionTripTitle = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId })?.title
            attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
        }
```

- [ ] **Step 2: Update `injectCapturedPhotoIntoCameraDraft`**

Find the Task block inside `injectCapturedPhotoIntoCameraDraft` that creates `MockPhoto` (around line 6447):

```swift
        Task { @MainActor in
            var locationName = "Captured Moment"
            var countryName: String? = nil
            if let geo = geoForPlace {
                let place = await GeocodingService.shared.place(for: geo)
                locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                countryName = place.countryName != "Unknown" ? place.countryName : nil
            }
            let photo = MockPhoto(
                id: photoId,
                imageName: "camera.fill",
                timestamp: timestamp,
                locationName: locationName,
                countryName: countryName,
                isSelected: true,
                localIdentifier: localId,
                location: photoLocation
            )
            tripsViewModel.appendPhotosToCameraDraft(tripId: tripId, newPhotos: [photo])
            let draftTitle = tripsViewModel.tripDrafts.first(where: { $0.id == tripId })?.title
            if let t = draftTitle, !t.isEmpty { sessionTripTitle = t }
            attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
        }
```

Replace with:
```swift
        let pendingName = pendingPlaceNames[momentId]
        Task { @MainActor in
            var locationName = "Captured Moment"
            var countryName: String? = nil
            if pendingName == nil, let geo = geoForPlace {
                let place = await GeocodingService.shared.place(for: geo)
                locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                countryName = place.countryName != "Unknown" ? place.countryName : nil
            }
            let photo = MockPhoto(
                id: photoId,
                imageName: "camera.fill",
                timestamp: timestamp,
                locationName: pendingName?.name ?? locationName,
                countryName: pendingName?.subtitle ?? countryName,
                isSelected: true,
                localIdentifier: localId,
                location: photoLocation
            )
            tripsViewModel.appendPhotosToCameraDraft(tripId: tripId, newPhotos: [photo])
            if let pending = pendingName {
                createdRecapStore.updatePlaceStopFromPlacesVisited(
                    photoId: photoId,
                    newName: pending.name,
                    category: pending.category,
                    coordinate: pending.coordinate,
                    subtitle: pending.subtitle
                )
                pendingPlaceNames.removeValue(forKey: momentId)
            }
            let draftTitle = tripsViewModel.tripDrafts.first(where: { $0.id == tripId })?.title
            if let t = draftTitle, !t.isEmpty { sessionTripTitle = t }
            attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
        }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: flush pending place name into MockPhoto on injection"
```

---

## Manual Verification Checklist

After all tasks pass build, test these flows on simulator or device:

**Offline / no injection path:**
1. Disable network (airplane mode or Wi-Fi off)
2. Take a photo in Daily (My Places) mode
3. Tap the "Captured Moment" chip — alert should fire: "Poor Connection … Got it"
4. Tap "Got it" — place editor opens, pre-filled "Captured Moment"
5. Type "Playa del Rey", tap Save — chip updates to "Playa del Rey" immediately
6. Re-enable network, confirm a trip — injection fires, place stop is created with "Playa del Rey"
7. `refreshCaptionModePlaceChrome` re-fires — chip still shows "Playa del Rey" (not overwritten)

**Good connection / active trip path:**
1. Take a photo with an active trip selected
2. Tap the place name chip — no alert, editor opens directly
3. Geocoded name visible, save works normally via `updatePlaceStopFromPlacesVisited`
4. No regression in this flow
