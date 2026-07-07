# Bloggo Documentation Suite — CLAUDE.md, Brand.md, Voice.md

**Date:** 2026-07-02
**Status:** Approved for implementation

## Goal

Create three authoritative documentation files now that the app is publicly released and stable:

1. **`/CLAUDE.md`** — Root-level Claude Code orientation file
2. **`docs/Documents/Brand.md`** — Visual identity and design bible
3. **`docs/Documents/Voice.md`** — Tone of voice and copy guide

All three serve both AI assistants working in the codebase and human team members (designers, marketers, interns).

---

## Approach

**Tiered (C):** CLAUDE.md covers product context + critical technical rules inline and delegates deep detail via `@`-references to `.ai/skills/`. Brand.md and Voice.md are comprehensive standalone docs living in `docs/Documents/` alongside the existing product docs.

---

## File 1: `/CLAUDE.md`

**Location:** Repo root (where Claude Code reads it by default)
**Replaces:** `docs/Documents/CLAUDE.md` (which will be removed) and the previously deleted root CLAUDE.md

### Sections

#### 1. Product
- What Bloggo is: AI-powered travel journal iOS app that auto-generates beautiful blogs from camera roll photos, organized by day and place
- Company: LinkedSpaces LLC
- Current state: Live on App Store, stable v1.x
- Mission: "Home for your travel life" — the app you open before, during, and after every trip
- Two modes: **Trip Blogs** (multi-day travel) and **My Places** (everyday moments near home)
- Export formats: PDF, video reel, carousel, storybook
- In-app camera: photos + Reel clips + Vibe audio, all stored locally on device
- Privacy-first: blog content never uploaded to servers; only account/auth data is server-side
- ASO positioning: "Bloggo: Journal & Diary" in Photo & Video category

#### 2. Audience
**Who They Are**
- Everyday travelers (not professional bloggers or influencers)
- iOS users who take lots of photos on trips but rarely do anything with them
- People who want to remember and share travel without manual effort

**Pain Points**
- Camera roll is full of trip photos that never get organized or shared
- Writing about a trip after the fact feels like homework — no one does it
- Existing tools (Day One, Worldee) require too much manual input
- Photo dumps on social media lack context and narrative
- People forget details of trips within weeks — no structured memory
- Group trips have no single place to collect and remember everyone's perspective

#### 3. Technical Setup
- Build command
- iOS version targets with Vision API guards (`#available(iOS 18, *)` etc.)
- How to register new `.swift` files in `project.pbxproj` (all 4 steps)

#### 4. Architecture Summary
- MVVM strict layering: View → ViewModel → Service → Model (plain English, no code)
- Key singletons: `AuthService`, `CreatedRecapBlogStore`, `APIManager`, `AppAnalytics`, `GeocodingService`
- State ownership tiers: `@State`, `@Published`, `@EnvironmentObject`, `@AppStorage`, `CreatedRecapBlogStore`
- Rule: Views never call Services directly

#### 5. Skills Index
`@`-reference to each `.ai/skills/` file with one-line description:
- `architecture/mvvm/layers.md` — Strict layering rules and singleton table
- `architecture/mvvm/state.md` — State tiers, `@StateObject` vs `@ObservedObject`, ViewModel template
- `architecture/async.md` — Async/await patterns
- `ui/navigation.md` — Navigation system
- `ui/components.md` — Shared component library, when to reuse vs. build new
- `ui/animations.md` — Animation conventions
- `ui/colors/palette.md` — Color values, text hierarchy, overlays (canonical Swift source)
- `ui/colors/gradients.md` — Standard gradients, regional themes, placeholder variants
- `code/naming.md` — File, type, property, function naming conventions
- `code/data-models.md` — Model conventions

#### 6. Key Docs
- `docs/Documents/product-vision.md` — Long-term roadmap and feature pillars
- `docs/Documents/competitor-analysis.md` — Competitor landscape and strategic positioning
- `docs/Documents/Brand.md` — Visual identity, design philosophy, color system
- `docs/Documents/Voice.md` — Tone of voice, copy rules, product language

