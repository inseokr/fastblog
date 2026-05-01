// fastblog/Services/BlogVideoExportService.swift
import AVFoundation
import SwiftUI
import UIKit

// MARK: - Options

struct BlogVideoExportOptions: Codable, Equatable {
    var secondsPerSlide: Double = 3.0
    /// Filename of the bundled music track to mix in, or nil for silence.
    var musicFilename: String? = nil
    /// When true, overlay each slide photo's capture time (24-hour) in the center.
    var includeTimestamps: Bool = true
    /// When true, prepend a per-day route map before each day's photos.
    var includeDailyMapIntro: Bool = true
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

    /// Builds a slideshow video from the same **photo** sequence as the recap slideshow (`PanoramaPlayerView`):
    /// one place per group, solo vs split diptych when a place has two or more photos (deterministic pattern
    /// so exports are stable; in-app playback randomizes that choice).
    ///
    /// Pipeline:
    /// 1. Load images and render each slide full-bleed on black at 2× with `ImageRenderer`.
    /// 2. Write frames to a silent MP4 via `AVAssetWriter`.
    /// 3. If a music track is set, composite it into the video with `AVMutableComposition`.
    ///
    /// Progress is reported on the **main actor** via `progressHandler` in [0, 1].
    @MainActor
    static func exportVideo(
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let dayGroups = slideshowDayGroups(from: draft)
        let specs = enumerateSlideshowSlides(dayGroups: dayGroups, includeDailyMapIntro: options.includeDailyMapIntro)
        guard !specs.isEmpty else { throw ExportError.noPages }

        let logicalSize = CGSize(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.clampedScreenHeight
        )
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
        let loadSize = CGSize(width: logicalSize.width * 3, height: logicalSize.height * 3)

        var idToPhoto: [String: RecapPhoto] = [:]
        for day in draft.days {
            for stop in day.placeStops {
                for p in stop.photos where p.isIncluded {
                    if let lid = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
                        idToPhoto[lid] = p
                    }
                }
            }
        }

