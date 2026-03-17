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
        return true
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
        print("[APNs] Device token: \(token)")
        // Persist the token so it can be sent to the backend once the user has an account.
        UserDefaults.standard.set(token, forKey: DraftReminderNotificationManager.pendingDeviceTokenKey)
        // Only register with the backend if the user is already logged in.
        guard AuthService.shared.currentJwtToken != nil else {
            print("[APNs] No auth token — device token saved for post-login registration")
            return
        }
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
    @State private var showNotificationDeniedAlert = false

    #if DEBUG
        /// Flip to `true` to skip splash + onboarding and land directly on ManagePhotosView.
        private static let kDevBypassToManagePhotos = false
    #endif

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(authService)
                .environmentObject(authStateManager)
                .environmentObject(createdRecapStore)
                .environmentObject(splashManager)
                .onOpenURL { url in
                    if let token = Self.parseResetPasswordToken(from: url) {
                        DispatchQueue.main.async { pendingResetToken = token }
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
                            if isDenied { showNotificationDeniedAlert = true }
                        }
                    }
                }
                .alert("Enable Notifications", isPresented: $showNotificationDeniedAlert) {
                    Button("Open Settings") { openSettings() }
                    Button("Not Now", role: .cancel) {}
                } message: {
                    Text("Turn on notifications to get updates about your blogs. You can enable them in Settings.")
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

            // ── Layer 2: animated logo overlay ──
            if splashManager.phase != .done {
                let isSplash = splashManager.phase == .splash

                ZStack {
                    // Dark background fades out as home fades in
                    Color(red: 5 / 255, green: 10 / 255, blue: 48 / 255)
                        .ignoresSafeArea()

                    // Logo fades away
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
            DraftReminderNotificationManager.requestPermissionIfNeeded()
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
            if newPhase == .active {
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
}
