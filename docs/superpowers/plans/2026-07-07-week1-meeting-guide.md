# Week 1 Meeting Guide — Photo Metadata & POI
**July 7, 2026 · Intern Kickoff**

---

## Opening (Say This)

> "Welcome. We're starting a four-week sprint that has a real chance of shipping into the app. This isn't throwaway intern work — if you do it right, real users see it.
>
> Week 1 is not about writing production code. It's about two things: proving the approach actually works, and agreeing on the data model before anyone touches the codebase.
>
> By Friday, I want one thing from you together: a table of real photos showing what we can extract and how it improves place names — and a written agreement on what data fields we're adding to the app."

---

## What We're Building — 60 Seconds

Bloggo knows roughly where you were based on GPS. It can tell you "SoHo, Manhattan" — but it can't tell you "Balthazar" or "that museum on the corner."

We're adding a layer that changes that. Every photo you take carries hidden signals: the text on a storefront sign, what the scene looks like, where you were standing. We're going to read those signals on-device — no internet, no third-party services — and use them to figure out the real name of the place.

We're calling it **Memory DNA**: structured signals attached to each moment that make the app smarter without the user doing anything.

---

## The Two Tracks

| | Track A — Photo Metadata | Track B — Place Naming |
|---|---|---|
| **What** | Extract signals from each photo: scene labels, text in the image, how many people, AI description | Use those signals + GPS to identify the real place name |
| **Tools** | Apple Vision framework, Apple Intelligence | MapKit, GeocodingService |
| **Output** | Tags and text stored on each photo | Updated place name on each stop |
| **Depends on** | Nothing — starts from the photo itself | Track A's output + GPS coordinates |

**The connection:** Track A produces signals. Track B consumes them. They need to agree this week on exactly what Track A hands off — because Track B can't build anything until that contract is set.

---

## This Week — What Actually Happens

### Monday–Tuesday: Codebase Orientation

Each intern reads a specific set of files — not the whole codebase, just the parts relevant to their track. The goal is not to understand everything. It's to understand the existing flow well enough to know exactly where new code plugs in, and to spot any assumptions we need to resolve before the experiment.

They are not writing code yet. They are building a map.
z
---

#### Track A — What to Read and What to Find

