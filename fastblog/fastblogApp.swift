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
    @AppStorage("blogify.hasCheckedExistingUser") private
        var hasCheckedExistingUser = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAppReady = false
    @State private var pendingResetToken: String?
    @State private var showPushPermissionPrompt = false

    #if DEBUG
        /// Flip to `true` to skip splash + onboarding and land directly on ManagePhotosView.
        private static let kDevBypassToManagePhotos = false
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
                        DispatchQueue.main.async { pendingResetToken = token }
                    } else if let jwt = Self.parseVerifyEmailToken(from: url) {
                        Task { await authService.loginWithVerificationToken(jwt) }
                    } else if Self.isReceiveTripURL(url) {
                        let code = Self.parseReceiveTripCode(from: url)
                        TripNearbyShareSessionController.shared.handleReceiveTripDeepLink(code: code)
                    } else {
                        _ = GoogleAuthManager.handleURL(url)
                    }
                }
                .sheet(
                    isPresented: Binding(
                        get: { isAppReady && pendingResetToken != nil },
                        set: { if !$0 { pendingResetToken = nil } }
                    )
                ) {
                    if let token = pendingResetToken {
                        ResetPasswordView(token: token) {
                            pendingResetToken = nil
                        }
                        .environmentObject(authService)
                    }
                }
                // Import drafts modal presented at app root so it overlays any screen
                .sheet(isPresented: $authStateManager.showImportDraftsModal) {
                    ImportDraftsModalView()
                        .environmentObject(authStateManager)
                        .environmentObject(createdRecapStore)
                }
                // Migrate anonymous drafts + import prompt on login; also kick off cloud sync.
                .onChange(of: authStateManager.authState) { _, newState in
                    if case .loggedIn(let userId) = newState {
                        createdRecapStore.importAnonymousDrafts(into: userId)
                        authStateManager.checkAndPromptImportIfNeeded()
                        Task { await createdRecapStore.syncFromCloud() }
                        // Register any pending APNs token now that the user has an account.
                        Task {
                            let isDenied = await DraftReminderNotificationManager.handlePostLoginSetup()
                            if isDenied { showPushPermissionPrompt = true }
                        }
                    }
                }
                // If the user was already logged in, finishing onboarding does not change authState — still register for push.
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    guard completed, authStateManager.isLoggedIn else { return }
                    Task {
                        let isDenied = await DraftReminderNotificationManager.handlePostLoginSetup()
                        if isDenied { showPushPermissionPrompt = true }
                    }
                }
                .sheet(isPresented: $showPushPermissionPrompt) {
                    PushPermissionPromptView(isPresented: $showPushPermissionPrompt)
                }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
            if Self.kDevBypassToManagePhotos {
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
                            // Refresh auth FIRST so photoAuth.isAuthorized is
                            // already true when hasCompletedOnboarding triggers
                            // the view transition to ContentView.
                            photoAuth.refreshStatus()
                            hasCompletedOnboarding = true
                            justFinishedOnboarding = true
                        }
                    } else if photoAuth.isAuthorized {
                        ContentView()
                    } else {
                        PhotosPermissionView(
                            status: photoAuth.status,
                            onOpenSettings: { openSettings() },
                            onContinueWithoutScanning: {
                                hasCompletedOnboarding = true
                                justFinishedOnboarding = true
                            }
                        )
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
                await EntitlementManager.shared.refreshEntitlements()
                createdRecapStore.enforceArchiveRules()

                // Ensure splash is visible for at least 1.5 seconds.
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                if !hasCheckedExistingUser {
                    if !hasCompletedOnboarding
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
                    await EntitlementManager.shared.refreshEntitlements()
                    createdRecapStore.enforceArchiveRules()
                    if authStateManager.isLoggedIn {
                        await createdRecapStore.syncFromCloud()
                    }
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
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
