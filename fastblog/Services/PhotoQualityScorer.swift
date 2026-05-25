//
//  PhotoQualityScorer.swift
//  fastblog
//
//  Scores photos using iOS Vision framework AI for intelligent selection.
//  Mirrors the coverPhotoScore system from the companion app.
//

import CoreImage
import CoreLocation
import Foundation
import Photos
import Vision

// MARK: - Score Model

/// Composite quality score for a single photo. Persisted with RecapPhoto.
struct PhotoScore: Codable, Equatable {
    /// Aesthetic quality from VNGenerateImageAestheticsScoresRequest (iOS 17+) or saliency fallback. 0–1.
    let aesthetics: Double
    /// Sharpness estimated from contour detection. 0–1.
    let sharpness: Double
    /// Legacy field; always 0 (face penalty removed). Kept for persisted blog JSON compatibility.
    let facePenalty: Double
    /// Weighted composite: aesthetics×0.6 + sharpness×0.4.
    let totalScore: Double
}

// MARK: - Scorer

/// Scores a batch of photos using Vision framework. Runs as a Swift actor (thread-safe).
actor PhotoQualityScorer {
    static let shared = PhotoQualityScorer()

    // Score weights (mirror expo app)
    private let aestheticsWeight = 0.6
    private let sharpnessWeight  = 0.4

    // Thumbnail size for analysis (balance speed vs accuracy)
    private let analysisSize = CGSize(width: 300, height: 300)

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    // MARK: - Public API

    /// Score multiple photos in parallel. Returns a dict keyed by localIdentifier.
    /// Missing or errored photos are omitted from the result.
    func scorePhotos(identifiers: [String]) async -> [String: PhotoScore] {
        guard !identifiers.isEmpty else {
            print("[PQS] scorePhotos: called with 0 identifiers — skipping")
            return [:]
        }
        print("[PQS] scorePhotos: start count=\(identifiers.count)")

        let assets = fetchAssets(identifiers: identifiers)
        print("[PQS] scorePhotos: fetchAssets returned \(assets.count)/\(identifiers.count)")
        guard !assets.isEmpty else {
            print("[PQS] scorePhotos: no assets fetched — returning empty")
            return [:]
        }

        /// Unbounded parallelism against `assetsd` (dozens of concurrent `PHImageManager` requests) reliably
        /// triggers XPC/CoreData flakes on large trips — cap in-flight scoring work.
        let maxConcurrentScores = 6
        var results: [String: PhotoScore] = [:]
        var iterator = assets.makeIterator()
        await withTaskGroup(of: (String, PhotoScore?).self) { group in
            for _ in 0..<min(maxConcurrentScores, assets.count) {
                if let asset = iterator.next() {
                    group.addTask {
                        let score = await self.scoreAsset(asset)
                        return (asset.localIdentifier, score)
                    }
                }
            }
            for await (identifier, score) in group {
                if let score {
                    results[identifier] = score
                } else {
                    print("[PQS] scorePhotos: scoreAsset returned nil for \(identifier.prefix(8))…")
                }
                if let next = iterator.next() {
                    group.addTask {
                        let s = await self.scoreAsset(next)
                        return (next.localIdentifier, s)
                    }
                }
            }
        }
        print("[PQS] scorePhotos: done scored=\(results.count)/\(assets.count)")
        return results
    }

    /// Scores an in-app capture (`bloggo-capture:`) from its on-disk still (`image.jpg`).
    func scoreAppCapture(identifier: String) async -> PhotoScore? {
        guard identifier.hasPrefix(AppCapturePhotoService.prefix),
              let uuid = AppCapturePhotoService.uuid(from: identifier),
              let image = AppCapturePhotoService.shared.loadImage(captureId: uuid),
              let cgImage = image.cgImage else { return nil }
        return await score(cgImage: cgImage)
    }

    // MARK: - Private helpers

    private func scoreAsset(_ asset: PHAsset) async -> PhotoScore? {
        let shortId = String(asset.localIdentifier.prefix(8))
        print("[PQS] scoreAsset: start id=\(shortId)… mediaType=\(asset.mediaType.rawValue) pixelSize=\(asset.pixelWidth)×\(asset.pixelHeight)")
        guard let cgImage = await loadThumbnail(asset: asset) else {
            print("[PQS] scoreAsset: loadThumbnail returned nil for \(shortId)… — skipping")
            return nil
        }
        print("[PQS] scoreAsset: thumbnail loaded \(cgImage.width)×\(cgImage.height) for \(shortId)…")
        return await score(cgImage: cgImage)
    }

    private func score(cgImage: CGImage) async -> PhotoScore? {
        async let aesthetics = analyzeAesthetics(cgImage)
        async let sharpness  = analyzeSharpness(cgImage)

        let a = await aesthetics
        let s = await sharpness
        let total = max(0, a * aestheticsWeight + s * sharpnessWeight)

        return PhotoScore(aesthetics: a, sharpness: s, facePenalty: 0, totalScore: total)
    }

    /// Load a small thumbnail from the photo library. Returns nil on failure.
    private func loadThumbnail(asset: PHAsset) async -> CGImage? {
        let shortId = String(asset.localIdentifier.prefix(8))
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // .fastFormat requires a pre-cached thumbnail and fails with 3303 when none exists.
            // .opportunistic falls back to generating the image if no fast thumbnail is available.
            options.deliveryMode = .opportunistic
            options.resizeMode   = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: analysisSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded   = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled  = (info?[PHImageCancelledKey] as? Bool) ?? false
                let callbackError = info?[PHImageErrorKey] as? Error
                print("[PQS] loadThumbnail cb id=\(shortId)… image=\(image != nil) degraded=\(isDegraded) cancelled=\(isCancelled) error=\(callbackError?.localizedDescription ?? "none") resumed=\(resumed)")
                guard !resumed else { return }
                // Skip degraded intermediate results — wait for the final delivery
                if isDegraded { return }
                resumed = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: - Aesthetics

    /// Returns an aesthetics score 0–1.
    /// Uses VNCalculateImageAestheticsScoresRequest on iOS 18+; falls back to saliency on older OS.
    private func analyzeAesthetics(_ cgImage: CGImage) async -> Double {
        if #available(iOS 18.0, *) {
            print("[PQS] analyzeAesthetics: using modern path (iOS 18+)")
            return await analyzeAestheticsModern(cgImage)
        } else {
            print("[PQS] analyzeAesthetics: using saliency fallback (pre-iOS 18)")
            return await analyzeAestheticsFallback(cgImage)
        }
    }

    @available(iOS 18.0, *)
    private func analyzeAestheticsModern(_ cgImage: CGImage) async -> Double {
        #if DEBUG
        print(
            "[PhotoQualityScorer] analyzeAestheticsModern enter size=\(cgImage.width)×\(cgImage.height)"
        )
        #endif
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("[PhotoQualityScorer] analyzeAestheticsModern perform failed: \(error)")
            #endif
            return 0.5
        }
        guard let obs = request.results?.first as? VNImageAestheticsScoresObservation else {
            #if DEBUG
            print("[PhotoQualityScorer] analyzeAestheticsModern no VNImageAestheticsScoresObservation (using 0.5)")
            #endif
            return 0.5
        }
        // isUtility = receipt/screenshot/document → penalise heavily
        if obs.isUtility {
            #if DEBUG
            print("[PhotoQualityScorer] analyzeAestheticsModern utility image → aesthetics=0.1")
            #endif
            return 0.1
        }
        let score = Double(obs.overallScore)
        #if DEBUG
        print(
            "[PhotoQualityScorer] analyzeAestheticsModern ok overallScore=\(String(format: "%.4f", score)) isUtility=false"
        )
        #endif
        return score
    }

    /// Saliency-based fallback: ideal salient area ~20–35% of frame.
    private func analyzeAestheticsFallback(_ cgImage: CGImage) async -> Double {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNSaliencyImageObservation else { return 0.5 }
        let objects = obs.salientObjects ?? []
        let totalArea = objects.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        // Ideal coverage: ~25%. Penalise extremes.
        let ideal: Double = 0.25
        let deviation = abs(totalArea - ideal)
        return max(0.1, 1.0 - deviation * 2.0)
    }

    // MARK: - Sharpness

    /// Estimates sharpness by counting Vision contours. More/complex contours → sharper.
    private func analyzeSharpness(_ cgImage: CGImage) async -> Double {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 0.9
        request.detectsDarkOnLight = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNContoursObservation else { return 0.5 }
        // Typically blurry images have very few meaningful contours (<15);
        // sharp images can have 50-200+.
        let count = Double(obs.contourCount)
        return min(1.0, count / 120.0)
    }

    // MARK: - PHAsset fetch

    private func fetchAssets(identifiers: [String]) -> [PHAsset] {
        let options = PHFetchOptions()
        let result  = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}