**Files to read:**
- `PhotoTagService.swift` — the existing tag extraction (this is where Track A's work begins)
- `PhotoQualityScorer.swift` — the background pipeline pattern Track A will copy
- `RecapBlogDetail.swift` — the `RecapPhoto` model (this is where new fields will be added)
- `LocalLLMStoryCaptionGenerator.swift` — how Apple Intelligence is already used in the app

**By Tuesday EOD, Track A should be able to answer:**

1. *What does `PhotoTagService` currently extract — and what's missing?*
The app already extracts some tags. Track A needs to know what those are, what confidence levels they come back at, and what useful signals (OCR text, face count, AI description) aren't being captured yet.

2. *Where exactly would new data live on a photo?*
`RecapPhoto` is the model that represents each photo in a saved blog. Track A should identify the exact place in that file where new fields like `tags` and `recognizedText` would be added — and flag any risk of breaking existing saved blogs when those fields don't exist yet.

3. *How does the background pipeline work in `PhotoQualityScorer`?*
This is the pattern Track A will copy: a background task that runs on many photos concurrently without blocking the user. Track A should be able to describe in plain language what it does — how it starts, how it limits itself to avoid crashing, and how it knows when it's done.

4. *Is Apple Intelligence already being used anywhere — and how?*
`LocalLLMStoryCaptionGenerator` uses Apple Intelligence today. Track A should understand the pattern: how the app checks whether Apple Intelligence is available on the device, what it asks it, and what it does when it's not available.

**Tuesday EOD check-in question for Track A:**
> "Show me where in the codebase your new data lives, and walk me through the existing pipeline you're going to copy. What part of it do you not understand yet?"

---

#### Track B — What to Read and What to Find

**Files to read:**
- `GeocodingService.swift` — the existing place name resolution (Track B's starting point)
- `RecapBlogDetail.swift` — the `PlaceStop` model (where the updated place name lives)

**By Tuesday EOD, Track B should be able to answer:**

1. *What does the current place-naming code actually do?*
Right now, Bloggo takes a GPS coordinate and converts it to a neighborhood or city name. Track B needs to trace that exact flow: what function is called, what it asks Apple's servers, and what it returns. The goal is to understand the current ceiling — what it can and can't distinguish today.

2. *Where does it break down — and what would a real improvement look like?*
Track B should find at least one concrete example (from their own photos or the simulator) where the current result is too vague — "SoHo" instead of a restaurant name, or "Times Square" instead of a specific venue. That example becomes the baseline for the experiment.

3. *What is `placeTitleIsManual` and why does it exist?*
There's a flag on each place stop that tracks whether the user typed the name themselves. Track B needs to understand what it protects: if a user edited a place name, the system must never overwrite it. This is a hard rule, and Track B owns enforcing it.

4. *What does MapKit's local search return — and what does it need as input?*
Track B will be using `MKLocalSearch` to find nearby venues by name and category. Before the experiment, they should know what inputs it accepts (GPS coordinates, search text, category filters) and what comes back. The experiment on Wednesday depends on this being understood.

**Tuesday EOD check-in question for Track B:**
> "Show me the current place-naming flow from start to finish, and give me one real example where it returns something too vague. What would the right answer have been?"

---

#### For Both Interns — One Shared Question by Tuesday

Before the joint experiment on Wednesday, both interns need to agree on one thing: **what does Track A hand to Track B?**

Track A extracts signals. Track B uses them. But what exactly gets passed — a list of text strings? A dictionary of labels with confidence scores? A single best guess? If this isn't agreed before Wednesday morning, the experiment can't run cleanly.

**Joint check-in question for Tuesday EOD:**
> "What exactly does Track A give Track B? Write it down — even roughly. We need that agreed before Wednesday."

---

### Wednesday–Thursday: The Joint Experiment

This is the most important moment of the week. Both interns work through the **same set of 10–15 real photos** together — not in separate silos.

**Wednesday morning (Track A):**
Run the photo analysis on each image and record what comes out: scene labels ("restaurant," "outdoor," "people"), any text visible in the image, GPS coordinates. Write it all into a table.

**Wednesday afternoon (Track B):**
Take that exact table. For each photo, attempt to identify the real place using the GPS coordinate plus whatever Track A found. Compare that result to what the app currently shows.

**The question they're answering:** Does adding photo signals on top of GPS coordinates actually give better place names — and how often?

**Your benchmark:** 5 out of 10 improved results = green light to proceed. Fewer = we revisit the approach together before anyone writes production code.

**Important:** Run this experiment twice — once on iOS 18 and once on iOS 26. Apple Intelligence is only available on iOS 26. We need to know what users on the older version actually get.

---

### Friday: Schema Meeting (You Should Be There)

Both interns sit together and answer these questions in writing:

1. What exact fields are we adding to each photo record? What are their types?
2. What fields (if any) are we adding to each place stop record?
3. What does an existing saved blog see when it loads after the update — does anything break?
4. Who writes the model change — Track A, Track B, or together?

**You sign off on the output.** This document becomes the contract both interns build toward in Week 2. Nothing goes into the production codebase until it's agreed here.

---

## Week 1 Deliverables (The Checklist)

- [ ] Experiment table — 10–15 photos with extracted signals, GPS coordinates, and resolved place name attempts
- [ ] Timing data — how long does the extraction take on iOS 18 vs. iOS 26?
- [ ] Quality comparison — does Apple Intelligence meaningfully improve the results over Vision alone?
- [ ] Agreed schema document — fields, types, defaults, backward compatibility notes
- [ ] Your sign-off on the schema before Week 2 begins

---

## Questions to Engage the Interns

**For Track A:**
- "What does the photo analysis return — can you show me an example output from the experiment?"
- "Did OCR find anything useful in the test photos? Storefront signs, menus, signs?"
- "On iOS 18 with no Apple Intelligence — what do we actually get? Is it still useful?"

**For Track B:**
- "Walk me through a photo where the result improved. What was the GPS showing before, and what does it show now?"
- "Walk me through one that got worse. What happened?"
- "What's your gut on confidence threshold — when do we auto-fill the name vs. just suggest it?"

**For both together:**
- "How do your two pieces hand off? What exactly does Track A give Track B?"
- "What's the smallest thing you can each show me by end of Week 2 that proves this works in the real app?"
- "What's out of scope for four weeks — what are you explicitly not trying to solve?"
- "From the experiment — did Apple Intelligence change anything meaningful, or did Vision tags and OCR do most of the work?"

---

## What Comes After This Week

Here's the arc of what we're building toward, so the team sees the full picture.

### Week 2 — First Integration
Both tracks move from experiments into the real codebase. Track A wires the extraction pipeline to run in the background when a blog is created. Track B starts updating place names from aggregated signals. Goal: one full end-to-end run on a test blog, even if it's rough.

### Week 3 — Accuracy & Edge Cases
Testing on at least 3 real trip types. Refining confidence thresholds so we only auto-fill names when we're actually right. Handling the hard cases: no GPS, ambiguous scene tags, OCR that picks up noise instead of venue names.

### Week 4 — Polish & Handoff
The code is in the codebase, tested, and documented. Each intern produces a handoff doc: what was built, what edge cases remain, what the next sprint would tackle. Final demo to the team.

### After the Sprint — What This Unlocks

The metadata we're collecting this month becomes the foundation for features that don't exist yet:

- **In-app search** — "show me all my restaurant moments in Tokyo"
- **Memory recall** — "what was that café I loved in Paris?"
- **Smarter cover photo selection** — pick the photo that best represents the place
- **Trip itinerary suggestions** — auto-suggest a day plan based on past place categories

The decisions made in these four weeks — what to store, how to structure it, what thresholds to use — shape all of that. That's the real stakes.

---

## Hard Rules to Reinforce (Non-Negotiable)

- **No photo content leaves the device.** All processing happens on-device using Apple frameworks. No Google Vision, no AWS, no external image APIs.
- **Never overwrite a place name the user set manually.** If a user typed the name themselves, our system never touches it.
- **When in doubt, do less.** A wrong auto-filled name is worse than no suggestion. Show a suggestion; don't auto-apply if confidence is uncertain.
- **No production code before the schema is agreed.** Week 1 is experiments and alignment. Week 2 is integration.

---

## Closing (Say This)

> "The four weeks are enough to prove the concept and ship something real. They are not enough to handle every edge case — and that's okay. Set that expectation with yourselves now.
>
> What I care about this week: the experiment table by Thursday, and the schema signed off by Friday. Everything else is in service of those two things.
>
> Questions before we start?"

---

## Jira Epic & Tickets

### What an Epic Is

An Epic is the container. Everything this sprint produces lives inside it. Individual tickets are the discrete pieces of work — one per person, per task, per deliverable. When all the tickets close, the Epic closes.

---

### The Epic

| Field | Value |
|---|---|
| **Type** | Epic |
| **Summary** | Memory DNA — Photo Metadata & POI Name Resolution |
| **Label** | `memory-dna` `intern-sprint` `ios` |
| **Priority** | Medium |
| **Target dates** | July 7 – August 1, 2026 |
| **Description** | Four-week intern sprint to extract on-device photo signals (scene labels, OCR text, face count, AI descriptions) and use them to improve place name accuracy in Bloggo. All processing is on-device only. No photo content leaves the device. Week 1: experiments + agreed data schema. Weeks 2–4: integration, accuracy testing, and handoff. |

---

### Week 1 Tickets

Each ticket below is a child of the Epic above. Create them in order — the joint tickets depend on the track tickets being done first.

---

#### TRACK A — Photo Metadata (Jangyoung)

---

**Ticket A-1**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Track A] Codebase orientation — map the existing photo analysis pipeline |
| **Assignee** | Jangyoung |
| **Priority** | High |
| **Due** | July 8, 2026 (Tuesday EOD) |
| **Description** | Read and map four files: `PhotoTagService.swift`, `PhotoQualityScorer.swift`, `RecapBlogDetail.swift`, `LocalLLMStoryCaptionGenerator.swift`. Produce a plain-language written summary of: (1) what the existing tag extraction does and what's missing, (2) where new fields like `tags` and `recognizedText` would be added on `RecapPhoto`, (3) how the background pipeline in `PhotoQualityScorer` works, (4) how Apple Intelligence is already used and what the fallback looks like on iOS 18. No code written. Output is a written summary, shared with Track B before Wednesday. |
| **Acceptance criteria** | Can demonstrate all four answers verbally in a Tuesday EOD check-in. Written summary shared with Track B. |

---

**Ticket A-2**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Track A] Run photo extraction experiment — 10–15 photos, iOS 18 + iOS 26 |
| **Assignee** | Jangyoung |
| **Priority** | High |
| **Due** | July 9, 2026 (Wednesday EOD) |
| **Description** | Using an Xcode Playground, load 10–15 real photos that have GPS data. For each photo, run: `VNClassifyImageRequest` (scene labels above 0.1 confidence), `VNRecognizeTextRequest` at `.accurate` level (all recognized text strings), `VNDetectFaceRectanglesRequest` (face count). Record GPS coordinate from each photo's EXIF data. Output: a table with columns — photo ID, GPS coordinate, scene labels, OCR text, face count. Run once on iOS 18 simulator and once on iOS 26 simulator. Record timing for each run. Hand the completed table to Track B by Wednesday midday so Track B can begin place resolution in the afternoon. |
| **Acceptance criteria** | Table complete with all signals for 10–15 photos. Timing recorded for both simulators. Delivered to Track B by Wednesday midday. |

