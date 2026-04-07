//
//  PhotoPermissionOnboardingView.swift
//  Capper
//

import Photos
import SwiftUI

struct PhotoPermissionOnboardingView: View {
    @ObservedObject var photoAuth: PhotosAuthorizationManager
    /// Called after the permission request completes with the resulting status.
    var onResult: ((PHAuthorizationStatus) -> Void)? = nil
    var onBack: (() -> Void)? = nil

    // Staggered animation phases (similar to ProblemStatementView)
    @State private var showIcon = false
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showTrustLine = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop,
                    OnboardingConstants.Colors.backgroundGradientBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let onBack = onBack {
                    ZStack {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.leading, 8)
                            }
                            Spacer()
                        }
                        // Invisible placeholder matches the height of "Set Home" title in
                        // NeighborhoodSelectionView so the chevron sits at the same vertical position.
                        Text(" ")
                            .font(.title)
                            .fontWeight(.bold)
                            .opacity(0)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
                    .padding(.top, OnboardingConstants.Layout.titleTopPadding)
                }
                
                Spacer()
                
                // Icon Header
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.2), radius: 20, y: 10)
                    .padding(.bottom, 40)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.8)

                // Copy
                VStack(spacing: 16) {
                    Text("Your photos already tell the story")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo finds trips in your camera roll using date and location so you can create blogs in seconds.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)
                    
                    Text("Your photos stay private on your device. Nothing uploads unless you choose to publish.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 40)
                        .opacity(showTrustLine ? 1 : 0)
                        .offset(y: showTrustLine ? 0 : 8)
                }
                
                Spacer()

                // Button
                VStack(spacing: 8) {
                    // Big CTA: triggers Apple's system permission dialog (required on first
                    // launch — cannot be bypassed). If already granted, proceeds immediately.
                    Button {
                        Task {
                            let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                            if current == .authorized || current == .limited {
                                // Already granted — proceed straight to trip scanner
                                onResult?(current)
                            } else {
                                // First time: Apple's system dialog appears here.
                                // The dialog defaults to "Allow Full Access".
                                AppAnalytics.shared.trackEvent(name: "photo_permission_prompted")
                                await photoAuth.requestAccess()
                                if photoAuth.status == .authorized || photoAuth.status == .limited {
                                    AppAnalytics.shared.trackEvent(name: "photo_permission_granted")
                                }
                                onResult?(photoAuth.status)
                            }
                        }
                    } label: {
                        Text("Allow Photo Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)
                    }

                    // Secondary link: shows Apple's limited photo selection picker.
                    // On first launch this still requires the system dialog first,
                    // then immediately opens the picker. If already limited, opens
                    // the picker directly so the user can add/remove photos.
                    Button {
                        Task {
                            await requestLimitedAccess()
                        }
                    } label: {
                        Text("Choose limited access")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.55))
                            .underline()
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startStaggeredAnimation()
        }
    }

    /// "Choose limited photos" flow:
    /// - .notDetermined: shows Apple's system dialog; if user picks limited
    ///   access the limited picker immediately follows so they can select photos.
    /// - .limited: directly presents the picker so the user can add/remove photos.
    /// - .authorized / .denied / other: proceeds without showing the picker.
    private func requestLimitedAccess() async {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch currentStatus {
        case .notDetermined:
            // Apple's system permission dialog is required before any photo access
            AppAnalytics.shared.trackEvent(name: "photo_permission_prompted")
            await photoAuth.requestAccess()
            if photoAuth.status == .authorized || photoAuth.status == .limited {
                AppAnalytics.shared.trackEvent(name: "photo_permission_granted")
            }
            if photoAuth.status == .limited {
                // User chose limited — immediately open the photo selection picker
                await presentLimitedPicker()
                photoAuth.refreshStatus()
            }
            onResult?(photoAuth.status)

        case .limited:
            // Already limited — open Apple's picker so the user can adjust their selection
            await presentLimitedPicker()
            photoAuth.refreshStatus()
            onResult?(photoAuth.status)

        default:
            // Already authorized (or denied/restricted) — proceed immediately
            onResult?(currentStatus)
        }
    }

    /// Present Apple's limited library picker and wait for completion.
    @MainActor
    private func presentLimitedPicker() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC) { _ in
                continuation.resume()
            }
        }
    }

    private func startStaggeredAnimation() {
        let duration: TimeInterval = 0.5

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showIcon = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.2)) {
            showHeadline = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.5)) {
            showBody = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.8)) {
            showTrustLine = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.1)) {
            showButton = true
        }
    }
}

#Preview {
    PhotoPermissionOnboardingView(photoAuth: PhotosAuthorizationManager())
}
