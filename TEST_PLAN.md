# Fastblog (Bloggo) — Regression Test Plan

**App:** Bloggo iOS  
**Target:** Pre-release regression baseline  
**Platform:** iPhone (iOS 16+), test on at least one iOS 17 and one iOS 18 device  

---

## Priority Levels

| Level | Meaning |
|-------|---------|
| **P0** | Release blocker — must pass before shipping |
| **P1** | Important — investigate failures before shipping |
| **P2** | Nice to catch — can ship with known issue if tracked |

---

## Test Environment Setup

- [ ] Clean install (delete app, reinstall) on at least one device
- [ ] Logged-in session on at least one device
- [ ] Logged-out (anonymous) session on at least one device
- [ ] Photo library with at least one multi-day trip with geotagged photos
- [ ] At least one existing saved blog in the account

---

## 1. Authentication & Account

### 1.1 Sign In with Apple
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| A-1 | Fresh install → tap "Sign in with Apple" | Apple auth sheet appears, completes without error, lands on Landing screen | P0 |
| A-2 | Sign out → Sign back in with same Apple ID | Existing blogs visible after sign-in | P0 |

### 1.2 Sign In with Google
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| A-3 | Tap "Sign in with Google" | Google OAuth sheet opens, completes, lands on Landing screen | P0 |

### 1.3 Email / OTP
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| A-4 | Tap email sign-in → enter valid email → submit | OTP sent confirmation shown | P0 |
| A-5 | Enter correct OTP code | Signs in successfully | P0 |
| A-6 | Enter wrong OTP code | Error shown, can retry | P1 |

### 1.4 Sign Out & Anonymous Mode
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| A-7 | Profile → sign out | Returns to landing, blogs hidden, no crash | P0 |
| A-8 | Use app without signing in | Can scan trips and preview blogs; save/sync prompts sign-in | P1 |

### 1.5 Password Reset
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| A-9 | Email login → "Forgot password" → submit email | Reset email sent confirmation | P1 |

---

## 2. Trip Scanning & Discovery

### 2.1 Initial Scan
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| S-1 | Grant full photo library access → tap "Tap to Blog" | Scanning animation appears, trips detected | P0 |
| S-2 | Scanning completes | TripsView shows carousel of detected trips, no crash | P0 |
| S-3 | Photos with no geotag | Those photos excluded gracefully (no crash, no phantom trips) | P1 |

### 2.2 Limited Photo Access
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| S-4 | Grant limited photo access (select a few photos) | "Manage Photos" prompt appears, limited access flow shown | P0 |
| S-5 | Tap "Manage Photos" → add more photos in system picker | New photos appear in scan results after re-scan | P1 |

### 2.3 Find More Trips
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| S-6 | TripsView → "Find More Trips" → enter custom date range | Scanning runs for that date range, result shown | P1 |
| S-7 | Date range with no photos | Empty state shown, no crash | P1 |

### 2.4 Local Neighborhood Exclusion
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| S-8 | Photos taken at home address should not appear as a "trip" | Home-area photos excluded from trip list | P1 |

---

## 3. Blog Creation Flow

### 3.1 Standard Creation
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| C-1 | Trips carousel → tap "Create Blog" on a trip | Title input screen appears | P0 |
| C-2 | Enter title → tap Continue | Cover photo selection screen appears | P0 |
| C-3 | Select cover photo → tap Continue | "Creating Recap" animation plays | P0 |
| C-4 | Animation completes | Blog published; blog appears in My Blogs / Landing | P0 |
| C-5 | Create blog with no title (blank) | Validation prevents proceeding or applies default title | P1 |

### 3.2 Photo Selection During Creation
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| C-6 | On cover photo screen: scroll through available photos | All trip photos visible, no missing thumbnails | P1 |
| C-7 | Select a cover photo and change selection | New selection takes effect | P1 |

---

## 4. Blog Editing

### 4.1 Day Captions
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| E-1 | Open blog → tap day caption area | Text editor opens | P0 |
| E-2 | Edit and save caption | Caption persists after closing and reopening blog | P0 |

