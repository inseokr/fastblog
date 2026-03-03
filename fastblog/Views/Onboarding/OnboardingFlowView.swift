//
//  OnboardingFlowView.swift
//  Capper
//

import Photos
import SwiftUI

enum OnboardingStep {
    case splash
    case problemStatement
    case neighborhoodIntro
    case neighborhood
    case photoPermissionOnboarding
    case photoPermissionDenied
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
                    step = .problemStatement
                }
            } else if step == .problemStatement {
                ProblemStatementView {
                    step = .neighborhoodIntro
                }
            } else if step == .neighborhoodIntro {
                NeighborhoodExplainerView {
                    step = .neighborhood
                }
            } else if step == .neighborhood {
                NeighborhoodSelectionView {
                    step = .photoPermissionOnboarding
                }
            } else if step == .photoPermissionOnboarding {
                PhotoPermissionOnboardingView(photoAuth: photoAuth)
            } else {
                PhotosPermissionView(
                    status: photoAuth.status,
                    onOpenSettings: { openSettings() },
                    onContinueWithoutScanning: {
                        OnboardingStore.hasCompletedOnboarding = true
                        onComplete()
                    }
                )
            }
        }
        .onChange(of: photoAuth.status) { _, newStatus in
            if step == .photoPermissionOnboarding || step == .photoPermissionDenied {
                if newStatus == .authorized || newStatus == .limited {
                    OnboardingStore.hasCompletedOnboarding = true
                    onComplete()
                } else if newStatus == .denied || newStatus == .restricted {
                    step = .photoPermissionDenied
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - ProblemStatementView
struct ProblemStatementView: View {
    var onContinue: () -> Void

    // Staggered animation phases
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showPunchline = false
    @State private var showButton = false
    @State private var buttonGlow = false

    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

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

            ZStack {
                // Top-left text
                VStack(alignment: .leading, spacing: 0) {
                    // Phase 1: Headline
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bloggo removes")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("blank page anxiety.")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.white)
                    }
                    .opacity(showHeadline ? 1 : 0)
                    .offset(y: showHeadline ? 0 : 8)

                    // Phase 2: Body
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thousands of photos.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Zero stories written.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 20)
                    .opacity(showBody ? 1 : 0)
                    .offset(y: showBody ? 0 : 8)

                    // Phase 3: Punchline
                    (Text("We turn them into ")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    + Text("stories.")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue))
                    .padding(.top, 16)
                    .opacity(showPunchline ? 1 : 0)
                    .offset(y: showPunchline ? 0 : 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 32)
                
                // Phase 4: Bottom buttons
                VStack(spacing: 0) {
                    Spacer()

                    Button(action: onContinue) {
                        HStack {
                            Text("Continue")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.3), radius: buttonGlow ? 20 : 10, x: 0, y: 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    HStack(spacing: 4) {
                        Button("Privacy Policy") {
                            showPrivacyPolicy = true
                        }
                        .foregroundColor(.white.opacity(0.5))

                        Text("and")
                            .foregroundColor(.white.opacity(0.35))

                        Button("Terms of Service") {
                            showTermsOfService = true
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    .font(.caption)
                    .padding(.bottom, 32)
                }
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startStaggeredAnimation()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showTermsOfService) {
            TermsOfServiceView()
        }
    }

    private func startStaggeredAnimation() {
        let duration: TimeInterval = 0.5

        withAnimation(.easeOut(duration: duration)) {
            showHeadline = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.4)) {
            showBody = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.8)) {
            showPunchline = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.1)) {
            showButton = true
        }

        // Button glow pulse starts after button appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                buttonGlow = true
            }
        }
    }
}

