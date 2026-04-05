# Unused Photos Storage Management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Unused Photos" screen (StorageManagementView) accessible from BlogSettingsSheet that lets users browse, filter, and delete photos where `isIncluded == false`.

**Architecture:** One new SwiftUI view file pushed onto BlogSettingsSheet's existing NavigationStack via NavigationLink. No new NavigationStack or sheet. View receives `@Binding var draft: RecapBlogDetail` and `var onSave: () -> Void`, consistent with the rest of BlogSettingsSheet's sub-views.

**Tech Stack:** SwiftUI, Photos framework (PHPhotoLibrary for device-photo deletion), InAppCameraPhotoStore (existing singleton for in-app camera photo deletion).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `fastblog/Views/BlogSettingsSheet.swift` | Add `NavigationLink` row for "Unused Photos" in `editAndRestoreSection` |
| Create | `fastblog/Views/StorageManagementView.swift` | Full screen: grid, selection mode, filter dropdown, delete flow, empty state |

---

### Task 1: Add "Unused Photos" entry point in BlogSettingsSheet

**Files:**
- Modify: `fastblog/Views/BlogSettingsSheet.swift:133-168` (`editAndRestoreSection`)

- [ ] **Step 1: Read the current `editAndRestoreSection`**

Open `fastblog/Views/BlogSettingsSheet.swift`, lines 133–168. Confirm the `Section { }` block and where to insert.

- [ ] **Step 2: Add a `NavigationLink` row at the bottom of `editAndRestoreSection`**

Inside the closing `}` of the existing `Section { }` in `editAndRestoreSection`, add this link **after** the `onRescanAllMoments` block and **before** the closing `}` of `Section`:

```swift
NavigationLink {
    StorageManagementView(draft: $draft, onSave: onSave)
} label: {
    Label("Unused Photos", systemImage: "photo.badge.minus")
}
```

The full `editAndRestoreSection` should now end with:

```swift
        if onRescanAllMoments != nil {
            Button {
                onRescanAllMoments?()
                dismiss()
            } label: {
                Label("Rescan All Moments", systemImage: "arrow.clockwise.circle")
            }
        }
        NavigationLink {
            StorageManagementView(draft: $draft, onSave: onSave)
        } label: {
            Label("Unused Photos", systemImage: "photo.badge.minus")
        }
    }
}
```

- [ ] **Step 3: Build — confirm no compile errors**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED` (StorageManagementView doesn't exist yet — this will fail until Task 2 creates the stub)

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/BlogSettingsSheet.swift
git commit -m "feat: add Unused Photos navigation link to BlogSettingsSheet"
```

---

### Task 2: Scaffold StorageManagementView with data model

**Files:**
- Create: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Create the file with view scaffold + computed properties**

```swift
//
//  StorageManagementView.swift
//  fastblog
//

import SwiftUI
import Photos

struct StorageManagementView: View {
    @Binding var draft: RecapBlogDetail
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Selection state
    @State private var isSelectMode = false
    @State private var selectedPhotoIds: Set<UUID> = []

    // MARK: - Filter state
    @State private var activeDayFilter: Int? = nil
    @State private var showFilterDropdown = false

    // MARK: - Delete state
    @State private var pendingInApp: [RecapPhoto] = []
    @State private var pendingPhone: [RecapPhoto] = []
    @State private var deletedAny = false
    @State private var showInAppAlert = false
    @State private var showPhoneAlert = false

    // MARK: - Grid layout (matches ManagePhotosView)
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    // MARK: - Derived data

    /// Flat list of (dayIndex, photo) for all photos where isIncluded == false.
    private var allUnused: [(dayIndex: Int, photo: RecapPhoto)] {
        draft.days.flatMap { day in
            day.placeStops.flatMap { stop in
                stop.photos
                    .filter { !$0.isIncluded }
                    .map { (day.dayIndex, $0) }
            }
        }
    }

    /// Unused photos visible in the grid — respects active day filter.
    private var visiblePhotos: [(dayIndex: Int, photo: RecapPhoto)] {
        guard let filter = activeDayFilter else { return allUnused }
        return allUnused.filter { $0.dayIndex == filter }
    }

    /// Days that have at least one unused photo, for the filter dropdown.
    private var filterableDays: [(dayIndex: Int, date: Date)] {
        let daysWithPhotos = Set(allUnused.map(\.dayIndex))
        return draft.days
            .filter { daysWithPhotos.contains($0.dayIndex) }
            .map { ($0.dayIndex, $0.date) }
            .sorted { $0.dayIndex < $1.dayIndex }
    }

    var body: some View {
        Text("StorageManagementView placeholder")
            .navigationTitle(isSelectMode ? "\(selectedPhotoIds.count) selected" : "Unused Photos")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: Build to confirm scaffold compiles**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: scaffold StorageManagementView with data model"
```

