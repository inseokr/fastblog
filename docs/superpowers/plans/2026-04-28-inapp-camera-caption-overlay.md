# In-App Camera Caption Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Snapchat-style in-place caption overlay for the in-app camera — tapping the caption toolbar button freezes the last capture full-bleed on screen so the user can type a caption before committing or discarding.

**Architecture:** All changes live inside the existing `CameraCaptureView` hierarchy in `TripsView.swift`. A new `InAppCameraCaptionOverlay` SwiftUI struct (separate file) is injected as a ZStack layer over the live preview when `isCaptionModeActive` is true; the existing state, bindings, and action functions (`enterInPlaceCaptionMode`, `commitCaptionModeDone`, `discardCaptionModeCapture`) already exist and just need to be wired up. A new toolbar button in `nonCaptionCameraOverlay` enters the mode.

**Tech Stack:** Swift, SwiftUI, UIKit (`ScrollMetricsReportingTextEditor` / `UITextView`)

---

## File Map

| File | Change |
|------|--------|
| `fastblog/Views/InAppCameraCaptionOverlay.swift` | **Create** — full-bleed frozen-still overlay struct |
| `fastblog/Views/TripsView.swift` | **Modify** — (a) add caption button to right toolbar VStack in `nonCaptionCameraOverlay`; (b) replace disabled comment in `inAppCameraPreviewStack` with the overlay |
| `fastblog.xcodeproj/project.pbxproj` | **Modify** — register new swift file (4 sections) |

---

## Task 1: Create `InAppCameraCaptionOverlay.swift`

**Files:**
- Create: `fastblog/Views/InAppCameraCaptionOverlay.swift`

- [ ] **Step 1: Write the file**

```swift
//
//  InAppCameraCaptionOverlay.swift
//  fastblog
//
//  Snapchat-style in-place caption overlay for the in-app camera.
//  Shown after the user taps the caption toolbar button — the live
//  preview freezes and this layer sits on top at full bleed.
//  Exits by tapping Done (commit) or xmark (discard).
//

import SwiftUI
import UIKit

/// Full-screen caption overlay that replaces the visible live camera
/// preview when caption mode is active in CameraCaptureView.
struct InAppCameraCaptionOverlay: View {
    /// The frozen still to show in place of the live camera feed.
    let frozenImage: UIImage
    /// Caption draft. Bound to CameraCaptureView.captionModeCaptionBinding.
    @Binding var caption: String
    /// Resolved place name for this capture.
    var placeTitle: String
    /// Optional place subtitle (city / country).
    var placeSubtitle: String?
    /// Controls ScrollMetricsReportingTextEditor first-responder state.
    @Binding var wantsKeyboard: Bool
    /// Done button is disabled until the capture is injected into a blog or draft.
    var canCommit: Bool
    /// Tap xmark — discard this capture and all associated storage.
    var onDiscard: () -> Void
    /// Tap Done — persist caption then exit caption mode.
    var onDone: () -> Void
    /// When set, shows an edit-pencil next to the place title.
    var onEditPlace: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            // ── 1. Frozen still ──────────────────────────────────────────
            // Matches FullScreenCameraPreview: aspect-fill framed to screen bounds.
            GeometryReader { geo in
                Image(uiImage: frozenImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // ── 2. Scrim for text legibility ─────────────────────────────
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ── 3. Chrome ────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Top bar: xmark (leading) + Done pill (trailing)
                HStack {
                    Button(action: onDiscard) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Discard photo")

                    Spacer()

                    Button(action: onDone) {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                canCommit ? Color.blue : Color.blue.opacity(0.4),
                                in: Capsule()
                            )
                    }
                    .disabled(!canCommit)
                    .accessibilityLabel("Save caption and photo")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom: place title + caption editor
                VStack(alignment: .leading, spacing: 6) {
                    // Place title row with optional edit pencil
                    HStack(alignment: .top, spacing: 8) {
                        Text(placeTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if let editPlace = onEditPlace {
                            Button(action: {
                                wantsKeyboard = false
                                editPlace()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.22))
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit place name")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let sub = placeSubtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    // Caption text editor
                    ZStack(alignment: .topLeading) {
                        ScrollMetricsReportingTextEditor(
                            text: $caption,
                            wantsKeyboardFocus: $wantsKeyboard,
                            textInsets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
                            caretTint: .white
                        )
                        .frame(minHeight: 100, maxHeight: 180)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))

                        if caption.isEmpty {
                            Text("Describe this moment...")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Focus the keyboard as soon as the overlay appears.
            DispatchQueue.main.async {
                wantsKeyboard = true
            }
        }
    }
}
```

