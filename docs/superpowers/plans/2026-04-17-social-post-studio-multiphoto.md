# Social Post Studio — Multi-Photo Mode (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable `.multiPhoto` style mode end-to-end: one slide per PlaceStop with up to 3 stacked photos, selection rings, context menus, replace/add/trash/duplicate actions, a photo picker sheet, and a mode-switch confirmation gate.

**Architecture:** All rendering lives in `CarouselSlideView` so `ImageRenderer` export stays WYSIWYG. `SlideTextEditorView` owns photo-action mutations and picker state. `SocialPostStudioSheet` guards mode switches with a confirmation alert when customizations exist.

**Tech Stack:** SwiftUI, Photos framework (`PHImageManager`), `ImageRenderer`, `ContentUnavailableView`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `fastblog/Views/CarouselStudioSheet.swift` | Modify | All model, rendering, toolbar, and mode-switch changes |
| `fastblog/Views/SlidePhotoPickerSheet.swift` | Create | Photo picker grid sheet |
| `fastblog/fastblog.xcodeproj/project.pbxproj` | Modify | Register new file |

---

### Task 1: Rename `TextBlockID` → `SlideBlockID` and add `.photoSlot(Int)`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift`

- [ ] **Step 1: Replace the enum declaration (line 52–56)**

Change:
```swift
enum TextBlockID: Equatable, Hashable {
    case primary    // cover title / map heading / place name+subtitle
    case secondary  // map story / place caption
}
```
To:
```swift
/// Identifies which block in a slide is active in the editor.
enum SlideBlockID: Equatable, Hashable {
    case primary          // place name + subtitle / cover title / map heading
    case secondary        // map story / place caption
    case photoSlot(Int)   // index into slide.photoSlots (multi-photo mode)
}
```

- [ ] **Step 2: Update `DraggableTextBlock` (line ~133)**

Change `let id: TextBlockID` → `let id: SlideBlockID`.

- [ ] **Step 3: Update `CarouselSlideView` properties (lines ~252–260)**

Change all four `TextBlockID` references to `SlideBlockID`:
```swift
var selectedBlockID: SlideBlockID? = nil
var onSelectBlock: ((SlideBlockID) -> Void)? = nil
var onUpdateBlockCenter: ((SlideBlockID, CGPoint?) -> Void)? = nil
```

- [ ] **Step 4: Update `centerBinding(for:)` in `CarouselSlideView` (line ~268)**

```swift
private func centerBinding(for id: SlideBlockID) -> Binding<CGPoint?> {
```

- [ ] **Step 5: Update `SlideEditPage` (lines ~524–525)**

```swift
let selectedBlock: SlideBlockID?
let onSelectBlock: (SlideBlockID) -> Void
```

- [ ] **Step 6: Update `SlideTextEditorView` state and helper types (lines ~575, ~603, ~619, ~643, ~651)**

```swift
@State private var selectedBlock: SlideBlockID? = nil

private var availableBlocks: [SlideBlockID] { ... }

private var currentStyle: TextBlockStyle {
    guard let slide = currentSlide else { return TextBlockStyle() }
    return selectedBlock == .secondary ? slide.textStyle.secondary : slide.textStyle.primary
}

private func updateStyle(_ update: (inout TextBlockStyle) -> Void) {
    guard let selectedBlock, hasValidCurrentIndex else { return }
    if selectedBlock == .secondary { update(&slides[currentIndex].textStyle.secondary) }
    else { update(&slides[currentIndex].textStyle.primary) }
}

private func deleteSelectedBlock() {
    guard let selectedBlock, hasValidCurrentIndex else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
        if selectedBlock == .primary {
            slides[currentIndex].isPrimaryHidden = true
        } else {
            slides[currentIndex].isSecondaryHidden = true
        }
    }
    self.selectedBlock = availableBlocks.first
}
```

