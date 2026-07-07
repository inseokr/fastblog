# Bloggo — Product Vision
**For Interns | Updated July 2026**

> This document describes where Bloggo is going — not just what it is today. Use it to understand the long game, the "why" behind what we're building, and where each feature fits in the bigger picture.

---

## The North Star

Bloggo's mission is to become the **home for your travel life** — the app you open before, during, and after every trip. Today we're the best post-trip blog generator on iOS. Tomorrow we're the platform that plans your next trip, documents it in real-time with your friends, and connects you with a community of people who travel like you do.

LinkedSpaces was our first attempt at building this: a social travel platform for mapping, saving, and sharing places. Bloggo inherits those ideas and takes them further — with better AI, better content output, and a cleaner product focus.

---

## Feature Pillars

---

### 1. AI-Powered Itinerary Builder

**Status:** Planned
**Predecessor:** LinkedSpaces had a full itinerary builder — structured day-by-day trip plans with places, times, and notes.

**The Bloggo version goes further.** Because we already have:
- Rich location metadata from every blog a user has generated
- Their photo history organized by place and category
- Knowledge of what cities, neighborhoods, and types of places they've been to

…we can use AI agents to generate **personalized trip itineraries** — not generic "top 10 things to do in Tokyo" lists, but plans tuned to what this specific user has loved before.

**How it works:**
1. User says "I'm going to Lisbon for 5 days"
2. Bloggo looks at: their past trip data, the places they've saved, their travel pace (how many places per day), categories they frequent (food-heavy? museums? hidden gems?)
3. AI agent generates a day-by-day itinerary with real place recommendations, estimated time per stop, and routing logic
4. User can edit, swap, or regenerate any day
5. After the trip, Bloggo compares the plan to what they actually did and generates the blog from the real experience

**Why this matters:** It closes the loop. Bloggo becomes the app you open *before* the trip, not just after. That's a massive retention multiplier.

**Data inputs the AI uses:**
- User's past `PlaceStop` data (categories, neighborhoods, visit patterns)
- Wishlist (see section 4)
- Public place data (coordinates, hours, ratings)
- User's preferred travel pace from previous blogs

---

### 2. Collaborative & Social Features

**Status:** In Design
**Full spec:** See [`social-fun-features.md`](social-fun-features.md) for detailed feature breakdowns.

**Summary of what's coming:**

| Feature | What It Does |
|---|---|
| **Shared Trip Room** | One person creates a room, friends join via link. Photos flow into a shared feed in real-time. Bloggo auto-generates one group blog at the end. This is our biggest word-of-mouth download driver — joining a room requires downloading the app. |
| **Trip Invite Card** | Auto-designed shareable card with destination + dates. Sent via iMessage or posted to a story. Think: Partiful for travel. |
| **Live Trip Feed** | Inside a Trip Room, a real-time feed of every photo added by every member, organized by time and place. Lightweight emoji reactions only — no comments, no social pressure. |
| **My Perspective Split** | After the group blog is generated, each member can view a version filtered to only their photos and narrative. One trip, personalized for everyone who was there. |
| **Shared Blog Link** | The finished blog is shareable as a public read-only link — like a mini travel website. Soft "Download Bloggo" CTA at the bottom. Biggest viral reach mechanic we have. |

**The strategic thread:** Every one of these features has a built-in loop where *using Bloggo requires your friends to use Bloggo*. That's how you get organic growth without a marketing budget.

---

### 3. Discovery Page

**Status:** Long-term / Requires Community First
**Predecessor:** LinkedSpaces had a networking layer where users connected through shared spaces.

**The concept:** Once we have enough users generating blogs and saving places, we can build a Discovery page — a curated feed of travel content from the Bloggo community, organized by:
- **Destination** — "Trending in Lisbon this month"
- **Category** — "Hidden cafes your network loves"
- **People you follow** — blogs from travelers you've connected with

