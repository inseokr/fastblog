//
//  fastblogApp.swift
//  fastblog
//

import SwiftUI
import UIKit

@main
struct fastblogApp: App {
    @StateObject private var photoAuth = PhotosAuthorizationManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var authStateManager = AuthStateManager.shared
    @StateObject private var createdRecapStore = CreatedRecapBlogStore.shared
    @AppStorage("blogify.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("blogify.hasCheckedExistingUser") private var hasCheckedExistingUser = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAppReady = false
    @State private var pendingResetToken: String?

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
                .onOpenURL { url in
                    if let token = Self.parseResetPasswordToken(from: url) {
                        DispatchQueue.main.async { pendingResetToken = token }
                    } else {
                        _ = GoogleAuthManager.handleURL(url)
                    }
                }
                .sheet(isPresented: Binding(
                    get: { isAppReady && pendingResetToken != nil },
                    set: { if !$0 { pendingResetToken = nil } }
                )) {
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
                    }
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
            if !isAppReady {
                AppLaunchSplashView()
                    .transition(.opacity)
            } else {
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingFlowView {
                            hasCompletedOnboarding = true
                            photoAuth.refreshStatus()
                        }
                    } else if photoAuth.isAuthorized {
                        ContentView()
                    } else {
                        PhotosPermissionView(
                            status: photoAuth.status,
                            onRequest: { await photoAuth.requestAccess() },
                            onOpenSettings: { openSettings() }
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            DraftReminderNotificationManager.requestPermissionIfNeeded()
            GoogleAuthManager.shared.restorePreviousSignIn()
            Task {
                await EntitlementManager.shared.refreshEntitlements()
                createdRecapStore.enforceArchiveRules()

                // Minor delay to ensure splash is visible for a moment if init is too fast.
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s

                withAnimation {
                    if !hasCheckedExistingUser {
                        // Any user with a photo auth status other than notDetermined is an old user.
                        if !hasCompletedOnboarding && photoAuth.status != .notDetermined {
                            hasCompletedOnboarding = true
                        }
                        hasCheckedExistingUser = true
                    }
                    isAppReady = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await EntitlementManager.shared.refreshEntitlements()
                    createdRecapStore.enforceArchiveRules()
                    // Re-sync cloud data whenever the app returns to the foreground (logged in only).
                    if authStateManager.isLoggedIn {
                        await createdRecapStore.syncFromCloud()
                    }
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Parses fastblog://reset-password?token=... deep link. Returns token if valid.
    private static func parseResetPasswordToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "fastblog" else { return nil }
        guard url.host?.lowercased() == "reset-password" else { return nil }
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespaces),
            !token.isEmpty
        else { return nil }
        return token
    }
}
