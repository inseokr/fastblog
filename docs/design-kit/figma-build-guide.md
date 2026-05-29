# Figma Build Guide — Bloggo Visual Design Kit

**Date:** 2026-05-28  
**Product:** Bloggo (fastblog iOS)  
**Status:** Ready to build in Figma

---

## 1. Create the Figma file

1. Team / project: **Bloggo**
2. File name: **`Bloggo Design Kit`**
3. Enable **Variables** (local collections first; publish as library when v1 is stable)
4. Frame preset: **iPhone 15 Pro** (393 × 852) for all screen templates
5. Pin the file URL in [README.md](./README.md) and your team wiki

### Pages (in order)

| # | Page name | Purpose |
|---|-----------|---------|
| 1 | `Start here` | Role-based “open these pages” cards |
| 2 | `Brand` | Logo, icon, voice, photography, do/don’t |
| 3 | `Foundations` | Color, type, spacing, radius, effects, motion |
| 4 | `Components` | Library-ready UI pieces + all states |
| 5 | `Screens` | Full-device compositions for sign-off |
| 6 | `Patterns` | Navigation, dark-first, photo overlays |
| 7 | `Resources` | Icon exports, PDF colors, changelog |
| 8 | `Archive` | Deprecated / brainstorm snapshots |

---

## 2. Variables (paste into Figma)

Create two collections: **Color** and **Layout**. Use slash naming so Dev Mode maps cleanly to docs.

### Color / Brand

| Variable | Hex | Usage |
|----------|-----|--------|
| `background/app` | `#050A30` | Full-screen, bottom nav bar |
| `background/app-gradient-end` | `#080E38` | Splash gradient bottom |
| `surface/card` | `#242424` | Dark cards |
| `surface/card-narrative` | `#191919` | Story / narrative cards |
| `action/primary` | `#007AFF` | Buttons, links, Tap to Blog |
| `action/filter-active` | `#0B84FF` | Active filter chips |
| `action/destructive` | `#FF4539` | Delete, destructive |
| `feedback/success` | `#A6F2B7` | Success states |
| `text/brand-accent` | `#C8EBFF` | Accent headlines on dark |
| `text/primary-on-dark` | `#FFFFFF` @ 92% | Primary copy on navy |
| `text/secondary-on-dark` | `#FFFFFF` @ 70% | Secondary copy |
| `text/tertiary-on-dark` | `#FFFFFF` @ 50% | Disabled / hint |
| `border/hairline-on-dark` | `#FFFFFF` @ 12% | Nav top border, dividers |
| `export/pdf-header` | `#2E62E0` | PDF header accent |

### Color / Scrim & overlay (document as % on black or white)

| Variable | Value | Usage |
|----------|-------|--------|
| `scrim/subtle` | Black 15% | Tag backgrounds |
| `scrim/border` | White 20% | Borders on dark |
| `scrim/shadow` | Black 30–35% | Shadows |
| `scrim/loading` | Black 45% | Loading overlay |
| `scrim/dim` | Black 60% | Modal dim |
| `scrim/photo-text` | Black 65% → 0% | Bottom photo caption gradient |

### Color / Light mode (reference only — use system in UI)

Show side-by-side swatches labeled **iOS adaptive** (not hardcoded hex in app):

- `system/grouped-background`
- `system/secondary-grouped-background`
- `system/tertiary-grouped-background`

### Layout

| Variable | Value | Usage |
|----------|-------|--------|
| `space/grid-unit` | 4 | Base grid |
| `space/screen-horizontal` | 20 | Standard horizontal padding (`OnboardingConstants.Layout`) |
| `radius/search-field` | 12 | Search bars |
| `radius/primary-button` | 25 | Pill buttons |
| `radius/sheet-top` | 16–20 | Bottom sheet top corners (continuous) |
| `nav/bar-content-height` | 62 | Bottom nav content |
| `nav/bar-breathing` | 8 | Padding above nav (camera shutter bar) |
| `touch/min-target` | 44 | Minimum tap target |
| `splash/logo-size` | 200 | Splash mark |
| `type/splash-title` | 34 | Splash wordmark size |

