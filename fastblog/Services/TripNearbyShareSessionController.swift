//
//  TripNearbyShareSessionController.swift
//  fastblog
//
//  Nearby trip transfer: QR/deep link session code + MultipeerConnectivity (encrypted link-level crypto).
//  Mutual consent on host (invitation) and guest (manifest). Abuse: session code acts as a short shared secret.
//

import Foundation
import MultipeerConnectivity
import os
import Photos
import UIKit

/// Owns one `MCSession` for a single nearby transfer lifecycle.
@MainActor
final class TripNearbyShareSessionController: NSObject, ObservableObject {

    static let shared = TripNearbyShareSessionController()
    private static let logger = Logger(subsystem: "com.fastblog.app", category: "TripNearbyShare")

    enum Phase: Equatable {
        case idle
        case hostingPreparing
        case hostingAdvertising
        case hostingConnected(peerName: String)
        case receivingBrowsing
        case receivingConnected(peerName: String)
        case transferring(current: Int, total: Int)
        case succeeded
        case failed(String)
    }

    enum GallerySaveStatus: Equatable {
        case idle
        case saving
        case succeeded(Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Guest must accept the manifest before JPEG resources are accepted into the blog store.
    @Published private(set) var guestManifestConsent: (TripShareRecapManifestV1, senderName: String, decide: (Bool) -> Void)?
    @Published private(set) var sessionCode: String = ""
    @Published private(set) var receiveURLForQR: URL?

    /// Capture identifiers for the most recently imported blog (included photos only).
    @Published private(set) var recentlyImportedCaptureIds: [String] = []
    /// Tracks the optional “save to Gallery” step after import.
    @Published private(set) var gallerySaveStatus: GallerySaveStatus = .idle
    /// Set by `fastblog://receive-trip` so `ContentView` can present the receive sheet.
    @Published var presentReceiveFromDeepLink: Bool = false
    @Published var deepLinkPrefillCode: String = ""
    @Published private(set) var debugEvents: [String] = []

    private var session: MCSession!
    /// Nonisolated reference used by advertiser/browser delegates that run off the main actor.
    private nonisolated(unsafe) var _sessionRef: MCSession?
    private var myPeerID: MCPeerID!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private enum ActiveRole {
        case none
        case host
        case guest
    }

    private var activeRole: ActiveRole = .none
    private var codeFilter: String = ""

    private struct HostExportPayload {
        var manifestJSON: Data
        var resourceQueue: [(name: String, url: URL)]
        var tempRoot: URL
    }

    private var hostExport: HostExportPayload?
    private var hostSendingIndex: Int = 0
    private var hostRemotePeer: MCPeerID?
    private var hostGuestAcceptedManifest: Bool = false
    /// Pre-built manifest payload (0x01 prefix + JSON). Stored nonisolated-unsafe so the
    /// MCSession delegate can send it directly on the MC thread without a main-actor hop.
    private nonisolated(unsafe) var _hostManifestPayload: Data?

    private var guestManifestDecoded: TripShareRecapManifestV1?
    /// Photo index from resource name → copied temp file (order matches manifest `photos`).
    private var guestReceivedPhotosByOrder: [Int: URL] = [:]
    /// Reel index from resource name → copied temp `.mov` file.
    private var guestReceivedReelsByOrder: [Int: URL] = [:]
    private var guestAcceptedManifest: Bool = false
    private var guestInvitedPeers: Set<ObjectIdentifier> = []

    private override init() {
        super.init()
        myPeerID = MCPeerID(displayName: Self.deviceDisplayName())
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        _sessionRef = session
        session.delegate = self
        logDebug("Session initialized as peer '\(myPeerID.displayName)' with service '\(TripShareNearbyConfig.multipeerServiceType)'.")
        logNearbyConfigurationWarningsIfAny()
    }

    /// Called from app delegate / `onOpenURL` for `fastblog://receive-trip?code=…`.
    func handleReceiveTripDeepLink(code: String?) {
        deepLinkPrefillCode = code?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        presentReceiveFromDeepLink = true
    }

    func dismissReceiveDeepLinkPresentation() {
        presentReceiveFromDeepLink = false
        deepLinkPrefillCode = ""
    }

    // MARK: - Host

    func startHosting(recapDetail: RecapBlogDetail) {
        let includedPhotoCount = recapDetail.days
            .flatMap(\.placeStops)
            .flatMap(\.photos)
            .filter(\.isIncluded)
            .count
        logDebug("Host start requested for trip '\(recapDetail.title)' (\(includedPhotoCount) included photos).")
        resetForNewSession()
        activeRole = .host
        phase = .hostingPreparing
        sessionCode = Self.makeSessionCode()
        receiveURLForQR = Self.receiveTripURL(code: sessionCode)
        logDebug("Host prepared session code \(sessionCode).")
        guard verifyRuntimeNearbyConfiguration() else { return }

        Task {
            do {
                let (manifest, images, reelsByOrder) = try await TripShareRecapExporter.makePayload(from: recapDetail)
                let json = try JSONEncoder().encode(manifest)
                let (root, resourceQueue) = try Self.writeResourcesToTemp(images: images, reelsByOrder: reelsByOrder)
                await MainActor.run {
                    self.hostExport = HostExportPayload(manifestJSON: json, resourceQueue: resourceQueue, tempRoot: root)
                    self.logDebug("Host payload prepared: \(manifest.photos.count) manifest photos, \(resourceQueue.count) resource files (\(reelsByOrder.count) reels).")
                    self.beginAdvertising()
                }
            } catch {
                await MainActor.run {
                    self.logDebug("Host payload preparation failed: \(error.localizedDescription)")
                    self.phase = .failed(error.localizedDescription)
                    self.teardown(resetRole: true)
                }
            }
        }
    }

    private func beginAdvertising() {
        guard activeRole == .host, let export = hostExport else { return }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        // Pre-build the manifest payload so it can be sent immediately on the MC thread
        // upon connection, without waiting for a main-actor hop.
        var payload = Data([0x01])
        payload.append(export.manifestJSON)
        _hostManifestPayload = payload
        let info = [
            TripShareNearbyConfig.discoverySessionCodeKey: sessionCode,
            TripShareNearbyConfig.discoveryRoleKey: TripShareNearbyConfig.discoveryRoleHost
        ]
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: info,
            serviceType: TripShareNearbyConfig.multipeerServiceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        phase = .hostingAdvertising
        logDebug("Advertising started with discovery info \(info).")
    }

    // MARK: - Guest

    func startReceiving(filterCode: String) {
        logDebug("Guest browse requested with raw code '\(filterCode)'.")
        phase = .idle
        resetForNewSession()
        activeRole = .guest
        codeFilter = filterCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = "0123456789ABCDEF"
        guard codeFilter.count == 6, codeFilter.allSatisfy({ allowed.contains($0) }) else {
            logDebug("Guest code validation failed for '\(codeFilter)'.")
            phase = .failed("Enter the 6-character code from the sender’s QR.")
            activeRole = .none
            return
        }
        guard verifyRuntimeNearbyConfiguration() else { return }
        sessionCode = codeFilter
        guestManifestDecoded = nil
        guestReceivedPhotosByOrder = [:]
        guestReceivedReelsByOrder = [:]
        guestAcceptedManifest = false
        guestInvitedPeers = []
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: TripShareNearbyConfig.multipeerServiceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        phase = .receivingBrowsing
        logDebug("Guest browsing started with filter code \(codeFilter).")
    }

    /// Cancels advertising/browsing and tears down the session.
    func cancel() {
        logDebug("Cancel requested by UI.")
        teardown(resetRole: true)
        phase = .idle
    }

    // MARK: - Internals

    private func resetForNewSession() {
        logDebug("Resetting state for new nearby session.")
        guestManifestConsent = nil
        hostExport = nil
        _hostManifestPayload = nil
        hostSendingIndex = 0
        hostRemotePeer = nil
        hostGuestAcceptedManifest = false
        guestManifestDecoded = nil
        guestReceivedPhotosByOrder = [:]
        guestReceivedReelsByOrder = [:]
        guestAcceptedManifest = false
        guestInvitedPeers = []
        receiveURLForQR = nil
        recentlyImportedCaptureIds = []
        gallerySaveStatus = .idle
        session.disconnect()
    }

    private func teardown(resetRole: Bool) {
        logDebug("Tearing down session. resetRole=\(resetRole)")
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        if let exp = hostExport {
            try? FileManager.default.removeItem(at: exp.tempRoot)
        }
        hostExport = nil
        _hostManifestPayload = nil
        session.disconnect()
        if resetRole {
            activeRole = .none
            codeFilter = ""
            sessionCode = ""
            recentlyImportedCaptureIds = []
            gallerySaveStatus = .idle
        }
    }

    private static func makeSessionCode() -> String {
        String(format: "%06X", UInt32.random(in: 0...0xFF_FFFF))
    }

    private static func receiveTripURL(code: String) -> URL {
        var c = URLComponents()
        c.scheme = "fastblog"
        c.host = "receive-trip"
        c.queryItems = [URLQueryItem(name: "code", value: code)]
        return c.url!
    }

    private static func writeResourcesToTemp(images: [Data], reelsByOrder: [Int: Data]) throws -> (URL, [(name: String, url: URL)]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloggo_trip_share_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var queue: [(name: String, url: URL)] = []
        for (i, data) in images.enumerated() {
            let photoURL = root.appendingPathComponent("bloggo-photo-\(i).jpg")
            try data.write(to: photoURL)
            queue.append(("bloggo-photo-\(i).jpg", photoURL))
            if let reelData = reelsByOrder[i] {
                let reelURL = root.appendingPathComponent("bloggo-reel-\(i).mov")
                try reelData.write(to: reelURL)
                queue.append(("bloggo-reel-\(i).mov", reelURL))
            }
        }
        return (root, queue)
    }

    private static func deviceDisplayName() -> String {
        let n = UIDevice.current.name
        if n.count <= 20 { return n }
        return String(n.prefix(17)) + "…"
    }

    private func sendManifestToGuest(_ peer: MCPeerID) {
        guard let json = hostExport?.manifestJSON else { return }
        logDebug("Sending manifest (\(json.count) bytes) to \(peer.displayName).")
        var payload = Data([0x01])
        payload.append(json)
        do {
            try session.send(payload, toPeers: [peer], with: .reliable)
        } catch {
            logDebug("Manifest send failed: \(error.localizedDescription)")
            phase = .failed("Could not send trip info.")
            teardown(resetRole: true)
        }
    }

    private func sendNextPhotoResource(to peer: MCPeerID) {
        guard let exp = hostExport else { return }
        guard hostSendingIndex < exp.resourceQueue.count else {
            logDebug("All resources sent to \(peer.displayName).")
            phase = .succeeded
            teardown(resetRole: false)
            activeRole = .none
            return
        }
        let resource = exp.resourceQueue[hostSendingIndex]
        phase = .transferring(current: hostSendingIndex + 1, total: exp.resourceQueue.count)
        logDebug("Sending resource \(resource.name) to \(peer.displayName).")
        session.sendResource(at: resource.url, withName: resource.name, toPeer: peer) { [weak self] err in
            Task { @MainActor in
                guard let self else { return }
                if let err {
                    self.logDebug("Resource send failed (\(resource.name)): \(err.localizedDescription)")
                    self.phase = .failed(err.localizedDescription)
                    self.teardown(resetRole: true)
                    return
                }
                self.hostSendingIndex += 1
                self.sendNextPhotoResource(to: peer)
            }
        }
    }

    private func finalizeGuestImport() {
        guard let manifest = guestManifestDecoded else { return }
        let expectedResources = Self.expectedResourceCount(for: manifest)
        let receivedCount = guestReceivedPhotosByOrder.count + guestReceivedReelsByOrder.count
        guard guestReceivedPhotosByOrder.count == manifest.photos.count,
              receivedCount == expectedResources else {
            logDebug("Finalize failed: \(guestReceivedPhotosByOrder.count) photos, \(guestReceivedReelsByOrder.count) reels of \(manifest.photos.count) photos / \(expectedResources) total resources.")
            phase = .failed("Incomplete transfer.")
            teardown(resetRole: true)
            return
        }
        do {
            var datas: [Data] = []
            datas.reserveCapacity(manifest.photos.count)
            for i in 0..<manifest.photos.count {
                guard let url = guestReceivedPhotosByOrder[i] else {
                    throw TripShareRecapImportError.photoCountMismatch
                }
                datas.append(try Data(contentsOf: url))
            }
            var reelsByOrder: [Int: Data] = [:]
            for (order, url) in guestReceivedReelsByOrder {
                reelsByOrder[order] = try Data(contentsOf: url)
            }
            recentlyImportedCaptureIds = try CreatedRecapBlogStore.shared.importNearbySharedRecapBlog(
                manifest: manifest,
                images: datas,
                reelsByOrder: reelsByOrder
            )
            for url in guestReceivedPhotosByOrder.values {
                try? FileManager.default.removeItem(at: url)
            }
            for url in guestReceivedReelsByOrder.values {
                try? FileManager.default.removeItem(at: url)
            }
            guestReceivedPhotosByOrder = [:]
            guestReceivedReelsByOrder = [:]
            phase = .succeeded
            logDebug("Guest import succeeded for trip '\(manifest.tripTitle)'.")
            teardown(resetRole: false)
            activeRole = .none
        } catch {
            logDebug("Guest import failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            teardown(resetRole: true)
        }
    }

    /// Copies the most recently imported in-app capture images into the user’s iOS Photos gallery.
    func saveRecentlyImportedToPhotoLibrary() {
        let ids = recentlyImportedCaptureIds
        guard !ids.isEmpty else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            gallerySaveStatus = .failed("Photos permission not granted.")
            return
        }

        gallerySaveStatus = .saving

        // We intentionally load images on the main actor to avoid Swift 6 'Sendable' / concurrency violations
        // with UIImage. Users trigger this manually after import completes.
        let service = AppCapturePhotoService.shared
        var payloads: [AppCapturePhotoService.PhotosExportPayload] = []
        payloads.reserveCapacity(ids.count)

        for id in ids {
            guard let uuid = AppCapturePhotoService.uuid(from: id) else { continue }
            if let payload = service.preferredPhotosExport(captureId: uuid) {
                payloads.append(payload)
            }
        }

        guard !payloads.isEmpty else {
            gallerySaveStatus = .failed("Could not load imported photos to save.")
            return
        }

        let saveCount = payloads.count
        PHPhotoLibrary.shared().performChanges({
            for payload in payloads {
                switch payload {
                case .image(let image):
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                case .video(let url):
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            }
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    self.gallerySaveStatus = .succeeded(saveCount)
                } else {
                    self.gallerySaveStatus = .failed(error?.localizedDescription ?? "Save failed.")
                }
            }
        })
    }

