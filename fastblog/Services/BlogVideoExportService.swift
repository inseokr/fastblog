// fastblog/Services/BlogVideoExportService.swift
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

// MARK: - Options

struct BlogVideoExportOptions: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case secondsPerSlide, musicFilename, musicDisabled, showPhotoCaptions, maxPhotosPerPlace,
             includedPlaceIDs, includedPlaceCategoryRaws
    }

    var secondsPerSlide: Double = 3.0
    /// Bundled track filename, or `nil` meaning “use app default” (`SlideshowMusicPreference.defaultFilename`).
    var musicFilename: String? = nil
    /// When true, export has no background music (user chose “None”). Ignores `musicFilename`.
    var musicDisabled: Bool = false
    /// Whether photo captions are shown as text overlays on photo slides.
    var showPhotoCaptions: Bool = true
    /// Maximum number of photos shown per place stop. Capped at this count from includedPhotos.
    var maxPhotosPerPlace: Int = 3
    /// Place stop IDs to include. nil means all places are included.
    var includedPlaceIDs: Set<UUID>? = nil
    /// Place categories to include (raw MapKit POI strings, plus optional `"Others"`). nil means all categories are included.
    var includedPlaceCategoryRaws: Set<String>? = nil

    init(
        secondsPerSlide: Double = 3.0,
        musicFilename: String? = nil,
        musicDisabled: Bool = false,
        showPhotoCaptions: Bool = true,
        maxPhotosPerPlace: Int = 3,
        includedPlaceIDs: Set<UUID>? = nil,
        includedPlaceCategoryRaws: Set<String>? = nil
    ) {
        self.secondsPerSlide = secondsPerSlide
        self.musicFilename = musicFilename
        self.musicDisabled = musicDisabled
        self.showPhotoCaptions = showPhotoCaptions
        self.maxPhotosPerPlace = maxPhotosPerPlace
        self.includedPlaceIDs = includedPlaceIDs
        self.includedPlaceCategoryRaws = includedPlaceCategoryRaws
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        secondsPerSlide = try c.decodeIfPresent(Double.self, forKey: .secondsPerSlide) ?? 3.0
        musicFilename = try c.decodeIfPresent(String.self, forKey: .musicFilename)
        musicDisabled = try c.decodeIfPresent(Bool.self, forKey: .musicDisabled) ?? false
        showPhotoCaptions = try c.decodeIfPresent(Bool.self, forKey: .showPhotoCaptions) ?? true
        maxPhotosPerPlace = try c.decodeIfPresent(Int.self, forKey: .maxPhotosPerPlace) ?? 3
        includedPlaceIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .includedPlaceIDs)
        includedPlaceCategoryRaws = try c.decodeIfPresent(Set<String>.self, forKey: .includedPlaceCategoryRaws)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(secondsPerSlide, forKey: .secondsPerSlide)
        try c.encodeIfPresent(musicFilename, forKey: .musicFilename)
        try c.encode(musicDisabled, forKey: .musicDisabled)
        try c.encode(showPhotoCaptions, forKey: .showPhotoCaptions)
        try c.encode(maxPhotosPerPlace, forKey: .maxPhotosPerPlace)
        try c.encodeIfPresent(includedPlaceIDs, forKey: .includedPlaceIDs)
        try c.encodeIfPresent(includedPlaceCategoryRaws, forKey: .includedPlaceCategoryRaws)
    }

    /// Filename passed to `SlideshowBundledMusicLibrary`, or `nil` when music is off.
    func resolvedMusicFilenameForMix() -> String? {
        if musicDisabled { return nil }
        return musicFilename ?? SlideshowMusicPreference.defaultFilename
    }
}

// MARK: - Service

