# Onboarding animations + legal copy — final spec (merge recovery)

> **Purpose:** After your teammate resolves the merge, hand this file (plus the two task plans it references) to an agent so it can **reproduce the current `new_inapp_camera` behavior** without guessing from an outdated plan.
>
> **Source of truth:** This document was written from the tree at branch **`new_inapp_camera`** (HEAD includes onboarding commits through `4918231` and related fixes). **Do not** paste the old embedded Swift from `2026-05-01-camera-roll-to-blog-onboarding.md` — that snapshot predates the final layout.

**Related plans (updated in-repo):**

- `docs/superpowers/plans/2026-05-01-camera-roll-to-blog-onboarding.md` — camera-roll → blog animation + flow wiring
- `docs/superpowers/plans/2026-05-01-creating-blog-photo-finale.md` — “Creating blog” falling-photo finale

---

## 1. Onboarding flow order (final)

Defined in `fastblog/Views/Onboarding/OnboardingFlowView.swift`.

| Order | `OnboardingStep` | View | Continue action |
|------:|------------------|------|-------------------|
| 1 | `.splash` | `SplashView` | `step = .cameraRollToBlog` |
| 2 | `.cameraRollToBlog` | `CameraRollToBlogView` | `step = .problemStatement` |
| 3 | `.problemStatement` | `ProblemStatementView` | `step = .neighborhoodIntro` |
| 4 | `.neighborhoodIntro` | `NeighborhoodExplainerView` | `step = .neighborhood` |
| 5 | `.neighborhood` | `NeighborhoodSelectionView` | forward → photo permission; back → intro |
| 6 | `.photoPermissionOnboarding` | `PhotoPermissionOnboardingView` | per `PHAuthorizationStatus` |
| 7 | `.tripDistanceFromHome` | `TripDistanceFromHomeOnboardingView` | completes onboarding |
| 8 | `.photoPermissionDenied` | `PhotosPermissionView` | settings / continue without |

**Note:** The old plan said Continue on `CameraRollToBlogView` lands on `NeighborhoodExplainerView` directly. **Final behavior** inserts **`ProblemStatementView`** then **`NeighborhoodExplainerView`** (`neighborhoodIntro`).

---

## 2. Legal / consent copy (final strings)

These are **not** a copyright symbol line; they are **consent + Privacy / Terms** affordances. Exact wording matters for product/legal consistency.

### `SplashView` (`fastblog/Views/Onboarding/SplashView.swift`)

- Primary CTA: **Get Started**
- Legal line: **`By continuing you agree to Bloggo's`** (no comma after “continuing”). In source, **Bloggo** uses a **typographic apostrophe** (Unicode `’`, U+2019), not ASCII `'` — match the committed file exactly.
- `Privacy Policy` / `Terms of Service` open **`PrivacyPolicyView`** / **`TermsOfServiceView`** via `.sheet`

### `ProblemStatementView` (same file as flow: `OnboardingFlowView.swift`)

- Bottom legal line: **`By continuing, you agree to Bloggo's`** (comma after “continuing”; ASCII apostrophe in **`Bloggo's`** in current source)
- Buttons present sheets for Privacy / Terms (same as splash)

### `CameraRollToBlogView` (`fastblog/Views/Onboarding/CameraRollToBlogView.swift`)

