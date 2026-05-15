# Architecture Skill: MVVM Layers

## Layering rules (strict)

```
View  (SwiftUI)
 ├─ Renders @Published state from ViewModel
 ├─ Calls ViewModel methods on user interaction
 ├─ Uses @EnvironmentObject for app-wide singletons
 └─ NEVER calls Services directly or holds business logic

ViewModel  (ObservableObject, @MainActor)
 ├─ Owns @Published properties that drive the View
 ├─ Calls Service methods; transforms results into View-ready state
 └─ NEVER imports SwiftUI or touches views directly

Service  (class, singleton: Type.shared)
 ├─ Atomic business logic: networking, persistence, geocoding, auth, analytics
 ├─ May call other Services
 └─ NEVER holds UI state or imports SwiftUI

Model  (struct)
 ├─ Codable, Identifiable, Equatable, Hashable
 ├─ Computed properties and init only
 └─ NEVER calls Services or contains side effects
```

## Key singletons (use these — don't recreate)

| Singleton | Purpose |
|-----------|---------|
| `AuthService.shared` | JWT, sign-in/out, `authState` |
| `CreatedRecapBlogStore.shared` | Blog CRUD + cloud sync |
| `APIManager.shared` | REST with automatic JWT injection |
| `AppAnalytics.shared` | Event tracking with background batching |
| `GeocodingService.shared` | Reverse geocoding + timezone inference |

## Dependency injection
Pass services in ViewModel `init` with a `.shared` default — keeps code testable without over-engineering:
```swift
init(store: CreatedRecapBlogStore = .shared) { self.store = store }
```
