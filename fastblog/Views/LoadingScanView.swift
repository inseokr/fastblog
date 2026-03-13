//
//  LoadingScanView.swift
//  fastblog
//

import SwiftUI

private let loadingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

struct LoadingScanView: View {
    var message: String = "Finding your trips…"
    /// When true, renders with a semi-transparent blurred background instead of solid navy.
    var isOverlay: Bool = false
    /// When non-nil, shows a percentage and drives step labels from real progress instead of timer.
    var progress: Double? = nil
    /// When non-nil, shows a gray Cancel button at the bottom.
    var onCancel: (() -> Void)? = nil
    /// When non-nil, shows a primary "Use Camera" button at the bottom.
    var onUseCamera: (() -> Void)? = nil
    /// When non-nil, shows an X close button in the top-right corner.
    var onClose: (() -> Void)? = nil

    @State private var ringRotation: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0
    @State private var nodeFade: [Bool] = [false, false, false]

    private let timerStepLabels = [
        "Organizing…",
        "Grouping days into trips…",
        "Almost done…"
    ]

    private let nodeIcons = ["mappin.and.ellipse", "photo.on.rectangle.angled", "sparkles"]

    /// Step label driven by real progress value.
    private var progressStepLabel: String {
        guard let p = progress else { return timerStepLabels[stepLabelIndex] }
        switch p {
        case ..<0.20: return "Organizing…"
        case 0.20..<0.40: return "Filtering trip photos…"
        case 0.40..<0.85: return "Grouping days into trips…"
        default: return "Almost done…"
        }
    }

    var body: some View {
        ZStack {
            if isOverlay {
                // Blur the content behind, then tint with semi-transparent navy
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                loadingBackground.opacity(0.65)
                    .ignoresSafeArea()
            } else {
                loadingBackground
                    .ignoresSafeArea()
            }

            ZStack {
                scanAnimation

                VStack(spacing: 36) {
                    messageSection

                    if let onUseCamera {
                        Button {
                            onUseCamera()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Use Camera")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.18, green: 0.40, blue: 0.78),
                                        Color(red: 0.25, green: 0.35, blue: 0.72)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        }
                    } else if let onCancel {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 32)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(10)
                        }
                    }
                }
                .offset(y: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
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
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: ringRotation)

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
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseScale)
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
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: visible)
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(progressStepLabel)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: progressStepLabel)

            if let progress {
                Text("\(Int(progress * 100))%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.5))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: Int(progress * 100))
                    .padding(.top, 4)
            } else {
                Text("This may take a moment")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Animations

    private func startAnimations() {
        // Dashed outer ring spins continuously
        ringRotation = 360

        // Gentle pulse on central icon
        pulseScale = 1.12

        // Orbit nodes pop in one by one
        for index in 0..<3 {
            let delay = 0.3 + Double(index) * 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                nodeFade[index] = true
            }
        }

        // Cycle step labels only when no real progress is driving them
        if progress == nil {
            for idx in 1..<timerStepLabels.count {
                let delay = 1.0 + Double(idx) * 1.4
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        stepLabelIndex = idx
                    }
                }
            }
        }
    }
}

#Preview {
    LoadingScanView(message: "Scanning your trips…")
}