    private static func photoOrder(fromResourceName name: String) -> Int? {
        guard name.hasPrefix("bloggo-photo-"), name.hasSuffix(".jpg") else { return nil }
        let mid = name.dropFirst("bloggo-photo-".count).dropLast(".jpg".count)
        return Int(mid)
    }

    private static func reelOrder(fromResourceName name: String) -> Int? {
        guard name.hasPrefix("bloggo-reel-"), name.hasSuffix(".mov") else { return nil }
        let mid = name.dropFirst("bloggo-reel-".count).dropLast(".mov".count)
        return Int(mid)
    }

    private static func expectedResourceCount(for manifest: TripShareRecapManifestV1) -> Int {
        manifest.photos.count + manifest.photos.filter { $0.reelByteCount != nil }.count
    }

    private nonisolated static func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        return d
    }

    private func verifyRuntimeNearbyConfiguration() -> Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let warnings = TripShareNearbyConfig.runtimeConfigWarnings(infoDictionary: info)
        guard warnings.isEmpty else {
            let combined = warnings.joined(separator: " | ")
            logDebug("Nearby runtime config warnings: \(combined)")
            phase = .failed("Nearby share configuration issue: \(combined)")
            activeRole = .none
            return false
        }
        return true
    }

    private func logNearbyConfigurationWarningsIfAny() {
        let info = Bundle.main.infoDictionary ?? [:]
        let warnings = TripShareNearbyConfig.runtimeConfigWarnings(infoDictionary: info)
        for warning in warnings {
            logDebug("Config warning at launch: \(warning)")
        }
    }

    private func logDebug(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
        let stamp = Self.debugDateFormatter.string(from: Date())
        debugEvents.append("[\(stamp)] \(message)")
        if debugEvents.count > 60 {
            debugEvents.removeFirst(debugEvents.count - 60)
        }
    }

    private static let debugDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - MCSessionDelegate

