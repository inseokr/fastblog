# Alignment rubric (doubtful)

Use when the audit is non-trivial (features, UI flows, multi-file changes).

## Severity

| Level | Definition | Action |
|-------|------------|--------|
| **Blocker** | User cannot achieve stated goal; spec violation; build broken | Fix before ship |
| **Should fix** | Goal achievable but fragile, wrong layer, skill violation | Fix unless user accepts risk |
| **Accepted risk** | Edge case unlikely or explicitly deferred | Document; user confirms |
| **Out of scope** | Nice-to-have not in intent | Do not implement unless user expands |

## UI / navigation checks

- Entry point matches spec (who opens what, from where)
- Back/dismiss behavior matches platform and app patterns
- Empty, loading, error states: do they match intent or leave dead ends?
- Visual tokens: palette, typography, spacing vs `.ai/skills/ui/`

## Swift / fastblog checks

- MVVM boundaries respected (`.ai/skills/architecture/mvvm/`)
- New `.swift` files registered in `project.pbxproj` if applicable
- Vision APIs guarded for iOS version targets in `CLAUDE.md`
- Async work: cancellation, main-thread UI (`.ai/skills/architecture/async.md`)

## Spec drift signals

- Plan task marked done but acceptance criterion not observable in app
- "Similar to mockup" without naming what differs
- Renamed user-facing strings without user request
- Removed behavior that existed before without explicit approval

## Evidence types (prefer strongest available)

1. Command output (build, test)
2. Code path trace (file + line behavior)
3. Screenshot/simulator description (only if you ran or user provided)
4. Reasoning from code (label as **inferred**, not verified)
