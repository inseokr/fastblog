//
//  AppCapturePhotoService.swift
//  fastblog
//
//  Saves in-app camera captures to app-designated storage (Application Support/bloggo_captures/<uuid>/)
//  excluded from iOS backup. Photos are referenced by "bloggo-capture:<uuid>" instead of PHAsset localIdentifier.
//

import CoreLocation
import Foundation
import UIKit

final class AppCapturePhotoService {
    static let shared = AppCapturePhotoService()
    private init() {}

    // MARK: - Identifier helpers

    static let prefix = "bloggo-capture:"

    static func identifier(for uuid: UUID) -> String {
        "\(prefix)\(uuid.uuidString)"
    }

    static func uuid(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    // MARK: - Root directory

    private var rootURL: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = base.appendingPathComponent("bloggo_captures", isDirectory: true)
            if !FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                // Exclude entire captures folder from iCloud / iTunes backup.
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutable = root
                try mutable.setResourceValues(resourceValues)
            }
            return root
        }
    }

    private func captureURL(for uuid: UUID) throws -> URL {
        try rootURL.appendingPathComponent(uuid.uuidString, isDirectory: true)
    }

    // MARK: - Save

    struct CaptureMetadata: Codable {
        var createdAt: TimeInterval          // Unix timestamp
        var latitude: Double?
        var longitude: Double?
        var digitizedTime: String            // "yyyy:MM:dd HH:mm:ss"
        var caption: String?                 // User-written or blank
    }

    /// Writes `image.jpg` and `meta.json` to a new capture folder.
    /// Returns the UUID used as folder name (and embedded in the identifier).
    @discardableResult
    func saveCapture(
        image: UIImage,
        timestamp: Date,
        location: CLLocation?
    ) throws -> UUID {
        let uuid = UUID()
        let folder = try captureURL(for: uuid)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Exclude folder from backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFolder = folder
        try mutableFolder.setResourceValues(resourceValues)

        // Write image
        guard let jpegData = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let imageURL = folder.appendingPathComponent("image.jpg")
        try jpegData.write(to: imageURL)

        // Compute digitized time using device timezone at capture
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let digitizedTime = formatter.string(from: timestamp)

        let meta = CaptureMetadata(
            createdAt: timestamp.timeIntervalSince1970,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            digitizedTime: digitizedTime,
            caption: nil
        )
        let metaData = try JSONEncoder().encode(meta)
        let metaURL = folder.appendingPathComponent("meta.json")
        try metaData.write(to: metaURL)

        return uuid
    }

    // MARK: - Load image

    func loadImage(captureId: UUID) -> UIImage? {
        guard let folder = try? captureURL(for: captureId) else { return nil }
        let imageURL = folder.appendingPathComponent("image.jpg")
        guard let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }

    /// Convenience: parse identifier and load image.
    func loadImage(identifier: String) -> UIImage? {
        guard let uuid = Self.uuid(from: identifier) else { return nil }
        return loadImage(captureId: uuid)
    }

    // MARK: - Load metadata

    struct CaptureInfo {
        var timestamp: Date
        var location: PhotoCoordinate?
        var digitizedTime: String
        var caption: String?
    }

    func metadata(captureId: UUID) -> CaptureInfo? {
        guard let folder = try? captureURL(for: captureId) else { return nil }
        let metaURL = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return nil }
        let timestamp = Date(timeIntervalSince1970: meta.createdAt)
        var loc: PhotoCoordinate?
        if let lat = meta.latitude, let lon = meta.longitude {
            loc = PhotoCoordinate(latitude: lat, longitude: lon)
        }
        return CaptureInfo(timestamp: timestamp, location: loc, digitizedTime: meta.digitizedTime, caption: meta.caption)
    }

    func metadata(identifier: String) -> CaptureInfo? {
        guard let uuid = Self.uuid(from: identifier) else { return nil }
        return metadata(captureId: uuid)
    }

    // MARK: - Update caption

    func updateCaption(captureId: UUID, caption: String?) throws {
        guard let folder = try? captureURL(for: captureId) else { return }
        let metaURL = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              var meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return }
        meta.caption = caption?.isEmpty == true ? nil : caption
        let updated = try JSONEncoder().encode(meta)
        try updated.write(to: metaURL)
    }

    // MARK: - Enumerate all captures

    /// Returns all capture UUIDs sorted newest-first by createdAt in meta.json.
    func allCaptureIds() -> [UUID] {
        guard let root = try? rootURL else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        let uuids = contents.compactMap { url -> (UUID, TimeInterval)? in
            guard let uuid = UUID(uuidString: url.lastPathComponent) else { return nil }
            let metaURL = url.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return nil }
            return (uuid, meta.createdAt)
        }
        return uuids.sorted { $0.1 > $1.1 }.map(\.0)
    }

    // MARK: - Delete

    func deleteCapture(captureId: UUID) {
        guard let folder = try? captureURL(for: captureId) else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