// MARK: - Per-stop scoring sample (temporal spread)

extension Array where Element == RecapPhoto {
    /// Max library + in-app photos per place stop sent through Vision on each scoring pass.
    static let qualityScoringSampleLimit = 10

    /// Unscored photos to run through Vision. When count exceeds `limit`, picks evenly across visit time.
    func localIdentifiersForQualityScoring(limit: Int = qualityScoringSampleLimit) -> [String] {
        let unscored = filter { $0.qualityScore == nil && $0.localIdentifier != nil }
        let sorted = unscored.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return ($0.localIdentifier ?? "") < ($1.localIdentifier ?? "")
        }
        guard sorted.count > limit else {
            return sorted.compactMap(\.localIdentifier)
        }
        return temporalSampleLocalIdentifiers(from: sorted, limit: limit)
    }

    /// Evenly spaced photo ids across visit time (used when scores are not available yet).
    func spreadSampledPhotoIds(limit: Int) -> Set<UUID> {
        let sorted = self.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard sorted.count > limit else { return Set(sorted.map(\.id)) }
        return Set(temporalSpreadPhotos(from: sorted, limit: limit).map(\.id))
    }

    private func temporalSampleLocalIdentifiers(from sorted: [RecapPhoto], limit: Int) -> [String] {
        temporalSpreadPhotos(from: sorted, limit: limit).compactMap(\.localIdentifier)
    }

    private func temporalSpreadPhotos(from sorted: [RecapPhoto], limit: Int) -> [RecapPhoto] {
        guard let first = sorted.first, let last = sorted.last else { return [] }

        let t0 = first.timestamp.timeIntervalSince1970
        let t1 = last.timestamp.timeIntervalSince1970
        if t1 <= t0 {
            return Array(sorted.prefix(limit))
        }

        var picked: [RecapPhoto] = []
        var pickedIds = Set<UUID>()
        let slotCount = limit
        let divisor = Swift.max(1, slotCount - 1)

        for slot in 0..<slotCount {
            let target = t0 + (t1 - t0) * Double(slot) / Double(divisor)
            var best: RecapPhoto?
            var bestDelta = TimeInterval.greatestFiniteMagnitude

            for photo in sorted {
                guard !pickedIds.contains(photo.id) else { continue }
                let delta = abs(photo.timestamp.timeIntervalSince1970 - target)
                if delta < bestDelta {
                    bestDelta = delta
                    best = photo
                } else if delta == bestDelta, let current = best {
                    if photo.id.uuidString < current.id.uuidString { best = photo }
                }
            }

            if let photo = best {
                picked.append(photo)
                pickedIds.insert(photo.id)
            }
        }

        if picked.count < limit {
            for photo in sorted where !pickedIds.contains(photo.id) {
                picked.append(photo)
                pickedIds.insert(photo.id)
                if picked.count >= limit { break }
            }
        }

        return picked
    }
}

