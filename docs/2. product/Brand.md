# Bloggo Brand Guide

**Audience:** AI assistants, designers, interns — anyone making visual or design decisions.

---

## 1. Brand Identity

Bloggo is cinematic, private, effortless, and travel-native. The emotional experience the app should evoke: *your memories, beautifully preserved.*

Bloggo is not a social media app. There are no feeds, no follower counts, no performance anxiety. It is a private space for the user's own travel life — premium in feel but accessible to any traveler, not exclusive or aspirational in a way that creates pressure.

The design should always make users feel like the app is doing the work for them. The interface recedes; the memories step forward.

---

## 2. Design Philosophy

**Dark-first.** The primary canvas is deep navy `#050A30`, not black. Navy feels warmer and more cinematic than pure black. Light mode uses system adaptive colors throughout.

**Cinematic.** Gradients over flat fills. Photography is the hero at all times. UI elements are supporting cast — they should never compete with the user's photos for attention.

**Travel-native.** Color themes respond to destination. A blog about Iceland looks different from one about Morocco. The visual system adapts to make every blog feel like it belongs to its place.

**Effortless.** The UI should feel like the app is doing the heavy lifting. Interactions should feel smooth and anticipatory, not mechanical.

---

## 3. Color System

### App UI

| Role | Value |
|---|---|
| Primary background | `#050A30` (deep navy) |
| Brand accent text | `#C8EBFF` (light blue) |
| Primary action | `#007AFF` |
| Active filter / selected state | `#0B84FF` |
| Destructive | `#FF4539` |
| Success | `#A6F2B7` |
| Dark card surface | `#242424` |
| Dark narrative card surface | `#191919` |

### Text Hierarchy on Dark

| Level | Value |
|---|---|
| Primary | white (`1.0`) |
| Secondary | white `0.92` |
| Tertiary | white `0.7` |
| Quaternary / disabled | white `0.5` |

### Light Mode

Always use system adaptive colors. Never hardcode a light-mode background color.

### Export

| Role | Value |
|---|---|
| PDF header accent | `#2E62E0` |

### Overlay / Scrim Scale

| Use | Opacity |
|---|---|
| Subtle color tint | `0.15` |
| Card overlay | `0.35` |
| Photo scrim (text readability) | `0.65` |

The canonical Swift source for all color values is `.ai/skills/ui/colors/palette.md`. Brand.md explains the *intent*; the skill file has the *code*.

---

## 4. Gradients

**Photo text scrim:** black `0.65` → clear, bottom to center. Used whenever text appears over a photo to ensure readability without hiding the image.

**Cover page fallback:** `#1a1a2e` → `#2d3561`, top to bottom. Used when no cover photo is available.

**Regional trip card themes.** Each region has a gradient that evokes the destination before the user even opens the blog:

| Region | Intent |
|---|---|
| Iceland | Cold blues and teals |
| Morocco | Warm reds and amber |
| Tokyo | Electric magentas and purples |
| Paris | Dusty rose and gold |
| California | Warm sunset oranges |
| Alps | Ice blue and white |
| Barcelona | Terracotta and saffron |
| London | Steel grey and muted gold |

**Photo placeholders.** 10 variants (Sunset, Ocean, Forest, Mountain, Golden Hour, Aurora, Beach, City/Dusk, Meadow, Lake), selected by `index % 10`. Used when a photo hasn't loaded or isn't available.

**Neon glow (Nearby Share).** 6 rotating colors — purple, bright blue, cyan, pink, violet, light blue.

Canonical gradient code lives in `.ai/skills/ui/colors/gradients.md`.

---

## 5. Materials & Surfaces

- `.ultraThinMaterial` — frosted-glass controls, toolbars, overlays
- `Color.white.opacity(0.12)` — hairline dividers on dark surfaces
- `Color.black.opacity(0.08)` — hairline dividers on light surfaces
- Full-screen dark: `#050A30`
- Cards on dark: `#242424`
- Nested cards: `#191919`

---

## 6. Export Aesthetics

Exports (PDF, StoryBook) should feel like premium publications, not screenshots of the app.

**Light mode:**
- Background: white
- Primary text: black
- Secondary text: dark gray
- Card surface: `UIColor(white: 0.92)`

**Dark mode:**
- Background: black
- Primary text: white
- Secondary text: `UIColor(white: 0.72)`
- Card surface: `UIColor(white: 0.14)`

The PDF header accent (`#2E62E0`) is the only place a brighter blue appears in exports.

---

## 7. Design Rules

Things Bloggo never does:

- Never hardcode a light-mode background — always use system adaptive colors
- Never use pure black (`#000000`) as the app background — use `#050A30`
- Never flatten gradients to solid fills as a performance shortcut
- Never use follower counts, star ratings, or numeric rankings as UI elements
- Never add social pressure mechanics (likes, view counts) to the UI