---

### Task 3: Photo grid

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Replace the placeholder `body` with a ZStack + ScrollView + LazyVGrid**

Replace the `body` computed property:

```swift
var body: some View {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        photoGrid
    }
    .navigationTitle(isSelectMode ? "\(selectedPhotoIds.count) selected" : "Unused Photos")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar { navigationToolbar }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Add `photoGrid` and `photoCell` computed properties**

Add these below `body`:

```swift
private var photoGrid: some View {
    Group {
        if visiblePhotos.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(visiblePhotos, id: \.photo.id) { item in
                        photoCell(item.photo)
                    }
                }
            }
        }
    }
}

private func photoCell(_ photo: RecapPhoto) -> some View {
    let size = (UIScreen.main.bounds.width - 4) / 3
    return RecapPhotoThumbnail(
        photo: photo,
        cornerRadius: 0,
        targetSize: CGSize(width: size * 2, height: size * 2)
    )
    .frame(width: size, height: size)
    .clipped()
    .contentShape(Rectangle())
    .onTapGesture {
        if isSelectMode { toggleSelection(photo.id) }
    }
}
```

- [ ] **Step 3: Add `emptyState` placeholder (full content added in Task 9)**

```swift
private var emptyState: some View {
    VStack(spacing: 12) {
        Image(systemName: "photo.on.rectangle")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
        Text("No unused photos")
            .font(.headline)
        Text("All photos in this blog are included.")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 4: Add stub `navigationToolbar` and helper**

```swift
@ToolbarContentBuilder
private var navigationToolbar: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
        if isSelectMode {
            Button("Cancel") { exitSelectMode() }
        } else {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
            }
        }
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        if isSelectMode {
            Button("Select All") { selectAll() }
        } else {
            Button("Select") { enterSelectMode() }
        }
    }
}

private func enterSelectMode() {
    isSelectMode = true
    selectedPhotoIds = []
}

private func exitSelectMode() {
    isSelectMode = false
    selectedPhotoIds = []
    showFilterDropdown = false
}

private func toggleSelection(_ id: UUID) {
    if selectedPhotoIds.contains(id) {
        selectedPhotoIds.remove(id)
    } else {
        selectedPhotoIds.insert(id)
    }
}

private func selectAll() {
    selectedPhotoIds = Set(visiblePhotos.map(\.photo.id))
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: add photo grid to StorageManagementView"
```

---

### Task 4: Photo cell selection overlay (checkmark + dim)

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Replace the `photoCell` function with one that includes the selection overlay**

Replace the existing `photoCell` function:

```swift
private func photoCell(_ photo: RecapPhoto) -> some View {
    let size = (UIScreen.main.bounds.width - 4) / 3
    let isSelected = selectedPhotoIds.contains(photo.id)

    return ZStack(alignment: .bottomTrailing) {
        RecapPhotoThumbnail(
            photo: photo,
            cornerRadius: 0,
            targetSize: CGSize(width: size * 2, height: size * 2)
        )
        .frame(width: size, height: size)
        .clipped()
        .opacity(isSelectMode && !isSelected ? 0.4 : 1.0)

        if isSelectMode {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .padding(4)
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(4)
            }
        }
    }
    .contentShape(Rectangle())
    .onTapGesture {
        if isSelectMode { toggleSelection(photo.id) }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: add selection overlay (checkmark/dim) to photo cells"
```

---

### Task 5: Bottom floating buttons (select mode only)

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Add `floatingButtons` overlay to the ZStack in `body`**

Update `body`'s ZStack:

```swift
var body: some View {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        photoGrid
        if isSelectMode {
            floatingButtons
        }
    }
    .navigationTitle(isSelectMode ? "\(selectedPhotoIds.count) selected" : "Unused Photos")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar { navigationToolbar }
    .preferredColorScheme(.dark)
    // (alerts added in Task 7)
}
```

- [ ] **Step 2: Add `floatingButtons` computed property**

```swift
private var floatingButtons: some View {
    HStack {
        // Filter button (left)
        let filterActive = activeDayFilter != nil || showFilterDropdown
        Button {
            showFilterDropdown.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundColor(filterActive ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white)
                .padding(12)
                .background(
                    filterActive
                        ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.2)
                        : Color.white.opacity(0.12),
                    in: Circle()
                )
        }

        Spacer()

        // Trash button (right)
        Button {
            beginDeleteSelected()
        } label: {
            Image(systemName: "trash")
                .font(.title2)
                .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                .padding(12)
                .background(
                    Color(red: 0.4, green: 0.08, blue: 0.06),
                    in: Circle()
                )
        }
        .disabled(selectedPhotoIds.isEmpty)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .background(.ultraThinMaterial)
}
```

- [ ] **Step 3: Add `beginDeleteSelected` stub (full logic in Task 7)**

```swift
private func beginDeleteSelected() {
    let selected = visiblePhotos
        .filter { selectedPhotoIds.contains($0.photo.id) }
        .map(\.photo)
    pendingInApp = selected.filter { $0.localIdentifier == nil || $0.localIdentifier!.isEmpty }
    pendingPhone = selected.filter { let id = $0.localIdentifier; return id != nil && !id!.isEmpty }
    deletedAny = false
    if !pendingInApp.isEmpty {
        showInAppAlert = true
    } else if !pendingPhone.isEmpty {
        showPhoneAlert = true
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: add floating filter + trash buttons for select mode"
```

---

### Task 6: Day filter dropdown overlay

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Add `filterDropdown` and dismiss-tap overlay to the ZStack in `body`**

Update `body`'s ZStack to add the dropdown above the floating buttons:

```swift
var body: some View {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        photoGrid
        if isSelectMode {
            floatingButtons
        }
        if showFilterDropdown {
            // Tap-to-dismiss background
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { showFilterDropdown = false }

            // Dropdown anchored bottom-left, above floating buttons
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    filterDropdown
                        .padding(.leading, 16)
                        .padding(.bottom, 88) // sits above the floating button bar
                    Spacer()
                }
            }
        }
    }
    .navigationTitle(isSelectMode ? "\(selectedPhotoIds.count) selected" : "Unused Photos")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar { navigationToolbar }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Add `filterDropdown` computed property**

```swift
private var filterDropdown: some View {
    VStack(alignment: .leading, spacing: 0) {
        Text("FILTER BY DAY")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

        Divider().background(Color.white.opacity(0.1))

        ForEach(filterableDays, id: \.dayIndex) { item in
            let isActive = activeDayFilter == item.dayIndex
            Button {
                activeDayFilter = isActive ? nil : item.dayIndex
                showFilterDropdown = false
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(dayColor(for: item.dayIndex))
                        .frame(width: 8, height: 8)
                    Text("Day \(item.dayIndex + 1)")
                        .foregroundColor(.white)
                    Text(formattedDate(item.date))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            if item.dayIndex != filterableDays.last?.dayIndex {
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
            }
        }
    }
    .background(
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.97))
            .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 4)
    )
    .frame(minWidth: 220, maxWidth: 280)
}

