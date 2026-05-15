# Stories & TikTok Slide Pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a slide-selection modal before sharing to Instagram Stories (single-select) and TikTok (multi-select), replacing the current direct-export behavior.

**Architecture:** All changes are within `SlideTextEditorView` in `CarouselStudioSheet.swift`. Two new phases are added to the existing `CarouselStudioExportHubPhase` enum and two new deferred-work cases to `CarouselStudioDeferredExportHubWork`. The existing sheet (`showCarouselStudioExportHub`) is reused — no new sheet is introduced. New state, computed properties, helper functions, and content views follow the exact same patterns as the existing Share and Download pickers.

**Tech Stack:** SwiftUI, Swift, `PHAsset` / `UIPasteboard` for IG Stories share, `UIApplication.shared.open` for TikTok deep-link.

---

## File Map

| File | Changes |
|------|---------|
| `fastblog/Views/CarouselStudioSheet.swift:4860–4871` | Add 2 enum cases to `CarouselStudioDeferredExportHubWork` and `CarouselStudioExportHubPhase` |
| `fastblog/Views/CarouselStudioSheet.swift:4847–4848` | Add 2 `@State` vars for new pickers |
| `fastblog/Views/CarouselStudioSheet.swift:4988–5092` | Add computed props + helper functions for Stories and TikTok pickers |
| `fastblog/Views/CarouselStudioSheet.swift:7436–7557` | Add `exportHubInstagramStoriesPickContent` and `exportHubTikTokPickContent` views |
| `fastblog/Views/CarouselStudioSheet.swift:7674–7686` | Extend switch in `carouselStudioExportHubSheetContent` |
| `fastblog/Views/CarouselStudioSheet.swift:7744–7768` | Update Stories and TikTok menu buttons to open picker |
| `fastblog/Views/CarouselStudioSheet.swift:8180–8194` | Handle new deferred work cases in onDismiss |
| `fastblog/Views/CarouselStudioSheet.swift:11662–11688` | Update `shareToInstagramStories` and `shareToTikTok` to accept explicit indices |

---

## Task 1: Extend enums — phases and deferred work

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift:4860–4871`

- [ ] **Step 1: Add new cases to `CarouselStudioDeferredExportHubWork`**

Find (lines 4860–4864):
```swift
private enum CarouselStudioDeferredExportHubWork {
    case sharePickedIndices([Int], omitMapsFromShare: Bool)
    case savePhotosIndices([Int])
    case exportPDFIndices([Int])
}
```

Replace with:
```swift
private enum CarouselStudioDeferredExportHubWork {
    case sharePickedIndices([Int], omitMapsFromShare: Bool)
    case savePhotosIndices([Int])
    case exportPDFIndices([Int])
    case instagramStoriesSlide(Int)
    case tiktokSlides([Int])
}
```

- [ ] **Step 2: Add new cases to `CarouselStudioExportHubPhase`**

Find (lines 4868–4871):
```swift
private enum CarouselStudioExportHubPhase {
    case pickDownloadSlides
    case pickShareSlides
}
```

Replace with:
```swift
private enum CarouselStudioExportHubPhase {
    case pickDownloadSlides
    case pickShareSlides
    case pickInstagramStoriesSlide
    case pickTikTokSlides
}
```

- [ ] **Step 3: Build to verify no errors**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED` (switch exhaustiveness errors will appear in later tasks — that's expected, fix them in Task 4).

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): add Stories/TikTok picker phases and deferred work cases"
```

---

## Task 2: Add state variables for the new pickers

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 4847)

- [ ] **Step 1: Add two new `@State` vars after `shareSlidePickSelection`**

Find (line 4847):
```swift
    @State private var shareSlidePickSelection: Set<Int> = []
```

Replace with:
```swift
    @State private var shareSlidePickSelection: Set<Int> = []
    /// Single slide index chosen in the Instagram Stories picker (nil = nothing selected yet).
    @State private var storiesSlidePickSelection: Int? = nil
    /// Indices selected in the TikTok picker (all visible slides, ignoring Reel mode filter).
    @State private var tiktokSlidePickSelection: Set<Int> = []
```

- [ ] **Step 2: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): add storiesSlidePickSelection and tiktokSlidePickSelection state"
```

---

## Task 3: Add computed properties and helper functions for both pickers

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 5092, after `sharePickOmitMapsToggleBinding`)

- [ ] **Step 1: Add TikTok candidate list, selection helpers, and Stories toggle**

Find the end of `sharePickOmitMapsToggleBinding` (the closing `}` of the Binding around line 5092), then insert the following block immediately after it:

