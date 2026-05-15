//
//  BlogDropService.swift
//  fastblog
//
//  Cloud-based blog sharing between Bloggo users. Creates a JSON "drop" on the file
//  server (photos uploaded first so recipients download directly from cloud URLs).
//  All story levels are preserved: blog narrative, day narratives, place narratives,
//  and per-photo captions.
//

import CoreLocation
import Foundation
import UIKit

// MARK: - Manifest

/// Schema version for the blog-drop wire format.
private let kBlogDropSchemaVersion = 1

struct BlogDropManifestV1: Codable, Sendable {
    var schemaVersion: Int
    var tripTitle: String
    /// Blog-level opening narrative.
    var tripNarrative: String?
    var countryName: String?
    var coverTheme: String
    /// Cloud URL of the cover photo (nil when the cover photo wasn't included/uploaded).
    var coverPhotoURL: String?
    var days: [BlogDropDayV1]
    var photos: [BlogDropPhotoV1]
}

struct BlogDropDayV1: Codable, Sendable {
    var dayIndex: Int
    var dateUnixSeconds: TimeInterval
    /// User/AI caption shown below the day date.
    var dayCaption: String?
    /// AI narrative (overrides dayCaption in display).
    var dayNarrative: String?
    var placeStops: [BlogDropPlaceStopV1]
}

struct BlogDropPlaceStopV1: Codable, Sendable {
    var orderIndex: Int
    var placeTitle: String
    var placeSubtitle: String?
    var representativeLatitude: Double?
    var representativeLongitude: Double?
    /// User-written place note.
    var noteText: String?
    /// LLM-generated overall story summary.
    var overallStory: String?
    var overallStoryIsManual: Bool
    /// AI-generated place narrative (overrides overallStory in display).
    var placeNarrative: String?
}

struct BlogDropPhotoV1: Codable, Sendable {
    var dayIndex: Int
    var stopOrderIndex: Int
    var timestamp: TimeInterval
    var latitude: Double?
    var longitude: Double?
    var imageName: String
    var isIncluded: Bool
    /// Per-photo caption (photo-level story).
    var caption: String?
    var captionIsManual: Bool
    /// Cloud URL to download the photo JPEG.
    var cloudURL: String?
}

// MARK: - Errors

enum BlogDropError: LocalizedError {
    case noIncludedPhotos
    case manifestUploadFailed
    case invalidDropURL
    case manifestDownloadFailed
    case schemaUnsupported(Int)
    case photoDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noIncludedPhotos:
            return "This blog has no included photos to drop."
        case .manifestUploadFailed:
            return "Could not upload the drop package. Check your connection."
        case .invalidDropURL:
            return "That drop link doesn't look valid."
        case .manifestDownloadFailed:
            return "Couldn't download the drop. The link may have expired."
        case .schemaUnsupported(let v):
            return "This drop was created with a newer version of Bloggo (schema \(v))."
        case .photoDownloadFailed(let url):
            return "Failed to download photo: \(url)"
        }
    }
}

// MARK: - Progress

struct BlogDropProgress: Sendable {
    enum Phase: Sendable {
        case uploadingPhotos(done: Int, total: Int)
        case uploadingManifest
        case downloadingManifest
        case downloadingPhotos(done: Int, total: Int)
    }
    let phase: Phase
}

// MARK: - Service

