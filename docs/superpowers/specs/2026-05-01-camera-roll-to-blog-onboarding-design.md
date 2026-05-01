# Camera Roll → Blog Onboarding Page

## Context

New users don't immediately understand what Bloggo does. This animated onboarding page
is inserted between SplashView (step 1) and ProblemStatementView (step 2) to visually
demonstrate the core value: messy iPhone camera roll becomes a beautifully organized Blog.

---

## Placement in flow

`OnboardingFlowView.OnboardingStep`:

```
.splash  →  .cameraRollToBlog  →  .problemStatement  →  ...
```

---

## New file

`fastblog/Views/Onboarding/CameraRollToBlogView.swift`

Entry point: `struct CameraRollToBlogView: View` with one callback `onContinue: () -> Void`.

---

## Animation sequence (7 phases)

All timing via `Task.sleep` in a single async func `startAnimation()` called from `.task {}`.
Never use `DispatchQueue.main.asyncAfter`. All `@Published`/`@State` mutations on `@MainActor`.

| Phase | Delay | What happens |
|-------|-------|-------------|
| 1 | 0.3 s | "Your Camera Roll" label fades in (opacity + subtle scale) |
| 2 | 0.5 s | 12 photo tiles fall from above — staggered 0.1 s apart, random rotations ±15°, `easeIn` gravity feel |
| 3 | 2.6 s | All photos dissolve out (opacity → 0, blur 4, slight scale down) |
| 4 | 0.1 s | White flash (`Color.white.opacity(0.22)` brief pulse) |
| 5 | 0.2 s | Blog UI fades in, then staggered reveal: cover title → dates → share button → map → day header → stop 1 → stop 2 → day pills |
| 6 | 1.5 s | Entire blog container slides up `offset(y: -220)` over 1.4 s (custom ease-in-out via `withAnimation`) |
| 7 | 1.6 s | Tagline overlay appears + Continue button slides up from bottom |

---

## View structure

```
ZStack (background: #050A30 gradient)
 ├── CameraLabelView          — phase 1
 ├── FallingPhotosLayer       — phase 2 (12 photo tiles, positioned absolutely)
 ├── FlashOverlay             — phase 4
 ├── BlogMockView             — phase 5–6 (offset animated)
 │    ├── CoverHeroMock       — gradient bg + scrim + centered title block
 │    ├── ScrollContent       — map + day header + 2 stop rows + day pills
 └── TaglineOverlay           — phase 7 (ZStack over all, .ultraThinMaterial bg)
      └── ContinueButton      — pinned bottom, appears with tagline
```

---

## Falling photos (12 tiles)

Use a `FallingPhoto` struct:
```swift
struct FallingPhoto {
    let size: CGSize
    let xPos: CGFloat        // 0–1 normalised
    let rotation: Double     // degrees
    let gradient: [Color]
    let delay: Double
    let filename: String     // e.g. "IMG_3847"
}
```

12 hardcoded instances covering varied sizes (55–110 pt wide), positions, rotations, gradient colours
taken from the existing `MockPhotoView` palette. Each animates:
- `opacity: 0 → 1` on fall-in
- `offset(y: -200 → landY)` on fall-in
- `opacity: 1 → 0` + `blur(4)` + `scaleEffect(0.8)` on dissolve

---

## Blog mock (`BlogMockView`)

Hardcoded content: "Bali 2024" trip. Uses real app colors/fonts from project conventions.

### Cover hero (180 pt tall)
- Background: `LinearGradient([Color(hex:"1a1a2e"), Color(hex:"2d3561"), ...])` — matches `CoverPageView` fallback
- Scrims: `Color.black.opacity(0.38)` solid + `LinearGradient(.black.opacity(0.62) → .black.opacity(0.12) → .black.opacity(0.45))`
- Centered VStack (spacing 10):
  - Title: `"Bali 2024"` — `.system(size: 26, weight: .bold)`, white, `shadow(.black.opacity(0.6), r:6)`
  - Date: `"Jun 12 – Jun 17, 2024"` — `.callout`, `white.opacity(0.9)`
  - Count: `"14 moments"` — `.callout`, `white.opacity(0.9)`
  - Share button: `"Share Your Blog"` — `.ultraThinMaterial` capsule, matches `RecapBlogPageView` style

