// fastblog/Services/BlogVideoExportService.swift
import AVFoundation
import SwiftUI
import UIKit

// MARK: - Video Style

enum VideoStyle: String, Codable, CaseIterable {
    case cinematic  = "cinematic"
    case storyPages = "storyPages"

    var label: String {
        switch self {
        case .cinematic:  return "Cinematic Journey"
        case .storyPages: return "Story Pages"
        }
    }

    var subtitle: String {
        switch self {
        case .cinematic:  return "Map animations + full-frame photos"
        case .storyPages: return "Full blog layout pages"
        }
    }
}

// MARK: - Options

struct BlogVideoExportOptions: Codable, Equatable {
    var videoStyle: VideoStyle = .cinematic
    var secondsPerSlide: Double = 3.0
    var colorStyle: BlogColor = .white
    var fontTheme: FontTheme = .classic
    /// Filename of the bundled music track to mix in, or nil for silence.
    var musicFilename: String? = nil
}

// MARK: - Service

enum BlogVideoExportService {

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
        pages: [StoryPage],
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {

        let logicalSize = CGSize(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.effectiveStoryViewportHeight
        )
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)

        // Open the writer before generating any frames.
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        guard let writer = try? AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000]
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

        let timescale: CMTimeScale = 600
        var currentPTS  = CMTime.zero
        var frameIdx    = 0

        // Encode one frame and release the image immediately after the pixel buffer is written.
        func appendFrame(_ image: UIImage, duration: Double) async throws {
            while !videoInput.isReadyForMoreMediaData { await Task.yield() }
            let pb = autoreleasepool { BlogVideoExportService.pixelBuffer(from: image, size: pixelSize) }
            guard let pb else { throw ExportError.failedToRenderPage(frameIdx) }
            adaptor.append(pb, withPresentationTime: currentPTS)
            currentPTS = CMTimeAdd(currentPTS, CMTime(value: CMTimeValue(duration * Double(timescale)), timescale: timescale))
            frameIdx += 1
        }

        // Step 1 – Generate + write frames one at a time (0 → 85 %).
        if options.videoStyle == .cinematic {
            try await CinematicBlogVideoBuilder.buildFrames(
                from: draft,
                logicalSize: logicalSize,
                secondsPerPhoto: options.secondsPerSlide,
                progressHandler: { p in progressHandler?(p * 0.85) },
                frameHandler: { img, dur in try await appendFrame(img, duration: dur) }
            )
        } else {
            guard !pages.isEmpty else { throw ExportError.noPages }
            for (idx, page) in pages.enumerated() {
                if idx % 2 == 0 { await Task.yield() }
                let image = try autoreleasepool {
                    try renderPageToImage(page: page, logicalSize: logicalSize, pageIndex: idx, options: options)
                }
                try await appendFrame(image, duration: options.secondsPerSlide)
                progressHandler?(Double(idx + 1) / Double(pages.count) * 0.85)
            }
        }

        guard frameIdx > 0 else { throw ExportError.noPages }

        videoInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        progressHandler?(0.85)

        // Step 2 – Composite audio (85 → 100 %).
        let safeTitle = draft.title.replacingOccurrences(of: "/", with: "-")
        let finalURL = URL.documentsDirectory
            .appendingPathComponent("\(safeTitle) | Blog Video.mp4")
        try? FileManager.default.removeItem(at: finalURL)

        if let filename = options.musicFilename,
           let track = SlideshowBundledMusicLibrary.tracksInAppBundle().first(where: { $0.filename == filename }) {
            try await compositeAudio(videoURL: tempVideoURL, musicURL: track.fileURL, outputURL: finalURL)
            try? FileManager.default.removeItem(at: tempVideoURL)
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: finalURL)
        }

        progressHandler?(1.0)
        return finalURL
    }

    // MARK: - Story-page rendering

    @MainActor
    private static func renderPageToImage(
        page: StoryPage,
        logicalSize: CGSize,
        pageIndex: Int,
        options: BlogVideoExportOptions
    ) throws -> UIImage {
        let bgColor: Color           = options.colorStyle == .black ? .black : .white
        let colorScheme: ColorScheme = options.colorStyle == .black ? .dark  : .light

        let root = StoryPageView(page: page)
            .environment(\.colorScheme, colorScheme)
            .environment(\.storyFontTheme, options.fontTheme)
            .environment(\.storyBlogColor, options.colorStyle)
            .environment(\.storyRasterizesForExport, true)
            .frame(width: logicalSize.width, height: logicalSize.height)
            .background(bgColor)

        let renderer = ImageRenderer(content: root)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: logicalSize.width, height: logicalSize.height)

        guard let image = renderer.uiImage else {
            throw ExportError.failedToRenderPage(pageIndex)
        }
        return image
    }

    // MARK: - AVMutableComposition (audio track)

    private static func compositeAudio(videoURL: URL, musicURL: URL, outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)
        let composition = AVMutableComposition()

        guard
            let videoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
            let compVideo  = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.audioMixFailed }

        let videoDuration = try await videoAsset.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                      of: videoTrack, at: .zero)

        if let musicTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first,
           let compAudio  = composition.addMutableTrack(withMediaType: .audio,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicDuration = try await musicAsset.load(.duration)
            var insertAt = CMTime.zero
            while insertAt < videoDuration {
                let remaining = CMTimeSubtract(videoDuration, insertAt)
                let chunk = CMTimeMinimum(musicDuration, remaining)
                try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: chunk),
                                              of: musicTrack, at: insertAt)
                insertAt = CMTimeAdd(insertAt, musicDuration)
            }
        }

        guard let session = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.audioMixFailed }
        session.outputURL  = outputURL
        session.outputFileType = .mp4
        session.timeRange  = CMTimeRange(start: .zero, duration: videoDuration)
        await session.export()
        if session.status != .completed { throw ExportError.audioMixFailed }
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
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
