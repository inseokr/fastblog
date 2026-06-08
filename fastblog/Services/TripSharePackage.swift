//
//  TripSharePackage.swift
//  fastblog
//
//  Canonical v1 trip package: manifest (JSON) + JPEG files sent via Multipeer sendResource.
//

import CoreLocation
import CryptoKit
import Foundation
import UIKit

// MARK: - Manifest

/// Serializable trip metadata + ordered photo descriptors (content-addressed for integrity / dedup hints).
struct TripShareManifestV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var tripTitle: String
    var dateRangeText: String
    var daysSeasonText: String
    var coverTheme: String
    var coverImageName: String
    var isScannedFromDefaultRange: Bool
    var draftCreatedAgoText: String
    /// Ordered flat list of photos (group into `TripDay` by `dayIndex` + `dateText` on import).
    var photos: [TripSharePhotoEntryV1]
}

struct TripSharePhotoEntryV1: Codable, Equatable, Sendable {
    /// Monotonic index matching `sendResource` name `bloggo-photo-<order>.jpg`.
    var order: Int
    var dayIndex: Int
    var dateText: String
    var countryCode: String?
    var countryName: String?
    var cityName: String?
    var timestamp: TimeInterval
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var countryNamePhoto: String?
    var isSelected: Bool
    var caption: String?
    var imageName: String
    /// SHA256 hex of JPEG bytes (integrity + dedup signal for receivers).
    var contentSha256Hex: String
    var byteCount: Int
    /// Optional moment reel sent as `bloggo-reel-<order>.mov`.
    var reelContentSha256Hex: String?
    var reelByteCount: Int?
}

// MARK: - Export

enum TripShareExportError: Error {
    case missingImageData(UUID)
    case imageEncodingFailed
}

enum TripShareExporter {
    /// Builds manifest + JPEG data for every photo in the trip (library + bloggo-capture assets).
    @MainActor
    static func makePayload(from trip: TripDraft) async throws -> (manifest: TripShareManifestV1, images: [Data], reelsByOrder: [Int: Data]) {
        var entries: [TripSharePhotoEntryV1] = []
        var images: [Data] = []
        var reelsByOrder: [Int: Data] = [:]
        var order = 0

        for day in trip.days {
            for photo in day.photos {
                let image: UIImage?
                if let lid = photo.localIdentifier {
                    image = await ImageLoader.shared.loadImage(
                        assetIdentifier: lid,
                        targetSize: CGSize(width: 2048, height: 2048)
                    )
                } else {
                    image = nil
                }
                guard let uiImage = image,
                      let jpeg = uiImage.jpegData(compressionQuality: 0.88) else {
                    throw TripShareExportError.missingImageData(photo.id)
                }
                let digest = SHA256.hash(data: jpeg)
                let hex = digest.map { String(format: "%02x", $0) }.joined()

                var reelHex: String?
                var reelByteCount: Int?
                if let lid = photo.localIdentifier {
                    let recapPhoto = RecapPhoto(
                        timestamp: photo.timestamp,
                        location: photo.location,
                        imageName: photo.imageName,
                        localIdentifier: lid
                    )
                    if let reelData = MomentVideoTransfer.loadMomentVideoData(for: recapPhoto) {
                        reelsByOrder[order] = reelData
                        reelHex = MomentVideoTransfer.sha256Hex(of: reelData)
                        reelByteCount = reelData.count
                    }
                }

                entries.append(
                    TripSharePhotoEntryV1(
                        order: order,
                        dayIndex: day.dayIndex,
                        dateText: day.dateText,
                        countryCode: day.countryCode,
                        countryName: day.countryName,
                        cityName: day.cityName,
                        timestamp: photo.timestamp.timeIntervalSince1970,
                        latitude: photo.location?.latitude,
                        longitude: photo.location?.longitude,
                        locationName: photo.locationName,
                        countryNamePhoto: photo.countryName,
                        isSelected: photo.isSelected,
                        caption: photo.caption,
                        imageName: photo.imageName,
                        contentSha256Hex: hex,
                        byteCount: jpeg.count,
                        reelContentSha256Hex: reelHex,
                        reelByteCount: reelByteCount
                    )
                )
                images.append(jpeg)
                order += 1
            }
        }

        let manifest = TripShareManifestV1(
            schemaVersion: TripShareNearbyConfig.schemaVersion,
            tripTitle: trip.title,
            dateRangeText: trip.dateRangeText,
            daysSeasonText: trip.daysSeasonText,
            coverTheme: trip.coverTheme,
            coverImageName: trip.coverImageName,
            isScannedFromDefaultRange: trip.isScannedFromDefaultRange,
            draftCreatedAgoText: trip.draftCreatedAgoText,
            photos: entries
        )
        return (manifest, images, reelsByOrder)
    }
}