---

**Ticket A-3**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Track A] iOS 26 — add Apple Intelligence description to experiment output |
| **Assignee** | Jangyoung |
| **Priority** | Medium |
| **Due** | July 10, 2026 (Thursday EOD) |
| **Description** | On the iOS 26 simulator only: add a `FoundationModels` AI description column to the experiment table from A-2. For each place stop (group of photos at the same GPS cluster), generate a free-text scene description using `SystemLanguageModel`. Record: (1) whether Apple Intelligence was available on the simulator, (2) the description it produced for each stop, (3) the additional time added per stop vs. the iOS 18 Vision-only run. This column feeds directly into the joint accuracy comparison on Thursday. |
| **Acceptance criteria** | AI description column added to the shared experiment table. Timing delta vs. iOS 18 recorded per stop. |

---

#### TRACK B — POI Name Resolution (Woohyuk)

---

**Ticket B-1**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Track B] Codebase orientation — map the existing place naming flow |
| **Assignee** | Woohyuk |
| **Priority** | High |
| **Due** | July 8, 2026 (Tuesday EOD) |
| **Description** | Read and map two files: `GeocodingService.swift` and `RecapBlogDetail.swift`. Produce a plain-language written summary of: (1) the complete flow from GPS coordinate to place name — every function involved, (2) one concrete real-world example where the result is too vague (e.g. "SoHo" instead of a restaurant name), (3) what `placeTitleIsManual` does and why it must never be overwritten, (4) what inputs `MKLocalSearch` accepts and what it returns. No code written. Output is a written summary shared with Track A before Wednesday. |
| **Acceptance criteria** | Can demonstrate all four answers verbally in a Tuesday EOD check-in, with a real example of where current naming falls short. Written summary shared with Track A. |

