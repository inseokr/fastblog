# Architecture Skill: Async/Await & Concurrency

## Rules

### All @Published mutations must be on the main thread
- Mark every ViewModel `@MainActor` at the class level — this is sufficient
- Inside a non-isolated async function that updates UI state, use `await MainActor.run { ... }`
- Never use `DispatchQueue.main.async` for this — use `@MainActor` or `await MainActor.run`

### Task cancellation in loops
Always guard long loops:
```swift
for item in items {
    guard !Task.isCancelled else { return }
    await process(item)
}
```

### Fire-and-forget tasks
Acceptable for analytics, background sync — not for critical paths:
```swift
Task { await AppAnalytics.shared.flush() }       // OK: analytics
Task { await createdRecapStore.syncFromCloud() }  // OK: background sync
```
For critical paths (blog save, photo upload), await the result and handle errors.

### Timing / delays
Use `Task.sleep` (not `DispatchQueue.asyncAfter`):
```swift
try? await Task.sleep(for: .milliseconds(500))  // GPU drain after map dismiss
try await Task.sleep(for: .seconds(1))           // Must propagate cancellation
```

### Debouncing
For search / rapid-input, use a `Task` that gets cancelled and re-created:
```swift
private var searchTask: Task<Void, Never>?

func onQueryChanged(_ query: String) {
    searchTask?.cancel()
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await performSearch(query)
    }
}
```

## Async error handling
```swift
func loadData() {
    Task {
        do {
            let result = try await service.fetch()
            self.data = result
        } catch is CancellationError {
            // ignore — task was cancelled intentionally
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

## Data flow: async operations
```
User action
  → ViewModel method (sync entry point)
    → Task { } (async boundary)
      → Service.method() async throws
        → APIManager.shared.get/post()
          → URLSession async
      ← Result / throws
    ← @Published update (on MainActor)
  ← View re-renders
```
