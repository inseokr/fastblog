//
//  fastblogApp.swift
//  fastblog
//

import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.prewarmKeyboard()
        return true
    }

    /// Pre-warms the iOS keyboard so its first real appearance is instant.
    /// Without this, the first keyboard show in a session takes ~200-300ms extra
    /// while UIKit lazily loads the keyboard component.
    private static func prewarmKeyboard() {
        let field = UITextField()
        field.isHidden = true
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    // MARK: - APNs Registration

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Push] APNs token received: \(token)")
        // Persist the token so it can be sent to the backend once the user has an account.
        UserDefaults.standard.set(token, forKey: DraftReminderNotificationManager.pendingDeviceTokenKey)
        print("[Push] Token saved to UserDefaults key '\(DraftReminderNotificationManager.pendingDeviceTokenKey)'")
        // Only register with the backend if the user is already logged in.
        guard AuthService.shared.currentJwtToken != nil else {
            print("[Push] No JWT — token will be flushed to backend after login")
            return
        }
        print("[Push] Already logged in — sending token to backend immediately")
        Task { await APIManager.shared.registerDeviceToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications as banners even when app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap (background / quit state).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("[APNs] Notification tapped: \(userInfo)")
        // TODO: Parse userInfo and navigate to the relevant screen
        completionHandler()
    }
}

