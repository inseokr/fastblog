//
//  TripNearbyShareViews.swift
//  fastblog
//
//  UI for QR + Multipeer nearby trip sharing (host sheet, receive sheet, QR image).
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - QR

enum TripShareQRCodeGenerator {
    static func image(from string: String, scale: CGFloat = 8) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct TripShareQRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let ui = TripShareQRCodeGenerator.image(from: payload) {
                Image(uiImage: ui)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                Text("Could not build QR")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Host

/// Scroll content shared by the standalone host sheet and the blog-settings inline overlay.
struct TripNearbyShareHostScrollContent: View {
    @ObservedObject var controller: TripNearbyShareSessionController
    @State private var preparingTooSlow = false

    private var siriRadiationPhase: TripNearbySiriRadiationPhase {
        switch controller.phase {
        case .hostingAdvertising:
            return .searching
        case .hostingConnected, .transferring:
            return .linked
        default:
            return .idle
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nearby share")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "Have your friend open Bloggo, scan this QR (or enter the code), then accept on both phones. Photos and trip details transfer over an encrypted device-to-device link on Wi‑Fi or Bluetooth."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let url = controller.receiveURLForQR {
                    VStack(spacing: 12) {
                        TripShareQRCodeView(payload: url.absoluteString)
                            .frame(maxWidth: .infinity)
                        Text("Code: \(controller.sessionCode)")
                            .font(.title)
                            .fontWeight(.semibold)
                            .monospaced()
                            .frame(maxWidth: .infinity)
                    }
                }

                switch controller.phase {
                case .hostingPreparing:
                    VStack(spacing: 6) {
                        ProgressView("Preparing trip…")
                        if preparingTooSlow {
                            Text("This is taking a moment for larger photo collections…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                case .hostingAdvertising:
                    Label("Waiting for a nearby device…", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                case .hostingConnected(let name):
                    Label("Connected to \(name)", systemImage: "link")
                        .foregroundStyle(.blue)
                case .transferring(let cur, let total):
                    ProgressView(value: Double(cur), total: Double(total)) {
                        Text("Sending photos \(cur) of \(total)")
                    }
                case .succeeded:
                    Label("Trip sent successfully", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let msg):
                    Text(msg)
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
            .padding()
        }
        .modifier(TripNearbySiriRadiationModifier(phase: siriRadiationPhase, cornerRadius: 18))
        .onChange(of: controller.phase) { oldPhase, newPhase in
            TripNearbyShareHaptics.playForPhaseTransition(from: oldPhase, to: newPhase)
        }
        .task(id: controller.phase) {
            guard case .hostingPreparing = controller.phase else {
                preparingTooSlow = false
                return
            }
            preparingTooSlow = false
            try? await Task.sleep(for: .seconds(5))
            if case .hostingPreparing = controller.phase {
                withAnimation { preparingTooSlow = true }
            }
        }
    }
}

/// Full-screen blur + centered card + back chevron, for use inside ``BlogSettingsSheet``.
struct TripNearbyShareHostBlogSettingsOverlay: View {
    let recap: RecapBlogDetail
    @ObservedObject var controller: TripNearbyShareSessionController
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onBack()
                    }
                }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onBack()
                        }
                    } label: {
                        Text("Close")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Spacer(minLength: 0)

                TripNearbyShareHostScrollContent(controller: controller)
                    .frame(maxWidth: 400)
                    .frame(maxHeight: 620)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }

        }
        .preferredColorScheme(.dark)
        .onAppear {
            controller.startHosting(recapDetail: recap)
        }
        .onDisappear {
            controller.cancel()
        }
    }
}

