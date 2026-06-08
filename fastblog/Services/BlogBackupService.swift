//
//  BlogBackupService.swift
//  fastblog
//
//  Portable ZIP backup: full RecapBlogDetail JSON + JPEGs (+ optional moment reels) keyed by RecapPhoto.id.
//

import CoreLocation
import CryptoKit
import Foundation
import Photos
import UIKit
import ZIPFoundation

/// `fractionComplete` is in `0...1` for UI (e.g. percentage).
typealias BlogBackupProgressHandler = @Sendable (_ fractionComplete: Double) -> Void

// MARK: - Format constants

enum BlogBackupFormat {
    static let schemaVersion = 1
    static let manifestFilename = "manifest.json"
    static let detailFilename = "recapBlogDetail.json"
    static let createdRecapFilename = "createdRecapBlog.json"
    static let bundleManifestFilename = "bloggo-backup-bundle.json"
    static let mediaDirectory = "media"
    static let blogsDirectory = "blogs"
    /// Rough cap for total uncompressed payload while reading a user-provided archive.
    static let maxUncompressedBytes: Int64 = 1_000 * 1024 * 1024
}

// MARK: - Manifest & optional recap snapshot

struct BlogBackupManifestV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var appMarketingVersion: String?
    var assets: [BlogBackupAssetEntryV1]
    /// RecapPhoto.id for the cover image (derived from `selectedCoverPhotoIdentifier` at export).
    var coverPhotoId: UUID?
}

struct BlogBackupAssetEntryV1: Codable, Equatable, Sendable {
    var photoId: UUID
    /// Path inside the archive, e.g. `media/UUID.jpg`
    var relativePath: String
    var contentSha256Hex: String
    var byteCount: Int
    /// Optional moment reel companion file, e.g. `media/UUID.mov`
    var reelRelativePath: String?
    var reelContentSha256Hex: String?
    var reelByteCount: Int?
}

/// Optional metadata to restore list-card fields after import.
struct BlogBackupCreatedRecapPayload: Codable, Equatable, Sendable {
    var title: String
    var createdAt: Date
    var coverImageName: String
    var totalPlaceVisitCount: Int
    var tripDurationDays: Int
    var selectedPhotoCount: Int
    var countryName: String?
    var tripDateRangeText: String?
    var lastEditedAt: Date?
    var tripStartDate: Date?
    var tripEndDate: Date?
    var caption: String?
    var hasCommittedRecapSave: Bool
    var hasCompletedInitialRecapExit: Bool
}

struct BlogBackupBundleManifestV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    /// Subfolder names (each contains a single-blog backup tree).
    var blogFolderNames: [String]
}

// MARK: - Errors

enum BlogBackupError: Error, LocalizedError {
    case detailMissing(sourceTripId: UUID)
    case cannotCreateWorkDirectory
    case cannotCreateArchive
    case cannotOpenArchive
    case invalidEntryPath(String)
    case archiveTooLarge
    case manifestMissing
    case manifestDecodeFailed
    case unsupportedSchema(Int)
    case detailMissingInArchive
    case detailDecodeFailed
    case hashMismatch(photoId: UUID)
    case sizeMismatch(photoId: UUID)
    case noPhotosExported
    case bundleManifestInvalid
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .detailMissing(let id):
            return "No saved blog data for \(id.uuidString)."
        case .cannotCreateWorkDirectory:
            return "Could not create a temporary folder."
        case .cannotCreateArchive:
            return "Could not create backup archive."
        case .cannotOpenArchive:
            return "Could not open backup archive."
        case .invalidEntryPath(let p):
            return "Unsafe path in archive: \(p)"
        case .archiveTooLarge:
            return "Backup archive is too large to import safely."
        case .manifestMissing:
            return "Backup is missing manifest.json."
        case .manifestDecodeFailed:
            return "Backup manifest is invalid."
        case .unsupportedSchema(let v):
            return "Unsupported backup version (\(v))."
        case .detailMissingInArchive:
            return "Backup is missing recapBlogDetail.json."
        case .detailDecodeFailed:
            return "Could not read blog data from backup."
        case .hashMismatch(let id):
            return "Photo data failed verification (\(id.uuidString))."
        case .sizeMismatch(let id):
            return "Photo size mismatch (\(id.uuidString))."
        case .noPhotosExported:
            return "No photos could be exported (check photo access or cloud copies)."
        case .bundleManifestInvalid:
            return "Multi-blog backup index is invalid."
        case .importFailed(let msg):
            return msg
        }
    }
}

