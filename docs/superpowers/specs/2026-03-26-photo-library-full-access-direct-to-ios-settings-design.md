# App Settings — Photo Permission Full Access Flow Design Spec

**Date:** 2026-03-26
**Status:** Pending spec review

---
## Overview
When a user is already granted **Full** photo library access (Photo framework status `.authorized`), tapping **Photo Library Access** in the App Settings "Permissions" section should immediately open the iOS Settings page for this app.

This replaces the current confirmation dialog that offers:
- "Manage Selected Photos"
- "Open iOS Settings"

Rationale: "Selected Photos" is only meaningful for **Limited** photo access; showing it for Full access confuses users.

---
## Current Behavior
In `fastblog/Views/PhotoAccessRow.swift`:
- Photo auth status is managed by `PhotosAuthorizationManager`.
- For `.authorized`:
  - The tap sets `showFullAccessOptions = true`.
  - A `confirmationDialog` is shown with "Manage Selected Photos" and "Open iOS Settings".
- For `.limited`:
  - The row shows two separate tappable areas:
    - "Photo Library Access" -> opens iOS Settings
    - "Selected Photos" -> opens the limited library picker

---
## Proposed Behavior
For `.authorized` ("Full"):
- Tapping **Photo Library Access** should call `openAppSettings()` immediately.
- The confirmation dialog should be **completely removed** in the Full-access state (no intermediate choice UI).

For all other states (unchanged):
- `.limited`: keep the two-row layout, with "Selected Photos" opening the limited picker.
- `.denied` / `.restricted` / `.notDetermined`: keep existing behavior (request access for notDetermined; otherwise open iOS Settings).

---
## UX / UI Details
`PhotoAccessRow` should have:
- No "Manage Selected Photos" option for `.authorized` users.
- A direct transition to iOS Settings when the user taps the row while in `.authorized`.

---
## Implementation Notes
Primary file: `fastblog/Views/PhotoAccessRow.swift`

Changes:
1. Remove the `showFullAccessOptions` state.
2. Remove the `confirmationDialog` modifier from `defaultRow` (it is only needed for the Full-access dialog choices).
3. Update `handleTap()`:
   - In the `case .authorized:` branch, replace `showFullAccessOptions = true` with `openAppSettings()`.

Notes:
- `openAppSettings()` currently uses `UIApplication.openSettingsURLString` to open this app's Settings page. This is the correct supported iOS deep-link for changing privacy permissions at the app level.
  - Product decision: the app will not provide an in-app way to downgrade from Full -> Limited; such changes should happen via iOS Settings only.

---
## Error Handling
- If `openAppSettings()` cannot construct the Settings URL (unlikely), do nothing (current behavior). No crash.

---
## Accessibility Considerations
- Removing the dialog reduces number of tap targets presented to the user in the Full-access state.
- The user still has a single obvious action: open iOS Settings.
- (Recommendation) Add an accessibility hint on the row button in the Full-access state: "Opens iOS Settings for this app".

---
## Testing Plan
Manual checks (minimum):
1. Simulate `.authorized` state:
   - Open App Settings -> Permissions -> tap "Photo Library Access".
   - Verify it immediately opens iOS Settings for this app.
   - Verify no confirmation dialog appears.
2. Simulate `.limited` state:
   - Verify "Photo Library Access" opens iOS Settings.
   - Verify "Selected Photos" opens the limited picker.
3. Simulate `.notDetermined` state:
   - Verify tapping "Photo Library Access" triggers the system photo permission prompt (via `manager.requestAccess()`).
4. Simulate `.denied` / `.restricted`:
   - Verify tapping opens iOS Settings.
5. Post-return refresh:
   - From `.authorized`, open iOS Settings and change the photo permission to `.limited` or `.denied`, then return to the app.
   - Verify the Permissions UI updates correctly (Full -> Limited two-row layout with "Selected Photos", or Full -> None state).

