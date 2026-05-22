// fastblog/Services/BlogVideoExportService.swift
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

// MARK: - Options

struct BlogVideoExportOptions: Codable, Equatable {
    enum ExportMode: String, Codable, Equatable {
        case video
        case carousel
    }

    /// Cinematic blog export (cover, maps, place chrome) vs. back-to-back reel stitch with day labels.
    enum VideoStyle: String, Codable, Equatable {
        case cinematic
        case simpleStitch
    }

    static let defaultMusicVolume: Float = 0.25

    enum CodingKeys: String, CodingKey {
        case secondsPerSlide, musicFilename, musicDisabled, musicVolume, showPhotoCaptions,
             maxPhotosPerPlace, includedPlaceIDs, includedReelPhotoIDs, includedPlaceCategoryRaws,
             showDayItineraryCards, exportMode, showMapFrames, videoStyle
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
    /// Moment-reel photo IDs to stitch. nil means all exportable reels (after place/category filters).
    var includedReelPhotoIDs: Set<UUID>? = nil
    /// Place categories to include (raw MapKit POI strings, plus optional `”Others”`). nil means all categories are included.
    var includedPlaceCategoryRaws: Set<String>? = nil
    /// Inject a 2-second itinerary card before each day's map sequence listing all places for that day.
    var showDayItineraryCards: Bool = false
    /// Whether to export a cinematic video or a set of carousel slide images.
    var exportMode: ExportMode = .video
    /// When true, map pan/zoom/overlay segments are included between photo slides.
    var showMapFrames: Bool = true
    /// Cinematic (default) or simple reel stitch with day title cards.
    var videoStyle: VideoStyle = .cinematic
    /// Background music level in the final mux (0…1). Ignored when `musicDisabled`.
    var musicVolume: Float = Self.defaultMusicVolume

