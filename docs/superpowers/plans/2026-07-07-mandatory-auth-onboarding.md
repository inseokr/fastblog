# Mandatory Account Creation in Onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert a non-dismissible `AuthView` step between the welcome splash and the rest of onboarding, and remove all guest-access copy from `AuthView`, `PrivacyPolicyView`, and `TermsOfServiceView`.

**Architecture:** The existing `OnboardingStep` enum gets a new `.createAccount` case; `OnboardingFlowView.body` routes to `AuthView` with `showsCloseButton: false` and `hostControlsDismiss: true`. `AuthService.shared` is already in the SwiftUI environment at the app root — no additional injection required. The three copy changes are independent string edits with no logic implications.

**Tech Stack:** Swift, SwiftUI, iOS. No new dependencies. No new files.

## Global Constraints

- `OnboardingFlowView` lives at `fastblog/Views/Onboarding/OnboardingFlowView.swift`
- `AuthView` lives at `fastblog/Views/Auth/AuthView.swift`
- `PrivacyPolicyView` lives at `fastblog/Views/PrivacyPolicyView.swift`
- `TermsOfServiceView` lives at `fastblog/Views/TermsOfServiceView.swift`
- Build command: `xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build`
- The `AuthService.shared` `@EnvironmentObject` is injected at the app root — do NOT add `.environmentObject(authService)` to `AuthView` inside `OnboardingFlowView`
- No changes to `SplashView`, `CameraRollToBlogView`, `ProblemStatementView`, `fastblogApp.swift`, or `OnboardingStore`
- Sentence case for all copy; no exclamation points; no guest references anywhere after these changes

---

### Task 1: OnboardingFlowView — Insert `.createAccount` step

**Files:**
- Modify: `fastblog/Views/Onboarding/OnboardingFlowView.swift:8-36`

**Interfaces:**
- Produces: `OnboardingStep.createAccount` case available for any caller that switches on `OnboardingStep`

- [ ] **Step 1: Add `.createAccount` case to `OnboardingStep`**

Replace lines 8–12:

```swift
// BEFORE
enum OnboardingStep {
    case splash
    case cameraRollToBlog
    case problemStatement
}

// AFTER
enum OnboardingStep {
    case splash
    case createAccount
    case cameraRollToBlog
    case problemStatement
}
```

- [ ] **Step 2: Wire the new step into `OnboardingFlowView.body`**

Replace the entire `body` computed property (lines 19–35):

```swift
// BEFORE
@ViewBuilder
var body: some View {
    Group {
        if step == .splash {
            SplashView {
                step = .cameraRollToBlog
            }
        } else if step == .cameraRollToBlog {
            CameraRollToBlogView {
                step = .problemStatement
            }
        } else if step == .problemStatement {
            ProblemStatementView {
                onComplete()
            }
        }
    }
}

// AFTER
@ViewBuilder
var body: some View {
    Group {
        if step == .splash {
            SplashView {
                step = .createAccount
            }
        } else if step == .createAccount {
            AuthView(
                onAuthenticated: { step = .cameraRollToBlog },
                hostControlsDismiss: true,
                showsCloseButton: false
            )
        } else if step == .cameraRollToBlog {
            CameraRollToBlogView {
                step = .problemStatement
            }
        } else if step == .problemStatement {
            ProblemStatementView {
                onComplete()
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/Onboarding/OnboardingFlowView.swift
git commit -m "feat: make account creation mandatory in onboarding flow"
```

---

### Task 2: AuthView — Update subtitle copy

**Files:**
- Modify: `fastblog/Views/Auth/AuthView.swift:150`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: nothing consumed by other tasks

- [ ] **Step 1: Update the subtitle string in `headerSection`**

Replace line 150 (inside `headerSection`):

```swift
// BEFORE
Text("Save and export unlimited blogs.\nGuests can export one blog to try Bloggo.")
    .font(.subheadline)
    .foregroundColor(.white.opacity(0.7))
    .multilineTextAlignment(.center)
    .lineSpacing(3)

// AFTER
Text("Save your blogs, access them anywhere.")
    .font(.subheadline)
    .foregroundColor(.white.opacity(0.7))
    .multilineTextAlignment(.center)
    .lineSpacing(3)
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add fastblog/Views/Auth/AuthView.swift
git commit -m "fix: remove guest copy from AuthView subtitle"
```

---

### Task 3: PrivacyPolicyView — Remove guest references

**Files:**
- Modify: `fastblog/Views/PrivacyPolicyView.swift`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: nothing consumed by other tasks

Two changes in this file:

**Change A — Section 2, third `bodyText` (currently line 55):**

Remove the guest-tier framing from the opening clause.

