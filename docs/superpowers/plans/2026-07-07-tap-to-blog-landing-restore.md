# Tap to Blog Landing Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the "Tap to Blog" landing screen as the default `.create` tab, moving the in-app camera from a nav tab to an overlay triggered by a top-right camera icon on the landing.

**Architecture:** Three files change. `BottomNavBar.swift` renames the center tab enum case and UI. `ContentView.swift` drops the auto-hide nav machinery, adds a `showCameraOverlay` bool, wires `LandingView` into the `.create` slot, and mounts `CameraCaptureView` as a zIndex-8 overlay. `LandingView.swift` sheds its old bindings and internal overlays, adding two clean callbacks (`onOpenCamera`, `onShowSettings`).

**Tech Stack:** SwiftUI, Swift async/await, existing project architecture (MVVM, ZStack overlay system)

## Global Constraints

- No new files — all changes are in-place edits to existing files
- Do not touch `handleTapToBlog()`, `TripsView`, `RecapBlogPageView`, `LoadingScanView`, `MyBlogsProfileView`, `PlacesVisitedStandaloneView`, `ScanningAnimationView`, or any blog/scan logic
- Animations: spring `response: 0.4, dampingFraction: 0.75`; screen fade `.easeInOut(duration: 0.3)`
- Build command: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -5`
- No new comments unless WHY is non-obvious

---

### Task 1: Rename BottomNavTab `.camera` → `.create` in BottomNavBar.swift

**Files:**
- Modify: `fastblog/Views/Components/BottomNavBar.swift`

**Interfaces:**
- Produces: `BottomNavTab.create` case (replaces `.camera`), `BottomNavBar.onCreate` parameter (replaces `onCamera`)

- [ ] **Step 1: Rename the enum case**

In `fastblog/Views/Components/BottomNavBar.swift`, change:
```swift
enum BottomNavTab: Equatable {
    case myBlogs
    case camera
    case myPlaces
}
```
to:
```swift
enum BottomNavTab: Equatable {
    case myBlogs
    case create
    case myPlaces
}
```

- [ ] **Step 2: Rename the parameter and update center nav item**

Change `BottomNavBar` struct and its center item from:
```swift
struct BottomNavBar: View {
    let activeTab: BottomNavTab
    let onMyBlogs: () -> Void
    let onCamera: () -> Void
    let onMyPlaces: () -> Void
    ...
        navItem(
            tab: .camera,
            label: "Camera",
            icon: .sfSymbol("camera.fill"),
            action: onCamera
        )
```
to:
```swift
struct BottomNavBar: View {
    let activeTab: BottomNavTab
    let onMyBlogs: () -> Void
    let onCreate: () -> Void
    let onMyPlaces: () -> Void
    ...
        navItem(
            tab: .create,
            label: "Create",
            icon: .sfSymbol("plus"),
            action: onCreate
        )
```

- [ ] **Step 3: Build to catch compilation errors from the enum rename**

Run:
```
cd /Users/ybstudio/Desktop/Projects/Bloggo && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: errors about `.camera` and `onCamera` usage in ContentView — that's correct, Task 2 fixes them.

- [ ] **Step 4: Commit BottomNavBar changes**

```bash
git add fastblog/Views/Components/BottomNavBar.swift
git commit -m "rename BottomNavTab .camera→.create, nav label Camera→Create, icon camera.fill→plus"
```

---

### Task 2: ContentView — state cleanup + navigation wiring + camera overlay

**Files:**
- Modify: `fastblog/ContentView.swift`

**Interfaces:**
- Consumes: `BottomNavTab.create` from Task 1
- Produces: `showCameraOverlay: Bool`, `isLandingHomeVisible: Bool`, updated `isHomeBottomNavVisible`, `LandingView` slot in `.create` tab, `CameraCaptureView` at zIndex 8 as overlay

- [ ] **Step 1: Replace state declarations**

At the top of `ContentView`, make these changes:

**Remove these lines (lines ~23–27, 46):**
```swift
@State private var homeTab: BottomNavTab = .camera
/// Immersive home camera hides the tab bar until the user taps the back chevron.
@State private var isHomeBottomNavRevealed = false
@State private var homeBottomNavAutoHideTask: Task<Void, Never>?
private static let homeBottomNavAutoHideSeconds: UInt64 = 4
...
@AppStorage("bloggo.hasSeenCameraTooltip") private var hasSeenCameraTooltip = false
```

**Replace with:**
```swift
@State private var homeTab: BottomNavTab = .create
@State private var showCameraOverlay = false
```

- [ ] **Step 2: Update `isHomeBottomNavVisible` and rename `isCameraHomeVisible`**

Change:
```swift
/// Tab bar: hidden on default camera, My Places place viewer, and share studio; optional on camera after back chevron.
private var isHomeBottomNavVisible: Bool {
    showsHomeChrome && !suppressHomeBottomNav && (homeTab != .camera || isHomeBottomNavRevealed)
}

private var isCameraHomeVisible: Bool {
    homeTab == .camera && showsHomeChrome
}
```

To:
```swift
private var isHomeBottomNavVisible: Bool {
    showsHomeChrome && !suppressHomeBottomNav && !showCameraOverlay
}

private var isLandingHomeVisible: Bool {
    homeTab == .create && showsHomeChrome
}
```

- [ ] **Step 3: Simplify `selectHomeTab()`**

Change:
```swift
private func selectHomeTab(_ tab: BottomNavTab) {
    cancelHomeBottomNavAutoHide()
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        if tab == .camera {
            isHomeBottomNavRevealed = false
        }
        homeTab = tab
    }
}
```

To:
```swift
private func selectHomeTab(_ tab: BottomNavTab) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        homeTab = tab
    }
}
```

- [ ] **Step 4: Delete `scheduleHomeBottomNavAutoHide()` and `cancelHomeBottomNavAutoHide()`**

Remove both functions entirely (lines ~463–477 in original):
```swift
private func scheduleHomeBottomNavAutoHide() {
    cancelHomeBottomNavAutoHide()
    homeBottomNavAutoHideTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: Self.homeBottomNavAutoHideSeconds * 1_000_000_000)
        guard !Task.isCancelled else { return }
        guard homeTab == .camera, isHomeBottomNavRevealed else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isHomeBottomNavRevealed = false
        }
    }
}

private func cancelHomeBottomNavAutoHide() {
    homeBottomNavAutoHideTask?.cancel()
    homeBottomNavAutoHideTask = nil
}
```

- [ ] **Step 5: Update `rootContent` BottomNavBar call and onChange blocks**

In `rootContent`, change the `BottomNavBar` call:
```swift
BottomNavBar(
    activeTab: homeTab,
    onMyBlogs: { selectHomeTab(.myBlogs) },
    onCamera: { selectHomeTab(.camera) },
    onMyPlaces: { selectHomeTab(.myPlaces) }
)
```
to:
```swift
BottomNavBar(
    activeTab: homeTab,
    onMyBlogs: { selectHomeTab(.myBlogs) },
    onCreate: { selectHomeTab(.create) },
    onMyPlaces: { selectHomeTab(.myPlaces) }
)
```

Change the `onChange(of: homeTab)` block:
```swift
.onChange(of: homeTab) { _, newTab in
    if newTab == .camera {
        isHomeBottomNavRevealed = false
    } else {
        cancelHomeBottomNavAutoHide()
    }
    if newTab != .myPlaces {
        suppressHomeBottomNav = false
    }
}
```
to:
```swift
.onChange(of: homeTab) { _, newTab in
    if newTab != .myPlaces {
        suppressHomeBottomNav = false
    }
}
```

Remove the `onChange(of: isHomeBottomNavRevealed)` block entirely:
```swift
.onChange(of: isHomeBottomNavRevealed) { _, revealed in
    if revealed {
        scheduleHomeBottomNavAutoHide()
    } else {
        cancelHomeBottomNavAutoHide()
    }
}
```

- [ ] **Step 6: Update `onAppear`, `ScanPhotoAccessSheet.onUseCamera`, and `PostOnboardingWelcomeView.onCaptureMoments`**

In `.onAppear`, remove the `isHomeBottomNavRevealed = true` line from the `justFinishedOnboarding` block:
```swift
// Before:
withTransaction(transaction) {
    homeTab = .myBlogs
    isHomeBottomNavRevealed = true
}
// After:
withTransaction(transaction) {
    homeTab = .myBlogs
}
```

In `ScanPhotoAccessSheet`, change `onUseCamera`:
```swift
// Before:
onUseCamera: {
    showScanPhotoAccessSheet = false
    cancelPendingFindPastTripsScan()
    hasSeenCameraTooltip = true
    selectHomeTab(.camera)
    isHomeBottomNavRevealed = true
},
// After:
onUseCamera: {
    showScanPhotoAccessSheet = false
    cancelPendingFindPastTripsScan()
    showCameraOverlay = true
},
```

In `PostOnboardingWelcomeView`, change `onCaptureMoments`:
```swift
// Before:
onCaptureMoments: {
    cancelPendingFindPastTripsScan()
    showPostOnboardingWelcome = false
    hasSeenCameraTooltip = true
    selectHomeTab(.camera)
    isHomeBottomNavRevealed = true
},
// After:
onCaptureMoments: {
    cancelPendingFindPastTripsScan()
    showPostOnboardingWelcome = false
    showCameraOverlay = true
},
```

- [ ] **Step 7: Update tab callbacks in `homeTabsLayer`**

In `MyBlogsProfileView` slot:
```swift
// Before:
onNavCamera: {
    selectHomeTab(.camera)
},
// After:
onNavCamera: {
    selectHomeTab(.create)
},
```

In `PlacesVisitedStandaloneView` slot:
```swift
// Before:
onDismiss: { selectHomeTab(.camera) },
// After:
onDismiss: { selectHomeTab(.create) },
```

- [ ] **Step 8: Update `onChange(of: isCameraHomeVisible)` in `body`**

```swift
// Before:
.onChange(of: isCameraHomeVisible) { _, visible in
// After:
.onChange(of: isLandingHomeVisible) { _, visible in
```

- [ ] **Step 9: Update `considerPresentingNewMomentsBannerOnCamera()`**

```swift
// Before:
private func considerPresentingNewMomentsBannerOnCamera() {
    guard isCameraHomeVisible else { return }
// After:
private func considerPresentingNewMomentsBannerOnCamera() {
    guard isLandingHomeVisible else { return }
```

- [ ] **Step 10: Replace CameraCaptureView tab slot with LandingView + add camera overlay**

In `homeTabsLayer`, replace the CameraCaptureView NavigationStack block (the one with `.opacity(homeTab == .camera ? 1 : 0)`) with:

```swift
NavigationStack {
    LandingView(
        selectedCreatedRecap: $selectedCreatedRecap,
        tripsViewModel: tripsViewModel,
        onTapToBlog: handleTapToBlog,
        onOpenCamera: { showCameraOverlay = true },
        onShowSettings: { showSettingsFromNav = true }
    )
    .environmentObject(createdRecapStore)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.opacity(homeTab == .create ? 1 : 0)
.allowsHitTesting(homeTab == .create)
.zIndex(homeTab == .create ? 1 : 0)
```

Then, after the MyBlogsProfileView block and before the TripsView block, add the camera overlay:

```swift
if showCameraOverlay {
    NavigationStack {
        CameraCaptureView(
            tripsViewModel: tripsViewModel,
            postDismissToast: { msg in
                presentPostCameraToast(msg)
            },
            onWillCaptureMoment: {
                dismissPostCameraToast()
            },
            onDismissOverlay: { showCameraOverlay = false },
            onNavigateToBlog: { sourceTripId in
                if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId }) {
                    selectedCreatedRecap = blog
                }
            },
            homeBottomNavRevealed: nil,
            isTabActive: true
        )
        .environmentObject(createdRecapStore)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .transition(.identity)
    .zIndex(8)
}
```

- [ ] **Step 11: Build and verify**

```
cd /Users/ybstudio/Desktop/Projects/Bloggo && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 12: Commit**

```bash
git add fastblog/ContentView.swift
git commit -m "restore landing tab: drop nav auto-hide, wire LandingView to .create, camera as zIndex-8 overlay"
```

---

### Task 3: LandingView — remove old bindings/overlays, update top bar

**Files:**
- Modify: `fastblog/Views/LandingView.swift`

**Interfaces:**
- Consumes: `onOpenCamera: () -> Void`, `onShowSettings: () -> Void` (new callbacks)
- Produces: simplified `LandingView` struct (no `showProfile`, `showSeeAll`, `showCameraFromHome`, `postCameraToastMessage`, `showTrips`, `showPlacesVisited` bindings)

- [ ] **Step 1: Update struct signature — remove old bindings, add callbacks, remove state**

Replace the current struct top (from `struct LandingView: View {` through the last `@State` line before `private let landingBackground`) with:

```swift
struct LandingView: View {
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @ObservedObject var tripsViewModel: TripsViewModel
    var onTapToBlog: (() -> Void)? = nil
    var onOpenCamera: () -> Void
    var onShowSettings: () -> Void
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var splashManager: SplashStateManager

    @State private var circlesScale: CGFloat = 0.001
    @State private var showScanIcon: Bool = false
    @State private var ctaTextOpacity: Double = 0
    @State private var showAlternateText = false
    private let textCycleTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    @StateObject private var photoAuth = PhotosAuthorizationManager()
```

(Removed: `showTrips`, `showProfile`, `showSeeAll`, `showPlacesVisited`, `showCameraFromHome`, `postCameraToastMessage` bindings; `showSettings`, `showAuth`, `showNotifications`, `avatarImageData`, `showNewMomentsAlert`, `newMomentsAlertBlogTitle`, `newMomentsAlertBlogId`, `newMomentsAlertDayIndex` state; `authService` EnvironmentObject)

- [ ] **Step 2: Update the `body` top bar**

Replace the current top bar `HStack` (inside the VStack that has `Spacer()` + `recentRecapsSection` + `bottomMenuBar`) with:

```swift
HStack {
    Button {
        onShowSettings()
    } label: {
        Image(systemName: "gearshape.fill")
            .font(.title2)
            .foregroundColor(.white)
    }
    Spacer()
    Button {
        onOpenCamera()
    } label: {
        Image(systemName: "camera.fill")
            .font(.title2)
            .foregroundColor(.white)
    }
}
.padding(.horizontal, 20)
.padding(.top, 8)
.padding(.bottom, 12)
```

- [ ] **Step 3: Remove `bottomMenuBar` from body VStack**

In the VStack that reads:
```swift
VStack(spacing: 0) {
    HStack { ... } // top bar
    Spacer()
    recentRecapsSection
    bottomMenuBar    // ← remove this line
}
```

Remove `bottomMenuBar` so the VStack ends with `recentRecapsSection`.

- [ ] **Step 4: Remove overlays from body ZStack**

Remove these three blocks from the body ZStack:

**1. AuthView overlay:**
```swift
if showAuth {
    AuthView(onAuthenticated: {
        showProfile = true
        showAuth = false
    }, onDismiss: {
        showAuth = false
    })
    .environmentObject(authService)
    .transition(.move(edge: .trailing))
    .zIndex(10)
}
```

**2. NotificationsOverlayView:**
```swift
NotificationsOverlayView(onDismiss: {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showNotifications = false }
})
.offset(x: showNotifications ? 0 : UIScreen.main.bounds.width)
.opacity(showNotifications ? 1 : 0)
.allowsHitTesting(showNotifications)
.animation(.spring(response: 0.4, dampingFraction: 0.9), value: showNotifications)
.zIndex(10)
```

**3. Post-camera toast banner:**
```swift
if let toastMsg = postCameraToastMessage {
    VStack { ... }
    .transition(.move(edge: .top).combined(with: .opacity))
    .zIndex(15)
}
```

- [ ] **Step 5: Remove body modifiers that reference removed state**

Remove these `.sheet` and `.alert` modifiers from the body:

```swift
.sheet(isPresented: $showSettings) {
    SettingsView()
    .environmentObject(authService)
    .environmentObject(photoAuth)
    .environmentObject(createdRecapStore)
}
```

```swift
.alert(
    "New moments added to \"\(newMomentsAlertBlogTitle)\"",
    isPresented: $showNewMomentsAlert
) { ... } message: { ... }
```

```swift
.onChange(of: postCameraToastMessage) { _, msg in ... }
```

```swift
.onChange(of: authService.currentUser?.id) { _, _ in
    avatarImageData = authService.profileImageData
}
```

- [ ] **Step 6: Update `onAppear`**

Remove `avatarImageData = authService.profileImageData` from `onAppear`. The block becomes:

```swift
.onAppear {
    AppAnalytics.track(.appOpen)
    if splashManager.phase == .done {
        circlesScale = 1.0
        showScanIcon = true
        ctaTextOpacity = 1
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                circlesScale = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            showScanIcon = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.55)) {
                    ctaTextOpacity = 1
                }
            }
        }
    }
}
```

- [ ] **Step 7: Remove `bottomMenuBar` computed var**

Delete the entire `private var bottomMenuBar: some View { ... }` computed property.

- [ ] **Step 8: Update the `#Preview`**