- [ ] **Step 2: Verify the file is at the right path**

```
ls fastblog/Views/InAppCameraCaptionOverlay.swift
```
Expected: file listed.

---

## Task 2: Register the new file in `project.pbxproj`

**Files:**
- Modify: `fastblog.xcodeproj/project.pbxproj`

The file uses IDs `BB00040A` (FileReference) and `BB00040B` (BuildFile) which are confirmed unused.

- [ ] **Step 1: Add PBXBuildFile entry**

Find the line (around line 231):
```
		BB000409 /* EditBlogPhotoFlowView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB000408 /* EditBlogPhotoFlowView.swift */; };
```
Insert **after** it:
```
		BB00040B /* InAppCameraCaptionOverlay.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB00040A /* InAppCameraCaptionOverlay.swift */; };
```

- [ ] **Step 2: Add PBXFileReference entry**

Find the line (around line 483):
```
		BB000408 /* EditBlogPhotoFlowView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EditBlogPhotoFlowView.swift; sourceTree = "<group>"; };
```
Insert **after** it:
```
		BB00040A /* InAppCameraCaptionOverlay.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = InAppCameraCaptionOverlay.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add to PBXGroup (Views group)**

Find the line (around line 702):
```
				BB000408 /* EditBlogPhotoFlowView.swift */,
```
Insert **after** it:
```
				BB00040A /* InAppCameraCaptionOverlay.swift */,
```

- [ ] **Step 4: Add to PBXSourcesBuildPhase**

Find the line (around line 1032):
```
				BB000409 /* EditBlogPhotoFlowView.swift in Sources */,
```
Insert **after** it:
```
				BB00040B /* InAppCameraCaptionOverlay.swift in Sources */,
```

- [ ] **Step 5: Verify build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/InAppCameraCaptionOverlay.swift fastblog.xcodeproj/project.pbxproj
git commit -m "feat: add InAppCameraCaptionOverlay view (unconnected)"
```

---

## Task 3: Add caption toolbar button to `nonCaptionCameraOverlay`

**Files:**
- Modify: `fastblog/Views/TripsView.swift` around line 2420

The right-side VStack currently has this order: Flip → Flash → Save to Photos → Vibe → "VIBE" label.
Insert the caption button **between Flash and Save to Photos**.

- [ ] **Step 1: Locate the insertion point**

The Flash button ends at approximately:
```swift
            .accessibilityLabel(flashAccessibilityLabel)
            .disabled(cameraController.position == .front)
```
The Save-to-Photos button starts right after:
```swift
            Button {
                toggleSaveToPhotos()
            } label: {
```

- [ ] **Step 2: Insert the caption button**

Insert this block between the two buttons above:

```swift
            Button {
                enterInPlaceCaptionMode()
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(latestCaptureWithPreview == nil ? .white.opacity(0.35) : .white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(latestCaptureWithPreview == nil)
            .accessibilityLabel("Add caption to latest photo")
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: add caption toolbar button to in-app camera"
```

---

## Task 4: Wire `InAppCameraCaptionOverlay` into `inAppCameraPreviewStack`

