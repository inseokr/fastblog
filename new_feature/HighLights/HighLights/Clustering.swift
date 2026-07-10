import Foundation
import CoreLocation

/// Feature ②: place clustering (DBSCAN) + timeline sort.
/// Pure computation — no network/AI, fully on-device.
enum Clustering {

    /// DBSCAN: same place if there are >= minPts photos within eps (meters) radius.
    /// Falls back honestly to time-gap clustering if there are only photos without GPS.
    static func dbscan(_ allPhotos: [PhotoItem], epsMeters: Double = 300, minPts: Int = 3) -> [PlaceCluster] {
        let photos = allPhotos.filter(\.hasGPS)
        guard !photos.isEmpty else { return timeClusters(allPhotos) }

        var labels = [Int](repeating: -1, count: photos.count)  // -1 = unvisited, -2 = noise
        var clusterID = 0

        func neighbors(of i: Int) -> [Int] {
            let loc = CLLocation(latitude: photos[i].coordinate.latitude,
                                 longitude: photos[i].coordinate.longitude)
            return photos.indices.filter { j in
                let other = CLLocation(latitude: photos[j].coordinate.latitude,
                                       longitude: photos[j].coordinate.longitude)
                return loc.distance(from: other) <= epsMeters
            }
        }

        for i in photos.indices where labels[i] == -1 {
            let nbrs = neighbors(of: i)
            if nbrs.count < minPts { labels[i] = -2; continue }
            labels[i] = clusterID
            var queue = nbrs
            var head = 0
            while head < queue.count {
                let j = queue[head]; head += 1
                if labels[j] == -2 { labels[j] = clusterID }
                guard labels[j] == -1 else { continue }
                labels[j] = clusterID
                let jNbrs = neighbors(of: j)
                if jNbrs.count >= minPts { queue.append(contentsOf: jNbrs) }
            }
            clusterID += 1
        }

        // Even within the same GPS cluster, split into separate visits if the visit times are
        // 3+ hours apart (detects a morning/evening revisit — the input for hidden moments ⑦)
        var clusters: [PlaceCluster] = []
        for cid in 0..<clusterID {
            let members = photos.indices.filter { labels[$0] == cid }
                .map { photos[$0] }
                .sorted { $0.timestamp < $1.timestamp }
            guard !members.isEmpty else { continue }

            var current: [PhotoItem] = [members[0]]
            for photo in members.dropFirst() {
                if photo.timestamp.timeIntervalSince(current.last!.timestamp) > 3 * 3600 {
                    clusters.append(PlaceCluster(name: current[0].placeName, photos: current))
                    current = [photo]
                } else {
                    current.append(photo)
                }
            }
            clusters.append(PlaceCluster(name: current[0].placeName, photos: current))
        }

        // Photos without GPS get merged into the nearest-in-time cluster
        let orphans = allPhotos.filter { !$0.hasGPS }
        for orphan in orphans {
            if let nearest = clusters.indices.min(by: {
                abs(clusters[$0].arrival.timeIntervalSince(orphan.timestamp))
                    < abs(clusters[$1].arrival.timeIntervalSince(orphan.timestamp))
            }) {
                clusters[nearest].photos.append(orphan)
                clusters[nearest].photos.sort { $0.timestamp < $1.timestamp }
            }
        }

        // Timeline sort (Prof. Seoin: by EXIF timestamp, trivial) + default names for unnamed clusters
        var result = clusters.sorted { $0.arrival < $1.arrival }
        for i in result.indices where result[i].name.isEmpty {
            result[i].name = "Stop \(i + 1)"
        }
        return result
    }

    /// Fallback: no GPS at all — treat a 90+ min shooting gap as a different place
    private static func timeClusters(_ photos: [PhotoItem]) -> [PlaceCluster] {
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return [] }
        var clusters: [PlaceCluster] = []
        var current: [PhotoItem] = [first]
        for photo in sorted.dropFirst() {
            if photo.timestamp.timeIntervalSince(current.last!.timestamp) > 90 * 60 {
                clusters.append(PlaceCluster(name: "", photos: current))
                current = [photo]
            } else {
                current.append(photo)
            }
        }
        clusters.append(PlaceCluster(name: "", photos: current))
        for i in clusters.indices { clusters[i].name = "Stop \(i + 1)" }
        return clusters
    }
}
