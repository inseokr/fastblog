//
//  OnboardingFlowView.swift
//  Capper
//

import Photos
import SwiftUI

enum OnboardingStep {
    case splash
    case cameraRollToBlog
    case problemStatement
    case neighborhoodIntro
    case neighborhood
    case photoPermissionOnboarding
    case tripDistanceFromHome
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
                    step = .cameraRollToBlog
                }
            } else if step == .cameraRollToBlog {
                CameraRollToBlogView {
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
                NeighborhoodSelectionView(
                    onSelect: {
                        step = .photoPermissionOnboarding
                    },
                    onBack: {
                        step = .neighborhoodIntro
                    }
                )
            } else if step == .photoPermissionOnboarding {
                PhotoPermissionOnboardingView(
                    photoAuth: photoAuth,
                    onResult: { resultStatus in
                        if resultStatus == .authorized {
                            step = .tripDistanceFromHome
                        } else if resultStatus == .limited {
                            OnboardingStore.hasCompletedOnboarding = true
                            onComplete()
                        } else if resultStatus == .denied || resultStatus == .restricted {
                            step = .photoPermissionDenied
                        }
                    },
                    onBack: {
                        step = .neighborhood
                    }
                )
            } else if step == .tripDistanceFromHome {
                TripDistanceFromHomeOnboardingView(
                    onContinue: {
                        OnboardingStore.hasCompletedOnboarding = true
                        onComplete()
                    },
                    onBack: {
                        step = .photoPermissionOnboarding
                    }
                )
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
        /// Only the denied screen needs status observation: returning from Settings does not call `onResult`.
        /// Avoid handling `.limited` / `.authorized` here while on the permission step — `onResult` already does, and
        /// duplicating would invoke `onComplete()` twice.
        .onChange(of: photoAuth.status) { _, newStatus in
            guard step == .photoPermissionDenied else { return }
            switch newStatus {
            case .authorized:
                step = .tripDistanceFromHome
            case .limited:
                OnboardingStore.hasCompletedOnboarding = true
                onComplete()
            default:
                break
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Marquee width measurement
private struct MarqueePillWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - ProblemStatementView
struct ProblemStatementView: View {
    var onContinue: () -> Void

    // Staggered animation phases
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showMomentTags = false
    @State private var showPunchline = false
    @State private var showButton = false
    @State private var buttonGlow = false

    // Marquee
    private let marqueeStart = Date()
    private let marqueeItems: [(String, String)] = [
        ("☕", "Morning outing"),
        ("🌆", "City walk"),
        ("🏖️", "Weekend trip"),
        ("🥾", "Day hike"),
        ("✈️", "Long vacation"),
        ("🎉", "Night out"),
    ]
    // Fallback width used until measurement arrives; overwritten on first layout pass.
    @State private var measuredPillWidth: CGFloat = 830

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
                    Text("Thousands of photos sitting in your camera roll. No story written.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)

                    // Phase 3: Moment type chips — auto-scrolling marquee
                    marqueePillsRow
                        .padding(.top, 16)
                        .padding(.leading, -32) // bleed past the VStack's leading inset to the screen edge
                        .opacity(showMomentTags ? 1 : 0)
                        .offset(y: showMomentTags ? 0 : 8)

                    // Phase 4: Punchline
                    (Text("Turn any moment ")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    + Text("into a story.")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue))
                    .padding(.top, 20)
                    .opacity(showPunchline ? 1 : 0)
                    .offset(y: showPunchline ? 0 : 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 32)
                
                // Phase 4: Bottom buttons
                VStack(spacing: 0) {
                    Spacer()

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.3), radius: buttonGlow ? 20 : 10, x: 0, y: 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    VStack(spacing: 4) {
                        Text("By continuing, you agree to Bloggo's")
                            .foregroundColor(.white.opacity(0.35))

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

    private func momentTag(_ emoji: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(emoji).font(.system(size: 14))
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    private var marqueePillsRow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
            let elapsed = CGFloat(tl.date.timeIntervalSince(marqueeStart))
            let speed: CGFloat = 46
            // Use measured width so the loop point aligns exactly with content,
            // eliminating the jitter jump.
            let offset = -(elapsed * speed).truncatingRemainder(dividingBy: measuredPillWidth)

            GeometryReader { _ in
                HStack(spacing: 10) {
                    ForEach(0..<12, id: \.self) { i in
                        momentTag(marqueeItems[i % marqueeItems.count].0,
                                  marqueeItems[i % marqueeItems.count].1)
                    }
                }
                .fixedSize()
                .offset(x: offset)
                .background(
                    GeometryReader { geo in
                        // The HStack has 11 gaps for 12 pills; one set of 6 scrolls
                        // 6 pill-widths + 6 gaps = (totalWidth + 1 gap) / 2.
                        Color.clear.preference(
                            key: MarqueePillWidthKey.self,
                            value: (geo.size.width + 10) / 2
                        )
                    }
                )
            }
        }
        .frame(height: 34)
        .clipped()
        .onPreferenceChange(MarqueePillWidthKey.self) { w in
            guard w > 0 else { return }
            measuredPillWidth = w
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
            showMomentTags = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.2)) {
            showPunchline = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.5)) {
            showButton = true
        }

        // Button glow pulse starts after button appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                buttonGlow = true
            }
        }
    }
}

