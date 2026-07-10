# Blog Highlights First-Time Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first time a blog opens in Highlights style, the hero builds itself in a ~2.4s staged sequence and the Trip Intelligence cards cascade in when scrolled into view — once per blog, persisted.

**Architecture:** All state and logic live in `fastblog/Views/RecapBlogPageView.swift` (spec: no new files, no pbxproj edits). A stepped `HighlightsRevealStage` enum drives every hero element; a single sequencing `Task` advances it with `withAnimation` + `Task.sleep`. The intelligence cascade is one boolean flip observed through a new `PreferenceKey`, with per-card `.delay(i * 0.08)` animations. Seen-state persists in one comma-joined `@AppStorage` string capped at 120 blog IDs.

**Tech Stack:** SwiftUI (iOS 17+ APIs already in use in this file: `.onChange(of:)` two-param, `Task.sleep(for:)`).

**Spec:** `docs/superpowers/specs/2026-07-09-blog-highlights-first-reveal-design.md`

## Global Constraints

- Only `fastblog/Views/RecapBlogPageView.swift` is modified. No new files, no `project.pbxproj` edits, no model/service changes, Classic style untouched.
- `@AppStorage` key is exactly `"bloggo.highlightsRevealSeen"` — comma-joined blog UUID strings, capped at the most recent 120 entries.
- Blog identity for the seen list is `blogId.uuidString` (the stable `let blogId: UUID` at `RecapBlogPageView.swift:106`).
- Marked seen only when the hero sequence **completes** — an interrupted reveal replays next open.
- Hero timeline (cumulative): 0.0 photo → 0.5 capsule → 0.7 title → 0.95 opening line → 1.2 metrics → 1.9 slide strip → 2.4 done.
- Animation values: interactive spring `.spring(response: 0.4, dampingFraction: 0.75)`, fades `.easeInOut(duration: 0.3)`, photo fade `.easeIn(duration: 0.5)`.
- Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): same timestamps, opacity fades only — no springs, slides, scale, or count-up.
- No code comments unless the WHY is non-obvious (house rule).
- Build command (must pass after every task): `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
- Working branch: `Revamp`. Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Note: `RecapBlogPageView.swift` has ~180 lines of uncommitted Highlights-style work in the working tree. Task 1 Step 1 commits it as a baseline **before any reveal work** so reveal commits are clean diffs.
- Line numbers below refer to the working-tree file as of plan writing; they drift as tasks land — anchor to the quoted code, not the number.

---

### Task 1: Reveal state machine & persistence

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`
  - State block after `@State private var activeHighlightSlideIndex = 0` (line 262)
  - `.onChange` chain after `.onChange(of: hasFinishedInitialLoad) { _, _ in refreshBlogReelAutoplayEnabled() }` (line 744)
  - New extension appended at end of file (line 8691)

**Interfaces:**
- Consumes: existing `blogId: UUID`, `hasFinishedInitialLoad`, `isEditMode`, `selectedDayIndex`, `isExportingPDF`, `showStoryMode`, `pendingStoryOpen`, `pendingDeepLinkStopScrollId`, `initialScrollToStopId`.
- Produces (Tasks 2–4 rely on these exact names):
  - `enum HighlightsRevealStage: Int, Comparable` with cases `hidden, heroPhoto, capsule, title, openingLine, metrics, slideStrip, done`
  - `@State highlightsRevealStage: HighlightsRevealStage` (default `.done`)
  - `@State showIntelligenceCascade: Bool` (default `true`), `@State isIntelligenceCascadeEligible: Bool` (default `false`)
  - `@Environment(\.accessibilityReduceMotion) reduceMotion: Bool`
  - `func startHighlightsRevealIfNeeded()`, `func cancelHighlightsReveal()`

- [ ] **Step 1: Baseline commit of the existing uncommitted Highlights work**

```bash
cd /Users/ybstudio/Desktop/Projects/Bloggo
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: highlights presentation style baseline

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Add the reveal state block**

Directly after `@State private var activeHighlightSlideIndex = 0` (line 262), insert:

```swift
    // MARK: - Highlights Reveal State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("bloggo.highlightsRevealSeen") private var highlightsRevealSeenRaw = ""
    @State private var highlightsRevealStage: HighlightsRevealStage = .done
    @State private var highlightsRevealTask: Task<Void, Never>?
    @State private var hasStartedHighlightsRevealThisSession = false
    @State private var isIntelligenceCascadeEligible = false
    @State private var showIntelligenceCascade = true
