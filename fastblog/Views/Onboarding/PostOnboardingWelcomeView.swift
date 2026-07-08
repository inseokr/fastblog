//
//  PostOnboardingWelcomeView.swift
//  fastblog
//

import SwiftUI

/// One-time welcome after onboarding: two paths — in-app camera or camera-roll scan.
struct PostOnboardingWelcomeView: View {
    var onCaptureMoments: () -> Void
    var onFindPastTrips: () -> Void

    @State private var showHeadline = false
    @State private var showActions = false

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
                Spacer(minLength: 32)

                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 16))
                    .padding(.bottom, 20)
                    .opacity(showHeadline ? 1 : 0)
                    .scaleEffect(showHeadline ? 1 : 0.9)

                VStack(spacing: 10) {
                    Text("You're all set")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(OnboardingConstants.Colors.primaryText)
                        .multilineTextAlignment(.center)

                    Text("How would you like to get started?")
                        .font(.body)
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .opacity(showHeadline ? 1 : 0)
                .offset(y: showHeadline ? 0 : 8)

                VStack(spacing: 14) {
                    welcomeAction(
                        icon: "camera.fill",
                        tint: OnboardingConstants.Colors.doneButtonBlue,
                        title: "Capture Moments",
                        detail: "Everyday moments save to My Places. Start a trip blog when you travel.",
                        isPrimary: true,
                        action: onCaptureMoments
                    )

                    welcomeAction(
                        icon: "photo.on.rectangle.angled",
                        tint: Color(red: 0.45, green: 0.85, blue: 0.55),
                        title: "Find Past Trips",
                        detail: "Scan your camera roll for trips you've already taken.",
                        isPrimary: false,
                        action: onFindPastTrips
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 10)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.light)
        .onAppear {
            let duration: TimeInterval = 0.45
            withAnimation(.easeOut(duration: duration)) {
                showHeadline = true
            }
            withAnimation(.easeOut(duration: duration).delay(0.25)) {
                showActions = true
            }
        }
    }

    private func welcomeAction(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isPrimary ? 0.28 : 0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(OnboardingConstants.Colors.primaryText)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(OnboardingConstants.Colors.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingConstants.Colors.tertiaryText)
            }
            .padding(16)
            .background(
                isPrimary
                    ? tint.opacity(0.18)
                    : OnboardingConstants.Colors.controlBackground
            )
            .clipShape(RoundedRectangle(appChromeBaseRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 16, style: .continuous)
                    .stroke(isPrimary ? tint.opacity(0.35) : OnboardingConstants.Colors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PostOnboardingWelcomeView(onCaptureMoments: {}, onFindPastTrips: {})
}