enum BlogVideoExportService {
    /// Small box used to move `AVAssetExportSession` through `@Sendable` closures safely.
    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(session: AVAssetExportSession) {
            self.session = session
        }
    }

    /// Short-form vertical video must match **9:16** pixel aspect. Using `UIScreen` width ×
    /// safe-area-clamped height skews taller than 9:16 → pillarboxing in some players and
    /// Instagram filling the frame with a center crop (“zoomed”). Export uses a fixed canvas
    /// at **1080×1920** (@2× from 540×960 logical) regardless of device or orientation.
    private enum SocialVerticalVideoExportMetrics {
        static let logicalWidth: CGFloat = 540
        static let logicalHeight: CGFloat = 960
        static var logicalSize: CGSize { CGSize(width: logicalWidth, height: logicalHeight) }
    }

    enum ExportError: Error, LocalizedError {
        case noPages
        case failedToRenderPage(Int)
        case writerSetupFailed
        case writerFailed(String)
        case audioMixFailed

        var errorDescription: String? {
            switch self {
            case .noPages:                   return "Nothing to export."
            case .failedToRenderPage(let i): return "Could not render page \(i + 1)."
            case .writerSetupFailed:         return "Could not set up video writer."
            case .writerFailed(let msg):     return "Video export failed: \(msg)"
            case .audioMixFailed:            return "Could not add music to video."
            }
        }
    }

    /// Exports the blog as a video by **streaming** frames directly into `AVAssetWriter`.
    ///
    /// Peak memory = one rendered frame at a time.  The old approach buffered the entire
    /// frame list (~700 MB+ for a multi-day trip) before writing a single byte, which
    /// caused OOM crashes.  Now the writer is opened first and each frame is encoded and
    /// released before the next is generated.
    @MainActor
    static func exportVideo(
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {

        let logicalSize = SocialVerticalVideoExportMetrics.logicalSize
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)

        // Open the writer before generating any frames.
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        guard let writer = try? AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        // TikTok and some other transcoders mishandle very long per-sample durations (one frame
        // held for 2–3s). Instagram tends to cope; splitting static holds into ~30fps slices keeps
        // timestamps closer to what short-form pipelines expect and improves cover-frame extraction.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ] as [String: Any]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(pixelSize.width),
                kCVPixelBufferHeightKey as String: Int(pixelSize.height)
            ]
        )
        guard writer.canAdd(videoInput) else { throw ExportError.writerSetupFailed }
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        defer {
            ImageLoader.shared.clearDecodedImageMemoryCache()
            if writer.status == .writing {
                writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: tempVideoURL)
        }

        let timescale: CMTimeScale = 600
        /// Slice long static segments at this rate so downstream transcoders see ~CFR timing.
        let staticSegmentTimelineFPS: Double = 30
        var currentPTS  = CMTime.zero
        var frameIdx    = 0
        /// With `appendPixelBuffer(..., presentationTime:)`, each frame’s visible length is the **delta to the next PTS**.
        /// The final sample has no successor, so decoders often treat its duration as ~0 — the last photo (or page) flashes away.
        /// We append one extra duplicate at the end so the real last frame keeps its intended duration.
        var lastImageWritten: UIImage?

        // Encode one logical "hold" as one or more samples so very long display durations are not
        // a single frame (problematic for some social transcoders / cover extraction).
        func appendFrame(_ image: UIImage, duration: Double) async throws {
            let minSlice = 1.0 / staticSegmentTimelineFPS
            let sliceCount: Int
            let sliceDuration: Double
            if duration <= minSlice * 1.000_001 {
                sliceCount = 1
                sliceDuration = duration
            } else {
                sliceCount = max(1, Int((duration * staticSegmentTimelineFPS).rounded()))
                sliceDuration = duration / Double(sliceCount)
            }
            for _ in 0..<sliceCount {
                while !videoInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    await Task.yield()
                }
                let pb = autoreleasepool { BlogVideoExportService.pixelBuffer(from: image, size: pixelSize) }
                guard let pb else { throw ExportError.failedToRenderPage(frameIdx) }
                adaptor.append(pb, withPresentationTime: currentPTS)
                let delta = CMTime(
                    value: CMTimeValue((sliceDuration * Double(timescale)).rounded()),
                    timescale: timescale
                )
                currentPTS = CMTimeAdd(currentPTS, delta)
                frameIdx += 1
            }
            lastImageWritten = image
        }

        // Step 1 – Generate + write frames one at a time (0 → 85 %).
        try await CinematicBlogVideoBuilder.buildFrames(
            from: draft,
            logicalSize: logicalSize,
            secondsPerPhoto: options.secondsPerSlide,
            showPhotoCaptions: options.showPhotoCaptions,
            maxPhotosPerPlace: options.maxPhotosPerPlace,
            includedPlaceIDs: options.includedPlaceIDs,
            progressHandler: { p in progressHandler?(p * 0.85) },
            frameHandler: { img, dur in try await appendFrame(img, duration: dur) }
        )

        if frameIdx == 0 {
            try Task.checkCancellation()
            throw ExportError.noPages
        }

        // One-tick successor PTS so the last content frame isn’t encoded with ~0 display duration (see `lastImageWritten`).
        let endPadSeconds = 1.0 / 30.0
        if let padImage = lastImageWritten {
            try await appendFrame(padImage, duration: endPadSeconds)
        }

        videoInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        progressHandler?(0.85)
        try Task.checkCancellation()

        // Step 2 – Composite audio (85 → 100 %).
        let safeTitle = draft.title.replacingOccurrences(of: "/", with: "-")
        let finalURL = URL.documentsDirectory
            .appendingPathComponent("\(safeTitle) | Blog Video.mp4")
        try? FileManager.default.removeItem(at: finalURL)

        if let filename = options.resolvedMusicFilenameForMix(),
           let track = SlideshowBundledMusicLibrary.tracksInAppBundle().first(where: { $0.filename == filename }) {
            try await compositeAudio(videoURL: tempVideoURL, musicURL: track.fileURL, outputURL: finalURL)
            try? FileManager.default.removeItem(at: tempVideoURL)
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
        }

        progressHandler?(1.0)
        return finalURL
    }

    // MARK: - AVMutableComposition (audio track)

    private static func compositeAudio(videoURL: URL, musicURL: URL, outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(
            url: musicURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let composition = AVMutableComposition()

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first,
              let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.audioMixFailed }

        let videoDuration = try await videoAsset.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                      of: videoTrack, at: .zero)

        _ = try await musicAsset.load(.isReadable)
        let musicTrackList = try await musicAsset.loadTracks(withMediaType: .audio)
        guard let musicTrack = musicTrackList.first,
              let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.audioMixFailed }

        let musicTimeRange = try await musicTrack.load(.timeRange)
        let sourceStart = musicTimeRange.start
        let musicDuration = musicTimeRange.duration
        guard CMTimeCompare(musicDuration, .zero) > 0 else { throw ExportError.audioMixFailed }

        var insertAt = CMTime.zero
        while CMTimeCompare(insertAt, videoDuration) < 0 {
            let remaining = CMTimeSubtract(videoDuration, insertAt)
            let chunk = CMTimeMinimum(musicDuration, remaining)
            if CMTimeCompare(chunk, .zero) <= 0 { break }
            try compAudio.insertTimeRange(CMTimeRange(start: sourceStart, duration: chunk),
                                          of: musicTrack, at: insertAt)
            insertAt = CMTimeAdd(insertAt, chunk)
        }

        guard !composition.tracks(withMediaType: .audio).isEmpty else {
            throw ExportError.audioMixFailed
        }

        guard let session = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.audioMixFailed }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        session.shouldOptimizeForNetworkUse = true
        try Task.checkCancellation()
        let sessionBox = ExportSessionBox(session: session)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: sessionBox.session.error ?? ExportError.audioMixFailed)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: ExportError.audioMixFailed)
                }
            }
        }
        try Task.checkCancellation()
    }

    // MARK: - UIImage → CVPixelBuffer

    fileprivate static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        guard let ctx, let cgImage = image.cgImage else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
