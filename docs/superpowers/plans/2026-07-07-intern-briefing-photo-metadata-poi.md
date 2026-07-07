# Monday Briefing — Intern Kickoff
**July 7, 2026 · Week 1 of 4**
*Photo Metadata + POI Naming · Bloggo iOS*

---

## Part 1 — Project Context

### What Bloggo Is
Bloggo is an AI-powered travel journal iOS app (live on the App Store as "Bloggo: Journal & Diary" in Photo & Video). It auto-generates beautiful blogs from camera roll photos, organized by day and place. Two core modes: **Trip Blogs** (multi-day travel) and **My Places** (everyday moments near home).

**The mission:** "Home for your travel life" — the app you open before, during, and after every trip.

**Who uses it:** Everyday travelers — not influencers. People with camera rolls full of trip photos they never organize. The core pain: organizing after a trip feels like homework, and the details are forgotten within weeks.

**Current state:** Stable v1.x, live and shipping. Real users. Any data model change the interns make will affect existing saved blogs — handle with care.

### Privacy — Hard Rule
Bloggo's core promise: **photo content never leaves the device.** This is non-negotiable and shapes every technical decision:
- Vision processing: on-device only ✓
- Apple Intelligence (`FoundationModels`): on-device only ✓
- MapKit searches: GPS coordinates only, never images ✓
- No Google Vision, no AWS Rekognition, no third-party image APIs

### Architecture — Quick Map
MVVM, strict layering: **View → ViewModel → Service → Model**

Key patterns the interns will use:
- New services go in `fastblog/Services/` as Swift `actor` singletons (`static let shared`)
- Models are plain `struct`s with `Identifiable, Codable, Equatable, Hashable`
- Background async work uses `Task { }` with `guard !Task.isCancelled` in loops
- All `@Published` updates must be on `@MainActor`
- Concurrency cap pattern: see `PhotoQualityScorer.swift` — max 6 concurrent workers to avoid XPC flakes

Key files to read on Day 1:
- `PhotoTagService.swift` — existing tag extraction (the starting point for Track A)
- `PhotoQualityScorer.swift` — the background pipeline pattern to copy
- `GeocodingService.swift` — existing place name resolution (the starting point for Track B)
- `RecapBlogDetail.swift` — `PlaceStop` and `RecapPhoto` data models (where new fields will go)
- `LocalLLMStoryCaptionGenerator.swift` — how Apple Intelligence is already used

---

## Part 2 — The Feature Work

### The Vision (Share This with Both Interns)

Every photo saved in Bloggo should silently carry a rich metadata layer — scene tags, recognized text, place context — that makes the app smarter without the user lifting a finger. We're calling this **Memory DNA**: structured signals attached to each moment that power place naming accuracy today, and will unlock search, itinerary suggestions, and recall features in the future.

**Why this matters now:** Bloggo's place names currently come from reverse geocoding alone (GPS → neighborhood/city). It can't distinguish "a café in SoHo" from "a hotel in SoHo." Apple Intelligence and Vision give us the tools to do better — entirely on-device.

### The Two Tracks (and How They Connect)

**Track A — Photo Metadata Extraction** (Intern 1)
Extract and persist a structured metadata set for each photo using on-device Vision + Apple Intelligence.

| Signal | API | Why it matters |
|---|---|---|
| Scene labels | `VNClassifyImageRequest` (already exists in `PhotoTagService`) | "beach", "restaurant", "museum" |
| OCR text | `VNRecognizeTextRequest` | Reads storefront signs → venue name hints |
| Face/people count | `VNDetectFaceRectanglesRequest` | Social vs. solo context |
| AI description | `FoundationModels` (iOS 26+) | Free-text scene understanding |

Stretch goal: video keyframe extraction via `VNVideoProcessor` (iOS 14+).

**Track B — POI Name Resolution** (Intern 2)
Use metadata from Track A + GPS + MapKit to auto-suggest the best place name for each `PlaceStop`.

Confidence ladder (highest to lowest):
1. OCR text matches a nearby MapKit POI → venue name confirmed
2. Scene tags point to a category, MapKit has a matching POI nearby → medium confidence
3. GPS only → current behavior (neighborhood/city fallback)

