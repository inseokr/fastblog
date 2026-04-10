// fastblog/Services/BlogVideoExportService.swift
import AVFoundation
import SwiftUI
import UIKit

// MARK: - Options

struct BlogVideoExportOptions: Codable, Equatable {
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

    /// Builds a slideshow video from the same `StoryPage` array used by Story Mode.
    ///
    /// Pipeline:
    /// 1. Render each slide with `ImageRenderer` at 2× (same approach as storybook / PDF page rendering).
    /// 2. Write frames to a silent MP4 via `AVAssetWriter`.
    /// 3. If a music track is set, composite it into the video with `AVMutableComposition`.
    ///
    /// Progress is reported on the **main actor** via `progressHandler` in [0, 1].
    @MainActor
    static func exportVideo(
        pages: [StoryPage],
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard !pages.isEmpty else { throw ExportError.noPages }

        // Logical size matches the Story Mode slideshow viewport.
        let logicalSize = CGSize(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.effectiveStoryViewportHeight
        )
        // Pixel size: 2× logical (matching imageRenderer.scale = 2.0 below).
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)

        // Step 1 – Render all pages to UIImage (0 → 60 % of progress).
        var frames: [UIImage] = []
        frames.reserveCapacity(pages.count)
        for (idx, page) in pages.enumerated() {
            if idx % 2 == 0 { await Task.yield() }
            let image = try autoreleasepool {
                try renderPageToImage(page: page, logicalSize: logicalSize, pageIndex: idx, options: options)
            }
            frames.append(image)
            progressHandler?(Double(idx + 1) / Double(pages.count) * 0.6)
        }

        // Step 2 – Write silent video (60 → 80 %).
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try await writeVideoFrames(frames: frames, to: tempVideoURL, pixelSize: pixelSize, options: options)
        progressHandler?(0.8)

        // Step 3 – Composite audio if requested (80 → 100 %).
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

    // MARK: - Page rendering (mirrors storybook slide rendering in StoryModePDFExportService)

    @MainActor
    private static func renderPageToImage(
        page: StoryPage,
        logicalSize: CGSize,
        pageIndex: Int,
        options: BlogVideoExportOptions
    ) throws -> UIImage {
        let bgColor: Color    = options.colorStyle == .black ? .black : .white
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

    // MARK: - AVAssetWriter (video-only, silent)

    private static func writeVideoFrames(
        frames: [UIImage],
        to outputURL: URL,
        pixelSize: CGSize,
        options: BlogVideoExportOptions
    ) async throws {
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
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
        let slideTicks = CMTimeValue(options.secondsPerSlide * Double(timescale))

        for (idx, image) in frames.enumerated() {
            while !videoInput.isReadyForMoreMediaData { await Task.yield() }
            guard let pb = pixelBuffer(from: image, size: pixelSize) else {
                throw ExportError.failedToRenderPage(idx)
            }
            let pts = CMTime(value: CMTimeValue(idx) * slideTicks, timescale: timescale)
            adaptor.append(pb, withPresentationTime: pts)
        }

        videoInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    // MARK: - AVMutableComposition (add audio track)

    private static func compositeAudio(
        videoURL: URL,
        musicURL: URL,
        outputURL: URL
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)
        let composition = AVMutableComposition()

        // Add video track.
        guard
            let videoTrack  = try? await videoAsset.loadTracks(withMediaType: .video).first,
            let compVideo   = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.audioMixFailed }

        let videoDuration = try await videoAsset.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                      of: videoTrack, at: .zero)

        // Add music track, looping to fill the video duration.
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
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        await session.export()

        if session.status != .completed { throw ExportError.audioMixFailed }
    }

    // MARK: - UIImage → CVPixelBuffer

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
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
