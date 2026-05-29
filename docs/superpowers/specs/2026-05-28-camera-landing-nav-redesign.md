# Camera Landing & Bottom Nav Redesign

**Date:** 2026-05-28  
**Branch:** CovaV1

---

## Overview

Replace the existing `LandingView` (scan circle, "Tap to Blog") as the app's home screen with the in-app camera (`CameraCaptureView`). Add a persistent bottom navigation bar (My Blogs | Camera | My Places) across all three primary screens. Migrate "Tap to Blog" and "Latest Edits" into My Blogs. Replace X dismiss buttons on My Blogs and My Places with a Settings gear.

---

## Changes by Screen

### 1. ContentView

- **Camera is the base layer.** `CameraCaptureView` replaces `NavigationStack { LandingView(...) }` as the root of the ZStack. It is always mounted and visible by default.
- `LandingView` is removed. Its state properties related to the scan flow (`pendingShowTripsWhenIdle`, `showTrips`, etc.) remain in `ContentView` and are triggered from My Blogs instead.
- Overlays (`showSeeAll` → My Blogs, `showPlacesVisited` → My Places, `showTrips`, `selectedCreatedRecap`, loading scan) keep their existing ZStack zIndex layers unchanged.
- Post-camera toast (`postCameraToastMessage`) stays in `ContentView` — it currently appears over LandingView but will now appear over the camera base layer.
- A shared `@State var showSettingsFromNav = false` is added to `ContentView` and a `showSettings` callback is passed down to My Blogs and My Places (not Camera — camera has no settings button) so both can present `SettingsView` as a sheet.

### 2. CameraCaptureView

**What changes:**
- Remove the X (xmark) button from the top-left. Camera is now the home screen — there is nothing to close back to.
- Top-right controls (flip camera, flash, save-to-photos) are **unchanged**.
- `shutterBar` (gallery icon + shutter/reel button + photo counter + `captureModePicker`) shifts up to leave comfortable padding above the bottom nav bar. Implemented by adding `.safeAreaInset(edge: .bottom)` or bottom padding equal to the nav bar height (~62 pt) + breathing room (~8 pt).
- A `BottomNavBar` component is added at the bottom. Camera tab is active.
- Tapping My Blogs in the nav sets `showSeeAll = true` (via callback from `ContentView`). Tapping My Places sets `showPlacesVisited = true`.

**What does NOT change:**
- The "Capturing Vibe" pill, zoom indicator, reel stop-mode picker — all top-area overlays untouched.
- Post-capture preview overlay (`isCaptionModeActive`) — untouched.
- Swipe-down-to-dismiss gesture on camera — removed (no longer needed since camera is home).

### 3. MyBlogsProfileView

**What changes:**
- Top-left toolbar item: `xmark` button → `gearshape.fill` button that presents `SettingsView` as a sheet.
- **Tap to Blog banner** added at the top of the scrollable content area (above Latest Edits), below the search bar. It's a compact blue-tinted row with a `+` icon, title "Tap to Blog", subtitle "Scan your photos into a blog". Tapping it calls `onTapToBlog()` — the same callback currently handled by `LandingView`.
- **Latest Edits carousel** (`recentRecapsSection` from `LandingView`) is moved into the scrollable content, directly below the Tap to Blog banner. Only shown when `createdRecapStore.displayRecents` is non-empty.
- Map icon and search bar **maintain their current position** — they are already a persistent bottom overlay (`ZStack(alignment: .bottom)`). They now sit above the `BottomNavBar` instead of at the raw screen bottom. Achieved by adding `.safeAreaInset(edge: .bottom)` equal to nav bar height on the existing bottom stack, or by padding the bottom of the `ZStack`.
- `BottomNavBar` component added at the very bottom. My Blogs tab is active.
- `onDismissCover` callback is no longer used for the top-left button. The gear replaces it. The overlay is dismissed by tapping Camera or My Places in the bottom nav (which routes through `ContentView`).

