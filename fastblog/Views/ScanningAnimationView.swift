//
//  ScanningAnimationView.swift
//  Capper
//

import SwiftUI

/// Shazam-style scanning animation: pulsing concentric rings with an optional center icon.
struct ScanningAnimationView: View {
    let ringCount: Int
    let ringSpacing: CGFloat
    let pulseDuration: Double
    var showIcon: Bool
    /// The name of the image asset to show at the center. Defaults to "ScanIcon".
    var iconName: String
    /// Optional SF Symbol to use instead of an image asset.
    var systemIconName: String?
    /// Tint for the expanding rings. Defaults to white for dark scan surfaces.
    var ringTint: Color

    /// Same expansion cadence for every ring so pulses stay phase-locked (mixed speeds moiré against the center icon).
    private static let durationMultipliers: [Double] = [1.0, 1.0, 1.0, 1.0]

    init(
        ringCount: Int = 4,
        ringSpacing: CGFloat = 28,
        pulseDuration: Double = 1.8,
        showIcon: Bool = true,
        iconName: String = "ScanIcon",
        systemIconName: String? = nil,
        ringTint: Color = .white
    ) {
        self.ringCount = ringCount
        self.ringSpacing = ringSpacing
        self.pulseDuration = pulseDuration
        self.showIcon = showIcon
        self.iconName = iconName
        self.systemIconName = systemIconName
        self.ringTint = ringTint
    }

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { index in
                let multiplier = Self.durationMultipliers[index % Self.durationMultipliers.count]
                ScanningRingView(
                    delay: Double(index) * (pulseDuration / Double(ringCount)),
                    duration: pulseDuration * multiplier,
                    tint: ringTint
                )
                .scaleEffect(0.4 + CGFloat(index) * 0.2)
            }
            if showIcon {
                centerIcon
            }
        }
        .frame(width: 200, height: 200)
    }

    @ViewBuilder
    private var centerIcon: some View {
        if let systemIconName {
            RewindAnimationIcon(systemIconName: systemIconName)
        } else {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        }
    }
}

struct RewindAnimationIcon: View {
    var systemIconName: String = "gobackward"
    var circleSide: CGFloat = 102
    var symbolSize: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.50))
                .frame(width: circleSide, height: circleSide)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)

            Image(systemName: systemIconName)
                .font(.system(size: symbolSize, weight: .heavy))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.black.opacity(0.84))
        }
    }
}

private struct ScanningRingView: View {
    let delay: Double
    let duration: Double
    let tint: Color
    @State private var isExpanded: Bool = false
    private let specks: [RingSpeck] = [
        RingSpeck(x: 0.19, y: 0.33, size: 2.2, opacity: 0.36),
        RingSpeck(x: 0.31, y: 0.17, size: 1.4, opacity: 0.28),
        RingSpeck(x: 0.68, y: 0.20, size: 2.0, opacity: 0.34),
        RingSpeck(x: 0.82, y: 0.42, size: 1.6, opacity: 0.30),
        RingSpeck(x: 0.73, y: 0.76, size: 2.4, opacity: 0.32),
        RingSpeck(x: 0.38, y: 0.82, size: 1.8, opacity: 0.26),
        RingSpeck(x: 0.16, y: 0.62, size: 1.5, opacity: 0.30)
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.94),
                            tint.opacity(0.70),
                            tint.opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.4
                )
            GeometryReader { proxy in
                ForEach(specks) { speck in
                    Circle()
                        .fill(Color.black.opacity(speck.opacity))
                        .frame(width: speck.size, height: speck.size)
                        .position(
                            x: proxy.size.width * speck.x,
                            y: proxy.size.height * speck.y
                        )
                }
            }
            .clipShape(Circle())
        }
        .scaleEffect(isExpanded ? 1.4 : 0.6)
        .opacity(isExpanded ? 0 : 0.78)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isExpanded = true
                }
            }
    }
}

private struct RingSpeck: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}

#Preview {
    ZStack {
        Color(red: 5/255, green: 10/255, blue: 48/255)
            .ignoresSafeArea()
        ScanningAnimationView(systemIconName: "gobackward")
    }
    .preferredColorScheme(.dark)
}