// MARK: - Service

@MainActor
enum BlogBackupService {
    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Export (single blog)

    /// Builds a `.zip` at a temp URL. Caller moves or shares it.
    /// - Parameters:
    ///   - detail: Persisted blog content (e.g. from ``CreatedRecapBlogStore/getBlogDetail(blogId:)``), not live editor draft.
    ///   - createdRecapSnapshot: Optional list-card metadata from `CreatedRecapBlog` for the same `detail.id`.
    static func exportZip(
        detail: RecapBlogDetail,
        createdRecapSnapshot: CreatedRecapBlog?,
        progress: BlogBackupProgressHandler? = nil
    ) async throws -> URL {
        let report: (Double) -> Void = { p in progress?(min(1, max(0, p))) }
        report(0)
        let recap = createdRecapSnapshot
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let mediaDir = work.appendingPathComponent(BlogBackupFormat.mediaDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        var assets: [BlogBackupAssetEntryV1] = []
        let photos = allPhotos(in: detail)
        let photoCount = photos.count

        for (index, photo) in photos.enumerated() {
            guard let data = await loadJPEGDataForBackup(photo: photo) else { continue }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            let rel = "\(BlogBackupFormat.mediaDirectory)/\(photo.id.uuidString).jpg"
            let fileURL = work.appendingPathComponent(rel)
            try data.write(to: fileURL, options: .atomic)

            var reelRelativePath: String?
            var reelContentSha256Hex: String?
            var reelByteCount: Int?
            if let reelData = MomentVideoTransfer.loadMomentVideoData(for: photo) {
                let reelRel = "\(BlogBackupFormat.mediaDirectory)/\(photo.id.uuidString).mov"
                let reelFileURL = work.appendingPathComponent(reelRel)
                try reelData.write(to: reelFileURL, options: .atomic)
                reelRelativePath = reelRel
                reelContentSha256Hex = MomentVideoTransfer.sha256Hex(of: reelData)
                reelByteCount = reelData.count
            }

            assets.append(
                BlogBackupAssetEntryV1(
                    photoId: photo.id,
                    relativePath: rel,
                    contentSha256Hex: hex,
                    byteCount: data.count,
                    reelRelativePath: reelRelativePath,
                    reelContentSha256Hex: reelContentSha256Hex,
                    reelByteCount: reelByteCount
                )
            )
            if photoCount > 0 {
                report(0.78 * Double(index + 1) / Double(photoCount))
            }
        }

        guard !assets.isEmpty else { throw BlogBackupError.noPhotosExported }

        let coverPhotoId = coverPhotoUUID(in: detail)

        let manifest = BlogBackupManifestV1(
            schemaVersion: BlogBackupFormat.schemaVersion,
            exportedAt: Date(),
            appMarketingVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            assets: assets,
            coverPhotoId: coverPhotoId
        )
        try jsonEncoder.encode(manifest).write(to: work.appendingPathComponent(BlogBackupFormat.manifestFilename), options: .atomic)

        let stripped = stripLocalMediaReferences(detail)
        try jsonEncoder.encode(stripped).write(to: work.appendingPathComponent(BlogBackupFormat.detailFilename), options: .atomic)

        if let recap {
            let payload = BlogBackupCreatedRecapPayload(from: recap)
            try jsonEncoder.encode(payload).write(to: work.appendingPathComponent(BlogBackupFormat.createdRecapFilename), options: .atomic)
        }
        report(0.85)

        let zipName = "\(sanitizeFilenameComponent(detail.title))-bloggo-backup.zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try zipDirectory(contentsOf: work, to: zipURL) { zipFrac in
            report(0.85 + 0.15 * zipFrac)
        }
        return zipURL
    }