---

## File 2: `docs/Documents/Brand.md`

**Location:** `docs/Documents/Brand.md`
**Audience:** AI assistants, designers, interns, anyone making visual or design decisions

### Sections

#### 1. Brand Identity
- What Bloggo stands for aesthetically: cinematic, private, effortless, travel-native
- The emotional experience the app should evoke: "your memories, beautifully preserved"
- Not a social media app — no feeds, no follower counts, no performance anxiety
- Premium feel without being exclusive — accessible to any traveler

#### 2. Design Philosophy
- **Dark-first:** Primary canvas is deep navy `#050A30`, not black. Navy feels warmer and more cinematic than pure black
- **Cinematic:** Gradients over flat fills; photography is the hero at all times; UI recedes behind content
- **Travel-native:** Color themes respond to destination (Iceland blues, Morocco reds, Tokyo magentas)
- **Effortless:** UI should feel like the app is doing the work, not the user

#### 3. Color System
- Primary background: `#050A30` (deep navy)
- Brand accent text: `#C8EBFF` (light blue)
- Primary action: `#007AFF` / Active filter: `#0B84FF`
- Destructive: `#FF4539`
- Success: `#A6F2B7`
- Dark card: `#242424` / Dark narrative card: `#191919`
- Text hierarchy on dark: white → white 0.92 → white 0.7 → white 0.5
- Light mode: always use system adaptive colors, never hardcode
- PDF header accent: `#2E62E0`
- Overlay/scrim opacity scale (0.15 tint → 0.65 photo scrim)

#### 4. Gradients
- Photo text scrim: black 0.65 → clear (bottom to center)
- Cover page fallback: `#1a1a2e` → `#2d3561` (top to bottom)
- Regional trip card themes: Iceland, Morocco, Tokyo, Paris, California, Alps, Barcelona, London — intent: the card background evokes the destination before the user opens the blog
- Photo placeholders: 10 variants (Sunset, Ocean, Forest, Mountain, Golden Hour, Aurora, Beach, City/Dusk, Meadow, Lake) — chosen by `index % 10`
- Neon glow (Nearby Share): 6 rotating colors (purple, bright blue, cyan, pink, violet, light blue)

#### 5. Materials & Surfaces
- `.ultraThinMaterial` for frosted-glass controls, toolbars, overlays
- `Color.white.opacity(0.12)` for hairline dividers on dark surfaces
- `Color.black.opacity(0.08)` for hairline dividers on light surfaces
- Full-screen dark: `#050A30`; cards on dark: `#242424`; nested cards: `#191919`

#### 6. Export Aesthetics
- **StoryBook / PDF Light mode:** white background, black primary, dark gray secondary, `UIColor(white: 0.92)` cards
- **StoryBook / PDF Dark mode:** black background, white primary, `UIColor(white: 0.72)` secondary, `UIColor(white: 0.14)` cards
- Export output should feel like a premium publication — not a screenshot of the app
- PDF header accent (`#2E62E0`) is the only place a brighter blue appears in exports

#### 7. Design Rules (What Bloggo Never Does)
- Never hardcode a light-mode background — always use system adaptive colors
- Never use follower counts, star ratings, or numeric rankings as UI elements
- Never flatten gradients to solid fills for performance shortcuts
- Never use pure black (`#000000`) as the app background — use `#050A30`
- Never add social pressure mechanics (likes, view counts) to the UI

---

## File 3: `docs/Documents/Voice.md`

**Location:** `docs/Documents/Voice.md`
**Audience:** AI assistants, anyone writing in-app copy, notifications, onboarding, or error messages

### Sections

#### 1. Voice Principles
Four core traits, each with a paragraph explaining what it means in practice:
- **Direct** — Short sentences. Active verbs. No filler. Users are in the middle of doing something; don't slow them down with copy.
- **Warm** — Not cold, not chirpy. Bloggo acknowledges the emotional weight of memories without being sentimental. "Your memories deserve more than five blogs." not "Upgrade now!"
- **Private-first** — Every time data or storage is mentioned, the copy is clear and reassuring without being defensive. Privacy is a feature, not a disclaimer.
- **Effortless** — Copy should make the user feel like the app is doing the hard work. We don't describe steps; we describe outcomes.

