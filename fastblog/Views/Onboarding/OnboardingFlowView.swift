//
//  OnboardingFlowView.swift
//  Capper
//

import Photos
import SwiftUI

enum OnboardingStep {
    case splash
    case neighborhood
    case photoPermission
}

struct OnboardingFlowView: View {
    @State private var step: OnboardingStep = .splash
    @StateObject private var photoAuth = PhotosAuthorizationManager()
    var onComplete: () -> Void

    @ViewBuilder
    var body: some View {
        Group {
            if step == .splash {
                SplashView {
                    step = .neighborhood
                }
            } else if step == .neighborhood {
                NeighborhoodSelectionView {
                    step = .photoPermission
                }
            } else {
                PhotosPermissionView(
                    status: photoAuth.status,
                    onRequest: { await photoAuth.requestAccess() },
                    onOpenSettings: { openSettings() }
                )
                .onAppear {
                    if photoAuth.isAuthorized {
                        OnboardingStore.hasCompletedOnboarding = true
                        onComplete()
                    }
                }
            }
        }
        .onChange(of: photoAuth.status) { _, newStatus in
            if case .photoPermission = step, newStatus == .authorized || newStatus == .limited {
                OnboardingStore.hasCompletedOnboarding = true
                onComplete()
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
