# Code Skill: Naming Conventions

## File naming
| Type | Pattern | Examples |
|------|---------|---------|
| View | `{Feature}View.swift` | `TripsView.swift`, `RecapBlogPageView.swift` |
| Sheet/modal | `{Feature}Sheet.swift`, `{Feature}Modal.swift` | `BlogSettingsSheet.swift`, `FindMoreTripsSheet.swift` |
| ViewModel | `{Feature}ViewModel.swift` | `TripsViewModel.swift`, `StoryBookViewModel.swift` |
| Service | `{Feature}Service.swift` | `AuthService.swift`, `GeocodingService.swift` |
| Manager | `{Feature}Manager.swift` | `APIManager.swift`, `GoogleAuthManager.swift` |
| Model | `{Noun}.swift` | `TripDraft.swift`, `PlaceStop.swift`, `RecapPhoto.swift` |
| Component | `{Component}View.swift`, `{Component}Card.swift` | `PlaceCardView.swift`, `ReminderCardView.swift` |

## Type naming (PascalCase)
- Structs/Classes: `TripDraft`, `RecapBlogDetail`, `PlaceStop`
- Enums: `MockScanState`, `CloudState`, `OwnerScope`
- Nested types scoped to parent: `ShareYourBlogSheetPhase`, `PlaceCardView.CardStyle`
- Preference keys: `TitleMinYPreferenceKey`, `CoverHeroTitleHeightPreferenceKey`
- Environment keys: `DismissToLandingKey`, `StoryFontThemeKey`

## Property naming
| Category | Convention | Examples |
|----------|-----------|---------|
| Boolean state | `is`, `has`, `show`, `should` prefix | `isLoading`, `hasCompletedOnboarding`, `showTrips`, `shouldAnimateMap` |
| Published arrays | Plural noun | `tripDrafts`, `blogDays`, `placeStops` |
| Selections | `selected{Type}` | `selectedCreatedRecap`, `selectedDayIndex` |
| Bindings received | Descriptive of content | `postCameraToastMessage`, `initialDayIndexForRecap` |
| Dev bypass flags | `kDev{Description}` | `kDevBypassToManagePhotos` |

## Function naming
| Category | Convention | Examples |
|----------|-----------|---------|
| Event handlers | `on{Event}()` or `handle{Action}()` | `onTapToBlog()`, `handleDismiss()` |
| Async operations | No suffix — type signature speaks | `func syncFromCloud() async`, `func fetchSignedPhotoURL() async throws` |
| Setup/teardown | `setUp()`, `tearDown()` | |
| Predicates | `is{State}()`, `has{Property}()` | `isDownwardDismissSwipe()` |
| Computed props | Noun form | `var centerCoordinate`, `var defaultBlogTitle` |

## MARK sections
Organize large files with `// MARK: -` comments:
```swift
// MARK: - Published State
// MARK: - Dependencies
// MARK: - Actions
// MARK: - Private Helpers
// MARK: - Lifecycle
```

## Constants
- Persisted `@AppStorage` keys: lowercase dot-namespaced strings — `"blogify.hasCompletedOnboarding"`
- Device/keychain keys: camelCase descriptive name — `pendingDeviceTokenKey`
- Dev flags: `kDev` prefix