    // MARK: Export (all visible blogs)

    static func exportAllVisibleBlogsZip(
        store: CreatedRecapBlogStore,
        progress: BlogBackupProgressHandler? = nil
    ) async throws -> URL {
        let report: (Double) -> Void = { p in progress?(min(1, max(0, p))) }
        report(0)
        let ids = store.visibleRecents.compactMap { blog -> UUID? in
            guard blog.hasCommittedRecapSave,
                  store.getBlogDetail(blogId: blog.sourceTripId) != nil else { return nil }
            return blog.sourceTripId
        }
        guard !ids.isEmpty else {
            throw BlogBackupError.importFailed("No saved blogs to export. Save each blog from the editor first.")
        }

        let weights: [Double] = ids.map { id in
            guard let d = store.getBlogDetail(blogId: id) else { return 1 }
            return Double(allPhotos(in: d).count) + 1
        }
        let finalZipWeight = 1.0
        let totalWeight = weights.reduce(0, +) + finalZipWeight

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-export-all-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var folderNames: [String] = []
        var cumulative: Double = 0
        for (index, id) in ids.enumerated() {
            let folder = work.appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let w = weights[index]
            let progressBase = cumulative
            try await exportSingleBlogTree(
                sourceTripId: id,
                intoExistingFolder: folder,
                store: store,
                progress: { local in
                    report((progressBase + w * local) / totalWeight)
                }
            )
            cumulative += w
            folderNames.append(id.uuidString)
        }

        let bundle = BlogBackupBundleManifestV1(
            schemaVersion: BlogBackupFormat.schemaVersion,
            exportedAt: Date(),
            blogFolderNames: folderNames
        )
        try jsonEncoder.encode(bundle).write(to: work.appendingPathComponent(BlogBackupFormat.bundleManifestFilename), options: .atomic)

        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-all-blogs-backup.zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        let zipProgressBase = cumulative
        try zipDirectory(contentsOf: work, to: zipURL) { zipFrac in
            report((zipProgressBase + finalZipWeight * zipFrac) / totalWeight)
        }
        return zipURL
    }

    private static func exportSingleBlogTree(
        sourceTripId: UUID,
        intoExistingFolder folder: URL,
        store: CreatedRecapBlogStore,
        progress: BlogBackupProgressHandler? = nil
    ) async throws {
        let report: (Double) -> Void = { p in progress?(min(1, max(0, p))) }
        report(0)
        guard let detail = store.getBlogDetail(blogId: sourceTripId) else {
            throw BlogBackupError.detailMissing(sourceTripId: sourceTripId)
        }
        let recap = store.recents.first { $0.sourceTripId == sourceTripId && $0.hasCommittedRecapSave }
        let mediaDir = folder.appendingPathComponent(BlogBackupFormat.mediaDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        var assets: [BlogBackupAssetEntryV1] = []
        let photos = allPhotos(in: detail)
        let photoCount = photos.count

        for (index, photo) in photos.enumerated() {
            guard let data = await loadJPEGDataForBackup(photo: photo) else { continue }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            let rel = "\(BlogBackupFormat.mediaDirectory)/\(photo.id.uuidString).jpg"
            let fileURL = folder.appendingPathComponent(rel)
            try data.write(to: fileURL, options: .atomic)

            var reelRelativePath: String?
            var reelContentSha256Hex: String?
            var reelByteCount: Int?
            if let reelData = MomentVideoTransfer.loadMomentVideoData(for: photo) {
                let reelRel = "\(BlogBackupFormat.mediaDirectory)/\(photo.id.uuidString).mov"
                let reelFileURL = folder.appendingPathComponent(reelRel)
                try reelData.write(to: reelFileURL, options: .atomic)
                reelRelativePath = reelRel
                reelContentSha256Hex = MomentVideoTransfer.sha256Hex(of: reelData)
                reelByteCount = reelData.count
            }

            assets.append(
                BlogBackupAssetEntryV1(
                    photoId: photo.id,
                    relativePath: rel,
                    contentSha256Hex: hex,
                    byteCount: data.count,
                    reelRelativePath: reelRelativePath,
                    reelContentSha256Hex: reelContentSha256Hex,
                    reelByteCount: reelByteCount
                )
            )
            if photoCount > 0 {
                report(0.78 * Double(index + 1) / Double(photoCount))
            }
        }
        guard !assets.isEmpty else { throw BlogBackupError.noPhotosExported }

        let manifest = BlogBackupManifestV1(
            schemaVersion: BlogBackupFormat.schemaVersion,
            exportedAt: Date(),
            appMarketingVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            assets: assets,
            coverPhotoId: coverPhotoUUID(in: detail)
        )
        try jsonEncoder.encode(manifest).write(to: folder.appendingPathComponent(BlogBackupFormat.manifestFilename), options: .atomic)
        try jsonEncoder.encode(stripLocalMediaReferences(detail)).write(to: folder.appendingPathComponent(BlogBackupFormat.detailFilename), options: .atomic)
        if let recap {
            try jsonEncoder.encode(BlogBackupCreatedRecapPayload(from: recap)).write(
                to: folder.appendingPathComponent(BlogBackupFormat.createdRecapFilename),
                options: .atomic
            )
        }
        report(1)
    }

    // MARK: Import

    /// Imports one or more blogs from a `.zip` (single-blog or bundle). Returns new `sourceTripId`s.
    /// - Parameter preferPhotoLibrary: When true, tries to attach each photo to a ``PHAsset`` in the library (e.g. iCloud-restored originals) using capture time and GPS from the backup; falls back to embedded JPEGs when no confident match exists.
    static func importFromZip(
        zipURL: URL,
        store: CreatedRecapBlogStore,
        preferPhotoLibrary: Bool,
        progress: BlogBackupProgressHandler? = nil
    ) async throws -> [UUID] {
        let push: (Double) -> Void = { p in progress?(min(1, max(0, p))) }
        push(0)
        await Task.yield()
        let unpack = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpack) }

