# Travel DNA vs. Blog Highlights — Meeting Briefing

**For:** Yoobin + Janghyun
**Meeting:** 2026-07-08
**Purpose:** This is a discussion briefing, not a decision doc. It captures where we landed in prep discussion and lists what's still open to resolve live. Goal is a productive meeting, not a settled spec.

## Why this meeting

Prior brainstorming (Travel DNA demo + Blog Highlights discussion) surfaced two features that were getting conflated: an on-device foundation-model demo that classifies trip photos into activity/mood categories to build a personality-style "Travel DNA," and a separate idea for a Spotify-Wrapped-style recap shown right after a blog is created. Both matter, but they serve different jobs and were at risk of becoming one muddled feature. This meeting is to nail down the split and get concrete about what's actually feasible to build first.

## Definitions we've landed on

| | Travel DNA | Blog Highlights |
|---|---|---|
| Scope | Cross-trip, cumulative — builds up across all of a user's blogs | Per-trip — generated once per blog |
| Purpose | Personality/identity: "what kind of traveler are you" | Recap/celebration: "here's what this trip was" |
| Trigger | Recomputed in the background as new blogs are added | Immediately after scan completes — no user action needed |
| Taxonomy | Activity (major/sub, e.g. sports → surfing) **+ Mood** (chill vibes, cozy corner, vibrant scene) folded in, so archetypes can read "chill nature logger," not just "nature logger" | Not category-driven — mostly stats, top photos, and narrative already generated per trip |
| Generation method | New on-device classification of photos/captions into Activity+Mood — mirrors Janghyun's demo | Template-based stat sentences + top-photo picks + existing narrative generation — deterministic, near-zero hallucination risk |
| Shareable | Yes — social, MBTI-style compare-with-friends (per earlier notes) | Open question — see below |
| Explicitly deferred | Contextual, Experience/Moment, Time/Season, Feature/Amenity tag groups from the old tag taxonomy doc are **not** part of DNA. They're a different job (per-place search/filter tags) and go into a separate future feature. | — |

**Why Activity+Mood and not the full 6-group taxonomy:** the other four groups (Contextual, Experience, Time, Feature) are mostly per-place descriptive/filter tags, not identity-forming, and several aren't feasible yet anyway — "Popular / Recommended by friends" needs a social graph we don't have, "Wheelchair Accessible" isn't visible in a photo and is risky to hallucinate. Activity+Mood is what's actually validated on-device today and is what makes a personality archetype feel like *personality* rather than a filter chip.

## What already exists in code (don't rebuild this)

- **`PlaceCategoryID`** (`Services/StoryCaptionGenerator.swift`) — 20-case category enum, deterministically derived from `MKPOICategory` + place name. Free, already computed on every `PlaceStop`. Usable as a bootstrap signal for Activity, though it's coarser than true major/subcategory.
- **`PhotoQualityScorer`** — aesthetic/sharpness scoring per photo, already drives `autoSelectedIds()` and `aiRanksByPhotoId()` (top 3 photos per place). Highlight "best photo" selection is already solved — just needs surfacing in a Highlights UI.
- **`LocalLLMStoryCaptionGenerator` / `StoryCaptionService`** — on-device Apple Intelligence (iOS 26+) generates photo captions, place/day/trip narratives. Template fallback exists for captions when the model is unavailable; `tripNarrative` is currently LLM-only (nil if unavailable — worth discussing whether Highlights needs a template fallback here too).
- **Data model already has the raw material for stats:** `PlaceStop.representativeLocation` and `RecapPhoto.location` (both `PhotoCoordinate`), `RecapPhoto.timestamp` / `digitizedTime`, `isFavorite`, `sentiment`, `qualityScore`, and `RecapBlogDay.weather`. None of this requires new AI to turn into Highlights content — it's arithmetic over fields that already exist.

## What's genuinely new work

