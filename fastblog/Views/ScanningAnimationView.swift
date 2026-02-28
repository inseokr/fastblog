//
//  ScanningAnimationView.swift
//  Capper
//

import SwiftUI

/// Shazam-style scanning animation: pulsing concentric rings with the app icon at center. Suggests "finding" or "discovering" trips.
struct ScanningAnimationView: View {
    let ringCount: Int
    let ringSpacing: CGFloat
    let pulseDuration: Double
    var showIcon: Bool
    /// The name of the image asset to show at the center. Defaults to "ScanIcon".
    var iconName: String

    init(ringCount: Int = 4, ringSpacing: CGFloat = 28, pulseDuration: Double = 1.8, showIcon: Bool = true, iconName: String = "ScanIcon") {
        self.ringCount = ringCount
        self.ringSpacing = ringSpacing
        self.pulseDuration = pulseDuration
        self.showIcon = showIcon
        self.iconName = iconName
    }

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { index in
                ScanningRingView(
                    delay: Double(index) * (pulseDuration / Double(ringCount)),
                    duration: pulseDuration
                )
                .scaleEffect(0.4 + CGFloat(index) * 0.2)
            }
            if showIcon {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
            }
        }
        .frame(width: 200, height: 200)
    }
}

private struct ScanningRingView: View {
    let delay: Double
    let duration: Double
    @State private var isExpanded: Bool = false

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.6),
                        Color.blue.opacity(0.5),
                        Color.white.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .scaleEffect(isExpanded ? 1.4 : 0.6)
            .opacity(isExpanded ? 0 : 0.7)
            .onAppear {
                withAnimation(
                    .easeOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isExpanded = true
                }
            }
    }
}

#Preview {
    ZStack {
        Color(red: 5/255, green: 10/255, blue: 48/255)
            .ignoresSafeArea()
        ScanningAnimationView()
    }
    .preferredColorScheme(.dark)
}