    init(
        secondsPerSlide: Double = 3.0,
        musicFilename: String? = nil,
        musicDisabled: Bool = false,
        musicVolume: Float = Self.defaultMusicVolume,
        showPhotoCaptions: Bool = true,
        maxPhotosPerPlace: Int = 3,
        includedPlaceIDs: Set<UUID>? = nil,
        includedReelPhotoIDs: Set<UUID>? = nil,
        includedPlaceCategoryRaws: Set<String>? = nil,
        showDayItineraryCards: Bool = false,
        exportMode: ExportMode = .video,
        showMapFrames: Bool = true,
        videoStyle: VideoStyle = .cinematic
    ) {
        self.secondsPerSlide = secondsPerSlide
        self.musicFilename = musicFilename
        self.musicDisabled = musicDisabled
        self.musicVolume = min(1, max(0, musicVolume))
        self.showPhotoCaptions = showPhotoCaptions
        self.maxPhotosPerPlace = maxPhotosPerPlace
        self.includedPlaceIDs = includedPlaceIDs
        self.includedReelPhotoIDs = includedReelPhotoIDs
        self.includedPlaceCategoryRaws = includedPlaceCategoryRaws
        self.showDayItineraryCards = showDayItineraryCards
        self.exportMode = exportMode
        self.showMapFrames = showMapFrames
        self.videoStyle = videoStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        secondsPerSlide = try c.decodeIfPresent(Double.self, forKey: .secondsPerSlide) ?? 3.0
        musicFilename = try c.decodeIfPresent(String.self, forKey: .musicFilename)
        musicDisabled = try c.decodeIfPresent(Bool.self, forKey: .musicDisabled) ?? false
        showPhotoCaptions = try c.decodeIfPresent(Bool.self, forKey: .showPhotoCaptions) ?? true
        maxPhotosPerPlace = try c.decodeIfPresent(Int.self, forKey: .maxPhotosPerPlace) ?? 3
        includedPlaceIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .includedPlaceIDs)
        includedReelPhotoIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .includedReelPhotoIDs)
        includedPlaceCategoryRaws = try c.decodeIfPresent(Set<String>.self, forKey: .includedPlaceCategoryRaws)
        showDayItineraryCards = try c.decodeIfPresent(Bool.self, forKey: .showDayItineraryCards) ?? false
        exportMode = try c.decodeIfPresent(ExportMode.self, forKey: .exportMode) ?? .video
        showMapFrames = try c.decodeIfPresent(Bool.self, forKey: .showMapFrames) ?? true
        videoStyle = try c.decodeIfPresent(VideoStyle.self, forKey: .videoStyle) ?? .cinematic
        let decodedVolume = try c.decodeIfPresent(Float.self, forKey: .musicVolume) ?? Self.defaultMusicVolume
        musicVolume = min(1, max(0, decodedVolume))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(secondsPerSlide, forKey: .secondsPerSlide)
        try c.encodeIfPresent(musicFilename, forKey: .musicFilename)
        try c.encode(musicDisabled, forKey: .musicDisabled)
        try c.encode(musicVolume, forKey: .musicVolume)
        try c.encode(showPhotoCaptions, forKey: .showPhotoCaptions)
        try c.encode(maxPhotosPerPlace, forKey: .maxPhotosPerPlace)
        try c.encodeIfPresent(includedPlaceIDs, forKey: .includedPlaceIDs)
        try c.encodeIfPresent(includedReelPhotoIDs, forKey: .includedReelPhotoIDs)
        try c.encodeIfPresent(includedPlaceCategoryRaws, forKey: .includedPlaceCategoryRaws)
        try c.encode(showDayItineraryCards, forKey: .showDayItineraryCards)
        try c.encode(exportMode, forKey: .exportMode)
        try c.encode(showMapFrames, forKey: .showMapFrames)
        try c.encode(videoStyle, forKey: .videoStyle)
    }

    /// Filename passed to `SlideshowBundledMusicLibrary`, or `nil` when music is off.
    func resolvedMusicFilenameForMix() -> String? {
        if musicDisabled { return nil }
        return musicFilename ?? SlideshowMusicPreference.defaultFilename
    }

    /// Options as consumed by export after applying category pills (subset + `includedPlaceIDs` fold-in).
    func effectiveForExport(draft: RecapBlogDetail) -> BlogVideoExportOptions {
        var resolved = self
        if let cats = includedPlaceCategoryRaws {
            let allowedIDs = Set(
                draft.days.flatMap(\.placeStops).filter { stop in
                    let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = (raw == nil || raw?.isEmpty == true) ? "Others" : raw!
                    return cats.contains(key)
                }.map(\.id)
            )
            resolved.includedPlaceIDs = {
                if let ids = includedPlaceIDs {
                    let filtered = ids.intersection(allowedIDs)
                    return filtered.isEmpty ? [] : filtered
                }
                return allowedIDs
            }()
            let allowedReelPhotoIDs = CinematicBlogVideoBuilder.allExportableReelPhotoIDs(
                draft: draft,
                includedPlaceIDs: resolved.includedPlaceIDs
            )
            if let reelIDs = resolved.includedReelPhotoIDs {
                let pruned = reelIDs.intersection(allowedReelPhotoIDs)
                resolved.includedReelPhotoIDs = pruned.isEmpty ? [] : pruned
            }
        }
        if resolved.videoStyle == .simpleStitch {
            resolved.showMapFrames = false
            resolved.showDayItineraryCards = false
        }
        return resolved
    }
}

// MARK: - Moment reel audio

/// Where a moment-video reel’s original audio should sit on the exported timeline.
struct MomentVideoAudioSegment: Sendable {
    let url: URL
    /// Wall-clock start on the finished video (after any map→reel transition).
    let timelineStart: Double
    /// How long to play source audio (matches the reel body, not the transition).
    let duration: Double
}

// MARK: - Service

enum BlogVideoExportService {
    /// Final duplicate frame appended in `exportVideo` so the last sample has non-zero duration.
    private static let videoWriterEndPadSeconds: Double = 1.0 / 30.0