        let capturedProgress = progress
        try await Task.detached(priority: .userInitiated) {
            try BlogBackupService.extractArchive(from: zipURL, to: unpack) { extractFrac in
                let v = 0.02 + 0.13 * extractFrac
                if let capturedProgress {
                    Task { @MainActor in capturedProgress(v) }
                }
            }
        }.value
        push(0.15)
        await Task.yield()

        let bundleURL = unpack.appendingPathComponent(BlogBackupFormat.bundleManifestFilename)
        if FileManager.default.fileExists(atPath: bundleURL.path),
           let data = try? Data(contentsOf: bundleURL),
           let bundle = try? jsonDecoder.decode(BlogBackupBundleManifestV1.self, from: data),
           bundle.schemaVersion == BlogBackupFormat.schemaVersion {
            var ids: [UUID] = []
            let blogCount = max(bundle.blogFolderNames.count, 1)
            for (i, name) in bundle.blogFolderNames.enumerated() {
                guard !name.contains(".."), !name.contains("/") else { throw BlogBackupError.invalidEntryPath(name) }
                let sub = unpack.appendingPathComponent(name, isDirectory: true)
                let spanStart = 0.15 + Double(i) / Double(blogCount) * 0.82
                let spanEnd = 0.15 + Double(i + 1) / Double(blogCount) * 0.82
                let id = try await importSingleBlogFolder(
                    sub,
                    store: store,
                    preferPhotoLibrary: preferPhotoLibrary,
                    onFraction: { local in
                        push(spanStart + (spanEnd - spanStart) * local)
                    }
                )
                ids.append(id)
            }
            push(1)
            await Task.yield()
            return ids
        }