#### 2. Tone Calibration
- **Warmer:** First-time onboarding flows, empty states, post-trip moments, auth screens
- **More direct:** Destructive action confirmations, error messages, permission requests, loading states
- **Never playful in:** data deletion warnings, account deletion, error messages that involve data loss
- **Never robotic in:** empty states, onboarding, first blog creation

#### 3. Product Language (Canonical Terms)
What to always call things and what to avoid:

| Concept | Use | Avoid |
|---|---|---|
| The app's output | Blog | Post, entry, story (except in "cover story" context) |
| Short video clips | Reel | Video, clip, short |
| Ambient audio | Vibe | Background audio, soundtrack |
| A place stop in a blog | Place, Place Stop | Location, pin, spot |
| Daily content collection | Moment | Photo, capture |
| Everyday home-area content | My Places | Daily mode, home mode |
| Multi-day travel content | Trip Blog | Travel log, trip |
| Narrative AI text | Story, Caption | AI text, generated text |
| Draft not yet generated | Draft | Pending, unfinished |
| The company | LinkedSpaces LLC | Linked Spaces, LS |

#### 4. Writing Rules
- **Sentence case** for all UI labels, button text, and headings (not Title Case)
- **Verbs for buttons:** "Create Blog" not "Blog Creation"; "Save Draft" not "Draft Saving"
- **No exclamation points in errors** — ever. Reserve them for genuine celebration moments only (and use sparingly)
- **Privacy copy is plain English** — never paste legalese into UI-facing strings
- **Numbers under 10 are spelled out** in narrative copy, numerals in counts and data
- **Avoid passive voice** in UI copy — "We deleted your blog" not "Your blog has been deleted"
- **Ellipsis (…) for in-progress only** — "Creating your blog…" not "Loading..."
- **"Bloggo" never abbreviated** — not "BG", not "the app", always "Bloggo"

#### 5. Copy Patterns
Real examples from the app annotated with why they work, and "instead of X, say Y" rewrites:

- "Your photos already tell the story" → outcome-focused, not feature-focused
- "No blank page, no manual sorting" → addresses the pain point directly in two phrases
- "Automatically sorted by day, place & moment" → outcome, not process description
- "Your blog stays private. Nothing is shared unless you choose to share it." → reassurance without legalese
- "Your memories deserve more than five blogs." → warm, specific, motivating without pressure
- "Bloggo finds trips in your camera roll using date and location so you can create blogs in seconds." → mechanism + benefit in one sentence

#### 6. What Bloggo Never Sounds Like
Anti-patterns with contrast:
- No hype: "Amazing!" / "Incredible!" / "🔥🔥🔥" — Bloggo is confident, not excitable
- No pressure: "Don't miss out!" / "Limited time!" — no FOMO mechanics in copy
- No social comparison: "See what your friends are sharing" — we're not a feed
- No corporate jargon: "Leverage your memories" / "Optimize your travel content" — plain English always
- No vagueness: "Something went wrong" — always say what happened and what to do next

---

## File Relationships

```
/CLAUDE.md                      ← Full orientation for cold-start (product + tech)
    ↓ references
.ai/skills/                     ← Deep technical detail (Swift code conventions)
docs/Documents/Brand.md         ← Visual identity for design decisions
docs/Documents/Voice.md         ← Copy guide for any written content
docs/Documents/product-vision.md ← Long-term roadmap (where we're going)
docs/Documents/competitor-analysis.md ← Competitive landscape
```

---

## Implementation Notes

- Delete `docs/Documents/CLAUDE.md` after the root version is written — don't keep both
- Brand.md references `.ai/skills/ui/colors/palette.md` as the canonical source for Swift color values; Brand.md explains the *intent*, the skill file has the *code*
- Voice.md canonical product language table should be kept in sync with any rebrand decisions in the ASO strategy doc
- Commit all three files together in one commit with message referencing the stable release milestone
