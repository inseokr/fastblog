# UI Skill: Color Palette

## Design philosophy
Dark-first. Primary background is deep navy `#050A30`. Light mode uses iOS system adaptive colors — never hardcode a light-mode background.

## Core colors

| Role | Hex | Swift |
|------|-----|-------|
| App background | `#050A30` | `Color(red: 5/255, green: 10/255, blue: 48/255)` |
| Splash gradient end | `#080E38` | `Color(red: 8/255, green: 14/255, blue: 56/255)` |
| Dark card | `#242424` | `Color(white: 0.14)` |
| Dark narrative card | `#191919` | `Color(white: 0.1)` |
| Primary action | `#007AFF` | `.blue` / `OnboardingConstants.Colors.doneButtonBlue` |
| Active filter | `#0B84FF` | `Color(red: 0.04, green: 0.52, blue: 1.0)` |
| Destructive | `#FF4539` | `Color(red: 1.0, green: 0.27, blue: 0.23)` |
| Success | `#A6F2B7` | `Color(red: 0.65, green: 0.95, blue: 0.72)` |
| Brand accent text | `#C8EBFF` | `Color(red: 200/255, green: 235/255, blue: 255/255)` |

## Light mode surfaces
Use system adaptive colors — never hardcode:
- `Color(uiColor: .systemGroupedBackground)` — primary background
- `Color(uiColor: .secondarySystemGroupedBackground)` — cards
- `Color(uiColor: .tertiarySystemGroupedBackground)` — nested cards

## Text hierarchy
| Level | Dark bg | Light bg |
|-------|---------|----------|
| Primary | `.white` or `.white.opacity(0.92)` | `.primary` |
| Secondary | `.white.opacity(0.7)` | `.secondary` |
| Tertiary / disabled | `.white.opacity(0.5)` | `.secondary` |

## Overlay & scrim opacities
| Purpose | Opacity |
|---------|---------|
| Subtle tint / tag background | `0.15` |
| Border / divider | `0.2` |
| Shadow | `0.3`–`0.35` |
| Loading overlay | `0.45` |
| Dimming scrim | `0.6` |
| Photo text scrim | `0.65` |

## Materials
- `.ultraThinMaterial` — frosted-glass controls and toolbars
- `Color.white.opacity(0.12)` — hairline dividers on dark surfaces
- `Color.black.opacity(0.08)` — hairline dividers on light surfaces

## PDF / StoryBook export (`BlogColor` enum)
| Mode | Background | Primary | Secondary | Card |
|------|-----------|---------|-----------|------|
| Light | `.white` | `.black` | `.darkGray` | `UIColor(white: 0.92)` |
| Dark | `.black` | `.white` | `UIColor(white: 0.72)` | `UIColor(white: 0.14)` |

PDF header accent: `#2E62E0` — `Color(red: 0.18, green: 0.38, blue: 0.88)`

## Hex helper
A `Color(hex:)` initializer exists in `CoverPageView.swift`. Use it, don't redefine it.

## Rules
- Never use `Color.white` / hardcoded RGB for backgrounds that adapt to dark/light — use system colors or the palette above
- New dark surfaces: `Color(white: 0.14)` for cards, `#050A30` for full-screen
- New action buttons: `#007AFF` primary, `.red` / `#FF4539` destructive