        let id = try await importSingleBlogFolder(
            unpack,
            store: store,
            preferPhotoLibrary: preferPhotoLibrary,
            onFraction: { local in
                push(0.15 + 0.85 * local)
            }
        )
        push(1)
        await Task.yield()
        return [id]
    }

    private static func importSingleBlogFolder(
        _ folder: URL,
        store: CreatedRecapBlogStore,
        preferPhotoLibrary: Bool,
        onFraction: BlogBackupProgressHandler? = nil
    ) async throws -> UUID {
        func push(_ v: Double) async {
            onFraction?(min(1, max(0, v)))
            await Task.yield()
        }
        await push(0)
        let manifestURL = folder.appendingPathComponent(BlogBackupFormat.manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw BlogBackupError.manifestMissing }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: BlogBackupManifestV1
        do {
            manifest = try jsonDecoder.decode(BlogBackupManifestV1.self, from: manifestData)
        } catch {
            throw BlogBackupError.manifestDecodeFailed
        }
        guard manifest.schemaVersion == BlogBackupFormat.schemaVersion else {
            throw BlogBackupError.unsupportedSchema(manifest.schemaVersion)
        }
        await push(0.04)

        let detailURL = folder.appendingPathComponent(BlogBackupFormat.detailFilename)
        guard FileManager.default.fileExists(atPath: detailURL.path) else { throw BlogBackupError.detailMissingInArchive }
        var detail: RecapBlogDetail
        do {
            detail = try jsonDecoder.decode(RecapBlogDetail.self, from: Data(contentsOf: detailURL))
        } catch {
            throw BlogBackupError.detailDecodeFailed
        }
        await push(0.06)

        var localIdByPhotoId: [UUID: String] = [:]
        var usedLibraryLocalIds = Set<String>()

        let assetList = manifest.assets
        let assetDenom = max(assetList.count, 1)
        for (idx, asset) in assetList.enumerated() {
            guard !asset.relativePath.contains("..") else { throw BlogBackupError.invalidEntryPath(asset.relativePath) }
            let (timestamp, location) = photoTimestampAndLocation(in: detail, photoId: asset.photoId)
            let caption = photoCaption(in: detail, photoId: asset.photoId)

            if preferPhotoLibrary,
               let libId = findMatchingPhotoLibraryLocalIdentifier(
                timestamp: timestamp,
                location: location,
                excludingLocalIdentifiers: usedLibraryLocalIds
               ) {
                usedLibraryLocalIds.insert(libId)
                localIdByPhotoId[asset.photoId] = libId
                // Photo-library matches are stills only; restore embedded reel to a new app capture when present.
                if let captureId = try restoreEmbeddedReelIfNeeded(
                    asset: asset,
                    folder: folder,
                    imageData: try? Data(contentsOf: folder.appendingPathComponent(asset.relativePath)),
                    timestamp: timestamp,
                    location: location,
                    caption: caption
                ) {
                    localIdByPhotoId[asset.photoId] = AppCapturePhotoService.identifier(for: captureId)
                }
                await push(0.06 + 0.84 * Double(idx + 1) / Double(assetDenom))
                continue
            }

            let fileURL = folder.appendingPathComponent(asset.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                await push(0.06 + 0.84 * Double(idx + 1) / Double(assetDenom))
                continue
            }
            let data = try Data(contentsOf: fileURL)
            guard data.count == asset.byteCount else { throw BlogBackupError.sizeMismatch(photoId: asset.photoId) }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == asset.contentSha256Hex else { throw BlogBackupError.hashMismatch(photoId: asset.photoId) }
            guard let uiImage = UIImage(data: data) else { throw BlogBackupError.hashMismatch(photoId: asset.photoId) }

            let reelSourceURL = reelFileURL(in: folder, asset: asset)
            let captureId = try AppCapturePhotoService.shared.saveSharedImport(
                image: uiImage,
                timestamp: timestamp,
                location: location,
                caption: caption,
                momentVideoSourceURL: reelSourceURL
            )
            localIdByPhotoId[asset.photoId] = AppCapturePhotoService.identifier(for: captureId)
            await push(0.06 + 0.84 * Double(idx + 1) / Double(assetDenom))
        }

        let hydrated = assignLocalIdentifiers(detail, mapping: localIdByPhotoId)
        let newTripId = UUID()
        let coverLid: String? = {
            if let coverId = manifest.coverPhotoId, let lid = localIdByPhotoId[coverId] { return lid }
            return manifest.assets.first.flatMap { localIdByPhotoId[$0.photoId] }
        }()
        let detailForStore = hydrated.withTripId(newTripId, selectedCoverPhotoIdentifier: coverLid)

        guard let trip = TripShareBlogDraftBuilder.tripDraft(from: detailForStore) else {
            throw BlogBackupError.importFailed("Could not build trip from imported photos.")
        }

        store.addCreatedBlog(trip: trip)
        let saved = store.saveBlogDetail(detailForStore, asDraft: false, skipGuestSecondSaveGuard: true)
        if !saved {
            throw BlogBackupError.importFailed("Could not save imported blog (guest save limit). Sign in to import.")
        }

        let payloadURL = folder.appendingPathComponent(BlogBackupFormat.createdRecapFilename)
        if FileManager.default.fileExists(atPath: payloadURL.path),
           let pdata = try? Data(contentsOf: payloadURL),
           let payload = try? jsonDecoder.decode(BlogBackupCreatedRecapPayload.self, from: pdata) {
            store.applyBlogBackupCreatedRecapPayload(payload, sourceTripId: newTripId)
        }

        await push(1)
        return newTripId
    }

    // MARK: - Helpers

    private static func allPhotos(in detail: RecapBlogDetail) -> [RecapPhoto] {
        var seen = Set<UUID>()
        var out: [RecapPhoto] = []
        func append(_ photos: [RecapPhoto]) {
            for p in photos where !seen.contains(p.id) {
                seen.insert(p.id)
                out.append(p)
            }
        }
        for d in detail.days {
            for s in d.placeStops {
                append(s.photos)
            }
        }
        for e in detail.removedPlaceStops {
            append(e.stop.photos)
        }
        return out
    }

    private static func coverPhotoUUID(in detail: RecapBlogDetail) -> UUID? {
        guard let coverLid = detail.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !coverLid.isEmpty else { return nil }
        for d in detail.days {
            for s in d.placeStops {
                for p in s.photos {
                    let lid = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if lid == coverLid { return p.id }
                }
            }
        }
        for e in detail.removedPlaceStops {
            for p in e.stop.photos {
                let lid = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if lid == coverLid { return p.id }
            }
        }
        return nil
    }

    private static func stripLocalMediaReferences(_ detail: RecapBlogDetail) -> RecapBlogDetail {
        var d = detail
        d.selectedCoverPhotoIdentifier = nil
        for i in d.days.indices {
            for j in d.days[i].placeStops.indices {
                for k in d.days[i].placeStops[j].photos.indices {
                    d.days[i].placeStops[j].photos[k].localIdentifier = nil
                }
            }
        }
        for r in d.removedPlaceStops.indices {
            for k in d.removedPlaceStops[r].stop.photos.indices {
                d.removedPlaceStops[r].stop.photos[k].localIdentifier = nil
            }
        }
        return d
    }

    private static func assignLocalIdentifiers(_ detail: RecapBlogDetail, mapping: [UUID: String]) -> RecapBlogDetail {
        var d = detail
        for i in d.days.indices {
            for j in d.days[i].placeStops.indices {
                for k in d.days[i].placeStops[j].photos.indices {
                    let pid = d.days[i].placeStops[j].photos[k].id
                    if let lid = mapping[pid] {
                        d.days[i].placeStops[j].photos[k].localIdentifier = lid
                    }
                }
            }
        }
        for r in d.removedPlaceStops.indices {
            for k in d.removedPlaceStops[r].stop.photos.indices {
                let pid = d.removedPlaceStops[r].stop.photos[k].id
                if let lid = mapping[pid] {
                    d.removedPlaceStops[r].stop.photos[k].localIdentifier = lid
                }
            }
        }
        return d
    }

    private static func photoTimestampAndLocation(in detail: RecapBlogDetail, photoId: UUID) -> (Date, CLLocation?) {
        for d in detail.days {
            for s in d.placeStops {
                for p in s.photos where p.id == photoId {
                    let loc = p.location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
                    return (p.timestamp, loc)
                }
            }
        }
        for e in detail.removedPlaceStops {
            for p in e.stop.photos where p.id == photoId {
                let loc = p.location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
                return (p.timestamp, loc)
            }
        }
        return (Date(), nil)
    }

    private static func photoCaption(in detail: RecapBlogDetail, photoId: UUID) -> String? {
        for d in detail.days {
            for s in d.placeStops {
                for p in s.photos where p.id == photoId {
                    return p.caption
                }
            }
        }
        for e in detail.removedPlaceStops {
            for p in e.stop.photos where p.id == photoId {
                return p.caption
            }
        }
        return nil
    }

    /// Links a backup row to an existing Photos asset (e.g. after iCloud Photo Library sync on a new phone).
    private static func findMatchingPhotoLibraryLocalIdentifier(
        timestamp: Date,
        location: CLLocation?,
        excludingLocalIdentifiers: Set<String>
    ) -> String? {
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard auth == .authorized || auth == .limited else { return nil }

        let windows: [TimeInterval] = [18, 120, 600]

        for windowSec in windows {
            let start = timestamp.addingTimeInterval(-windowSec)
            let end = timestamp.addingTimeInterval(windowSec)
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.image.rawValue,
                start as NSDate,
                end as NSDate
            )

            let result = PHAsset.fetchAssets(with: .image, options: opts)
            var candidates: [PHAsset] = []
            result.enumerateObjects { ph, _, _ in
                if !excludingLocalIdentifiers.contains(ph.localIdentifier) {
                    candidates.append(ph)
                }
            }
            guard !candidates.isEmpty else { continue }

            func timeDelta(_ ph: PHAsset) -> TimeInterval {
                abs((ph.creationDate ?? .distantPast).timeIntervalSince(timestamp))
            }

            var scored: [(PHAsset, Double)] = []
            for ph in candidates {
                let dt = timeDelta(ph)
                if dt <= 15 {
                    scored.append((ph, dt))
                    continue
                }
                if dt <= 420, let reqLoc = location, let assetLoc = ph.location {
                    let meters = reqLoc.distance(from: assetLoc)
                    if meters < 600 {
                        scored.append((ph, dt + meters * 0.01))
                    }
                }
            }

            if let best = scored.min(by: { $0.1 < $1.1 }) {
                return best.0.localIdentifier
            }
        }

        return nil
    }

    /// Returns a verified on-disk reel file URL from the backup folder, or nil when absent/invalid.
    private static func reelFileURL(in folder: URL, asset: BlogBackupAssetEntryV1) -> URL? {
        guard let rel = asset.reelRelativePath,
              let expectedHex = asset.reelContentSha256Hex,
              let expectedCount = asset.reelByteCount,
              !rel.contains("..") else { return nil }
        let url = folder.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              data.count == expectedCount,
              MomentVideoTransfer.sha256Hex(of: data) == expectedHex else { return nil }
        return url
    }

    /// When a photo-library match succeeds but the backup also embeds a reel, import as app capture so playback works.
    private static func restoreEmbeddedReelIfNeeded(
        asset: BlogBackupAssetEntryV1,
        folder: URL,
        imageData: Data?,
        timestamp: Date,
        location: CLLocation?,
        caption: String?
    ) throws -> UUID? {
        guard asset.reelRelativePath != nil,
              let reelURL = reelFileURL(in: folder, asset: asset),
              let imageData,
              let uiImage = UIImage(data: imageData) else { return nil }
        return try AppCapturePhotoService.shared.saveSharedImport(
            image: uiImage,
            timestamp: timestamp,
            location: location,
            caption: caption,
            momentVideoSourceURL: reelURL
        )
    }

    private static func loadJPEGDataForBackup(photo: RecapPhoto) async -> Data? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            if let img = await ImageLoader.shared.loadImage(
                assetIdentifier: lid,
                targetSize: CGSize(width: 2048, height: 2048)
            ), let data = img.jpegData(compressionQuality: 0.88) {
                return data
            }
        }
        if let urlStr = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty,
           let u = URL(string: urlStr),
           let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            do {
                let (data, _) = try await URLSession.shared.data(from: u)
                if let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.88) {
                    return jpeg
                }
                return data
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func sanitizeFilenameComponent(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Blog" : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return String(base.components(separatedBy: invalid).joined(separator: "-").prefix(48))
    }

    nonisolated private static func zipDirectory(
        contentsOf directory: URL,
        to archiveURL: URL,
        onProgress: BlogBackupProgressHandler? = nil
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw BlogBackupError.cannotCreateWorkDirectory
        }
        var fileURLs: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let basePath = directory.path
            var rel = String(item.path.dropFirst(basePath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            guard !rel.isEmpty, !rel.contains("..") else { continue }
            fileURLs.append(item)
        }
        let n = fileURLs.count
        guard n > 0 else {
            onProgress?(1)
            return
        }
        // Write entries while `Archive` is alive; finalize (central directory, flush) happens on deinit.
        // Progress must not hit 1.0 until after the archive is released, or the UI sits at 100% while the file finishes.
        try zipDirectoryWriteFileEntries(archiveURL: archiveURL, fileURLs: fileURLs, directory: directory) { partial in
            // `partial` is in (0, 1); caller maps to their overall range, then we send 1.0 below.
            onProgress?(partial)
        }
        onProgress?(1)
    }

    nonisolated private static func zipDirectoryWriteFileEntries(
        archiveURL: URL,
        fileURLs: [URL],
        directory: URL,
        onPartialProgress: BlogBackupProgressHandler?
    ) throws {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .create)
        } catch {
            throw BlogBackupError.cannotCreateArchive
        }
        let n = fileURLs.count
        for (index, item) in fileURLs.enumerated() {
            let basePath = directory.path
            var rel = String(item.path.dropFirst(basePath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            try archive.addEntry(with: rel, fileURL: item, compressionMethod: .deflate)
            onPartialProgress?(Double(index + 1) / Double(n + 1))
        }
    }

    nonisolated private static func extractArchive(
        from zipURL: URL,
        to destination: URL,
        onProgress: BlogBackupProgressHandler? = nil
    ) throws {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw BlogBackupError.cannotOpenArchive
        }
        var entries: [Entry] = []
        var totalUncompressed: Int64 = 0
        for entry in archive {
            totalUncompressed += Int64(entry.uncompressedSize)
            if totalUncompressed > BlogBackupFormat.maxUncompressedBytes {
                throw BlogBackupError.archiveTooLarge
            }
            entries.append(entry)
        }
        let n = entries.count
        guard n > 0 else {
            onProgress?(1)
            return
        }
        for (index, entry) in entries.enumerated() {
            let path = entry.path
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else {
                throw BlogBackupError.invalidEntryPath(path)
            }
            let out = destination.appendingPathComponent(path)
            let parent = out.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if !path.hasSuffix("/") {
                _ = try archive.extract(entry, to: out)
            }
            onProgress?(Double(index + 1) / Double(n))
        }
    }
}