struct TripNearbyShareHostSheet: View {
    let recap: RecapBlogDetail
    @ObservedObject var controller: TripNearbyShareSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TripNearbyShareHostScrollContent(controller: controller)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            controller.cancel()
                            dismiss()
                        } label: {
                            Text("Close")
                                .foregroundStyle(.white)
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            controller.startHosting(recapDetail: recap)
        }
        .onDisappear {
            controller.cancel()
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

// MARK: - Receive

struct TripNearbyShareReceiveSheet: View {
    @ObservedObject var controller: TripNearbyShareSessionController
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput: String = ""
    /// User chose to skip copying imports to the Camera Roll for this completed transfer.
    @State private var skippedCameraRollOffer = false

    private var siriRadiationPhase: TripNearbySiriRadiationPhase {
        switch controller.phase {
        case .receivingBrowsing:
            return .searching
        case .receivingConnected, .transferring:
            return .linked
        default:
            return .idle
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Enter the 6-character code shown on the sender’s screen if pairing is not working automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("6-character code", text: $codeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)

                    receiveStatusView
                }
                .padding()
            }
            .modifier(TripNearbySiriRadiationModifier(phase: siriRadiationPhase, cornerRadius: 18))
            .navigationTitle("Receive trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        controller.cancel()
                        controller.dismissReceiveDeepLinkPresentation()
                        dismiss()
                    } label: {
                        Text("Close")
                            .foregroundStyle(.white)
                    }
                }
            }
            .overlay {
                if let consent = controller.guestManifestConsent {
                    guestConsentOverlay(
                        manifest: consent.0,
                        sender: consent.1,
                        decide: consent.2
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            if !controller.deepLinkPrefillCode.isEmpty {
                codeInput = controller.deepLinkPrefillCode
                controller.startReceiving(filterCode: controller.deepLinkPrefillCode)
            }
        }
        .onChange(of: codeInput) { _, newValue in
            let trimmed = newValue.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != newValue { codeInput = trimmed }
            guard trimmed.count == 6 else { return }
            switch controller.phase {
            case .idle, .failed:
                controller.startReceiving(filterCode: trimmed)
            default:
                break
            }
        }
        .onChange(of: controller.phase) { _, newPhase in
            switch newPhase {
            case .idle, .receivingBrowsing:
                skippedCameraRollOffer = false
            default:
                break
            }
        }
        .onChange(of: controller.phase) { oldPhase, newPhase in
            TripNearbyShareHaptics.playForPhaseTransition(from: oldPhase, to: newPhase)
        }
        .onChange(of: controller.guestManifestConsent != nil) { _, hasConsentPrompt in
            if hasConsentPrompt {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    @ViewBuilder
    private var receiveStatusView: some View {
        switch controller.phase {
        case .idle:
            EmptyView()
        case .receivingBrowsing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching for nearby device…")
                    .foregroundStyle(.secondary)
            }
        case .receivingConnected(let name):
            Label("Connected to \(name)", systemImage: "link")
                .foregroundStyle(.blue)
        case .transferring(let cur, let total):
            ProgressView(value: Double(cur), total: Double(total)) {
                Text("Receiving photos \(cur) of \(total)")
            }
        case .succeeded:
            VStack(alignment: .leading, spacing: 10) {
                Label("Trip added to your blogs.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                if !controller.recentlyImportedCaptureIds.isEmpty, !skippedCameraRollOffer {
                    switch controller.gallerySaveStatus {
                    case .idle:
                        Text(
                            "Optional: copy \(controller.recentlyImportedCaptureIds.count) imported photo\(controller.recentlyImportedCaptureIds.count == 1 ? "" : "s") to your Camera Roll. They stay in Bloggo either way."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task {
                                if !photoAuth.isAuthorized {
                                    await photoAuth.requestAccess()
                                }
                                controller.saveRecentlyImportedToPhotoLibrary()
                            }
                        } label: {
                            Text("Save to Camera Roll")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.gallerySaveStatus == .saving)

                        Button("Not now") {
                            skippedCameraRollOffer = true
                        }
                        .foregroundStyle(.secondary)
                    case .saving:
                        HStack {
                            ProgressView()
                            Text("Saving to Camera Roll…")
                        }
                        .foregroundStyle(.secondary)
                    case .succeeded(let count):
                        Label(
                            "Saved \(count) photo\(count == 1 ? "" : "s") to Camera Roll",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    case .failed(let msg):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(msg)
                                .foregroundStyle(.red)
                            Button("Try again") {
                                Task {
                                    if !photoAuth.isAuthorized {
                                        await photoAuth.requestAccess()
                                    }
                                    controller.saveRecentlyImportedToPhotoLibrary()
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("Not now") {
                                skippedCameraRollOffer = true
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case .failed(let msg):
            Text(msg)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func guestConsentOverlay(
        manifest: TripShareRecapManifestV1,
        sender: String,
        decide: @escaping (Bool) -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Import trip?")
                    .font(.headline)
                Text("“\(manifest.tripTitle)” — \(manifest.photos.count) photos from \(sender).")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Text("Only accept if you trust this person. Data is sent directly between phones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Decline", role: .cancel) {
                        decide(false)
                    }
                    .buttonStyle(.bordered)
                    Button("Import") {
                        decide(true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(28)
        }
    }
}

// MARK: - Siri-style nearby aura

/// Drives the multicolor “Siri orb” style glow while discovering or linked.
enum TripNearbySiriRadiationPhase: Equatable {
    case idle
    case searching
    case linked
}

/// Soft light radiating outward from all four edges (no rings, corners-only blobs, or traveling ripples).
struct TripNearbySiriCardGlow: View {
    let size: CGSize
    let cornerRadius: CGFloat
    let phase: TripNearbySiriRadiationPhase
    let time: TimeInterval

    fileprivate static let siriPalette: [Color] = [
        Color(red: 0.49, green: 0.23, blue: 0.99),
        Color(red: 0.22, green: 0.56, blue: 1.0),
        Color(red: 0.28, green: 0.93, blue: 0.85),
        Color(red: 1.0, green: 0.36, blue: 0.58),
        Color(red: 0.62, green: 0.38, blue: 1.0),
        Color(red: 0.35, green: 0.82, blue: 1.0),
    ]

    private var intensity: CGFloat {
        switch phase {
        case .idle: return 0
        case .searching: return 0.5
        case .linked: return 0.78
        }
    }

    private var speed: Double {
        switch phase {
        case .idle: return 0
        case .searching: return 0.68
        case .linked: return 0.98
        }
    }

    private var resolved: TripNearbySiriGlowLayout {
        let tRaw = time * speed
        let warp = 0.12 * sin(tRaw * 0.33) + 0.08 * sin(tRaw * 0.71 + 0.5)
        let t = tRaw + warp
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let depth = max(min(w, h) * 0.13, 28)
        let cr = min(cornerRadius, min(w, h) * 0.22)
        let spanW = max(w - cr * 1.2, 32)
        let spanH = max(h - cr * 1.2, 32)
        return TripNearbySiriGlowLayout(t: t, w: w, h: h, intensity: intensity, glowDepth: depth, spanW: spanW, spanH: spanH)
    }

    var body: some View {
        let g = resolved
        ZStack {
            TripNearbySiriEdgeRadiate(g: g, edge: 0)
            TripNearbySiriEdgeRadiate(g: g, edge: 1)
            TripNearbySiriEdgeRadiate(g: g, edge: 2)
            TripNearbySiriEdgeRadiate(g: g, edge: 3)
        }
        .frame(width: g.w, height: g.h)
        .compositingGroup()
    }
}

private struct TripNearbySiriGlowLayout {
    let t: Double
    let w: CGFloat
    let h: CGFloat
    let intensity: CGFloat
    let glowDepth: CGFloat
    let spanW: CGFloat
    let spanH: CGFloat
}

private func tripNearbySiriEdgePulse(t: Double, edge: Int) -> CGFloat {
    let phase = Double(edge) * 1.17
    let v = 0.52 + 0.48 * sin(t * 0.5 + phase)
    return CGFloat(v)
}

/// One side: `edge` 0 top, 1 bottom, 2 leading, 3 trailing — gradient shines *outward* from the card edge.
private struct TripNearbySiriEdgeRadiate: View {
    let g: TripNearbySiriGlowLayout
    let edge: Int

    var body: some View {
        let pulse = tripNearbySiriEdgePulse(t: g.t, edge: edge)
        let base = TripNearbySiriCardGlow.siriPalette[edge % TripNearbySiriCardGlow.siriPalette.count]
        let mid = TripNearbySiriCardGlow.siriPalette[(edge + 2) % TripNearbySiriCardGlow.siriPalette.count]
        let a0 = 0.42 * pulse * g.intensity
        let a1 = 0.18 * pulse * g.intensity
        let clear = Color.clear
        let d = g.glowDepth
        let sw = g.spanW
        let sh = g.spanH

        Group {
            switch edge {
            case 0:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(a0), mid.opacity(a1), clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: sw, height: d)
                    .position(x: g.w / 2, y: d / 2)
            case 1:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(a0), mid.opacity(a1), clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: sw, height: d)
                    .position(x: g.w / 2, y: g.h - d / 2)
            case 2:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(a0), mid.opacity(a1), clear],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(width: d, height: sh)
                    .position(x: d / 2, y: g.h / 2)
            default:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(a0), mid.opacity(a1), clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: d, height: sh)
                    .position(x: g.w - d / 2, y: g.h / 2)
            }
        }
        .blur(radius: 12)
        .blendMode(.plusLighter)
    }
}

private struct TripNearbySiriRadiationModifier: ViewModifier {
    var phase: TripNearbySiriRadiationPhase
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        Group {
            if phase == .idle {
                content
            } else {
                content
                    .overlay {
                        GeometryReader { geo in
                            let s = geo.size
                            let margin: CGFloat = 44
                            TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
                                TripNearbySiriCardGlow(
                                    size: CGSize(width: s.width + margin * 2, height: s.height + margin * 2),
                                    cornerRadius: cornerRadius + 6,
                                    phase: phase,
                                    time: context.date.timeIntervalSinceReferenceDate
                                )
                                .frame(width: s.width + margin * 2, height: s.height + margin * 2)
                                .position(x: s.width * 0.5, y: s.height * 0.5)
                            }
                        }
                        .allowsHitTesting(false)
                    }
            }
        }
    }
}
