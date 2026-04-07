//
//  AtmosphericWaveformView.swift
//  fastblog
//
//  Custom animated waveform bars with a cyan→green gradient (in-app camera, Bloggo Gallery detail, etc.).
//

import SwiftUI

/// Animated waveform bars with a cyan→green gradient, mirroring the in-app camera Vibe control.
struct AtmosphericWaveformView: View {
    var isActive: Bool
    // Heights of the 12 bars (symmetric waveform shape)
    private let heights: [CGFloat] = [5, 9, 15, 20, 13, 22, 18, 22, 13, 20, 9, 5]
    // Per-bar animation delays matching the prototype
    private let delays: [Double] = [0.00, 0.07, 0.14, 0.21, 0.28, 0.35, 0.42, 0.35, 0.28, 0.21, 0.07, 0.00]

    // Internal driver so repeatForever kicks off on appear even when isActive is
    // already true (e.g. returning to camera with Vibe toggled on and persisted).
    @State private var animating = false

    var body: some View {
        // 12×2pt bars + 11×1pt spacing = 35pt wide so the shape fits 36–44pt circular buttons without clipping.
        HStack(spacing: 1) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(appChromeBaseRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: animating ? [.cyan, .green] : [Color.white.opacity(0.45), Color.white.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: heights[i])
                    .scaleEffect(y: animating ? 1 : 0.42, anchor: .center)
                    .animation(
                        animating
                            ? .easeInOut(duration: 0.65 + Double(i % 4) * 0.12)
                                .repeatForever(autoreverses: true)
                                .delay(delays[i])
                            : .easeInOut(duration: 0.2),
                        value: animating
                    )
            }
        }
        .frame(width: 36, height: 26)
        .shadow(color: animating ? .cyan.opacity(0.55) : .clear, radius: animating ? 5 : 0)
        .onAppear {
            Task { @MainActor in
                animating = isActive
            }
        }
        .onChange(of: isActive) { _, active in
            animating = active
        }
    }
}
