//
//  PlacesDataExportService.swift
//  fastblog
//
//  Builds a `.zip` of up to 100 visited places (concrete POI name, category, timestamp,
//  coordinate, one photo each) for offline analysis. Triggered from Places Visited → Manage.
//

import CoreLocation
import Foundation
import UIKit
import Vision
import ZIPFoundation

@MainActor
enum PlacesDataExportService {
    static let maxPlaces = 100

    enum PlacesDataExportError: Error, LocalizedError {
        case noQualifyingPlaces
        case cannotCreateWorkDirectory
        case cannotCreateArchive

        var errorDescription: String? {
            switch self {
            case .noQualifyingPlaces:
                return "No places with a resolved point-of-interest name yet."
            case .cannotCreateWorkDirectory:
                return "Could not create a temporary folder."
            case .cannotCreateArchive:
                return "Could not create the export archive."
            }
        }
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Concrete-POI filter: drops unresolved placeholder titles ("Name this place", "Unknown
    /// Place", empty) and any title starting with "Near " (a fallback street/area label, not a
    /// real POI name). A POI category tag is preferred but not required — places without one
    /// export with category "Others".
    ///
    /// Note: `placeTitleIsManual` is intentionally NOT used here — in this codebase it's set both
    /// on genuine user renames and whenever a title is auto-resolved and "locked in" (e.g.
    /// `RecapBlogPageView.silentlyUpdatePlaceName`, `CreatedRecapBlogStore.applySavedAppCapturePlaceMetadata`),
    /// so it does not reliably distinguish a hand-typed name from a real resolved POI name.
    /// Returns candidates paired with the resolved category raw value, latest-visit-first.
    static func filterConcretePOIPlaces(_ places: [VisitedPlaceSummary]) -> [(place: VisitedPlaceSummary, categoryRaw: String)] {
        places
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
            .compactMap { place -> (VisitedPlaceSummary, String)? in
                let name = place.displayName
                guard name != PlacePlaceholderNaming.unsetPlaceDisplayTitle, name != "Unknown Place" else { return nil }
                guard !name.hasPrefix("Near ") else { return nil }

                let stored = place.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let categoryRaw: String
                if !stored.isEmpty, stored.caseInsensitiveCompare("Others") != .orderedSame {
                    categoryRaw = stored
                } else {
                    categoryRaw = PlacePOICategoryPresentation.inferredCategoryRaw(fromPlaceTitle: name) ?? "Others"
                }
                return (place, categoryRaw)
            }
    }

    /// Builds a `.zip` at a temp URL. Caller moves or shares it (and deletes it when done).
    static func exportZip(
        places: [VisitedPlaceSummary],
        progress: BlogBackupProgressHandler? = nil
    ) async throws -> URL {
        let report: (Double) -> Void = { p in progress?(min(1, max(0, p))) }
        report(0)

        let candidates = Array(filterConcretePOIPlaces(places).prefix(maxPlaces))
        guard !candidates.isEmpty else { throw PlacesDataExportError.noQualifyingPlaces }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-places-export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            throw PlacesDataExportError.cannotCreateWorkDirectory
        }
        defer { try? FileManager.default.removeItem(at: work) }

        let photosDir = work.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        var entries: [PlaceDataExportEntry] = []
        let total = candidates.count

        for (index, candidate) in candidates.enumerated() {
            defer { report(0.9 * Double(index + 1) / Double(total)) }

            let place = candidate.place
            guard let photo = await selectExportPhoto(for: place),
                  let coordinate = place.representativeCoordinate ?? photo.location?.clCoordinate else { continue }
            guard let imageData = await loadJPEGData(photo: photo) else { continue }

            let fileName = String(format: "%04d.jpg", entries.count + 1)
            let relativePath = "photos/\(fileName)"
            try imageData.write(to: photosDir.appendingPathComponent(fileName), options: .atomic)

            entries.append(
                PlaceDataExportEntry(
                    id: place.placeId,
                    placeName: place.displayName,
                    category: PlacePOICategoryPresentation.displayLabel(forRaw: candidate.categoryRaw),
                    categoryRaw: candidate.categoryRaw,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    timestamp: photo.timestamp,
                    photoFileName: relativePath
                )
            )
        }

        guard !entries.isEmpty else { throw PlacesDataExportError.noQualifyingPlaces }

        let manifest = PlaceDataExportManifest(exportedAt: Date(), placeCount: entries.count, places: entries)
        try jsonEncoder.encode(manifest).write(to: work.appendingPathComponent("places.json"), options: .atomic)
        report(0.92)

        let dateStamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            return f.string(from: Date())
        }()
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-places-export-\(dateStamp).zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try zipDirectory(contentsOf: work, to: zipURL) { zipFrac in
            report(0.92 + 0.08 * zipFrac)
        }
        return zipURL
    }