extension TripNearbyShareSessionController: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Send manifest immediately on the MC thread when connected — avoids a full
        // main-actor round-trip before the guest can receive it.
        if state == .connected, let payload = _hostManifestPayload {
            try? session.send(payload, toPeers: [peerID], with: .reliable)
        }
        Task { @MainActor in
            self.logDebug("Session state with \(peerID.displayName): \(Self.describe(state: state)).")
            switch state {
            case .connected:
                if self.activeRole == .host {
                    self.phase = .hostingConnected(peerName: peerID.displayName)
                    self.hostRemotePeer = peerID
                } else if self.activeRole == .guest {
                    self.phase = .receivingConnected(peerName: peerID.displayName)
                }
            case .connecting:
                break
            case .notConnected:
                if self.phase != .succeeded && self.phase != .idle {
                    if case .failed = self.phase {} else {
                        self.phase = .failed("Disconnected.")
                    }
                    self.teardown(resetRole: true)
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard !data.isEmpty else { return }
        let kind = data[0]

        // Decode the manifest on the MC thread immediately — don't wait for the main actor.
        // Only the thin UI update (setting guestManifestConsent) goes to main actor.
        if kind == 0x01, data.count > 1 {
            let jsonData = Data(data.dropFirst())
            let decoded = try? Self.jsonDecoder().decode(TripShareRecapManifestV1.self, from: jsonData)
            Task { @MainActor in
                guard self.activeRole == .guest else { return }
                self.logDebug("Received manifest (\(data.count) bytes) from \(peerID.displayName).")
                guard let manifest = decoded else {
                    self.logDebug("Manifest decode failed.")
                    self.phase = .failed("Invalid trip data.")
                    self.teardown(resetRole: true)
                    return
                }
                self.guestManifestDecoded = manifest
                self.guestManifestConsent = (
                    manifest,
                    peerID.displayName,
                    { [weak self] accept in
                        guard let self else { return }
                        self.logDebug("Guest manifest consent decision for \(peerID.displayName): \(accept ? "accept" : "decline").")
                        self.guestManifestConsent = nil
                        self.guestAcceptedManifest = accept
                        let reply = Data([0x02, accept ? 0x01 : 0x00])
                        try? session.send(reply, toPeers: [peerID], with: .reliable)
                        if !accept {
                            self.phase = .idle
                            self.teardown(resetRole: true)
                        }
                    }
                )
            }
            return
        }

        Task { @MainActor in
            self.logDebug("Received control packet kind=0x\(String(format: "%02X", kind)) size=\(data.count) from \(peerID.displayName).")
            if kind == 0x02, data.count >= 2, self.activeRole == .host {
                let accept = data[1] == 0x01
                self.hostGuestAcceptedManifest = accept
                if accept, let peer = self.hostRemotePeer {
                    self.logDebug("Host received manifest acceptance from \(peer.displayName).")
                    self.hostSendingIndex = 0
                    self.sendNextPhotoResource(to: peer)
                } else {
                    self.logDebug("Host received manifest decline from \(peerID.displayName).")
                    self.phase = .idle
                    self.teardown(resetRole: true)
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            guard self.activeRole == .guest, self.guestAcceptedManifest else { return }
            if let error {
                self.logDebug("Resource receive failed (\(resourceName)): \(error.localizedDescription)")
                self.phase = .failed(error.localizedDescription)
                self.teardown(resetRole: true)
                return
            }
            guard let localURL else { return }
            if let order = Self.photoOrder(fromResourceName: resourceName) {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bloggo_in_photo_\(order)_\(UUID().uuidString).jpg")
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: localURL, to: dest)
                    self.guestReceivedPhotosByOrder[order] = dest
                } catch {
                    self.logDebug("Failed to persist received resource \(resourceName): \(error.localizedDescription)")
                    self.phase = .failed("Could not save a received photo.")
                    self.teardown(resetRole: true)
                    return
                }
            } else if let order = Self.reelOrder(fromResourceName: resourceName) {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bloggo_in_reel_\(order)_\(UUID().uuidString).mov")
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: localURL, to: dest)
                    self.guestReceivedReelsByOrder[order] = dest
                } catch {
                    self.logDebug("Failed to persist received reel \(resourceName): \(error.localizedDescription)")
                    self.phase = .failed("Could not save a received reel.")
                    self.teardown(resetRole: true)
                    return
                }
            } else {
                return
            }
            self.logDebug("Received resource \(resourceName) (\(self.guestReceivedPhotosByOrder.count) photos, \(self.guestReceivedReelsByOrder.count) reels).")
            if let m = self.guestManifestDecoded {
                let n = self.guestReceivedPhotosByOrder.count + self.guestReceivedReelsByOrder.count
                let total = Self.expectedResourceCount(for: m)
                self.phase = .transferring(current: n, total: total)
                if self.guestReceivedPhotosByOrder.count == m.photos.count,
                   n >= total {
                    self.finalizeGuestImport()
                }
            }
        }
    }
}

