//
//  LoadingScanView.swift
//  fastblog
//

import SwiftUI

private let loadingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

struct LoadingScanView: View {
    /// Tint layered on top of `Material` when ``isOverlay`` is true. ``modalGrayGlass`` is for in-modal
    /// loading (e.g. video export); ``tripNavy`` matches the trip scanner overlay.
    enum OverlayTint {
        case tripNavy
        case modalGrayGlass
    }

    var message: String = "Finding your trips…"
    /// When true, renders with a semi-transparent blurred background instead of solid navy.
    var isOverlay: Bool = false
    /// When ``isOverlay`` is true, controls the color wash on top of ``ultraThinMaterial``.
    var overlayTint: OverlayTint = .tripNavy
    /// When non-nil, shows a percentage and drives step labels from real progress instead of timer.
    var progress: Double? = nil
    /// When non-nil, shows a gray Cancel button at the bottom.
    var onCancel: (() -> Void)? = nil
    /// When non-nil, shows a primary "Use Camera" button at the bottom.
    var onUseCamera: (() -> Void)? = nil
    /// When non-nil, shows an X close button in the top-right corner.
    var onClose: (() -> Void)? = nil
    /// Optional override for the secondary progress text.
    var progressStepLabelOverride: ((Double) -> String)? = nil
    /// Optional full-screen background override for non-overlay mode.
    var backgroundColorOverride: Color? = nil
    /// When true, centers the animation + message stack without the lower offset.
    var useCenteredLayout: Bool = false
    /// When false, hides the top-right circular action buttons.
    var showsTopTrailingActions: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var ringRotation: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var stepLabelIndex: Int = 0
    @State private var nodeFade: [Bool] = [false, false, false]
    @State private var showSlowScanHint = false
    @State private var slowScanHintTask: Task<Void, Never>? = nil

    /// Shows the secondary "taking longer" hint only after the user experience delay threshold.
    /// Derived from ~15% over a typical ~4s scan duration (tunable).
    private let slowScanHintDelay: TimeInterval = 4.0 * 1.15

    private let timerStepLabels = [
        "Organizing…",
        "Grouping days into trips…",
        "Almost done…"
    ]

    private let nodeIcons = ["mappin.and.ellipse", "photo.on.rectangle.angled", "sparkles"]

    /// Step label driven by real progress value.
    private var progressStepLabel: String {
        guard let p = progress else { return timerStepLabels[stepLabelIndex] }
        if let progressStepLabelOverride {
            return progressStepLabelOverride(p)
        }
        switch p {
        case ..<0.20: return "Organizing…"
        case 0.20..<0.40: return "Filtering trip photos…"
        case 0.40..<0.85: return "Grouping days into trips…"
        default: return "Almost done…"
        }
    }

    /// When the slow-scan hint is shown, replaces cycling/progress step text so we do not stack two messages.
    private var displayedSecondaryLabel: String {
        showSlowScanHint
            ? "Please wait… it may take longer if photos are in iCloud"
            : progressStepLabel
    }

    /// Non-`useCenteredLayout` stacks the message block with a fixed Y offset; large Dynamic Type
    /// makes that text taller and it overlaps the scan rings. Add clearance and lift the animation slightly.
    private var nonCenteredDynamicTypeClearance: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 0
        case .xLarge:
            return 32
        case .xxLarge:
            return 58
        case .xxxLarge:
            return 86
        case .accessibility1:
            return 108
        case .accessibility2:
            return 128
        case .accessibility3:
            return 148
        case .accessibility4:
            return 166
        case .accessibility5:
            return 184
        @unknown default:
            return 108
        }
    }

    var body: some View {
        ZStack {
            if isOverlay {
                // Blur the content behind, then tint for legibility
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                switch overlayTint {
                case .tripNavy:
                    loadingBackground.opacity(0.65)
                        .ignoresSafeArea()
                case .modalGrayGlass:
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                    Color.white.opacity(0.06)
                        .ignoresSafeArea()
                }
            } else {
                (backgroundColorOverride ?? loadingBackground)
                    .ignoresSafeArea()
            }

            Group {
                if useCenteredLayout {
                    VStack(spacing: dynamicTypeSize >= .xLarge ? 26 : 20) {
                        scanAnimation
                        messageSection
                        actionButtons
                    }
                } else {
                    ZStack {
                        scanAnimation
                            .offset(y: -nonCenteredDynamicTypeClearance * 0.42)
                        VStack(spacing: 36) {
                            messageSection
                            actionButtons
                        }
                        // Keep the text block below the scan animation; extra drop + lift animation when type is large.
                        .offset(y: 240 + nonCenteredDynamicTypeClearance * 0.58)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .topTrailing) {
            if showsTopTrailingActions {
                HStack(spacing: 12) {
                    if let onUseCamera {
                        Button {
                            onUseCamera()
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(10)
                                .background(Color.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                    }
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
                    }
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
            scheduleSlowScanHint()
        }
        .onDisappear {
            slowScanHintTask?.cancel()
            slowScanHintTask = nil
            showSlowScanHint = false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
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
                .appChromeCornerRadius(12)
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
                    .appChromeCornerRadius(10)
            }
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

            Text(displayedSecondaryLabel)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: displayedSecondaryLabel)

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

    private func scheduleSlowScanHint() {
        slowScanHintTask?.cancel()
        showSlowScanHint = false

        slowScanHintTask = Task { [slowScanHintDelay] in
            do {
                try await Task.sleep(nanoseconds: UInt64(slowScanHintDelay * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSlowScanHint = true
                }
            }
        }
    }
}

#Preview {
    LoadingScanView(message: "Scanning your trips…")
}