actor BlogDropService {
    static let shared = BlogDropService()

    // MARK: - Create Drop

    /// Uploads any missing photos to the cloud, builds a `BlogDropManifestV1`, uploads it
    /// as a JSON file, and returns the drop URL. Caller should store or share this URL.
    func createDrop(
        from detail: RecapBlogDetail,
        onProgress: @Sendable @escaping (BlogDropProgress) -> Void = { _ in }
    ) async throws -> URL {
        var workingDetail = detail

        // --- Phase 1: upload photos that don't have cloud URLs yet ---
        let allIncluded = workingDetail.days
            .flatMap(\.placeStops)
            .flatMap(\.photos)
            .filter { $0.isIncluded }
        let missingCloud = allIncluded.filter { $0.cloudURL == nil }
        let totalMissing = missingCloud.count
        var doneCount = 0

        if totalMissing > 0 {
            onProgress(BlogDropProgress(phase: .uploadingPhotos(done: 0, total: totalMissing)))
            for dayIdx in workingDetail.days.indices {
                for stopIdx in workingDetail.days[dayIdx].placeStops.indices {
                    for photoIdx in workingDetail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        let photo = workingDetail.days[dayIdx].placeStops[stopIdx].photos[photoIdx]
                        guard photo.isIncluded, photo.cloudURL == nil,
                              let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !lid.isEmpty else { continue }
                        guard !Task.isCancelled else { return URL(string: "about:blank")! }
                        let cloudURL = try await APIManager.shared.uploadPhoto(assetIdentifier: lid)
                        workingDetail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = cloudURL
                        doneCount += 1
                        onProgress(BlogDropProgress(phase: .uploadingPhotos(done: doneCount, total: totalMissing)))
                    }
                }
            }
        }

        // --- Phase 2: build manifest ---
        onProgress(BlogDropProgress(phase: .uploadingManifest))
        let manifest = buildManifest(from: workingDetail)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(manifest)

        // --- Phase 3: upload manifest JSON ---
        let filename = "bloggo-drop-\(detail.id.uuidString.lowercased()).json"
        guard let manifestURLStr = try? await APIManager.shared.uploadJSONData(jsonData, filename: filename),
              let manifestURL = URL(string: manifestURLStr) else {
            throw BlogDropError.manifestUploadFailed
        }
        return manifestURL
    }

    // MARK: - Import Drop

    /// Downloads and imports a blog drop from the given URL.
    /// Returns a new `RecapBlogDetail` with fresh local photo assets and all stories restored.
    func importDrop(
        from url: URL,
        onProgress: @Sendable @escaping (BlogDropProgress) -> Void = { _ in }
    ) async throws -> RecapBlogDetail {
        // --- Phase 1: download manifest ---
        onProgress(BlogDropProgress(phase: .downloadingManifest))
        let (manifestData, _): (Data, URLResponse)
        do {
            (manifestData, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw BlogDropError.manifestDownloadFailed
        }
        let manifest: BlogDropManifestV1
        do {
            manifest = try JSONDecoder().decode(BlogDropManifestV1.self, from: manifestData)
        } catch {
            throw BlogDropError.manifestDownloadFailed
        }
        guard manifest.schemaVersion <= kBlogDropSchemaVersion else {
            throw BlogDropError.schemaUnsupported(manifest.schemaVersion)
        }

        // --- Phase 2: download photos and save to device ---
        let includedPhotos = manifest.photos.filter(\.isIncluded)
        let total = includedPhotos.count
        var done = 0
        onProgress(BlogDropProgress(phase: .downloadingPhotos(done: 0, total: total)))

        // Key: "\(dayIndex)|\(stopOrderIndex)" → [RecapPhoto]
        var photosByKey: [String: [RecapPhoto]] = [:]

        for entry in includedPhotos {
            guard !Task.isCancelled else { break }
            guard let cloudURLStr = entry.cloudURL,
                  let cloudURL = URL(string: cloudURLStr) else { continue }

            let imageData: Data
            do {
                (imageData, _) = try await URLSession.shared.data(from: cloudURL)
            } catch {
                throw BlogDropError.photoDownloadFailed(cloudURLStr)
            }
            guard let uiImage = UIImage(data: imageData) else { continue }

            let timestamp = Date(timeIntervalSince1970: entry.timestamp)
            let location: CLLocation? = {
                guard let lat = entry.latitude, let lon = entry.longitude else { return nil }
                return CLLocation(latitude: lat, longitude: lon)
            }()

            let captureId = try AppCapturePhotoService.shared.saveSharedImport(
                image: uiImage,
                timestamp: timestamp,
                location: location,
                caption: entry.caption
            )
            let localIdentifier = AppCapturePhotoService.identifier(for: captureId)

            let recapPhoto = RecapPhoto(
                id: UUID(),
                timestamp: timestamp,
                location: location.map {
                    PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                },
                imageName: entry.imageName,
                isIncluded: true,
                localIdentifier: localIdentifier,
                caption: entry.caption,
                cloudURL: entry.cloudURL,
                captionIsManual: entry.captionIsManual
            )

            let key = "\(entry.dayIndex)|\(entry.stopOrderIndex)"
            photosByKey[key, default: []].append(recapPhoto)

            done += 1
            onProgress(BlogDropProgress(phase: .downloadingPhotos(done: done, total: total)))
        }

        // --- Phase 3: reconstruct blog detail ---
        let importedId = UUID()
        let sortedDays = manifest.days.sorted { $0.dayIndex < $1.dayIndex }
        var recapDays: [RecapBlogDay] = []
        var coverIdentifier: String? = nil

        for day in sortedDays {
            let sortedStops = day.placeStops.sorted { $0.orderIndex < $1.orderIndex }
            var placeStops: [PlaceStop] = []
            for stop in sortedStops {
                let key = "\(day.dayIndex)|\(stop.orderIndex)"
                var stopPhotos = photosByKey[key] ?? []
                stopPhotos.sort { $0.timestamp < $1.timestamp }

                let repLocation: PhotoCoordinate? = {
                    guard let lat = stop.representativeLatitude,
                          let lon = stop.representativeLongitude else { return nil }
                    return PhotoCoordinate(latitude: lat, longitude: lon)
                }()

                placeStops.append(PlaceStop(
                    id: UUID(),
                    orderIndex: stop.orderIndex,
                    placeTitle: stop.placeTitle,
                    placeSubtitle: stop.placeSubtitle,
                    placeTitleIsManual: true,
                    representativeLocation: repLocation,
                    photos: stopPhotos,
                    noteText: stop.noteText,
                    overallStory: stop.overallStory,
                    placeNarrative: stop.placeNarrative,
                    overallStoryIsManual: stop.overallStoryIsManual
                ))
            }

            recapDays.append(RecapBlogDay(
                id: UUID(),
                dayIndex: day.dayIndex,
                date: Date(timeIntervalSince1970: day.dateUnixSeconds),
                placeStops: placeStops,
                dayCaption: day.dayCaption,
                dayNarrative: day.dayNarrative,
                isPlaceNamesResolved: false,
                weather: nil
            ))
        }

        // Find cover photo local identifier by matching cloud URL
        if let coverCloudURL = manifest.coverPhotoURL {
            coverIdentifier = recapDays
                .flatMap(\.placeStops)
                .flatMap(\.photos)
                .first { $0.cloudURL == coverCloudURL }?
                .localIdentifier
        }
        if coverIdentifier == nil {
            coverIdentifier = recapDays.flatMap(\.placeStops).flatMap(\.photos).first?.localIdentifier
        }

        return RecapBlogDetail(
            id: importedId,
            title: manifest.tripTitle,
            days: recapDays,
            coverTheme: manifest.coverTheme,
            selectedCoverPhotoIdentifier: coverIdentifier,
            countryName: manifest.countryName,
            blogKey: nil,
            removedPlaceStops: [],
            tripNarrative: manifest.tripNarrative
        )
    }

    // MARK: - Helpers

    private func buildManifest(from detail: RecapBlogDetail) -> BlogDropManifestV1 {
        var days: [BlogDropDayV1] = []
        var photos: [BlogDropPhotoV1] = []
        var coverPhotoURL: String? = nil

        for day in detail.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            var stopEntries: [BlogDropPlaceStopV1] = []
            for stop in day.placeStops.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                stopEntries.append(BlogDropPlaceStopV1(
                    orderIndex: stop.orderIndex,
                    placeTitle: stop.placeTitle,
                    placeSubtitle: stop.placeSubtitle,
                    representativeLatitude: stop.representativeLocation?.latitude,
                    representativeLongitude: stop.representativeLocation?.longitude,
                    noteText: stop.noteText,
                    overallStory: stop.overallStory,
                    overallStoryIsManual: stop.overallStoryIsManual,
                    placeNarrative: stop.placeNarrative
                ))

                for photo in stop.photos.filter(\.isIncluded).sorted(by: { $0.timestamp < $1.timestamp }) {
                    if coverPhotoURL == nil,
                       let coverId = detail.selectedCoverPhotoIdentifier,
                       photo.localIdentifier == coverId || photo.cloudURL != nil {
                        coverPhotoURL = photo.cloudURL
                    }
                    photos.append(BlogDropPhotoV1(
                        dayIndex: day.dayIndex,
                        stopOrderIndex: stop.orderIndex,
                        timestamp: photo.timestamp.timeIntervalSince1970,
                        latitude: photo.location?.latitude,
                        longitude: photo.location?.longitude,
                        imageName: photo.imageName,
                        isIncluded: photo.isIncluded,
                        caption: photo.caption,
                        captionIsManual: photo.captionIsManual,
                        cloudURL: photo.cloudURL
                    ))
                }
            }

            days.append(BlogDropDayV1(
                dayIndex: day.dayIndex,
                dateUnixSeconds: day.date.timeIntervalSince1970,
                dayCaption: day.dayCaption,
                dayNarrative: day.dayNarrative,
                placeStops: stopEntries
            ))
        }

        // Refine cover photo URL using the saved cover identifier
        if let coverId = detail.selectedCoverPhotoIdentifier {
            let allPhotos = detail.days.flatMap(\.placeStops).flatMap(\.photos)
            coverPhotoURL = allPhotos.first { $0.localIdentifier == coverId }?.cloudURL ?? coverPhotoURL
        }

        return BlogDropManifestV1(
            schemaVersion: kBlogDropSchemaVersion,
            tripTitle: detail.title,
            tripNarrative: detail.tripNarrative,
            countryName: detail.countryName,
            coverTheme: detail.coverTheme,
            coverPhotoURL: coverPhotoURL,
            days: days,
            photos: photos
        )
    }
}