```swift
// BEFORE
bodyText("Whether you use Bloggo as a guest or with an account, your blog files stay with you locally unless you export them yourself (for example, PDF, zip, or video using the app's export tools). If you create an account, we store the information needed to sign you in and operate your account on our systems, such as username and email—that is separate from your blog drafts and media, which remain on your device.")

// AFTER
bodyText("Your blog files stay with you locally unless you export them yourself (for example, PDF, zip, or video using the app's export tools). If you create an account, we store the information needed to sign you in and operate your account on our systems, such as username and email—that is separate from your blog drafts and media, which remain on your device.")
```

**Change B — Replace Section 7 entirely (currently lines 92–101):**

```swift
// BEFORE
Group {
    sectionTitle("7. Guest and Registered User Access")
    bodyText("Bloggo offers two tiers of access:")
    bullet("Guest users (no account): Guests may create and export one (1) blog. To save additional blogs or use features that require an account, you can create one.")
    bullet("Registered users: Users with a Bloggo account can save and export blogs according to the limits shown in the app. Account creation requires a valid email address.")
    bodyText("Age and accounts. Bloggo is listed on the Apple App Store with a 4+ age rating. That rating reflects the general suitability of the app for download and everyday use, including when you use Bloggo without registering. Creating a Bloggo account is different: it requires you to provide personal information (such as an email address) that we process on our systems. For that reason, you must be at least 13 years old to create an account. If you are not yet 13, you may not register; you may still use Bloggo as a guest within the limits shown in the app, without submitting the information we collect for registered users.")
    bullet("By creating an account, you represent that you are at least 13 years of age, or the minimum age required in your jurisdiction to consent to the collection of your personal information online, whichever is higher.")
    bullet("Only one account may be created per email address.")
    bodyText("An account does not move your blog content to our servers; drafts and photos stay on your device as described in Section 2, while we store the account details needed to sign you in.")
}

// AFTER
Group {
    sectionTitle("7. Registered Accounts")
    bodyText("Bloggo requires an account to use the app. Account creation requires a valid email address.")
    bodyText("Age and accounts. Bloggo is listed on the Apple App Store with a 4+ age rating. Creating a Bloggo account requires you to provide personal information (such as an email address) that we process on our systems. You must be at least 13 years old to create an account, or the minimum age required in your jurisdiction to consent to the collection of your personal information online, whichever is higher. If you do not meet this requirement, you must not use the app.")
    bullet("By creating an account, you represent that you meet the age requirement above.")
    bullet("Only one account may be created per email address.")
    bodyText("An account does not move your blog content to our servers; drafts and photos stay on your device as described in Section 2, while we store the account details needed to sign you in.")
}
```

- [ ] **Step 1: Apply Change A (Section 2 body paragraph)**

Edit `fastblog/Views/PrivacyPolicyView.swift` — find and replace the `bodyText` string shown above in Change A.

- [ ] **Step 2: Apply Change B (Section 7 replacement)**

Edit `fastblog/Views/PrivacyPolicyView.swift` — find and replace the entire `Group { ... }` block for Section 7 shown above in Change B.

- [ ] **Step 3: Build to verify compilation**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/PrivacyPolicyView.swift
git commit -m "fix: remove guest-user references from Privacy Policy"
```

---

### Task 4: TermsOfServiceView — Remove guest references

**Files:**
- Modify: `fastblog/Views/TermsOfServiceView.swift`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: nothing consumed by other tasks

Three changes in this file:

**Change A — Section 1, first `bodyText` (line ~47): remove "whether as a guest or with a registered account"**

```swift
// BEFORE
bodyText("The Bloggo mobile application and the features and services available through it (the \"App,\" and our \"Services\") are provided to you by LinkedSpaces LLC (\"LinkedSpaces,\" \"we,\" \"us\") subject to these Terms of Service, including the policies described in our Privacy Policy (together, the \"Terms\"). By downloading, accessing, or using the App, whether as a guest or with a registered account, you agree to follow and be bound by the Terms. We may update the Terms from time to time. The current Terms are available within the App. We and our third party service providers may change features, services, related to the App without notice. Bloggo is a travel journaling app; your blog content, photos, and Reel clips stay on your device and are not stored on or synced through our servers. We collect account and limited technical information as described in the Privacy Policy, not your blog manuscripts, Reel clips, or photo library.")

// AFTER
bodyText("The Bloggo mobile application and the features and services available through it (the \"App,\" and our \"Services\") are provided to you by LinkedSpaces LLC (\"LinkedSpaces,\" \"we,\" \"us\") subject to these Terms of Service, including the policies described in our Privacy Policy (together, the \"Terms\"). By downloading, accessing, or using the App, you agree to follow and be bound by the Terms. We may update the Terms from time to time. The current Terms are available within the App. We and our third party service providers may change features, services, related to the App without notice. Bloggo is a travel journaling app; your blog content, photos, and Reel clips stay on your device and are not stored on or synced through our servers. We collect account and limited technical information as described in the Privacy Policy, not your blog manuscripts, Reel clips, or photo library.")
```

**Change B — Section 1, second age-paragraph `bodyText` (line ~49): remove guest fallback**

```swift
// BEFORE
bodyText("Bloggo is offered on the Apple App Store with a 4+ age rating. That rating describes the general suitability of the Bloggo app for a wide audience when used as designed. Registering for a Bloggo account is separate: it involves providing personal information and using our authentication and account services. You must be at least 13 years old to create an account (or the minimum age required in your jurisdiction for you to consent to our collection and use of your personal information online, if that age is higher). If you are under that age, you must not register; you may use Bloggo only as a guest, within the limits described in these Terms. Parents and guardians are responsible for deciding whether guest use is appropriate for minors in their care. If you do not agree with the Terms, do not use the App.")

