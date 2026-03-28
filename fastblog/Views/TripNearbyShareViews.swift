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

    private var isRadiating: Bool {
        switch controller.phase {
        case .hostingAdvertising, .hostingConnected, .transferring:
            return true
        default:
            return false
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
        .modifier(TripNearbyRadiatingBorderModifier(isActive: isRadiating))
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
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Back")
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
        .onChange(of: controller.phase) { oldPhase, newPhase in
            triggerHostHaptic(oldPhase: oldPhase, newPhase: newPhase)
        }
    }
}

private func triggerHostHaptic(oldPhase: TripNearbyShareSessionController.Phase, newPhase: TripNearbyShareSessionController.Phase) {
    if oldPhase == newPhase { return }
    switch newPhase {
    case .hostingAdvertising:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .hostingConnected:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .transferring:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    case .succeeded:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .failed:
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    default:
        break
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
                        Button("Close") {
                            controller.cancel()
                            dismiss()
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
        .onChange(of: controller.phase) { oldPhase, newPhase in
            triggerHostHaptic(oldPhase: oldPhase, newPhase: newPhase)
        }
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

    private var isRadiating: Bool {
        switch controller.phase {
        case .receivingBrowsing, .receivingConnected, .transferring:
            return true
        default:
            return false
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
            .modifier(TripNearbyRadiatingBorderModifier(isActive: isRadiating))
            .navigationTitle("Receive trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        controller.cancel()
                        controller.dismissReceiveDeepLinkPresentation()
                        dismiss()
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
            triggerReceiveHaptic(oldPhase: oldPhase, newPhase: newPhase)
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

    private func triggerReceiveHaptic(oldPhase: TripNearbyShareSessionController.Phase, newPhase: TripNearbyShareSessionController.Phase) {
        if oldPhase == newPhase { return }
        switch newPhase {
        case .receivingBrowsing:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .receivingConnected:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .transferring:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        case .succeeded:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        default:
            break
        }
    }
}

private struct TripNearbyRadiatingBorderModifier: ViewModifier {
    let isActive: Bool
    @State private var animatePulse = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(isActive ? 0.85 : 0),
                                Color.cyan.opacity(isActive ? 0.6 : 0),
                                Color.blue.opacity(isActive ? 0.85 : 0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? 2.5 : 0
                    )
                    .shadow(color: Color.blue.opacity(isActive ? (animatePulse ? 0.75 : 0.25) : 0), radius: animatePulse ? 22 : 8)
                    .padding(4)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animatePulse)
                    .onAppear { animatePulse = true }
            }
    }
}
