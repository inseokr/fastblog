# Blog Highlights — Wrapped-Style Story

**Date:** 2026-07-10
**Status:** Approved
**Scope:** New `HighlightsStory` view module + targeted `RecapBlogPageView.swift` changes

## Context

The staged first-open hero reveal (spec 2026-07-09, shipped on `Revamp`) animates the blog page itself. This feature adds the marquee layer above it: a Spotify-Wrapped-style, full-screen story that auto-plays when a blog finishes creation — best moments, fun stats, and Travel DNA as a choreographed sequence — then lands on the blog page, where the staged reveal remains the landing moment.

Insight computation stays local (same data the intelligence section uses). When richer context-extraction data lands, pages upgrade in place because all content flows through one builder.

## Entry, replay, persistence

- **Auto-play:** only for newly created blogs. When a blog detail is first built from a trip draft (creation), its ID is appended to `@AppStorage("bloggo.highlightsStoryPending")` (comma-joined UUID strings, capped at the most recent 120). Whenever a blog opens while its ID is pending — and load has finished, and no PDF export / story mode / deep-link-to-stop is active — the story presents after a 600ms settle delay. The ID is removed only when the end card is reached, so an interrupted story replays on next open.
- **Existing blogs never auto-play** (they are not in the pending list). They get the story via the replay button. This intentionally differs from the hero reveal, which fires once for every blog.
- **Replay:** a `sparkles` toolbar button on the blog page re-opens the story anytime (view and edit mode). The share-days-later path.
- **Style-independent:** the story plays regardless of Classic/Highlights presentation style and regardless of edit mode (new blogs open in edit mode; the story plays over it).

## Playback model

Instagram-Stories hybrid:

- Segmented progress bar at top, one segment per page, filling in real time.
- Tap right two-thirds → next page (or next beat within a multi-beat page). Tap left third → previous page.
- Press-and-hold anywhere → pause (progress freezes, particles keep drifting). Release → resume.
- Swipe down → dismiss to blog (not marked watched).
- End card never auto-advances.
- Sequencing lives in one cancel-and-recreate `Task` using `Task.sleep` ticks (project convention). Skipping cancels and restarts the task at the new position.
- No sound. Haptics via `.sensoryFeedback` (iOS 17 SwiftUI API): tick on count-up landings, impact on rank stamps and the DNA pop.

## The pages (~35s + end card)

Shared motion language: each page derives a palette tint from its photo (CoreImage area-average color blended toward the deep navy `#050A30` so text always sits on dark), giant confident type, one idea per page, palette crossfade between pages.

| # | Page | Duration | Choreography |
|---|------|----------|--------------|
| 1 | Title | 5s | Hero photo (existing cover/quality scoring — no new Vision work) slow Ken Burns zoom via Metal `.layerEffect`; palette wash floods in; trip title sets in staggered lines; date range fades under |
| 2 | The numbers | 5s | Days → places → photos count up sequentially in giant monospaced digits, each landing with a haptic tick and a particle micro-burst |
| 3 | Best moments | 9s (3 beats) | #3 → #2 → #1 countdown, one beat each: photo card slides up with spring, rank stamp punches in, place name + one-line stat. #1 beat adds slow zoom + ambient sparks |
| 4 | Fun stat A | 5s | Shooting peak — clock-hour arc sweeps to the peak hour with a personality line |
| 5 | Fun stat B | 5s | First available of: travel span → longest stay → quiet gap — animated line draws between dots / duration dial fills |
| 6 | Travel DNA | 6s | Badge scales 0.6 → 1.05 → 1.0 with confetti burst from the particle layer, DNA name in display type, one-line "why" |
| 7 | End card | manual | Mini recap collage assembles; actions: **Share** and **Open your blog** |

Pages with missing data drop out silently. The story requires ≥2 content pages + end card, otherwise it never triggers and the pending ID is cleared.

## Architecture

Strict MVVM. Six new files (each registered in `project.pbxproj` per project rules) plus one shader file:

| File | Layer | Responsibility |
|------|-------|----------------|
| `fastblog/Models/BlogHighlightsContent.swift` | Model | Plain structs + static `build(from: RecapBlogDetail) -> BlogHighlightsContent`. Extracts the fact / Travel DNA / ranked-moment computation currently private in `RecapBlogPageView` into the shared provider boundary the 2026-07-09 spec anticipated. Returns the ordered page list with all copy resolved |
| `fastblog/ViewModels/HighlightsStoryViewModel.swift` | ViewModel | `@MainActor ObservableObject`. Page index, beat index, per-page progress 0–1, `isPaused`, sequencing `Task`. `onTapForward()`, `onTapBack()`, `onHoldChanged(_:)`, `onDismiss()`. Async palette extraction per photo (ImageLoader + CoreImage average), cached |
| `fastblog/Views/HighlightsStory/HighlightsStoryView.swift` | View | Container: progress segments, tap zones, hold-to-pause, swipe-down dismiss, page switching with palette crossfade |
| `fastblog/Views/HighlightsStory/HighlightsStoryPageViews.swift` | View | The seven page views; motion via `keyframeAnimator` / springs bound to ViewModel beat state |
| `fastblog/Views/HighlightsStory/HighlightsParticleField.swift` | View | Transparent `SpriteView` wrapper, two presets: `confettiBurst(palette:)`, `ambientSparks(palette:)`. The only SpriteKit in the app; absent under Reduce Motion |
| `fastblog/Views/HighlightsStory/HighlightsShareCard.swift` | View | Static 9:16 share-card layouts per page type + `ImageRenderer` export at 1080×1920 |
| `fastblog/Views/HighlightsStory/HighlightsShaders.metal` | Shader | Ken Burns zoom + palette color wash used by `.layerEffect` / `.colorEffect` |

`RecapBlogPageView.swift` changes only: story overlay in its ZStack (same pattern as `showStoryMode`, `.opacity` transition), pending-list trigger check after `hasFinishedInitialLoad`, pending-list append at the creation path (`buildBlogDetailFirstDayOnly` completion), toolbar replay button, and swapping its private intelligence computation to consume `BlogHighlightsContent.build`.

## Sharing

- Persistent share icon in a bottom corner of every page; tapping pauses playback and renders that page's card. End card carries the primary Share button.
- Cards render from the same `BlogHighlightsContent` model as the live pages via `ImageRenderer` — no drift.
- Layouts: photo pages (photo + stat + place), stat pages (big number + line), DNA card (badge + name), recap card. All carry the Bloggo wordmark footer.
- Handed to the existing share-sheet wrapper. No social mechanics beyond the system sheet.

## Edge cases

- **Reduce Motion:** identical pages and timings; opacity crossfades only — no springs, zoom, scale, count-up, or particles; numbers pre-resolved. Haptics stay.
- **Sparse data:** builder drops pages without data (a 5-photo blog gets title → numbers → #1 moment → DNA → end).
- **Interruptions:** app background, edit-mode navigation, PDF export, or deep link mid-story → dismiss cleanly, stay pending, replay next open.
- **Photo load failure:** page falls back to palette gradient background (never a blank frame).

## Deferred (intentional)

- Video export of the sequence (image cards ship first; revisit once share data exists)
- Music/sound
- SocialPostStudio integration for the cards
- Auto-playing the story for pre-existing blogs

## Verification

1. `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build` passes.
2. Simulator walkthrough with the CGEvent automation rig: fresh blog creation (auto-play, full sequence), gestures (tap forward/back, hold, swipe-down), interruption + replay-on-next-open, replay button, share card render, Reduce Motion pass, sparse-data blog.
