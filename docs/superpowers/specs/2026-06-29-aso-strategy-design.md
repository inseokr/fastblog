# Bloggo ASO Strategy — June 2026

## Goal

Improve Bloggo's organic discoverability on the App Store by replacing ineffective metadata with keyword-data-driven copy. Current metadata uses internal product language ("camera roll blog", "travel moments") that nobody searches for. This document defines the full metadata update based on AppFigures keyword research.

---

## The Problem With Current Metadata

| Field | Current | Issue |
|---|---|---|
| App Name | `Bloggo` | 6/30 chars used — most powerful ASO field is empty |
| Subtitle | `Turn Photos Into Blogs` | A tagline, not a keyword. Not how users search. |
| Keywords | `travel blog,travel diary,trip journal,photo journal,camera roll blog,travel memories,trip tracker` | Almost entirely Pop 5 — effectively invisible |
| Category | Travel | Competing against airlines and booking apps |
| Positioning | "Travel blogs" | Locks out the broader moments/life journal audience |

---

## Keyword Research Data (AppFigures, US Store — June 2026)

> Pop = Search Popularity (5–100 scale). KD = Keyword Difficulty (higher = harder to rank).
> Sweet spot: Pop 20+ with KD under 70.

### Viable Keywords

| Keyword | Pop | KD | Decision |
|---|---|---|---|
| journal | 61 | 81 | **App Name** — highest volume, must own |
| diary | 52 | 62 | **App Name** — best Pop/KD ratio in category |
| memory | 42 | 82 | **Subtitle** — next best volume after journal/diary |
| photo book | 8 | 65 | **Keyword field** — low volume, very winnable |
| daily journal | 9 | 70 | **Keyword field** — winnable long-tail |

### Dead Keywords — Do Not Use

| Keyword | Pop | KD | Why |
|---|---|---|---|
| vlog | 40 | 100 | Max difficulty — unrankable |
| blog | 39 | 95 | Near-impossible KD |
| moments | 38 | 86 | Volume exists but wall of competition |
| trip tracker | 13 | 82 | Low volume + high difficulty |
| memories | 8 | 68 | Too low volume |
| travel diary | 6 | 76 | Dead |
| travel journal | 6 | 78 | Dead |
| photo diary | 5 | 61 | Dead volume |
| photo journal | 5 | 78 | Dead |
| video journal | 5 | 75 | Dead |
| life journal | 5 | 59 | Dead volume |
| memory journal | 5 | 75 | Dead |
| camera roll | 5 | 78 | Dead |
| visited places | 5 | 59 | Dead |
| travel moments | 5 | 62 | Dead |
| save places | 5 | 58 | Dead |
| place tracker | 5 | 69 | Dead |
| scrapbook | 5 | 100 | Dead + max difficulty — never use |

### Key Insight

The entire journal/diary/photo app category has only **two keywords with meaningful volume AND winnable competition: `journal` (Pop 61) and `diary` (Pop 52, KD 62)**. Everything else is either a ghost town or dominated by apps with massive authority. The entire current keyword field is doing nothing.

---

## New Metadata — Final Recommendations

### App Name (30 chars)
```
Bloggo: Journal & Diary
```
**22/30 chars used.**

Stacks the two most powerful keywords in the most heavily-weighted ASO field. Apple indexes the app name first — every competitor is wasting this fighting over dead terms like "travel journal" (Pop 6). We own the parent terms instead.

---

### Subtitle (30 chars)
```
Photos, Videos & Your Memories
```
**30/30 chars used.**

Three jobs:
1. Explicitly covers **both photos and videos** — removes the travel/photo-only perception
2. Indexes for `memory` (Pop 42) — the highest-volume keyword available after journal/diary
3. Signals broad scope — moments, not just trips

---

### Keyword Field (100 chars)
```
trip,travel,places,moments,daily,personal,life,map,blog,organize,ai,recap,book,auto,reel,route,story
```
**100/100 chars used.**

Rules applied:
- No words already in App Name or Subtitle (Apple ignores duplicates)
- No spaces — commas only, maximizes token count
- Includes `book` for "photo book" (Pop 8, KD 65 — most winnable niche term found)
- Includes `daily` to form "daily journal" compound with name
- Includes `ai` — trending in Photo & Video apps (22% of top apps use it per Nov 2025 data)
- Includes `organize` — matches the "no more messy camera roll" user intent
- Avoids `vlog`, `scrapbook`, `blog` (KD 95–100 — unrankable)

---