// MARK: - Import

enum TripShareImportError: Error {
    case photoCountMismatch
    case schemaUnsupported(Int)
    case hashMismatch(order: Int)
    case emptyManifest
}

enum TripShareImporter {
    /// Validates JPEG list against manifest and builds a new `TripDraft` with fresh identities (bloggo-capture ids).
    static func makeTripDraft(
        manifest: TripShareManifestV1,
        images: [Data],
        reelsByOrder: [Int: Data] = [:]
    ) throws -> TripDraft {
        guard manifest.schemaVersion == TripShareNearbyConfig.schemaVersion else {
            throw TripShareImportError.schemaUnsupported(manifest.schemaVersion)
        }
        guard manifest.photos.count == images.count else {
            throw TripShareImportError.photoCountMismatch
        }
        guard !manifest.photos.isEmpty else {
            throw TripShareImportError.emptyManifest
        }

        for (entry, data) in zip(manifest.photos, images) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == entry.contentSha256Hex, data.count == entry.byteCount else {
                throw TripShareImportError.hashMismatch(order: entry.order)
            }
            if let reelHex = entry.reelContentSha256Hex, let reelCount = entry.reelByteCount {
                guard let reelData = reelsByOrder[entry.order],
                      reelData.count == reelCount,
                      MomentVideoTransfer.sha256Hex(of: reelData) == reelHex else {
                    throw TripShareImportError.hashMismatch(order: entry.order)
                }
            }
        }

        var dayBuckets: [String: (dayIndex: Int, dateText: String, countryCode: String?, countryName: String?, cityName: String?, photos: [MockPhoto])] = [:]

        for (entry, data) in zip(manifest.photos, images) {
            let key = "\(entry.dayIndex)|\(entry.dateText)"
            let timestamp = Date(timeIntervalSince1970: entry.timestamp)
            let coord: PhotoCoordinate?
            if let lat = entry.latitude, let lon = entry.longitude {
                coord = PhotoCoordinate(latitude: lat, longitude: lon)
            } else {
                coord = nil
            }
            let location = coord.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            guard let uiImage = UIImage(data: data) else { continue }
            let reelTempURL: URL? = {
                guard let reelData = reelsByOrder[entry.order] else { return nil }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bloggo-trip-reel-\(entry.order)-\(UUID().uuidString).mov")
                try? reelData.write(to: temp)
                return temp
            }()
            defer {
                if let reelTempURL { try? FileManager.default.removeItem(at: reelTempURL) }
            }
            let captureId = try AppCapturePhotoService.shared.saveSharedImport(
                image: uiImage,
                timestamp: timestamp,
                location: location,
                caption: entry.caption,
                momentVideoSourceURL: reelTempURL
            )
            let localId = AppCapturePhotoService.identifier(for: captureId)
            let photo = MockPhoto(
                id: UUID(),
                imageName: entry.imageName,
                timestamp: timestamp,
                locationName: entry.locationName,
                countryName: entry.countryNamePhoto,
                isSelected: entry.isSelected,
                localIdentifier: localId,
                location: coord,
                caption: entry.caption
            )

            if var bucket = dayBuckets[key] {
                bucket.photos.append(photo)
                dayBuckets[key] = bucket
            } else {
                dayBuckets[key] = (
                    dayIndex: entry.dayIndex,
                    dateText: entry.dateText,
                    countryCode: entry.countryCode,
                    countryName: entry.countryName,
                    cityName: entry.cityName,
                    photos: [photo]
                )
            }
        }

