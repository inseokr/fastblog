//
//  SplashView.swift
//  Capper
//

import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("BlogGo")
                    .font(.system(size: OnboardingConstants.Splash.titleFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(textOpacity)
                    .padding(.top, OnboardingConstants.Layout.titleTopPadding)

                Spacer()

                splashLogo
                    .opacity(iconOpacity)

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            advanceImmediately()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimation()
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

    /// Logo: same icon as the landing CTA (ScanIcon).
    private var splashLogo: some View {
        Image("ScanIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: OnboardingConstants.Splash.logoSize, height: OnboardingConstants.Splash.logoSize)
    }

    private func startAnimation() {
        withAnimation(.easeOut(duration: OnboardingConstants.Splash.fadeInDuration).delay(OnboardingConstants.Splash.fadeInDelay)) {
            iconOpacity = 1
            textOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingConstants.Splash.autoAdvanceInterval) {
            advanceImmediately()
        }
    }

    private func advanceImmediately() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinish()
    }
}