### 4.2 Place Stop Management
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| E-3 | Tap a place stop → "Rename" | Edit name sheet appears; name saved | P0 |
| E-4 | Tap a place stop → "Remove" | Place disappears from timeline | P0 |
| E-5 | Undo place removal via "Removed Places" sheet | Place is restored to timeline | P1 |
| E-6 | Long-press place stop → reorder | Place stop moves to new position | P1 |
ISEO-COMMENTS: not sure long-press reorder is working
| E-7 | Tap place category → change to different category | Category updated, icon/label reflects change | P2 |

### 4.3 Photo Management
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| E-8 | Tap a photo → edit caption | Caption saved and displayed | P0 |
| E-9 | Toggle photo inclusion (include/exclude) | Photo disappears from blog view; undo works | P1 |
| E-10 | Cover photo change from blog settings | New cover photo shown on blog card | P1 |

### 4.4 Weather
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| E-11 | Tap weather field on a day → select condition | Weather icon displayed for that day | P2 |

### 4.5 Blog Settings
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| E-12 | Open blog settings sheet | Sheet opens, no crash | P1 |
| E-13 | Change blog title from settings | Updated title reflected in blog header and blog list | P1 |

---

## 5. Story / Magazine Mode (PDF Export)

### 5.1 Story Building
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| ST-1 | Blog → "Create Story" | Writing style selector appears | P0 |
| ST-2 | Select a writing style → confirm | "Preparing Story" loading screen plays | P0 |
| ST-3 | Story builds | Story preview appears with cover, days, photos, and generated captions | P0 |
| ST-4 | Story build with no network | Graceful error shown (or local fallback captions used) | P1 |

### 5.2 PDF Export
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| ST-5 | Story preview → "Export PDF" | PDF export options sheet appears | P0 |
| ST-6 | Confirm export | PDF generated and preview shown | P0 |
| ST-7 | Share PDF via share sheet | Share sheet opens with PDF attached | P1 |

---

## 6. Places Visited

### 6.1 Navigation & Display
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PL-1 | Landing → Places Visited icon | PlacesVisitedView opens with list of visited places | P0 |
| PL-2 | Tap a place | Detail view shows place photos and linked blogs | P0 |
| PL-3 | Scroll through a large places list | Smooth scroll, no layout glitches | P1 |

### 6.2 Country Grouping
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PL-4 | Verify places are grouped by country | Countries shown as sections with correct country names | P1 |

---

## 7. User Profile & My Blogs

### 7.1 My Blogs
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PR-1 | Navigate to My Blogs | All created blogs listed | P0 |
| PR-2 | Tap a blog in My Blogs | Blog opens correctly | P0 |
| PR-3 | Delete a blog from My Blogs | Blog removed from list, confirmed deletion | P0 |

### 7.2 Profile Stats & Map
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PR-4 | Profile → Stats tab | Trip count, photo count, country count all display | P1 |
| PR-5 | Profile → Map tab | Map shows pins for all trip locations | P1 |

### 7.3 Merge Blogs
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PR-6 | Select two blogs → Merge | Merged blog created with combined days | P2 |

---

## 8. Cloud Sync

### 8.1 Create & Sync
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SY-1 | Create a blog while online | Blog syncs to cloud (progress indicator completes) | P0 |
| SY-2 | Create a blog while offline | Blog saved locally; syncs when connection restored | P0 |
| SY-3 | Edit a synced blog | Changes propagate to cloud | P1 |

### 8.2 Cross-device
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SY-4 | Sign in on a second device with same account | Existing blogs appear after sign-in | P1 |

### 8.3 Storage Management
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SY-5 | Profile → Storage | Storage breakdown shown with used/available | P1 |

---

## 9. Sharing

### 9.1 Blog Share
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SH-1 | Open blog → Share | iOS share sheet appears with blog link or PDF | P0 |
| SH-2 | Shared blog URL opens correctly in Safari | Blog renders in web/preview | P1 |

### 9.2 Blog Drop
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SH-3 | Blog → "Blog Drop" | Share snapshot generated | P2 |

### 9.3 Nearby Share
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| SH-4 | Trip → Nearby Share → broadcast | Session starts, nearby devices can discover | P2 |