---

**Ticket B-2**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Track B] Run place name resolution experiment using Track A's metadata output |
| **Assignee** | Woohyuk |
| **Priority** | High |
| **Due** | July 10, 2026 (Thursday EOD) |
| **Description** | Using the table produced by Track A (Ticket A-2), attempt place name resolution for each photo using GPS + metadata signals together. For each photo: (1) run `MKLocalSearch` in a 200m radius of the GPS coordinate, (2) if OCR text is present, narrow the search to matching venue names, (3) if scene labels are present, filter MapKit results by matching POI category, (4) record the resolved name alongside the current `GeocodingService` result. Output: the shared experiment table with two new columns — "current result" and "new result with metadata." Mark each row: improved / same / worse. Run against both the iOS 18 output (Vision only) and the iOS 26 output (Vision + Apple Intelligence) so quality differences are visible side by side. |
| **Acceptance criteria** | All 10–15 photos resolved. Table has current vs. new result with improved/same/worse classification for both iOS versions. |

---

#### JOINT TICKETS

---

**Ticket J-1**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Joint] Agree on Track A → Track B handoff contract before Wednesday experiment |
| **Assignee** | Jangyoung + Woohyuk |
| **Priority** | High |
| **Due** | July 8, 2026 (Tuesday EOD) |
| **Description** | Before the joint experiment can run on Wednesday, both interns must agree in writing on what Track A produces and what format Track B expects to receive it in. This is not a code decision — it's a data decision. Deliverable: a short written document (one page max) specifying the handoff format: field names, data types, and an example row. Both interns sign off. This becomes the input spec for the experiment and the starting point for the Friday schema meeting. |
| **Acceptance criteria** | Written handoff spec exists, agreed by both interns, shared before Wednesday morning standup. |

---

**Ticket J-2**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Joint] Complete experiment table — metadata extraction + place name resolution side by side |
| **Assignee** | Jangyoung + Woohyuk |
| **Priority** | High |
| **Due** | July 10, 2026 (Thursday EOD) |
| **Description** | Final combined output from both tracks. The table should have one row per photo and the following columns: photo ID, GPS coordinate, scene labels, OCR text, face count, AI description (iOS 26 only), current place name (GeocodingService), new place name (Track B resolution), result classification (improved / same / worse), extraction time (iOS 18 vs. iOS 26). This table is the primary Week 1 deliverable and is reviewed together before the Friday schema meeting. Pass mark: 5 out of 10 results improved. |
| **Acceptance criteria** | Table complete with all columns. Both simulators represented. Pass/fail verdict recorded. Shared with team lead before Friday. |

---

**Ticket J-3**

| Field | Value |
|---|---|
| **Type** | Task |
| **Summary** | [Joint] Friday schema meeting — agree on data model changes and get sign-off |
| **Assignee** | Jangyoung + Woohyuk |
| **Priority** | High |
| **Due** | July 11, 2026 (Friday EOD) |
| **Description** | Both interns meet (team lead joins or reviews async) to answer and document: (1) what exact fields are being added to `RecapPhoto` — names, types, optional vs. required, (2) what fields if any are being added to `PlaceStop`, (3) how existing saved blogs decode gracefully when these fields don't exist yet (default values, nil-safe decoding), (4) who writes the model change in Week 2. Output is a written schema document. Team lead signs off. This document is the contract for Week 2 — no production code is written until it is approved. |
| **Acceptance criteria** | Schema document written, reviewed, and signed off by team lead before EOD Friday. |
