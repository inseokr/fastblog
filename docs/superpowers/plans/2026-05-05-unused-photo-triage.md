# Unused Photo Triage Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tap-to-open slideshow in the Unused Photos gallery with a sequential swipe-to-triage flow — swipe left to delete, swipe right to keep — that loops through all photos starting from the one tapped and dismisses back to the gallery when done.

**Architecture:** A new `private struct UnusedPhotoTriageView` is added to `StorageManagementView.swift`. `StorageManagementView` replaces its `fullScreenPhotoId` state with `triageStartPhotoId: UUID?` and presents `UnusedPhotoTriageView` as a full-screen ZStack overlay (zIndex 40). The existing `UnusedPhotosSlideshowView` struct stays in the file but is no longer presented. All delete logic remains in the parent via an `onDelete` callback.

**Tech Stack:** SwiftUI, Swift Concurrency (`Task.sleep`), `@AppStorage`, `DragGesture`

---

## File Map

| File | Change |
|---|---|
| `fastblog/Views/StorageManagementView.swift` | Remove `fullScreenPhotoId` + related state/helpers, add `triageStartPhotoId`, add `UnusedPhotoTriageView`, add `UnusedPhotosTriageTooltipOverlay` |

---

### Task 1: Wire the triage entry point in `StorageManagementView`

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Remove `fullScreenPhotoId` state and its dependents**

  In `StorageManagementView`, delete the following declarations (they are replaced in later steps):

  ```swift
  // DELETE these lines:
  @State private var fullScreenPhotoId: UUID?
  @State private var downloadToast: String?
  ```

  Delete the computed property `fullScreenHeaderPhoto`:
  ```swift
  // DELETE:
  private var fullScreenHeaderPhoto: RecapPhoto? {
      guard let id = fullScreenPhotoId else { return nil }
      return visiblePhotos.first { $0.photo.id == id }?.photo
  }
  ```

  Delete `downloadPhotoToLibrary` and `loadUIImageForBloggoExport` methods entirely (search for `private func downloadPhotoToLibrary` and `private func loadUIImageForBloggoExport` — remove both full method bodies).

  Delete the two static date formatters:
  ```swift
  // DELETE:
  private static let unusedPhotoFullscreenHeaderDateFormatter: DateFormatter = { ... }()
  private static let unusedPhotoFullscreenHeaderTimeFormatter: DateFormatter = { ... }()
  ```

- [ ] **Step 2: Add `triageStartPhotoId` state**

  Add this line in the `// MARK: - Full-screen slideshow` section (replacing the removed state):
  ```swift
  @State private var triageStartPhotoId: UUID?
  ```

- [ ] **Step 3: Update `navigationTitleText`**

  Replace the existing `navigationTitleText` computed property:
  ```swift
  // OLD:
  private var navigationTitleText: String {
      if fullScreenPhotoId != nil { return "" }
      if isSelectMode { return "\(selectedPhotoIds.count) selected" }
      return "Unused Photos"
  }

  // NEW:
  private var navigationTitleText: String {
      if isSelectMode { return "\(selectedPhotoIds.count) selected" }
      return "Unused Photos"
  }
  ```

- [ ] **Step 4: Update `photoCell` tap handler**

  In `photoCell`, replace the tap handler:
  ```swift
  // OLD:
  .onTapGesture {
      if isSelectMode {
          toggleSelection(photo.id)
      } else {
          withAnimation(.easeInOut(duration: 0.2)) {
              fullScreenPhotoId = photo.id
          }
      }
  }

  // NEW:
  .onTapGesture {
      if isSelectMode {
          toggleSelection(photo.id)
      } else {
          withAnimation(.easeInOut(duration: 0.2)) {
              triageStartPhotoId = photo.id
          }
      }
  }
  ```