// MARK: - Advertiser

extension TripNearbyShareSessionController: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // The session code in the QR already acts as the shared secret, so auto-accept.
        invitationHandler(true, _sessionRef)
        Task { @MainActor in
            self.logDebug("Host auto-accepted invitation from \(peerID.displayName).")
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.logDebug("Advertising failed to start: \(error.localizedDescription)")
            self.phase = .failed("Could not advertise nearby: \(error.localizedDescription)")
            self.teardown(resetRole: true)
        }
    }
}

// MARK: - Browser

extension TripNearbyShareSessionController: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard self.activeRole == .guest else { return }
            self.logDebug("Guest found peer \(peerID.displayName) with discovery info \(info ?? [:]).")
            guard info?[TripShareNearbyConfig.discoveryRoleKey] == TripShareNearbyConfig.discoveryRoleHost else {
                self.logDebug("Ignoring peer \(peerID.displayName): role is not host.")
                return
            }
            if !self.codeFilter.isEmpty {
                let theirs = info?[TripShareNearbyConfig.discoverySessionCodeKey] ?? ""
                guard theirs.uppercased() == self.codeFilter else {
                    self.logDebug("Ignoring peer \(peerID.displayName): code mismatch ours=\(self.codeFilter) theirs=\(theirs).")
                    return
                }
            }
            let oid = ObjectIdentifier(peerID)
            guard !self.guestInvitedPeers.contains(oid) else {
                self.logDebug("Skipping duplicate invitation to \(peerID.displayName).")
                return
            }
            self.guestInvitedPeers.insert(oid)
            self.logDebug("Inviting peer \(peerID.displayName).")
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 25)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.logDebug("Browsing failed to start: \(error.localizedDescription)")
            self.phase = .failed("Could not look for nearby devices: \(error.localizedDescription)")
            self.teardown(resetRole: true)
        }
    }
}

private extension TripNearbyShareSessionController {
    static func describe(state: MCSessionState) -> String {
        switch state {
        case .notConnected: return "notConnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        @unknown default: return "unknown"
        }
    }
}
