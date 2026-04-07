# Undo Button in Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bottom-of-screen undo overlay in blog edit mode with a toolbar Undo button next to Save, and repurpose the overlay as a 3-second confirmation toast shown after undo is performed.

**Architecture:** Add a new `UndoToastView` component (text-only, no undo button, auto-dismiss). Add `showUndoToast` + `undoToastText` state to `RecapBlogPageView`. Wire a new toolbar Undo button that calls `performUndo()` then triggers the toast. Remove the old bottom overlay from edit mode.

**Tech Stack:** SwiftUI, existing `RecapBlogPageView` state management

---

## File Map

- **Create:** `fastblog/Views/UndoToastView.swift` — new simplified toast component
- **Modify:** `fastblog/Views/RecapBlogPageView.swift`
  - Add `showUndoToast: Bool` and `undoToastText: String` state variables (~line 175)
  - Remove `isUndoMinimized` state variable (~line 176)
  - Replace `UndoOverlayView` block in overlay stack (~lines 1289–1303) with `UndoToastView` driven by `showUndoToast`
  - Add undo `ToolbarItem` in `toolbarContent` before the Save item (~line 4612)
  - Update `performUndo()` to no longer set `showUndoOverlay` / `lastUndoAction` after undo (already clears them; add toast trigger)

---

## Task 1: Create `UndoToastView`

**Files:**
- Create: `fastblog/Views/UndoToastView.swift`

- [ ] **Step 1: Create the file with this exact content**

```swift
//
//  UndoToastView.swift
//  fastblog
//

import SwiftUI

struct UndoToastView: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 16)
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        UndoToastView(text: "Place hidden")
    }
}
```

- [ ] **Step 2: Build the project to confirm no compile errors**

In Xcode: Product → Build (⌘B). Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/UndoToastView.swift
git commit -m "feat: add UndoToastView for post-undo confirmation"
```

---

## Task 2: Add toast state to `RecapBlogPageView`

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift:173-176`

- [ ] **Step 1: Replace the undo state block**

Find this block (around line 173):
```swift
    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoOverlay = false
    @State private var isUndoMinimized = false
```

Replace with:
```swift
    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoOverlay = false
    @State private var showUndoToast = false
    @State private var undoToastText = ""
```

- [ ] **Step 2: Build to confirm no compile errors**

In Xcode: ⌘B. Expected: Build Succeeded (any `isUndoMinimized` references will now show errors — those are fixed in Task 3).

---