private func dayColor(for dayIndex: Int) -> Color {
    let colors: [Color] = [
        Color(red: 0.4, green: 0.65, blue: 1.0),
        Color(red: 0.35, green: 0.85, blue: 0.5),
        Color(red: 1.0, green: 0.6, blue: 0.2),
        Color(red: 0.75, green: 0.4, blue: 0.95),
        Color(red: 1.0, green: 0.35, blue: 0.35),
        Color(red: 1.0, green: 0.85, blue: 0.3),
    ]
    return colors[dayIndex % colors.count]
}

private func formattedDate(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    return fmt.string(from: date)
}
```

- [ ] **Step 3: Also update the `activeDayFilter` setter logic — when filter changes, clear selection that is no longer visible**

Add this modifier to `body`, after `.preferredColorScheme(.dark)`:

```swift
.onChange(of: activeDayFilter) { _ in
    // Remove selected IDs that are no longer visible after filter change
    let visibleIds = Set(visiblePhotos.map(\.photo.id))
    selectedPhotoIds = selectedPhotoIds.intersection(visibleIds)
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: add day filter dropdown to StorageManagementView"
```

---

### Task 7: Delete flow — confirmations and execution

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Add two `.alert` modifiers to `body`**

Append these two modifiers after `.onChange(of: activeDayFilter)`:

```swift
.alert(
    "Delete \(pendingInApp.count) Photo\(pendingInApp.count == 1 ? "" : "s") From Bloggo?",
    isPresented: $showInAppAlert
) {
    Button("Delete", role: .destructive) { executeDeleteInApp() }
    Button("No", role: .cancel) {
        pendingInApp = []
        if !pendingPhone.isEmpty { showPhoneAlert = true }
    }
} message: {
    Text("Removes from Bloggo gallery.")
}
.alert(
    "Delete \(pendingPhone.count) Photo\(pendingPhone.count == 1 ? "" : "s") From Phone?",
    isPresented: $showPhoneAlert
) {
    Button("Delete", role: .destructive) { executeDeletePhone() }
    Button("No", role: .cancel) {
        pendingPhone = []
        finishDeleteFlow()
    }
} message: {
    Text("Removes from your device.")
}
```

- [ ] **Step 2: Add `executeDeleteInApp`, `executeDeletePhone`, `removeFromDraft`, and `finishDeleteFlow`**

```swift
// MARK: - Delete helpers

private func executeDeleteInApp() {
    // Remove files from InAppCameraPhotoStore
    // imageName for in-app camera photos is "UUID.jpg" or "UUID" — try both
    let storeIds: Set<UUID> = Set(pendingInApp.compactMap { photo in
        let name = photo.imageName
        if let direct = UUID(uuidString: name) { return direct }
        let stripped = (name as NSString).deletingPathExtension
        return UUID(uuidString: stripped)
    })
    if !storeIds.isEmpty {
        InAppCameraPhotoStore.shared.removePhotos(ids: storeIds)
    }
    removeFromDraft(pendingInApp)
    deletedAny = true
    pendingInApp = []

    if !pendingPhone.isEmpty {
        showPhoneAlert = true
    } else {
        finishDeleteFlow()
    }
}

private func executeDeletePhone() {
    let photos = pendingPhone
    let identifiers = photos.compactMap(\.localIdentifier).filter { !$0.isEmpty }
    guard !identifiers.isEmpty else {
        removeFromDraft(photos)
        deletedAny = true
        pendingPhone = []
        finishDeleteFlow()
        return
    }
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.deleteAssets(fetchResult)
    }) { _, _ in
        DispatchQueue.main.async {
            self.removeFromDraft(photos)
            self.deletedAny = true
            self.pendingPhone = []
            self.finishDeleteFlow()
        }
    }
}

