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

            splashLogo

            ZStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(.white)
                    Text("to")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Bloggo")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(Color(red: 200/255, green: 235/255, blue: 255/255))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.top, 80)

                VStack(spacing: 0) {
                    Button(action: onFinish) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
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
                .frame(maxHeight: .infinity, alignment: .bottom)
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

    // MARK: - Subviews

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