    /// Releases caches after export completes or fails (safe from export/mux background work).
    static func releaseExportWorkingSet() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                ImageLoader.shared.clearDecodedImageMemoryCache()
            }
        } else {
            DispatchQueue.main.sync {
                ImageLoader.shared.clearDecodedImageMemoryCache()
            }
        }
        URLCache.shared.removeAllCachedResponses()
    }

    /// Exported video timeline length assuming map/photo rendering succeeds as in `CinematicBlogVideoBuilder.buildFrames`
    /// (same travel mode selection as runtime; thumbnails / snapshots that fail shorten the actual file slightly).
    static func estimatedExportedVideoDurationSeconds(draft: RecapBlogDetail, options: BlogVideoExportOptions) -> Double {
        CinematicBlogVideoBuilder.estimatedTimelineSecondsForExportConfiguration(
            draft: draft,
            secondsPerPhoto: options.secondsPerSlide,
            maxPhotosPerPlace: options.maxPhotosPerPlace,
            includedPlaceIDs: options.includedPlaceIDs,
            includedReelPhotoIDs: options.includedReelPhotoIDs,
            showDayItineraryCards: options.showDayItineraryCards,
            showMapFrames: options.showMapFrames,
            videoStyle: options.videoStyle,
            reelsOnly: true
        ) + videoWriterEndPadSeconds
    }

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
        /// @2× logical canvas — matches cinematic export and 9:16 social targets.
        static var exportPixelSize: CGSize {
            CGSize(width: logicalWidth * 2, height: logicalHeight * 2)
        }
    }

    enum ExportError: Error, LocalizedError {
        case noPages
        case noReelsToExport
        case failedToRenderPage(Int)
        case writerSetupFailed
        case writerFailed(String)
        case audioMixFailed

        var errorDescription: String? {
            switch self {
            case .noPages:                   return "Nothing to export."
            case .noReelsToExport:
                return "This blog has no moment reels to stitch. Capture short reels with the in-app camera, then try again."
            case .failedToRenderPage(let i): return "Could not render page \(i + 1)."
            case .writerSetupFailed:         return "Could not set up video writer."
            case .writerFailed(let msg):     return "Video export failed: \(msg)"
            case .audioMixFailed:            return "Could not add music to video."
            }
        }
    }

    /// Moment reels available for the given export filters (place + category selection).
    static func exportableReelCount(draft: RecapBlogDetail, options: BlogVideoExportOptions) -> Int {
        let effective = options.effectiveForExport(draft: draft)
        return CinematicBlogVideoBuilder.exportableReelCount(
            draft: draft,
            includedPlaceIDs: effective.includedPlaceIDs,
            includedReelPhotoIDs: effective.includedReelPhotoIDs
        )
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
        defer { releaseExportWorkingSet() }

        let effective = options.effectiveForExport(draft: draft)
        guard CinematicBlogVideoBuilder.exportableReelCount(
            draft: draft,
            includedPlaceIDs: effective.includedPlaceIDs,
            includedReelPhotoIDs: effective.includedReelPhotoIDs
        ) > 0 else {
            throw ExportError.noReelsToExport
        }

        if effective.videoStyle == .simpleStitch {
            return try await exportSimpleStitchVideo(
                draft: draft,
                options: effective,
                progressHandler: progressHandler
            )
        }

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

        var removeTempVideoOnExit = true
        defer {
            if removeTempVideoOnExit {
                try? FileManager.default.removeItem(at: tempVideoURL)
            }
            if writer.status == .writing {
                writer.cancelWriting()
            }
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
        var videoTimelineSeconds: Double = 0
        var momentAudioSegments = [MomentVideoAudioSegment]()
        momentAudioSegments.reserveCapacity(32)

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
            for slice in 0..<sliceCount {
                while !videoInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    await Task.yield()
                }
                if slice > 0, slice % 90 == 0 {
                    await Task.yield()
                }
                let appended = autoreleasepool { () -> Bool in
                    guard let pb = pixelBuffer(from: image, size: pixelSize) else { return false }
                    return adaptor.append(pb, withPresentationTime: currentPTS)
                }
                guard appended else { throw ExportError.failedToRenderPage(frameIdx) }
                let delta = CMTime(
                    value: CMTimeValue((sliceDuration * Double(timescale)).rounded()),
                    timescale: timescale
                )
                currentPTS = CMTimeAdd(currentPTS, delta)
                frameIdx += 1
            }
            lastImageWritten = image
            videoTimelineSeconds += duration
        }

        // Step 1 – Generate + write frames one at a time (0 → 85 %).
        try await CinematicBlogVideoBuilder.buildFrames(
            from: draft,
            logicalSize: logicalSize,
            secondsPerPhoto: options.secondsPerSlide,
            showPhotoCaptions: options.showPhotoCaptions,
            maxPhotosPerPlace: options.maxPhotosPerPlace,
            includedPlaceIDs: options.includedPlaceIDs,
            includedReelPhotoIDs: options.includedReelPhotoIDs,
            showDayItineraryCards: options.showDayItineraryCards,
            showMapFrames: options.showMapFrames,
            videoStyle: options.videoStyle,
            reelsOnly: true,
            progressHandler: { p in progressHandler?(p * 0.85) },
            momentAudioHandler: { url, transitionSeconds, clipSeconds in
                momentAudioSegments.append(
                    MomentVideoAudioSegment(
                        url: url,
                        timelineStart: videoTimelineSeconds + transitionSeconds,
                        duration: clipSeconds
                    )
                )
            },
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
        lastImageWritten = nil
        releaseExportWorkingSet()

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

        let musicURL: URL? = {
            guard let filename = options.resolvedMusicFilenameForMix(),
                  let track = SlideshowBundledMusicLibrary.tracksInAppBundle().first(where: { $0.filename == filename })
            else { return nil }
            return track.fileURL
        }()

        if musicURL != nil || !momentAudioSegments.isEmpty {
            do {
                try await muxAudioOntoVideo(
                    videoURL: tempVideoURL,
                    musicURL: musicURL,
                    momentSegments: momentAudioSegments,
                    musicVolume: options.musicVolume,
                    outputURL: finalURL,
                    progressHandler: { muxProgress in
                        progressHandler?(0.85 + muxProgress * 0.14)
                    }
                )
            } catch {
                // Prefer a silent video over failing the whole export if audio mux fails.
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
            }
            removeTempVideoOnExit = false
            try? FileManager.default.removeItem(at: tempVideoURL)
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
            removeTempVideoOnExit = false
        }

        momentAudioSegments.removeAll(keepingCapacity: false)
        progressHandler?(1.0)
        return finalURL
    }

    // MARK: - Simple stitch (frame export with place / time overlay)

    /// Stitches moment reels at 9:16 with the same top-center place + timestamp chrome as cinematic reels.
    @MainActor
    private static func exportSimpleStitchVideo(
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        defer { releaseExportWorkingSet() }

        let logicalSize = SocialVerticalVideoExportMetrics.logicalSize
        let pixelSize = SocialVerticalVideoExportMetrics.exportPixelSize

        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        guard let writer = try? AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

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

        var removeTempVideoOnExit = true
        defer {
            if removeTempVideoOnExit {
                try? FileManager.default.removeItem(at: tempVideoURL)
            }
            if writer.status == .writing {
                writer.cancelWriting()
            }
        }

        let timescale: CMTimeScale = 600
        let staticSegmentTimelineFPS: Double = 30
        var currentPTS = CMTime.zero
        var frameIdx = 0
        var lastImageWritten: UIImage?
        var videoTimelineSeconds: Double = 0
        var momentAudioSegments = [MomentVideoAudioSegment]()
        momentAudioSegments.reserveCapacity(32)

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
            for slice in 0..<sliceCount {
                while !videoInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    await Task.yield()
                }
                if slice > 0, slice % 90 == 0 {
                    await Task.yield()
                }
                let appended = autoreleasepool { () -> Bool in
                    guard let pb = pixelBuffer(from: image, size: pixelSize) else { return false }
                    return adaptor.append(pb, withPresentationTime: currentPTS)
                }
                guard appended else { throw ExportError.failedToRenderPage(frameIdx) }
                let delta = CMTime(
                    value: CMTimeValue((sliceDuration * Double(timescale)).rounded()),
                    timescale: timescale
                )
                currentPTS = CMTimeAdd(currentPTS, delta)
                frameIdx += 1
            }
            lastImageWritten = image
            videoTimelineSeconds += duration
        }

        try await CinematicBlogVideoBuilder.buildFrames(
            from: draft,
            logicalSize: logicalSize,
            secondsPerPhoto: options.secondsPerSlide,
            showPhotoCaptions: false,
            maxPhotosPerPlace: options.maxPhotosPerPlace,
            includedPlaceIDs: options.includedPlaceIDs,
            includedReelPhotoIDs: options.includedReelPhotoIDs,
            showDayItineraryCards: false,
            showMapFrames: false,
            videoStyle: .simpleStitch,
            reelsOnly: true,
            progressHandler: { p in progressHandler?(p * 0.85) },
            momentAudioHandler: { url, transitionSeconds, clipSeconds in
                momentAudioSegments.append(
                    MomentVideoAudioSegment(
                        url: url,
                        timelineStart: videoTimelineSeconds + transitionSeconds,
                        duration: clipSeconds
                    )
                )
            },
            frameHandler: { img, dur in try await appendFrame(img, duration: dur) }
        )

        if frameIdx == 0 {
            try Task.checkCancellation()
            throw ExportError.noReelsToExport
        }

        let endPadSeconds = 1.0 / 30.0
        if let padImage = lastImageWritten {
            try await appendFrame(padImage, duration: endPadSeconds)
        }
        lastImageWritten = nil
        releaseExportWorkingSet()

        videoInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        progressHandler?(0.85)
        try Task.checkCancellation()

        let safeTitle = draft.title.replacingOccurrences(of: "/", with: "-")
        let finalURL = URL.documentsDirectory
            .appendingPathComponent("\(safeTitle) | Blog Video.mp4")
        try? FileManager.default.removeItem(at: finalURL)

        let musicURL: URL? = {
            guard let filename = options.resolvedMusicFilenameForMix(),
                  let track = SlideshowBundledMusicLibrary.tracksInAppBundle().first(where: { $0.filename == filename })
            else { return nil }
            return track.fileURL
        }()

        if musicURL != nil || !momentAudioSegments.isEmpty {
            do {
                try await muxAudioOntoVideo(
                    videoURL: tempVideoURL,
                    musicURL: musicURL,
                    momentSegments: momentAudioSegments,
                    musicVolume: options.musicVolume,
                    outputURL: finalURL,
                    progressHandler: { muxProgress in
                        progressHandler?(0.85 + muxProgress * 0.14)
                    }
                )
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
            }
            removeTempVideoOnExit = false
            try? FileManager.default.removeItem(at: tempVideoURL)
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
            removeTempVideoOnExit = false
        }

        momentAudioSegments.removeAll(keepingCapacity: false)
        progressHandler?(1.0)
        return finalURL
    }

    /// One stitched reel segment on the composition timeline (for per-clip portrait transforms).
    private struct StitchedClipSegment {
        let start: CMTime
        let duration: CMTime
        let layerTransform: CGAffineTransform
    }

    /// Aspect-fills source video into a fixed 9:16 canvas, honoring `preferredTransform`.
    private static func layerTransformFillingVerticalCanvas(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        var displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayW = abs(displayRect.width)
        let displayH = abs(displayRect.height)
        guard displayW > 0, displayH > 0 else { return preferredTransform }

        let scale = max(renderSize.width / displayW, renderSize.height / displayH)
        var transform = preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let dx = (renderSize.width - abs(displayRect.width)) / 2 - displayRect.minX
        let dy = (renderSize.height - abs(displayRect.height)) / 2 - displayRect.minY
        return transform.concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private static func makePortraitFillVideoComposition(
        renderSize: CGSize,
        compositionTrack: AVCompositionTrack,
        segments: [StitchedClipSegment],
        timelineDuration: CMTime
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        var instructions = [AVMutableVideoCompositionInstruction]()
        instructions.reserveCapacity(segments.count)

        for segment in segments {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: segment.start, duration: segment.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(segment.layerTransform, at: segment.start)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
        }

        if instructions.isEmpty {
            let fallback = AVMutableVideoCompositionInstruction()
            fallback.timeRange = CMTimeRange(start: .zero, duration: timelineDuration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(.identity, at: .zero)
            fallback.layerInstructions = [layer]
            instructions = [fallback]
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    /// Inserts each clip’s video (and clip audio when present) back-to-back, then exports once.
    private static func composeMomentClipsIntoVideo(
        clipURLs: [URL],
        outputURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.writerSetupFailed }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let renderSize = SocialVerticalVideoExportMetrics.exportPixelSize
        var cursor = CMTime.zero
        var segments = [StitchedClipSegment]()
        segments.reserveCapacity(clipURLs.count)
        let clipCount = clipURLs.count

        for (index, url) in clipURLs.enumerated() {
            try Task.checkCancellation()
            let asset = AVURLAsset(
                url: url,
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
            )
            _ = try await asset.load(.isReadable)
            let duration = try await asset.load(.duration)
            guard CMTimeCompare(duration, .zero) > 0 else { continue }

            let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
            if let sourceVideo = sourceVideoTracks.first {
                let segmentStart = cursor
                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceVideo,
                    at: cursor
                )
                let naturalSize = try await sourceVideo.load(.naturalSize)
                let preferredTransform = try await sourceVideo.load(.preferredTransform)
                let layerTransform = layerTransformFillingVerticalCanvas(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    renderSize: renderSize
                )
                segments.append(
                    StitchedClipSegment(
                        start: segmentStart,
                        duration: duration,
                        layerTransform: layerTransform
                    )
                )
            }

            if let compositionAudioTrack {
                let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let sourceAudio = sourceAudioTracks.first {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: sourceAudio,
                        at: cursor
                    )
                }
            }

            cursor = CMTimeAdd(cursor, duration)
            progressHandler?(Double(index + 1) / Double(clipCount))
            if index % 4 == 3 { await Task.yield() }
        }

        guard CMTimeCompare(cursor, .zero) > 0 else { throw ExportError.noReelsToExport }

        let videoComposition = makePortraitFillVideoComposition(
            renderSize: renderSize,
            compositionTrack: compositionVideoTrack,
            segments: segments,
            timelineDuration: cursor
        )

        try await runAssetExportSession(
            asset: composition,
            outputURL: outputURL,
            fileType: .mp4,
            presetName: AVAssetExportPresetHighestQuality,
            videoComposition: videoComposition
        )
    }

    private static func runAssetExportSession(
        asset: AVAsset,
        outputURL: URL,
        fileType: AVFileType,
        presetName: String,
        timeRange: CMTimeRange? = nil,
        audioMix: AVAudioMix? = nil,
        videoComposition: AVVideoComposition? = nil
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ExportError.writerFailed("Could not create export session.")
        }
        session.outputURL = outputURL
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        if let timeRange { session.timeRange = timeRange }
        session.audioMix = audioMix
        session.videoComposition = videoComposition
        try Task.checkCancellation()

        let sessionBox = ExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: sessionBox.session.error ?? ExportError.writerFailed("Export failed."))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: ExportError.writerFailed("Export did not finish."))
                }
            }
        }
        try Task.checkCancellation()
    }

    // MARK: - AVMutableComposition (audio tracks)

    private static let audioTimescale: CMTimeScale = 600

    /// Muxes background music and/or moment-reel clip audio onto the silent video-only export.
    private static func muxAudioOntoVideo(
        videoURL: URL,
        musicURL: URL?,
        momentSegments: [MomentVideoAudioSegment],
        musicVolume: Float,
        outputURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        let resolvedMusicVolume = min(1, max(0, musicVolume))
        defer { releaseExportWorkingSet() }

        let videoAsset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first,
              let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else { throw ExportError.audioMixFailed }

        let videoDuration = try await videoAsset.load(.duration)
        let videoSeconds = CMTimeGetSeconds(videoDuration)
        try compVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )

        var compMusicTrack: AVMutableCompositionTrack?
        if let musicURL {
            let musicAsset = AVURLAsset(
                url: musicURL,
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
            )
            _ = try await musicAsset.load(.isReadable)
            let musicTrackList = try await musicAsset.loadTracks(withMediaType: .audio)
            if let musicTrack = musicTrackList.first,
               let compMusic = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let musicTimeRange = try await musicTrack.load(.timeRange)
                let sourceStart = musicTimeRange.start
                let musicDuration = musicTimeRange.duration
                if CMTimeCompare(musicDuration, .zero) > 0 {
                    var insertAt = CMTime.zero
                    while CMTimeCompare(insertAt, videoDuration) < 0 {
                        let remaining = CMTimeSubtract(videoDuration, insertAt)
                        let chunk = CMTimeMinimum(musicDuration, remaining)
                        if CMTimeCompare(chunk, .zero) <= 0 { break }
                        try compMusic.insertTimeRange(
                            CMTimeRange(start: sourceStart, duration: chunk),
                            of: musicTrack,
                            at: insertAt
                        )
                        insertAt = CMTimeAdd(insertAt, chunk)
                    }
                    compMusicTrack = compMusic
                }
            }
        }

        var insertedClipCount = 0
        let sortedSegments = momentSegments.sorted { $0.timelineStart < $1.timelineStart }
        let compMomentClips = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let segmentCount = sortedSegments.count

        for (segmentIndex, segment) in sortedSegments.enumerated() {
            defer {
                if segmentCount > 0 {
                    progressHandler?(Double(segmentIndex + 1) / Double(segmentCount))
                }
            }

            guard segment.timelineStart.isFinite,
                  segment.duration.isFinite,
                  segment.timelineStart >= 0,
                  segment.duration > 0.02,
                  let compMomentClips else { continue }

            let clipAsset = AVURLAsset(url: segment.url)
            let clipAudioTracks = try await clipAsset.loadTracks(withMediaType: .audio)
            guard let clipAudio = clipAudioTracks.first else { continue }

            let assetDuration = try await clipAsset.load(.duration)
            let assetSec = CMTimeGetSeconds(assetDuration)
            var useSec = min(
                segment.duration,
                assetSec.isFinite && assetSec > 0 ? assetSec : segment.duration
            )
            if videoSeconds.isFinite, videoSeconds > 0 {
                let remaining = videoSeconds - segment.timelineStart
                if remaining > 0.02 {
                    useSec = min(useSec, remaining)
                } else {
                    continue
                }
            }
            guard useSec > 0.02 else { continue }

            let insertAt = CMTime(seconds: segment.timelineStart, preferredTimescale: audioTimescale)
            let insertDuration = CMTime(seconds: useSec, preferredTimescale: audioTimescale)
            guard insertAt.isValid, !insertAt.isIndefinite,
                  insertDuration.isValid, !insertDuration.isIndefinite,
                  CMTimeCompare(insertDuration, .zero) > 0 else { continue }

            do {
                try compMomentClips.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertDuration),
                    of: clipAudio,
                    at: insertAt
                )
                insertedClipCount += 1
            } catch {
                continue
            }

            if segmentIndex % 6 == 5 {
                await Task.yield()
            }
        }

        guard !composition.tracks(withMediaType: .audio).isEmpty else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }

        var audioMix: AVMutableAudioMix?
        if let compMusic = compMusicTrack {
            let musicParams = AVMutableAudioMixInputParameters(track: compMusic)
            musicParams.setVolume(resolvedMusicVolume, at: .zero)
            audioMix = AVMutableAudioMix()
            audioMix?.inputParameters = [musicParams]
        }

        try await runAssetExportSession(
            asset: composition,
            outputURL: outputURL,
            fileType: .mp4,
            presetName: AVAssetExportPresetHighestQuality,
            timeRange: CMTimeRange(start: .zero, duration: videoDuration),
            audioMix: audioMix
        )
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