        let sortedKeys = dayBuckets.keys.sorted { lhs, rhs in
            let l = dayBuckets[lhs]!
            let r = dayBuckets[rhs]!
            if l.dayIndex != r.dayIndex { return l.dayIndex < r.dayIndex }
            return lhs < rhs
        }

        var tripDays: [TripDay] = []
        for key in sortedKeys {
            guard let b = dayBuckets[key] else { continue }
            let sortedPhotos = b.photos.sorted { $0.timestamp < $1.timestamp }
            tripDays.append(
                TripDay(
                    id: UUID(),
                    dayIndex: b.dayIndex,
                    dateText: b.dateText,
                    photos: sortedPhotos,
                    countryCode: b.countryCode,
                    countryName: b.countryName,
                    cityName: b.cityName
                )
            )
        }

        let firstLocalId = tripDays.flatMap(\.photos).first(where: { $0.isSelected })?.localIdentifier
            ?? tripDays.flatMap(\.photos).first?.localIdentifier

        return TripDraft(
            id: UUID(),
            title: manifest.tripTitle,
            dateRangeText: manifest.dateRangeText,
            days: tripDays,
            coverImageName: manifest.coverImageName,
            isScannedFromDefaultRange: manifest.isScannedFromDefaultRange,
            draftCreatedAgoText: manifest.draftCreatedAgoText,
            daysSeasonText: manifest.daysSeasonText,
            coverTheme: manifest.coverTheme,
            coverAssetIdentifier: firstLocalId
        )
    }
}

// MARK: - Saved blog → TripDraft (nearby share from created / saved blog)

enum TripShareBlogDraftBuilder {
    /// Builds a `TripDraft` from a saved recap for P2P export. Only **included** photos with a non-empty `localIdentifier` are included.
    static func tripDraft(from detail: RecapBlogDetail) -> TripDraft? {
        let sortedDays = detail.days.sorted { $0.dayIndex < $1.dayIndex }
        var tripDays: [TripDay] = []
        for day in sortedDays {
            let stops = day.placeStops.sorted { $0.orderIndex < $1.orderIndex }
            var mockPhotos: [MockPhoto] = []
            for stop in stops {
                let sortedPhotos = stop.photos.sorted { $0.timestamp < $1.timestamp }
                for p in sortedPhotos where p.isIncluded {
                    let lid = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !lid.isEmpty else { continue }
                    mockPhotos.append(
                        MockPhoto(
                            id: p.id,
                            imageName: p.imageName,
                            timestamp: p.timestamp,
                            locationName: nil,
                            countryName: nil,
                            isSelected: true,
                            localIdentifier: lid,
                            location: p.location,
                            caption: p.caption
                        )
                    )
                }
            }
            guard !mockPhotos.isEmpty else { continue }
            tripDays.append(
                TripDay(
                    id: day.id,
                    dayIndex: day.dayIndex,
                    dateText: day.dateText,
                    photos: mockPhotos,
                    countryCode: nil,
                    countryName: nil,
                    cityName: nil
                )
            )
        }
        guard !tripDays.isEmpty else { return nil }
        let dateRangeText = Self.dateRangeText(for: tripDays)
        return TripDraft(
            id: detail.id,
            title: detail.title,
            dateRangeText: dateRangeText,
            days: tripDays,
            coverImageName: "photo.on.rectangle.angled",
            isScannedFromDefaultRange: false,
            draftCreatedAgoText: "From saved blog",
            daysSeasonText: "",
            coverTheme: detail.coverTheme,
            coverAssetIdentifier: detail.selectedCoverPhotoIdentifier
        )
    }

