//
//  MomentVideoTransfer.swift
//  fastblog
//
//  Shared helpers for exporting/importing moment reels (moment_video.mov) across backup and share flows.
//

import CryptoKit
import Foundation

enum MomentVideoTransfer {
    /// On-disk moment reel for an app-capture `RecapPhoto`, when present.
    static func momentVideoURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              let uuid = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.momentVideoFileURL(for: uuid)
    }

    static func loadMomentVideoData(for photo: RecapPhoto) -> Data? {
        guard let url = momentVideoURL(for: photo) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Writes reel bytes into an existing app-capture folder as `moment_video.mov`.
    static func attachMomentVideo(to captureId: UUID, data: Data) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloggo-reel-import-\(UUID().uuidString).mov")
        try data.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }
        try AppCapturePhotoService.shared.saveMomentVideo(captureId: captureId, from: temp)
    }

    static func attachMomentVideo(to captureId: UUID, from sourceURL: URL) throws {
        try AppCapturePhotoService.shared.saveMomentVideo(captureId: captureId, from: sourceURL)
    }
}