Replace the preview with:

```swift
#Preview {
    NavigationStack {
        LandingView(
            selectedCreatedRecap: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            onOpenCamera: {},
            onShowSettings: {}
        )
        .environmentObject(CreatedRecapBlogStore.shared)
        .environmentObject(SplashStateManager())
    }
}
```

- [ ] **Step 9: Build — full clean build**

```
cd /Users/ybstudio/Desktop/Projects/Bloggo && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 10: Commit**

```bash
git add fastblog/Views/LandingView.swift
git commit -m "simplify LandingView: drop old bindings/overlays, add onOpenCamera+onShowSettings callbacks, update top bar"
```

---

## Self-Review Against Spec

### Spec coverage check

| Spec requirement | Covered by |
|---|---|
| `BottomNavTab`: rename `.camera` → `.create` | Task 1 Step 1 |
| Center nav label "Create", icon `plus` | Task 1 Step 2 |
| Default tab `.create` | Task 2 Step 1 |
| `showCameraOverlay` state | Task 2 Step 1 |
| `.create` slot: `LandingView` with 5 params | Task 2 Step 10 |
| Camera overlay: zIndex 8, `onDismissOverlay: { showCameraOverlay = false }` | Task 2 Step 10 |
| Remove auto-hide machinery + `hasSeenCameraTooltip` | Task 2 Steps 1, 4 |
| `isHomeBottomNavVisible`: `!showCameraOverlay` instead of camera logic | Task 2 Step 2 |
| `isLandingHomeVisible`: fires on `.create` | Task 2 Step 2 |
| `selectHomeTab()` cleanup | Task 2 Step 3 |
| `onChange(of: homeTab)` cleanup | Task 2 Step 5 |
| `onNavCamera` → `selectHomeTab(.create)` | Task 2 Step 7 |
| `PlacesVisitedStandaloneView.onDismiss` → `.create` | Task 2 Step 7 |
| `ScanPhotoAccessSheet.onUseCamera` → `showCameraOverlay` | Task 2 Step 6 |
| `PostOnboardingWelcomeView.onCaptureMoments` → `showCameraOverlay` | Task 2 Step 6 |
| LandingView bindings removed | Task 3 Step 1 |
| `onOpenCamera`, `onShowSettings` callbacks | Task 3 Steps 1, 2 |
| Top bar: gear left → `onShowSettings`, camera right → `onOpenCamera` | Task 3 Step 2 |
| `bottomMenuBar` removed | Task 3 Steps 3, 7 |
| AuthView, NotificationsOverlayView, toast overlays removed | Task 3 Step 4 |
| Internal settings sheet + new-moments alert removed | Task 3 Step 5 |
| `newMomentsBannerBottomInset` stays at 32 | Not changed — already correct |
| `handleTapToBlog()` unchanged | Not touched |
| `recentRecapsSection` + `onTapToBlog` kept | Kept in Task 3 |

### Placeholder scan
No TBD, TODO, or "similar to" references. All code blocks are complete.

### Type consistency
- `BottomNavTab.create` defined in Task 1, consumed in Tasks 2 and 3
- `LandingView(selectedCreatedRecap:tripsViewModel:onTapToBlog:onOpenCamera:onShowSettings:)` defined in Task 3 Step 1, consumed in Task 2 Step 10
- `showCameraOverlay` defined in Task 2 Step 1, consumed in Steps 2, 6, 10
- `isLandingHomeVisible` defined in Task 2 Step 2, consumed in Steps 8, 9
- `selectHomeTab(.create)` — `.create` case defined in Task 1
