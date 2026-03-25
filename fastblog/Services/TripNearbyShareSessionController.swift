//
//  TripNearbyShareSessionController.swift
//  fastblog
//
//  Nearby trip transfer: QR/deep link session code + MultipeerConnectivity (encrypted link-level crypto).
//  Mutual consent on host (invitation) and guest (manifest). Abuse: session code acts as a short shared secret.
//

import Foundation
import MultipeerConnectivity
import Photos
import UIKit

/// Owns one `MCSession` for a single nearby transfer lifecycle.
@MainActor
final class TripNearbyShareSessionController: NSObject, ObservableObject {

    static let shared = TripNearbyShareSessionController()

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
    /// Host must accept an incoming browser invitation before any data moves.
    @Published private(set) var hostInvitation: (peerName: String, decide: (Bool) -> Void)?
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

    private var session: MCSession!
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

    private var hostExport: (manifestJSON: Data, photoURLs: [URL], tempRoot: URL)?
    private var hostSendingIndex: Int = 0
    private var hostRemotePeer: MCPeerID?
    private var hostGuestAcceptedManifest: Bool = false

    private var guestManifestDecoded: TripShareRecapManifestV1?
    /// Photo index from resource name → copied temp file (order matches manifest `photos`).
    private var guestReceivedByOrder: [Int: URL] = [:]
    private var guestAcceptedManifest: Bool = false
    private var guestInvitedPeers: Set<ObjectIdentifier> = []

    private override init() {
        super.init()
        myPeerID = MCPeerID(displayName: Self.deviceDisplayName())
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
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
        resetForNewSession()
        activeRole = .host
        phase = .hostingPreparing
        sessionCode = Self.makeSessionCode()
        receiveURLForQR = Self.receiveTripURL(code: sessionCode)

        Task {
            do {
                let (manifest, images) = try await TripShareRecapExporter.makePayload(from: recapDetail)
                let json = try JSONEncoder().encode(manifest)
                let (root, urls) = try Self.writeJPEGsToTemp(images: images)
                await MainActor.run {
                    self.hostExport = (manifestJSON: json, photoURLs: urls, tempRoot: root)
                    self.beginAdvertising()
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                    self.teardown(resetRole: true)
                }
            }
        }
    }

    private func beginAdvertising() {
        guard activeRole == .host, hostExport != nil else { return }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: [
                TripShareNearbyConfig.discoverySessionCodeKey: sessionCode,
                TripShareNearbyConfig.discoveryRoleKey: TripShareNearbyConfig.discoveryRoleHost
            ],
            serviceType: TripShareNearbyConfig.multipeerServiceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        phase = .hostingAdvertising
    }

    // MARK: - Guest

    func startReceiving(filterCode: String) {
        phase = .idle
        resetForNewSession()
        activeRole = .guest
        codeFilter = filterCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = "0123456789ABCDEF"
        guard codeFilter.count == 6, codeFilter.allSatisfy({ allowed.contains($0) }) else {
            phase = .failed("Enter the 6-character code from the sender’s QR.")
            activeRole = .none
            return
        }
        sessionCode = codeFilter
        guestManifestDecoded = nil
        guestReceivedByOrder = [:]
        guestAcceptedManifest = false
        guestInvitedPeers = []
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: TripShareNearbyConfig.multipeerServiceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        phase = .receivingBrowsing
    }

    /// Cancels advertising/browsing and tears down the session.
    func cancel() {
        teardown(resetRole: true)
        phase = .idle
    }

    // MARK: - Internals

    private func resetForNewSession() {
        hostInvitation = nil
        guestManifestConsent = nil
        hostExport = nil
        hostSendingIndex = 0
        hostRemotePeer = nil
        hostGuestAcceptedManifest = false
        guestManifestDecoded = nil
        guestReceivedByOrder = [:]
        guestAcceptedManifest = false
        guestInvitedPeers = []
        receiveURLForQR = nil
        recentlyImportedCaptureIds = []
        gallerySaveStatus = .idle
        session.disconnect()
    }

    private func teardown(resetRole: Bool) {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        if let exp = hostExport {
            try? FileManager.default.removeItem(at: exp.tempRoot)
        }
        hostExport = nil
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

    private static func writeJPEGsToTemp(images: [Data]) throws -> (URL, [URL]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloggo_trip_share_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, data) in images.enumerated() {
            let url = root.appendingPathComponent("bloggo-photo-\(i).jpg")
            try data.write(to: url)
            urls.append(url)
        }
        return (root, urls)
    }

    private static func deviceDisplayName() -> String {
        let n = UIDevice.current.name
        if n.count <= 20 { return n }
        return String(n.prefix(17)) + "…"
    }

    private func sendManifestToGuest(_ peer: MCPeerID) {
        guard let json = hostExport?.manifestJSON else { return }
        var payload = Data([0x01])
        payload.append(json)
        do {
            try session.send(payload, toPeers: [peer], with: .reliable)
        } catch {
            phase = .failed("Could not send trip info.")
            teardown(resetRole: true)
        }
    }

