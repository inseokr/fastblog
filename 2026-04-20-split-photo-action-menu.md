# Split Photo Action Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ambiguous "Reposition" button in Carousel Studio's SPLIT layout with a tap-to-select + contextual bottom action menu (Crop / Replace / Remove), styled like the existing text block toolbar.

**Architecture:** `selectedSplitSlot: SplitRepositionSlot?` state lives in `CarouselStudioSheet` and gates a new `splitPhotoActionToolbar` view in the existing bottom-chrome `safeAreaInset`. Tap callbacks in `CarouselSlideView` and `SlideEditPage` propagate slot selection up; deselection mirrors the existing `selectedBlock = nil` pattern.

**Tech Stack:** SwiftUI, iOS 17+, single file (`CarouselStudioSheet.swift`)

---

## Files

- Modify: `fastblog/Views/CarouselStudioSheet.swift`
  - `CarouselSlideView` struct — add `onTapSplitTopSlot` callback + `selectedSplitSlot` param + top-half tap target + selection highlight overlay
  - `SlideEditPage` struct — add `onRequestSplitTopSelect` callback + pass `selectedSplitSlot` down
  - `CarouselStudioSheet` main view — add `selectedSplitSlot` state, new `splitPhotoActionToolbar` view, wire bottom chrome, remove Reposition button
  - `SplitBottomPhotoPickerSheet` struct — move Clear to trailing, fix background color

---

## Task 1: Add `onTapSplitTopSlot` to `CarouselSlideView` + top-half tap target

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (~line 1144, ~line 1252)

- [ ] **Step 1: Add `onTapSplitTopSlot` property to `CarouselSlideView`**

Find the block at ~line 1143–1144:
```swift
    /// Split layout only: fired when the user taps the bottom slot to choose a second photo.
    var onTapSplitBottomSlot: (() -> Void)? = nil
```
Add immediately after:
```swift
    /// Split layout only: fired when the user taps the top slot.
    var onTapSplitTopSlot: (() -> Void)? = nil
    /// Split layout only: which slot is currently selected — drives the highlight ring.
    var selectedSplitSlot: SplitRepositionSlot? = nil
```

- [ ] **Step 2: Add top-half tap target inside `slideBackgroundStack`**

Find the existing bottom-half tap block at ~line 1252:
```swift
                if isEditingText, slide.layout == .split, onTapSplitBottomSlot != nil {
                    // Bottom-half tap target without `.position()` ...
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(width: width, height: height * 0.5)
                            .allowsHitTesting(false)
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: height * 0.5)
                            .highPriorityGesture(
                                TapGesture().onEnded { onTapSplitBottomSlot?() }
                            )
                    }
                    .frame(width: width, height: height)
                }
```

Replace that entire block with:
```swift
                if isEditingText, slide.layout == .split {
                    VStack(spacing: 0) {
                        // Top half — selects top slot
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: height * 0.5)
                            .highPriorityGesture(
                                TapGesture().onEnded { onTapSplitTopSlot?() }
                            )
                        // Bottom half — selects bottom slot
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: height * 0.5)
                            .highPriorityGesture(
                                TapGesture().onEnded { onTapSplitBottomSlot?() }
                            )
                    }
                    .frame(width: width, height: height)
                }
```

- [ ] **Step 3: Add selection highlight overlay for split slots**

