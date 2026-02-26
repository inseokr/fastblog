//
//  UploadingBlogView.swift
//  fastblog
//

import SwiftUI

struct UploadingBlogView: View {
    @Binding var uploadProgress: (current: Int, total: Int)

    @State private var ringRotation: Double = 0
    @State private var assembledStep: Int = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0

    private let stepLabels = [
        "Preparing your photos…",
        "Uploading to the cloud…",
        "Almost there…"
    ]

    private var progressFraction: CGFloat {
        guard uploadProgress.total > 0 else { return 0 }
        return CGFloat(uploadProgress.current) / CGFloat(uploadProgress.total)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                uploadAnimation
                messageSection
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
        }
    }

    private var uploadAnimation: some View {
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

            // Progress ring that fills based on actual upload progress
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progressFraction)

            // Cloud-themed building block icons that assemble in
            ForEach(0..<3, id: \.self) { index in
                buildingNode(at: index)
            }

            // Central app logo with subtle pulse
            Image("ScanIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .scaleEffect(pulseScale)
        }
        .frame(width: 200, height: 200)
    }

    private func buildingNode(at index: Int) -> some View {
        let angle = Double(index) * 120 - 60
        let radius: CGFloat = 72
        let x = radius * cos(angle * .pi / 180)
        let y = radius * sin(angle * .pi / 180)
        let iconName = ["icloud.and.arrow.up", "photo.fill", "checkmark.circle"][index]
        let visible = assembledStep > index

        return Image(systemName: iconName)
            .font(.system(size: 20))
            .foregroundColor(.blue.opacity(visible ? 0.9 : 0))
            .scaleEffect(visible ? 1 : 0.3)
            .offset(x: x, y: y)
    }

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text("Uploading Your Blog!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(stepLabels[stepLabelIndex])
                .font(.subheadline)
                .foregroundColor(.secondary)
                .animation(.easeInOut(duration: 0.3), value: stepLabelIndex)

            Text("\(uploadProgress.current) of \(uploadProgress.total) photos")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: uploadProgress.current)

            Text("Please do not leave this page")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    private func startAnimations() {
        // Dashed ring rotation (continuous)
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Gentle pulse on logo
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
        }

        // Assemble nodes one by one
        for step in 1...3 {
            let delay = 0.4 + Double(step) * 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    assembledStep = step
                }
            }
        }

        // Cycle step labels
        for idx in 1..<stepLabels.count {
            let delay = 0.6 + Double(idx) * 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    stepLabelIndex = idx
                }
            }
        }
    }
}

#Preview {
    UploadingBlogView(uploadProgress: .constant((3, 12)))
}
