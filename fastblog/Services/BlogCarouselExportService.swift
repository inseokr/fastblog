// fastblog/Services/BlogCarouselExportService.swift
import AVFoundation
import Photos
import UIKit

/// Generates a 1080×1920 carousel for TikTok-style photo+video carousel posts.
/// Static images for cover and day cards; short Ken Burns video clips for place hero slides.
/// Saves everything to a named Photos album and returns the saved asset IDs.
enum BlogCarouselExportService {

    private static let slideSize = CGSize(width: 1080, height: 1920)
    private static let clipDurationSeconds: Double = 2.5
    private static let clipFPS: Double = 30

    // MARK: - Slide type

    private enum CarouselSlide {
        case image(UIImage)
        case video(URL)
    }

    // MARK: - Public API

    @MainActor
    static func exportCarousel(
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> [String] {
        let slides = try await buildSlides(draft: draft, options: options, progressHandler: progressHandler)
        defer { cleanupVideoFiles(slides) }
        return try await saveToPhotos(slides: slides, albumName: "Bloggo – \(draft.title)")
    }

    // MARK: - Slide Building

    private static func buildSlides(
        draft: RecapBlogDetail,
        options: BlogVideoExportOptions,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> [CarouselSlide] {
        let pixelSize = slideSize
        var slides: [CarouselSlide] = []

        // Cover slide — static image
        progressHandler?(0.05)
        let coverImage = await loadPhoto(from: draft, pixelSize: pixelSize)
        let cover = autoreleasepool {
            drawCoverSlide(draft: draft, pixelSize: pixelSize, coverImage: coverImage)
        }
        slides.append(.image(cover))

        let activeDays: [RecapBlogDay] = draft.days.compactMap { day in
            let stops: [PlaceStop]
            if let ids = options.includedPlaceIDs {
                stops = day.placeStops.filter { ids.contains($0.id) }
            } else {
                stops = day.placeStops
            }
            guard !stops.isEmpty else { return nil }
            var d = day; d.placeStops = stops; return d
        }

        let totalStops = Double(max(activeDays.flatMap(\.placeStops).count, 1))
        var processedStops = 0.0

        for (dayIdx, day) in activeDays.enumerated() {
            try Task.checkCancellation()

            // Day itinerary card — static image
            let dayCard = autoreleasepool {
                CinematicBlogVideoBuilder.drawDayItineraryCard(
                    day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize
                )
            }
            slides.append(.image(dayCard))

            // Place hero — Ken Burns video clip, falling back to static image
            for (stopIdx, stop) in day.placeStops.enumerated() {
                try Task.checkCancellation()
                guard let bestPhoto = stop.includedPhotos.first,
                      let img = await loadPhoto(bestPhoto, pixelSize: pixelSize) else {
                    processedStops += 1
                    continue
                }
                let direction = KenBurnsDirection.allCases[(dayIdx * 7 + stopIdx) % KenBurnsDirection.allCases.count]
                if let clipURL = try? await renderKenBurnsClip(
                    photo: img, stop: stop, dayNumber: dayIdx + 1,
                    pixelSize: pixelSize, direction: direction
                ) {
                    slides.append(.video(clipURL))
                } else {
                    let fallback = autoreleasepool {
                        drawPlacePhotoSlide(photo: img, stop: stop, dayNumber: dayIdx + 1, pixelSize: pixelSize)
                    }
                    slides.append(.image(fallback))
                }
                processedStops += 1
                progressHandler?(0.05 + 0.85 * processedStops / totalStops)
            }
        }

        progressHandler?(0.92)
        return slides
    }

    // MARK: - Ken Burns Video Clip

    private enum KenBurnsDirection: CaseIterable {
        case zoomIn, zoomOut, panLeft, panRight
    }

    private static func renderKenBurnsClip(
        photo: UIImage,
        stop: PlaceStop,
        dayNumber: Int,
        pixelSize: CGSize,
        direction: KenBurnsDirection
    ) async throws -> URL {
        let frameCount = Int(clipDurationSeconds * clipFPS)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached(priority: .userInitiated) {
                do {
                    let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
                    let videoSettings: [String: Any] = [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: Int(pixelSize.width),
                        AVVideoHeightKey: Int(pixelSize.height),
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: 8_000_000,
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                        ]
                    ]
                    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                    writerInput.expectsMediaDataInRealTime = false
                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                        assetWriterInput: writerInput,
                        sourcePixelBufferAttributes: [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferWidthKey as String: Int(pixelSize.width),
                            kCVPixelBufferHeightKey as String: Int(pixelSize.height)
                        ]
                    )
                    writer.add(writerInput)
                    writer.startWriting()
                    writer.startSession(atSourceTime: .zero)

                    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.clipFPS))

                    for i in 0..<frameCount {
                        if Task.isCancelled { break }

                        var retries = 0
                        while !writerInput.isReadyForMoreMediaData, retries < 200 {
                            try await Task.sleep(for: .milliseconds(5))
                            retries += 1
                        }
                        guard writerInput.isReadyForMoreMediaData else { continue }

                        let progress = Double(i) / Double(max(frameCount - 1, 1))
                        let (scale, offset) = Self.kenBurnsTransform(direction: direction, progress: progress, size: pixelSize)
                        let frame = autoreleasepool {
                            Self.drawPlacePhotoSlide(
                                photo: photo, stop: stop, dayNumber: dayNumber,
                                pixelSize: pixelSize, photoScale: scale, photoOffset: offset
                            )
                        }
                        if let buffer = Self.pixelBuffer(from: frame, size: pixelSize) {
                            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
                            adaptor.append(buffer, withPresentationTime: pts)
                        }
                    }

                    writerInput.markAsFinished()
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        writer.finishWriting { cont.resume() }
                    }

