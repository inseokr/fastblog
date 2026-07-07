# Intern Plan — July 2026
**Duration:** 4 weeks (July 7 – August 1, 2026)
**Team:** 2 interns
**Theme:** Make Bloggo simpler by reducing manual work around photos and places.

---

## Context

From our July 2 team meeting, the top priorities are:

1. Simplify the overall user experience
2. Build social features that encourage organic sharing
3. Expand AI capabilities that reduce effort (not add complexity)
4. Strengthen marketing and community

For this intern sprint, we're focusing on **#1 and #3** — specifically two items from the AI roadmap that directly reduce manual effort for users:

- **KS2-10** — Improve POI selection process
- **KS2-11** — Improve photo grouping

These were selected because they eliminate real friction that exists today (manually naming places, manually organizing photos) without adding new concepts or complexity for the user.

---

## Team Split

| | Intern A | Intern B |
|---|---|---|
| **Task** | KS2-10 — POI Selection | KS2-11 — Photo Grouping |
| **Goal** | Replace manual place naming with smart auto-suggestions | Auto-group photos by time and location into blog sections |

---

## 4-Week Plan

### Week 1 — Understand Before You Build (Both Interns)
- Walk through the current POI and photo management flow end-to-end
- Document every manual step a user takes today — count taps, note friction points
- Explore available data: GPS coordinates, timestamps, photo metadata, MapKit/CoreLocation APIs
- Write a one-page spec (before → after) and get team sign-off before writing code

---

### Week 2 — Core Build

**Intern A (POI Selection)**
- Build auto-suggestions from Apple Maps / MapKit based on GPS location at photo capture time
- Handle edge cases: no GPS signal, ambiguous nearby locations (e.g. airport vs. hotel)

**Intern B (Photo Grouping)**
- Build time + location clustering: photos taken within a defined time and distance window are grouped together
- Define and tune the clustering thresholds based on real trip data

---

### Week 3 — UI + Integration

**Intern A (POI Selection)**
- Build a quick confirm/edit flow: app proposes a place name, user taps confirm or makes a correction — no typing from scratch
- Edge case polish

**Intern B (Photo Grouping)**
- Build the review UI: user sees proposed groups and can merge or split before confirming
- **Sync with Intern A mid-week** to agree on data contract — each photo group should receive a POI label from Intern A's work

---

### Week 4 — Connect, Polish, and Demo

- Connect the two features: photo groups are labeled automatically with POI names from the selection system
- Do one focused onboarding simplification pass (non-AI) to reinforce the "simpler app" goal from the team meeting
- Internal demo: show the full flow from "raw photos from a trip" → "organized, labeled blog sections" with minimal manual input
- Measure and report: how many taps were eliminated?
- Each intern writes a short handoff doc — what's done, what's not, what core team needs to take it further

---

## Definition of Success

A user returning from a trip can go from raw photos to an organized, labeled travel blog with **fewer manual decisions** than today. The experience should feel like the app already knows where you were and what belongs together.

---

## What We're Not Building (This Sprint)

These AI roadmap items were intentionally deferred — they add complexity before the core is simple:

- KS2-8 Digital Clone
- KS2-9 Extract user DNA/profile
- KS2-12 Text & Metadata generation
- KS2-13 Photo & Video Intelligence (broad scope)

These can be revisited once the core POI and grouping experience is solid.
