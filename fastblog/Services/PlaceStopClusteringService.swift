//
//  PlaceStopClusteringService.swift
//  Capper
//

import CoreLocation
import Foundation

/// Input photo for clustering: timestamp and optional location.
struct ClusterPhotoInput: Identifiable {
    let id: UUID
    let timestamp: Date
    let location: PhotoCoordinate?
}

/// Grouping heuristic constants (per product spec).
private enum GroupingConstants {
    static let fiveMinutesSeconds: TimeInterval = 5 * 60
    static let fiveHoursSeconds: TimeInterval = 5 * 3600
    static let samePlaceDistanceMeters: Double = 50
    static let walkingSpeedMetersPerSecond: Double = 1.34
    static let fudgeFactor: Double = 1.3
}

/// Takes photos for a day and returns place stops sorted oldest to newest.
/// Uses the business logic: same calendar date required; membership by time_from_group_start and distance/time_gap.
final class PlaceStopClusteringService {
    private let coordinateRoundingDecimals: Int = 3
    private let calendar = Calendar.current

    init() {}

    /// Returns place stop groups sorted by first photo timestamp ascending.
    /// Uses heuristic: same calendar date, then (time_from_group_start < 5 min OR (distance < 50m AND time < 5h AND last group)) AND (time_gap > min_expected OR time_gap < 5 min).
    func placeStops(from photos: [ClusterPhotoInput], placeTitleProvider: (Int) -> String) -> [(orderIndex: Int, photos: [ClusterPhotoInput])] {
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }

        let hasAnyLocation = sorted.contains { $0.location != nil }
        let groups: [[ClusterPhotoInput]]
        if hasAnyLocation {
            groups = clusterByHeuristic(sorted)
        } else {
            groups = clusterByTimeOnly(sorted)
        }

        return groups.enumerated().map { (orderIndex: $0.offset, photos: $0.element) }
    }

    /// Same calendar date (YYYY-MM-DD) required. Then find best matching group by heuristic; else start new group.
    private func clusterByHeuristic(_ photoList: [ClusterPhotoInput]) -> [[ClusterPhotoInput]] {
        var groups: [(reference: ClusterPhotoInput, photoList: [ClusterPhotoInput])] = []

        for photo in photoList {
            let photoDate = calendar.startOfDay(for: photo.timestamp)

            if groups.isEmpty {
                groups.append((reference: photo, photoList: [photo]))
                continue
            }

            var added = false
            for i in groups.indices {
                let group = groups[i]
                let lastPhoto = group.photoList.last!
                let lastDate = calendar.startOfDay(for: lastPhoto.timestamp)
                if lastDate != photoDate { continue }

                let distance_m: Double
                if let loc1 = lastPhoto.location, let loc2 = photo.location {
                    distance_m = distanceMeters(loc1, loc2)
                } else {
                    distance_m = 0
                }
                let time_gap_s = photo.timestamp.timeIntervalSince(lastPhoto.timestamp)
                let time_from_group_start_s = photo.timestamp.timeIntervalSince(group.reference.timestamp)
                let min_expected_s = (distance_m / GroupingConstants.walkingSpeedMetersPerSecond) * GroupingConstants.fudgeFactor

                let condition1: Bool
                if time_from_group_start_s < GroupingConstants.fiveMinutesSeconds {
                    condition1 = true
                } else if distance_m < GroupingConstants.samePlaceDistanceMeters
                    && time_from_group_start_s < GroupingConstants.fiveHoursSeconds
                    && i == groups.count - 1
                {
                    condition1 = true
                } else {
                    condition1 = false
                }

                let condition2 = time_gap_s > min_expected_s || time_gap_s < GroupingConstants.fiveMinutesSeconds

                if condition1 && condition2 {
                    var updated = groups[i]
                    updated.photoList.append(photo)
                    groups[i] = updated
                    added = true
                    break
                }
            }
            if !added {
                groups.append((reference: photo, photoList: [photo]))
            }
        }

        return groups.map(\.photoList)
    }

    /// No location: group by time only (within 30 min).
    private func clusterByTimeOnly(_ sorted: [ClusterPhotoInput]) -> [[ClusterPhotoInput]] {
        let timeProximityMinutes = 30
        var result: [[ClusterPhotoInput]] = []
        var currentGroup: [ClusterPhotoInput] = []
        var lastTimestamp: Date?

        for photo in sorted {
            if let last = lastTimestamp {
                let interval = photo.timestamp.timeIntervalSince(last)
                if interval <= Double(timeProximityMinutes * 60) {
                    currentGroup.append(photo)
                    lastTimestamp = photo.timestamp
                } else {
                    result.append(currentGroup)
                    currentGroup = [photo]
                    lastTimestamp = photo.timestamp
                }
            } else {
                currentGroup = [photo]
                lastTimestamp = photo.timestamp
            }
        }
        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }
        return result
    }

    private func distanceMeters(_ a: PhotoCoordinate, _ b: PhotoCoordinate) -> Double {
        let from = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let to = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return from.distance(from: to)
    }
}
