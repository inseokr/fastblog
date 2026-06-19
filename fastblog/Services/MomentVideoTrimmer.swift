//
//  MomentVideoTrimmer.swift
//  fastblog
//
//  Loads moment-reel metadata, generates filmstrip frames, and exports trimmed clips.
//

import AVFoundation
import UIKit

enum MomentVideoTrimmer {
    static let minimumClipDuration: TimeInterval = 1.0
    static let nudgeStep: TimeInterval = 0.25
    private static let timescale: CMTimeScale = 600

    static func loadDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0.05 else { return nil }
        return seconds
    }

    static func generateFilmstrip(from url: URL, frameCount: Int = 12) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = duration.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: timescale)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: timescale)

        let count = max(frameCount, 1)
        var images: [UIImage] = []
        images.reserveCapacity(count)

        for index in 0..<count {
            let fraction = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let time = CMTime(seconds: totalSeconds * fraction, preferredTimescale: timescale)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            images.append(UIImage(cgImage: cgImage))
        }
        return images
    }

    static func thumbnail(at seconds: TimeInterval, in url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: timescale)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: timescale)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Exports `[startSeconds, endSeconds)` from `sourceURL`. Returns the original URL when the
    /// requested range covers the full clip (within a small tolerance).
    static func exportTrimmed(
        from sourceURL: URL,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) async -> URL? {
        let clipDuration = endSeconds - startSeconds
        guard clipDuration >= minimumClipDuration - 0.01 else { return nil }

        let totalDuration = await loadDuration(of: sourceURL) ?? clipDuration
        if startSeconds <= 0.05, abs(endSeconds - totalDuration) <= 0.05 {
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        let start = CMTime(seconds: startSeconds, preferredTimescale: timescale)
        let range = CMTimeRange(
            start: start,
            duration: CMTime(seconds: clipDuration, preferredTimescale: timescale)
        )

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moment_trimmed_\(UUID().uuidString).mov")

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        export.outputURL = outURL
        export.outputFileType = .mov
        export.timeRange = range

        await withCheckedContinuation { continuation in
            export.exportAsynchronously {
                continuation.resume()
            }
        }

        if export.status == .completed {
            return outURL
        }
        try? FileManager.default.removeItem(at: outURL)
        return nil
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}