**What makes Bloggo's discovery different from Tripadvisor or Google:**
- Content is personal and authentic — real trip blogs, not review spam
- You can see the full trip narrative, not just a star rating
- Content is ranked by real engagement signals (see section 6 on sentiment)

**The networking concept from LinkedSpaces:** Users who visit the same places and have overlapping travel styles can be suggested to each other as connections. "3 people in your network went to Oaxaca last month." The social graph is built on *shared places*, not follower counts.

**Prerequisite:** We need a meaningful number of users generating public content before this is worth building. Don't rush Discovery — an empty feed kills the feature faster than no feed.

---

### 4. Wishlist / Next Visits

**Status:** Near-Term
**Trigger:** We already show other places on the map view inside a trip. Users have no way to act on what they see.

**The feature:** A **Wishlist** tab or section where users can save places they want to visit. This is distinct from their travel history — it's forward-looking.

**How you add to the Wishlist:**
- Tap any place on the map → "Save to Wishlist"
- Inside someone else's shared blog → "Add to my Wishlist"
- From the Discovery page (future) → direct save
- From the AI Itinerary Builder → "Save this place for a future trip instead"

**How the Wishlist is used:**
- Visible on your profile as a "Next Visits" section — shareable with friends
- Fed back into the AI Itinerary Builder: "You've had Lisbon on your wishlist for 8 months — want to plan that trip?"
- Notified when a friend you follow visits a place on your wishlist — "Your friend just went to this restaurant you saved"

**The value loop:** Wishlist → AI Itinerary suggestions → Real trip → Bloggo generates the blog → Places from the blog can become more Wishlist items. Every trip creates the data for the next one.

---

### 5. Travel Stats & Profile