```

- [ ] **Step 3: Append the Highlights Reveal extension at the end of the file**

At the very end of `RecapBlogPageView.swift` (after the last closing brace, line 8691), append:

```swift

// MARK: - Highlights Reveal

extension RecapBlogPageView {
    enum HighlightsRevealStage: Int, Comparable {
        case hidden
        case heroPhoto
        case capsule
        case title
        case openingLine
        case metrics
        case slideStrip
        case done

        static func < (lhs: HighlightsRevealStage, rhs: HighlightsRevealStage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private var highlightsRevealSeenIds: [String] {
        highlightsRevealSeenRaw.isEmpty ? [] : highlightsRevealSeenRaw.components(separatedBy: ",")
    }

    private var hasSeenHighlightsReveal: Bool {
        highlightsRevealSeenIds.contains(blogId.uuidString)
    }

    private func markHighlightsRevealSeen() {
        var ids = highlightsRevealSeenIds
        guard !ids.contains(blogId.uuidString) else { return }
        ids.append(blogId.uuidString)
        if ids.count > 120 {
            ids.removeFirst(ids.count - 120)
        }
        highlightsRevealSeenRaw = ids.joined(separator: ",")
    }

    private func startHighlightsRevealIfNeeded() {
        guard !hasStartedHighlightsRevealThisSession else { return }
        guard hasFinishedInitialLoad,
              isHighlightsStyleEnabled,
              !isEditMode,
              selectedDayIndex == 0,
              !isExportingPDF,
              !showStoryMode,
              !pendingStoryOpen,
              pendingDeepLinkStopScrollId == nil,
              initialScrollToStopId == nil,
              !hasSeenHighlightsReveal
        else { return }

        hasStartedHighlightsRevealThisSession = true
        isIntelligenceCascadeEligible = true
        showIntelligenceCascade = false
        highlightsRevealStage = .hidden
        let reduceMotion = self.reduceMotion
        highlightsRevealTask?.cancel()
        highlightsRevealTask = Task { @MainActor in
            func advance(to stage: HighlightsRevealStage, with animation: Animation) -> Bool {
                guard !Task.isCancelled else { return false }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : animation) {
                    highlightsRevealStage = stage
                }
                return true
            }
            guard advance(to: .heroPhoto, with: .easeIn(duration: 0.5)) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard advance(to: .capsule, with: .easeInOut(duration: 0.3)) else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard advance(to: .title, with: .spring(response: 0.4, dampingFraction: 0.75)) else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard advance(to: .openingLine, with: .easeInOut(duration: 0.3)) else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard advance(to: .metrics, with: .easeInOut(duration: 0.3)) else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard advance(to: .slideStrip, with: .spring(response: 0.4, dampingFraction: 0.75)) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            highlightsRevealStage = .done
            markHighlightsRevealSeen()
            highlightsRevealTask = nil
        }
    }

    private func cancelHighlightsReveal() {
        highlightsRevealTask?.cancel()
        highlightsRevealTask = nil
        highlightsRevealStage = .done
        isIntelligenceCascadeEligible = false
        showIntelligenceCascade = true
    }
}

private struct HighlightsIntelligenceMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}
```

Notes for the implementer:
- `advance` is intentionally synchronous — the sleeps between calls carry the timing. Deltas 0.5/0.2/0.25/0.25/0.7/0.5 s produce the spec's cumulative timestamps 0.5/0.7/0.95/1.2/1.9/2.4.
- Interrupted runs must NOT mark seen — only the final `highlightsRevealStage = .done` path calls `markHighlightsRevealSeen()`.
- `cancelHighlightsReveal` snaps the cascade visible unconditionally because the intelligence section is rendered in edit mode too; leaving cards at opacity 0 there would blank the section.
- `private` members in a same-file extension are visible to the main struct body — no access-level changes needed.

- [ ] **Step 4: Wire edit-mode interruption / re-evaluation**

After `.onChange(of: hasFinishedInitialLoad) { _, _ in refreshBlogReelAutoplayEnabled() }` (line 744), add:

```swift
        .onChange(of: isEditMode) { _, isEditing in
            if isEditing {
                cancelHighlightsReveal()
            } else {
                startHighlightsRevealIfNeeded()
            }
        }