// AFTER
bodyText("Bloggo is offered on the Apple App Store with a 4+ age rating. That rating describes the general suitability of the Bloggo app for a wide audience when used as designed. Registering for a Bloggo account is separate: it involves providing personal information and using our authentication and account services. You must be at least 13 years old to create an account (or the minimum age required in your jurisdiction for you to consent to our collection and use of your personal information online, if that age is higher). If you do not meet the age requirement, you must not use the app. If you do not agree with the Terms, do not use the App.")
```

**Change C — Section 3 (lines ~68–73): retitle and rewrite**

```swift
// BEFORE
Group {
    sectionTitle("3. Guest Users and Registered Accounts")
    bodyText("Bloggo can be used with or without a registered account. The App Store 4+ rating applies to the app overall; account registration is reserved for users who meet the age requirement in Section 4.")
    bullet("Guest Users: Guests may create and export one (1) blog. Guest data is stored locally on the device and is not associated with any account.")
    bullet("Registered Users: Creating a Bloggo account allows you to save and manage unlimited blog drafts and export as many blogs as you like. Registered accounts require a valid email address and that you are at least 13 years old (or the applicable age of digital consent in your jurisdiction, if higher).")
    bodyText("Account creation takes only a moment. Registered users enjoy the full Bloggo experience with no content restrictions.")
}

// AFTER
Group {
    sectionTitle("3. Registered Accounts")
    bodyText("Creating a Bloggo account allows you to save and manage blog drafts and export blogs. Registered accounts require a valid email address and that you meet the age requirement in Section 4.")
    bullet("Only one account may be created per email address.")
}
```

**Change D — Section 4, eligibility paragraph + guest sub-bullet (lines ~78–79): remove guest fallback and sub-bullet**

```swift
// BEFORE
bodyText("Eligibility. You must be at least 13 years of age to create a Bloggo account, or the minimum age required in your country or region for you to agree to our processing of your personal data without parental consent, whichever is greater. By registering, you represent and warrant that you satisfy this requirement. If you do not, you must not create an account and may use Bloggo only as a guest.")
bullet("Users under the applicable minimum age may use Bloggo without an account only, subject to guest limits described elsewhere in these Terms.")

// AFTER
bodyText("Eligibility. You must be at least 13 years of age to create a Bloggo account, or the minimum age required in your country or region for you to agree to our processing of your personal data without parental consent, whichever is greater. By registering, you represent and warrant that you satisfy this requirement. If you do not meet this requirement, you must not use the app.")
```

- [ ] **Step 1: Apply Change A (Section 1, first bodyText)**

Edit `fastblog/Views/TermsOfServiceView.swift` — replace the first `bodyText(...)` in Section 1 as shown above.

- [ ] **Step 2: Apply Change B (Section 1, age paragraph)**

Edit `fastblog/Views/TermsOfServiceView.swift` — replace the second `bodyText(...)` in Section 1 as shown above.

- [ ] **Step 3: Apply Change C (Section 3 rewrite)**

Edit `fastblog/Views/TermsOfServiceView.swift` — replace the entire Section 3 `Group { ... }` block as shown above.

- [ ] **Step 4: Apply Change D (Section 4 eligibility)**

Edit `fastblog/Views/TermsOfServiceView.swift` — replace the eligibility `bodyText` and remove the `bullet(...)` line that follows it, as shown above.

- [ ] **Step 5: Build to verify compilation**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/TermsOfServiceView.swift
git commit -m "fix: remove guest-user references from Terms of Service"
```

---

## Manual Test Checklist

After all tasks are committed, install on simulator and verify:

- Fresh install (or cleared `UserDefaults`): onboarding shows splash → auth screen → camera roll → problem statement
- Auth screen has no X button and no back gesture
- Completing sign-in (any method) advances to camera roll step
- `AuthView` subtitle reads "Save your blogs, access them anywhere."
- Privacy Policy Section 2 has no "guest" mention; Section 7 title reads "Registered Accounts"
- Terms of Service Section 1 has no "whether as a guest or with a registered account"; Section 3 title reads "Registered Accounts"; Section 4 eligibility paragraph ends "you must not use the app" with no guest sub-bullet