                    if writer.status == .failed {
                        continuation.resume(throwing: writer.error ?? CarouselExportError.videoRenderFailed)
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return tempURL
    }

    private static func kenBurnsTransform(
        direction: KenBurnsDirection, progress: Double, size: CGSize
    ) -> (scale: CGFloat, offset: CGPoint) {
        let p = CGFloat(progress)
        let maxScale: CGFloat = 1.14
        let panFraction: CGFloat = 0.06
        switch direction {
        case .zoomIn:
            return (1.0 + (maxScale - 1.0) * p, .zero)
        case .zoomOut:
            return (maxScale - (maxScale - 1.0) * p, .zero)
        case .panLeft:
            return (maxScale, CGPoint(x: size.width * panFraction * (1.0 - 2.0 * p), y: 0))
        case .panRight:
            return (maxScale, CGPoint(x: size.width * panFraction * (2.0 * p - 1.0), y: 0))
        }
    }

    // MARK: - Pixel Buffer

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        var buf: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA, attrs, &buf
        ) == kCVReturnSuccess, let buf else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let cg = image.cgImage else { return nil }

        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return buf
    }

    // MARK: - Photos Save

    private static func saveToPhotos(slides: [CarouselSlide], albumName: String) async throws -> [String] {
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else {
            throw CarouselExportError.photosAccessDenied
        }

        var albumRef: PHAssetCollection?
        let fetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        fetchResult.enumerateObjects { col, _, stop in
            if col.localizedTitle == albumName { albumRef = col; stop.pointee = true }
        }

        if albumRef == nil {
            var createdID: String?
            try await PHPhotoLibrary.shared().performChanges {
                createdID = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                    withTitle: albumName
                ).placeholderForCreatedAssetCollection.localIdentifier
            }
            if let cid = createdID {
                albumRef = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [cid], options: nil
                ).firstObject
            }
        }

        guard let album = albumRef else { throw CarouselExportError.albumCreationFailed }

        var savedIDs: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for slide in slides {
                switch slide {
                case .image(let img):
                    let req = PHAssetChangeRequest.creationRequestForAsset(from: img)
                    if let ph = req.placeholderForCreatedAsset { placeholders.append(ph) }
                case .video(let url):
                    if let req = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url),
                       let ph = req.placeholderForCreatedAsset {
                        placeholders.append(ph)
                    }
                }
            }
            if let albumReq = PHAssetCollectionChangeRequest(for: album) {
                albumReq.addAssets(placeholders as NSFastEnumeration)
            }
            savedIDs = placeholders.map(\.localIdentifier)
        }
        return savedIDs
    }

    private static func cleanupVideoFiles(_ slides: [CarouselSlide]) {
        for case .video(let url) in slides {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Drawing: Cover Slide

    private static func drawCoverSlide(
        draft: RecapBlogDetail, pixelSize: CGSize, coverImage: UIImage?
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            if let photo = coverImage {
                let ar = photo.size.width / max(photo.size.height, 1)
                let far = w / h
                let dw: CGFloat, dh: CGFloat
                if ar > far { dh = h; dw = dh * ar } else { dw = w; dh = dw / ar }
                photo.draw(in: CGRect(x: (w - dw) / 2, y: (h - dh) / 2, width: dw, height: dh))
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.clear.cgColor,
                        UIColor.black.withAlphaComponent(0.82).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: CGPoint(x: 0, y: h * 0.40), end: CGPoint(x: 0, y: h), options: []
                )
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.black.withAlphaComponent(0.55).cgColor,
                        UIColor.clear.cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h * 0.22), options: []
                )
            } else {
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor(red: 5/255, green: 10/255, blue: 48/255, alpha: 1).cgColor,
                        UIColor(red: 2/255, green: 5/255, blue: 30/255, alpha: 1).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h), options: []
                )
            }

            let titleFont = UIFont.systemFont(ofSize: (w * 0.062).rounded(), weight: .black)
            let titlePara = NSMutableParagraphStyle(); titlePara.alignment = .center
            let titleAttribs: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: titlePara
            ]
            let titleStr = draft.title as NSString
            let titleMaxW = w - 80
            let titleSize = titleStr.boundingRect(
                with: CGSize(width: titleMaxW, height: h * 0.45),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttribs, context: nil
            ).integral.size

            let dateFont = UIFont.systemFont(ofSize: (w * 0.032).rounded(), weight: .medium)
            let datePara = NSMutableParagraphStyle(); datePara.alignment = .center
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                .paragraphStyle: datePara
            ]
            let dateStr = coverDateRange(from: draft.days) as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let blockH = titleSize.height + 14 + dateSize.height
            let blockTop = (h * 0.78 - blockH / 2).rounded()

            titleStr.draw(
                in: CGRect(x: (w - titleSize.width) / 2, y: blockTop,
                           width: titleSize.width, height: titleSize.height),
                withAttributes: titleAttribs
            )
            let dateY = (blockTop + titleSize.height + 14).rounded()
            dateStr.draw(
                in: CGRect(x: (w - dateSize.width) / 2, y: dateY,
                           width: dateSize.width, height: dateSize.height),
                withAttributes: dateAttribs
            )
        }
    }

    // MARK: - Drawing: Place Photo Slide (also serves as Ken Burns per-frame renderer)

    private static func drawPlacePhotoSlide(
        photo: UIImage, stop: PlaceStop, dayNumber: Int, pixelSize: CGSize,
        photoScale: CGFloat = 1.0, photoOffset: CGPoint = .zero
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            // Aspect-fill photo with Ken Burns scale/offset applied
            let ar = photo.size.width / max(photo.size.height, 1)
            let far = w / h
            var dw: CGFloat, dh: CGFloat
            if ar > far { dh = h; dw = dh * ar } else { dw = w; dh = dw / ar }
            dw *= photoScale; dh *= photoScale
            let x = (w - dw) / 2 + photoOffset.x
            let y = (h - dh) / 2 + photoOffset.y
            photo.draw(in: CGRect(x: x, y: y, width: dw, height: dh))

            // Bottom scrim
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.65).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.60), options: []
            )

            // Day badge (top-left)
            let badgeFont = UIFont.monospacedSystemFont(ofSize: (w * 0.024).rounded(), weight: .semibold)
            let badgeAttribs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.9)
            ]
            let badgeStr = "DAY \(dayNumber)" as NSString
            let badgeSize = badgeStr.size(withAttributes: badgeAttribs)
            let badgePad: CGFloat = 10
            let badgeRect = CGRect(
                x: 40 - badgePad, y: 60 - badgePad,
                width: badgeSize.width + badgePad * 2,
                height: badgeSize.height + badgePad * 1.5
            )
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 8)
            UIColor.black.withAlphaComponent(0.48).setFill()
            badgePath.fill()
            badgeStr.draw(at: CGPoint(x: 40, y: 60), withAttributes: badgeAttribs)

            // Place name (bottom)
            let nameFont = UIFont.systemFont(ofSize: (w * 0.052).rounded(), weight: .bold)
            let namePara = NSMutableParagraphStyle()
            namePara.lineBreakMode = .byTruncatingTail
            let nameAttribs: [NSAttributedString.Key: Any] = [
                .font: nameFont, .foregroundColor: UIColor.white, .paragraphStyle: namePara
            ]
            let nameStr = stop.placeTitle as NSString
            let maxNameW = w - 80
            let nameSize = nameStr.boundingRect(
                with: CGSize(width: maxNameW, height: h * 0.15),
                options: [.usesLineFragmentOrigin], attributes: nameAttribs, context: nil
            ).integral.size

            var subtitleH: CGFloat = 0
            var subtitleAttribs: [NSAttributedString.Key: Any] = [:]
            let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !subtitle.isEmpty {
                let subFont = UIFont.systemFont(ofSize: (w * 0.032).rounded(), weight: .medium)
                subtitleAttribs = [
                    .font: subFont,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.70)
                ]
                subtitleH = (subtitle as NSString).size(withAttributes: subtitleAttribs).height + 6
            }

            let bottomPad: CGFloat = 80
            let nameY = (h - bottomPad - nameSize.height - subtitleH).rounded()
            nameStr.draw(
                in: CGRect(x: 40, y: nameY, width: maxNameW, height: nameSize.height + 4),
                withAttributes: nameAttribs
            )
            if !subtitle.isEmpty {
                (subtitle as NSString).draw(
                    at: CGPoint(x: 40, y: (nameY + nameSize.height + 6).rounded()),
                    withAttributes: subtitleAttribs
                )
            }
        }
    }

    // MARK: - Helpers

    private static func coverDateRange(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.monthDayStringForStoryBookRange()) – \(last.monthDayStringForStoryBookRange())\(last.yearSuffixForStoryBookRange())"
    }

    private static func loadPhoto(from draft: RecapBlogDetail, pixelSize: CGSize) async -> UIImage? {
        guard let lid = draft.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lid.isEmpty else { return nil }
        let dummy = RecapPhoto(timestamp: Date(), imageName: "cover", localIdentifier: lid)
        return await loadPhoto(dummy, pixelSize: pixelSize)
    }

    private static func loadPhoto(_ photo: RecapPhoto, pixelSize: CGSize) async -> UIImage? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            if lid.hasPrefix(AppCapturePhotoService.prefix) {
                return AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            return await ImageLoader.shared.loadImageBypassingMemoryCache(
                assetIdentifier: lid, targetSize: pixelSize
            )
        }
        guard let permanentURL = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !permanentURL.isEmpty else { return nil }
        do {
            let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: permanentURL)
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            return UIImage(data: data)
        } catch { return nil }
    }

    // MARK: - Errors

    enum CarouselExportError: Error, LocalizedError {
        case photosAccessDenied
        case albumCreationFailed
        case videoRenderFailed

        var errorDescription: String? {
            switch self {
            case .photosAccessDenied:  return "Photos access is required to save your carousel. Please allow access in Settings."
            case .albumCreationFailed: return "Could not create the Bloggo album in Photos."
            case .videoRenderFailed:   return "Failed to render a video clip for a place."
            }
        }
    }
}
