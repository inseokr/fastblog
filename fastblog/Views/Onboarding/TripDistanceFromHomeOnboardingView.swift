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
    @State private var didPlaySliderThumbHint = false

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
                    .foregroundColor(OnboardingConstants.Colors.doneButtonBlue)
                    .shadow(color: OnboardingConstants.Colors.doneButtonBlue.opacity(0.18), radius: 16, y: 8)
                    .padding(.bottom, 28)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.85)

                VStack(spacing: 14) {
                    Text("Distance from home")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(OnboardingConstants.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo saves everyday shots to My Places. Beyond this distance, we'll ask if you want a trip blog.")
                        .font(.title3)
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
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
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                        Spacer()
                        Text("\(Int(tripExclusionRadius)) miles")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
                    }

                    TripExclusionMilesSlider(
                        value: Binding(
                            get: { tripExclusionRadius },
                            set: { newValue in
                                tripExclusionRadius = newValue
                                NeighborhoodStore.tripExclusionRadiusMiles = newValue
                            }
                        ),
                        range: 5...200,
                        step: 1,
                        tint: OnboardingConstants.Colors.doneButtonBlue
                    )

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
                .background(OnboardingConstants.Colors.controlBackground)
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
        .preferredColorScheme(.light)
        .onAppear {
            tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles
            startStaggeredAnimation()
        }
        .onChange(of: showControls) { _, isVisible in
            if isVisible { scheduleSliderThumbHint() }
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
                .foregroundColor(OnboardingConstants.Colors.secondaryText)
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

    private func scheduleSliderThumbHint() {
        guard !didPlaySliderThumbHint else { return }
        didPlaySliderThumbHint = true
        let defaultRadius = NeighborhoodStore.tripExclusionRadiusMiles
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            // Slide right to hint that this is a horizontal drag
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                tripExclusionRadius = min(defaultRadius + 30, 200)
            }
            try? await Task.sleep(for: .milliseconds(600))
            // Snap back to the default
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                tripExclusionRadius = defaultRadius
            }
        }
    }
}

// MARK: - Miles slider (custom thumb so we can hint vertical drag affordance)

private struct TripExclusionMilesSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var tint: Color

    private let thumbDiameter: CGFloat = 28
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbR = thumbDiameter / 2
            let usable = max(width - thumbDiameter, 1)
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbCenterX = thumbR + CGFloat(t) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(tint)
                    .frame(width: max(trackHeight, thumbCenterX), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                    .offset(x: thumbCenterX - thumbR)
            }
            .frame(height: thumbDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, thumbR), width - thumbR)
                        let fraction = (x - thumbR) / usable
                        let raw = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = min(range.upperBound, max(range.lowerBound, stepped))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Exclude photos closer than")
            .accessibilityValue("\(Int(value)) miles")
            .accessibilityAdjustableAction { direction in
                let delta: Double
                switch direction {
                case .increment: delta = step
                case .decrement: delta = -step
                @unknown default: return
                }
                let next = value + delta
                value = min(range.upperBound, max(range.lowerBound, next))
            }
        }
        .frame(height: thumbDiameter)
    }
}

#Preview {
    TripDistanceFromHomeOnboardingView(onContinue: {})
}