**The shared dependency:** Both tracks need `RecapPhoto` to have a `tags` field (and likely `recognizedText`). This is the critical alignment item for Week 1. No production code until this is agreed.

### Processing Flow

```
Blog created
  ↓
[Background task — ~30–70 seconds, non-blocking]
  ↓
Phase 1 (per photo, 6 concurrent workers):
  VNClassifyImageRequest → scene labels
  VNRecognizeTextRequest → OCR text
  → Persist to RecapPhoto.tags + RecapPhoto.recognizedText
  ↓
Phase 2 (per place stop, after Phase 1):
  Aggregate tags + OCR from all photos in stop
  Apple Intelligence → scene understanding
  MapKit POI lookup with context
  → Update PlaceStop.placeTitle if confidence high + not manually edited
```

Key guard: never overwrite `placeTitle` when `placeTitleIsManual == true` (already exists in `PlaceStop`).

---

## Part 2b — iOS Version Compatibility & Performance

This is not a footnote — it shapes the architecture. Bloggo targets iOS 18+ as the minimum. Apple Intelligence (`FoundationModels`) is iOS 26+ only. The pipeline must produce a useful result on iOS 18 and a richer result on iOS 26+, with no code paths that crash or hang on older OS.

### API Availability Matrix

| Signal | API | Min iOS | Notes |
|---|---|---|---|
| Scene labels | `VNClassifyImageRequest` | iOS 14 | Available on both, fast |
| OCR text | `VNRecognizeTextRequest` | iOS 13 | Available on both, fast |
| Face count | `VNDetectFaceRectanglesRequest` | iOS 9 | Available on both, fast |
| Aesthetics score | `VNCalculateImageAestheticsScoresRequest` | iOS 18 | Already guarded in codebase |
| AI description | `FoundationModels` / `SystemLanguageModel` | iOS 26 | Progressive enhancement only |
| Video processing | `VNVideoProcessor` | iOS 14 | Available on both |
| MapKit POI lookup | `MKLocalSearch` | iOS 9 | Available on both |

### What Each OS Version Gets

**iOS 18 (minimum target):**
- Full Vision pipeline: scene labels + OCR text + face count ✓
- MapKit POI resolution using those signals ✓
- No Apple Intelligence descriptions — fallback to a heuristic label derived from the strongest scene tag
- Expected pipeline time: **~15–30 seconds** background for a typical trip

**iOS 26+ (Apple Intelligence):**
- Everything above, plus `FoundationModels` AI description per place stop
- Richer context → higher confidence on ambiguous place names
- Expected pipeline time: **~30–70 seconds** background (AI description adds ~10–40s at the place-stop level)

### Fallback Strategy for iOS 18

When `FoundationModels` is unavailable, Phase 2 of the pipeline falls back to a rule-based description built from the aggregated scene tags:

```
Tags: ["restaurant", "food", "indoor", "people"]
→ Fallback label: "restaurant" (highest-confidence category tag)
→ MapKit search: MKLocalSearch near GPS coords, filtered to .restaurant category
```

This is weaker than an AI description but still meaningfully better than GPS-only. The interns must design Phase 2 so the `FoundationModels` call is additive — removing it should degrade gracefully, not break the flow.

### Performance Testing Requirements (Week 1 Experiment)

**Run the joint experiment twice — once on each simulator:**

| Simulator | What to measure |
|---|---|
| iOS 18 | Time to extract tags + OCR for 10 photos; quality of MapKit results without AI description |
| iOS 26 | Same extraction time + time added by `FoundationModels` per place stop; quality improvement with AI description |

The output table from the experiment should have a column for each OS version so the accuracy and timing differences are visible side by side. This data directly informs the confidence thresholds and architecture decisions going into Week 2.

### Code Pattern to Use (Already in Codebase)

See `PhotoQualityScorer.swift` lines 164–173 for the existing `#available` guard pattern:
```swift
if #available(iOS 18.0, *) {
    return await analyzeAestheticsModern(cgImage)  // modern path
} else {
    return await analyzeAestheticsFallback(cgImage) // graceful fallback
}
```