    // MARK: - Photo selection

    /// Picks the place's representative export photo: prefers a face-free shot among the
    /// highest-quality candidates, falling back to a photo with faces only when it's the only one.
    private static func selectExportPhoto(for place: VisitedPlaceSummary) async -> RecapPhoto? {
        // Mirrors VisitedPlaceSummary.heroPhoto's ordering (best quality, ties broken by newest).
        let candidates = place.photos.sorted { lhs, rhs in
            let l = lhs.qualityScore?.totalScore ?? -1
            let r = rhs.qualityScore?.totalScore ?? -1
            if l != r { return l > r }
            return lhs.timestamp > rhs.timestamp
        }
        guard let best = candidates.first else { return nil }
        guard candidates.count > 1 else { return best }

        // Bound the face-check to the top candidates so a place with many photos doesn't
        // trigger a long chain of thumbnail loads + Vision passes.
        for candidate in candidates.prefix(5) {
            if await photoContainsFace(candidate) == false {
                return candidate
            }
        }
        return best
    }

    /// Returns true/false for face presence, or nil when the photo couldn't be loaded at all
    /// (caller should not treat "unknown" as face-free).
    private static func photoContainsFace(_ photo: RecapPhoto) async -> Bool? {
        guard let thumbnail = await loadThumbnailForFaceCheck(photo: photo), let cgImage = thumbnail.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return !(request.results?.isEmpty ?? true)
    }

    private static func loadThumbnailForFaceCheck(photo: RecapPhoto) async -> UIImage? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            return await ImageLoader.shared.loadThumbnail(assetIdentifier: lid, targetSize: CGSize(width: 400, height: 400))
        }
        // Cloud-only photo (no local asset): no cheap thumbnail path, so check against the full-size fetch.
        guard let data = await loadJPEGData(photo: photo) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Helpers

    private static func loadJPEGData(photo: RecapPhoto) async -> Data? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            if let img = await ImageLoader.shared.loadImage(
                assetIdentifier: lid,
                targetSize: CGSize(width: 2048, height: 2048)
            ), let data = img.jpegData(compressionQuality: 0.9) {
                return data
            }
        }
        if let urlStr = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty,
           let u = URL(string: urlStr),
           let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            do {
                let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: urlStr)
                let (data, _) = try await URLSession.shared.data(from: signedURL)
                if let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.9) {
                    return jpeg
                }
                return data
            } catch {
                return nil
            }
        }
        return nil
    }

    nonisolated private static func zipDirectory(
        contentsOf directory: URL,
        to archiveURL: URL,
        onProgress: BlogBackupProgressHandler? = nil
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw PlacesDataExportError.cannotCreateWorkDirectory
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

        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .create)
        } catch {
            throw PlacesDataExportError.cannotCreateArchive
        }
        for (index, item) in fileURLs.enumerated() {
            let basePath = directory.path
            var rel = String(item.path.dropFirst(basePath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            try archive.addEntry(with: rel, fileURL: item, compressionMethod: .deflate)
            onProgress?(Double(index + 1) / Double(n))
        }
    }
}