    private static func dateRangeText(for days: [TripDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if first.dateText == last.dateText { return first.dateText }
        return "\(first.dateText) – \(last.dateText)"
    }
}

// MARK: - RecapBlogDetail → Nearby package (preserve captions/stories)

/// Error type for recap-level sharing (preserves sender captions, day caption, place notes, and stories).
enum TripShareRecapImportError: Error {
    case missingManifest
    case schemaUnsupported(Int)
    case photoCountMismatch
    case hashMismatch(order: Int)
    case emptyPhotoList
}

enum TripShareRecapExportError: Error {
    case noExportableIncludedPhotos
    case missingPhotoLocalIdentifier
    case imageEncodingFailed
}

/// Serializable recap trip package: day + place story + per-photo captions, plus JPEG resources.
struct TripShareRecapManifestV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var tripTitle: String
    var tripNarrative: String?
    var countryName: String?
    var coverTheme: String
    /// Index into the `photos` array (and thus the sent JPEG resource order list).
    var coverPhotoOrder: Int?

    var days: [TripShareRecapDayV1]
    var photos: [TripShareRecapPhotoEntryV1]
}

struct TripShareRecapDayV1: Codable, Equatable, Sendable {
    var dayIndex: Int
    /// `Date.timeIntervalSince1970` for stable decoding across devices.
    var dateUnixSeconds: TimeInterval
    var dayCaption: String?
    var dayNarrative: String?
    var placeStops: [TripShareRecapPlaceStopV1]
}

struct TripShareRecapPlaceStopV1: Codable, Equatable, Sendable {
    var orderIndex: Int
    var placeTitle: String
    var placeSubtitle: String?
    var representativeLatitude: Double?
    var representativeLongitude: Double?
    var noteText: String?
    var overallStory: String?
    var overallStoryIsManual: Bool
    var placeNarrative: String?
}

struct TripShareRecapPhotoEntryV1: Codable, Equatable, Sendable {
    /// Monotonic index matching `sendResource` name `bloggo-photo-<order>.jpg`.
    var order: Int

    var dayIndex: Int
    var stopOrderIndex: Int

    var timestamp: TimeInterval
    var latitude: Double?
    var longitude: Double?

    var imageName: String
    var isIncluded: Bool

    var caption: String?
    var captionIsManual: Bool

    /// SHA256 hex of JPEG bytes.
    var contentSha256Hex: String
    var byteCount: Int
    /// Optional moment reel sent as `bloggo-reel-<order>.mov`.
    var reelContentSha256Hex: String?
    var reelByteCount: Int?
}