```

This handles both spec cases: edit entered mid-sequence (cancel + snap) and the common open path where `checkFirstTimeTip()` flips a saved blog to view mode shortly after first render (evaluate then). Adding a second `.onChange(of: isEditMode)` alongside the existing one at line 743 is fine — SwiftUI runs both.

- [ ] **Step 5: Build**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `BUILD SUCCEEDED` (the new functions are not yet called from the hero — that's Task 2; the `.onChange` call site keeps them live).

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: highlights reveal state machine and seen-list persistence

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Hero reveal choreography

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`
  - `BlogHighlightSlide` struct (line 83–89)
  - Call site in `dayPageScrollInner` (line 1903–1905)
  - `cinematicHighlightsOpening` (line 2594–2745)

**Interfaces:**
- Consumes (from Task 1): `HighlightsRevealStage`, `highlightsRevealStage`, `startHighlightsRevealIfNeeded()`, `reduceMotion`.
- Produces: `cinematicHighlightsOpening(screenHeight:revealApplies:)` — new signature; a local `let revealStage: HighlightsRevealStage` inside it that Task 3's pill call sites read.

- [ ] **Step 1: Give `BlogHighlightSlide` a stable identity**

The struct currently has `let id = UUID()`, which regenerates on every body evaluation — the hero photo's `.id(slide.id)` would remount the image on each of the 7 stage changes during the reveal. Replace lines 83–89:

```swift
    private struct BlogHighlightSlide: Identifiable {
        var id: String { (assetIdentifier ?? "no-asset") + "|" + title }
        let title: String
        let subtitle: String
        let assetIdentifier: String?
        let fallbackSymbol: String
    }
```

(No other code constructs `BlogHighlightSlide` with an explicit `id`; `ForEach(..., id: \.element.id)` at line 2778 works unchanged with `String`.)

- [ ] **Step 2: Pass reveal applicability from the call site**

In `dayPageScrollInner` (line 1904), change:

```swift
                cinematicHighlightsOpening(screenHeight: screenHeight)
```

to:

```swift
                cinematicHighlightsOpening(screenHeight: screenHeight, revealApplies: index == 0)
```

The reveal choreography renders only on the day-0 page; other mounted day pages show the hero in its final state, so a day swipe mid-sequence "completes silently off-screen" as the spec requires.

- [ ] **Step 3: Derive the stage inside the hero**

Change the function signature (line 2594) and add the derived stage after `let slides = highlightSlides` (line 2595):

```swift
    private func cinematicHighlightsOpening(screenHeight: CGFloat, revealApplies: Bool) -> some View {
        let slides = highlightSlides
        let revealStage: HighlightsRevealStage = revealApplies ? highlightsRevealStage : .done
```

- [ ] **Step 4: Hero photo — fade + Ken Burns landing**

The photo `Group` (lines 2609–2633) currently ends with:

```swift
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(slide.id)
            .transition(.opacity)
```

Replace with:

```swift
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect((reduceMotion || revealStage >= .heroPhoto) ? 1.0 : 1.06)
            .animation(revealStage == .done ? nil : .easeOut(duration: 1.1), value: revealStage)
            .clipped()
            .opacity(revealStage >= .heroPhoto ? 1 : 0)
            .animation(revealStage == .done ? nil : .easeIn(duration: 0.5), value: revealStage)
            .id(slide.id)
            .transition(.opacity)
```

`scaleEffect` must sit **before** `.clipped()` so the 1.06 overscan is clipped to the hero frame. The `revealStage == .done ? nil : …` pattern (used on every element that carries its own `.animation(value:)`) makes the jump-to-`.done` a hard snap — both at normal completion (no visual change left) and on edit-mode interruption.

- [ ] **Step 5: Capsule row, title, opening line, slide strip**

Capsule row — the top `HStack(alignment: .center, spacing: 10) { … }` (lines 2649–2681) gets, after its closing brace:

```swift
                .opacity(revealStage >= .capsule ? 1 : 0)
```

Title — the `Group { … }` wrapping `heroTitleText` (lines 2686–2697) gets, after its closing brace:

```swift
                    .opacity(revealStage >= .title ? 1 : 0)
                    .offset(y: (reduceMotion || revealStage >= .title) ? 0 : 14)
```

Opening line — the `Text(openingLine)` chain (lines 2699–2705) gets, after `.fixedSize(horizontal: false, vertical: true)`:

```swift
                        .opacity(revealStage >= .openingLine ? 1 : 0)
```