### Typography (text styles in Figma)

Use **SF Pro** (or Inter only for web marketing — not for iOS screens).

| Style name | Size | Weight | Use |
|------------|------|--------|-----|
| `text/splash-title` | 34 | Bold | Splash |
| `text/nav-label` | 10–11 | Medium | Bottom nav labels |
| `text/banner-title` | 17 | Semibold | Tap to Blog title |
| `text/banner-subtitle` | 13 | Regular | Tap to Blog subtitle |
| `text/card-title` | 17 | Semibold | Place cards |
| `text/body` | 17 | Regular | Body |
| `text/caption` | 12 | Regular | Metadata |
| `text/toolbar-save` | 15 (subheadline) | Semibold | Recap editor Save |

### Effects

| Style | Spec |
|-------|------|
| `effect/material-ultrathin` | Label: “Maps to `.ultraThinMaterial`” — show on photo, not flat gray |
| `effect/photo-scrim` | Linear gradient bottom → center, black 65% → 0% |

### Motion (annotation frame on Foundations)

| Token | Value |
|-------|--------|
| `motion/spring-interactive` | Spring ~0.4s, damping 0.75 |
| `motion/fade-screen` | Ease in-out 300ms |
| `motion/dismiss-quick` | Ease out 200ms |

---

## 3. Brand page

### Frames to include

1. **App icon** — export from `Assets.xcassets/AppIcon.appiconset`
2. **Splash mark** — `SplashIcon` / `AppIconMark` (200pt reference)
3. **Wordmark** — “Bloggo” in splash title style on `background/app`
4. **Clear space** — 1× icon height minimum around mark
5. **Photography mood** — 3–6 full-bleed travel photos with short captions (warm, cinematic, UI minimal in frame)
6. **Voice** — sample strings: “Tap to Blog”, “Scan your photos into a blog”, “My Blogs”, “My Places”
7. **Do / Don’t** — e.g. don’t use light gray text on navy; don’t clip photos without scrim for captions

---

## 4. Components page (library)

Build each as a **component set** with variants. Link description field to Swift file path.

### Priority v1 (ship with camera-nav redesign)

#### `BottomNavBar`

| Property | Values |
|----------|--------|
| Active tab | My Blogs \| Camera \| My Places |

**Anatomy**

- Background: `background/app`
- Top border: 1px `border/hairline-on-dark`
- Height: `nav/bar-content-height` + home indicator (show safe-area inset in layout guide)
- Items: equal width × 3
- Active: white icon + white label + dot below label
- Inactive: white icon + label @ **40%** opacity
- Icons: `MyBlogsIcon`, `camera.fill` (SF Symbol placeholder), `MyPlacesIcon`

**Swift:** `Views/Components/BottomNavBar.swift` (planned)

#### `Banner / Tap to Blog`

- Compact row below search on My Blogs
- `+` icon, title “Tap to Blog”, subtitle “Scan your photos into a blog”
- Tint: `action/primary` at low opacity background (blue-tinted row — match implementation)
- Horizontal padding: `space/screen-horizontal`

#### `Nav icon button`

- Gear `gearshape.fill` — Settings (My Blogs, My Places)
- Size ≥ `touch/min-target`

#### `PlaceCard` (existing code variants)

| Variant | Notes |
|---------|--------|
| minimal | Default list |
| editorial | Richer layout |
| voyage | Glassmorphic |

**Swift:** `PlaceCardView.swift`

#### `Search field (dark context)`

- Corner radius `radius/search-field`
- Reference: onboarding search styling

#### `Recap editor toolbar Save`

- Text only, `action/primary`, padding H18 V9

**Swift:** `RecapEditorToolbarSaveLabel` in `AppChromeMetrics.swift`

### Priority v2

- `KeyboardCaptionToolbar` — Cancel / Clear / Done
- `RecapPhotoThumbnail` — with/without quality badge
- `RankBadge` — gold #1 variant
- `ReminderCardView`, `RecallCard`
- Sheet chrome — `pullUpTopSurface` top radius only

---

## 5. Screens page (sign-off)