enum TripShareRecapExporter {
    /// Builds manifest + JPEG data for included photos only (used to preserve visible captions/stories without requiring cloud-only images).
    @MainActor
    static func makePayload(from detail: RecapBlogDetail) async throws -> (manifest: TripShareRecapManifestV1, images: [Data], reelsByOrder: [Int: Data]) {
        var days: [TripShareRecapDayV1] = []
        var photos: [TripShareRecapPhotoEntryV1] = []
        var images: [Data] = []
        var reelsByOrder: [Int: Data] = [:]

        var coverPhotoOrder: Int? = nil

        var order = 0
        let sortedDays = detail.days.sorted { $0.dayIndex < $1.dayIndex }
        for day in sortedDays {
            let sortedStops = day.placeStops.sorted { $0.orderIndex < $1.orderIndex }
            var stopEntries: [TripShareRecapPlaceStopV1] = []

            for stop in sortedStops {
                // Build stop story metadata regardless of whether any photos are exportable.
                stopEntries.append(
                    TripShareRecapPlaceStopV1(
                        orderIndex: stop.orderIndex,
                        placeTitle: stop.placeTitle,
                        placeSubtitle: stop.placeSubtitle,
                        representativeLatitude: stop.representativeLocation?.latitude,
                        representativeLongitude: stop.representativeLocation?.longitude,
                        noteText: stop.noteText,
                        overallStory: stop.overallStory,
                        overallStoryIsManual: stop.overallStoryIsManual,
                        placeNarrative: stop.placeNarrative
                    )
                )

                // Export only included photos that we can actually load image bytes for.
                let included = stop.photos.filter { $0.isIncluded }.sorted { $0.timestamp < $1.timestamp }
                for photo in included {
                    guard let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !lid.isEmpty else { continue }
                    guard let image = await ImageLoader.shared.loadImage(
                        assetIdentifier: lid,
                        targetSize: CGSize(width: 2048, height: 2048)
                    ) else { continue }
                    guard let jpeg = image.jpegData(compressionQuality: 0.88) else { continue }

                    let digest = SHA256.hash(data: jpeg)
                    let hex = digest.map { String(format: "%02x", $0) }.joined()

                    var reelHex: String?
                    var reelByteCount: Int?
                    if let reelData = MomentVideoTransfer.loadMomentVideoData(for: photo) {
                        reelsByOrder[order] = reelData
                        reelHex = MomentVideoTransfer.sha256Hex(of: reelData)
                        reelByteCount = reelData.count
                    }

                    if let coverId = detail.selectedCoverPhotoIdentifier,
                       coverId == lid,
                       coverPhotoOrder == nil {
                        coverPhotoOrder = order
                    }

                    photos.append(
                        TripShareRecapPhotoEntryV1(
                            order: order,
                            dayIndex: day.dayIndex,
                            stopOrderIndex: stop.orderIndex,
                            timestamp: photo.timestamp.timeIntervalSince1970,
                            latitude: photo.location?.latitude,
                            longitude: photo.location?.longitude,
                            imageName: photo.imageName,
                            isIncluded: photo.isIncluded,
                            caption: photo.caption,
                            captionIsManual: photo.captionIsManual,
                            contentSha256Hex: hex,
                            byteCount: jpeg.count,
                            reelContentSha256Hex: reelHex,
                            reelByteCount: reelByteCount
                        )
                    )
                    images.append(jpeg)
                    order += 1
                }
            }

            days.append(
                TripShareRecapDayV1(
                    dayIndex: day.dayIndex,
                    dateUnixSeconds: day.date.timeIntervalSince1970,
                    dayCaption: day.dayCaption,
                    dayNarrative: day.dayNarrative,
                    placeStops: stopEntries
                )
            )
        }

        guard !photos.isEmpty else {
            throw TripShareRecapExportError.noExportableIncludedPhotos
        }

        // Fallback cover selection if the saved cover isn't among exportable included photos.
        if coverPhotoOrder == nil {
            coverPhotoOrder = photos.first?.order
        }

        let manifest = TripShareRecapManifestV1(
            schemaVersion: TripShareNearbyConfig.schemaVersion,
            tripTitle: detail.title,
            tripNarrative: detail.tripNarrative,
            countryName: detail.countryName,
            coverTheme: detail.coverTheme,
            coverPhotoOrder: coverPhotoOrder,
            days: days,
            photos: photos
        )
        return (manifest, images, reelsByOrder)
    }
}

enum TripShareRecapImporter {
    /// Decodes manifest + JPEG resources into a new `RecapBlogDetail` with **new local capture assets**.
    static func makeRecapBlogDetail(
        manifest: TripShareRecapManifestV1,
        images: [Data],
        reelsByOrder: [Int: Data] = [:]
    ) throws -> RecapBlogDetail {
        guard manifest.schemaVersion == TripShareNearbyConfig.schemaVersion else {
            throw TripShareRecapImportError.schemaUnsupported(manifest.schemaVersion)
        }
        guard manifest.photos.count == images.count else {
            throw TripShareRecapImportError.photoCountMismatch
        }
        guard !manifest.photos.isEmpty else {
            throw TripShareRecapImportError.emptyPhotoList
        }

        for (entry, data) in zip(manifest.photos, images) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == entry.contentSha256Hex, data.count == entry.byteCount else {
                throw TripShareRecapImportError.hashMismatch(order: entry.order)
            }
            if let reelHex = entry.reelContentSha256Hex, let reelCount = entry.reelByteCount {
                guard let reelData = reelsByOrder[entry.order],
                      reelData.count == reelCount,
                      MomentVideoTransfer.sha256Hex(of: reelData) == reelHex else {
                    throw TripShareRecapImportError.hashMismatch(order: entry.order)
                }
            }
        }