- [ ] **Step 5: Update the body ZStack**

  In `var body: some View`, replace the slideshow + downloadToast overlay blocks:

  ```swift
  // DELETE these blocks:
  if fullScreenPhotoId != nil {
      UnusedPhotosSlideshowView(
          photos: visiblePhotos.map(\.photo),
          selectedPhotoId: $fullScreenPhotoId,
          shouldOfferDownload: { !isPhotoLibraryAsset($0) },
          onDelete: { beginDeleteFromSlideshow($0) },
          onDownload: { downloadPhotoToLibrary($0) }
      )
      .transition(.opacity)
      .zIndex(40)
  }
  if let downloadToast {
      VStack {
          Spacer()
          Text(downloadToast)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Capsule().fill(.black.opacity(0.7)))
              .padding(.bottom, 32)
      }
      .transition(.opacity)
      .allowsHitTesting(false)
      .zIndex(50)
  }
  ```

  Add this block in the same ZStack (after `showIntroTooltip` block):
  ```swift
  if let startId = triageStartPhotoId {
      UnusedPhotoTriageView(
          photos: visiblePhotos.map(\.photo),
          startingPhotoId: startId,
          onDelete: { beginDeleteFromSlideshow($0) },
          onDismiss: {
              withAnimation(.easeInOut(duration: 0.3)) {
                  triageStartPhotoId = nil
              }
          }
      )
      .transition(.opacity)
      .zIndex(40)
  }
  ```

- [ ] **Step 6: Update `bottomActionBar` visibility condition**

  In `var body: some View`, change:
  ```swift
  // OLD:
  if fullScreenPhotoId == nil {
      bottomActionBar
  }

  // NEW:
  if triageStartPhotoId == nil {
      bottomActionBar
  }
  ```

- [ ] **Step 7: Update `navigationToolbar`**

  Replace the entire `navigationToolbar` with a version that removes all `fullScreenPhotoId` conditions:
  ```swift
  @ToolbarContentBuilder
  private var navigationToolbar: some ToolbarContent {
      ToolbarItem(placement: .navigationBarLeading) {
          if isSelectMode {
              Button("Cancel") { exitSelectMode() }
          } else {
              Button {
                  dismiss()
              } label: {
                  Image(systemName: "chevron.left")
                      .fontWeight(.semibold)
              }
          }
      }
      if triageStartPhotoId == nil {
          ToolbarItem(placement: .navigationBarTrailing) {
              if isSelectMode {
                  Button(allVisiblePhotosAreSelected ? "Deselect All" : "Select All") {
                      if allVisiblePhotosAreSelected {
                          deselectAll()
                      } else {
                          selectAll()
                      }
                  }
              } else {
                  Button("Select") { enterSelectMode() }
              }
          }
      }
  }
  ```

- [ ] **Step 8: Update `finishDeleteFlow`**

  Remove the `fullScreenPhotoId` reference in `finishDeleteFlow`. Replace:
  ```swift
  // OLD:
  private func finishDeleteFlow() {
      if deletedAny { onSave() }
      deletedAny = false
      let remaining = Set(visiblePhotos.map(\.photo.id))
      selectedPhotoIds = selectedPhotoIds.intersection(remaining)
      if visiblePhotos.isEmpty {
          isSelectMode = false
          selectedPhotoIds = []
          activeDayFilter = nil
          fullScreenPhotoId = nil
      } else if let fs = fullScreenPhotoId, !remaining.contains(fs) {
          fullScreenPhotoId = visiblePhotos.first?.photo.id
      }
  }

  // NEW:
  private func finishDeleteFlow() {
      if deletedAny { onSave() }
      deletedAny = false
      let remaining = Set(visiblePhotos.map(\.photo.id))
      selectedPhotoIds = selectedPhotoIds.intersection(remaining)
      if visiblePhotos.isEmpty {
          isSelectMode = false
          selectedPhotoIds = []
          activeDayFilter = nil
          triageStartPhotoId = nil
      }
  }
  ```

- [ ] **Step 9: Also remove the downloadToast animation modifier**

  In `var body: some View`, remove this line:
  ```swift
  // DELETE:
  .animation(.easeInOut(duration: 0.2), value: downloadToast != nil)
  ```

- [ ] **Step 10: Add a compile stub for `UnusedPhotoTriageView`**

  At the bottom of `StorageManagementView.swift` (after the closing brace of `UnusedPhotosIntroTooltipOverlay`), add:
  ```swift
  // MARK: - Triage view

  private struct UnusedPhotoTriageView: View {
      let photos: [RecapPhoto]
      let startingPhotoId: UUID
      var onDelete: (RecapPhoto) -> Void
      var onDismiss: () -> Void

      var body: some View {
          Color.black.ignoresSafeArea()
      }
  }
  ```

