# Architecture Skill: State Ownership

## State tiers

| Tier | Mechanism | Scope |
|------|-----------|-------|
| Transient UI | `@State` | Single view, reset on recreation |
| Feature state | `@Published` in ViewModel | Feature subtree |
| App-wide | `@EnvironmentObject` | Whole app via `ContentView` |
| Persisted simple | `@AppStorage("blogify.key")` | Cross-launch primitives |
| Persisted complex | `CreatedRecapBlogStore` (disk + cloud) | Blogs, drafts |

## @StateObject vs @ObservedObject
- `@StateObject` — the view **owns** the ViewModel; use at the view that creates it
- `@ObservedObject` — the view **borrows** it; use in child views that receive it from a parent
- Never re-wrap a received ViewModel in a new `@StateObject`

## ViewModel template
```swift
@MainActor
final class FeatureViewModel: ObservableObject {
    // MARK: - Published State
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let service: FeatureService

    init(service: FeatureService = .shared) {
        self.service = service
    }

    // MARK: - Actions
    func loadItems() {
        isLoading = true
        Task {
            do {
                items = try await service.fetchItems()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
```
