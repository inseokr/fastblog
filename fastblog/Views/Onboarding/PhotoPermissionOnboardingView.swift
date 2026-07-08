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
                                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                                    .padding(.leading, 8)
                            }
                            Spacer()
                        }
                        // Invisible placeholder matches the height of "Set Home" header in
                        // NeighborhoodSelectionView so the chevron sits at the same vertical position.
                        Text(" ")
                            .font(.headline)
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
                    .foregroundColor(OnboardingConstants.Colors.doneButtonBlue)
                    .shadow(color: OnboardingConstants.Colors.doneButtonBlue.opacity(0.18), radius: 20, y: 10)
                    .padding(.bottom, 40)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.8)

                // Copy
                VStack(spacing: 16) {
                    Text("Your photos already tell the story")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(OnboardingConstants.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo finds trips in your camera roll using date and location so you can create blogs in seconds.")
                        .font(.title3)
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)
                    
                    Text("Your photos stay private on your device.")
                        .font(.footnote)
                        .foregroundColor(OnboardingConstants.Colors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 40)
                        .opacity(showTrustLine ? 1 : 0)
                        .offset(y: showTrustLine ? 0 : 8)
                }
                
                Spacer()

                // Single CTA: triggers Apple's system permission dialog on first launch.
                Button {
                    Task {
                        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                        if current == .authorized || current == .limited {
                            // Already granted — proceed straight to trip scanner.
                            onResult?(current)
                        } else {
                            AppAnalytics.shared.trackEvent(name: "photo_permission_prompted")
                            await photoAuth.requestAccess()
                            if photoAuth.status == .authorized || photoAuth.status == .limited {
                                AppAnalytics.shared.trackEvent(name: "photo_permission_granted")
                            }
                            onResult?(photoAuth.status)
                        }
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OnboardingConstants.Colors.doneButtonBlue)
                        .clipShape(Capsule())
                        .shadow(color: OnboardingConstants.Colors.doneButtonBlue.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 8)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            startStaggeredAnimation()
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