        var loaded: [String: UIImage] = [:]
        let allIds = Set(specs.flatMap { spec -> [String] in
            guard case .photo(let photoSpec) = spec else { return [] }
            if let b = photoSpec.bottom { return [photoSpec.top.id, b.id] }
            return [photoSpec.top.id]
        })
        let idList = Array(allIds)
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for lid in idList {
                group.addTask {
                    guard let photo = idToPhoto[lid] else { return (lid, nil) }
                    let img = await StoryBookBuilder.loadUIImage(for: photo, targetPixelSize: loadSize)
                    return (lid, img)
                }
            }
            for await (lid, img) in group {
                if let img { loaded[lid] = img }
            }
        }
        let dayMapImages = await generateDayMapSlides(
            dayGroups: dayGroups,
            logicalSize: logicalSize,
            includeDailyMapIntro: options.includeDailyMapIntro
        )
        progressHandler?(0.08)

        var zoomIn = true
        var frames: [UIImage] = []
        frames.reserveCapacity(specs.count)
        for (idx, spec) in specs.enumerated() {
            if idx > 0,
               case .photo(let photoSpec) = spec,
               photoSpec.layout == .solo {
                zoomIn.toggle()
            }
            if idx % 2 == 0 { await Task.yield() }
            let image = try autoreleasepool {
                try renderSlideshowSpecToImage(
                    spec: spec,
                    loaded: loaded,
                    dayMapImages: dayMapImages,
                    logicalSize: logicalSize,
                    slideIndex: idx,
                    zoomIn: zoomIn,
                    options: options
                )
            }
            frames.append(image)
            progressHandler?(0.08 + Double(idx + 1) / Double(specs.count) * 0.52)
        }

        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try await writeVideoFrames(frames: frames, to: tempVideoURL, pixelSize: pixelSize, options: options)
        progressHandler?(0.8)

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

    // MARK: - Slideshow sequencing (matches `RecapBlogPageView` + `PanoramaPlayerView`)

    private struct DaySlideshowGroup {
        let dayID: UUID
        let dayNumber: Int
        let dayDateText: String
        let placeCount: Int
        let photoCount: Int
        let mapStops: [PlaceStop]
        let photoGroups: [[PanoramaPhotoEntry]]
    }

    private static func slideshowDayGroups(from draft: RecapBlogDetail) -> [DaySlideshowGroup] {
        let groups = draft.days.enumerated().compactMap { (dayIndex, day) -> DaySlideshowGroup? in
            let placeGroups: [[PanoramaPhotoEntry]] = day.placeStops.compactMap { stop -> [PanoramaPhotoEntry]? in
                let entries = stop.photos
                    .filter(\.isIncluded)
                    .compactMap { photo -> PanoramaPhotoEntry? in
                        guard let id = photo.localIdentifier, !id.isEmpty else { return nil }
                        return PanoramaPhotoEntry(
                            id: id,
                            caption: photo.caption,
                            placeName: stop.placeTitle,
                            timestamp: photo.timestamp
                        )
                    }
                return entries.isEmpty ? nil : entries
            }
            guard !placeGroups.isEmpty else { return nil }
            let placesWithIncludedPhotos = day.placeStops.filter { !$0.includedPhotos.isEmpty }
            return DaySlideshowGroup(
                dayID: day.id,
                dayNumber: dayIndex + 1,
                dayDateText: day.shortDateText,
                placeCount: placesWithIncludedPhotos.count,
                photoCount: placeGroups.reduce(0) { $0 + $1.count },
                mapStops: day.placeStops,
                photoGroups: placeGroups
            )
        }
        if !groups.isEmpty { return groups }
        if let cover = draft.selectedCoverPhotoIdentifier {
            return [
                DaySlideshowGroup(
                    dayID: UUID(),
                    dayNumber: 1,
                    dayDateText: "",
                    placeCount: 1,
                    photoCount: 1,
                    mapStops: [],
                    photoGroups: [[PanoramaPhotoEntry(id: cover, caption: nil, placeName: nil, timestamp: nil)]]
                )
            ]
        }
        return []
    }

    private enum ExportSlideLayout { case solo, diptych }

    private struct ExportPhotoSlideSpec {
        let layout: ExportSlideLayout
        let top: PanoramaPhotoEntry
        let bottom: PanoramaPhotoEntry?
    }

    private struct ExportDayMapSlideSpec {
        let dayID: UUID
        let dayNumber: Int
        let dayDateText: String
        let placeCount: Int
        let photoCount: Int
    }

    private enum ExportSlideSpec {
        case photo(ExportPhotoSlideSpec)
        case dayMap(ExportDayMapSlideSpec)
    }

    /// Deterministic stand-in for `PanoramaPlayerView.chooseLayout` (which uses random when ≥2 photos remain).
    private static func chooseDeterministicLayout(groupIndex: Int, offset: Int, remaining: Int) -> ExportSlideLayout {
        guard remaining >= 2 else { return .solo }
        return (groupIndex + offset) % 2 == 0 ? .solo : .diptych
    }

    private static func advanceAfterStep(
        groups: [[PanoramaPhotoEntry]],
        groupIndex: Int,
        offset: Int,
        step: Int
    ) -> (groupIndex: Int, offset: Int)? {
        let group = groups[groupIndex]
        let nextOff = offset + step
        if nextOff < group.count {
            return (groupIndex, nextOff)
        }
        let ng = groupIndex + 1
        if ng >= groups.count { return nil }
        return (ng, 0)
    }

    private static func enumeratePhotoSlides(groups: [[PanoramaPhotoEntry]]) -> [ExportPhotoSlideSpec] {
        guard !groups.isEmpty else { return [] }
        var specs: [ExportPhotoSlideSpec] = []
        var gi = 0
        var off = 0
        var layout = chooseDeterministicLayout(
            groupIndex: gi,
            offset: off,
            remaining: groups[gi].count - off
        )

        while true {
            let group = groups[gi]
            switch layout {
            case .solo:
                guard off < group.count else { return specs }
                specs.append(ExportPhotoSlideSpec(layout: .solo, top: group[off], bottom: nil))
                guard let next = advanceAfterStep(groups: groups, groupIndex: gi, offset: off, step: 1) else {
                    return specs
                }
                gi = next.groupIndex
                off = next.offset
            case .diptych:
                guard off + 1 < group.count else {
                    layout = .solo
                    continue
                }
                specs.append(ExportPhotoSlideSpec(layout: .diptych, top: group[off], bottom: group[off + 1]))
                guard let next = advanceAfterStep(groups: groups, groupIndex: gi, offset: off, step: 2) else {
                    return specs
                }
                gi = next.groupIndex
                off = next.offset
            }
            layout = chooseDeterministicLayout(
                groupIndex: gi,
                offset: off,
                remaining: groups[gi].count - off
            )
        }
    }

    private static func enumerateSlideshowSlides(
        dayGroups: [DaySlideshowGroup],
        includeDailyMapIntro: Bool
    ) -> [ExportSlideSpec] {
        var specs: [ExportSlideSpec] = []
        for day in dayGroups {
            let photoSpecs = enumeratePhotoSlides(groups: day.photoGroups)
            guard !photoSpecs.isEmpty else { continue }
            if includeDailyMapIntro, !day.mapStops.isEmpty {
                specs.append(.dayMap(
                    ExportDayMapSlideSpec(
                        dayID: day.dayID,
                        dayNumber: day.dayNumber,
                        dayDateText: day.dayDateText,
                        placeCount: day.placeCount,
                        photoCount: day.photoCount
                    )
                ))
            }
            specs.append(contentsOf: photoSpecs.map { .photo($0) })
        }
        return specs
    }

    private static func generateDayMapSlides(
        dayGroups: [DaySlideshowGroup],
        logicalSize: CGSize,
        includeDailyMapIntro: Bool
    ) async -> [UUID: UIImage] {
        guard includeDailyMapIntro else { return [:] }
        let days = dayGroups.filter { !$0.mapStops.isEmpty }
        guard !days.isEmpty else { return [:] }

        let mapSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
        return await withTaskGroup(of: (UUID, UIImage?).self, returning: [UUID: UIImage].self) { group in
            for day in days {
                group.addTask {
                    let image = await MapSnapshotHelper.generateSnapshot(
                        for: day.mapStops,
                        size: mapSize,
                        regionPadding: 0.045,
                        showPlaceNames: true
                    )
                    return (day.dayID, image)
                }
            }

            var images: [UUID: UIImage] = [:]
            for await (dayID, image) in group {
                if let image { images[dayID] = image }
            }
            return images
        }
    }

    // MARK: - Slide rendering (full-bleed photos on black, Ken Burns midpoint for solo)

    private static let exportZoomScale: CGFloat = 1.12

    private static func soloKenBurnsScale(zoomIn: Bool, progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        let start: CGFloat = zoomIn ? 1.0 : exportZoomScale
        let end: CGFloat = zoomIn ? exportZoomScale : 1.0
        return start + (end - start) * t
    }

    @MainActor
    private static func renderSlideshowSpecToImage(
        spec: ExportSlideSpec,
        loaded: [String: UIImage],
        dayMapImages: [UUID: UIImage],
        logicalSize: CGSize,
        slideIndex: Int,
        zoomIn: Bool,
        options: BlogVideoExportOptions
    ) throws -> UIImage {
        let root = SlideshowExportFrameView(
            spec: spec,
            loaded: loaded,
            dayMapImages: dayMapImages,
            size: logicalSize,
            zoomIn: zoomIn,
            includeTimestamps: options.includeTimestamps
        )
        .frame(width: logicalSize.width, height: logicalSize.height)
        .background(Color.black)

        let renderer = ImageRenderer(content: root)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: logicalSize.width, height: logicalSize.height)

        guard let image = renderer.uiImage else {
            throw ExportError.failedToRenderPage(slideIndex)
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

    // MARK: - SwiftUI slideshow frame (export)

    private struct SlideshowExportFrameView: View {
        let spec: ExportSlideSpec
        let loaded: [String: UIImage]
        let dayMapImages: [UUID: UIImage]
        let size: CGSize
        let zoomIn: Bool
        let includeTimestamps: Bool

        private static let timestampFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        var body: some View {
            switch spec {
            case .photo(let photoSpec):
                switch photoSpec.layout {
                case .solo:
                    soloExportView(entry: photoSpec.top)
                case .diptych:
                    let paneH = (size.height - 2) / 2
                    VStack(spacing: 2) {
                        photoFill(entry: photoSpec.top, width: size.width, height: paneH)
                        photoFill(entry: photoSpec.bottom, width: size.width, height: paneH)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                }
            case .dayMap(let mapSpec):
                dayMapView(spec: mapSpec)
            }
        }

        @ViewBuilder
        private func dayMapView(spec: ExportDayMapSlideSpec) -> some View {
            ZStack(alignment: .bottomLeading) {
                if let map = dayMapImages[spec.dayID] {
                    Image(uiImage: map)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Color(white: 0.18)
                        .frame(width: size.width, height: size.height)
                }

                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: size.width, height: size.height)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Day \(spec.dayNumber)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if !spec.dayDateText.isEmpty {
                        Text(spec.dayDateText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    Text("\(spec.placeCount) places visited • \(spec.photoCount) photos")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }

        @ViewBuilder
        private func soloExportView(entry: PanoramaPhotoEntry) -> some View {
            let scale = BlogVideoExportService.soloKenBurnsScale(zoomIn: zoomIn, progress: 0.5)
            photoFill(entry: entry, width: size.width, height: size.height, scale: scale)
        }

        @ViewBuilder
        private func photoFill(entry: PanoramaPhotoEntry?, width: CGFloat, height: CGFloat, scale: CGFloat = 1.0) -> some View {
            if let entry, let img = loaded[entry.id] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .scaleEffect(scale)
                    .clipped()
                    .overlay {
                        if includeTimestamps,
                           let timestamp = entry.timestamp {
                            Text(Self.timestampFormatter.string(from: timestamp))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.35), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
                                .padding(12)
                        }
                    }
            } else {
                Color.gray.opacity(0.35)
                    .frame(width: width, height: height)
            }
        }
    }
}
