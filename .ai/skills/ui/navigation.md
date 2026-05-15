# UI Skill: Navigation Patterns

## ZStack Overlay System (primary navigation)

Top-level screens are NOT pushed via NavigationLink. They are stacked as full-screen overlays using `ZStack` + `zIndex` + `opacity` in `ContentView`.

### zIndex layers
| Layer | zIndex | Managed by |
|-------|--------|-----------|
| Landing | 0 | always visible as base |
| Camera | 2 | `showCamera` |
| My Blogs | 3 | `showMyBlogs` |
| Places Visited | 4 | `showPlacesVisited` |
| Trips | 5 | `showTrips` |
| Blog Detail | 10 | `showBlogDetail` |
| Loading/Scanning | 20 | `showScanning` |

### Rules
- Use `opacity(show ? 1 : 0)` + `.allowsHitTesting(show)` to show/hide overlays
- Dismiss via `onDismissOverlay` callback passed down as a closure, or `@Environment(DismissToLandingKey.self)`
- Never use `NavigationLink` to present a top-level screen — it breaks the overlay stack
- MapKit overlays: keep mounted after dismiss (`tripsViewKeepMounted`) for 500ms GPU drain before releasing

### In-flow navigation (within an overlay)
Use `NavigationStack` inside each overlay for drill-down flows (e.g., trip → day → place → photo detail).

## Modal patterns
| Pattern | API | When to use |
|---------|-----|-------------|
| Sheet | `.sheet(isPresented:)` | Settings, share, auth, permissions |
| Full screen | `.fullScreenCover(isPresented:)` | Camera capture, video export |
| Bottom sheet | `AppChromeShapes.pullUpTopSurface()` + manual drag | Custom pull-up panels |
| Alert | `.alert(isPresented:)` | Confirmations, errors |

## Custom dismiss environment key
```swift
// Reading in a deeply nested view:
@Environment(DismissToLandingKey.self) private var dismissToLanding
// Triggering:
dismissToLanding()
```