private func removeFromDraft(_ photos: [RecapPhoto]) {
    let ids = Set(photos.map(\.id))
    for dayIdx in draft.days.indices {
        for stopIdx in draft.days[dayIdx].placeStops.indices {
            draft.days[dayIdx].placeStops[stopIdx].photos.removeAll { ids.contains($0.id) }
        }
    }
}

private func finishDeleteFlow() {
    if deletedAny { onSave() }
    deletedAny = false
    // Clean up selection — remove IDs that no longer exist
    let remaining = Set(visiblePhotos.map(\.photo.id))
    selectedPhotoIds = selectedPhotoIds.intersection(remaining)
    // If no photos left in view, exit select mode
    if visiblePhotos.isEmpty {
        isSelectMode = false
        selectedPhotoIds = []
        activeDayFilter = nil
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: implement delete flow with two-phase confirmation in StorageManagementView"
```

---

### Task 8: Final polish — empty state and wire up

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

The `emptyState` view was added in Task 3 as part of `photoGrid`. Verify it is shown correctly when `visiblePhotos.isEmpty`. No code change needed unless it wasn't wired up.

- [ ] **Step 1: Verify `photoGrid` shows `emptyState` when `visiblePhotos.isEmpty`**

Confirm `photoGrid` reads:

```swift
private var photoGrid: some View {
    Group {
        if visiblePhotos.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(visiblePhotos, id: \.photo.id) { item in
                        photoCell(item.photo)
                    }
                }
            }
        }
    }
}
```

If the `else` branch is missing, add it now.

- [ ] **Step 2: Ensure `emptyState` is centered**

Replace `emptyState` with a version that fills the screen:

```swift
private var emptyState: some View {
    VStack(spacing: 12) {
        Image(systemName: "photo.on.rectangle")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
        Text("No unused photos")
            .font(.headline)
            .foregroundColor(.primary)
        Text("All photos in this blog are included.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 3: Build and smoke-test on simulator**

Run: `xcodebuild -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `BUILD SUCCEEDED`

Open the app on simulator, navigate to a blog → Blog Settings → "Unused Photos". Verify:
- Row appears in settings
- Tapping pushes StorageManagementView (no extra nav chrome)
- Back chevron (no text) appears in the leading position
- "Select" button appears trailing
- Tapping "Select" shows "Cancel" (leading) + "0 selected" (title) + "Select All" (trailing)
- Tapping a photo in select mode toggles checkmark/dim
- Filter button appears bottom-left in select mode; Trash button bottom-right
- Tapping filter button shows dropdown; tapping outside dismisses it
- Selecting a day filter updates the grid
- Tapping Trash with selections shows the appropriate confirmation dialog(s)
- After delete, the photo is removed from the grid

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/StorageManagementView.swift
git commit -m "feat: finalize StorageManagementView empty state and wiring"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Entry point: "Unused Photos" row in BlogSettingsSheet | Task 1 |
| NavigationLink pushes onto existing NavStack (no new sheet) | Task 1 |
| Back button = chevron only (no text) | Task 3 |
| Normal mode toolbar: Select trailing | Task 3 |
| Select mode toolbar: Cancel leading, N selected title, Select All trailing | Task 3 |
| 3-column LazyVGrid, 2pt spacing | Task 3 |
| Photos where `isIncluded == false` | Task 2 (allUnused) |
| Select mode: filled blue checkmark (selected), dimmed + empty circle (unselected) | Task 4 |
| Bottom floating buttons: filter + trash (select mode only) | Task 5 |
| Filter button color: white / blue when active or open | Task 5 |
| Trash button: red icon + dark red bg | Task 5 |
| Filter dropdown as overlay (no grid shift) | Task 6 |
| Dropdown: FILTER BY DAY header, colored dot + Day N + date + checkmark | Task 6 |
| Only days with excluded photos shown | Task 2 (filterableDays) |
| Select All respects active filter | Task 3 (selectAll uses visiblePhotos) |
| Tap outside dropdown dismisses it | Task 6 |
| Delete: in-app (`localIdentifier == nil`) → InAppCameraPhotoStore + remove from draft | Task 7 |
| Delete: phone (`localIdentifier != nil`) → PHPhotoLibrary + remove from draft | Task 7 |
| Batch: one confirmation per type in sequence | Task 7 |
| "No" to one type still allows delete of other | Task 7 |
| Call `onSave()` after deletion | Task 7 |
| Empty state: icon + "No unused photos" + subtitle | Task 8 |
| Dark mode only (`preferredColorScheme(.dark)`) | Task 2 |

**Placeholder scan:** No TBD, TODO, or "similar to Task N" references found.

**Type consistency:**
- `allUnused`, `visiblePhotos` both return `[(dayIndex: Int, photo: RecapPhoto)]` — consistent in Tasks 2, 3, 4, 5, 7.
- `pendingInApp`, `pendingPhone` are `[RecapPhoto]` throughout Tasks 5, 7.
- `removeFromDraft(_:)` takes `[RecapPhoto]` — called correctly in Task 7.
- `finishDeleteFlow()` references `visiblePhotos` — same computed property throughout.
