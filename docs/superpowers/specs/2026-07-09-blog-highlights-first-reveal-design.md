# Blog Highlights — First-Time Reveal Experience

**Date:** 2026-07-09
**Status:** Approved
**Scope:** `fastblog/Views/RecapBlogPageView.swift` only — additive, view-layer

## Context

The Highlights presentation style (uncommitted work in `RecapBlogPageView.swift`) gives a blog a cinematic hero opening — auto-rotating top-5 highlight slides, metric pills, and a "Trip Intelligence" grid of locally computed insight cards topped by a Travel DNA badge. Today everything appears instantly.

This feature adds a staged, once-per-blog reveal: the first time a blog opens in Highlights style, the hero builds itself in front of the user and the intelligence cards cascade in when scrolled into view. It is the first piece of the Travel DNA experience (Priority 1). Insight computation stays local for now; when Jangyoung's context-extraction data lands, the same reveal re-fires against richer data by removing the blog's seen flag.

Deliberately deferred: extracting insight computation out of the view into a provider boundary. That happens once the real payload shape is known, so the boundary isn't designed against an unknown contract.

## Reveal choreography

### Hero sequence (~2.4s, never blocks interaction)

| t (s) | Element | Animation |
|-------|---------|-----------|
| 0.0 | Hero photo | Fade in `.easeIn(0.5)`; scale settles 1.06 → 1.0 (Ken Burns landing) |
| 0.5 | "Blog Highlights" capsule + date | `.easeInOut(0.3)` fade |
| 0.7 | Title | Slide up 14pt + fade, `.spring(response: 0.4, dampingFraction: 0.75)` |
| 0.95 | Opening line | `.easeInOut(0.3)` fade |
| 1.2 | Metric pills | Staggered 90ms entries; numbers count up 0 → N over 0.7s with monospaced digits |
| 1.9 | Slide strip | Slide up from bottom + fade, spring |
| 2.4 | Done | Mark blog seen; hero slide auto-rotation begins (gated on reveal completion — currently starts immediately) |

Driven by one stepped `@State` reveal stage advanced by a single sequencing `Task` using `withAnimation` + `Task.sleep` (project convention). Each hero element compares its stage index to derive opacity/offset/scale.

### Intelligence cascade (scroll-triggered, same first open)

- A new `HighlightsIntelligenceMinYPreferenceKey` (pattern: existing `TitleMinYPreferenceKey`) reports the section's top edge in the existing `"scroll"` coordinate space.
- When the top crosses 82% of screen height and the cascade hasn't fired: section header fades in, fact cards cascade with 80ms stagger (slide up 12pt + spring each), and the Travel DNA badge fires **last** with a scale 0.6 → 1.05 → 1.0 spring pop.
- Implemented as one boolean flip with per-card `.delay(i * 0.08)` animations bound to that value.
- Hero and cascade are independent — scrolling down fast fires the cascade without waiting for the hero.

## State & persistence

- `@AppStorage("bloggo.highlightsRevealSeen")` — comma-joined blog UUID strings, capped at the most recent 120 entries.
- Marked seen when the **hero sequence completes**. An interrupted reveal replays on next open (harmless at 2.4s).
- Cascade eligibility is captured once per session when the blog opens, so a user who watched the hero but hasn't scrolled yet still gets the cascade later that session even though the flag is already persisted.
- Re-firing the reveal after a data upgrade (Jangyoung) = removing the blog's ID from the seen list.

## Trigger conditions

The sequence plays only when all hold:

1. Highlights style active (`isHighlightsStyleEnabled`)
2. Not in edit mode
3. Day index 0 is the visible page
4. Blog ID not in the seen list
5. Not exporting PDF, not in story mode, no pending deep-link-to-stop

Toggling Classic → Highlights on an unseen blog also triggers the reveal.

## Interruptions & accessibility

- **Edit mode entered mid-sequence:** cancel the sequencing task; snap every element to final state.
- **PDF export / story mode / deep link:** start in the done state — no reveal.
- **Day swipe mid-sequence:** sequence completes silently off-screen; nothing visible breaks.
- **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): same timestamps, opacity fades only — no springs, slides, scale, or count-up; numbers appear final.

## Existing blogs

Every already-created blog reveals once on its first Highlights open. Intentional — this is the marquee moment.

## Scope guard

- Classic style untouched.
- No model or service changes; no new files (no pbxproj edits).
- All new code in a `// MARK: - Highlights Reveal` section of `RecapBlogPageView.swift` (~180 lines), written so a later extraction into a `BlogHighlights` module is mechanical.

## Verification

1. `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build` passes.
2. Simulator walkthrough: fresh blog open (full sequence), reopen (instant), Classic → Highlights toggle on unseen blog, edit-mode interruption mid-sequence, Reduce Motion enabled.
