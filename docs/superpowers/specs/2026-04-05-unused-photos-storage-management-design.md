# Unused Photos — Storage Management

**Date:** 2026-04-05
**Status:** Approved

---

## Overview

A new screen accessible from Blog Settings that shows all photos belonging to a blog that are not currently included in the blog output (`isIncluded: false`). Users can browse these photos, filter by day, select multiple, and delete them to free up storage on their device or from Bloggo's in-app gallery.

---

## Entry Point

A new row added to `BlogSettingsSheet`'s settings list:

- Label: "Unused Photos" with a storage/photo system image
- Tap navigates via `NavigationLink` into `StorageManagementView`, pushing it onto the existing `NavigationStack` inside `BlogSettingsSheet`
- No new NavigationStack or sheet required

---

## Screen: StorageManagementView

### Navigation Bar

| Mode | Leading | Center | Trailing |
|---|---|---|---|
| Normal | `‹` (chevron only, no text) | "Unused Photos" | "Select" |
| Select | "Cancel" | N selected | "Select All" |

- "Select" button activates select mode
- "Cancel" exits select mode, clears all selections
- "Select All" selects every photo currently visible (respects active day filter)

### Photo Grid

- 3-column `LazyVGrid` with 2pt spacing, matching the `ManagePhotosView` layout
- Displays all photos from the blog where `isIncluded == false`
- Photos extend to the bottom edge of the screen, scrolling behind the floating bottom buttons
- In select mode: selected photos show a filled blue checkmark (bottom-right); unselected photos are dimmed to ~40% opacity with an empty circle indicator

### Bottom Floating Buttons (select mode only)

Both buttons are positioned as an overlay (`ZStack`) floating over the grid, with a frosted glass backdrop (`.ultraThinMaterial` or dark semi-transparent background).

- **Bottom-left:** Filter button — `line.3.horizontal.decrease.circle` SF Symbol
  - White when no filter is active
  - Blue (`#0A84FF`) with blue-tinted background when a filter is active or the dropdown is open
  - Tapping toggles the filter dropdown overlay
- **Bottom-right:** Trash button — `trash` SF Symbol in red (`#FF453A`) with dark red background
  - Tapping triggers the delete confirmation flow for all selected photos

### Filter Dropdown

- Appears as an overlay anchored **above the filter button**, bottom-left
- Does **not** push or shift the photo grid
- Background: blurred dark material (`rgba(28,28,30,0.96)` + backdrop blur)
- Header label: "FILTER BY DAY"
- Each row: colored dot · "Day N" · date (e.g. "Mar 15") · checkmark if active
- Days are derived from `draft.days` — one row per day that has at least one excluded photo
- Selecting a day filters the grid to show only photos from that day's place stops
- Tapping outside the dropdown dismisses it

---

## Delete Flow

Delete is triggered either by the Trash button (batch) or by individual photo actions (if added later). The flow branches based on photo source type.

### Determining Photo Source

- **In-app camera photo:** `photo.localIdentifier == nil` (stored in `InAppCameraPhotoStore`, identified by `imageName` being a UUID-based filename in the app's documents directory)
- **iPhone library photo:** `photo.localIdentifier != nil` (references a PHAsset in the system photo library)

### Single Photo Delete

| Source | Dialog | CTA |
|---|---|---|
| In-app camera | "Delete Photo From Bloggo?" · "Removes from Bloggo gallery." | No / Delete |
| iPhone library | "Delete Photo From Phone?" · "Removes from your device." | No / Delete |

### Batch Delete (Trash button)

When photos of multiple source types are selected, show one confirmation per type in sequence:

1. If any **in-app camera** photos are selected → "Delete N Photos From Bloggo?" · "Removes from Bloggo gallery." → No / Delete
2. If any **iPhone library** photos are selected → "Delete N Photos From Phone?" · "Removes from your device." → No / Delete

Each dialog only appears if that type is present in the selection. The user can say "No" to one type while still deleting the other.

### Delete Actions

- **Delete from Bloggo (in-app camera):** Call `InAppCameraPhotoStore.shared.removePhotos(ids:)` with the photo's UUID, and remove the `RecapPhoto` entry from the blog's day/stop data.
- **Delete from Phone (iPhone library):** Use `PHPhotoLibrary.shared().performChanges` to delete the asset via `PHAssetChangeRequest.deleteAssets`. Remove the `RecapPhoto` entry from the blog's day/stop data.
- After deletion, call `onSave()` to persist the updated blog draft.

---

## Data Source

The view receives `draft: RecapBlogDetail` (passed through from `BlogSettingsSheet`). Unused photos are gathered by iterating all `draft.days[*].placeStops[*].photos` and filtering where `isIncluded == false`.

Day filter rows are built from `draft.days` — using the day index and the first photo timestamp in that day to display the date.

---

## Empty State

If no unused photos exist, show a centered message:
- Icon: `photo.on.rectangle` or similar
- Title: "No unused photos"
- Subtitle: "All photos in this blog are included."

---

## Implementation Notes

- `StorageManagementView` takes `@Binding var draft: RecapBlogDetail` and `var onSave: () -> Void`, consistent with how `BlogSettingsSheet` passes data to other sub-views
- Reuse `RecapPhotoThumbnail` for grid cells (consistent with `ManagePhotosView`)
- The view is dark-mode only (`preferredColorScheme(.dark)`) consistent with the rest of the app
- No drag-to-range-select needed (simpler than `ManagePhotosView` — tap to toggle only)
- The filter dropdown dismisses when the user taps outside it (use a clear full-screen tap target behind the dropdown)