---

## 10. In-App Camera

### 10.1 Capture
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| CA-1 | Tap camera icon from Landing | Camera view opens (requires camera permission) | P0 |
| CA-2 | Capture a photo | Photo saved and appears in captured gallery | P0 |
| CA-3 | Captured photo added to relevant trip day | Photo visible in associated trip | P1 |

### 10.2 Voice Memo
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| CA-4 | Blog editing → voice memo recorder | Microphone permission requested, recording starts | P2 |
| CA-5 | Stop recording, playback | Recorded audio plays back correctly | P2 |

---

## 11. Memory Recall

| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| MR-1 | Open app on a date matching a past trip anniversary | Memory recall popup appears | P2 |
| MR-2 | Tap memory recall card | Opens the referenced blog or photo | P2 |

---

## 12. Notifications

### 12.1 Permission
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| N-1 | First run or Settings → Notifications | Push permission prompt appears | P1 |
| N-2 | Deny push permission | App continues without crash; no repeat prompt on same session | P1 |

### 12.2 Draft Reminders
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| N-3 | Leave a trip unturned-into-blog for the reminder threshold | Push notification received referencing the unsaved trip | P2 |

---

## 13. Premium / Paywall

| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| PW-1 | Trigger a gated premium feature | Paywall sheet appears cleanly | P0 |
| PW-2 | Paywall "Restore Purchases" | Restores subscription without crash | P1 |
| PW-3 | Paywall close/dismiss | Sheet dismisses, app continues | P0 |

---

## 14. Map Views

### 14.1 Trips Map
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| M-1 | TripsView → tap Map toggle | Map appears with trip location markers | P1 |
| M-2 | Tap a cluster on the map | Expands or navigates to that trip | P1 |

### 14.2 Blog Day Map
| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| M-3 | Open blog → tap map icon on a day | Day map shows route/pins for that day | P1 |

---

## 15. Onboarding (Fresh Install)

| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| OB-1 | Fresh install, first launch | Onboarding flow starts | P0 |
| OB-2 | Photo library permission prompt during onboarding | Permission sheet appears at correct step | P0 |
| OB-3 | Skip onboarding (if supported) | Lands on Landing screen, no crash | P1 |
| OB-4 | Complete onboarding | `blogify.hasCompletedOnboarding` set; onboarding not shown on next launch | P1 |

---

## 16. Edge Cases & Stability

| # | Steps | Expected | Priority |
|---|-------|----------|----------|
| EC-1 | Kill and relaunch app mid-blog-creation | Partial state handled (no crash, draft recoverable or clean state) | P0 |
| EC-2 | Background/foreground cycle during scan | Scan resumes or restarts cleanly | P1 |
| EC-3 | No internet on launch | App loads from local data, no crash | P0 |
| EC-4 | Photo library with 1000+ photos | Scan completes in reasonable time (<30s), no memory crash | P1 |
| EC-5 | Blog with 10+ days and 50+ places | Blog detail view scrolls smoothly | P1 |
| EC-6 | Delete blog that is currently open | Handled gracefully (dismiss + remove from list) | P1 |
| EC-7 | iOS 18 device — all Vision API features (aesthetic scoring) | AI photo quality scoring works; no crash on older device | P1 |
| EC-8 | iOS 16 / 17 device — aesthetic scoring guarded | App does not crash; falls back gracefully | P0 |

---

## 17. Build & Smoke Test

Run before every release candidate:

```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build
```

- [ ] Clean build succeeds with zero errors
- [ ] Zero warnings that are new relative to the last release
- [ ] App launches on iPhone 15 Pro simulator (iOS 17) without crash
- [ ] App launches on iPhone 16 simulator (iOS 18) without crash

---

## Release Sign-Off Checklist

- [ ] All P0 tests pass
- [ ] All P1 failures reviewed and triaged (no unreviewed P1 failures)
- [ ] Build compiles clean
- [ ] Tested on physical device (not just simulator) for camera and photo library flows
- [ ] Tested on iOS 17 and iOS 18
- [ ] Cloud sync verified end-to-end at least once
- [ ] PDF export produces a valid, non-corrupt file