```swift
    // MARK: - Instagram Stories picker helpers

    private func toggleStoriesSlidePick(for index: Int) {
        if storiesSlidePickSelection == index {
            storiesSlidePickSelection = nil
        } else {
            storiesSlidePickSelection = index
        }
    }

    // MARK: - TikTok picker helpers

    /// All visible, non-PIP-hidden slides — ignores Reel mode filter so every slide is always shown.
    private var tiktokPickCandidateIndices: [Int] {
        visibleSlideIndices
    }

    private var tiktokPickSelectionMatchesAll: Bool {
        let candidates = tiktokPickCandidateIndices
        return !candidates.isEmpty && Set(candidates).isSubset(of: tiktokSlidePickSelection)
    }

    private func selectAllSlidesForTikTokPick() {
        tiktokSlidePickSelection.formUnion(tiktokPickCandidateIndices)
    }

    private func toggleTikTokPick(for index: Int) {
        if tiktokSlidePickSelection.contains(index) {
            tiktokSlidePickSelection.remove(index)
        } else {
            tiktokSlidePickSelection.insert(index)
        }
    }

    private func orderedPickedTikTokIndices() -> [Int] {
        tiktokPickCandidateIndices.filter { tiktokSlidePickSelection.contains($0) }
    }

    private func toggleTikTokPickSelectAll() {
        if tiktokPickSelectionMatchesAll {
            tiktokSlidePickSelection.subtract(tiktokPickCandidateIndices)
        } else {
            tiktokSlidePickSelection.formUnion(tiktokPickCandidateIndices)
        }
    }
```