The same pattern applies to `FoundationModels`:
```swift
#if canImport(FoundationModels)
if #available(iOS 26.0, *) {
    if case .available = SystemLanguageModel.default.availability {
        // use Apple Intelligence
    }
}
#endif
// fallback: rule-based from tags
```

Both interns should understand this pattern before writing any pipeline code.

---

## Part 3 — Week 1 Agenda (Concrete)

Week 1 is not about writing production code. It's about two things:
1. **Prove the approach works** (individual experiments)
2. **Agree on the data model** (joint deliverable)

### Day 1–2 (Mon–Tue): Codebase Orientation
Each intern reads their starting-point files (listed above) and maps the existing flow on paper or a whiteboard. Goal: be able to explain it back to you by Tuesday EOD.

### Day 3–4 (Wed–Thu): Joint Experiment — Same Photo Set, Both Signals

Track B's place name resolution only has real signal when **coordinates and metadata are combined**. Running these as separate isolated experiments misses the point. Instead, both interns work through the same batch of photos together:

**Step 1 — Track A extracts (Wed morning):**
In an Xcode Playground, load 10–15 real photos that have GPS data. Run:
- `VNClassifyImageRequest` → all labels above 0.1 confidence
- `VNRecognizeTextRequest` (`.accurate` level) → all recognized text strings
- Record the GPS coordinate from each photo's EXIF data

Output: a simple table — photo identifier, GPS coordinate, scene labels, OCR text.

