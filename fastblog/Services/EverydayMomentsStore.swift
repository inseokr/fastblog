//
//  EverydayMomentsStore.swift
//  fastblog
//
//  Standalone everyday moments for My Places (not nested under trip blogs).
//

import Combine
import CoreLocation
import Foundation
import SwiftUI

enum EverydayRetentionKeys {
    static let shouldShowPushPrompt = "bloggo.everyday.shouldShowPushPrompt"
    static let lastAppOpenDate = "bloggo.everyday.lastAppOpenDate"
}

@MainActor
final class EverydayMomentsStore: ObservableObject {
    static let shared = EverydayMomentsStore()

    @Published private(set) var everydayCaptureIdentifiers: Set<String> = []

    private let clusteringService = PlaceStopClusteringService()
    private let captureService = AppCapturePhotoService.shared

    private static let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EverydayMoments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dirForResource = dir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirForResource.setResourceValues(resourceValues)
        return dir
    }()

    private static let stateURL = storageDirectory.appendingPathComponent("everydayCaptures.json")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct PersistedState: Codable {
        var captureIdentifiers: [String]
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Registration

    /// Registers an in-app capture as an everyday moment (My Places only).
    func registerCapture(localIdentifier: String) {
        guard AppCapturePhotoService.uuid(from: localIdentifier) != nil else { return }
        guard !everydayCaptureIdentifiers.contains(localIdentifier) else { return }
        everydayCaptureIdentifiers.insert(localIdentifier)
        persist()
        if everydayCaptureIdentifiers.count == 5 {
            UserDefaults.standard.set(true, forKey: EverydayRetentionKeys.shouldShowPushPrompt)
        }
        DraftReminderNotificationManager.scheduleEverydayReturnReminder()
        DraftReminderNotificationManager.schedulePlacesWeeklyDigestIfNeeded(placeCount: clusters.count)
        AppAnalytics.shared.trackEvent(
            name: "everyday_capture_registered",
            properties: ["localIdentifier": localIdentifier]
        )
    }

    func removeCaptures(identifiers: Set<String>) {
        let removed = identifiers.intersection(everydayCaptureIdentifiers)
        guard !removed.isEmpty else { return }
        everydayCaptureIdentifiers.subtract(removed)
        persist()
    }

    func containsCapture(identifier: String) -> Bool {
        everydayCaptureIdentifiers.contains(identifier)
    }

    // MARK: - Clusters

    var clusters: [EverydayPlaceCluster] {
        buildClusters(from: Array(everydayCaptureIdentifiers))
    }

    var recentClusters: [EverydayPlaceCluster] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return clusters.filter { $0.latestVisitDate >= weekAgo }
    }

    /// Maps everyday clusters to VisitedPlaceSummary for My Places.
    var visitedPlaceSummaries: [VisitedPlaceSummary] {
        clusters.compactMap { cluster in
            let photos = recapPhotos(for: cluster.captureIdentifiers)
            guard !photos.isEmpty else { return nil }
            let latest = photos.map(\.timestamp).max() ?? cluster.latestVisitDate
            let year = Calendar.current.component(.year, from: latest)
            let country = cluster.placeSubtitle?.components(separatedBy: ", ").last ?? "Local"
            let city = cluster.placeSubtitle ?? ""
            return VisitedPlaceSummary(
                placeId: "everyday_\(cluster.id.uuidString)",
                placeName: cluster.placeTitle,
                city: city,
                country: country,
                categoryRawValue: cluster.placeCategory,
                latestVisitDate: latest,
                year: year,
                photos: photos.sorted(by: { $0.timestamp > $1.timestamp }),
                placeCaption: cluster.noteText,
                photoCaptions: photos.compactMap(\.caption).filter { !$0.isEmpty },
                relatedBlogs: [],
                isEverydayOnly: true
            )
        }
        .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    // MARK: - Promote to blog

    /// Builds MockPhoto array from everyday capture identifiers for trip/blog creation.
    func mockPhotos(for identifiers: [String]) -> [MockPhoto] {
        identifiers.compactMap { id in
            guard let uuid = AppCapturePhotoService.uuid(from: id),
                  let meta = captureService.metadata(captureId: uuid) else { return nil }
            let placeName = meta.placeTitle ?? "Captured Moment"
            let country = meta.placeSubtitle?.components(separatedBy: ", ").last
            return MockPhoto(
                id: uuid,
                imageName: "camera.fill",
                timestamp: meta.timestamp,
                locationName: placeName,
                countryName: country,
                isSelected: true,
                localIdentifier: id,
                location: meta.location,
                caption: meta.caption
            )
        }
    }

    /// Removes captures from everyday store after promotion to a blog.
    func promoteCapturesToBlog(identifiers: Set<String>) -> [MockPhoto] {
        let photos = mockPhotos(for: Array(identifiers))
        removeCaptures(identifiers: identifiers)
        AppAnalytics.shared.trackEvent(
            name: "everyday_promoted_to_blog",
            properties: ["count": identifiers.count]
        )
        return photos
    }

    // MARK: - Import from blog (migration)

    func importFromBlogPlaceStop(_ stop: PlaceStop) {
        let ids = stop.photos.compactMap(\.localIdentifier).filter {
            AppCapturePhotoService.uuid(from: $0) != nil
        }
        for id in ids {
            everydayCaptureIdentifiers.insert(id)
        }
        persist()
    }

    // MARK: - Private

    private func buildClusters(from identifiers: [String]) -> [EverydayPlaceCluster] {
        struct CaptureRow {
            let identifier: String
            let uuid: UUID
            let timestamp: Date
            let location: PhotoCoordinate?
            let placeTitle: String?
            let placeSubtitle: String?
            let placeCategory: String?
            let caption: String?
        }

        let rows: [CaptureRow] = identifiers.compactMap { id in
            guard let uuid = AppCapturePhotoService.uuid(from: id),
                  let meta = captureService.metadata(captureId: uuid) else { return nil }
            return CaptureRow(
                identifier: id,
                uuid: uuid,
                timestamp: meta.timestamp,
                location: meta.location,
                placeTitle: meta.placeTitle,
                placeSubtitle: meta.placeSubtitle,
                placeCategory: meta.placeCategory,
                caption: meta.caption
            )
        }
        guard !rows.isEmpty else { return [] }

        let cal = Calendar.current
        let byDay = Dictionary(grouping: rows) { cal.startOfDay(for: $0.timestamp) }
        var allClusters: [EverydayPlaceCluster] = []

        for (_, dayRows) in byDay.sorted(by: { $0.key < $1.key }) {
            let inputs = dayRows.map {
                ClusterPhotoInput(id: $0.uuid, timestamp: $0.timestamp, location: $0.location)
            }
            let groups = clusteringService.placeStops(from: inputs) { index in
                "Stop \(index + 1)"
            }
            for group in groups {
                let groupRows = group.photos.compactMap { photo in
                    dayRows.first { $0.uuid == photo.id }
                }
                guard !groupRows.isEmpty else { continue }
                let titles = groupRows.compactMap(\.placeTitle).filter { !$0.isEmpty }
                let placeTitle = titles.first ?? groupRows.first?.placeTitle ?? "Captured Moment"
                let subtitle = groupRows.compactMap(\.placeSubtitle).first
                let category = groupRows.compactMap(\.placeCategory).first
                let loc = groupRows.compactMap(\.location).first
                let latest = groupRows.map(\.timestamp).max() ?? Date()
                let ids = groupRows.map(\.identifier)
                allClusters.append(EverydayPlaceCluster(
                    placeTitle: placeTitle,
                    placeSubtitle: subtitle,
                    placeCategory: category,
                    representativeLocation: loc,
                    captureIdentifiers: ids,
                    latestVisitDate: latest,
                    noteText: groupRows.compactMap(\.caption).first
                ))
            }
        }

        return allClusters.sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    private func recapPhotos(for identifiers: [String]) -> [RecapPhoto] {
        identifiers.compactMap { id in
            guard let uuid = AppCapturePhotoService.uuid(from: id),
                  let meta = captureService.metadata(captureId: uuid) else { return nil }
            return RecapPhoto(
                id: uuid,
                timestamp: meta.timestamp,
                location: meta.location,
                imageName: "camera.fill",
                isIncluded: true,
                localIdentifier: id,
                caption: meta.caption,
                digitizedTime: meta.digitizedTime
            )
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? Self.decoder.decode(PersistedState.self, from: data) else { return }
        everydayCaptureIdentifiers = Set(state.captureIdentifiers)
    }

    private func persist() {
        let state = PersistedState(captureIdentifiers: Array(everydayCaptureIdentifiers))
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
}