- [ ] **Step 2: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): add Stories and TikTok picker helper functions"
```

---

## Task 4: Add the two new picker content views

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (insert after `exportHubSharePickContent`, around line 7557)

- [ ] **Step 1: Add `exportHubInstagramStoriesPickContent`**

Find the closing `}` of `exportHubSharePickContent` (the view ends just before `@ViewBuilder private var exportHubDownloadPickContent`, around line 7558). Insert the following new view immediately before `exportHubDownloadPickContent`:

```swift
    @ViewBuilder
    private var exportHubInstagramStoriesPickContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: exportHubGridColumns, spacing: 12) {
                    ForEach(studioDownloadCandidateIndices, id: \.self) { idx in
                        let selected = storiesSlidePickSelection == idx
                        GeometryReader { geo in
                            let w = max(80, geo.size.width)
                            CarouselStudioDownloadStylePickCard(
                                slide: slides[idx],
                                width: w,
                                aspectRatio: aspectRatio,
                                isInCarousel: selected,
                                mode: .singleAction { toggleStoriesSlidePick(for: idx) }
                            )
                        }
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            VStack(spacing: 8) {
                Text("Instagram Stories supports one slide at a time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard let idx = storiesSlidePickSelection else { return }
                    deferredExportHubWork = .instagramStoriesSlide(idx)
                    showCarouselStudioExportHub = false
                } label: {
                    let count = storiesSlidePickSelection != nil ? " (1)" : ""
                    Text("Share to Stories\(count)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(storiesSlidePickSelection == nil || exportActions.exportActionsDisabled())
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showCarouselStudioExportHub = false }
            }
            ToolbarItem(placement: .principal) {
                Text("Stories").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
```

- [ ] **Step 2: Add `exportHubTikTokPickContent`**

Immediately after the closing `}` of `exportHubInstagramStoriesPickContent`, insert:

```swift
    @ViewBuilder
    private var exportHubTikTokPickContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: toggleTikTokPickSelectAll) {
                    Label(
                        tiktokPickSelectionMatchesAll ? "Deselect All" : "Select All",
                        systemImage: tiktokPickSelectionMatchesAll ? "circle" : "checkmark.circle.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tiktokPickSelectionMatchesAll ? Color.primary : .white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tiktokPickSelectionMatchesAll
                                  ? Color(uiColor: .secondarySystemFill)
                                  : CarouselStudioChrome.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: exportHubGridColumns, spacing: 12) {
                    ForEach(tiktokPickCandidateIndices, id: \.self) { idx in
                        let selected = tiktokSlidePickSelection.contains(idx)
                        GeometryReader { geo in
                            let w = max(80, geo.size.width)
                            CarouselStudioDownloadStylePickCard(
                                slide: slides[idx],
                                width: w,
                                aspectRatio: aspectRatio,
                                isInCarousel: selected,
                                mode: .singleAction { toggleTikTokPick(for: idx) }
                            )
                        }
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }

            VStack(spacing: 8) {
                Button {
                    let order = orderedPickedTikTokIndices()
                    guard !order.isEmpty else { return }
                    deferredExportHubWork = .tiktokSlides(order)
                    showCarouselStudioExportHub = false
                } label: {
                    let n = orderedPickedTikTokIndices().count
                    let label = n > 0 ? "Save & Open TikTok (\(n))" : "Save & Open TikTok"
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(orderedPickedTikTokIndices().isEmpty || exportActions.exportActionsDisabled())
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showCarouselStudioExportHub = false }
            }
            ToolbarItem(placement: .principal) {
                Text("TikTok").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
```

- [ ] **Step 3: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): add exportHubInstagramStoriesPickContent and exportHubTikTokPickContent views"
```

---

## Task 5: Wire new phases into `carouselStudioExportHubSheetContent`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 7674)

- [ ] **Step 1: Extend the phase switch**

Find (around line 7676–7681):
```swift
            Group {
                switch carouselStudioExportHubPhase {
                case .pickShareSlides: exportHubSharePickContent
                case .pickDownloadSlides: exportHubDownloadPickContent
                }
            }
```

Replace with:
```swift
            Group {
                switch carouselStudioExportHubPhase {
                case .pickShareSlides: exportHubSharePickContent
                case .pickDownloadSlides: exportHubDownloadPickContent
                case .pickInstagramStoriesSlide: exportHubInstagramStoriesPickContent
                case .pickTikTokSlides: exportHubTikTokPickContent
                }
            }
```

- [ ] **Step 2: Reset new picker state on sheet dismiss — find the `onDismiss` phase reset**

Find (around line 8180–8182):
```swift
            .sheet(isPresented: $showCarouselStudioExportHub, onDismiss: {
                carouselStudioExportHubPhase = .pickDownloadSlides
                let work = deferredExportHubWork
```

The phase reset to `.pickDownloadSlides` already runs regardless of which phase was active, which is fine — no change needed here.

- [ ] **Step 3: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): route new picker phases in carouselStudioExportHubSheetContent"
```

---

## Task 6: Handle new deferred work in onDismiss

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 8186)

- [ ] **Step 1: Add new cases to the deferred-work switch**

Find (around line 8186–8194):
```swift
                    switch work {
                    case .sharePickedIndices(let order, let omitMapsFromShare):
                        Task { await exportActions.shareAtIndices(order, omitMapsFromShare) }
                    case .savePhotosIndices(let order):
                        Task { await exportActions.saveToPhotosAtIndices(order) }
                    case .exportPDFIndices(let order):
                        Task { await exportActions.exportPDFAtIndices(order) }
                    }
```

Replace with:
```swift
                    switch work {
                    case .sharePickedIndices(let order, let omitMapsFromShare):
                        Task { await exportActions.shareAtIndices(order, omitMapsFromShare) }
                    case .savePhotosIndices(let order):
                        Task { await exportActions.saveToPhotosAtIndices(order) }
                    case .exportPDFIndices(let order):
                        Task { await exportActions.exportPDFAtIndices(order) }
                    case .instagramStoriesSlide(let idx):
                        Task { await shareToInstagramStories(at: idx) }
                    case .tiktokSlides(let order):
                        Task { await shareToTikTok(indices: order) }
                    }
```

- [ ] **Step 2: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED` (will show errors on `shareToInstagramStories(at:)` and `shareToTikTok(indices:)` — fixed in Task 7)

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): handle instagramStoriesSlide and tiktokSlides deferred work"
```

---

## Task 7: Update share functions to accept explicit indices

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 11662)

- [ ] **Step 1: Update `shareToInstagramStories` to accept a specific index**

Find (lines 11662–11678):
```swift
    @MainActor private func shareToInstagramStories() async {
        let instagramURL = URL(string: "instagram-stories://share")!
        guard UIApplication.shared.canOpenURL(instagramURL) else {
            await shareViaSheet()
            return
        }
        let indices = orderedExportSlideIndices()
        guard let firstIndex = indices.first else { return }
        let mapWatermarkIdx = indexOfFirstCarouselStudioMapSlide(in: slides)
        guard let image = renderStudioSlideUIImageForExport(at: firstIndex, firstMapWatermarkIndex: mapWatermarkIdx),
              let imageData = image.pngData() else { return }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": imageData]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        await UIApplication.shared.open(instagramURL)
    }
```

Replace with:
```swift
    @MainActor private func shareToInstagramStories(at index: Int) async {
        let instagramURL = URL(string: "instagram-stories://share")!
        guard UIApplication.shared.canOpenURL(instagramURL) else {
            await exportActions.shareAtIndices([index], false)
            return
        }
        let mapWatermarkIdx = indexOfFirstCarouselStudioMapSlide(in: slides)
        guard let image = renderStudioSlideUIImageForExport(at: index, firstMapWatermarkIndex: mapWatermarkIdx),
              let imageData = image.pngData() else { return }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": imageData]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        await UIApplication.shared.open(instagramURL)
    }
```

- [ ] **Step 2: Update `shareToTikTok` to accept explicit indices**

Find (lines 11680–11688):
```swift
    @MainActor private func shareToTikTok() async {
        let tiktokURL = URL(string: "tiktok://")!
        let indices = orderedExportSlideIndices()
        guard !indices.isEmpty else { return }
        await requestSaveToPhotos(indices: indices)
        if UIApplication.shared.canOpenURL(tiktokURL) {
            await UIApplication.shared.open(tiktokURL)
        }
    }
```

Replace with:
```swift
    @MainActor private func shareToTikTok(indices: [Int]) async {
        guard !indices.isEmpty else { return }
        await requestSaveToPhotos(indices: indices)
        let tiktokURL = URL(string: "tiktok://")!
        if UIApplication.shared.canOpenURL(tiktokURL) {
            await UIApplication.shared.open(tiktokURL)
        }
    }
```

- [ ] **Step 3: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): update shareToInstagramStories(at:) and shareToTikTok(indices:) signatures"
```

---

## Task 8: Wire menu buttons to open pickers

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (around line 7744)

- [ ] **Step 1: Update the Stories button**

Find (lines 7744–7756):
```swift
            Button {
                Task { await exportActions.shareToInstagramStories() }
            } label: {
                Label {
                    Text("Stories")
                } icon: {
                    Image("InstagramIcon")
                        .resizable()
                        .scaledToFit()
                }
            }
            .disabled(exportDisabled)
```

Replace with:
```swift
            Button {
                storiesSlidePickSelection = nil
                carouselStudioExportHubPhase = .pickInstagramStoriesSlide
                showCarouselStudioExportHub = true
            } label: {
                Label {
                    Text("Stories")
                } icon: {
                    Image("InstagramIcon")
                        .resizable()
                        .scaledToFit()
                }
            }
            .disabled(exportDisabled)
```

- [ ] **Step 2: Update the TikTok button**

Find (lines 7757–7768):
```swift
            Button {
                Task { await exportActions.shareToTikTok() }
            } label: {
                Label {
                    Text("TikTok")
                } icon: {
                    Image("TikTokIcon")
                        .resizable()
                        .scaledToFit()
                }
            }
            .disabled(exportDisabled)
```

Replace with:
```swift
            Button {
                selectAllSlidesForTikTokPick()
                carouselStudioExportHubPhase = .pickTikTokSlides
                showCarouselStudioExportHub = true
            } label: {
                Label {
                    Text("TikTok")
                } icon: {
                    Image("TikTokIcon")
                        .resizable()
                        .scaledToFit()
                }
            }
            .disabled(exportDisabled)
```

- [ ] **Step 3: Remove now-unused `shareToInstagramStories` and `shareToTikTok` closures from `SlideTextEditorExportActions` if they exist**

Check `SlideTextEditorExportActions` (around line 4689) to see if `shareToInstagramStories` and `shareToTikTok` closures are still referenced anywhere. Search:

```
grep -n "shareToInstagramStories\|shareToTikTok" fastblog/Views/CarouselStudioSheet.swift
```

If the closure properties on `SlideTextEditorExportActions` (lines ~4702–4703) are no longer called anywhere except the definitions in `SocialPostStudioSheet`, remove them from the struct and their assignment in `SocialPostStudioSheet.init` (around line 9988–9989). If they are still used elsewhere, leave them.

- [ ] **Step 4: Build**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat(carousel): wire Stories and TikTok menu buttons to slide picker modals"
```

---

## Task 9: Manual smoke test

- [ ] **Step 1: Run on simulator**

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

- [ ] **Step 2: Test Stories picker**
  1. Open any blog in Carousel Studio
  2. Tap the export hub icon → tap **Stories**
  3. Verify a modal appears showing slide thumbnails
  4. Verify "Share to Stories" button is disabled until a slide is tapped
  5. Tap one slide — verify it highlights and button enables showing "(1)"
  6. Tap a different slide — verify previous deselects, new one selects (single-select radio behavior)
  7. Tap **Cancel** — verify modal dismisses with no export

- [ ] **Step 3: Test TikTok picker**
  1. Tap export hub icon → tap **TikTok**
  2. Verify modal appears with all visible slides pre-selected and "Select All" active
  3. Verify "Save & Open TikTok (N)" shows correct count
  4. Tap to deselect individual slides — verify count updates
  5. Tap "Deselect All" — verify all deselect and button disables
  6. Tap "Select All" — verify all reselect
  7. Tap **Cancel** — verify modal dismisses with no export

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(carousel): complete Stories/TikTok slide picker user flow"
```