**Step 2 — Track B resolves (Wed afternoon, using Step 1's output):**
Take that table. For each photo, attempt place name resolution using **both signals together**:
- GPS coordinate → `MKLocalSearch` in a 200m radius
- OCR text (if any) → narrow the MapKit search to matching venue names
- Scene labels (if any) → filter MapKit results by matching POI category
- Compare the resolved name against what `GeocodingService` currently returns

Expected questions to answer: How often does adding metadata improve the result? When does it make it worse? What's the minimum useful signal — GPS alone, or do you need at least one metadata signal to be confident?

**Goal:** Before any production code exists, prove the combined approach works on real photos. 5 out of 10 correct improvements = green light. Fewer = revisit the ladder design with you.

### Day 5 (Fri): Joint Schema Meeting
Both interns sit together (you join or review async) and answer:
- What exact fields are we adding to `RecapPhoto`? What types?
- What fields (if any) are we adding to `PlaceStop`?
- Are any fields optional? What's the default value for existing saved blogs (must decode gracefully — `decodeIfPresent` with a nil/empty default)?
- Who owns writing the model change — Track A, Track B, or together?

Write it down. You sign off. This becomes the contract both interns build toward in Week 2.

**Week 1 deliverables:**
- [ ] Joint experiment table: 10–15 photos with extracted metadata + GPS + resolved name attempt, **run on both iOS 18 and iOS 26 simulators**
- [ ] Timing comparison: extraction pipeline duration on iOS 18 (Vision only) vs. iOS 26 (Vision + Foundation Models)
- [ ] Accuracy comparison: place name quality on iOS 18 vs. iOS 26 — does Apple Intelligence meaningfully improve results?
- [ ] Agreed schema doc — fields, types, defaults for backward compatibility

---

## Part 4 — Four-Week Milestones

| Week | Track A (Tags) | Track B (POI) | Joint |
|---|---|---|---|
| **1** | Extract tags + OCR from shared photo batch; hand output to Track B | Test place name resolution using Track A's metadata + GPS coordinates | Agree on RecapPhoto/PlaceStop schema; joint experiment on same 10–15 photos |
| **2** | Integrate: add fields to models, wire background extraction pipeline | Integrate: update placeTitle from aggregated signals in background | First end-to-end run on a test blog |
| **3** | Refine: confidence thresholds, handle no-GPS case, Apple Intelligence descriptions | Refine: conflict resolution (Vision vs GPS), accuracy testing on 3 trip types | Review together, identify rough edges |
| **4** | Polish + handoff doc | Polish + handoff doc | Demo to you; define next-sprint work |

---

## Part 5 — What "Done" Looks Like at 4 Weeks

For each intern, the end-of-sprint deliverable is:
1. **Working code** — integrated into the real codebase, not a prototype branch
2. **Accuracy report** — tested on at least 3 real saved blogs; how often does the place name improve?
3. **Handoff doc** — what was built, what edge cases remain, what the next sprint would tackle

The four weeks are enough to prove the concept and ship something that works for a representative case. They are not enough to handle every edge case. Set that expectation early.

---

## Part 6 — Questions to Prepare For

These are likely questions the interns will ask you. Have answers ready.

**"Can I look at real user data for testing?"**
No. Use your own camera roll or the simulator's sample photos. Privacy applies to the development process too.

**"Should we target iOS 26 or iOS 18?"**
Apple Intelligence (`FoundationModels`) requires iOS 26. Vision framework (`VNClassifyImageRequest`, `VNRecognizeTextRequest`) works on iOS 14+. Architecture: always guard Apple Intelligence behind `#available(iOS 26, *)` with a graceful fallback. The metadata pipeline should work on iOS 18+; AI descriptions are a progressive enhancement.

**"What if the place name gets worse after our change?"**
That's exactly what the Week 3 accuracy test catches. The system should only update `placeTitle` when confidence is above a threshold you define together. When in doubt, show the suggestion without auto-applying it.

**"Who owns the MapKit integration — Track A or Track B?"**
Track B. `GeocodingService` is Track B's domain. Track A produces tags, Track B consumes them.

**"What's the right confidence threshold?"**
Start high (70%+) and loosen with data. A wrong auto-filled name is worse than no suggestion — the user already trained themselves to expect to check it.

---

## Part 7 — Questions to Ask Them

### For Track A (Tags):
1. "Walk me through what `VNClassifyImageRequest` returns — what are the identifier strings, and how do you filter noise from the useful ones?"
2. "Where in the codebase would you store the extracted tags? What model change does that require, and does it break existing saved blogs?"
3. "OCR could be huge for place naming — have you looked at `VNRecognizeTextRequest`? What's the difference between `.accurate` and `.fast` levels, and which should we default to?"
4. "Foundation Models — have you checked if it's available on the test device? What does the `SystemLanguageModel.default.availability` check return?"
5. "What does your Week 2 look like? What's the first thing you'd integrate into the real codebase?"

### For Track B (POI):
1. "What does `GeocodingService.bestPlaceLabel` currently do, and where does it break down? Show me a real example from the experiment."
2. "Walk me through `resolvePlaceLabel` — how does it decide if something is a real venue?"
3. "In the experiment, when you combined GPS coordinates with the metadata Track A extracted — what actually moved the needle? Was it OCR, scene tags, or both?"
4. "What does `placeTitleIsManual` mean, and what happens if we ignore it?"
5. "What's your confidence threshold for auto-filling a place name vs. just surfacing a suggestion?"
6. "What happens when there's no OCR text and the scene tags are ambiguous — say, a photo that's just 'outdoor, sky, trees'? GPS alone — do you show a suggestion or stay silent?"

### For both together:
1. "How do your two features hand off to each other? Who produces what, and who consumes it?"
2. "What's the smallest thing you can each show me by end of Week 2 that proves your approach works?"
3. "What's out of scope for four weeks?"
4. "From the experiment — was there a meaningful quality difference between iOS 18 and iOS 26 results? Did the Apple Intelligence description actually change which place name was chosen, or did Vision tags + OCR do most of the work?"
5. "If a user is on iOS 18 and Apple Intelligence isn't available — what exactly do they get? Walk me through the fallback path."

---

## Part 8 — The Bigger Picture (Tell Them This)

The metadata they define and collect will become the input layer for features that don't exist yet:
- **In-app search** ("show me all my restaurant moments in Tokyo")
- **Trip itinerary builder** (auto-suggest a day plan based on past place categories)
- **Memory recall** ("what was that café I loved in Paris?")
- **Smarter cover photo selection** (pick the photo that best represents the place type)

The decisions they make in these four weeks — what to store, how to structure it, what confidence thresholds to use — will shape all of that. That's worth taking seriously. This isn't intern throwaway work; if they do it right, it ships.
