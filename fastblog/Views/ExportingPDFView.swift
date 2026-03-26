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

    private let navyBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

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
            // Outer rotating dashed ring — runs forever
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    style: StrokeStyle(lineWidth: 3, dash: [8, 8])
                )
                .foregroundColor(.blue.opacity(0.4))
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(ringRotation))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: ringRotation)

            // Inner progress ring — fills and empties in a loop so it never stops moving
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: ringTrim)

            // Export-themed building block icons
            ForEach(0..<3, id: \.self) { index in
                buildingNode(at: index)
            }

            // Central app logo with subtle pulse — runs forever
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
        VStack(spacing: 8) {
            Text("Opening Exporting Options...")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("This may take a moment")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private func startAnimations() {
        // Progress ring: loop 0 → 1 → 0 so it never stops (repeatForever on the view handles the cycle)
        ringTrim = 1

        // Dashed ring rotation — continuous
        ringRotation = 360

        // Gentle pulse on logo — continuous
        pulseScale = 1.08

        // Assemble nodes one by one (quick, then they stay visible)
        for step in 1...3 {
            let delay = 0.4 + Double(step) * 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                assembledStep = step
            }
        }
    }
}

#Preview {
    ExportingPDFView()
}
