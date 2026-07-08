//
//  NeighborhoodExplainerView.swift
//  fastblog
//

import SwiftUI

struct NeighborhoodExplainerView: View {
    var onContinue: () -> Void

    @State private var contentOpacity: Double = 0

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
                Spacer()

                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .padding(.bottom, 32)

                Text("Set Your Home Area")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                    .padding(.bottom, 16)

                VStack(spacing: 24) {
                    Text("This is your reference point for detecting trips.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)

                    Text("Private. Never shared.")
                        .font(.body)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: onContinue) {
                    Text("Set Home")
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

                Text("You can change this anytime.")
                    .font(.caption)
                    .foregroundColor(OnboardingConstants.Colors.tertiaryText)
                    .padding(.bottom, 32)
            }
            .opacity(contentOpacity)
        }
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                contentOpacity = 1
            }
        }
    }
}