## Task 3: Remove the bottom overlay and wire in the toast

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift:1289-1303`

- [ ] **Step 1: Replace the UndoOverlayView block in the overlay stack**

Find this block (around line 1289):
```swift
            // Undo Overlay (Banner or Button)
            if showUndoOverlay {
                UndoOverlayView(
                    text: lastUndoAction?.text ?? "Item hidden",
                    isMinimized: $isUndoMinimized,
                    onUndo: { performUndo() },
                    onDismiss: {
                        withAnimation {
                            showUndoOverlay = false
                            lastUndoAction = nil
                        }
                    }
                )
                .padding(.bottom, Self.dayFilterApproxHeight + 10)
                .zIndex(20)
            } else if showSplitUndoBanner {
```

Replace with:
```swift
            // Undo Toast (appears for 3s after undo is performed)
            if showUndoToast {
                UndoToastView(text: undoToastText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Self.dayFilterApproxHeight + 10)
                    .zIndex(20)
            } else if showSplitUndoBanner {
```

- [ ] **Step 2: Build to confirm no compile errors**

In Xcode: ⌘B. Expected: Build Succeeded. The `showUndoOverlay` and `isUndoMinimized` references that remain will be cleaned up in subsequent tasks.

---

## Task 4: Update `performUndo()` to trigger the toast

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift` — `performUndo()` function (around line 3603)

- [ ] **Step 1: Find `performUndo()` and update it**

Find this block at the end of `performUndo()` (around line 3651):
```swift
            showUndoOverlay = false
            lastUndoAction = nil

            persistRecapBlogDetail()
        }
    }
```

Replace with:
```swift
            showUndoOverlay = false
            lastUndoAction = nil

            persistRecapBlogDetail()
        }

        // Show toast confirming what was undone (`action` is still in scope from the guard let above)
        undoToastText = action.text
        withAnimation {
            showUndoToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showUndoToast = false
            }
        }
    }
```

- [ ] **Step 2: Build to confirm no compile errors**

In Xcode: ⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit tasks 2–4 together**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: wire UndoToastView into RecapBlogPageView, remove bottom overlay"
```

---

## Task 5: Add Undo toolbar button

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift` — `toolbarContent` (around line 4612)

- [ ] **Step 1: Insert the Undo ToolbarItem before the existing trailing Save item**

Find this block (around line 4612):
```swift
        ToolbarItem(placement: .topBarTrailing) {
            if isEditMode {
                Button {
                    if saveDraft() {
                        isEditMode = false
                    }
                } label: {
```

Insert the following **before** that `ToolbarItem`:
```swift
        ToolbarItem(placement: .topBarTrailing) {
            if isEditMode {
                Button {
                    performUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .foregroundColor(lastUndoAction != nil ? recapChromeForeground : recapChromeForeground.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(lastUndoAction == nil)
            }
        }
```

- [ ] **Step 2: Build and run in simulator**

In Xcode: ⌘R. Steps to verify:
1. Open a blog and tap the edit (pencil) button to enter edit mode.
2. Confirm the Undo button appears to the left of Save, visually greyed out.
3. Remove a place or photo — confirm the Undo button lights up (full opacity).
4. Tap Undo — confirm the place/photo is restored and a toast appears at the bottom with the description text (e.g. "Place hidden").
5. Confirm the toast disappears after ~3 seconds.
6. Confirm the Undo button returns to greyed-out state.

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: add Undo button to toolbar in blog edit mode"
```

---

## Task 6: Clean up residual `showUndoOverlay` and `isUndoMinimized` references

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`

- [ ] **Step 1: Search for remaining `isUndoMinimized` references**

Search in Xcode (⌘⇧F) for `isUndoMinimized` in `RecapBlogPageView.swift`. There should be none left after Task 2. If any remain, delete them.

- [ ] **Step 2: Search for remaining `showUndoOverlay` usages and audit them**

Search for `showUndoOverlay` in `RecapBlogPageView.swift`. Expected surviving usages:
- The declaration `@State private var showUndoOverlay = false` (~line 175) — keep, still set by `removePlaceStop`, `removePhoto`, `mergePlaceStops` as a signal; just no longer drives the overlay UI.

Actually, `showUndoOverlay` is now unused as a UI driver. Remove it and all its assignments:

Find and remove the declaration:
```swift
    @State private var showUndoOverlay = false
```

Then find every assignment of `showUndoOverlay = true` (in `removePlaceStop` ~line 3374, `removePhoto` ~line 3418, `mergePlaceStops` ~line 3466) and remove those lines.

Also remove `showUndoOverlay = false` from `performUndo()` (now inside the `withAnimation` block from Task 4 — remove that line) and from `saveDraft()` (~line 3338).

- [ ] **Step 3: Build to confirm no compile errors**

In Xcode: ⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "chore: remove unused showUndoOverlay and isUndoMinimized state"
```

---

## Task 7: Final smoke test

- [ ] **Step 1: Run app in simulator**

In Xcode: ⌘R.

- [ ] **Step 2: Verify all undo scenarios**

| Action | Expected toolbar button | Expected after tap Undo |
|---|---|---|
| Remove a place | Lights up (full opacity) | Place restored, toast "Place hidden" for 3s |
| Remove a photo | Lights up | Photo restored, toast "Photo removed" for 3s |
| Merge two places | Lights up | Places split back, toast "Places merged" for 3s |
| No undoable action | Greyed out, disabled | — |
| Tap Save | Greyed out (undo cleared on save) | — |

- [ ] **Step 3: Verify CountryBlogsView and SplitBlogView unaffected**

Open the blogs list and delete a blog — confirm the existing bottom `UndoOverlayView` still appears as before.

- [ ] **Step 4: Commit if any fixes were needed, otherwise done**

```bash
git add -p
git commit -m "fix: final adjustments from smoke test"
```