- [ ] **Step 11: Build to verify no compile errors**

  ```bash
  cd /Users/justinseo/Desktop/Bloggo/fastblog
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED` with no `error:` lines.

---

### Task 2: Implement `UnusedPhotoTriageView` — loop, display, and buttons

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift` (replace the stub from Task 1)

- [ ] **Step 1: Replace the stub with the full `UnusedPhotoTriageView` implementation**

  Replace the entire stub `UnusedPhotoTriageView` struct with:

  ```swift
  private struct UnusedPhotoTriageView: View {
      let photos: [RecapPhoto]
      let startingPhotoId: UUID
      var onDelete: (RecapPhoto) -> Void
      var onDismiss: () -> Void

      @State private var triageQueue: [UUID] = []
      @State private var currentQueueIndex: Int = 0

      // MARK: - Derived

      private var currentPhoto: RecapPhoto? {
          guard currentQueueIndex < triageQueue.count else { return nil }
          let id = triageQueue[currentQueueIndex]
          return photos.first { $0.id == id }
      }

      var body: some View {
          ZStack {
              Color.black.ignoresSafeArea()

              VStack(spacing: 0) {
                  // Custom top bar
                  HStack {
                      Button { onDismiss() } label: {
                          Image(systemName: "xmark")
                              .fontWeight(.semibold)
                              .foregroundStyle(.white)
                              .frame(width: 44, height: 44)
                      }
                      .buttonStyle(.plain)

                      Spacer()

                      if !triageQueue.isEmpty {
                          Text("Photo \(currentQueueIndex + 1) of \(triageQueue.count)")
                              .font(.subheadline.weight(.medium))
                              .foregroundStyle(.white)
                      }

                      Spacer()

                      Color.clear.frame(width: 44, height: 44)
                  }
                  .padding(.horizontal, 12)
                  .padding(.top, 8)

                  // Photo area
                  if let photo = currentPhoto {
                      RecapPhotoThumbnail(
                          photo: photo,
                          cornerRadius: 0,
                          showIcon: false,
                          targetSize: CGSize(width: 1200, height: 1200)
                      )
                      .aspectRatio(contentMode: .fit)
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                  } else {
                      Spacer()
                  }

                  // Swipe hint
                  Text("\u{2190} delete      keep \u{2192}")
                      .font(.footnote)
                      .foregroundStyle(.white.opacity(0.45))
                      .padding(.vertical, 12)

                  // CTA buttons
                  HStack(spacing: 12) {
                      Button { triggerDelete() } label: {
                          Label("Delete", systemImage: "trash")
                              .font(.body.weight(.semibold))
                              .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                              .frame(maxWidth: .infinity)
                              .frame(height: 56)
                              .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                      }
                      .buttonStyle(.plain)

                      Button { triggerKeep() } label: {
                          Label("Keep", systemImage: "checkmark")
                              .font(.body.weight(.semibold))
                              .foregroundStyle(.white)
                              .frame(maxWidth: .infinity)
                              .frame(height: 56)
                              .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                      }
                      .buttonStyle(.plain)
                  }
                  .padding(.horizontal, 20)
                  .padding(.bottom, 20)
              }
          }
          .onAppear { buildQueue() }
          .onChange(of: photos.map(\.id)) { _, newIds in
              // If all photos were deleted while triaging, dismiss
              if newIds.isEmpty { onDismiss(); return }
              // If the current photo was deleted, auto-advance
              guard currentQueueIndex < triageQueue.count else { return }
              let currentId = triageQueue[currentQueueIndex]
              if !newIds.contains(currentId) { advance() }
          }
      }

      // MARK: - Queue

      private func buildQueue() {
          let allIds = photos.map(\.id)
          guard let startIdx = allIds.firstIndex(of: startingPhotoId) else {
              triageQueue = allIds
              currentQueueIndex = 0
              return
          }
          triageQueue = Array(allIds[startIdx...]) + Array(allIds[..<startIdx])
          currentQueueIndex = 0
      }

      // MARK: - Actions

      private func advance() {
          currentQueueIndex += 1
          if currentQueueIndex >= triageQueue.count {
              onDismiss()
          }
      }

      private func triggerDelete() {
          guard let photo = currentPhoto else { advance(); return }
          onDelete(photo)
          advance()
      }

      private func triggerKeep() {
          advance()
      }
  }
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  cd /Users/justinseo/Desktop/Bloggo/fastblog
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`

---

### Task 3: Add swipe gesture with visual feedback

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift` (update `UnusedPhotoTriageView`)