@main
struct fastblogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var photoAuth = PhotosAuthorizationManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var authStateManager = AuthStateManager.shared
    @StateObject private var createdRecapStore = CreatedRecapBlogStore.shared
    @StateObject private var splashManager = SplashStateManager()
    @AppStorage("blogify.hasCompletedOnboarding") private
        var hasCompletedOnboarding = false
    @AppStorage("blogify.justFinishedOnboarding") private
        var justFinishedOnboarding = false
    @AppStorage("blogify.hasAuthenticatedDuringOnboarding") private
        var hasAuthenticatedDuringOnboarding = false
    @AppStorage("blogify.hasCheckedExistingUser") private
        var hasCheckedExistingUser = false
    @AppStorage("blogify.hasSkippedPhotoPermission") private
        var hasSkippedPhotoPermission = false
    @AppStorage(AppStyle.storageKey) private var appStyleRawValue = AppStyle.auto.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAppReady = false
    @State private var pendingResetToken: String?
    @State private var showResetPassword = false
    @State private var showSignInAfterReset = false
    @State private var showPushPermissionPrompt = false

    #if DEBUG
        /// Flip to `true` to skip splash + onboarding and land directly on ManagePhotosView.
        private static let kDevBypassToManagePhotos = false
        /// Flip to `true` to skip splash + onboarding and land directly on KakaoMapTestView.
        private static let kDevBypassToKakaoMapTest = false
    #endif

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(photoAuth)
                .environmentObject(authService)
                .environmentObject(authStateManager)
                .environmentObject(createdRecapStore)
                .environmentObject(splashManager)
                .environmentObject(TripNearbyShareSessionController.shared)
                .onOpenURL { url in
                    if let token = Self.parseResetPasswordToken(from: url) {
                        pendingResetToken = token
                        if splashManager.phase == .done {
                            // Warm start: ContentView's NavigationStack already owns the
                            // UIKit presentation context, so SwiftUI's fullScreenCover on
                            // the parent view is silently dropped. Present via UIKit instead.
                            Self.presentResetPasswordOverlay(token: token, authService: authService) {
                                pendingResetToken = nil
                            }
                        }
                        // Cold start: onChange(of: splashManager.phase) triggers
                        // showResetPassword = true after the splash finishes.
                    } else if let jwt = Self.parseVerifyEmailToken(from: url) {
                        Task { await authService.loginWithVerificationToken(jwt) }
                    } else if Self.isReceiveTripURL(url) {
                        let code = Self.parseReceiveTripCode(from: url)
                        TripNearbyShareSessionController.shared.handleReceiveTripDeepLink(code: code)
                    } else {
                        _ = GoogleAuthManager.handleURL(url)
                    }
                }
                // Import drafts modal presented at app root so it overlays any screen
                .sheet(isPresented: $authStateManager.showImportDraftsModal) {
                    ImportDraftsModalView()
                        .environmentObject(authStateManager)
                        .environmentObject(createdRecapStore)
                }
                // Migrate anonymous drafts + import prompt on login.
                .onChange(of: authStateManager.authState) { _, newState in
                    if case .loggedIn(let userId) = newState {
                        createdRecapStore.importAnonymousDrafts(into: userId)
                        authStateManager.checkAndPromptImportIfNeeded()
                        Task { await DraftReminderNotificationManager.handlePostLoginSetup() }
                    }
                }
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    guard completed, authStateManager.isLoggedIn else { return }
                    Task { await DraftReminderNotificationManager.handlePostLoginSetup() }
                }
                .sheet(isPresented: $showPushPermissionPrompt) {
                    PushPermissionPromptView(isPresented: $showPushPermissionPrompt)
                }
                .preferredColorScheme(AppStyle.value(from: appStyleRawValue).preferredColorScheme)
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
            if Self.kDevBypassToKakaoMapTest {
                NavigationStack { KakaoMapTestView() }
            } else if Self.kDevBypassToManagePhotos {
                ManagePhotosDevWrapper()
            } else {
                normalAppRoot
            }
        #else
            normalAppRoot
        #endif
    }

    @ViewBuilder
    private var normalAppRoot: some View {
        ZStack {
            // ── Layer 1: main app content (fades in when ready) ──
            if isAppReady {
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingFlowView {
                            hasCompletedOnboarding = true
                            justFinishedOnboarding = true
                            hasAuthenticatedDuringOnboarding = false
                        }
                    } else {
                        ContentView()
                    }
                }
                .opacity(splashManager.phase == .splash ? 0 : 1)
                .animation(
                    .easeInOut(duration: 0.4),
                    value: splashManager.phase == .splash
                )
            }

            // ── Layer 2: splash logo overlay ──
            if splashManager.phase != .done {
                let isSplash = splashManager.phase == .splash
                ZStack {
                    // Dark background fades out as home fades in
                    Color(red: 5 / 255, green: 10 / 255, blue: 48 / 255)
                        .ignoresSafeArea()

                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(
                            color: .black.opacity(0.3),
                            radius: 10,
                            x: 0,
                            y: 5
                        )
                }
                .opacity(isSplash ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: isSplash)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            GoogleAuthManager.shared.restorePreviousSignIn()
            Task {
                createdRecapStore.enforceArchiveRules()

                // Ensure splash is visible for at least 1.5 seconds.
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                if !hasCheckedExistingUser {
                    if !hasCompletedOnboarding
                        && !hasAuthenticatedDuringOnboarding
                        && photoAuth.status != .notDetermined
                    {
                        hasCompletedOnboarding = true
                    }
                    hasCheckedExistingUser = true
                }

                // Phase 1 → 2: reveal home content, start logo fly-in
                withAnimation {
                    isAppReady = true
                    splashManager.phase = .animating
                }

                // Phase 2 → 3: after zoom fills screen (~650ms), remove overlay
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeOut(duration: 0.1)) {
                    splashManager.phase = .done
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                AppAnalytics.shared.flushOnBackground()
            } else if newPhase == .active {
                AppAnalytics.shared.flushOnBackground()
                Task {
                    createdRecapStore.enforceArchiveRules()
                }
            }
        }
        // Cold start: token arrived during splash → show once splash is done.
        .onChange(of: splashManager.phase) { _, phase in
            if phase == .done, pendingResetToken != nil {
                showResetPassword = true
            }
        }
        // Reset-password deep link cover. Uses a plain @State Bool so SwiftUI's
        // presentation system observes it directly — computed Binding(get:set:)
        // is not reliably tracked for triggering new presentations on warm start.
        .fullScreenCover(isPresented: $showResetPassword, onDismiss: {
            pendingResetToken = nil
        }) {
            if let token = pendingResetToken {
                ResetPasswordView(token: token) {
                    showResetPassword = false
                    showSignInAfterReset = true
                }
                .environmentObject(authService)
            }
        }
        .fullScreenCover(isPresented: $showSignInAfterReset) {
            NavigationStack {
                EmailLoginView(
                    onAuthenticated: { showSignInAfterReset = false },
                    onDismiss: { showSignInAfterReset = false }
                )
                .environmentObject(authService)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// Presents `ResetPasswordView` from the topmost `UIViewController`, bypassing
    /// SwiftUI's presentation hierarchy. This is required on warm start because
    /// `ContentView`'s `NavigationStack` creates a `UINavigationController` that
    /// takes over as the active UIKit presentation context, causing any `fullScreenCover`
    /// on a SwiftUI ancestor view to be silently dropped.
    private static func presentResetPasswordOverlay(
        token: String,
        authService: AuthService,
        onDismiss: @escaping () -> Void
    ) {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first
        else { return }

        var topVC: UIViewController? = window.rootViewController
        while let presented = topVC?.presentedViewController { topVC = presented }
        guard let presenterVC = topVC else { return }

        let resetView = ResetPasswordView(token: token) { [weak presenterVC] in
            onDismiss()
            presenterVC?.dismiss(animated: true) {
                Self.presentSignInOverlay(authService: authService)
            }
        }
        .environmentObject(authService)

        let hostingVC = UIHostingController(rootView: resetView)
        hostingVC.modalPresentationStyle = .overFullScreen
        presenterVC.present(hostingVC, animated: true)
    }

    /// Presents `EmailLoginView` from the topmost UIViewController (warm-start path,
    /// called after the reset password overlay has fully dismissed).
    private static func presentSignInOverlay(authService: AuthService) {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first
        else { return }

        var topVC: UIViewController? = window.rootViewController
        while let presented = topVC?.presentedViewController { topVC = presented }
        guard let presenterVC = topVC else { return }

        let signInView = NavigationStack {
            EmailLoginView(
                onAuthenticated: { [weak presenterVC] in
                    presenterVC?.dismiss(animated: true)
                },
                onDismiss: { [weak presenterVC] in
                    presenterVC?.dismiss(animated: true)
                }
            )
            .environmentObject(authService)
        }

        let hostingVC = UIHostingController(rootView: signInView)
        hostingVC.modalPresentationStyle = .overFullScreen
        presenterVC.present(hostingVC, animated: true)
    }

    /// Parses fastblog://reset-password?token=... deep link. Returns token if valid.
    private static func parseResetPasswordToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "fastblog" else { return nil }
        guard url.host?.lowercased() == "reset-password" else { return nil }
        guard
            let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "token" })?
                .value?
                .trimmingCharacters(in: .whitespaces),
            !token.isEmpty
        else { return nil }
        return token
    }

    /// Parses fastblog://verify-email?token=<jwt> deep link. Returns the JWT if valid.
    private static func parseVerifyEmailToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "fastblog" else { return nil }
        guard url.host?.lowercased() == "verify-email" else { return nil }
        guard
            let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "token" })?
                .value?
                .trimmingCharacters(in: .whitespaces),
            !token.isEmpty
        else { return nil }
        return token
    }

    private static func isReceiveTripURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "fastblog" else { return false }
        return url.host?.lowercased() == "receive-trip"
    }

    /// Parses `fastblog://receive-trip?code=ABCDEF` (code optional). Returns nil if absent.
    private static func parseReceiveTripCode(from url: URL) -> String? {
        guard isReceiveTripURL(url) else { return nil }
        guard
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }
}
