# Tap To Blog Landing Page Restore

**Branch:** TaptoBlogonly  
**Date:** 2026-07-07  
**Status:** Approved

## Summary

Restore the old "Tap To Blog" landing page as the default home screen. The current branch made the in-app camera the default tab; this restores a dedicated landing tab with the pulsating circle CTA and Latest Edits scroll, with My Blogs / Create / My Places in the bottom nav. The in-app camera moves from a nav tab to an overlay triggered by a top-right camera icon on the landing.

---

## Section 1 — Tab System

### `BottomNavTab` enum (`BottomNavBar.swift`)
- Rename `.camera` → `.create`
- Cases: `.myBlogs`, `.create`, `.myPlaces`

### `BottomNavBar` center item
- Label: "Camera" → "Create"
- Icon: `camera.fill` → `plus` (SF Symbol)

### Default tab
- `ContentView.homeTab` initializes to `.create`

---

## Section 2 — ContentView

### New state
- `showCameraOverlay: Bool = false` — controls in-app camera overlay

### Tab content (`.create` slot)
- Replace `CameraCaptureView` with `LandingView`, passing:
  - `onTapToBlog: handleTapToBlog`
  - `onOpenCamera: { showCameraOverlay = true }`
  - `onShowSettings: { showSettingsFromNav = true }`
  - `tripsViewModel`, `selectedCreatedRecap` (for Latest Edits tap)

### Camera overlay
- `CameraCaptureView` stays in `homeTabsLayer` ZStack but only when `showCameraOverlay == true`
- zIndex: 8 (above tabs, below blog detail at 10)
- `onDismissOverlay: { showCameraOverlay = false }`
- Does not affect bottom nav (overlay is above tab content area)

### Bottom nav visibility — simplified
Remove all auto-hide machinery:
- Remove: `isHomeBottomNavRevealed`, `homeBottomNavAutoHideTask`, `homeBottomNavAutoHideSeconds`
- Remove: `scheduleHomeBottomNavAutoHide()`, `cancelHomeBottomNavAutoHide()`
- Remove: `hasSeenCameraTooltip` AppStorage (no longer needed)
- `isHomeBottomNavVisible` simplifies to: `showsHomeChrome && !suppressHomeBottomNav && !showCameraOverlay`
  - `!showCameraOverlay` is required because the camera overlay lives inside `homeTabsLayer` (a VStack sibling of `BottomNavBar`), so without this the nav bar renders visibly below the camera

### New moments banner
- `isCameraHomeVisible` → renamed `isLandingHomeVisible`
- Fires when `homeTab == .create && showsHomeChrome`
- `newMomentsBannerBottomInset` stays at `32` (no change needed — sits inside tab content area above the nav bar by VStack layout)

### `selectHomeTab()` cleanup
- Remove the `isHomeBottomNavRevealed = false` branch that was specific to `.camera`

### `onChange(of: homeTab)` cleanup
- Remove the camera-specific `isHomeBottomNavRevealed` branch

### Callbacks from other tabs
- `MyBlogsProfileView.onNavCamera` → `selectHomeTab(.create)` (was `.camera`)

---

## Section 3 — LandingView

### Bindings removed
| Removed | Reason |
|---|---|
| `showProfile: Binding<Bool>` | My Blogs tab owns profile navigation |
| `showSeeAll: Binding<Bool>` | My Blogs tab owns this |
| `showCameraFromHome: Binding<Bool>` | Replaced by `onOpenCamera` callback |
| `postCameraToastMessage: Binding<String?>` | ContentView owns toast |

### Callbacks added
| Callback | Type | Action |
|---|---|---|
| `onOpenCamera` | `() -> Void` | Top-right camera icon; sets `showCameraOverlay = true` in ContentView |
| `onShowSettings` | `() -> Void` | Top-left gear icon; sets `showSettingsFromNav = true` in ContentView |

### State removed
- `showSettings`, `showAuth`, `showNotifications`
- `avatarImageData`

### Views/overlays removed
- `bottomMenuBar` (3-button row)
- `AuthView` overlay + `showAuth` sheet
- `NotificationsOverlayView` + `showNotifications` state
- Internal settings `.sheet` (ContentView owns it now)
- Bell button from top bar
- Post-camera toast banner (ContentView renders this)
- New-moments `.alert` (ContentView renders the banner)

### Top bar — kept, updated
```
HStack {
    gear icon → onShowSettings()    [top-left]
    Spacer()
    camera.fill icon → onOpenCamera()  [top-right]
}
```

### Core content — kept unchanged
- `scanCTA`: pulsating `ScanningAnimationView` (4 rings, expanding + fading), "Tap to Blog" text above the circle, `SplashIcon` in center
- `circlesScale` spring reveal on appear
- `showScanIcon` delayed reveal
- `ctaTextOpacity` + text cycling timer ("Tap to Blog" / "Blog Your Trips in Seconds" on Pro Max)
- `recentRecapsSection` (Latest Edits horizontal scroll)
- `onTapToBlog` callback wired to `handleTapToBlog()` in ContentView
- `SplashStateManager` EnvironmentObject for splash sync

### Layout
```
ZStack {
    navy background (.ignoresSafeArea)
    scanCTA.offset(y: scanCTAOffsetY)          // centered + slight upward offset
    VStack { Spacer(); recentRecapsSection }   // Latest Edits pinned above nav
    VStack { topBar; Spacer() }                // gear + camera top row
}
```

---

## What Is Not Changing

- `handleTapToBlog()` in ContentView — logic unchanged
- `TripsView` overlay — unchanged
- `RecapBlogPageView` overlay — unchanged
- `LoadingScanView` — unchanged
- `MyBlogsProfileView` tab — unchanged (except `onNavCamera` callback target)
- `PlacesVisitedStandaloneView` tab — unchanged
- `ScanningAnimationView` — unchanged
- All blog creation, scan, and photo logic — unchanged