// MARK: - PlaceStop auto-selection helper

extension Array where Element == RecapPhoto {
    /// Default max included photos per place stop: 3 if stop has >5 photos, else 2 or 1.
    func maxAutoIncludedCount() -> Int {
        let count = self.count
        return count > 5 ? 3 : (count >= 3 ? 2 : 1)
    }

    /// Returns the top-quality photo ids that should be included by default.
    /// 3 photos if total > 5, 2 if 3–5, 1 if 1–2. Users can add more via "Manage Photos".
    /// Favorites (PHAsset.isFavorite) are always prioritized: if there are fewer favorites than the
    /// slot limit they are always included; if there are more, the best-scoring ones fill the slots.
    /// When no favorites exist, falls back to pure score ranking.
    func autoSelectedIds() -> Set<UUID> {
        guard !isEmpty else { return [] }
        let maxSelected = maxAutoIncludedCount()

        let minTimeDistance: TimeInterval = 90
        let minSpatialDistance: CLLocationDistance = 35

        let favorites = filter(\.isFavorite)
        let nonFavorites = filter { !$0.isFavorite }

        if !favorites.isEmpty {
            if favorites.count >= maxSelected {
                // More favorites than needed — pick best-scoring ones.
                let ranked = favorites.sorted {
                    ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0)
                }
                var selected: [RecapPhoto] = []
                for candidate in ranked {
                    guard selected.count < maxSelected else { break }
                    if isDistinctEnough(candidate, from: selected, minTimeDistance: minTimeDistance, minSpatialDistance: minSpatialDistance) {
                        selected.append(candidate)
                    }
                }
                if selected.count < maxSelected {
                    for candidate in ranked where !selected.contains(where: { $0.id == candidate.id }) {
                        guard selected.count < maxSelected else { break }
                        selected.append(candidate)
                    }
                }
                return Set(selected.map(\.id))
            } else {
                // Fewer favorites than the limit — always include all favorites, fill remainder by score.
                var selected = favorites
                let remaining = maxSelected - favorites.count
                let ranked = nonFavorites.sorted {
                    ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0)
                }
                for candidate in ranked {
                    guard selected.count < maxSelected else { break }
                    if isDistinctEnough(candidate, from: selected, minTimeDistance: minTimeDistance, minSpatialDistance: minSpatialDistance) {
                        selected.append(candidate)
                    }
                }
                if selected.count < maxSelected {
                    for candidate in ranked where !selected.contains(where: { $0.id == candidate.id }) {
                        guard selected.count < maxSelected,
                              selected.count - favorites.count < remaining else { break }
                        selected.append(candidate)
                    }
                }
                return Set(selected.map(\.id))
            }
        }

        // No favorites — use score-based selection.
        let scored = filter { $0.qualityScore != nil }
        if scored.isEmpty {
            return spreadSampledPhotoIds(limit: maxSelected)
        }

        let rankedPhotos = sorted {
            ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0)
        }

        var selected: [RecapPhoto] = []
        for candidate in rankedPhotos {
            guard selected.count < maxSelected else { break }
            if isDistinctEnough(candidate, from: selected, minTimeDistance: minTimeDistance, minSpatialDistance: minSpatialDistance) {
                selected.append(candidate)
            }
        }

        if selected.count < maxSelected {
            for candidate in rankedPhotos where !selected.contains(where: { $0.id == candidate.id }) {
                guard selected.count < maxSelected else { break }
                selected.append(candidate)
            }
        }

        return Set(selected.map(\.id))
    }

    private func isDistinctEnough(
        _ candidate: RecapPhoto,
        from selected: [RecapPhoto],
        minTimeDistance: TimeInterval,
        minSpatialDistance: CLLocationDistance
    ) -> Bool {
        let hardMinTimeDistance: TimeInterval = 10
        for existing in selected {
            let timeDelta = abs(candidate.timestamp.timeIntervalSince(existing.timestamp))
            // Hard cutoff: burst shots within 10 seconds are never both selected.
            if timeDelta < hardMinTimeDistance { return false }
            guard timeDelta < minTimeDistance else { continue }

            // If both locations exist, require spatial separation too.
            if let cLoc = candidate.location, let eLoc = existing.location {
                let c = CLLocation(latitude: cLoc.latitude, longitude: cLoc.longitude)
                let e = CLLocation(latitude: eLoc.latitude, longitude: eLoc.longitude)
                let distance = c.distance(from: e)
                if distance < minSpatialDistance { return false }
            } else {
                // When GPS is missing, time proximity alone is the best duplicate signal.
                return false
            }
        }
        return true
    }
}

// MARK: - AI rank badge helper

extension Array where Element == RecapPhoto {
    /// Maps photo id → rank (1, 2, 3) for the top-scoring photos. Only photos with a score get a badge.
    func aiRanksByPhotoId() -> [UUID: Int] {
        let scored = filter { $0.qualityScore != nil }
            .sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
        var ranks: [UUID: Int] = [:]
        for (index, photo) in scored.prefix(3).enumerated() {
            ranks[photo.id] = index + 1
        }
        return ranks
    }
}