**What does NOT change:**
- Search bar appearance, search overlay, map button — same visual, same behavior.
- Country sections, country drill-down page, Manage sheet — untouched.
- `chevron.left` back button on country sub-page — untouched.

### 4. PlacesVisitedStandaloneView (PlacesVisitedView)

**What changes:**
- Top-left toolbar item: `xmark` button → `gearshape.fill` button that presents `SettingsView` as a sheet.
- `BottomNavBar` component added at the bottom. My Places tab is active.
- Map icon / share button / filter menu in top-right toolbar — **unchanged**.
- `onDismiss` / `standaloneOnDismiss` — overlay is now dismissed by tapping Camera or My Blogs in the nav.

**What does NOT change:**
- Place list, search, year/country filters — all untouched.
- Place detail modal, share sheet — untouched.

---

## New Component: BottomNavBar

A shared SwiftUI view placed in `Views/Components/BottomNavBar.swift`.

```
BottomNavBar
  activeTab: BottomNavTab  (.myBlogs | .camera | .myPlaces)
  onMyBlogs:  () -> Void
  onCamera:   () -> Void
  onMyPlaces: () -> Void
```

- Three equal-width items: My Blogs (house/book icon) | Camera (camera icon) | My Places (pin icon).
- Active tab: white icon + white label + small dot indicator below label.
- Inactive tabs: icon + label at ~40% white opacity.
- Background: `Color(red: 5/255, green: 10/255, blue: 48/255)` (app background) with a top hairline border `Color.white.opacity(0.12)`.
- Height: ~62 pt content + `.safeAreaPadding(.bottom)` for home indicator.
- Uses existing icon assets: `MyBlogsIcon` image asset for My Blogs, `camera.fill` SF Symbol for Camera, `MyPlacesIcon` image asset for My Places.

---

## SettingsView Accessibility

`SettingsView` is currently a `private struct` inside `LandingView.swift`. It needs to be accessible from My Blogs and My Places (camera has no settings button — clean top bar).

**Approach:** Make it `internal` (remove `private`) and move it to its own file `Views/SettingsView.swift`, or keep it in `LandingView.swift` but change the access level. All three screens present it as a `.sheet`.

Required environment objects for `SettingsView`: `AuthService`, `PhotosAuthorizationManager`, `CreatedRecapBlogStore` — these are already in the environment at both call sites.

---

## LandingView Removal

- `LandingView.swift` can be deleted after its responsibilities are redistributed:
  - `recentRecapsSection` → moved into `MyBlogsProfileView`
  - `onTapToBlog` callback → triggered from the new Tap to Blog banner in My Blogs
  - `bottomMenuBar` → replaced by `BottomNavBar` component
  - `SettingsView`, `SettingsHelpSheet`, `NotificationsOverlayView` — moved or kept accessible
  - Post-camera toast display — stays in `ContentView`
  - `ScanningAnimationView` (scan circle) — no longer on home; still used inside TripsView

---

## Files to Create
- `Views/Components/BottomNavBar.swift`
- `Views/SettingsView.swift` (extracted from LandingView.swift)

## Files to Modify
- `ContentView.swift` — base layer swap, settings state, nav callbacks
- `Views/TripsView.swift` — `CameraCaptureView`: remove X, add bottom nav, shift shutter bar up
- `Views/MyBlogsProfileView.swift` — gear top-left, Tap to Blog banner, Latest Edits section, bottom nav, safeArea adjustment for map/search stack
- `Views/PlacesVisitedView.swift` — gear top-left, bottom nav
- `Views/LandingView.swift` — delete (or keep temporarily during migration)
- `fastblog.xcodeproj/project.pbxproj` — register new Swift files

---

## Out of Scope
- Notifications overlay (bell icon) — removed with LandingView; not part of this redesign
- Any changes to TripsView, RecapBlogPageView, StoryBook — untouched
- Auth flow — untouched
