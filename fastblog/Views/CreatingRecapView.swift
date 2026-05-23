//
//  CreatingRecapView.swift
//  Capper
//

import SwiftUI

struct CreatingRecapView: View {
    /// Optional cancel handler — if nil, the Cancel button is hidden.
    var onCancel: (() -> Void)? = nil
    /// When non-nil, drives the displayed percentage from real build progress (0.0–1.0).
    /// When nil, a time-based simulated animation is used instead.
    var externalProgress: Double? = nil

    @State private var ringTrim: CGFloat = 0
    @State private var ringRotation: Double = 0
    @State private var assembledStep: Int = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0
    @State private var colorProgress: CGFloat = 0
    /// Displayed progress percentage (0-100). Driven by externalProgress when available.
    @State private var progressPercent: Int = 0

    private let navyBlue = Color(red: 5/255, green: 10/255, blue: 48/255)
    /// Total animation duration for the simulated-progress fallback path.
    private let totalDuration: TimeInterval = 5.0

    private let earlyStepLabels = [
        "Selecting your photos…",
        "Organizing moments…"
    ]

    var body: some View {
        ZStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                navyBlue.opacity(colorProgress)
            }
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()
                buildingAnimation
                messageSection
                Spacer()

                // Cancel button — gray, soft, bottom center
                if let cancel = onCancel {
                    Button(action: cancel) {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
        }
        .onChange(of: externalProgress) { _, newValue in
            guard let p = newValue else { return }
            let target = min(Int(p * 100), 99)
            withAnimation(.easeOut(duration: 0.25)) {
                progressPercent = target
            }
            // Advance the step label when real progress crosses the early-label threshold
            if stepLabelIndex < 2 && p >= 0.1 {
                withAnimation(.easeInOut(duration: 0.25)) { stepLabelIndex = 2 }
            }
        }
    }

    private var buildingAnimation: some View {
        ZStack {
            // Outer rotating dashed ring (construction / progress feel)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    style: StrokeStyle(lineWidth: 3, dash: [8, 8])
                )
                .foregroundColor(.blue.opacity(0.4))
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(ringRotation))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: ringRotation)

            // Filling progress ring
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.8), value: ringTrim)

            // Small "building block" icons that assemble in
            ForEach(0..<3, id: \.self) { index in
                buildingNode(at: index)
            }

            // Central app logo with subtle pulse
            Image("ScanIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .scaleEffect(pulseScale)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseScale)
        }
        .frame(width: 200, height: 200)
    }

    private func buildingNode(at index: Int) -> some View {
        let angle = Double(index) * 120 - 60
        let radius: CGFloat = 72
        let x = radius * cos(angle * .pi / 180)
        let y = radius * sin(angle * .pi / 180)
        let iconName = ["photo.fill", "text.alignleft", "sparkles"][index]
        let visible = assembledStep > index

        return Image(systemName: iconName)
            .font(.system(size: 20))
            .foregroundColor(.blue.opacity(visible ? 0.9 : 0))
            .scaleEffect(visible ? 1 : 0.3)
            .offset(x: x, y: y)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: visible)
    }

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text("We're creating your Recap Blog!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Group {
                if stepLabelIndex < earlyStepLabels.count {
                    Text(earlyStepLabels[stepLabelIndex])
                } else {
                    // Show live percentage in the final stage
                    Text("\(progressPercent)%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .animation(.easeInOut(duration: 0.3), value: stepLabelIndex)

            Text("Please do not leave this screen")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 24)
    }

    private func startAnimations() {
        // Background slowly transitions to navy blue
        withAnimation(.easeIn(duration: 4.5)) {
            colorProgress = 1
        }

        // Progress ring fills over ~1.8s
        ringTrim = 1

        // Dashed ring rotation (continuous)
        ringRotation = 360

        // Gentle pulse on logo
        pulseScale = 1.08

        // Assemble nodes one by one
        for step in 1...3 {
            let delay = 0.4 + Double(step) * 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                assembledStep = step
            }
        }

        // Cycle through early step labels, then switch to percentage mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.25)) { stepLabelIndex = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.25)) { stepLabelIndex = 2 }
            // Only run the simulated counter when no real progress signal is wired up
            guard externalProgress == nil else { return }
            let tickInterval = 0.05
            let steps = Int((totalDuration - 2.2) / tickInterval)
            for i in 0..<steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * tickInterval) {
                    let raw = Int(Double(i) / Double(steps) * 99)
                    withAnimation(.easeOut(duration: tickInterval)) {
                        progressPercent = min(raw, 99) // never show 100% until complete
                    }
                }
            }
        }
    }
}

#Preview {
    CreatingRecapView(onCancel: { })
}