- [ ] **Step 7: Build to verify rename is clean**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 8: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "refactor: rename TextBlockID → SlideBlockID, add .photoSlot(Int) case"
```

---

### Task 2: Add `CarouselPhotoSlot` struct and `photoSlots` field on `CarouselSlide`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift`

- [ ] **Step 1: Add `CarouselPhotoSlot` struct after the `SlideBlockID` enum**

Insert immediately after the `SlideBlockID` enum closing brace:

```swift
struct CarouselPhotoSlot: Identifiable, Equatable {
    let id: String              // stable UUID string for SwiftUI diffing
    var photoID: String         // source-of-truth RecapPhoto.id (as UUID string)
    var localIdentifier: String?
    var image: UIImage?
    var caption: String?        // overlays on middle / bottom slots when non-empty
}
```

- [ ] **Step 2: Add `photoSlots` field to `CarouselSlide` (after `isSecondaryHidden`)**

Insert into `CarouselSlide` struct, after `var isSecondaryHidden: Bool = false`:

```swift
/// Non-nil activates the multi-photo stacked rendering path.
/// nil preserves single-photo rendering for cover, map, and default-mode place slides.
var photoSlots: [CarouselPhotoSlot]? = nil
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add CarouselPhotoSlot model and photoSlots field on CarouselSlide"
```

---

### Task 3: Extract `loadAssetImage` to file level + add `loadSlides()` multi-photo branch

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift`

- [ ] **Step 1: Extract `loadAssetImage` to a private file-level helper**

Add this function **before** the `// MARK: - Numeric helpers` section (after `SocialPostStudioSheet`'s closing brace at line ~1514):

```swift
// MARK: - Asset loading helper (shared by SocialPostStudioSheet and SlideTextEditorView)

private func loadAssetImage(identifier: String, size: CGSize) async -> UIImage? {
    await withCheckedContinuation { cont in
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetch.firstObject else { cont.resume(returning: nil); return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        PHImageManager.default().requestImage(for: asset, targetSize: size,
                                              contentMode: .aspectFill, options: opts) { img, _ in
            cont.resume(returning: img)
        }
    }
}
```

Then **delete** the identical `private func loadAssetImage(identifier:size:) async -> UIImage?` inside `SocialPostStudioSheet` (lines ~1444–1457), since the file-level version is now accessible everywhere in the file.

- [ ] **Step 2: Add `.multiPhoto` branch inside `loadSlides()` in `SocialPostStudioSheet`**

In `loadSlides()`, find the inner loop `for stop in day.placeStops { ... }` and wrap it in a switch on `styleMode`. Replace the entire per-day place-slides construction with:

```swift
for (dayIdx, day) in blog.days.enumerated() {
    let dayNumber = dayIdx + 1
    var markerImages: [UUID: UIImage] = [:]
    var placeSlides: [CarouselSlide] = []

    switch styleMode {
    case .default:
        for stop in day.placeStops {
            let included = stop.photos.filter { $0.isIncluded }
            guard !included.isEmpty else { continue }
            for (photoIdx, photo) in included.enumerated() {
                var hero: UIImage?
                if let localId = photo.localIdentifier {
                    hero = await loadAssetImage(identifier: localId,
                                                size: CGSize(width: exportWidth, height: exportHeight))
                }
                if photoIdx == 0, let img = hero { markerImages[stop.id] = img }
                placeSlides.append(CarouselSlide(
                    id: "\(stop.id.uuidString)-\(photo.id.uuidString)", kind: .placeStop,
                    isSelected: true, heroImage: hero, placeStop: stop, photoCaption: photo.caption))
            }
        }

    case .multiPhoto:
        for stop in day.placeStops {
            let included = stop.photos.filter { $0.isIncluded }
            guard !included.isEmpty else { continue }
            let topThree = included
                .sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
                .prefix(3)
            var slots: [CarouselPhotoSlot] = []
            for photo in topThree {
                var img: UIImage?
                if let localId = photo.localIdentifier {
                    img = await loadAssetImage(identifier: localId,
                                               size: CGSize(width: exportWidth, height: exportHeight))
                }
                slots.append(CarouselPhotoSlot(
                    id: UUID().uuidString,
                    photoID: photo.id.uuidString,
                    localIdentifier: photo.localIdentifier,
                    image: img,
                    caption: photo.caption.isEmpty ? nil : photo.caption
                ))
            }
            if let firstImg = slots.first?.image { markerImages[stop.id] = firstImg }
            placeSlides.append(CarouselSlide(
                id: "\(stop.id.uuidString)-multi", kind: .placeStop,
                isSelected: true, placeStop: stop, photoSlots: slots))
        }
    }

    let mapSnap = await MapSnapshotHelper.generatePhotoRouteSnapshot(
        for: day.placeStops, markerImagesByStopId: markerImages,
        size: CGSize(width: exportWidth, height: exportHeight), regionPadding: 0.015)

    let bestStory = [day.dayNarrative, day.dayCaption]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

    result.append(CarouselSlide(
        id: "map-\(day.id.uuidString)", kind: .mapRoute, isSelected: true,
        mapSnapshot: mapSnap, dayInfoLine1: "Day \(dayNumber)",
        dayInfoLine2: day.dayStoryDateLine, dayStory: bestStory))
    result.append(contentsOf: placeSlides)
}
```

