//
//  TripDistanceFromHomeOnboardingView.swift
//  Capper
//

import SwiftUI

/// Shown after full photo library access: lets the user set how far from home counts as a “trip” for scanning.
struct TripDistanceFromHomeOnboardingView: View {
    var onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles
    @State private var showIcon = false
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showControls = false

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
                        Text(" ")
                            .font(.title)
                            .fontWeight(.bold)
                            .opacity(0)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
                    .padding(.top, OnboardingConstants.Layout.titleTopPadding)
                }

                Spacer(minLength: 12)

                Image(systemName: "location.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.2), radius: 16, y: 8)
                    .padding(.bottom, 28)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.85)

                VStack(spacing: 14) {
                    Text("Distance from home")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo ignores photos taken closer than this to your home. So everyday shots stay out of your blogs.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)
                }

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Exclude photos closer than")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Text("\(Int(tripExclusionRadius)) miles")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }

                    Slider(
                        value: Binding(
                            get: { tripExclusionRadius },
                            set: { newValue in
                                tripExclusionRadius = newValue
                                NeighborhoodStore.tripExclusionRadiusMiles = newValue
                            }
                        ),
                        in: 5...200,
                        step: 1
                    )
                    .tint(OnboardingConstants.Colors.doneButtonBlue)

                    VStack(alignment: .leading, spacing: 10) {
                        hintRow(
                            "You can change this anytime in Settings > My home. Bloggo rescans when you release the slider."
                        )
                        hintRow(
                            "Use a shorter distance to include more nearby outings."
                        )
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(appChromeBaseRadius: 16, style: .continuous))
                .padding(.horizontal, OnboardingConstants.Layout.horizontalPadding)
                .opacity(showControls ? 1 : 0)
                .offset(y: showControls ? 0 : 10)

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OnboardingConstants.Colors.doneButtonBlue)
                        .clipShape(Capsule())
                        .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showControls ? 1 : 0)
                .offset(y: showControls ? 0 : 10)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles
            startStaggeredAnimation()
        }
    }

    private func hintRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.yellow.opacity(0.9))
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startStaggeredAnimation() {
        let duration: TimeInterval = 0.45
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            showIcon = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.15)) {
            showHeadline = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.4)) {
            showBody = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.65)) {
            showControls = true
        }
    }
}

#Preview {
    TripDistanceFromHomeOnboardingView(onContinue: {})
}
