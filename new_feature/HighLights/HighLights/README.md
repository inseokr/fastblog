# BloggoDemo v4 — real photos · Instagram-style highlight · captions · on-device RAG

All code comments and in-app strings are in **English**.

## Screens (4 tabs)

**Blog**
- Hero = a swipeable Instagram-style highlight carousel (Variant B): full-bleed photos you swipe
  through, with a pinned title / date / stats / Trip-DNA badge and a **Share to Instagram** button
  (opens a preview sheet; actual sharing is intentionally not wired up).
- Each slide shows meaningful blogging info: place name, time, and a mood chip (golden hour / daypart).
- Below the hero, **Day 1 / 2 / 3 …** sections each list that day's photos with place · time · mood ·
  AI caption, plus that day's GPS route on a mini map.
- Then Trip Data Report and Hidden Moments.

**Trip DNA**
- Persona breakdown (Café Explorer, Nature Lover, …) with percent bars, built from photo captions.
- **Tap any category → a grid of the photos in that category.**

**Search**
- Type (or tap a chip) → shows the **photos whose caption contains the term**, with captions.

**RAG** — the on-device RAG OFF/ON A/B comparison (caption place-name grounding, day draft, search).

## Which caption path is used?

`CaptionService.baseCaption` selects the path from *Untitled Project 3*:
- Default (today's SDK): **② `improvedCaption`** — Vision tags + iOS 26 text LLM (template fallback).
- With `ENABLE_IOS27_MULTIMODAL` defined: **④ `mapRichCaption`** — raw lat/long → Apple Maps →
  image+text multimodal. Falls back to ② automatically if it returns empty.
- The RAG-ON side then adds place-name grounding + evidence sentences on top of whichever base ran.
  The card footer shows which base path produced each caption.

## Run

1. Xcode → New iOS App (SwiftUI), Product Name `BloggoDemo`, Deployment Target **iOS 18**.
2. Delete the auto-generated `BloggoDemoApp.swift` / `ContentView.swift`.
3. Drag in the `.swift` files + `UserCode/` (3 files) + `PlaceFacts.json` (skip `MockTrip.swift`).
4. Drag a `TripPhotos` folder of original photos → choose **Create folder references** (blue folder).
   Use original HEIC/JPEG so EXIF (time · GPS) survives.
5. ⌘R.

Notes: FM captions need iOS 26 + Apple Intelligence; otherwise the template fallback keeps every
comparison valid. `PlaceFacts.json` must be in Copy Bundle Resources (only add verified facts —
missing/absent facts are omitted by the ③-b hard rule). iOS 27 `SpotlightSearchTool` /
`mapRich` / `PCC` paths stay behind their flags (`ENABLE_IOS27_RAG`, `ENABLE_IOS27_MULTIMODAL`,
`ENABLE_PCC`) — beta symbols, confirm via Xcode 27 autocomplete before enabling.