        let importedTripId = UUID()

        // Group imported photos into (dayIndex, stopOrderIndex).
        var photosByDayStop: [String: [RecapPhoto]] = [:]
        var localIdByOrder: [Int: String] = [:]

        for (entry, data) in zip(manifest.photos, images) {
            guard let uiImage = UIImage(data: data) else { continue }
            let timestamp = Date(timeIntervalSince1970: entry.timestamp)
            let location: CLLocation? = {
                if let lat = entry.latitude, let lon = entry.longitude {
                    return CLLocation(latitude: lat, longitude: lon)
                }
                return nil
            }()
            let reelTempURL: URL? = {
                guard let reelData = reelsByOrder[entry.order] else { return nil }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bloggo-recap-reel-\(entry.order)-\(UUID().uuidString).mov")
                try? reelData.write(to: temp)
                return temp
            }()
            defer {
                if let reelTempURL { try? FileManager.default.removeItem(at: reelTempURL) }
            }

            let captureId = try AppCapturePhotoService.shared.saveSharedImport(
                image: uiImage,
                timestamp: timestamp,
                location: location,
                caption: entry.caption,
                momentVideoSourceURL: reelTempURL
            )
            let localIdentifier = AppCapturePhotoService.identifier(for: captureId)
            localIdByOrder[entry.order] = localIdentifier

            let recapPhoto = RecapPhoto(
                id: UUID(),
                timestamp: timestamp,
                location: location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                imageName: entry.imageName,
                isIncluded: entry.isIncluded,
                localIdentifier: localIdentifier,
                caption: entry.caption,
                captionIsManual: entry.captionIsManual
            )

            let key = "\(entry.dayIndex)|\(entry.stopOrderIndex)"
            photosByDayStop[key, default: []].append(recapPhoto)
        }

        // Reconstruct day/stop structure from manifest and attach photos.
        let sortedDays = manifest.days.sorted { $0.dayIndex < $1.dayIndex }
        var recapDays: [RecapBlogDay] = []

        for day in sortedDays {
            let sortedStops = day.placeStops.sorted { $0.orderIndex < $1.orderIndex }
            var placeStops: [PlaceStop] = []

            for stop in sortedStops {
                let key = "\(day.dayIndex)|\(stop.orderIndex)"
                var stopPhotos = photosByDayStop[key] ?? []
                stopPhotos.sort { $0.timestamp < $1.timestamp }

                let representativeLocation: PhotoCoordinate? = {
                    guard let lat = stop.representativeLatitude,
                          let lon = stop.representativeLongitude else { return nil }
                    return PhotoCoordinate(latitude: lat, longitude: lon)
                }()

                placeStops.append(
                    PlaceStop(
                        id: UUID(),
                        orderIndex: stop.orderIndex,
                        placeTitle: stop.placeTitle,
                        placeSubtitle: stop.placeSubtitle,
                        placeTitleIsManual: true,
                        representativeLocation: representativeLocation,
                        photos: stopPhotos,
                        noteText: stop.noteText,
                        overallStory: stop.overallStory,
                        placeNarrative: stop.placeNarrative,
                        overallStoryIsManual: stop.overallStoryIsManual
                    )
                )
            }

            let dayDate = Date(timeIntervalSince1970: day.dateUnixSeconds)
            recapDays.append(
                RecapBlogDay(
                    id: UUID(),
                    dayIndex: day.dayIndex,
                    date: dayDate,
                    placeStops: placeStops,
                    dayCaption: day.dayCaption,
                    dayNarrative: day.dayNarrative,
                    isPlaceNamesResolved: false,
                    weather: nil
                )
            )
        }

        let coverIdentifier: String? = {
            guard let coverOrder = manifest.coverPhotoOrder else { return nil }
            return localIdByOrder[coverOrder]
        }()

        return RecapBlogDetail(
            id: importedTripId,
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
}