    private func sendNextPhotoResource(to peer: MCPeerID) {
        guard let exp = hostExport else { return }
        guard hostSendingIndex < exp.photoURLs.count else {
            phase = .succeeded
            teardown(resetRole: false)
            activeRole = .none
            return
        }
        let url = exp.photoURLs[hostSendingIndex]
        let name = "bloggo-photo-\(hostSendingIndex).jpg"
        phase = .transferring(current: hostSendingIndex + 1, total: exp.photoURLs.count)
        session.sendResource(at: url, withName: name, toPeer: peer) { [weak self] err in
            Task { @MainActor in
                guard let self else { return }
                if let err {
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
        guard guestReceivedByOrder.count == manifest.photos.count else {
            phase = .failed("Incomplete transfer.")
            teardown(resetRole: true)
            return
        }
        do {
            var datas: [Data] = []
            datas.reserveCapacity(manifest.photos.count)
            for i in 0..<manifest.photos.count {
                guard let url = guestReceivedByOrder[i] else {
                    throw TripShareRecapImportError.photoCountMismatch
                }
                datas.append(try Data(contentsOf: url))
            }
            recentlyImportedCaptureIds = try CreatedRecapBlogStore.shared.importNearbySharedRecapBlog(manifest: manifest, images: datas)
            for url in guestReceivedByOrder.values {
                try? FileManager.default.removeItem(at: url)
            }
            guestReceivedByOrder = [:]
            phase = .succeeded
            teardown(resetRole: false)
            activeRole = .none
        } catch {
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
        var imagesAndMeta: [(image: UIImage, meta: AppCapturePhotoService.CaptureInfo?)] = []
        imagesAndMeta.reserveCapacity(ids.count)

        for id in ids {
            if let image = service.loadImage(identifier: id) {
                imagesAndMeta.append((image: image, meta: service.metadata(identifier: id)))
            }
        }

        guard !imagesAndMeta.isEmpty else {
            gallerySaveStatus = .failed("Could not load imported photos to save.")
            return
        }

        let saveCount = imagesAndMeta.count
        PHPhotoLibrary.shared().performChanges({
            for item in imagesAndMeta {
                let creation = PHAssetChangeRequest.creationRequestForAsset(from: item.image)
                if let meta = item.meta {
                    creation.creationDate = meta.timestamp
                    if let loc = meta.location {
                        creation.location = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                    }
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

    private nonisolated static func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        return d
    }
}

// MARK: - MCSessionDelegate

extension TripNearbyShareSessionController: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if self.activeRole == .host {
                    self.phase = .hostingConnected(peerName: peerID.displayName)
                    self.hostRemotePeer = peerID
                    self.sendManifestToGuest(peerID)
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
        Task { @MainActor in
            guard !data.isEmpty else { return }
            let kind = data[0]
            if kind == 0x01, data.count > 1, self.activeRole == .guest {
                let jsonData = data.dropFirst()
                do {
                    let manifest = try Self.jsonDecoder().decode(TripShareRecapManifestV1.self, from: Data(jsonData))
                    self.guestManifestDecoded = manifest
                    self.guestManifestConsent = (
                        manifest,
                        peerID.displayName,
                        { [weak self] accept in
                            guard let self else { return }
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
                } catch {
                    self.phase = .failed("Invalid trip data.")
                    self.teardown(resetRole: true)
                }
                return
            }
            if kind == 0x02, data.count >= 2, self.activeRole == .host {
                let accept = data[1] == 0x01
                self.hostGuestAcceptedManifest = accept
                if accept, let peer = self.hostRemotePeer {
                    self.hostSendingIndex = 0
                    self.sendNextPhotoResource(to: peer)
                } else {
                    self.phase = .idle
                    self.teardown(resetRole: true)
                }
                return
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            guard self.activeRole == .guest, self.guestAcceptedManifest else { return }
            if let error {
                self.phase = .failed(error.localizedDescription)
                self.teardown(resetRole: true)
                return
            }
            guard let localURL else { return }
            guard let order = Self.photoOrder(fromResourceName: resourceName) else { return }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("bloggo_in_\(order)_\(UUID().uuidString).jpg")
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: localURL, to: dest)
                self.guestReceivedByOrder[order] = dest
                if let m = self.guestManifestDecoded {
                    let n = self.guestReceivedByOrder.count
                    self.phase = .transferring(current: n, total: m.photos.count)
                    if n >= m.photos.count {
                        self.finalizeGuestImport()
                    }
                }
            } catch {
                self.phase = .failed("Could not save a received photo.")
                self.teardown(resetRole: true)
            }
        }
    }
}

// MARK: - Advertiser

extension TripNearbyShareSessionController: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            self.hostInvitation = (
                peerID.displayName,
                { accept in
                    self.hostInvitation = nil
                    invitationHandler(accept, accept ? self.session : nil)
                }
            )
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
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
            guard info?[TripShareNearbyConfig.discoveryRoleKey] == TripShareNearbyConfig.discoveryRoleHost else { return }
            if !self.codeFilter.isEmpty {
                let theirs = info?[TripShareNearbyConfig.discoverySessionCodeKey] ?? ""
                guard theirs.uppercased() == self.codeFilter else { return }
            }
            let oid = ObjectIdentifier(peerID)
            guard !self.guestInvitedPeers.contains(oid) else { return }
            self.guestInvitedPeers.insert(oid)
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 25)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.phase = .failed("Could not look for nearby devices: \(error.localizedDescription)")
            self.teardown(resetRole: true)
        }
    }
}
