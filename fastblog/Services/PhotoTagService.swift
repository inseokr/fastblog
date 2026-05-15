//
//  PhotoTagService.swift
//  fastblog
//
//  Extracts descriptive tags from photos using Vision VNClassifyImageRequest
//  for use in AI-generated captions and place stories.
//

import Foundation
import Photos
import Vision

/// Returns image classification labels (tags) from the Vision framework.
/// Labels are sorted by confidence; typical examples: "outdoor", "sky", "water", "building".
actor PhotoTagService {
    static let shared = PhotoTagService()

    private let analysisSize = CGSize(width: 400, height: 400)
    /// Minimum confidence (0–1) to include a tag. VNClassifyImageRequest returns many; we keep the strongest.
    private let minConfidence: Float = 0.1
    /// Max number of tags to return per image.
    private let maxTags = 12

    private init() {}

    /// Classify a photo by its Photos library local identifier.
    /// Returns an array of tag strings (e.g. "outdoor", "sky", "water") for use in story/caption generation.
    func tags(forLocalIdentifier localIdentifier: String) async -> [String] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return [] }
        guard let cgImage = await loadThumbnail(asset: asset) else { return [] }
        return await classify(cgImage: cgImage)
    }

    /// Classify an image from CGImage (e.g. when you already have the image in memory).
    func tags(for cgImage: CGImage) async -> [String] {
        await classify(cgImage: cgImage)
    }

    // MARK: - Private

    private func loadThumbnail(asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: analysisSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    private func classify(cgImage: CGImage) async -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let results = request.results else { return [] }
        return results
            .filter { $0.confidence >= minConfidence }
            .prefix(maxTags)
            .map { $0.identifier }
    }
}
