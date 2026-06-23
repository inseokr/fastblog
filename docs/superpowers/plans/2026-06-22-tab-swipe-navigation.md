# Tab Swipe Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live-drag horizontal swipe navigation between the three home tabs (My Blogs ↔ Camera ↔ My Places) with a pager feel — content follows the finger and springs into place or snaps back on release.

**Architecture:** Replace the current opacity-toggle approach in `homeTabsLayer` with an offset-based side-by-side layout. A `GeometryReader` provides `screenWidth`; `swipeDragOffset` shifts all three tab views simultaneously during a drag. Overlays (Trips, Blog Detail, Scan, toasts) stay at x:0 and are completely unaffected.

**Tech Stack:** SwiftUI — `DragGesture`, `GeometryReader`, `offset(x:)`, `withAnimation`, `withTransaction`

## Global Constraints

- Only `fastblog/ContentView.swift` is modified — zero child view file changes.
- Tab order is fixed: `[.myBlogs, .camera, .myPlaces]` — My Blogs at index 0 (left), Camera at 1 (center), My Places at 2 (right).
- Camera edge restriction: 50 pt activation zone at left/right edges to protect camera controls in the center.
- Commit threshold: 35% of screen width OR predicted velocity proxy > 200 pt.
- Spring on commit/snap-back: `.spring(response: 0.35, dampingFraction: 0.85)`.
- Rubber-band damping factor at ends: `0.15`.
- Build command: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`

---

### Task 1: New state + tab offset helper

**Files:**
- Modify: `fastblog/ContentView.swift` — add two `@State` vars, one `private let`, one private helper function

**Interfaces:**
- Produces: `swipeDragOffset: CGFloat`, `swipeDragIsActive: Bool`, `tabOrder: [BottomNavTab]`, `tabVisualOffset(for:screenWidth:) -> CGFloat` — all used by Tasks 2 and 3.

- [ ] **Step 1: Add state and constant after line 55 (`suppressHomeBottomNav` declaration)**

  Insert immediately after `@State private var suppressHomeBottomNav = false`:

  ```swift
  @State private var swipeDragOffset: CGFloat = 0
  @State private var swipeDragIsActive = false

  private let tabOrder: [BottomNavTab] = [.myBlogs, .camera, .myPlaces]
  ```

- [ ] **Step 2: Add tab offset helper after `isCameraHomeVisible` computed property (after line 437)**

  Insert after `private var isCameraHomeVisible: Bool { ... }`:

  ```swift
  private func tabVisualOffset(for tab: BottomNavTab, screenWidth: CGFloat) -> CGFloat {
      let myIdx     = tabOrder.firstIndex(of: tab)     ?? 0
      let activeIdx = tabOrder.firstIndex(of: homeTab) ?? 1
      return CGFloat(myIdx - activeIdx) * screenWidth + swipeDragOffset
  }
  ```

- [ ] **Step 3: Build to verify no regressions**

  ```bash
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
  ```
  Expected: `Build succeeded`

- [ ] **Step 4: Commit**

  ```bash
  git add fastblog/ContentView.swift
  git commit -m "feat: add swipe navigation state and tab offset helper"
  ```

---

### Task 2: Refactor `homeTabsLayer` to offset-based layout

**Files:**
- Modify: `fastblog/ContentView.swift:273-424` — wrap ZStack in GeometryReader, replace opacity/zIndex with offset for the three tab views, add `.clipped()` and gesture attachment point.

**Interfaces:**
- Consumes: `tabVisualOffset(for:screenWidth:)`, `swipeDragIsActive` from Task 1.
- Produces: `homeTabsLayer` now accepts a `swipeGesture(screenWidth:)` call added in Task 3 — the `.simultaneousGesture(...)` modifier is added here with a placeholder that Task 3 replaces.

- [ ] **Step 1: Wrap the ZStack in a GeometryReader**

  Change the `homeTabsLayer` computed property signature from:

  ```swift
  private var homeTabsLayer: some View {
      ZStack {
  ```

  to:

  ```swift
  private var homeTabsLayer: some View {
      GeometryReader { geo in
      ZStack {
  ```

  And close the `GeometryReader` after the existing closing brace of `ZStack`:

  ```swift
      } // ZStack
      .clipped()
      .simultaneousGesture(swipeGesture(screenWidth: geo.size.width))
      } // GeometryReader
  ```

- [ ] **Step 2: Replace CameraCaptureView opacity/zIndex with offset**

  Find these three modifiers on the `CameraCaptureView` NavigationStack block:

  ```swift
  .opacity(homeTab == .camera ? 1 : 0)
  .allowsHitTesting(homeTab == .camera)
  .zIndex(homeTab == .camera ? 1 : 0)
  ```

  Replace with:

  ```swift
  .offset(x: tabVisualOffset(for: .camera, screenWidth: geo.size.width))
  .allowsHitTesting(homeTab == .camera && !swipeDragIsActive)
  .zIndex(1)
  ```

- [ ] **Step 3: Replace MyBlogsProfileView opacity/zIndex with offset**

  Find these three modifiers on the `MyBlogsProfileView` NavigationStack block:

  ```swift
  .opacity(homeTab == .myBlogs ? 1 : 0)
  .allowsHitTesting(homeTab == .myBlogs)
  .zIndex(homeTab == .myBlogs ? 3 : 0)
  ```

  Replace with:

  ```swift
  .offset(x: tabVisualOffset(for: .myBlogs, screenWidth: geo.size.width))
  .allowsHitTesting(homeTab == .myBlogs && !swipeDragIsActive)
  .zIndex(1)
  ```

- [ ] **Step 4: Replace PlacesVisitedStandaloneView opacity/zIndex with offset**

  Find these three modifiers on the `PlacesVisitedStandaloneView` NavigationStack block:

  ```swift
  .opacity(homeTab == .myPlaces ? 1 : 0)
  .allowsHitTesting(homeTab == .myPlaces)
  .zIndex(homeTab == .myPlaces ? 4 : 0)
  ```

  Replace with:

  ```swift
  .offset(x: tabVisualOffset(for: .myPlaces, screenWidth: geo.size.width))
  .allowsHitTesting(homeTab == .myPlaces && !swipeDragIsActive)
  .zIndex(1)
  ```

- [ ] **Step 5: Build to verify no regressions**

  ```bash
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
  ```
  Expected: `Build succeeded`

  > Note: `swipeGesture(screenWidth:)` referenced in Step 1 doesn't exist yet — the build will fail until Task 3 adds it. If you want to build mid-task, temporarily replace `.simultaneousGesture(swipeGesture(screenWidth: geo.size.width))` with an empty comment and restore it in Task 3.

- [ ] **Step 6: Commit**

  ```bash
  git add fastblog/ContentView.swift
  git commit -m "feat: replace tab opacity toggle with offset-based pager layout"
  ```

---

### Task 3: Implement the swipe gesture

**Files:**
- Modify: `fastblog/ContentView.swift` — add `swipeGesture(screenWidth:)` function

**Interfaces:**
- Consumes: `swipeDragOffset`, `swipeDragIsActive`, `tabOrder`, `homeTab`, `showsHomeChrome` from Task 1 / existing code.
- Consumes: `selectHomeTab(_:)` is NOT called here — tab commit is done via `withTransaction` directly to avoid the reset in `selectHomeTab` (that reset is for programmatic tap-driven switches only).

- [ ] **Step 1: Add the swipe gesture function after `tabVisualOffset(for:screenWidth:)` (after Task 1's insertion)**

  ```swift
  private func swipeGesture(screenWidth: CGFloat) -> some Gesture {
      DragGesture(minimumDistance: 10)
          .onChanged { value in
              let dx = value.translation.width
              let dy = value.translation.height

              guard showsHomeChrome else { return }
              guard abs(dx) > abs(dy) * 1.5 || swipeDragIsActive else { return }

              if homeTab == .camera && !swipeDragIsActive {
                  guard value.startLocation.x < 50 || value.startLocation.x > screenWidth - 50 else { return }
              }

              swipeDragIsActive = true

              let activeIdx = tabOrder.firstIndex(of: homeTab) ?? 1
              let atLeftEnd  = activeIdx == 0
              let atRightEnd = activeIdx == tabOrder.count - 1

              if (atLeftEnd && dx > 0) || (atRightEnd && dx < 0) {
                  swipeDragOffset = dx * 0.15
              } else {
                  swipeDragOffset = dx
              }
          }
          .onEnded { value in
              swipeDragIsActive = false

              let dx             = value.translation.width
              let velocityProxy  = value.predictedEndTranslation.width - value.translation.width
              let shouldCommit   = abs(dx) > screenWidth * 0.35 || abs(velocityProxy) > 200

              let activeIdx  = tabOrder.firstIndex(of: homeTab) ?? 1
              let direction  = dx < 0 ? 1 : -1
              let newTabIdx  = shouldCommit
                  ? max(0, min(tabOrder.count - 1, activeIdx + direction))
                  : activeIdx

              if newTabIdx != activeIdx {
                  swipeDragOffset += CGFloat(newTabIdx - activeIdx) * screenWidth
                  var transaction = Transaction()
                  transaction.disablesAnimations = true
                  withTransaction(transaction) {
                      homeTab = tabOrder[newTabIdx]
                  }
              }
              withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                  swipeDragOffset = 0
              }
          }
  }
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
  ```
  Expected: `Build succeeded`

- [ ] **Step 3: Manual smoke test on simulator**

  Launch the app on iPhone 16 simulator and verify:
  - Swipe left from Camera → My Places slides in from the right ✓
  - Swipe right from Camera → My Blogs slides in from the left ✓
  - Slow swipe < 35% width snaps back ✓
  - Fast flick commits even at < 35% ✓
  - Swipe right from My Blogs (left end) → rubber-bands (damped) and snaps back ✓
  - Swipe left from My Places (right end) → rubber-bands and snaps back ✓
  - Camera center-screen drag (not from edge) → does NOT trigger tab swipe ✓
  - Camera edge drag (< 50 pt from edge) → DOES trigger tab swipe ✓
  - Trips overlay open → swipe gesture ignored ✓
  - Blog Detail open → swipe gesture ignored ✓

- [ ] **Step 4: Commit**

  ```bash
  git add fastblog/ContentView.swift
  git commit -m "feat: implement horizontal swipe gesture for tab pager navigation"
  ```

---

### Task 4: Update `selectHomeTab` safety resets

**Files:**
- Modify: `fastblog/ContentView.swift:439-449` — add two resets at the top of `selectHomeTab(_:)`

**Interfaces:**
- Consumes: `swipeDragOffset`, `swipeDragIsActive` from Task 1.

- [ ] **Step 1: Add resets at the top of `selectHomeTab(_:)`**

  Find the start of `selectHomeTab`:

  ```swift
  private func selectHomeTab(_ tab: BottomNavTab) {
      cancelHomeBottomNavAutoHide()
  ```

  Replace with:

  ```swift
  private func selectHomeTab(_ tab: BottomNavTab) {
      swipeDragOffset = 0
      swipeDragIsActive = false
      cancelHomeBottomNavAutoHide()
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
  ```
  Expected: `Build succeeded`

- [ ] **Step 3: Manual verification**

  - Tap BottomNavBar "My Blogs" tab → instant switch, no slide animation, no offset residue ✓
  - Start a swipe mid-drag then tap BottomNavBar → offset resets cleanly ✓
  - Post-onboarding `showPostOnboardingWelcome` flow calls `selectHomeTab(.camera)` → no stuck offset ✓

- [ ] **Step 4: Commit**

  ```bash
  git add fastblog/ContentView.swift
  git commit -m "fix: reset swipe drag state on programmatic tab switch"
  ```

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|-----------------|------|
| Live-drag pager feel (content follows finger) | Task 2 (offset), Task 3 (gesture onChanged) |
| Spring commit or snap-back on release | Task 3 (onEnded spring) |
| `swipeDragOffset`, `swipeDragIsActive`, `tabOrder` state | Task 1 |
| `tabVisualOffset(for:screenWidth:)` helper | Task 1 |
| `GeometryReader` wrapping ZStack | Task 2 |
| `.clipped()` on ZStack | Task 2 |
| `.simultaneousGesture(...)` on ZStack | Task 2 |
| `.offset(x:)` replacing `.opacity` for three tabs | Task 2 |
| `.allowsHitTesting(homeTab == .x && !swipeDragIsActive)` | Task 2 |
| `.zIndex(1)` simplified for three tab views | Task 2 |
| Overlays retain existing if-conditional + high z-indices | Task 2 (unchanged) |
| `onChanged` overlay guard (`showsHomeChrome`) | Task 3 |
| `onChanged` direction filter (`|dx| > |dy| * 1.5`) | Task 3 |
| Camera edge restriction (50 pt) | Task 3 |
| Rubber-band at ends (15% damp) | Task 3 |
| `onEnded` commit threshold (35% width \|\| velocity > 200) | Task 3 |
| `swipeDragOffset` pre-adjust before homeTab change | Task 3 |
| `disablesAnimations: true` on homeTab commit | Task 3 |
| Spring on commit/snap-back (response 0.35, damping 0.85) | Task 3 |
| `selectHomeTab` safety resets | Task 4 |
| Child view files untouched | All tasks — single file only |
| Overlays, toasts, BottomNavBar unaffected | Task 2 — overlays left as-is |
