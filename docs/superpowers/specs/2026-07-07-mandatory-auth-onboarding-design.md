---
name: mandatory-auth-onboarding
description: Make account creation mandatory in onboarding — inserted as the second step after the welcome splash, reusing AuthView. Remove all guest-access copy from AuthView, Privacy Policy, and Terms of Service.
type: spec
date: 2026-07-07
---

# Mandatory Account Creation in Onboarding

## Overview

Account creation is currently optional — users can proceed through onboarding as guests and only encounter `AuthView` later (e.g., when trying to export). This change makes an account required to complete onboarding. The existing `AuthView` is reused unchanged structurally; it is inserted as a non-dismissible step between the welcome splash and the rest of the onboarding flow.

---

## New Onboarding Flow

```
splash → createAccount → cameraRollToBlog → problemStatement
```

Previously: `splash → cameraRollToBlog → problemStatement`

---

## Changes

### 1. `OnboardingFlowView.swift`

**Add `.createAccount` to `OnboardingStep`:**

```swift
enum OnboardingStep {
    case splash
    case createAccount   // new
    case cameraRollToBlog
    case problemStatement
}
```

**Wire the new step:**

- `SplashView.onFinish` → advance to `.createAccount` (was `.cameraRollToBlog`)
- New branch: `step == .createAccount` → render `AuthView` with:
  - `showsCloseButton: false` — no X button; screen cannot be dismissed
  - `hostControlsDismiss: true` — `OnboardingFlowView` owns navigation
  - `onAuthenticated: { step = .cameraRollToBlog }`
- `AuthView` already handles Apple, Google, and email sign-in, plus the "Already have an account? Log in" path — no structural changes to `AuthView` needed.

---

### 2. `AuthView.swift` — Copy Update

**Location:** `headerSection`, the `Text` subtitle beneath "Create your account"

| | Copy |
|---|---|
| **Before** | "Save and export unlimited blogs. Guests can export one blog to try Bloggo." |
| **After** | "Save your blogs, access them anywhere." |

---

### 3. `PrivacyPolicyView.swift` — Remove Guest References

**Change A — Section 2 body paragraph (line ~55):**

Remove the guest/account framing from the opening clause:

- Before: *"Whether you use Bloggo as a guest or with an account, your blog files stay with you locally…"*
- After: *"Your blog files stay with you locally unless you export them yourself (for example, PDF, zip, or video using the app's export tools). If you create an account, we store the information needed to sign you in and operate your account on our systems, such as username and email—that is separate from your blog drafts and media, which remain on your device."*

**Change B — Remove Section 7 "Guest and Registered User Access" entirely.**

Replace with a condensed **Section 7 "Registered Accounts"** that retains:
- The 13+ age requirement
- The one-account-per-email rule
- The note that account creation does not move blog content to servers

Remove:
- Guest tier description ("Guests may create and export one (1) blog…")
- The under-13 guest fallback ("you may still use Bloggo as a guest within the limits shown in the app")

Revised Section 7 text:

> **7. Registered Accounts**
>
> Bloggo requires an account to use the app. Account creation requires a valid email address.
>
> Age and accounts. Bloggo is listed on the Apple App Store with a 4+ age rating. Creating a Bloggo account requires you to provide personal information (such as an email address) that we process on our systems. You must be at least 13 years old to create an account, or the minimum age required in your jurisdiction to consent to the collection of your personal information online, whichever is higher. If you do not meet this requirement, you must not use the app.
>
> - By creating an account, you represent that you meet the age requirement above.
> - Only one account may be created per email address.
>
> An account does not move your blog content to our servers; drafts and photos stay on your device as described in Section 2, while we store the account details needed to sign you in.

---

### 4. `TermsOfServiceView.swift` — Remove Guest References

**Change A — Section 1 "Acceptance of Terms" (line ~47):**

- Remove: *"whether as a guest or with a registered account"* from the opening sentence.
  - Before: *"…whether as a guest or with a registered account, you agree to follow and be bound by the Terms."*
  - After: *"…you agree to follow and be bound by the Terms."*
- Rewrite the age paragraph to remove the guest fallback:
  - Before: *"…you may use Bloggo only as a guest, within the limits described in these Terms. Parents and guardians are responsible for deciding whether guest use is appropriate for minors in their care."*
  - After: *"If you do not meet the age requirement, you must not use the app."*

**Change B — Section 3: Retitle and remove guest bullet:**

- Before title: *"Guest Users and Registered Accounts"*
- After title: *"Registered Accounts"*
- Remove: the opening sentence *"Bloggo can be used with or without a registered account…"* and the guest bullet *"Guest Users: Guests may create and export one (1) blog…"*
- Keep and update the registered users bullet and the closing sentence about full access.

Revised Section 3:

> **3. Registered Accounts**
>
> Creating a Bloggo account allows you to save and manage blog drafts and export blogs. Registered accounts require a valid email address and that you meet the age requirement in Section 4.
>
> - Only one account may be created per email address.

**Change C — Section 4 "User Accounts" eligibility paragraph (lines ~78–79):**

- Remove: *"and may use Bloggo only as a guest"* from the ineligibility sentence.
  - Before: *"If you do not, you must not create an account and may use Bloggo only as a guest."*
  - After: *"If you do not meet this requirement, you must not use the app."*
- Remove the sub-bullet: *"Users under the applicable minimum age may use Bloggo without an account only, subject to guest limits described elsewhere in these Terms."*

---

## What Does NOT Change

- `SplashView` — no changes; it still calls `onFinish` as before
- `CameraRollToBlogView`, `ProblemStatementView` — no changes
- `fastblogApp.swift` — the existing user bypass (`if !hasCompletedOnboarding && photoAuth.status != .notDetermined { hasCompletedOnboarding = true }`) remains; this only applies to users who already had the app installed before this change
- `OnboardingStore` — no changes
- `AuthView` logic — no structural changes; only the subtitle string changes

---

## Edge Cases

- **Sign-in fails / user cancels:** `AuthView` stays on screen. There is no back button and no X. The user must complete sign-in or sign-up to proceed.
- **Existing users on re-install:** `hasCompletedOnboarding` is stored in `UserDefaults`, which does not persist across re-installs by default. A re-installing user will hit the new mandatory auth step. `AuthView` already handles returning users via "Already have an account? Log in."
- **Deep-link resets (password reset flow):** Not affected — that flow bypasses onboarding entirely via `fullScreenCover` in `fastblogApp`.