Immediately after the tap-target block you just modified (still inside `slideBackgroundStack`'s `ZStack`), add:
```swift
                // Selection ring for split photo slots.
                if isEditingText, slide.layout == .split, let slot = selectedSplitSlot {
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                slot == .top ? Color.white.opacity(0.55) : Color.clear,
                                lineWidth: 2
                            )
                            .frame(width: width, height: height * 0.5)
                            .allowsHitTesting(false)
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                slot == .bottom ? Color.white.opacity(0.55) : Color.clear,
                                lineWidth: 2
                            )
                            .frame(width: width, height: height * 0.5)
                            .allowsHitTesting(false)
                    }
                    .frame(width: width, height: height)
                    .animation(.easeInOut(duration: 0.15), value: slot)
                }
```

- [ ] **Step 4: Build and confirm no errors**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add split slot tap targets and selection highlight ring to CarouselSlideView"
```

---

## Task 2: Add `onRequestSplitTopSelect` to `SlideEditPage` + pass `selectedSplitSlot`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (`SlideEditPage` struct ~lines 1934–2026)

- [ ] **Step 1: Add two new properties to `SlideEditPage`**

Find the existing properties around line 1950–1953:
```swift
    let onRequestHeroSwap: (Int) -> Void
    /// Present the split-bottom picker (split layout): user tapped the bottom slot.
    let onRequestSplitBottomPick: (Int) -> Void
```
Add after `onRequestSplitBottomPick`:
```swift
    /// Split layout: user tapped the top slot — select it in the parent.
    let onRequestSplitTopSelect: (Int) -> Void
    /// Split layout: which slot is currently selected (drives highlight in CarouselSlideView).
    var selectedSplitSlot: SplitRepositionSlot? = nil
```

- [ ] **Step 2: Wire both callbacks and pass `selectedSplitSlot` into `CarouselSlideView`**

Inside `SlideEditPage.body`, find the `CarouselSlideView(...)` call at ~line 1966. It currently has:
```swift
            onTapSplitBottomSlot: {
                guard slide.kind == .placeStop, slide.layout == .split else { return }
                onRequestSplitBottomPick(slidePageIndex)
            },
```
Change that to:
```swift
            onTapSplitTopSlot: {
                guard slide.kind == .placeStop, slide.layout == .split else { return }
                onRequestSplitTopSelect(slidePageIndex)
            },
            onTapSplitBottomSlot: {
                guard slide.kind == .placeStop, slide.layout == .split else { return }
                onRequestSplitBottomPick(slidePageIndex)
            },
            selectedSplitSlot: selectedSplitSlot,
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **` (the call site in CarouselStudioSheet will error until Task 3 — that's expected if you build incrementally; otherwise do Tasks 2+3 together before building)

---

## Task 3: Add `selectedSplitSlot` state to `CarouselStudioSheet` + wire call site

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (state declarations ~line 2305, `SlideEditPage` call site ~line 3509)

- [ ] **Step 1: Add state variable**

Find the block around line 2305:
```swift
    @State private var showsSplitBottomPhotoPicker: Bool = false
    /// Slide index captured when opening `showsSplitBottomPhotoPicker`.
    @State private var splitBottomPickSlideIndex: Int?
```
Add immediately after those two lines:
```swift
    /// Split layout: which photo slot (top / bottom) the user has selected for editing.
    /// Nil means no split slot is selected; drives `splitPhotoActionToolbar` visibility.
    @State private var selectedSplitSlot: SplitRepositionSlot?
```

- [ ] **Step 2: Update the `SlideEditPage` call site**

Find the `SlideEditPage(...)` call (~line 3509). It currently has:
```swift
                                                onRequestSplitBottomPick: { idx in
                                                    selectedBlock = nil
                                                    let options = availableSplitBottomPhotos(for: idx)
                                                    if options.count == 1, let only = options.first {
                                                        setSplitBottomPhoto(only, slideIndex: idx)
                                                    } else {
                                                        splitBottomPickSlideIndex = idx
                                                        showsSplitBottomPhotoPicker = true
                                                    }
                                                },
```
Replace that closure with:
```swift
                                                onRequestSplitBottomPick: { idx in
                                                    // Now selects the slot; Replace button in the
                                                    // action toolbar opens the picker explicitly.
                                                    selectedBlock = nil
                                                    selectedSplitSlot = .bottom
                                                },
```
And add the new callback right after it (before `onRequestStudioCoverPhotoPick`):
```swift
                                                onRequestSplitTopSelect: { idx in
                                                    selectedBlock = nil
                                                    selectedSplitSlot = .top
                                                },
                                                selectedSplitSlot: selectedSplitSlot,
```

- [ ] **Step 3: Clear `selectedSplitSlot` when a text block is selected**

Find the `.onTapGesture` for deselect at ~line 3650:
```swift
                .onTapGesture {
                    if selectedBlock != nil { selectedBlock = nil }
                }
```
Change to:
```swift
                .onTapGesture {
                    if selectedBlock != nil { selectedBlock = nil }
                    if selectedSplitSlot != nil { selectedSplitSlot = nil }
                }
```

Find where `selectedBlock` is set to a non-nil value (the `onSelectBlock` call site at ~line 3515):
```swift
                                                onSelectBlock: { selectedBlock = $0 },
```
Change to:
```swift
                                                onSelectBlock: {
                                                    selectedBlock = $0
                                                    selectedSplitSlot = nil
                                                },
```

- [ ] **Step 4: Also clear `selectedSplitSlot` in slide-change cleanup**

Find the slide-change reset block around line 3911 (where `showsHeroPhotoSwapSheet` and `selectedBlock` are cleared on page change):
```swift
                showsHeroPhotoSwapSheet = false
                heroSwapSlideIndex = nil
                showsSplitBottomPhotoPicker = false
                splitBottomPickSlideIndex = nil
                selectedBlock = nil
```
Add `selectedSplitSlot = nil` after `selectedBlock = nil` in that block.

- [ ] **Step 5: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add selectedSplitSlot state + wire split slot tap callbacks in CarouselStudioSheet"
```

---

## Task 4: Add `splitPhotoActionToolbar` view

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (add new computed view near `pipClusterToolbar` ~line 4262)

- [ ] **Step 1: Add the toolbar view**

Find the `// MARK: - PIP cluster toolbar` comment at ~line 4251. Insert the following block immediately before that comment:

```swift
    // MARK: - Split photo action toolbar

    /// Bottom chrome shown when a split photo slot is selected. Provides Crop
    /// (reposition), Replace (swap photo), and Remove (clear slot) actions for
    /// the selected slot. Style matches `textFormattingToolbar`'s top action row.
    @ViewBuilder
    private var splitPhotoActionToolbar: some View {
        guard let slot = selectedSplitSlot,
              let slide = currentSlide,
              slide.layout == .split else { return }

        let isTop = slot == .top

        HStack(spacing: 12) {
            // Crop — opens the full-screen pinch/pan repositioner for the selected slot.
            Button {
                let idx = editorPagerFocusedSlideIndex
                guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
                splitRepositionSession = SplitRepositionSession(slideIndex: idx, initialSlot: slot)
            } label: {
                Label("Crop", systemImage: "crop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Replace — hero swap for top slot; SplitBottomPhotoPicker for bottom slot.
            Button {
                let idx = editorPagerFocusedSlideIndex
                if isTop {
                    selectedBlock = nil
                    heroSwapSlideIndex = idx
                    showsHeroPhotoSwapSheet = true
                } else {
                    let options = availableSplitBottomPhotos(for: idx)
                    if options.count == 1, let only = options.first {
                        setSplitBottomPhoto(only, slideIndex: idx)
                        selectedSplitSlot = nil
                    } else {
                        splitBottomPickSlideIndex = idx
                        showsSplitBottomPhotoPicker = true
                    }
                }
            } label: {
                Label("Replace", systemImage: "photo.badge.arrow.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            // Remove — disabled (grayed out) for top slot; clears bottom slot.
            Button {
                guard !isTop else { return }
                clearSplitBottomPhoto(slideIndex: editorPagerFocusedSlideIndex)
                selectedSplitSlot = nil
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isTop ? Color.white.opacity(0.06) : Color.red.opacity(0.3))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            isTop ? Color.white.opacity(0.1) : Color.red.opacity(0.5),
                            lineWidth: 1
                        )
                    )
                    .opacity(isTop ? 0.4 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(isTop)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(white: 0.08).ignoresSafeArea(edges: .bottom))
    }
```

> **Note:** `@ViewBuilder` functions cannot use `guard … else { return }` — replace the guard with `if let` or move the guard logic into the caller. Use `if let` instead:

Actually, `@ViewBuilder` cannot use guard-return. Rewrite the opening as:

```swift
    @ViewBuilder
    private var splitPhotoActionToolbar: some View {
        if let slot = selectedSplitSlot,
           let slide = currentSlide,
           slide.layout == .split {
            let isTop = slot == .top

            HStack(spacing: 12) {
                Button {
                    let idx = editorPagerFocusedSlideIndex
                    guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
                    splitRepositionSession = SplitRepositionSession(slideIndex: idx, initialSlot: slot)
                } label: {
                    Label("Crop", systemImage: "crop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    let idx = editorPagerFocusedSlideIndex
                    if isTop {
                        selectedBlock = nil
                        heroSwapSlideIndex = idx
                        showsHeroPhotoSwapSheet = true
                    } else {
                        let options = availableSplitBottomPhotos(for: idx)
                        if options.count == 1, let only = options.first {
                            setSplitBottomPhoto(only, slideIndex: idx)
                            selectedSplitSlot = nil
                        } else {
                            splitBottomPickSlideIndex = idx
                            showsSplitBottomPhotoPicker = true
                        }
                    }
                } label: {
                    Label("Replace", systemImage: "photo.badge.arrow.up.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    guard !isTop else { return }
                    clearSplitBottomPhoto(slideIndex: editorPagerFocusedSlideIndex)
                    selectedSplitSlot = nil
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(isTop ? Color.white.opacity(0.06) : Color.red.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                isTop ? Color.white.opacity(0.1) : Color.red.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                        .opacity(isTop ? 0.4 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isTop)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(white: 0.08).ignoresSafeArea(edges: .bottom))
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: add splitPhotoActionToolbar with Crop / Replace / Remove actions"
```

---

## Task 5: Wire `splitPhotoActionToolbar` into the bottom chrome

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (bottom `safeAreaInset` ZStack ~line 3684, `currentChromeHeight` ~line 2463)

- [ ] **Step 1: Add the split toolbar branch into the ZStack**

Find the block at ~line 3684–3701:
```swift
                            ZStack(alignment: .bottom) {
                                if selectedBlock != nil {
                                    Color(white: 0.08)
                                        .ignoresSafeArea(edges: .bottom)
                                        .transition(.opacity)
                                }

                                if selectedBlock == nil {
                                    emptySelectionHint
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity)
                                } else if isPIPClusterSelected {
                                    pipClusterToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else {
                                    textFormattingToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
```
Replace with:
```swift
                            ZStack(alignment: .bottom) {
                                if selectedBlock != nil || selectedSplitSlot != nil {
                                    Color(white: 0.08)
                                        .ignoresSafeArea(edges: .bottom)
                                        .transition(.opacity)
                                }

                                if selectedBlock == nil && selectedSplitSlot != nil {
                                    splitPhotoActionToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else if selectedBlock == nil {
                                    emptySelectionHint
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity)
                                } else if isPIPClusterSelected {
                                    pipClusterToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else {
                                    textFormattingToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
```

- [ ] **Step 2: Update `currentChromeHeight` to account for `selectedSplitSlot`**

Find `private var currentChromeHeight: CGFloat` at ~line 2463:
```swift
    private var currentChromeHeight: CGFloat {
        if activePIPCategory == .order {
            let images = currentSlide?.pipImages ?? []
            let visible = min(max(0, currentSlide?.pipVisibleCount ?? 0), images.count)
            if visible <= 1 { return bottomChromeExpanded }
            return bottomChromePIPReorder
        }
        let expanded = activeStyleCategory != nil || activePIPCategory != nil
        let base = expanded ? bottomChromeExpanded : bottomChromeCollapsed
        return base + inlineEditorHeight
    }
```
Replace with:
```swift
    private var currentChromeHeight: CGFloat {
        if activePIPCategory == .order {
            let images = currentSlide?.pipImages ?? []
            let visible = min(max(0, currentSlide?.pipVisibleCount ?? 0), images.count)
            if visible <= 1 { return bottomChromeExpanded }
            return bottomChromePIPReorder
        }
        // Split photo action toolbar is a single flat row — no drop-ups.
        if selectedBlock == nil, selectedSplitSlot != nil {
            return bottomChromeCollapsed
        }
        let expanded = activeStyleCategory != nil || activePIPCategory != nil
        let base = expanded ? bottomChromeExpanded : bottomChromeCollapsed
        return base + inlineEditorHeight
    }
```

- [ ] **Step 3: Add `selectedSplitSlot` animation value to the chrome ZStack**

Find the two `.animation` modifiers on the ZStack around line 3704:
```swift
                            .animation(.easeInOut(duration: 0.22), value: selectedBlock)
```
Add another line after it:
```swift
                            .animation(.easeInOut(duration: 0.22), value: selectedSplitSlot)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "feat: wire splitPhotoActionToolbar into bottom chrome safeAreaInset"
```

---

## Task 6: Remove "Reposition" button from `splitToolsRow`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (`splitToolsRow` ~lines 2796–2825)

- [ ] **Step 1: Delete the Reposition button and its trailing spacer**

Find in `splitToolsRow`:
```swift
                        HStack(spacing: 10) {
                            Button {
                                let idx = editorPagerFocusedSlideIndex
                                guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
                                splitRepositionSession = SplitRepositionSession(slideIndex: idx, initialSlot: .top)
                            } label: {
                                Label("Reposition", systemImage: "crop")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.88))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 8)

                            Button {
                                swapSplitTopBottom(slideIndex: editorPagerFocusedSlideIndex)
```
Replace with (keeping Swap and the divider toggle, removing Reposition + Spacer):
```swift
                        HStack(spacing: 10) {
                            Button {
                                swapSplitTopBottom(slideIndex: editorPagerFocusedSlideIndex)
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "refactor: remove Reposition button from splitToolsRow (replaced by tap-photo flow)"
```

---

## Task 7: Move "Clear" to trailing + fix modal background in `SplitBottomPhotoPickerSheet`

**Files:**
- Modify: `fastblog/Views/CarouselStudioSheet.swift` (`SplitBottomPhotoPickerSheet` ~lines 6570–6607)

- [ ] **Step 1: Move Clear button to trailing**

Find at ~line 6587:
```swift
                if selectedPhotoID != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear") {
                            onClear()
                        }
                        .foregroundStyle(.white)
                    }
                }
```
Replace with:
```swift
                if selectedPhotoID != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            onClear()
                        }
                    }
                }
```
(Drop the explicit `.foregroundStyle(.white)` — it will adopt the system tint after the color scheme fix below.)

- [ ] **Step 2: Fix modal background color and remove forced dark scheme**

Find at ~line 6570:
```swift
            .background(Color(red: 5/255, green: 10/255, blue: 48/255))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 5/255, green: 10/255, blue: 48/255), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
```
Replace with:
```swift
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
```

Then find at ~line 6603–6607:
```swift
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
```
Replace with:
```swift
        }
    }
```

- [ ] **Step 3: Fix hardcoded white text colors in the toolbar**

Find at ~line 6577:
```swift
                        Text("Pick bottom photo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(placeStop.placeTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
```
Replace with:
```swift
                        Text("Pick bottom photo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(placeStop.placeTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
```
(Removing `.foregroundStyle(.white)` on the title lets it use `.primary`, which is correct for both light and dark.)

- [ ] **Step 4: Also fix the xmark button foreground**

Find at ~line 6596:
```swift
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close")
                }
```
Replace with:
```swift
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme fastblog -sdk iphonesimulator build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/CarouselStudioSheet.swift
git commit -m "fix: move Clear to trailing + system background color in SplitBottomPhotoPickerSheet"
```

---

## Manual Verification Checklist

After all tasks complete, test these flows in the simulator on a split-layout slide:

- [ ] Tap top photo → top half gets selection ring, bottom chrome shows Crop / Replace / Remove
- [ ] Tap bottom photo → bottom half gets selection ring, bottom chrome shows Crop / Replace / Remove
- [ ] Tap a text block → split selection ring clears, text toolbar appears
- [ ] Tap slide background (outside photos/text) → all selections clear, hint appears
- [ ] **Crop (top)** → SplitPhotoRepositionCover opens for top slot
- [ ] **Crop (bottom)** → SplitPhotoRepositionCover opens for bottom slot
- [ ] **Replace (top)** → hero swap sheet opens
- [ ] **Replace (bottom)** → SplitBottomPhotoPickerSheet opens (or auto-assigns if only 1 option)
- [ ] **Remove (top)** → button is grayed out, tap does nothing
- [ ] **Remove (bottom)** → bottom photo cleared, slot selection dismissed
- [ ] "Reposition" button no longer visible in splitToolsRow — only Swap + Straight/Curve remain
- [ ] SplitBottomPhotoPickerSheet: Clear button is on the right side
- [ ] SplitBottomPhotoPickerSheet: background is system gray (not deep navy)
- [ ] SplitBottomPhotoPickerSheet: text adapts to light/dark mode correctly