private extension RecapBlogDetail {
    func withTripId(_ newId: UUID, selectedCoverPhotoIdentifier: String?) -> RecapBlogDetail {
        RecapBlogDetail(
            id: newId,
            title: title,
            days: days,
            coverTheme: coverTheme,
            selectedCoverPhotoIdentifier: selectedCoverPhotoIdentifier,
            countryName: countryName,
            blogKey: nil,
            removedPlaceStops: removedPlaceStops,
            tripNarrative: tripNarrative
        )
    }
}

private extension BlogBackupCreatedRecapPayload {
    init(from blog: CreatedRecapBlog) {
        title = blog.title
        createdAt = blog.createdAt
        coverImageName = blog.coverImageName
        totalPlaceVisitCount = blog.totalPlaceVisitCount
        tripDurationDays = blog.tripDurationDays
        selectedPhotoCount = blog.selectedPhotoCount
        countryName = blog.countryName
        tripDateRangeText = blog.tripDateRangeText
        lastEditedAt = blog.lastEditedAt
        tripStartDate = blog.tripStartDate
        tripEndDate = blog.tripEndDate
        caption = blog.caption
        hasCommittedRecapSave = blog.hasCommittedRecapSave
        hasCompletedInitialRecapExit = blog.hasCompletedInitialRecapExit
    }
}