**Files:**
- Modify: `fastblog/Views/TripsView.swift` around line 2469

- [ ] **Step 1: Locate the disabled comment**

Find this block (around line 2469):
```swift
    @ViewBuilder
    private var inAppCameraPreviewStack: some View {
        ZStack {
            cameraPreviewLayer

            if !isCaptionModeActive {
                nonCaptionCameraOverlay
            }

            // In-app camera caption mode is intentionally disabled.
        }
    }
```

- [ ] **Step 2: Replace the disabled comment with the overlay**

Replace the entire `inAppCameraPreviewStack` computed property with:

```swift
    @ViewBuilder
    private var inAppCameraPreviewStack: some View {
        ZStack {
            cameraPreviewLayer

            if !isCaptionModeActive {
                nonCaptionCameraOverlay
            }

            if isCaptionModeActive, let frozen = captionModeFrozenImage {
                InAppCameraCaptionOverlay(
                    frozenImage: frozen,
                    caption: captionModeCaptionBinding,
                    placeTitle: captionModePlaceTitle,
                    placeSubtitle: captionModePlaceSubtitle,
                    wantsKeyboard: $captionModeWantsKeyboard,
                    canCommit: captionModeCanCommit,
                    onDiscard: discardCaptionModeCapture,
                    onDone: commitCaptionModeDone,
                    onEditPlace: { showCaptionModeEditPlaceSheet = true }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: wire InAppCameraCaptionOverlay into camera preview stack"
```

---

## Spec Coverage Self-Check

| Requirement | Covered by |
|-------------|-----------|
| Full-bleed frozen still (no modal, no sheet, no card) | Task 1 — `GeometryReader` + `scaledToFill` matching `FullScreenCameraPreview` framing |
| ZStack overlay over preview (same level as existing overlays) | Task 4 — injected in `inAppCameraPreviewStack` ZStack |
| Opacity transition live→frozen | Task 4 — `.transition(.opacity)` on the overlay |
| Hide main camera controls while caption mode active | Already handled — `nonCaptionCameraOverlay` is gated on `!isCaptionModeActive` |
| Swipe-up gallery gesture suppressed | Already handled — `inAppCameraChromeRoot` DragGesture has `guard !isCaptionModeActive` |
| Caption toolbar button (quote.bubble, 44pt, ultraThinMaterial) | Task 3 |
| Button disabled when no capture with preview | Task 3 — `.disabled(latestCaptureWithPreview == nil)` |
| Caption button inserts between Flash and Save to Photos | Task 3 |
| xmark → discard capture + storage cleanup | Task 1 — `onDiscard: discardCaptionModeCapture` (existing function handles blog/draft removal + InAppCameraPhotoStore cleanup) |
| Done → persist caption via `createdRecapStore.updatePhotoCaption` (blog path) | Already in `commitCaptionModeDone()` |
| Done → persist caption via `tripsViewModel.updatePhotoCaptionInCameraDraft` (draft path) | Already in `commitCaptionModeDone()` |
| Place title shown with edit-pencil button | Task 1 — `onEditPlace` triggers `showCaptionModeEditPlaceSheet` |
| Keyboard focused on overlay appear | Task 1 — `onAppear { wantsKeyboard = true }` |
| `ScrollMetricsReportingTextEditor` for caption input | Task 1 — used directly, matches `PhotoCaptionEditSheet` pattern |
| Toast on Done: "1 moment added to [title]" | Already in `commitCaptionModeDone()` |
| Toast routed via `postDismissToast` when non-nil | Already in `commitCaptionModeDone()` |
| `includedInExitAddedToast = false` on Done | Already in `commitCaptionModeDone()` |
| "Edit note?" vs "Add note?" in `addNotePromptCard` | Already implemented via `sessionHasAnyCaptionNote` |
| No behavior change when caption overlay never opened | No changes to `applyCapturedPhoto` or exit flow; overlay only activates on button tap |
