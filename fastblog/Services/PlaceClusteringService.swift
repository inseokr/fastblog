//
//  PlaceClusteringService.swift
//  Capper
//

import Foundation
import Photos
import CoreLocation

struct ClusteringConfig {
    static let timeGapSeconds: TimeInterval = 2 * 3600  // 2 hours
    static let distanceThresholdMeters: CLLocationDistance = 1000
}

final class PlaceClusteringService {
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Sort by creationDate ascending; nils last.
    /// Cluster: centroid-based greedy clustering.
    /// - Distance to *current cluster centroid* < 150m (ScanConfig.placeClusterMeters)
    /// - Time gap < 2h (ClusteringConfig.timeGapSeconds)
    func cluster(assets: [PHAsset]) -> [PlaceCluster] {
        let sorted = assets.sorted { a, b in
            switch (a.creationDate, b.creationDate) {
            case (let d1?, let d2?): return d1 < d2
            case (nil, _): return false
            case (_, nil): return true
            }
        }

        guard !sorted.isEmpty else { return [] }

        var clusters: [[PHAsset]] = []
        var currentCluster: [PHAsset] = [sorted[0]]
        // Track centroid of the current cluster
        var currentCentroid: (lat: Double, lon: Double)? = nil
        
        if let loc = sorted[0].location {
            currentCentroid = (loc.coordinate.latitude, loc.coordinate.longitude)
        }

        for i in 1..<sorted.count {
            let curr = sorted[i]
            let prev = sorted[i-1] // Still check time gap against previous item (chaining)
            
            // Time gap check (still chain-based for temporal continuity)
            let t1 = prev.creationDate?.timeIntervalSince1970 ?? .infinity
            let t2 = curr.creationDate?.timeIntervalSince1970 ?? -.infinity
            let timeGap = t2 - t1
            
            var shouldSplit = false
            
            if timeGap > ClusteringConfig.timeGapSeconds {
                shouldSplit = true
            } else {
                // Distance check: modify to check against CENTROID, not just previous
                if let currLoc = curr.location {
                    if let centroid = currentCentroid, !shouldSplit {
                         let centroidLoc = CLLocation(latitude: centroid.lat, longitude: centroid.lon)
                         let dist = currLoc.distance(from: centroidLoc)
                         if dist > ScanConfig.placeClusterMeters {
                             shouldSplit = true
                         }
                    } else if currentCentroid == nil && !shouldSplit {
                        // Current cluster has no location so far. If new one has location, 
                        // it becomes the anchor. We don't split just because new one has location.
                        shouldSplit = false
                    }
                } else {
                    // If no location, maybe keep with previous? 
                    // PRD says "May not define Place Clusters" if no GPS. 
                    // Current logic: if no GPS, we can't check distance. Default to split or keep?
                    // Let's keep with current if time is close, assuming same place.
                    shouldSplit = false 
                }
            }

            if shouldSplit {
                clusters.append(currentCluster)
                currentCluster = [curr]
                // Reset centroid
                if let loc = curr.location {
                    currentCentroid = (loc.coordinate.latitude, loc.coordinate.longitude)
                } else {
                    currentCentroid = nil
                }
            } else {
                currentCluster.append(curr)
                // Update centroid (running average)
                if curr.location != nil {
                    // Re-calculate average including new point
                    let locations = currentCluster.compactMap { $0.location }
                    if !locations.isEmpty {
                        let avgLat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
                        let avgLon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
                        currentCentroid = (avgLat, avgLon)
                    }
                }
            }
        }
        clusters.append(currentCluster)

        return clusters.map { group in
            placeCluster(from: group)
        }
    }

    // Removed older linear pairwise check helper as logic is moved inline for centroid access


    private func placeCluster(from assets: [PHAsset]) -> PlaceCluster {
        let ids = assets.map(\.localIdentifier)
        let coverId = ids.first ?? ""
        let dateRange = formatDateRange(assets: assets)
        let repLocation = assets.compactMap(\.location).first
        return PlaceCluster(
            resolvedTitle: "Finding place…",
            subtitle: "",
            dateRange: dateRange,
            photoCount: assets.count,
            coverAssetIdentifier: coverId,
            assetIdentifiers: ids,
            representativeLocation: repLocation
        )
    }

    private func formatDateRange(assets: [PHAsset]) -> String {
        let dates = assets.compactMap(\.creationDate)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        if first == last {
            return dateFormatter.string(from: first)
        }
        return "\(dateFormatter.string(from: first)) – \(dateFormatter.string(from: last))"
    }
}
