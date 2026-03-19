# Google OAuth setup for fastblog

This project is wired for Google Sign-In. To enable it, add the SDK and your client ID.

## 1. Add the Google Sign-In Swift package

1. In Xcode: **File → Add Package Dependencies…**
2. Enter the URL: `https://github.com/google/GoogleSignIn-iOS`
3. Choose **Up to Next Major** with version **9.0.0** (or later).
4. Add the product **GoogleSignIn** to the **fastblog** target.
5. (Optional) For the “Sign in with Google” button UI, also add **GoogleSignInSwift**.

## 2. Set your OAuth client ID in Info.plist

1. Open **fastblog/Info.plist**.
2. Set **GIDClientID** to your **iOS OAuth client ID** from [Google Cloud Console](https://console.cloud.google.com/apis/credentials) (e.g. `123456789-xxxx.apps.googleusercontent.com`).
3. Set the **URL scheme** (inside `CFBundleURLTypes` → `CFBundleURLSchemes` → Item 0) to your **reversed client ID**:
   - Take the client ID and reverse the dot-delimited parts.
   - Example: `123456789-abcdefg.apps.googleusercontent.com` → `com.googleusercontent.apps.123456789-abcdefg`
   - In Cloud Console, when you open your iOS OAuth client, the **iOS URL scheme** field shows this value.

## 3. Use Google Sign-In in the app

- **Restore session**: `GoogleAuthManager.shared.restorePreviousSignIn()` is already called on app launch.
- **Handle callback**: The app already uses `.onOpenURL` to call `GoogleAuthManager.handleURL(url)`.
- **Sign in**: Call `GoogleAuthManager.shared.signIn(presenting: nil)` (or pass a specific view controller). The manager finds the root view controller if you pass `nil`.
- **Sign out**: `GoogleAuthManager.shared.signOut()`
- **State**: `GoogleAuthManager.shared.isSignedIn`, `currentUser`, `signInError`

Example in a SwiftUI view:

```swift
@StateObject private var googleAuth = GoogleAuthManager.shared

Button("Sign in with Google") {
    googleAuth.signIn(presenting: nil)
}
```

With the **GoogleSignInSwift** package you can use the official button:

```swift
import GoogleSignInSwift

GoogleSignInButton(viewModel: signInViewModel) {
    // handle sign-in (e.g. use GoogleAuthManager.shared.signIn)
}
```

## 4. Backend verification

The pocketverse API verifies the Google ID token on `POST /oauth/google`. The token’s **audience** (`aud`) must match one of the OAuth client IDs the server trusts.

### One app (simplest)

Set **`GOOGLE_CLIENT_ID`** on the server to the **same** value as **`GIDClientID`** in this app’s Info.plist (the iOS OAuth client ID).

### Multiple apps / websites (shared backend)

If the same backend serves fastblog (iOS), a web app, Android, etc., each client uses its **own** Google OAuth client ID. The ID token is always issued for **that** client’s ID as `aud`.

On the server, list **every** client ID you accept, comma-separated, in **`GOOGLE_CLIENT_IDS`**:

```text
GOOGLE_CLIENT_IDS=ios-fastblog-xxx.apps.googleusercontent.com,web-linkedspaces-yyy.apps.googleusercontent.com,android-zzz.apps.googleusercontent.com
```

The backend accepts a token if its `aud` is **any** of those IDs. Duplicates are ignored.

You can still set **`GOOGLE_CLIENT_ID`** and/or **`GOOGLE_WEB_CLIENT_ID`**; they are merged into the same allowlist (see `getGoogleAudiences()` in pocketverse).

**Google Cloud Console:** All of these OAuth clients should live in the **same Google Cloud project** as the backend’s credentials (so Google’s public keys verify the tokens).

### Optional: single web audience from iOS

If you prefer the iOS app to send tokens with **web** client as `aud`, add **`GIDServerClientID`** (web client) in Info.plist and add that web client ID to **`GOOGLE_CLIENT_IDS`** on the server. Otherwise keep **`GIDClientID`** only and include this app’s **iOS** client ID in **`GOOGLE_CLIENT_IDS`**.

## Notes

- The app builds without the Google Sign-In package; sign-in will no-op until the package is added and Info.plist is configured.
- Use an **iOS**-type OAuth client in Cloud Console for the app; use a **Web** client only if you need a server client ID or web sign-in.