Slide strip — the call inside `if !isCompactHero || slides.count <= 3` (lines 2716–2719) becomes:

```swift
                if !isCompactHero || slides.count <= 3 {
                    highlightSlideStrip(slides: slides, selectedIndex: safeIndex, compact: isCompactHero)
                        .padding(.top, 18)
                        .opacity(revealStage >= .slideStrip ? 1 : 0)
                        .offset(y: (reduceMotion || revealStage >= .slideStrip) ? 0 : 24)
                }
```

These four have no element-level `.animation` — the sequencing task's `withAnimation` carries their curves, and a plain (un-animated) assignment in `cancelHighlightsReveal()` snaps them.

- [ ] **Step 6: Gate slide auto-rotation on reveal completion, trigger reveal on appear**

The rotation task (lines 2733–2742) currently reads:

```swift
        .task(id: slides.count) {
            guard slides.count > 1 else { return }
```

Replace those two lines with:

```swift
        .task(id: "\(slides.count)-\(highlightsRevealStage == .done)") {
            guard slides.count > 1, highlightsRevealStage == .done else { return }
```

(Keying the task on completion restarts it the moment the reveal finishes, so rotation begins at t≈2.4s. Gating on the shared stage — not `revealApplies` — also stops off-screen day pages from rotating the shared `activeHighlightSlideIndex` mid-reveal.)

Then, directly before `.onChange(of: draft.id) { _, _ in activeHighlightSlideIndex = 0 }` (line 2743), add:

```swift
        .onAppear {
            guard revealApplies else { return }
            startHighlightsRevealIfNeeded()
        }
```

This is the open-in-view-mode trigger and — because the hero mounts fresh when the style toggles — also the Classic → Highlights trigger.

- [ ] **Step 7: Build**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: staged first-open hero reveal for highlights style

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Metric pill stagger + count-up

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`
  - Pill call sites inside `cinematicHighlightsOpening` (lines 2709–2713)
  - `heroMetricPill` (lines 2757–2773)
  - `HeroCountUpText` struct appended in the `// MARK: - Highlights Reveal` section (end of file)

**Interfaces:**
- Consumes (Task 1/2): `HighlightsRevealStage`, `reduceMotion`, local `revealStage` in the hero.
- Produces: `heroMetricPill(value: Int, label: String, revealStage: HighlightsRevealStage, staggerIndex: Int)`; `HeroCountUpText(target: Int, started: Bool, animated: Bool)`.

- [ ] **Step 1: Add `HeroCountUpText` to the Highlights Reveal section**

At the end of the file, after `HighlightsIntelligenceMinYPreferenceKey`, append:

```swift
private struct HeroCountUpText: View {
    let target: Int
    let started: Bool
    let animated: Bool

    @State private var displayed = 0

    var body: some View {
        Text("\(displayed)")
            .monospacedDigit()
            .task(id: started) {
                guard started else {
                    displayed = animated ? 0 : target
                    return
                }
                guard animated, displayed != target else {
                    displayed = target
                    return
                }
                let steps = 14
                for step in 1...steps {
                    guard !Task.isCancelled else { return }
                    let progress = Double(step) / Double(steps)
                    let eased = 1 - pow(1 - progress, 3)
                    displayed = Int((Double(target) * eased).rounded())
                    try? await Task.sleep(for: .milliseconds(50))
                }
                displayed = target
            }
    }
}
```

14 × 50ms = the spec's 0.7s count-up, with cubic ease-out. When `animated` is false (Reduce Motion, or a pill rendered outside a reveal) the number appears final immediately.

- [ ] **Step 2: Rework `heroMetricPill`**

Replace the whole function (lines 2757–2773) with:

```swift
    private func heroMetricPill(
        value: Int,
        label: String,
        revealStage: HighlightsRevealStage,
        staggerIndex: Int
    ) -> some View {
        HStack(spacing: 4) {
            HeroCountUpText(
                target: value,
                started: revealStage >= .metrics,
                animated: !reduceMotion && revealStage != .done
            )
            .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(.white.opacity(0.9))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.26), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .opacity(revealStage >= .metrics ? 1 : 0)
        .offset(y: (reduceMotion || revealStage >= .metrics) ? 0 : 8)
        .animation(
            revealStage == .done
                ? nil
                : (reduceMotion ? Animation.easeInOut(duration: 0.3) : .spring(response: 0.4, dampingFraction: 0.75))
                    .delay(Double(staggerIndex) * 0.09),
            value: revealStage
        )
    }
```