One frame per screen, **dark mode primary**, optional light variant column.

| Screen | Key elements |
|--------|----------------|
| **Camera (home)** | Live viewfinder placeholder, top-right flip/flash/save, “Capturing Vibe” pill, shutter bar lifted above nav (`nav/bar-content-height` + `nav/bar-breathing`), `BottomNavBar` Camera active, **no** top-left X |
| **My Blogs** | Gear top-left, scroll: search, Tap to Blog banner, Latest Edits carousel, country sections; bottom: map + search stack above nav; `BottomNavBar` My Blogs active |
| **My Places** | Gear top-left, list + filters; `BottomNavBar` My Places active |
| **Settings** | Sheet from gear — `SettingsView` |
| **Splash** | Gradient `background/app` → `background/app-gradient-end`, logo 200, title 34 |

Reference spec: `docs/superpowers/specs/2026-05-28-camera-landing-nav-redesign.md`

Import brainstorm HTML screenshots into **Archive** only; rebuild screens with variables in **Screens**.

---

## 6. Patterns page

### Navigation model (diagram)

```
[Camera base layer — always mounted]
     ↓ overlay
[My Blogs | My Places] — ZStack, bottom nav dismisses overlay
```

- Camera = home; no dismiss X on camera
- Settings = sheet from My Blogs / My Places only

### Dark-first

- Default canvas `background/app`
- Light mode column: system grouped backgrounds, never hardcoded white page BG

### Photo overlays

- Caption scrim: `effect/photo-scrim`
- Controls on photos: prefer `effect/material-ultrathin`

---

## 7. Resources page

### Icons (export @1x @2x @3x from assets)

| Asset | Figma note |
|-------|------------|
| `MyBlogsIcon` | Nav |
| `MyPlacesIcon` | Nav |
| `SplashIcon` | Brand |
| `AppIconMark` | Brand |
| `ScanIcon` | Legacy scan (TripsView) |
| `InstagramIcon`, `TikTokIcon` | Share |
| `PDFLogo`, `PDFLinkIcon` | Export |

### Changelog frame (template)

```
v1.0 — 2026-05-28
- Initial kit
- Camera home + BottomNavBar + Settings gear

v1.1 — (date)
- ...
```

### Engineering links (text block)

- Colors: `.ai/skills/ui/colors/palette.md`
- Components: `.ai/skills/ui/components.md`
- Gradients: `.ai/skills/ui/colors/gradients.md`
- Animations: `.ai/skills/ui/animations.md`

---

## 8. Publish & team access

1. **Local variables** → attach to all components
2. **Publish library** — `Bloggo Design Kit`
3. **Share**
   - Designers: **Edit**
   - Engineering: **View** + Dev Mode
   - Clients / PM: **View** + comment
4. **Consumption** — feature files use published library; don’t detach components
5. **PDF** — export `Start here` + `Brand` + `Screens` → `docs/design-kit/exports/` each release

### Governance

| Event | Action |
|-------|--------|
| New UI in app | Update Figma component/screen + changelog |
| Token change | Update Figma variables + `.ai/skills/ui/` in same PR |
| Client review | Share view link to **Screens** only |

---

## 9. v1 build checklist

- [ ] File created with 8 pages
- [ ] Color + Layout variable collections
- [ ] Text styles (SF Pro scale)
- [ ] Brand: icon, splash, voice, do/don’t
- [ ] Components: BottomNavBar, Tap to Blog, PlaceCard variants, gear button
- [ ] Screens: Camera, My Blogs, My Places, Settings, Splash
- [ ] Patterns: navigation diagram + dark-first note
- [ ] Resources: icons + changelog + eng links
- [ ] Library published; URL in README.md
- [ ] View-only link tested with one non-designer

---

## 10. Optional: Dev Mode ↔ Swift

In component descriptions, use consistent IDs:

```
background.app → OnboardingConstants.Colors.background
action.primary → #007AFF / .blue
nav.barHeight → 62pt (BottomNavBar spec)
```

When tokens move into a shared `DesignTokens.swift` later, keep Figma variable names unchanged.