- [ ] **Step 1: Add drag state properties to `UnusedPhotoTriageView`**

  Inside `UnusedPhotoTriageView`, add these `@State` properties after `currentQueueIndex`:
  ```swift
  @State private var dragOffset: CGFloat = 0
  @State private var dragRotation: Double = 0
  @State private var deleteOverlayOpacity: Double = 0
  @State private var keepOverlayOpacity: Double = 0
  ```

- [ ] **Step 2: Replace the photo display area with a draggable version**

  Replace the `if let photo = currentPhoto { ... }` block in `body` with:
  ```swift
  if let photo = currentPhoto {
      ZStack {
          RecapPhotoThumbnail(
              photo: photo,
              cornerRadius: 0,
              showIcon: false,
              targetSize: CGSize(width: 1200, height: 1200)
          )
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          // Delete tint (swipe left)
          Color.red
              .opacity(deleteOverlayOpacity * 0.35)
              .allowsHitTesting(false)

          // Keep tint (swipe right)
          Color.green
              .opacity(keepOverlayOpacity * 0.35)
              .allowsHitTesting(false)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .offset(x: dragOffset)
      .rotationEffect(.degrees(dragRotation))
      .gesture(
          DragGesture(minimumDistance: 20)
              .onChanged { value in
                  let x = value.translation.width
                  dragOffset = x
                  dragRotation = max(-5, min(5, Double(x) / 20))
                  if x < 0 {
                      deleteOverlayOpacity = min(abs(Double(x)) / 80, 1.0)
                      keepOverlayOpacity = 0
                  } else {
                      keepOverlayOpacity = min(Double(x) / 80, 1.0)
                      deleteOverlayOpacity = 0
                  }
              }
              .onEnded { value in
                  let x = value.translation.width
                  if x < -80 {
                      commitSwipe(direction: .left)
                  } else if x > 80 {
                      commitSwipe(direction: .right)
                  } else {
                      withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                          resetDrag()
                      }
                  }
              }
      )
  } else {
      Spacer()
  }
  ```

- [ ] **Step 3: Add `commitSwipe`, `resetDrag`, and `SwipeDirection` to `UnusedPhotoTriageView`**

  Add inside `UnusedPhotoTriageView` (after `triggerKeep`):
  ```swift
  private enum SwipeDirection { case left, right }

  private func commitSwipe(direction: SwipeDirection) {
      let targetOffset: CGFloat = direction == .left
          ? -UIScreen.main.bounds.width
          : UIScreen.main.bounds.width
      withAnimation(.easeOut(duration: 0.2)) {
          dragOffset = targetOffset
      }
      Task {
          try? await Task.sleep(for: .milliseconds(220))
          resetDrag()
          if direction == .left {
              triggerDelete()
          } else {
              triggerKeep()
          }
      }
  }

  private func resetDrag() {
      dragOffset = 0
      dragRotation = 0
      deleteOverlayOpacity = 0
      keepOverlayOpacity = 0
  }
  ```

- [ ] **Step 4: Build to verify**

  ```bash
  cd /Users/justinseo/Desktop/Bloggo/fastblog
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`

---

### Task 4: Add first-time tooltip, commit

**Files:**
- Modify: `fastblog/Views/StorageManagementView.swift`

