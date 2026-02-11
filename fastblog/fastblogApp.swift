//
//  fastblogApp.swift
//  fastblog
//

import SwiftUI
import UIKit

@main
struct fastblogApp: App {
    @StateObject private var photoAuth = PhotosAuthorizationManager()
    @AppStorage("blogify.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
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
            .onAppear {
                hasCompletedOnboarding = false
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