- On the tagline overlay, after **Continue** appears, footer text matches **ProblemStatementView** wording: **`By continuing, you agree to Bloggo's`** (ASCII apostrophe on **Bloggo's** in current source — differs from Splash’s typographic apostrophe)
- **Current implementation detail:** `Privacy Policy` and `Terms of Service` buttons in this overlay use **empty actions** `{}`. For parity with Splash / Problem statement, wire the same `.sheet` pattern (or extract a small shared subview). Track this when resolving merge conflicts.

---

## 3. `CameraRollToBlogView` — animation & layout (final vs original plan)

**File:** `fastblog/Views/Onboarding/CameraRollToBlogView.swift`  
**Project:** `fastblog.xcodeproj/project.pbxproj` — refs `BB0003E4` / `BB0003E5` (unchanged from original plan)

### Imports

- `import SwiftUI`
- `import UIKit` (for `UIScreen.main.bounds.height` in animation)

### Falling tiles

- Model uses **`xFraction`** (0–1 of screen width) and **`landYFraction`** (0–1 of screen height), not fixed pt `xOffset` / `landY`.
- Initial Y offset for tiles: **`-240`**.
- Tiles are **larger** and positions differ from the first-draft plan; keep the **array in the committed file** as canonical.
- **No** extra white stroke overlay on tiles in the final file (shadow + gradient only).
- Filename badge font **8pt** semibold (plan had 7pt).

### Blog mock structure

- **Not** a single `blogMockView` that includes day pills inside scroll content.
- **Blog block:** `Color.clear.ignoresSafeArea()` + `.overlay(alignment: .top) { blogMockView }` + `.offset(y: blogOffset)` so the mock pins from the **top of the screen** while translating.
- **Day pill bar:** separate layer in root `ZStack` when `showDayPills`, **fixed to screen bottom**, so it **does not scroll away** with `blogOffset`.
- `blogScrollContent` ends with **`Color.clear.frame(height: 58)`** so the last stop row stays clear of the fixed pill bar.

### Cover hero (`coverHeroMock`)

- Height **300** (plan draft had 220).
- **Vivid tropical** three-stop `LinearGradient` (not the dark brown/navy gradient from the draft).
- Scrim: **light bottom gradient** only (`black.opacity(0.55)` → `0.05` bottom→center), not the heavy multi-layer scrim from the draft.

### Map mock

- Card height **140** (draft plan had 90).

### Photo strip (`photoStrip`)

- Thumbnail size: **`UIScreen.main.bounds.width * 0.8`** square thumbnails (matches app `PlaceStopRowView` comment in file).

### Tagline overlay

- Background: **`.ultraThinMaterial`** + **`Color.black.opacity(0.72)`** overlay (full-screen frosted dark).
- Headline typography: **30pt** bold main headline; subtitle **15pt** (draft used 24 / 13).
- **Continue** uses `OnboardingConstants.Colors.doneButtonBlue` and **rounded rect** 14 continuous (not always capsule in every draft).
- **Continue** + legal footer animate in with **`withAnimation(.spring(...))`** when `showContinue` becomes true (not only opacity on bool).

### Timing deltas (vs old plan text)

| Phase | Old plan | Final (committed) |
|--------|----------|-------------------|
| Blog slide delay before `blogOffset` | 1500 ms | **1000 ms** |
| `showTagline` | assigned `true` without animation | **`withAnimation(.easeIn(duration: 0.4))`** |
| `showContinue` | assigned `true` without animation | **`withAnimation(.spring(...))`** |

Landing Y for each tile in the loop: `fallingPhotos[i].landYFraction * screenHeight` where `screenHeight = UIScreen.main.bounds.height`.

---

## 4. “Creating blog” photo finale (final vs original plan)

**Files:** `fastblog/Views/CreatingRecapView.swift`, `fastblog/Views/CreateBlogFlowView.swift`

### Photo selection (`selectedPhotoIdentifiers`)

**Final:** First **12** `localIdentifier` values from **all** photos in the trip (days flattened), **not** filtered to `isSelected`:

```swift
Array(trip.days
    .flatMap(\.photos)
    .compactMap(\.localIdentifier)
    .prefix(12))
```

Original plan used `.filter(\.isSelected)` — **do not** restore that if you want current branch behavior.

### `CreatingRecapView` initializer call order

`CreateBlogFlowView` passes **`onCancel`** first, then **`photoIdentifiers`**.

### `loadPhotos()` callback safety

`PHImageManager` completion updates **`loadedImages`** inside **`DispatchQueue.main.async { ... }`** and guards `index < loadedImages.count`.

### Dissolve animation

`fallingPhotosLayer` applies **`.animation(.easeIn(duration: 0.5), value: dissolvePhotos)`** on blur/scale so dissolve animates reliably.

### `startPhotoFinale()` timing comment

File documents worst-case sleep budget (~**4690 ms** inside **5000 ms** `creatingAnimationDuration`) so staggered drops for 12 photos still finish before handoff.

---

## 5. Verification commands (post-merge)

```bash
xcodebuild -project /Users/justinseo/Desktop/Bloggo/fastblog/fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build
```

Reset onboarding if needed:

```text
UserDefaults / OnboardingStore: clear `hasCompletedOnboarding` equivalent per app (see `OnboardingStore` usage in `OnboardingFlowView`).
```

---

## 6. Optional: commits on this branch that correspond to this work

High-signal git subjects (newest relevant first):

- `4918231` — finale: show all trip photos, not only selected
- `db16222` — `loadPhotos` main-queue dispatch + timing/animation
- `7c299a6` / `199d25e` / `7c015f6` / `41a3441` — creating recap finale implementation chain
- `a07a1af` / `cfaff6f` / `1ce6e8a` / `d41aa8b` — onboarding pages / copy tuning

Use `git log --oneline -- fastblog/Views/Onboarding fastblog/Views/CreatingRecapView.swift fastblog/Views/CreateBlogFlowView.swift` after merge for the exact sequence on `main`.
