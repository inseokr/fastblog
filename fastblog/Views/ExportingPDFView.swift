//
//  ExportingPDFView.swift
//  fastblog
//

import SwiftUI

struct ExportingPDFView: View {
    @State private var ringTrim: CGFloat = 0
    @State private var ringRotation: Double = 0
    @State private var assembledStep: Int = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0
    @State private var progressPercent: Int = 0
    @State private var colorProgress: CGFloat = 0

    private let navyBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

    private let earlyStepLabels = [
        "Laying out your blog...",
        "Rendering photos..."
    ]

    var body: some View {
        ZStack {
            navyBlue
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()
                exportAnimation
                messageSection
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
        }
    }

    private var exportAnimation: some View {
        ZStack {
            // Outer rotating dashed ring
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

            // Export-themed building block icons
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
        let iconName = ["doc.text", "photo.fill", "arrow.down.doc"][index]
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
            Text("Exporting to PDF...")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Group {
                if stepLabelIndex < earlyStepLabels.count {
                    Text(earlyStepLabels[stepLabelIndex])
                } else {
                    Text("\(progressPercent)%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .animation(.easeInOut(duration: 0.3), value: stepLabelIndex)
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
            // Animate percentage from 0 → 99 — keeps ticking until dismissed
            let tickInterval = 0.06
            let totalTicks = 200 // enough headroom (~12s before hitting 99)
            for i in 0..<totalTicks {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * tickInterval) {
                    // Ease-out curve: fast at start, slows toward 99
                    let t = Double(i) / Double(totalTicks)
                    let eased = 1 - pow(1 - t, 2.5)
                    let raw = Int(eased * 99)
                    withAnimation(.easeOut(duration: tickInterval)) {
                        progressPercent = min(raw, 99)
                    }
                }
            }
        }
    }
}

#Preview {
    ExportingPDFView()
}