### Map card (72 pt tall)
Rounded rectangle (radius 14) with `Color(white: 0.12)` fill + 3 coloured `Circle` pins
(green/blue/orange at fixed positions). Expand arrow icon top-right. Matches `mapCard()`.

### Day header
`"Jun 12"` — `.system(size: 18, weight: .bold)`, white.
`"☀️ 84° / 71°F"` — `.subheadline`, `white.opacity(0.7)`.

### Place stop rows (2 rows)

Each row: `HStack(spacing: 10)` — badge circle + info VStack. Matches `PlaceStopRowView` layout.

**Badge**: 28×28 pt circle. Stop 1 = `.green`, Stop 2 = `.blue`.

**Info**:
- Name: `.system(size: 15, weight: .bold)`, white
- Subtitle: location + time, `.caption`, `white.opacity(0.45)`
- Category chip: capsule, matching `PlaceCategoryChip` style
- **Photo strip**: `ScrollView(.horizontal, showsIndicators: false)` + `HStack(spacing: 8)`
  - Each thumb: `240 × 190` pt (80% of 300 pt phone width), `cornerRadius(10)`, gradient fill
  - Timestamp badge: top-left, `black.opacity(0.6)` capsule
  - "+N" overflow chip at end

**Stop 1** — Tegallalang Rice Terraces, Ubud · 2:14 PM, Nature, 3 photo thumbs + "+7"
**Stop 2** — Tirta Empul Temple, Tampaksiring · 4:50 PM, Landmark, 2 photo thumbs + "+4"

### Day pill bar (50 pt, bottom)
`HStack` of capsule pills: "Day 1" (`.blue` bg, white text) + "Day 2"–"Day 5" (idle `Color(white:0.2)`).
Border-top: `white.opacity(0.08)`, 0.5 pt.

---

## Tagline overlay (phase 7)

`ZStack` covering entire screen, `Color.black.opacity(0.72)` + `.background(.ultraThinMaterial)`.

Staggered fade-up animations (spacing 0.15 s):
1. Star glyph `"✦"` — spring scale pop
2. `"INTRODUCING BLOGGO"` — 11 pt, uppercase, `white.opacity(0.45)`
3. `"Your camera roll,\norganized into\na Blog."` — 22 pt bold, white. "Blog." uses brand gradient `#C8EBFF → #7bb8ff`
4. `"Automatically sorted by day,\nplace & moment."` — 13 pt, `white.opacity(0.5)`
5. **Continue button** — `#007AFF` filled, `cornerRadius(14)`, 16 pt semibold, `padding(.horizontal, 20)`, `padding(.bottom, 40)`

---

## `OnboardingFlowView` changes

1. Add `.cameraRollToBlog` to `OnboardingStep` enum
2. Insert branch between `.splash` and `.problemStatement`:
   ```swift
   } else if step == .cameraRollToBlog {
       CameraRollToBlogView { step = .problemStatement }
   ```
3. Change `.splash` callback: `step = .cameraRollToBlog`

---

## pbxproj registration

New IDs (next available after BB000281):
- **BB000282** — PBXBuildFile
- **BB000283** — PBXFileReference

Add to:
- `PBXBuildFile` section
- `PBXFileReference` section
- Onboarding `PBXGroup` (alongside `SplashView.swift`)
- `PBXSourcesBuildPhase` Sources list

---

## Verification

1. Build: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
2. Run on simulator — navigate to onboarding (fresh install or reset `hasCompletedOnboarding`)
3. Watch full animation sequence plays through all 7 phases
4. Tap Continue → lands on NeighborhoodExplainerView ("Set Your Home Area")
5. Confirm back navigation from NeighborhoodExplainerView does not regress
