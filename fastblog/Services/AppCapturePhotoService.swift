//
//  AppCapturePhotoService.swift
//  fastblog
//
//  Saves in-app camera captures to app-designated storage (Application Support/bloggo_captures/<uuid>/)
//  excluded from iOS backup. Photos are referenced by "bloggo-capture:<uuid>" instead of PHAsset localIdentifier.
//

import CoreLocation
import Foundation
import ImageIO
import Photos
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
        /// User-edited place name from Bloggo Gallery / place editor (survives reopen when not yet in a blog).
        var placeTitle: String?
        /// City / country line shown under the place name.
        var placeSubtitle: String?
        /// `MKPointOfInterestCategory` raw value when resolved from POI search.
        var placeCategory: String?
        /// True when this capture was made in continuous (manual-stop) reel mode.
        var isContinuousReel: Bool?
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

    /// Same as `saveCapture` but persists an optional caption (e.g. nearby trip import).
    @discardableResult
    func saveSharedImport(
        image: UIImage,
        timestamp: Date,
        location: CLLocation?,
        caption: String?,
        momentVideoSourceURL: URL? = nil
    ) throws -> UUID {
        let uuid = UUID()
        let folder = try captureURL(for: uuid)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFolder = folder
        try mutableFolder.setResourceValues(resourceValues)

        guard let jpegData = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let imageURL = folder.appendingPathComponent("image.jpg")
        try jpegData.write(to: imageURL)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let digitizedTime = formatter.string(from: timestamp)

        let meta = CaptureMetadata(
            createdAt: timestamp.timeIntervalSince1970,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            digitizedTime: digitizedTime,
            caption: caption?.isEmpty == true ? nil : caption
        )
        let metaData = try JSONEncoder().encode(meta)
        let metaURL = folder.appendingPathComponent("meta.json")
        try metaData.write(to: metaURL)

        if let momentVideoSourceURL {
            try saveMomentVideo(captureId: uuid, from: momentVideoSourceURL)
        }

        return uuid
    }

    // MARK: - Load image

    private func imageFileURL(for captureId: UUID) -> URL? {
        guard let folder = try? captureURL(for: captureId) else { return nil }
        return folder.appendingPathComponent("image.jpg")
    }

    /// True when `image.jpg` exists on disk — does not decode pixels (safe for filters / validation).
    func imageExists(captureId: UUID) -> Bool {
        guard let imageURL = imageFileURL(for: captureId) else { return false }
        return FileManager.default.fileExists(atPath: imageURL.path)
    }

    /// Convenience: parse identifier and check on-disk image without decoding.
    func imageExists(identifier: String) -> Bool {
        guard let uuid = Self.uuid(from: identifier) else { return false }
        return imageExists(captureId: uuid)
    }

    func loadImage(captureId: UUID) -> UIImage? {
        guard let imageURL = imageFileURL(for: captureId),
              let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }

    /// Convenience: parse identifier and load image.
    func loadImage(identifier: String) -> UIImage? {
        guard let uuid = Self.uuid(from: identifier) else { return nil }
        return loadImage(captureId: uuid)
    }

    /// Downsampled decode for grids / modals — avoids loading full-resolution JPEG into memory.
    func loadThumbnail(captureId: UUID, maxPixelSize: CGFloat) -> UIImage? {
        guard maxPixelSize > 0,
              let imageURL = imageFileURL(for: captureId),
              FileManager.default.fileExists(atPath: imageURL.path) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func loadThumbnail(identifier: String, maxPixelSize: CGFloat) -> UIImage? {
        guard let uuid = Self.uuid(from: identifier) else { return nil }
        return loadThumbnail(captureId: uuid, maxPixelSize: maxPixelSize)
    }

    // MARK: - Load metadata

    struct CaptureInfo {
        var timestamp: Date
        var location: PhotoCoordinate?
        var digitizedTime: String
        var caption: String?
        var placeTitle: String?
        var placeSubtitle: String?
        var placeCategory: String?
        var isContinuousReel: Bool
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
        return CaptureInfo(
            timestamp: timestamp,
            location: loc,
            digitizedTime: meta.digitizedTime,
            caption: meta.caption,
            placeTitle: meta.placeTitle,
            placeSubtitle: meta.placeSubtitle,
            placeCategory: meta.placeCategory,
            isContinuousReel: meta.isContinuousReel == true
        )
    }

    func metadata(identifier: String) -> CaptureInfo? {
        guard let uuid = Self.uuid(from: identifier) else { return nil }
        return metadata(captureId: uuid)
    }

    /// User saved a non-placeholder place name in Bloggo Gallery / place editor.
    func hasUserEditedPlaceMetadata(captureId: UUID) -> Bool {
        guard let title = metadata(captureId: captureId)?.placeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return false }
        return !PlacePlaceholderNaming.isResolvablePlaceholder(title)
    }

    // MARK: - Update metadata flags

    func markAsContinuousReel(captureId: UUID) throws {
        guard let folder = try? captureURL(for: captureId) else { return }
        let metaURL = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              var meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return }
        meta.isContinuousReel = true
        let updated = try JSONEncoder().encode(meta)
        try updated.write(to: metaURL)
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

    /// Updates latitude/longitude in `meta.json` (nil clears stored coordinates).
    func updateLocation(captureId: UUID, coordinate: CLLocationCoordinate2D?) throws {
        guard let folder = try? captureURL(for: captureId) else { return }
        let metaURL = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              var meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return }
        if let coordinate {
            meta.latitude = coordinate.latitude
            meta.longitude = coordinate.longitude
        } else {
            meta.latitude = nil
            meta.longitude = nil
        }
        let updated = try JSONEncoder().encode(meta)
        try updated.write(to: metaURL)
    }

    /// Persists user-edited place name, subtitle, category, and optional map pin into `meta.json`.
    func updatePlaceMetadata(
        captureId: UUID,
        placeTitle: String,
        placeSubtitle: String?,
        placeCategory: String?,
        coordinate: CLLocationCoordinate2D?
    ) throws {
        guard let folder = try? captureURL(for: captureId) else { return }
        let metaURL = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              var meta = try? JSONDecoder().decode(CaptureMetadata.self, from: data) else { return }

        let trimmedTitle = placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.placeTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        let trimmedSubtitle = placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        meta.placeSubtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
        meta.placeCategory = placeCategory
        if let coordinate {
            meta.latitude = coordinate.latitude
            meta.longitude = coordinate.longitude
        }

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

    // MARK: - Vibe file (vibe.m4a inside capture folder)

    private func vibePath(for captureId: UUID) throws -> URL {
        try captureURL(for: captureId).appendingPathComponent("vibe.m4a")
    }

    /// Copies a trimmed vibe m4a file into the capture folder. Call after `saveCapture`.
    func saveVibe(captureId: UUID, from sourceURL: URL) throws {
        let dest = try vibePath(for: captureId)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    /// Returns the local vibe file URL for a capture if it exists on disk.
    func vibeFileURL(for captureId: UUID) -> URL? {
        guard let url = try? vibePath(for: captureId),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Removes only the vibe clip for a capture (keeps the photo and voice memo).
    func deleteVibe(captureId: UUID) {
        guard let url = try? vibePath(for: captureId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Voice memo file (voice_memo.m4a inside capture folder)

    private func voiceMemoPath(for captureId: UUID) throws -> URL {
        try captureURL(for: captureId).appendingPathComponent("voice_memo.m4a")
    }

    /// Copies a recorded voice memo into the capture folder, replacing any existing one.
    /// Call after `saveCapture` once the user explicitly saves a recording from `VoiceMemoRecorderSheet`.
    func saveVoiceMemo(captureId: UUID, from sourceURL: URL) throws {
        let dest = try voiceMemoPath(for: captureId)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    /// Returns the local voice memo file URL for a capture if one exists on disk.
    func voiceMemoFileURL(for captureId: UUID) -> URL? {
        guard let url = try? voiceMemoPath(for: captureId),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Removes only the voice memo for a capture (keeps the photo and vibe).
    func deleteVoiceMemo(captureId: UUID) {
        guard let url = try? voiceMemoPath(for: captureId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Moment video file (moment_video.mov inside capture folder)

    private func momentVideoPath(for captureId: UUID) throws -> URL {
        try captureURL(for: captureId).appendingPathComponent("moment_video.mov")
    }

    /// Copies a short moment video into the capture folder. Call after `saveCapture`.
    func saveMomentVideo(captureId: UUID, from sourceURL: URL) throws {
        let dest = try momentVideoPath(for: captureId)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        Task { @MainActor in
            ImageLoader.shared.invalidateThumbnailCache(for: Self.identifier(for: captureId))
        }
    }

    /// Returns the local moment video file URL for a capture if it exists on disk.
    func momentVideoFileURL(for captureId: UUID) -> URL? {
        guard let url = try? momentVideoPath(for: captureId),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Removes only the moment video for a capture (keeps the photo, vibe, and voice memo).
    func deleteMomentVideo(captureId: UUID) {
        guard let url = try? momentVideoPath(for: captureId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Delete

    func deleteCapture(captureId: UUID) {
        guard let folder = try? captureURL(for: captureId) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Export to Photos

    enum PhotosExportPayload {
        case image(UIImage)
        case video(URL)
    }

    /// Moment video when on disk, otherwise the still image — used for manual and auto-save to the Photo Library.
    func preferredPhotosExport(captureId: UUID) -> PhotosExportPayload? {
        if let videoURL = momentVideoFileURL(for: captureId) {
            return .video(videoURL)
        }
        if let image = loadImage(captureId: captureId) {
            return .image(image)
        }
        return nil
    }

    /// Saves one capture to the user's Photo Library (video preferred over still when both exist).
    func saveToPhotoLibrary(captureId: UUID, completion: @escaping (Bool) -> Void) {
        saveCapturesToPhotoLibrary(captureIds: [captureId], completion: { count, success in
            completion(success && count > 0)
        })
    }

    /// Saves multiple captures in a single Photos transaction.
    func saveCapturesToPhotoLibrary(
        captureIds: [UUID],
        completion: @escaping (_ savedCount: Int, _ success: Bool) -> Void
    ) {
        let payloads = captureIds.compactMap { preferredPhotosExport(captureId: $0) }
        guard !payloads.isEmpty else {
            DispatchQueue.main.async { completion(0, false) }
            return
        }
        PHPhotoLibrary.shared().performChanges {
            for payload in payloads {
                switch payload {
                case .image(let image):
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                case .video(let url):
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            }
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                completion(payloads.count, success)
            }
        }
    }
}
