//
//  LoadingScanView.swift
//  fastblog
//

import SwiftUI

private let loadingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

struct LoadingScanView: View {
    var message: String = "Scanning your trips…"

    @State private var ringRotation: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0
    @State private var nodeFade: [Bool] = [false, false, false]

    private let stepLabels = [
        "Reading your photo library…",
        "Grouping days into trips…",
        "Almost done…"
    ]

    private let nodeIcons = ["mappin.and.ellipse", "photo.on.rectangle.angled", "sparkles"]

    var body: some View {
        ZStack {
            loadingBackground
                .ignoresSafeArea()

            VStack(spacing: 36) {
                scanAnimation
                messageSection
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Animation

    private var scanAnimation: some View {
        ZStack {
            // Outer rotating dashed ring — matches CreatingRecapView / UploadingBlogView style
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    style: StrokeStyle(lineWidth: 3, dash: [8, 8])
                )
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(ringRotation))

            // Pulsating concentric rings — the signature scan effect
            ScanningAnimationView(ringCount: 4, ringSpacing: 28, pulseDuration: 1.8, showIcon: false)
                .frame(width: 200, height: 200)

            // Small orbit icons that pop in one by one
            ForEach(0..<3, id: \.self) { index in
                orbitNode(at: index)
            }

            // Central icon with subtle pulse
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .scaleEffect(pulseScale)
        }
        .frame(width: 260, height: 260)
    }

    private func orbitNode(at index: Int) -> some View {
        let angle = Double(index) * 120.0 - 90.0
        let radius: CGFloat = 118
        let x = radius * cos(angle * .pi / 180)
        let y = radius * sin(angle * .pi / 180)
        let visible = nodeFade[index]

        return Image(systemName: nodeIcons[index])
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.4, green: 0.7, blue: 1), Color(red: 0.2, green: 0.4, blue: 1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.3)
            .offset(x: x, y: y)
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(stepLabels[stepLabelIndex])
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: stepLabelIndex)

            Text("This may take a moment")
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Animations

    private func startAnimations() {
        // Dashed outer ring spins continuously
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Gentle pulse on central icon
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
        }

        // Orbit nodes pop in one by one
        for index in 0..<3 {
            let delay = 0.3 + Double(index) * 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    nodeFade[index] = true
                }
            }
        }

        // Cycle step labels
        for idx in 1..<stepLabels.count {
            let delay = 1.0 + Double(idx) * 1.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    stepLabelIndex = idx
                }
            }
        }
    }
}

#Preview {
    LoadingScanView(message: "Scanning your trips…")
}
