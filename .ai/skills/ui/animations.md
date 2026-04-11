# UI Skill: Animation & Transition Conventions

## Standard animation values

| Purpose | Code |
|---------|------|
| Interactive spring (buttons, cards) | `.spring(response: 0.4, dampingFraction: 0.75)` |
| Screen fade in/out | `.easeInOut(duration: 0.3)` |
| Quick dismiss | `.easeOut(duration: 0.2)` |
| Slow reveal | `.easeIn(duration: 0.5)` |
| Selection scale feedback | `.scaleEffect(isSelected ? 1.05 : 1.0)` + spring |

## Transition types

| Situation | Transition |
|-----------|-----------|
| Modal appearance | `.transition(.opacity)` |
| MapKit-backed views | `.transition(.identity)` — keeps view mounted to allow Metal/GPU cleanup |
| Sliding panels | `.transition(.move(edge: .bottom))` |

## Sequenced / phased animations
Use `Task.sleep()` between `withAnimation` calls for multi-step sequences:
```swift
withAnimation(.easeInOut(duration: 0.5)) { phase = .one }
try? await Task.sleep(for: .milliseconds(700))
withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { phase = .two }
```
Do NOT use `DispatchQueue.main.asyncAfter` — use `Task.sleep` in async context.

## Preference-based scroll effects
To react to scroll position (parallax, title hide/reveal):
1. Attach a `GeometryReader` in `.background` to measure child min Y
2. Report via a `PreferenceKey` (e.g., `TitleMinYPreferenceKey`)
3. Read with `.onPreferenceChange` in the parent
4. Use `TrackableScrollView` (UIViewRepresentable) for continuous offset tracking

## Rules
- Never animate inside `body` directly — animate on state change via `.animation(_:value:)` or `withAnimation { }`
- Always bind animations to a specific `value:` parameter to avoid unintended animations on unrelated state changes
- Prefer `@State` transition flags over `matchedGeometryEffect` unless truly needed (matchedGeometryEffect has performance cost)