**Status:** Planned
**Predecessor:** LinkedSpaces had a full-fledged travel stats system. Visit [linkedspaces.com](https://www.linkedspaces.com/) to see what we built before — use it as the visual benchmark.

**The concept:** A user's profile isn't just their blogs — it's a living record of everywhere they've ever been, automatically compiled from all their Bloggo trips.

**Stats we can derive automatically from existing data:**

| Stat | Source |
|---|---|
| Countries visited | GPS coordinates from `PlaceStop` → country lookup |
| Cities visited | Same — unique city count across all trips |
| Total places saved | `PlaceStop` count across all blogs |
| Miles/km traveled | Route distance calculated across trip days |
| Favorite categories | Most frequent `placeCategory` values |
| Most visited city | Highest frequency destination |
| Longest trip | Blog with highest day count |
| Travel streak | Consecutive months with at least one trip |
| Photos captured | Total `RecapPhoto` count across all blogs |
| Continents visited | Derived from country data |

**Yearly Wrapped:** At the end of each year, Bloggo generates a "Your Year in Travel" recap — most visited country, total distance, standout moments, a highlight reel. Think Spotify Wrapped for travel. Highly shareable, high retention mechanic.

**Profile layout (inspired by LinkedSpaces):**
- Map at the top showing every country/city visited, highlighted
- Stat grid below (countries, cities, miles, places)
- Recent trips as a horizontal scroll
- Wishlist teaser ("5 places saved for next time")

---

### 6. Community Content Ranking & Sentiment

**Status:** Research / Long-term
**The challenge:** Once we have user-generated content in a Discovery feed, we need a way to rank it — surface the best blogs, flag great places, understand what users actually respond to. But asking users to rate things explicitly (star ratings, long surveys) creates friction and gets ignored.

**Explicit signals (low friction):**
- **Save to Wishlist** from a blog — strongest positive signal, requires intent
- **Emoji reactions on Trip Feed** — lightweight, 1-tap, already planned for Live Trip Feed; extend to Discovery
- **Share a blog** — sharing = strong endorsement
- **Comment** — shows enough interest to type something; planned but kept minimal

**Passive / implicit signals (zero friction from user):**
- **Read depth** — how far did they scroll through a blog? Did they reach the last day?
- **Re-opens** — did they open the same blog more than once?
- **Dwell time per place** — how long did they pause on a specific PlaceStop?
- **Wishlist adds from blog** — which specific places within a blog got saved?
- **Referral opens** — did they share the blog link and did the recipient open it?

**The sentiment model:** Instead of asking "Was this good? 1-5 stars," we combine these signals into a passive quality score per blog and per place. A blog that people read fully, re-open, and save places from is objectively better content than one they skimmed.

**AI-assisted quality layering:**
- Photo quality already scored via `PhotoScore` / Vision framework
- Caption clarity can be scored via LLM pass (does the text describe what's actually in the photo?)
- Narrative coherence — does the blog tell a story with a clear arc, or is it just a list of places?

**Community ranking tiers (visible on profile):**
- Explorer → Voyager → Correspondent → Curator
- Unlocked based on: number of places documented, community engagement received, wishlist saves by others
- Keeps the status mechanic meaningful without making it a leaderboard race

**What we explicitly avoid:**
- Numeric ratings — they invite negativity and gaming
- Downvotes — too much social friction
- Comment counts as quality signal — a controversial blog gets comments; doesn't mean it's good
- Follower counts as the primary ranking signal — we're not trying to be Instagram

**The core insight:** The best travel content inspires action (saves a place, plans a trip). Measure action, not attention.

---

### 7. Content Ecosystem & Travel Network *(Stretch Goal)*

**Status:** Visionary / Long-term
**Analogy:** LinkedIn, but for travel — your blogs become your professional-grade travel portfolio, and the places database you've built over every trip becomes a shareable, collaborative asset.

---

#### The Core Idea

Right now, a Bloggo blog is a document you *own* — rich, personal, and beautifully generated, but ultimately private unless you share a link. The Content Ecosystem flips that model: **blogs become living, interconnected nodes in a shared travel knowledge graph.**

Every `PlaceStop` a user documents — the hidden ramen spot in Kyoto, the viewpoint above Lisbon, the off-grid hostel in the Atlas Mountains — is a piece of data with coordinates, a category, a narrative, and a quality signal. Collectively, all Bloggo users are building the most authentic travel database in the world, one real trip at a time. The Content Ecosystem is what lets that data do something.

---

#### Two Layers

**Layer 1 — The Content Platform**

Blogs become portable, embeddable, and cross-platform:

| Feature | What It Does |
|---|---|
| **Blog as a Web Page** | Every blog gets a permanent, beautifully designed public URL — `bloggo.app/u/username/kyoto-2026` — shareable anywhere, no app required to read |
| **Embed Cards** | One-line embed for any `PlaceStop` or full blog — paste into Substack, Notion, Reddit, a personal travel site |
| **Content API** | Open API for place data — travel journalists, tour operators, guidebook writers can pull authenticated user-shared place databases into their own tools |
| **Creator Profile** | A public-facing travel portfolio: your stats, your best blogs, your most-saved places, your travel style tag (`"food-first"`, `"museum circuit"`, `"off-grid"`) |

The strategic move: Bloggo content appears *across the internet*, not just inside the app. Every embed is a download CTA. Every shared blog page is a top-of-funnel entry point.

---

**Layer 2 — The Travel Network**

This is the LinkedIn parallel. LinkedIn's core insight was that your *professional history* — your resume, your skills, your connections — is more valuable when it's visible and structured. Bloggo's equivalent is your *travel history*: the places you've been, what you thought of them, and what you know.

| Concept | Bloggo Version |
|---|---|
| **Shared Databases** | Users can publish a curated `PlaceStop` list as a public "collection" — "Best Spots in Oaxaca," "Tokyo for First-Timers," "Hidden Gems: Southern Spain." Others can follow, fork, or add to it |
| **Verified Travel Experience** | Your profile shows countries, cities, and place categories you've documented — not self-reported, but *evidenced by your blogs*. A "Foodie" tag isn't a checkbox you click; it's earned by documenting 50+ restaurants across 10 countries |
| **Network Connections** | Follow other travelers. See when someone in your network visits a place on your wishlist. Get notified when a connection publishes a blog from a destination you've been to |
| **Collaborative Collections** | Two or more users co-author a place database — a group of friends compiling the definitive list of every restaurant they've eaten at across 5 years of travel together |
| **B2B Layer** | Tour operators, travel agencies, and local guides can claim a Bloggo Business Profile, see authentic user-generated content about their region, and reach travelers who've already documented interest in that destination |

---

#### Why "LinkedIn for Travel" Is the Right Frame

LinkedIn works because your professional data — where you worked, what you did, who you know — has verifiable provenance. Bloggo's travel data has the same property: your blogs are *timestamped, geolocated, photo-evidenced* records of where you actually went and what you actually experienced. That's not an influencer's curated aesthetic; it's a credential.

| LinkedIn | Bloggo |
|---|---|
| Work history | Trip history |
| Skills & endorsements | Place categories & verified destinations |
| Connections | Travelers with overlapping itineraries |
| Posts & articles | Blogs & place collections |
| Company pages | B2B destination profiles |
| Recruiter search | Travel concierge matching ("Find travelers who've been to rural Japan in spring") |

---

#### What Makes This a Stretch Goal

This requires:
1. **Critical mass of content** — the network effect only works once thousands of users have generated dozens of blogs each. An empty database is useless.
2. **Trust infrastructure** — user authentication, content moderation, spam prevention for the public web layer.
3. **API & partner ecosystem** — B2B integrations require dedicated BD effort, legal agreements, and a stable public API.
4. **Monetization model** — the B2B layer and Content API are the natural revenue paths; this is where Bloggo becomes a business, not just an app.

**We don't build this until the community exists to fill it.** But every feature we build before this — the blogs, the place stops, the wishlist, the travel stats, the Discovery feed — is laying the foundation. When the time comes, the data is already there.

---

## How These Features Connect

```
Before a trip          →     During a trip          →     After a trip          →     Beyond the app
──────────────────────────────────────────────────────────────────────────────────────────────────────
AI Itinerary Builder       Shared Trip Room               Blog Generation (today)    Content Ecosystem
Wishlist planning          Live Trip Feed                 Travel Stats update        Travel Network
                           Trip Invite Card               Discovery (if public)      Shared Databases
                                                          Wishlist → next trip       B2B Layer
```

Every phase feeds into every other phase. A blog from a past trip populates your stats, informs future AI itineraries, and creates Discovery content — all without the user doing extra work. At scale, all of that content flows into the Content Ecosystem and Travel Network, where it compounds into a platform others build on top of.

---

## What We're NOT Building (and why)

| Thing | Why not |
|---|---|
| Follower / following counts as primary mechanic | Turns into an influencer platform, not a travel tool |
| Paid sponsored places in itineraries | Destroys trust in the AI's recommendations |
| Public comment sections before community is mature | Empty or toxic — either kills the feature |
| Booking integration (hotels, flights) | Tripadvisor's territory; we'd be a worse version |
| Web app or cross-platform | Focus iOS first, do it better than anyone |

---

## The Sequence

These features should be built roughly in this order, because each one creates the data or community needed for the next:

1. **Wishlist** — near-term, low complexity, creates the forward-looking data layer
2. **Travel Stats** — near-term, derived from existing data, drives profile identity
3. **Collaborative features** — medium-term, drives downloads and retention
4. **AI Itinerary Builder** — medium-term, requires wishlist + stats data to be good
5. **Discovery Page** — long-term, requires community + content volume
6. **Community Ranking / Sentiment** — long-term, layered on top of Discovery
7. **Content Ecosystem & Travel Network** *(stretch)* — platform-stage, requires critical mass of users and content; unlocks B2B revenue and network effects beyond the app