- **Activity+Mood classifier** — `PhotoTagService` only gives generic Vision tags ("outdoor", "sky", "water"), not the rich major/subcategory classification Janghyun demoed. That classifier needs to be built (or the demo's approach ported in).
- **DNA aggregation & storage** — nothing persists a cross-trip rollup today. Needs a store for accumulated Activity/Mood weights per user, plus a decision on update cadence (see open questions).
- **Highlights UI** — no highlights screen/card exists. `MyStatsView` is a plain count grid; `ProfileMapViewModel.countrySummaries` aggregates by country only, not category or stats.

## Data flow sketch

```
Raw inputs
  photos + EXIF, MKPOICategory, user captions/edits, weather
        │
        ▼
Extracted signals (mostly already computed)
  PlaceCategoryID · PhotoCoordinate · timestamps · qualityScore
  on-device captions/narratives · [NEW] Activity+Mood classification
        │
        ├──────────────► Blog Highlights (per-trip, immediate)
        │                 template stats + top photos + existing narrative
        │
        └──────────────► Travel DNA (cross-trip, cumulative, background)
                          Activity+Mood rollup → archetype
```

## Blog Highlights: fun facts generatable purely from trip metadata

These are the "meaningless alone, interesting together" numbers — Spotify Wrapped's core trick. All are template sentences with a number/place-name slotted in, not free-form generation, so they sidestep the hallucination concern the team raised earlier.

**Pace & scale**
- "5 days, 14 places, 210 photos — 38 made the cut" (day/place/photo counts vs. `isIncluded` survivors)
- Busiest day: most `placeStops` or most photos in one day
- Most photographed place: `PlaceStop` with the most included `RecapPhoto`s

**Time & rhythm** (from `timestamp` / `digitizedTime` + `timeZoneIdentifier`)
- Early bird vs. night owl: dominant daypart across photo timestamps
- Golden hour count: % of top-quality photos shot near local sunrise/sunset
- Longest stop: biggest gap between first/last photo timestamp at one place

**Distance & geography** (from `PhotoCoordinate` on `PlaceStop` / `RecapPhoto`)
- Total ground covered: sum of distance between consecutive places
- Furthest point from home — check whether `TripDistanceFromHomeOnboardingView`'s distance logic is reusable here
- Bookends: first place vs. last place of the trip

**Vibe / category mix** (from `placeCategory` → `PlaceCategoryID`)
- Dominant category as a fun label: "40% of your stops were cafés — basically a coffee tour"
- Contrast framing: sharp category shifts day to day ("beach one day, mountains the next")

**Photography behavior** (from `isFavorite`, `qualityScore`, `sentiment`)
- Favorite count: photos the user explicitly starred
- Top 3 shots: already computed via `aiRanksByPhotoId()`, just needs surfacing
- Weather variety, if `DayWeather` is populated: "you caught the only sunny day of the trip"

Rough feasibility ordering: **Pace & scale** and **Photography behavior** are safest/fastest (pure counts over existing fields). **Time & rhythm** and **Distance** need light new computation but no new AI. **Vibe/category mix** is the most interpretive and worth scrutiny for whether the framing ever reads wrong (e.g. "coffee tour" landing as flat instead of fun).

## Open questions for tomorrow's meeting

1. **DNA archetype list & naming** — what are the actual archetypes (e.g. "cafe lover," "nature logger")? Who owns curating the name list — a fixed taxonomy or algorithmically generated from top Activity+Mood pairs?
2. **DNA update cadence** — recompute on every new blog, or batched periodically? Does the user see it change, or only a periodic "refreshed" moment (Wrapped-style reveal)?
3. **Sharing & privacy scope** — is DNA sharing opt-in per-user, and what's shown to others (full breakdown vs. just the archetype)? Ties to the company's no-social-comparison-mechanics stance — needs care so it doesn't become a leaderboard.
4. **Highlights content set** — which of the fun-facts categories above actually ship in v1? Recommend starting with Pace & Scale + Photography behavior since they need zero new AI.
5. **Hallucination guardrails** — for the more interpretive categories (vibe/category mix, contrast framing), do we need a review/tone pass, or is template-only generation strict enough to trust as-is?
6. **`tripNarrative` fallback** — it's currently LLM-only (nil if Apple Intelligence unavailable). Does Highlights need this to degrade gracefully on older devices, and if so, does that mean extending the template fallback that captions already have?
7. **Deferred tag groups roadmap** — do we want to timebox when the Contextual/Experience/Time/Feature place-tags feature gets picked up, or leave it fully unscheduled for now?

## Parked for later (not in scope for this meeting)

The original 6-group tag taxonomy doc (Contextual, Mood*, Experience/Moment, Time/Season, Feature/Amenity, Activity) — *Mood is now folded into DNA per above, the rest stay parked — was designed for per-place search/filter tags (2 shown on frontend, top 10 stored per place, NLP-merged). That's a legitimate future feature but a different one from DNA/Highlights and isn't being scoped today.