### Category
| | Current | New |
|---|---|---|
| **Primary** | Travel | **Photo & Video** |
| **Secondary** | — | **Lifestyle** |

**Why Photo & Video:** Bloggo's core mechanic is camera roll → journal. AI-powered photo/video organization is the dominant trend in this category (22% of top apps use "AI" in metadata). Users searching "organize photos" or overwhelmed by their camera roll land here.

**Why not Health & Fitness:** Day One works there because it has gratitude prompts, mood tracking, and mental health framing. Bloggo doesn't — wrong audience intent, would cause churn.

**Why not Travel:** Competing for featuring against Airbnb, Google Maps, and airline apps. Editorial slots in Travel go to booking-intent apps, not journals.

**Why Lifestyle as secondary:** Captures the "all your moments, not just travel" positioning. Where life journals, memory keepers, and daily capture apps browse. Less competitive than H&F for journaling.

---

### Description Rewrite Guidelines

**Kill this opening line:**
> "Turn your camera roll into beautiful travel blogs."

**Replace with:**
> "Turn your camera roll into a beautiful journal — photos, videos, and places, organized automatically."

**Rules for the full rewrite:**
- Remove "travel blog" framing entirely — this limits the audience
- Replace "blog" language with "journal" and "diary" — these are the searched terms
- Mention **photos AND videos** explicitly in the first paragraph
- Keep the "no blank page, no manual sorting" line — strong conversion copy
- Add "journal" and "diary" naturally throughout — helps Google Play indexing and conversion
- Keep the privacy section — it's a trust signal and differentiator

**Section order to keep:**
1. Lead paragraph (rewritten above)
2. How Bloggo Works
3. Features (keep all current features, rename "INSTANT BLOG CREATION" → "INSTANT JOURNAL CREATION")
4. Privacy First

---

### Promotional Text (170 chars — unchanged structure, update framing)

**Current:**
> Capture photos, vibes, and reels—or scan your camera roll. It builds trip blogs by day and place, with on-device AI. Export PDFs, videos, carousels, and storybooks.

**Suggested update:**
> Capture photos and videos—or scan your camera roll. Builds a journal by day and place, with on-device AI. Export PDFs, videos, carousels, and storybooks.

Promotional text is NOT indexed by Apple for search — it only shows on the App Store page. Keep it conversion-focused, not keyword-stuffed.

---

## Competitive Landscape

| App | Name | Subtitle | Lesson |
|---|---|---|---|
| Day One (15M DL) | `Day One: Daily Journal & Diary` | `Private Gratitude Journaling` | Stacks journal + diary in name, different keywords in subtitle |
| Journo | `Journo: Travel & Trip Tracker` | `Journal, Log & Map Your Trips` | Every slot used — but targeting dead travel keywords |
| Travel Diaries | `Travel Journal: Photo Diary` | `Digital Scrapbook & Trip Blog` | Locked into travel + scrapbook (Pop 5, KD 100) |
| Collect | `Collect - Photo Journal, Diary` | `Daily picture calendar & album` | Right idea, weak execution on subtitle |
| Polarsteps (18M users) | `Polarsteps` | `Trip Planner & Tracker` | Pure brand — survives on brand recognition, not ASO |

**The gap:** Nobody has cleanly claimed `Journal & Diary` in the Photo & Video category. Day One owns it in Health & Fitness. Bloggo can own it in Photo & Video.

---

## Implementation Checklist

- [ ] Update App Name → `Bloggo: Journal & Diary`
- [ ] Update Subtitle → `Photos, Videos & Your Memories`
- [ ] Replace Keyword Field → `trip,travel,places,moments,daily,personal,life,map,blog,organize,ai,recap,book,auto,reel,route,story`
- [ ] Update Primary Category → Photo & Video
- [ ] Add Secondary Category → Lifestyle
- [ ] Rewrite Description opening paragraph
- [ ] Rename "INSTANT BLOG CREATION" → "INSTANT JOURNAL CREATION" in description
- [ ] Update Promotional Text framing (blog → journal)
- [ ] Submit app update to Apple (category change requires a new binary submission)

---

## What To Monitor After Launch

Check AppFigures 4–6 weeks after the update goes live:

- **Impressions** — should increase as "journal" and "diary" start indexing
- **Keyword rankings** — track `journal`, `diary`, `memory`, `photo book`, `daily journal`
- **Conversion rate (CVR)** — watch that the new positioning doesn't confuse existing Travel users
- **Category ranking** — benchmark your rank in Photo & Video vs old rank in Travel

---

*Research conducted June 29, 2026. Keyword data from AppFigures, US App Store.*
