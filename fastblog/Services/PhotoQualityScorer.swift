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
    /// Penalty applied when faces are detected (keeps scenic/landscape preference). 0 or 0.05.
    let facePenalty: Double
    /// Weighted composite: aesthetics×0.6 + sharpness×0.4 − facePenalty.
    let totalScore: Double
}

// MARK: - Scorer

/// Scores a batch of photos using Vision framework. Runs as a Swift actor (thread-safe).
actor PhotoQualityScorer {
    static let shared = PhotoQualityScorer()

    // Score weights (mirror expo app)
    private let aestheticsWeight = 0.6
    private let sharpnessWeight  = 0.4
    private let facePenaltyValue = 0.05

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

        var results: [String: PhotoScore] = [:]
        await withTaskGroup(of: (String, PhotoScore?).self) { group in
            for asset in assets {
                group.addTask {
                    let score = await self.scoreAsset(asset)
                    return (asset.localIdentifier, score)
                }
            }
            for await (identifier, score) in group {
                if let score {
                    results[identifier] = score
                } else {
                    print("[PQS] scorePhotos: scoreAsset returned nil for \(identifier.prefix(8))…")
                }
            }
        }
        print("[PQS] scorePhotos: done scored=\(results.count)/\(assets.count)")
        return results
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

        async let aesthetics = analyzeAesthetics(cgImage)
        async let sharpness  = analyzeSharpness(cgImage)
        async let hasFaces   = detectFaces(cgImage)

        let a = await aesthetics
        let s = await sharpness
        let f = await hasFaces
        let penalty = f ? facePenaltyValue : 0.0
        let total   = max(0, a * aestheticsWeight + s * sharpnessWeight - penalty)

        return PhotoScore(aesthetics: a, sharpness: s, facePenalty: penalty, totalScore: total)
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

    // MARK: - Face detection

    /// Returns true when at least one face is detected (results in a small penalty).
    private func detectFaces(_ cgImage: CGImage) async -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        return (request.results?.count ?? 0) > 0
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

// MARK: - PlaceStop auto-selection helper

extension Array where Element == RecapPhoto {
    /// Returns the top-quality photo ids that should be included by default.
    /// 3 photos if total > 5, 2 if 3–5, 1 if 1–2. Users can add more via "Manage Photos".
    /// Adds duplicate control: avoid selecting photos that are too close in time/location.
    func autoSelectedIds() -> Set<UUID> {
        guard !isEmpty else { return [] }
        let count = self.count
        let maxSelected: Int = count > 5 ? 3 : (count >= 3 ? 2 : 1)

        let scored = filter { $0.qualityScore != nil }
        if scored.isEmpty {
            // No scores yet – fall through to original selection
            return Set(filter(\.isIncluded).map(\.id))
        }

        let rankedPhotos = sorted {
            ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0)
        }

        // Keep deterministic, but skip obvious near-duplicate burst shots.
        let minTimeDistance: TimeInterval = 90 // seconds
        let minSpatialDistance: CLLocationDistance = 35 // meters
        var selected: [RecapPhoto] = []

        for candidate in rankedPhotos {
            guard selected.count < maxSelected else { break }
            if isDistinctEnough(
                candidate,
                from: selected,
                minTimeDistance: minTimeDistance,
                minSpatialDistance: minSpatialDistance
            ) {
                selected.append(candidate)
            }
        }

        // Fallback to ensure we still fill the expected count in dense/same-spot sequences.
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
        for existing in selected {
            let timeDelta = abs(candidate.timestamp.timeIntervalSince(existing.timestamp))
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
