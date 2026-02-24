//
//  SplashView.swift
//  Capper
//

import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @State private var contentOpacity: Double = 0
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("Welcome To")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text("Bloggo")
                    .font(.system(size: OnboardingConstants.Splash.titleFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 4)

                Spacer()

                splashLogo

                Spacer()

                Button(action: onFinish) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 4)
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
            .opacity(contentOpacity)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: OnboardingConstants.Splash.fadeInDuration).delay(OnboardingConstants.Splash.fadeInDelay)) {
                contentOpacity = 1
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showTermsOfService) {
            TermsOfServiceView()
        }
    }

    private var splashBackground: some View {
        LinearGradient(
            colors: [
                OnboardingConstants.Colors.backgroundGradientTop,
                OnboardingConstants.Colors.backgroundGradientBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var splashLogo: some View {
        Image("SplashIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 140, height: 140)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}