- [ ] **Step 1: Add `UnusedPhotosTriageTooltipOverlay` struct**

  Add after the closing brace of `UnusedPhotoTriageView`:
  ```swift
  private struct UnusedPhotosTriageTooltipOverlay: View {
      let onGotIt: () -> Void

      var body: some View {
          ZStack {
              Color.black.opacity(0.52)
                  .ignoresSafeArea()
                  .allowsHitTesting(true)

              VStack(alignment: .leading, spacing: 14) {
                  HStack(spacing: 10) {
                      Image(systemName: "hand.draw")
                          .font(.title3.weight(.semibold))
                          .foregroundStyle(.white)
                      Text("Review Your Photos")
                          .font(.title3.weight(.bold))
                          .foregroundStyle(.white)
                  }

                  Text("Swipe left to delete \u{00B7} Swipe right to keep.")
                      .font(.subheadline)
                      .foregroundStyle(.white.opacity(0.9))
                      .fixedSize(horizontal: false, vertical: true)

                  Text("We'll go through each one.")
                      .font(.footnote)
                      .foregroundStyle(.white.opacity(0.72))
                      .fixedSize(horizontal: false, vertical: true)

                  Button(action: onGotIt) {
                      Text("Got it")
                          .font(.body.weight(.semibold))
                          .frame(maxWidth: .infinity)
                          .padding(.vertical, 14)
                          .background(
                              Color.white.opacity(0.2),
                              in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous)
                          )
                          .foregroundStyle(.white)
                  }
                  .buttonStyle(.plain)
                  .padding(.top, 6)
              }
              .padding(24)
              .background(
                  RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                      .fill(.ultraThinMaterial)
              )
              .overlay(
                  RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                      .stroke(Color.white.opacity(0.14), lineWidth: 1)
              )
              .padding(.horizontal, 28)
          }
      }
  }
  ```

- [ ] **Step 2: Wire tooltip into `UnusedPhotoTriageView`**

  Add these two properties inside `UnusedPhotoTriageView` (after `keepOverlayOpacity`):
  ```swift
  @AppStorage("bloggo.hasSeenUnusedPhotosTriageTooltip") private var hasSeenTriageTooltip: Bool = false
  @State private var showTriageTooltip = false
  ```

  In `UnusedPhotoTriageView.body`, wrap the outer `ZStack` content with the tooltip. Change the `ZStack` to add the tooltip layer and its animation:
  ```swift
  ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
          // ... (existing VStack content unchanged)
      }

      if showTriageTooltip {
          UnusedPhotosTriageTooltipOverlay(onGotIt: {
              hasSeenTriageTooltip = true
              withAnimation(.easeInOut(duration: 0.25)) {
                  showTriageTooltip = false
              }
          })
          .transition(.opacity)
          .zIndex(10)
      }
  }
  .animation(.easeInOut(duration: 0.25), value: showTriageTooltip)
  .onAppear {
      buildQueue()
      if !hasSeenTriageTooltip {
          showTriageTooltip = true
      }
  }
  .onChange(of: photos.map(\.id)) { ... }  // keep as-is
  ```

  The full modifier chain on the outer ZStack (replacing the `.onAppear` from Task 2) becomes:
  ```swift
  .animation(.easeInOut(duration: 0.25), value: showTriageTooltip)
  .onAppear {
      buildQueue()
      if !hasSeenTriageTooltip {
          showTriageTooltip = true
      }
  }
  .onChange(of: photos.map(\.id)) { _, newIds in
      if newIds.isEmpty { onDismiss(); return }
      guard currentQueueIndex < triageQueue.count else { return }
      let currentId = triageQueue[currentQueueIndex]
      if !newIds.contains(currentId) { advance() }
  }
  ```

- [ ] **Step 3: Build to verify**

  ```bash
  cd /Users/justinseo/Desktop/Bloggo/fastblog
  xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/justinseo/Desktop/Bloggo/fastblog
  git add fastblog/Views/StorageManagementView.swift
  git commit -m "$(cat <<'EOF'
  feat: add swipe-to-triage flow for unused photos

  Replaces tap-to-open slideshow with UnusedPhotoTriageView — a
  sequential swipe-left-to-delete / swipe-right-to-keep loop that
  starts from the tapped photo, wraps around, and dismisses back
  to the gallery when all photos have been reviewed.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```