- [ ] **Step 3: Add `.onChange(of: styleMode)` to trigger reload in `SocialPostStudioSheet.body`**

After the existing `.onChange(of: exportFormat)` modifier, add:

```swift
.onChange(of: styleMode) { _, _ in Task { await loadSlides() } }
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add loadSlides() multi-photo branch, extract loadAssetImage to file level"
```

---

### Task 4: `CarouselSlideView` — multi-photo rendering, selection rings, context menu

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` — `CarouselSlideView` and `SlideEditPage`

- [ ] **Step 1: Add photo-action closure properties to `CarouselSlideView`**

After the existing `var onBlockDragEnd: (() -> Void)? = nil` property, add:

```swift
/// Photo slot actions — only called in editing (isEditingText) context.
var onTrashPhotoSlot: ((Int) -> Void)? = nil
var onDuplicatePhotoSlot: ((Int) -> Void)? = nil
var onReplacePhotoSlot: ((Int) -> Void)? = nil
var onAddPhotoSlot: (() -> Void)? = nil
```

- [ ] **Step 2: Add multi-photo rendering branch inside `case .placeStop:` in `CarouselSlideView.body`**

Inside the `switch slide.kind` background block, replace the existing `case .placeStop:` branch with:

```swift
case .placeStop:
    if let slots = slide.photoSlots {
        // Multi-photo: stacked VStack, equal height slices
        VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                Group {
                    if let img = slot.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(white: 0.18)
                    }
                }
                .frame(width: width, height: height / CGFloat(slots.count))
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { onSelectBlock?(.photoSlot(i)) }
                // Per-slot caption (non-top slots only)
                .overlay(alignment: .bottomLeading) {
                    if i > 0, let cap = slot.caption, !cap.isEmpty {
                        Text(cap)
                            .font(.system(size: width * 0.038, design: .default))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, width * 0.05)
                            .padding(.vertical, width * 0.025)
                    }
                }
                // Selection ring
                .overlay {
                    if isEditingText && selectedBlockID == .photoSlot(i) {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                Color(red: 0.14, green: 0.52, blue: 1.0),
                                style: StrokeStyle(lineWidth: 2.5)
                            )
                            .padding(2)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        onTrashPhotoSlot?(i)
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .disabled(slots.count == 1)

                    Button {
                        onDuplicatePhotoSlot?(i)
                    } label: {
                        Label("Duplicate", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(slots.count >= 3)

                    Button {
                        onReplacePhotoSlot?(i)
                    } label: {
                        Label("Replace…", systemImage: "arrow.2.squarepath")
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    } else {
        coverBackground
    }
    // Top gradient: protects place name text
    if !slide.isPrimaryHidden {
        LinearGradient(colors: [.black.opacity(0.65), .clear],
                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
            .frame(width: width, height: height)
    }
    // Bottom gradient: protects caption text (only when caption exists)
    if slide.caption != nil, !slide.isSecondaryHidden {
        LinearGradient(colors: [.clear, .black.opacity(0.72)],
                       startPoint: .init(x: 0.5, y: 0.58), endPoint: .bottom)
            .frame(width: width, height: height)
    }
```

- [ ] **Step 3: Update `SlideEditPage` to accept and pass through photo-action closures**

Add these optional properties to `SlideEditPage`:

```swift
var onReplacePhotoSlot: ((Int) -> Void)? = nil
var onAddPhotoSlot: (() -> Void)? = nil
```

And in `SlideEditPage.body`, update the `CarouselSlideView(...)` call to include:

```swift
onTrashPhotoSlot: { i in
    guard var slots = slide.photoSlots, slots.count > 1 else { return }
    slots.remove(at: i)
    slide.photoSlots = slots
},
onDuplicatePhotoSlot: { i in
    guard var slots = slide.photoSlots, slots.count < 3 else { return }
    let original = slots[i]
    let dup = CarouselPhotoSlot(
        id: UUID().uuidString,
        photoID: original.photoID,
        localIdentifier: original.localIdentifier,
        image: original.image,
        caption: original.caption
    )
    slots.insert(dup, at: i + 1)
    slide.photoSlots = slots
},
onReplacePhotoSlot: onReplacePhotoSlot,
onAddPhotoSlot: onAddPhotoSlot,
```

> **Note:** Trash and Duplicate mutate the slide binding directly in `SlideEditPage` because they're self-contained. Replace and Add need `SlideTextEditorView`'s picker state, so they're passed through as closures.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add multi-photo rendering, selection rings, and context menus to CarouselSlideView"
```

---

### Task 5: `SlideTextEditorView` — `availableBlocks`, toolbar branch, photo actions, picker state

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` — `SlideTextEditorView`

- [ ] **Step 1: Add `PhotoPickerPurpose` enum and picker state in `SlideTextEditorView`**

Add inside `SlideTextEditorView` after the `@State private var didApplyToAll = false` line:

```swift
private enum PhotoPickerPurpose: Identifiable {
    case replace(slotIndex: Int)
    case add
    var id: String {
        switch self {
        case .replace(let i): return "replace-\(i)"
        case .add:            return "add"
        }
    }
}

@State private var photoPickerPurpose: PhotoPickerPurpose? = nil
```

- [ ] **Step 2: Extend `availableBlocks` to emit `.photoSlot(i)` entries**

Replace the existing `availableBlocks` computed property with:

```swift
private var availableBlocks: [SlideBlockID] {
    guard let slide = currentSlide else { return [] }
    var blocks: [SlideBlockID] = []
    switch slide.kind {
    case .cover:
        if !slide.isPrimaryHidden { blocks.append(.primary) }
    case .mapRoute:
        if !slide.isPrimaryHidden { blocks.append(.primary) }
        if !slide.isSecondaryHidden, slide.dayStory?.isEmpty == false { blocks.append(.secondary) }
    case .placeStop:
        if !slide.isPrimaryHidden { blocks.append(.primary) }
        if !slide.isSecondaryHidden, slide.caption != nil { blocks.append(.secondary) }
        if let slots = slide.photoSlots {
            for i in slots.indices { blocks.append(.photoSlot(i)) }
        }
    }
    return blocks
}
```

- [ ] **Step 3: Branch `textFormattingToolbar` to show `selectedPhotoControls` when a photo slot is selected**

Replace the `ZStack` inside `textFormattingToolbar` with:

```swift
ZStack {
    if selectedBlock == nil {
        emptySelectionHint
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    } else if case .photoSlot = selectedBlock {
        selectedPhotoControls
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    } else {
        selectedBlockControls
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
.animation(.easeInOut(duration: 0.22), value: selectedBlock)
```

- [ ] **Step 4: Add `selectedPhotoControls` view**

Add this `@ViewBuilder` property after `selectedBlockControls`:

```swift
/// Toolbar shown when a photo slot is selected.
@ViewBuilder
private var selectedPhotoControls: some View {
    if case let .photoSlot(slotIndex) = selectedBlock,
       hasValidCurrentIndex,
       let slots = slides[currentIndex].photoSlots {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                Text("EDITING PHOTO")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(0.4)
            }
            Spacer()
            iconActionButton(systemImage: "trash", tint: .red) {
                trashPhotoSlot(at: slotIndex, in: slots)
            }
            .opacity(slots.count == 1 ? 0.35 : 1.0)
            .disabled(slots.count == 1)

            iconActionButton(systemImage: "plus.rectangle.on.rectangle",
                             tint: Color.white.opacity(0.7)) {
                duplicatePhotoSlot(at: slotIndex, in: slots)
            }
            .opacity(slots.count >= 3 ? 0.35 : 1.0)
            .disabled(slots.count >= 3)

            iconActionButton(systemImage: "arrow.2.squarepath",
                             tint: Color.white.opacity(0.7)) {
                photoPickerPurpose = .replace(slotIndex: slotIndex)
            }

            if slots.count < 3 {
                iconActionButton(systemImage: "plus.circle",
                                 tint: Color(red: 0.04, green: 0.52, blue: 1.0)) {
                    photoPickerPurpose = .add
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}
```

- [ ] **Step 5: Add photo-slot mutation helpers**

Add these private methods to `SlideTextEditorView`:

```swift
private func trashPhotoSlot(at index: Int, in slots: [CarouselPhotoSlot]) {
    guard slots.count > 1, hasValidCurrentIndex else { return }
    var updated = slots
    updated.remove(at: index)
    slides[currentIndex].photoSlots = updated
    selectedBlock = .photoSlot(min(index, updated.count - 1))
}

private func duplicatePhotoSlot(at index: Int, in slots: [CarouselPhotoSlot]) {
    guard slots.count < 3, hasValidCurrentIndex else { return }
    let original = slots[index]
    let dup = CarouselPhotoSlot(
        id: UUID().uuidString,
        photoID: original.photoID,
        localIdentifier: original.localIdentifier,
        image: original.image,
        caption: original.caption
    )
    var updated = slots
    updated.insert(dup, at: index + 1)
    slides[currentIndex].photoSlots = updated
    selectedBlock = .photoSlot(index + 1)
}

private func handlePhotoPicked(_ photo: RecapPhoto, purpose: PhotoPickerPurpose) {
    guard hasValidCurrentIndex, var slots = slides[currentIndex].photoSlots else { return }
    Task {
        var newSlot = CarouselPhotoSlot(
            id: UUID().uuidString,
            photoID: photo.id.uuidString,
            localIdentifier: photo.localIdentifier,
            caption: photo.caption.isEmpty ? nil : photo.caption
        )
        if let localId = photo.localIdentifier {
            newSlot.image = await loadAssetImage(
                identifier: localId,
                size: CGSize(width: 1080, height: 1080)
            )
        }
        switch purpose {
        case .replace(let i):
            guard slots.indices.contains(i) else { return }
            slots[i] = newSlot
            selectedBlock = .photoSlot(i)
        case .add:
            guard slots.count < 3 else { return }
            slots.append(newSlot)
            selectedBlock = .photoSlot(slots.count - 1)
        }
        slides[currentIndex].photoSlots = slots
        photoPickerPurpose = nil
    }
}
```

- [ ] **Step 6: Wire photo-action closures through `SlideEditPage` in `SlideTextEditorView.body`**

In the `ForEach(slides.indices, id: \.self) { i in SlideEditPage(...) }` block, update the `SlideEditPage` call to include:

```swift
SlideEditPage(
    slide: $slides[i],
    aspectRatio: aspectRatio,
    selectedBlock: selectedBlock,
    onSelectBlock: { selectedBlock = $0 },
    onDeselectAll: { selectedBlock = nil },
    locksHorizontalSlidePaging: $locksHorizontalSlidePaging,
    onReplacePhotoSlot: { slotIndex in
        photoPickerPurpose = .replace(slotIndex: slotIndex)
    },
    onAddPhotoSlot: {
        photoPickerPurpose = .add
    }
)
```

- [ ] **Step 7: Add `.sheet(item: $photoPickerPurpose)` to `SlideTextEditorView.body`**

Add after `.onAppear { ... }`:

```swift
.sheet(item: $photoPickerPurpose) { purpose in
    if let placeStop = currentSlide?.placeStop,
       let slots = currentSlide?.photoSlots {
        let excluded = Set(slots.map(\.photoID))
        SlidePhotoPickerSheet(
            placeStop: placeStop,
            excludedPhotoIDs: excluded,
            onPick: { photo in handlePhotoPicked(photo, purpose: purpose) }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 8: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded` (will fail on `SlidePhotoPickerSheet` not defined — that's OK, do Task 6 next)

- [ ] **Step 9: Commit (after Task 6 makes the build pass)**

Defer commit to after Task 6 since `SlidePhotoPickerSheet` type must exist first.

---

### Task 6: Create `SlidePhotoPickerSheet.swift` and register in project

**Files:**
- Create: `fastblog/Views/SlidePhotoPickerSheet.swift`
- Modify: `fastblog/fastblog.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `SlidePhotoPickerSheet.swift`**

```swift
// SlidePhotoPickerSheet.swift
// fastblog

import Photos
import SwiftUI

struct SlidePhotoPickerSheet: View {
    let placeStop: PlaceStop
    let excludedPhotoIDs: Set<String>
    let onPick: (RecapPhoto) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availablePhotos: [RecapPhoto] {
        placeStop.photos.filter { $0.isIncluded && !excludedPhotoIDs.contains($0.id.uuidString) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if availablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No other photos",
                        systemImage: "photo",
                        description: Text("Add more photos to this place to use them here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(availablePhotos) { photo in
                                PhotoTileView(photo: photo)
                                    .onTapGesture {
                                        onPick(photo)
                                        dismiss()
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Choose from \(placeStop.placeTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

// MARK: - Tile

private struct PhotoTileView: View {
    let photo: RecapPhoto
    @State private var image: UIImage? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.2))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task { await loadImage() }
    }

    private func loadImage() async {
        guard let localId = photo.localIdentifier else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
        guard let asset = fetch.firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        image = await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in cont.resume(returning: img) }
        }
    }
}
```

- [ ] **Step 2: Register `SlidePhotoPickerSheet.swift` in `project.pbxproj`**

Open `fastblog/fastblog.xcodeproj/project.pbxproj` and make three edits:

**2a. Add PBXBuildFile entry** — in the `/* Begin PBXBuildFile section */`, near the `BB0002FB` entry for CarouselStudioSheet, add:

```
		BB00030B /* SlidePhotoPickerSheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB00030A /* SlidePhotoPickerSheet.swift */; };
```

**2b. Add PBXFileReference entry** — in the `/* Begin PBXFileReference section */`, near `BB0002FA` for CarouselStudioSheet, add:

```
		BB00030A /* SlidePhotoPickerSheet.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SlidePhotoPickerSheet.swift; sourceTree = "<group>"; };
```

**2c. Add to Views PBXGroup** — in the group containing `BB0002FA /* CarouselStudioSheet.swift */,`, add:

```
				BB00030A /* SlidePhotoPickerSheet.swift */,
```

**2d. Add to PBXSourcesBuildPhase** — in the sources phase containing `BB0002FB /* CarouselStudioSheet.swift in Sources */,`, add:

```
				BB00030B /* SlidePhotoPickerSheet.swift in Sources */,
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/SlidePhotoPickerSheet.swift fastblog/Views/CarouselStudioSheet.swift fastblog/fastblog.xcodeproj/project.pbxproj
git commit -m "feat: add SlideTextEditorView photo toolbar + SlidePhotoPickerSheet"
```

---

### Task 7: Mode-switch confirmation alert + remove Coming Soon gate

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` — `SocialPostStudioSheet` and `BasicStylesSheet`

- [ ] **Step 1: Remove the Coming Soon gate in `BasicStylesSheet`**

In `BasicStylesSheet.body`, change:

```swift
styleCard(mode: .multiPhoto, isAvailable: false)
```
to:
```swift
styleCard(mode: .multiPhoto, isAvailable: true)
```

- [ ] **Step 2: Add mode-switch state and computed helper to `SocialPostStudioSheet`**

After `@State private var showBasicStylesSheet = false`, add:

```swift
@State private var pendingStyleMode: StudioStyleMode? = nil
@State private var showModeSwitchAlert = false
```

Add this computed property inside `SocialPostStudioSheet`:

```swift
private var hasUserCustomizations: Bool {
    slides.contains { slide in
        slide.textStyle.primary != TextBlockStyle()
        || slide.textStyle.secondary != TextBlockStyle()
        || slide.isPrimaryHidden
        || slide.isSecondaryHidden
    }
}
```

- [ ] **Step 3: Intercept `BasicStylesSheet` binding to go through `pendingStyleMode`**

Currently the sheet is presented as:

```swift
.sheet(isPresented: $showBasicStylesSheet) {
    BasicStylesSheet(selectedMode: $styleMode)
        ...
}
```

Change to bind through `pendingStyleMode`:

```swift
.sheet(isPresented: $showBasicStylesSheet) {
    BasicStylesSheet(selectedMode: Binding(
        get: { styleMode },
        set: { pendingStyleMode = $0 }
    ))
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
}
```

- [ ] **Step 4: Add `onChange(of: pendingStyleMode)` and the confirmation alert**

After the existing `.onChange(of: styleMode)` modifier, add:

```swift
.onChange(of: pendingStyleMode) { _, newMode in
    guard let newMode, newMode != styleMode else {
        pendingStyleMode = nil
        return
    }
    if hasUserCustomizations {
        showModeSwitchAlert = true
    } else {
        styleMode = newMode
        pendingStyleMode = nil
    }
}
.alert("Switch styles?", isPresented: $showModeSwitchAlert) {
    Button("Cancel", role: .cancel) { pendingStyleMode = nil }
    Button("Switch", role: .destructive) {
        if let newMode = pendingStyleMode {
            styleMode = newMode
        }
        pendingStyleMode = nil
    }
} message: {
    Text("Your text edits on this carousel will be reset.")
}
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: mode-switch confirmation alert and remove Coming Soon gate from BasicStylesSheet"
```

---

### Task 8: Final build + manual test checklist

- [ ] **Step 1: Full clean build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator clean build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded` with zero errors.

- [ ] **Step 2: Manual test — Default mode unchanged**

Run on simulator. Open Social Post Studio on any blog. Verify:
- Default mode shows one slide per included photo.
- Cover and map slides render as before.
- Text block editing (font/color/size/delete/apply-to-all) works normally.

- [ ] **Step 3: Manual test — Multi-Photo mode, 1 photo place**

Switch to Multi-Photo. Find a place with exactly 1 included photo. Tap "Edit" on that slide. Verify:
- Single full-height photo fills the slide.
- Tap photo → blue ring appears, toolbar shows "EDITING PHOTO".
- Trash button shows red (disabled, slots.count == 1).
- Duplicate visible but disabled.
- Replace visible and tappable → picker opens.
- Add Photo button visible (slots.count < 3).

- [ ] **Step 4: Manual test — Multi-Photo mode, 2 photos**

Find a place with 2+ included photos. Verify:
- 50/50 split rendering.
- Tap each photo independently → ring moves to correct slot.
- Add Photo visible (slots.count == 2 < 3).

- [ ] **Step 5: Manual test — Multi-Photo mode, 3 photos**

Find a place with 3+ included photos. Verify:
- 33/33/33 split.
- Add Photo button hidden.
- Duplicate disabled (slots.count == 3).
- Long-press photo → native context menu with Trash / Duplicate (disabled) / Replace.

- [ ] **Step 6: Manual test — Multi-Photo mode, 6+ photos**

Verify top 3 by `qualityScore.totalScore` appear (the highest-scored photos).

- [ ] **Step 7: Manual test — Replace picker**

Tap Replace on any slot. Verify picker title says "Choose from [place name]". Picker shows only photos NOT currently in the stack (excluded). Tap a photo → slot updates, picker dismisses.

- [ ] **Step 8: Manual test — Mode switch**

With no edits: switch Basic Style → immediate reload, no alert.
With text edits (move a block or change font): switch Basic Style → alert appears. Tap Cancel → chip reverts to current mode. Tap Switch → slides reload, edits wiped.

- [ ] **Step 9: Manual test — Export**

In Multi-Photo mode, tap Save. Open Photos app. Verify saved images show the stacked layout (not single-photo). Share via sheet → same stacked layout in shared files.

- [ ] **Step 10: Manual test — No regression on text blocks**

In Multi-Photo mode, tap place name or subtitle → solid blue ring, font/color/size controls appear. Drag to reposition. Apply to all. Delete. Reset. All working.

---

## Self-Review Against Spec

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| `SlideBlockID` rename + `.photoSlot(Int)` | Task 1 |
| `CarouselPhotoSlot` struct | Task 2 |
| `CarouselSlide.photoSlots` | Task 2 |
| `loadSlides()` multiPhoto branch | Task 3 |
| Top-3 by qualityScore | Task 3 |
| `markerImages[stop.id]` from slot 0 | Task 3 |
| VStack stacked rendering, equal heights | Task 4 |
| Gradients at slide level, gated | Task 4 |
| Per-slot caption (non-top, non-draggable) | Task 4 |
| Selection ring per slot | Task 4 |
| `.contextMenu` Trash/Duplicate/Replace | Task 4 |
| `availableBlocks` emits `.photoSlot(i)` | Task 5 |
| Toolbar branches on `.photoSlot` | Task 5 |
| `selectedPhotoControls` header + 4 buttons | Task 5 |
| Trash disabled when count == 1 | Tasks 4, 5 |
| Duplicate disabled when count == 3 | Tasks 4, 5 |
| Add Photo hidden when count == 3 | Task 5 |
| Trash action + selection update | Task 5 |
| Duplicate with fresh UUID | Task 5 |
| Replace → picker → slot rebuild | Tasks 5, 6 |
| Add Photo → picker → slot append | Tasks 5, 6 |
| `SlidePhotoPickerSheet` (new file) | Task 6 |
| Picker excludes current stack | Task 6 |
| Picker empty state `ContentUnavailableView` | Task 6 |
| pbxproj registration | Task 6 |
| Remove Coming Soon gate | Task 7 |
| `hasUserCustomizations` helper | Task 7 |
| `pendingStyleMode` interception | Task 7 |
| Confirmation alert (Cancel/Switch) | Task 7 |
| Export unchanged (WYSIWYG) | No new work needed (spec confirmed) |

**Placeholder scan:** None found — all steps contain complete code.

**Type consistency:** `SlideBlockID` used uniformly in Tasks 1–5. `CarouselPhotoSlot` defined in Task 2 and used in Tasks 3–6. `PhotoPickerPurpose` defined in Task 5 and used in Tasks 5–6. `loadAssetImage(identifier:size:)` extracted to file level in Task 3 and used in Task 5. ✓