- [ ] **Step 3: Update the three call sites**

Replace lines 2709–2713 with:

```swift
                HStack(spacing: 8) {
                    heroMetricPill(value: dayCount, label: "day\(dayCount == 1 ? "" : "s")", revealStage: revealStage, staggerIndex: 0)
                    heroMetricPill(value: momentCount, label: "moments", revealStage: revealStage, staggerIndex: 1)
                    heroMetricPill(value: photoCount, label: "photos", revealStage: revealStage, staggerIndex: 2)
                }
```

(`dayCount`, `momentCount`, `photoCount` are already `Int` locals in `cinematicHighlightsOpening` — the old code stringified them. `grep -n "heroMetricPill(" ` to confirm these are the only call sites.)

- [ ] **Step 4: Build**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: staggered metric pills with count-up in highlights reveal

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Trip Intelligence cascade

**Files:**
- Modify: `fastblog/Views/RecapBlogPageView.swift`
  - `BlogHighlightFact` struct (lines 74–81)
  - Intelligence call site in `dayPageScrollInner` (lines 1914–1916)
  - Preference listener in `dayPageScrollView` (after the `TitleMinYPreferenceKey` handler ending line 2050)
  - `highlightsIntelligenceSection` (lines 2812–2849)

**Interfaces:**
- Consumes (Task 1): `showIntelligenceCascade`, `isIntelligenceCascadeEligible`, `reduceMotion`, `HighlightsIntelligenceMinYPreferenceKey`.
- Produces: `cascadeAnimation(delay:pop:) -> Animation?` helper used only inside the section.

- [ ] **Step 1: Give `BlogHighlightFact` a stable identity**

Same `UUID()`-per-render problem as the slides — per-card `.animation(value:)` needs stable identity across the boolean flip. Replace lines 74–81:

```swift
    private struct BlogHighlightFact: Identifiable {
        var id: String { title }
        let icon: String
        let title: String
        let value: String
        let detail: String
        let tint: Color
    }
```

(Fact titles — "Longest Stay", "Shooting Peak", "Travel Span", "Quiet Gap", "Top Highlight" — are unique by construction in `highlightFacts`.)

- [ ] **Step 2: Report the section's top edge**

In `dayPageScrollInner` (lines 1914–1916), replace:

```swift
                if index == 0 {
                    highlightsIntelligenceSection
                }
```

with:

```swift
                if index == 0 {
                    highlightsIntelligenceSection
                        .background(
                            GeometryReader { intelGeo in
                                Color.clear.preference(
                                    key: HighlightsIntelligenceMinYPreferenceKey.self,
                                    value: intelGeo.frame(in: .named("scroll")).minY
                                )
                            }
                        )
                }
```

- [ ] **Step 3: Fire the cascade at the 82% threshold**

In `dayPageScrollView`, after the existing `.onPreferenceChange(TitleMinYPreferenceKey.self) { … }` block (ends line 2050), add:

```swift
            .onPreferenceChange(HighlightsIntelligenceMinYPreferenceKey.self) { minY in
                guard index == 0, isIntelligenceCascadeEligible, !showIntelligenceCascade else { return }
                guard minY < screenHeight * 0.82 else { return }
                isIntelligenceCascadeEligible = false
                showIntelligenceCascade = true
            }
```

The flip alone triggers every card's own delayed animation — no `withAnimation` here (spec: "one boolean flip with per-card `.delay(i * 0.08)` animations bound to that value"). Hero and cascade stay independent: fast scrolling fires this regardless of `highlightsRevealStage`.

- [ ] **Step 4: Animate the section**

Replace `highlightsIntelligenceSection` (lines 2812–2849) with:

```swift
    private var highlightsIntelligenceSection: some View {
        let facts = highlightFacts
        let badgeDelay = Double(facts.count) * 0.08
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip Intelligence")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(recapChromeForeground)
                    Text("Signals from your photos, places, and timing")
                        .font(.caption)
                        .foregroundColor(recapSecondaryOnChrome)
                }
                .opacity(showIntelligenceCascade ? 1 : 0)
                .animation(cascadeAnimation(delay: 0), value: showIntelligenceCascade)
                Spacer()
                Text(primaryTravelDNA)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.20, green: 0.48, blue: 0.86), in: Capsule())
                    .opacity(showIntelligenceCascade ? 1 : 0)
                    .scaleEffect((reduceMotion || showIntelligenceCascade) ? 1.0 : 0.6)
                    .animation(cascadeAnimation(delay: badgeDelay, pop: true), value: showIntelligenceCascade)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    highlightFactCard(fact)
                        .opacity(showIntelligenceCascade ? 1 : 0)
                        .offset(y: (reduceMotion || showIntelligenceCascade) ? 0 : 12)
                        .animation(cascadeAnimation(delay: Double(index) * 0.08), value: showIntelligenceCascade)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    colorScheme == .dark ? Color(white: 0.10) : Color(red: 0.94, green: 0.97, blue: 0.98),
                    colorScheme == .dark ? Color(white: 0.07) : Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func cascadeAnimation(delay: Double, pop: Bool = false) -> Animation? {
        guard !isEditMode else { return nil }
        if reduceMotion { return .easeInOut(duration: 0.3).delay(delay) }
        if pop { return .spring(response: 0.35, dampingFraction: 0.55).delay(delay) }
        return .spring(response: 0.4, dampingFraction: 0.75).delay(delay)
    }
```

Only the reveal modifiers and the `let`/`return` at the top are new — header text, badge styling, grid, padding, and background are byte-identical to the current code. The badge's `dampingFraction: 0.55` spring from scale 0.6 overshoots to ≈1.05 before settling at 1.0 — the spec's pop. `cascadeAnimation` returning `nil` in edit mode makes the `cancelHighlightsReveal()` snap instant (the `.animation(value:)` modifiers would otherwise override the plain assignment).

- [ ] **Step 5: Build**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/RecapBlogPageView.swift
git commit -m "feat: scroll-triggered trip intelligence cascade with travel dna pop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Simulator verification walkthrough

**Files:** none (verification only; fix-forward edits go to `fastblog/Views/RecapBlogPageView.swift` if a scenario fails).

**Interfaces:** consumes the complete feature.

To replay a reveal for a blog already marked seen, clear the seen list on the booted simulator:

```bash
xcrun simctl spawn booted defaults delete com.fastblog.fastblog bloggo.highlightsRevealSeen
```

(Relaunch the app afterward so `@AppStorage` re-reads.)

- [ ] **Step 1: Full build**

Run: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Fresh blog open — full sequence**

Launch in a simulator, open a saved blog in Highlights style (view mode, day 1). Expected, in order: black frame → hero photo fades in with a slight zoom-out settle (0.5s) → "Blog Highlights" capsule (0.5s) → title slides up 14pt with spring (0.7s) → opening line fades (0.95s) → three metric pills stagger in, numbers counting 0 → N (1.2s) → slide strip rises from bottom (1.9s) → slide auto-rotation starts (~2.4s). Scrolling/tapping during the sequence must work throughout.

- [ ] **Step 3: Scroll — intelligence cascade**

Same session, scroll down. When the Trip Intelligence section top passes 82% of screen height: header fades, fact cards cascade with 80ms stagger (12pt rise + spring), Travel DNA badge pops last (0.6 → overshoot → 1.0). On larger screens the section top may already sit above the threshold at rest — the cascade then fires on the first scroll movement; that is acceptable per the spec's "hero and cascade are independent".

- [ ] **Step 4: Reopen — instant**

Close and reopen the same blog. Expected: hero and intelligence section fully visible immediately; no animation; rotation starts right away.

- [ ] **Step 5: Classic → Highlights toggle on an unseen blog**

Clear the seen list (command above), relaunch, switch the blog to Classic, then toggle to Highlights via the toolbar style button. Expected: the full reveal plays.

- [ ] **Step 6: Edit-mode interruption mid-sequence**

Clear the seen list, relaunch, open the blog and tap Edit within ~1.5s. Expected: every hero element snaps to final state instantly; intelligence cards visible in edit chrome. Close and reopen the blog: the reveal replays (interruption did not mark it seen).

- [ ] **Step 7: Reduce Motion**

Enable Settings → Accessibility → Motion → Reduce Motion in the simulator. Clear the seen list, relaunch, open the blog. Expected: same element timing, but opacity fades only — no slide-up, no Ken Burns scale, no badge pop, and pill numbers appear final without counting.

- [ ] **Step 8: Report results**

Report each scenario pass/fail with what was observed. Any failure: fix in `RecapBlogPageView.swift`, rebuild, re-run the failed scenario, then commit the fix with a `fix:` message.
