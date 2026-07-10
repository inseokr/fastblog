import Foundation
import Vision
import UIKit

/// Supports features ①·③: photo quality / aesthetics scoring.
/// - iOS 18+: VNCalculateImageAestheticsScoresRequest (same API already used in fastblog)
/// - Fallback/auxiliary: Laplacian variance sharpness (blur detection, Prof. Kim Stage 1)
enum AestheticScorer {

    /// Full pipeline: fill sharpness + aestheticScore for each photo and return
    static func score(_ photos: [PhotoItem]) async -> [PhotoItem] {
        var result: [PhotoItem] = []
        for var photo in photos {
            photo.sharpness = laplacianVariance(photo.image)
            photo.aestheticScore = await visionAesthetics(photo.image)
                ?? min(1.0, photo.sharpness / 400.0)   // fallback: sharpness-based approximation
            photo.hasSaliency = await hasSalientRegion(photo.image)
            result.append(photo)
        }
        return result
    }

    /// Vision Aesthetics (iOS 18+). Works in the simulator too. Returns nil on failure → fallback.
    private static func visionAesthetics(_ image: UIImage) async -> Double? {
        guard #available(iOS 18.0, *), let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNCalculateImageAestheticsScoresRequest()
                    let handler = VNImageRequestHandler(cgImage: cg)
                    try handler.perform([request])
                    let score = request.results?.first?.overallScore
                    continuation.resume(returning: score.map { (Double($0) + 1) / 2 })  // -1...1 → 0...1
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Stage 5: attention-based saliency — whether a clear subject exists (iOS 13+)
    private static func hasSalientRegion(_ image: UIImage) async -> Bool {
        guard let cg = image.cgImage else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNGenerateAttentionBasedSaliencyImageRequest()
                    let handler = VNImageRequestHandler(cgImage: cg)
                    try handler.perform([request])
                    let salient = (request.results?.first)
                        .flatMap { $0.salientObjects?.first }
                        .map { $0.confidence > 0.3 } ?? false
                    continuation.resume(returning: salient)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Stage 1: Laplacian variance blur detection — pure pixel math, OS-version independent.
    /// variance < 100 → blurry photo (Prof. Kim's threshold)
    static func laplacianVariance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let w = 64, h = 48   // downsample — speed first
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var values: [Double] = []
        values.reserveCapacity((w - 2) * (h - 2))
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(pixels[y * w + x])
                let lap = Double(pixels[(y - 1) * w + x]) + Double(pixels[(y + 1) * w + x])
                        + Double(pixels[y * w + x - 1]) + Double(pixels[y * w + x + 1]) - 4 * c
                values.append(lap)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}
