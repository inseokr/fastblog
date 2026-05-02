// fastblog/Services/CinematicBlogVideoBuilder.swift
import UIKit
import Foundation
import MapKit

/// Builds the cinematic video frame sequence and streams each frame to the caller via
/// `frameHandler` so memory stays flat (one frame live at a time).
///
/// Per-place visual sequence:
///   1. Pan animation  — 14 true snapshots: first stop of each day from day-wide map → neighborhood;
///      later stops pan neighborhood→neighborhood (retains secondary zoom, no zoom-out reset).
///   2. Zoom-in        — `MapAnimationQuality.efficient`: cross-dissolve at cinematicZoomSegmentTargetFPS.
///                       `.highFidelity`: interpolated MKMapSnapshotter frames (true tile zoom; slower export).
///   3. Focused reveal — 0.003° with place info overlaid at bottom (2.5 s)
///   4. Photo slides   — full-pixel images, story panel when caption is non-empty
enum CinematicBlogVideoBuilder {

    /// Target temporal sampling for the wide→tight zoom dissolve (no extra MapKit work).
    private static let cinematicZoomSegmentTargetFPS: Double = 30
    /// Wall-clock for wide frame + dissolve chain. Shorter than legacy ~1.82 s so zoom feels snappier
    /// (angular change 0.008°→0.003° is subtle; long duration reads as “slow” even at 30 fps).
    private static let cinematicZoomSegmentDurationSeconds: Double = 0.88

    private static let cinematicPanFrameDurationSeconds: Double = 0.11

    /// Aligns map bitmap pixels with `BlogVideoExportService` / `ImageRenderer(scale: 2)`.
    private static let exportMapDisplayScale: CGFloat = 2
    private static let cinematicPanFrameCount = 14
    /// After the first place on a day, the map “hands off” from the previous marker (still highlighted)
    /// → brief all-muted beat → new marker + optional on-map place pill for the rest of the pan.
    private static let cinematicPanHandoffPreviousHighlightFrames = 5
    private static let cinematicPanHandoffAllMutedFrames = 3
    /// Snapshot-based wide→tight zoom when using `MapAnimationQuality.highFidelity`.
    private static let cinematicHighFidelityZoomFrameCount = 22

    private static var cinematicZoomFrameDurationSeconds: Double {
        1.0 / cinematicZoomSegmentTargetFPS
    }

    /// Number of synthesized dissolve steps after the initial wide frame (at least 12).
    private static var cinematicZoomBlendFrameCount: Int {
        let fromDuration = Int(round(cinematicZoomSegmentDurationSeconds * cinematicZoomSegmentTargetFPS)) - 1
        return max(12, fromDuration)
    }

    // MARK: - Entry point

    /// Generates frames in order and calls `frameHandler(image, duration)` for each.
    /// The handler is expected to write the frame to video immediately; the image is
    /// released once the handler returns.
    static func buildFrames(
        from draft: RecapBlogDetail,
        logicalSize: CGSize,
        secondsPerPhoto: Double,
        mapAnimationQuality: MapAnimationQuality = .efficient,
        progressHandler: ((Double) -> Void)? = nil,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws {
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
        let days = draft.days.filter { !$0.placeStops.isEmpty }
        let totalDays = Double(max(days.count, 1))

        let coverImage = await loadCoverImageForVideo(draft: draft, pixelSize: pixelSize)
        try await frameHandler(
            autoreleasepool { drawCoverPage(draft: draft, pixelSize: pixelSize, coverImage: coverImage) },
            2.0
        )

        for (dayIdx, day) in days.enumerated() {
            try Task.checkCancellation()

            let stops = day.placeStops

            let dayOverviewRegion: MKCoordinateRegion = {
                if let r = MapSnapshotHelper.regionBoundingAllStops(stops, padding: 0.16) { return r }
                let c = stops.compactMap { $0.representativeLocation?.clCoordinate }
                    .first { $0.latitude.isFinite && $0.longitude.isFinite }
                    ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902)
                return MKCoordinateRegion(
                    center: c,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                )
            }()

            for (placeIdx, stop) in stops.enumerated() {
                try Task.checkCancellation()

                if let focusedCoord = stop.representativeLocation?.clCoordinate,
                   focusedCoord.latitude.isFinite, focusedCoord.longitude.isFinite {

                    let neighborhoodSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    let wideRegion  = MKCoordinateRegion(center: focusedCoord, span: neighborhoodSpan)
                    let tightRegion = MKCoordinateRegion(center: focusedCoord,
                                                         span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))

                    let previousIdx = placeIdx - 1
                    let previousHasMapPin: Bool = {
                        guard placeIdx > 0,
                              let loc = stops[previousIdx].representativeLocation else { return false }
                        let c = loc.clCoordinate
                        return c.latitude.isFinite && c.longitude.isFinite
                    }()
                    /// First stop of the day: pan from full-day overview into neighborhood. Later stops: stay at
                    /// neighborhood zoom and pan from the previous marker’s frame so export does not zoom out again.
                    let panFromRegion: MKCoordinateRegion = {
                        guard placeIdx > 0, previousHasMapPin,
                              let prevCoord = stops[previousIdx].representativeLocation?.clCoordinate,
                              prevCoord.latitude.isFinite, prevCoord.longitude.isFinite else {
                            return dayOverviewRegion
                        }
                        return MKCoordinateRegion(center: prevCoord, span: neighborhoodSpan)
                    }()

                    // 1. Pan: day-wide (first stop only) or neighborhood → neighborhood around the focus.
                    let panDt = cinematicPanFrameDurationSeconds
                    var isFirstPanFrameThisDay = (placeIdx == 0)
                    let handoffEnd = cinematicPanHandoffPreviousHighlightFrames + cinematicPanHandoffAllMutedFrames
                    try await MapSnapshotHelper.forEachInterpolatedFrame(
                        from: panFromRegion, to: wideRegion,
                        allStops: stops,
                        focusedStopIndexForFrame: { frameIdx in
                            if placeIdx == 0 { return 0 }
                            guard previousHasMapPin else { return placeIdx }
                            if frameIdx < cinematicPanHandoffPreviousHighlightFrames { return previousIdx }
                            if frameIdx < handoffEnd { return nil }
                            return placeIdx
                        },
                        showPlaceNamePillForFrame: { frameIdx in
                            guard frameIdx >= handoffEnd else { return false }
                            if placeIdx == 0 { return true }
                            return previousHasMapPin
                        },
                        logicalSize: logicalSize, displayScale: exportMapDisplayScale,
                        frameCount: cinematicPanFrameCount, inclusiveEndpoints: true
                    ) { img in
                        if isFirstPanFrameThisDay {
                            isFirstPanFrameThisDay = false
                            let withHeader = autoreleasepool {
                                drawDayHeaderOverlay(on: img, day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize)
                            }
                            try await frameHandler(withHeader, panDt)
                        } else {
                            try await frameHandler(img, panDt)
                        }
                    }

                    let zoomDt = cinematicZoomFrameDurationSeconds

                    // 2. Zoom-in to POI
                    if mapAnimationQuality == .highFidelity {
                        var lastZoomFrame: UIImage?
                        try await MapSnapshotHelper.forEachInterpolatedFrame(
                            from: wideRegion, to: tightRegion,
                            allStops: stops,
                            focusedStopIndexForFrame: { _ in placeIdx },
                            showPlaceNamePillForFrame: { _ in true },
                            logicalSize: logicalSize, displayScale: exportMapDisplayScale,
                            frameCount: cinematicHighFidelityZoomFrameCount, inclusiveEndpoints: true
                        ) { img in
                            lastZoomFrame = img
                            try await frameHandler(img, zoomDt)
                        }
                        if let tightMap = lastZoomFrame {
                            let photoThumbs = await loadThumbnailsForPlaceMapOverlay(stop: stop)
                            let overlaid = autoreleasepool {
                                drawPlaceOverlayOnMap(
                                    mapImage: tightMap, stop: stop,
                                    markerNumber: placeIdx + 1, totalStops: stops.count,
                                    pixelSize: pixelSize,
                                    photoThumbnails: photoThumbs
                                )
                            }
                            try await frameHandler(overlaid, 2.5)
                        }
                    } else if let wideImg = await MapSnapshotHelper.generateSnapshotAtRegion(
                        region: wideRegion, focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize,
                        displayScale: exportMapDisplayScale, showPlaceNamePillForFocused: false
                    ) {
                        try await frameHandler(wideImg, zoomDt)

                        var tightBase = await MapSnapshotHelper.generateSnapshotAtRegion(
                            region: tightRegion, focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: true
                        )
                        if tightBase == nil {
                            tightBase = await MapSnapshotHelper.generateFocusedSnapshot(
                                focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize,
                                displayScale: exportMapDisplayScale,
                                showPlaceNamePillForFocused: true
                            )
                        }

                        if let tightBase {
                            let blendCount = cinematicZoomBlendFrameCount
                            for step in 1...blendCount {
                                try Task.checkCancellation()
                                let blended = autoreleasepool {
                                    synthesizeBlendFrame(
                                        from: wideImg, to: tightBase,
                                        stepIndex: step, blendStepCount: blendCount, size: pixelSize
                                    )
                                }
                                try await frameHandler(blended, zoomDt)
                            }

                            let photoThumbs = await loadThumbnailsForPlaceMapOverlay(stop: stop)
                            let overlaid = autoreleasepool {
                                drawPlaceOverlayOnMap(
                                    mapImage: tightBase, stop: stop,
                                    markerNumber: placeIdx + 1, totalStops: stops.count,
                                    pixelSize: pixelSize,
                                    photoThumbnails: photoThumbs
                                )
                            }
                            try await frameHandler(overlaid, 2.5)
                        }
                    }

                    let stopCount = Double(max(stops.count, 1))
                    progressHandler?((Double(dayIdx) + Double(placeIdx + 1) / stopCount) / totalDays)
                }

                // 4. Photo slides — one at a time, released after each write
                let placeTZ = await PlaceLibraryPhotoImport.placeTimeZone(for: stop)
                for photo in stop.includedPhotos.prefix(5) {
                    try Task.checkCancellation()
                    if let img = await loadPhoto(photo, targetSize: pixelSize) {
                        let timeLabel = militaryTimeDisplayString(photo: photo, placeTimeZone: placeTZ)
                        let slide = autoreleasepool {
                            drawPhotoSlide(
                                img,
                                caption: photo.caption,
                                placeName: stop.placeTitle,
                                timestampText: timeLabel,
                                pixelSize: pixelSize
                            )
                        }
                        try await frameHandler(slide, secondsPerPhoto)
                    }
                }
            }

            progressHandler?(Double(dayIdx + 1) / totalDays)
        }
    }

    // MARK: - Cover page

    private static func loadCoverImageForVideo(draft: RecapBlogDetail, pixelSize: CGSize) async -> UIImage? {
        guard let lid = draft.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lid.isEmpty else { return nil }
        let dummy = RecapPhoto(timestamp: Date(), imageName: "cover", localIdentifier: lid)
        return await loadPhoto(dummy, targetSize: pixelSize)
    }

    private static func videoCoverDateRangeString(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.monthDayStringForStoryBookRange()) – \(last.monthDayStringForStoryBookRange())\(last.yearSuffixForStoryBookRange())"
    }

    private static func drawCoverPage(
        draft: RecapBlogDetail, pixelSize: CGSize, coverImage: UIImage?
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            if let photo = coverImage {
                let photoAR = photo.size.width / max(photo.size.height, 1)
                let frameAR = w / h
                let drawRect: CGRect
                if photoAR > frameAR {
                    let dh = h, dw = dh * photoAR
                    drawRect = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
                } else {
                    let dw = w, dh = dw / photoAR
                    drawRect = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
                }
                photo.draw(in: drawRect)

                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.black.withAlphaComponent(0.58).cgColor, UIColor.clear.cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h * 0.24), options: []
                )
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.78).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: CGPoint(x: 0, y: h * 0.48), end: CGPoint(x: 0, y: h), options: []
                )
                // Extra lift for centered type on bright cover photos
                cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
                cg.fill(CGRect(origin: .zero, size: pixelSize))
            } else {
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor(red: 5/255, green: 10/255, blue: 48/255, alpha: 1).cgColor,
                        UIColor(red: 2/255, green: 5/255, blue: 30/255, alpha: 1).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h), options: []
                )
            }

            let iceBlue = UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.70)
            let labelFont = UIFont.monospacedSystemFont(ofSize: w * 0.028, weight: .medium)
            let labelStr = "TRAVEL BLOG" as NSString
            let labelAttribs: [NSAttributedString.Key: Any] = [
                .font: labelFont, .foregroundColor: iceBlue, .kern: w * 0.006
            ]
            let labelSize = labelStr.size(withAttributes: labelAttribs)

            let titleFont = UIFont.systemFont(ofSize: w * 0.072, weight: .black)
            let titlePara = NSMutableParagraphStyle()
            titlePara.alignment = .center
            let titleAttribs: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: titlePara
            ]
            let titleStr = draft.title as NSString
            let titleMaxW = w - 80
            let titleMeasured = titleStr.boundingRect(
                with: CGSize(width: titleMaxW, height: h * 0.45),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttribs, context: nil
            ).integral.size

            let dateFont = UIFont.systemFont(ofSize: w * 0.036, weight: .medium)
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont, .foregroundColor: UIColor.white.withAlphaComponent(0.75)
            ]
            let dateStr = videoCoverDateRangeString(from: draft.days) as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let momentsCount = draft.days.filter { !$0.placeStops.isEmpty }.flatMap(\.placeStops).count
            let daysCount = draft.days.count
            let photosCount = draft.allIncludedPhotos.count
            let numFont = UIFont.systemFont(ofSize: w * 0.034, weight: .semibold)
            let capFont = UIFont.systemFont(ofSize: w * 0.026, weight: .regular)
            let sepColor = UIColor.white.withAlphaComponent(0.20)

            let momentsNum = "\(momentsCount)" as NSString
            let momentsCap = "Moments" as NSString
            let daysNum = "\(daysCount)" as NSString
            let daysCap = (daysCount == 1 ? "Day" : "Days") as NSString
            let photosNum = "\(photosCount)" as NSString
            let photosCap = "Photos" as NSString
            let mNumSize = momentsNum.size(withAttributes: [.font: numFont])
            let mCapSize = momentsCap.size(withAttributes: [.font: capFont])
            let dNumSize = daysNum.size(withAttributes: [.font: numFont])
            let dCapSize = daysCap.size(withAttributes: [.font: capFont])
            let pNumSize = photosNum.size(withAttributes: [.font: numFont])
            let pCapSize = photosCap.size(withAttributes: [.font: capFont])
            let col1W = max(mNumSize.width, mCapSize.width)
            let col2W = max(dNumSize.width, dCapSize.width)
            let col3W = max(pNumSize.width, pCapSize.width)
            let statsGap: CGFloat = 14
            let sepW: CGFloat = 1
            let statsRowW = col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW + statsGap + col3W
            let statsRowH = max(
                mNumSize.height + 2 + mCapSize.height,
                dNumSize.height + 2 + dCapSize.height,
                pNumSize.height + 2 + pCapSize.height
            )

            let dividerW: CGFloat = min(200, w * 0.22)
            let dividerMargin: CGFloat = 8
            let lineGap: CGFloat = 10
            let stackH = labelSize.height + lineGap + titleMeasured.height + dividerMargin + 1.5 + dividerMargin
                + lineGap + dateSize.height + lineGap + statsRowH
            var y = (h - stackH) / 2

            labelStr.draw(at: CGPoint(x: (w - labelSize.width) / 2, y: y), withAttributes: labelAttribs)
            y += labelSize.height + lineGap
            titleStr.draw(
                with: CGRect(x: 40, y: y, width: titleMaxW, height: titleMeasured.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttribs, context: nil
            )
            y += titleMeasured.height + dividerMargin
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.42).cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: (w - dividerW) / 2, y: y))
            cg.addLine(to: CGPoint(x: (w + dividerW) / 2, y: y))
            cg.strokePath()
            y += 1.5 + dividerMargin + lineGap
            dateStr.draw(at: CGPoint(x: (w - dateSize.width) / 2, y: y), withAttributes: dateAttribs)
            y += dateSize.height + lineGap

            let statsX = (w - statsRowW) / 2
            let col1CenterX = statsX + col1W / 2
            let col2CenterX = statsX + col1W + statsGap + sepW + statsGap + col2W / 2
            let col3CenterX = statsX + col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW + statsGap + col3W / 2
            momentsNum.draw(
                at: CGPoint(x: col1CenterX - mNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            momentsCap.draw(
                at: CGPoint(x: col1CenterX - mCapSize.width / 2, y: y + mNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            daysNum.draw(
                at: CGPoint(x: col2CenterX - dNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            daysCap.draw(
                at: CGPoint(x: col2CenterX - dCapSize.width / 2, y: y + dNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            photosNum.draw(
                at: CGPoint(x: col3CenterX - pNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            photosCap.draw(
                at: CGPoint(x: col3CenterX - pCapSize.width / 2, y: y + pNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            cg.setStrokeColor(sepColor.cgColor)
            cg.setLineWidth(1)
            let sep1X = statsX + col1W + statsGap + sepW / 2
            cg.move(to: CGPoint(x: sep1X, y: y))
            cg.addLine(to: CGPoint(x: sep1X, y: y + statsRowH))
            cg.strokePath()
            let sep2X = statsX + col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW / 2
            cg.move(to: CGPoint(x: sep2X, y: y))
            cg.addLine(to: CGPoint(x: sep2X, y: y + statsRowH))
            cg.strokePath()
        }
    }

    // MARK: - Day Header Overlay on Map

    private static func drawDayHeaderOverlay(
        on mapImage: UIImage, day: RecapBlogDay, dayNumber: Int, pixelSize: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            mapImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            // Top scrim so the day header stays readable; text sits top-leading with extra left inset
            // so preview UIs (e.g. Instagram back control) do not overlap export captions.
            // Taller scrim so the header stays legible after we push the text below in-app preview chrome.
            let scrimBottom = h * 0.32
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.48).cgColor,
                    UIColor.black.withAlphaComponent(0.14).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray, locations: [0, 0.55, 1])!,
                start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: scrimBottom), options: []
            )

            let padX = max(56, w * 0.072)
            // Extra ~50pt downward shift so preview chrome (e.g. Instagram) clears the header block.
            let padY = max(88, h * 0.052) + 50
            let lineGap: CGFloat = 5

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = CGSize(width: 0, height: 1)

            let dayFont = UIFont.systemFont(ofSize: w * 0.052, weight: .bold)
            let dayAttribs: [NSAttributedString.Key: Any] = [
                .font: dayFont, .foregroundColor: UIColor.white, .shadow: shadow
            ]
            let dayStr = "DAY \(dayNumber)" as NSString
            let daySize = dayStr.size(withAttributes: dayAttribs)

            let dateFont = UIFont.systemFont(ofSize: w * 0.034, weight: .regular)
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                .shadow: shadow
            ]
            let dateStr = day.shortDateText as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let subtitle = day.placeStops.first?.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cityFont = UIFont.systemFont(ofSize: w * 0.030, weight: .regular)
            let cityAttribs: [NSAttributedString.Key: Any] = [
                .font: cityFont,
                .foregroundColor: UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.70),
                .shadow: shadow
            ]
            let cityStr = subtitle as NSString

            var y = padY
            dayStr.draw(at: CGPoint(x: padX, y: y), withAttributes: dayAttribs)
            y += daySize.height + lineGap
            dateStr.draw(at: CGPoint(x: padX, y: y), withAttributes: dateAttribs)
            y += dateSize.height + lineGap
            if !subtitle.isEmpty {
                cityStr.draw(at: CGPoint(x: padX, y: y), withAttributes: cityAttribs)
            }
        }
    }

    // MARK: - Focused Map with Place Info Overlay

    /// Loads images for the in-map thumbnail strip (large enough to stay sharp when tiles are scaled up on export).
    /// At most three tiles are drawn; `stop.includedPhotos.count` supplies the overflow `+N` hint.
    private static func loadThumbnailsForPlaceMapOverlay(stop: PlaceStop, maxCount: Int = 3) async -> [UIImage] {
        let photos = stop.includedPhotos.prefix(maxCount)
        let target = CGSize(width: 1200, height: 1200)
        var images: [UIImage] = []
        images.reserveCapacity(photos.count)
        for photo in photos {
            try? Task.checkCancellation()
            if let img = await loadPhoto(photo, targetSize: target) {
                images.append(img)
            }
        }
        return images
    }

    /// Aspect-fill rect for drawing a bitmap into a square cell.
    private static func mapOverlayAspectFillRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let sw = imageSize.width * scale
        let sh = imageSize.height * scale
        return CGRect(x: bounds.midX - sw / 2, y: bounds.midY - sh / 2, width: sw, height: sh)
    }

    /// One row of thumbnails: at most **three** tiles, generous spacing, `+N` on the dimmed third when this place has more than three photos.
    @discardableResult
    private static func drawMapOverlayThumbnailRow(
        images: [UIImage],
        totalPhotoCount: Int,
        origin: CGPoint,
        rowWidth: CGFloat,
        context: UIGraphicsImageRendererContext
    ) -> CGFloat {
        guard !images.isEmpty, rowWidth > 8 else { return 0 }

        let cg = context.cgContext
        let maxSlots = 3
        let displayCount = min(maxSlots, images.count)
        let overflowPastSlots = max(0, totalPhotoCount - maxSlots)
        let needsTrailingPill = overflowPastSlots > 0 && displayCount < maxSlots

        let spacing: CGFloat = max(12, min(20, rowWidth * 0.028))
        let gapBeforeBadge: CGFloat = needsTrailingPill ? 10 : 0
        let pillW: CGFloat = needsTrailingPill ? min(80, rowWidth * 0.18) : 0
        let availForThumbs = rowWidth - gapBeforeBadge - pillW
        guard availForThumbs > 8 else { return 0 }

        let minSide = max(72, rowWidth * 0.096)
        let maxSide = min(220, rowWidth * 0.28)
        let rawFit = (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount)
        var side = min(maxSide, max(minSide, rawFit))
        let thumbsWidthCheck = CGFloat(displayCount) * side + CGFloat(displayCount - 1) * spacing
        if thumbsWidthCheck > availForThumbs + 0.5 {
            side = max(44, (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount))
        }
        let thumbsWidth = CGFloat(displayCount) * side + CGFloat(displayCount - 1) * spacing

        let cornerR = side * 0.2
        let dimThird = displayCount >= maxSlots && overflowPastSlots > 0

        for i in 0..<displayCount {
            let x = origin.x + CGFloat(i) * (side + spacing)
            let cell = CGRect(x: x, y: origin.y, width: side, height: side)
            let img = images[i]
            cg.saveGState()
            UIBezierPath(roundedRect: cell, cornerRadius: cornerR).addClip()
            img.draw(in: mapOverlayAspectFillRect(imageSize: img.size, bounds: cell))
            cg.restoreGState()

            if dimThird, i == displayCount - 1 {
                UIColor.black.withAlphaComponent(0.42).setFill()
                UIBezierPath(roundedRect: cell, cornerRadius: cornerR).fill()
                let badgeFont = UIFont.systemFont(ofSize: min(22, max(13, side * 0.36)), weight: .bold)
                let str = "+\(overflowPastSlots)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: UIColor.white]
                let sz = str.size(withAttributes: attrs)
                str.draw(
                    at: CGPoint(x: cell.midX - sz.width / 2, y: cell.midY - sz.height / 2),
                    withAttributes: attrs
                )
            }

            UIColor.white.withAlphaComponent(dimThird && i == displayCount - 1 ? 0.65 : 0.45).setStroke()
            let border = UIBezierPath(roundedRect: cell, cornerRadius: cornerR)
            border.lineWidth = max(1, side * 0.04)
            border.stroke()
        }

        if needsTrailingPill {
            let pillFont = UIFont.systemFont(ofSize: min(15, max(11, side * 0.34)), weight: .bold)
            let str = "+\(overflowPastSlots)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: UIColor.white]
            let sz = str.size(withAttributes: attrs)
            let bx = origin.x + thumbsWidth + gapBeforeBadge
            let pillH = min(side, sz.height + 10)
            let pillDrawW = min(max(sz.width + 16, pillH * 1.55), pillW)
            let pill = CGRect(x: bx, y: origin.y + (side - pillH) / 2, width: pillDrawW, height: pillH)
            UIColor.white.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: pillH * 0.35).fill()
            UIColor.white.withAlphaComponent(0.5).setStroke()
            let outline = UIBezierPath(roundedRect: pill, cornerRadius: pillH * 0.35)
            outline.lineWidth = 1
            outline.stroke()
            str.draw(
                at: CGPoint(x: pill.midX - sz.width / 2, y: pill.midY - sz.height / 2),
                withAttributes: attrs
            )
        }

        return side + 6
    }

    private static func drawPlaceOverlayOnMap(
        mapImage: UIImage, stop: PlaceStop, markerNumber: Int, totalStops: Int, pixelSize: CGSize,
        photoThumbnails: [UIImage]
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            mapImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.92).cgColor,
                    UIColor.black.withAlphaComponent(0.75).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray, locations: [0, 0.45, 1])!,
                start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.38), options: []
            )

            let padX: CGFloat = 28
            let markerR: CGFloat = w * 0.052
            let contentY: CGFloat = h * 0.63

            let markerColor: UIColor = markerNumber == 1 ? .systemGreen
                : (markerNumber == totalStops ? .systemOrange : .systemBlue)
            let markerCenter = CGPoint(x: padX + markerR, y: contentY + markerR)
            let markerRect = CGRect(x: markerCenter.x - markerR, y: markerCenter.y - markerR,
                                    width: markerR * 2, height: markerR * 2)
            cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 12,
                         color: markerColor.withAlphaComponent(0.5).cgColor)
            cg.setFillColor(markerColor.cgColor)
            cg.fillEllipse(in: markerRect)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: markerRect)
            let numStr = "\(markerNumber)" as NSString
            let numFont = UIFont.systemFont(ofSize: markerR * 0.95, weight: .bold)
            let numAttribs: [NSAttributedString.Key: Any] = [.font: numFont, .foregroundColor: UIColor.white]
            let numSize = numStr.size(withAttributes: numAttribs)
            numStr.draw(at: CGPoint(x: markerCenter.x - numSize.width / 2,
                                    y: markerCenter.y - numSize.height / 2), withAttributes: numAttribs)

            let titleX = markerCenter.x + markerR + 14
            let titleFont = UIFont.systemFont(ofSize: w * 0.050, weight: .bold)
            let titleAttribs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.white]
            (stop.placeTitle as NSString).draw(
                in: CGRect(x: titleX, y: contentY, width: w - titleX - padX, height: titleFont.lineHeight * 2),
                withAttributes: titleAttribs
            )
            var nextY = contentY + titleFont.lineHeight + 4

            if let sub = stop.placeSubtitle, !sub.isEmpty {
                let subFont = UIFont.systemFont(ofSize: w * 0.032, weight: .regular)
                let subAttribs: [NSAttributedString.Key: Any] = [.font: subFont,
                                                                   .foregroundColor: UIColor.white.withAlphaComponent(0.72)]
                (sub as NSString).draw(at: CGPoint(x: titleX, y: nextY), withAttributes: subAttribs)
                nextY += subFont.lineHeight + 8
            }

            if let ts = formattedTimestamp(stop.visitedTimeDigitized) {
                let tsFont = UIFont.monospacedSystemFont(ofSize: w * 0.028, weight: .medium)
                let tsAttribs: [NSAttributedString.Key: Any] = [.font: tsFont, .foregroundColor: UIColor.white]
                let tsStr = ts as NSString
                let tsSize = tsStr.size(withAttributes: tsAttribs)
                let pH: CGFloat = 10, pV: CGFloat = 5
                let pillRect = CGRect(x: titleX, y: nextY,
                                      width: tsSize.width + pH * 2, height: tsSize.height + pV * 2)
                UIColor.white.withAlphaComponent(0.15).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2).fill()
                tsStr.draw(at: CGPoint(x: pillRect.minX + pH, y: pillRect.minY + pV), withAttributes: tsAttribs)
                nextY += pillRect.height + 12
            }

            // Place caption / notes — below time stamp, above photo strip (when present).
            let storyText = stop.noteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storyText.isEmpty {
                let storyFont = UIFont.systemFont(ofSize: w * 0.031, weight: .regular)
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 4
                para.lineBreakMode = .byTruncatingTail
                let storyAttribs: [NSAttributedString.Key: Any] = [
                    .font: storyFont,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                    .paragraphStyle: para
                ]
                let maxW = w - titleX - padX
                let maxH = storyFont.lineHeight * 3 + 8
                let fitted = (storyText as NSString).boundingRect(
                    with: CGSize(width: maxW, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs,
                    context: nil
                )
                let drawH = min(ceil(fitted.height), maxH)
                (storyText as NSString).draw(
                    with: CGRect(x: titleX, y: nextY, width: maxW, height: drawH),
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                    attributes: storyAttribs,
                    context: nil
                )
                nextY += drawH + 10
            }

            if !photoThumbnails.isEmpty {
                let rowWidth = w - titleX - padX
                let rowH = drawMapOverlayThumbnailRow(
                    images: photoThumbnails,
                    totalPhotoCount: stop.includedPhotos.count,
                    origin: CGPoint(x: titleX, y: nextY),
                    rowWidth: rowWidth,
                    context: ctx
                )
                nextY += rowH + 8
            }
        }
    }

    // MARK: - Photo Slide

    private static func drawPhotoSlide(
        _ photo: UIImage,
        caption: String?,
        placeName: String,
        timestampText: String,
        pixelSize: CGSize
    ) -> UIImage {
        let hasStory = !(caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            // Aspect-fill
            let photoAR = photo.size.width / max(photo.size.height, 1)
            let frameAR = w / h
            let drawRect: CGRect
            if photoAR > frameAR {
                let dh = h; let dw = dh * photoAR
                drawRect = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
            } else {
                let dw = w; let dh = dw / photoAR
                drawRect = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
            }
            photo.draw(in: drawRect)

            // Light top scrim — keeps the fixed-position clock readable on bright skies
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h * 0.16), options: []
            )

            // Bottom gradient — taller when story caption is present
            let gradEndFrac: CGFloat = hasStory ? 0.38 : 0.52
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.75).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * gradEndFrac), options: []
            )

            // Optional mid scrim when the place title sits over the image (no caption)
            if !hasStory {
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.clear.cgColor,
                        UIColor.black.withAlphaComponent(0.28).cgColor,
                        UIColor.clear.cgColor
                    ] as CFArray, locations: [0, 0.55, 1])!,
                    start: CGPoint(x: 0, y: h * 0.48),
                    end: CGPoint(x: 0, y: h * 0.78),
                    options: []
                )
            }

            let bottomSafeMargin: CGFloat = h * 0.14
            let maxW = w - 80
            let capTrimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let storyFont = UIFont.systemFont(ofSize: w * 0.042, weight: .medium)
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 5
            para.lineBreakMode = .byWordWrapping
            para.alignment = .center
            let storyAttribs: [NSAttributedString.Key: Any] = [
                .font: storyFont, .foregroundColor: UIColor.white, .paragraphStyle: para
            ]
            let capHeight: CGFloat = {
                guard hasStory, !capTrimmed.isEmpty else { return 0 }
                let measured = (capTrimmed as NSString).boundingRect(
                    with: CGSize(width: maxW, height: storyFont.lineHeight * 4 + 16),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs, context: nil
                )
                return ceil(measured.height)
            }()

            // Place + timestamp — top center stack, a bit lower than the old single timestamp (y ≈ 56)
            let placeFont = UIFont.systemFont(ofSize: w * 0.038, weight: .semibold)
            let placeStr = placeName as NSString
            let placeAttribs: [NSAttributedString.Key: Any] = [.font: placeFont, .foregroundColor: UIColor.white]
            let placeSize = placeStr.size(withAttributes: placeAttribs)
            let pPX: CGFloat = 16, pPY: CGFloat = 9
            let placePillW = min(placeSize.width + pPX * 2, w - 64)
            let placePillH = placeSize.height + pPY * 2
            let placePillX = (w - placePillW) / 2

            let tsFont = UIFont.monospacedDigitSystemFont(ofSize: w * 0.034, weight: .semibold)
            let tsStr = timestampText as NSString
            let tsAttribs: [NSAttributedString.Key: Any] = [.font: tsFont, .foregroundColor: UIColor.white]
            let tsSize = tsStr.size(withAttributes: tsAttribs)
            let tsPadH: CGFloat = 18, tsPadV: CGFloat = 10
            let tsPillW = min(tsSize.width + tsPadH * 2, w - 64)
            let tsPillH = tsSize.height + tsPadV * 2

            let pillStackGap: CGFloat = 10
            let reelTopChromePad: CGFloat = 50
            let topStackOriginY = max(72, h * 0.048) + reelTopChromePad
            let placePillY = topStackOriginY
            let placePillRect = CGRect(x: placePillX, y: placePillY, width: placePillW, height: placePillH)
            UIColor.black.withAlphaComponent(0.52).setFill()
            UIBezierPath(roundedRect: placePillRect, cornerRadius: placePillRect.height / 2).fill()
            placeStr.draw(
                in: CGRect(
                    x: placePillRect.minX + pPX,
                    y: placePillRect.minY + pPY,
                    width: placePillW - pPX * 2,
                    height: placeSize.height + 2
                ),
                withAttributes: placeAttribs
            )

            let tsPillRect = CGRect(x: (w - tsPillW) / 2, y: placePillRect.maxY + pillStackGap, width: tsPillW, height: tsPillH)
            drawGlassPillBackground(in: tsPillRect, cornerRadius: tsPillH * 0.5)
            tsStr.draw(
                at: CGPoint(x: tsPillRect.midX - tsSize.width / 2, y: tsPillRect.midY - tsSize.height / 2),
                withAttributes: tsAttribs
            )

            // Story caption last so it paints above the place pill when stacks are tight
            if hasStory, !capTrimmed.isEmpty, capHeight > 0 {
                let capRect = CGRect(
                    x: (w - maxW) / 2,
                    y: h - bottomSafeMargin - capHeight,
                    width: maxW,
                    height: capHeight
                )
                (capTrimmed as NSString).draw(
                    with: capRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs,
                    context: nil
                )
            }
        }
    }

    /// Frosted “glass” capsule: light fill + hairline edge (matches map-overlay pill language).
    private static func drawGlassPillBackground(in rect: CGRect, cornerRadius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        UIColor.white.withAlphaComponent(0.22).setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Helpers

    /// One cross-dissolve frame between two already-rendered images (`stepIndex` is 1...`blendStepCount`).
    /// No MKMapSnapshotter calls — pure pixel blending with smooth-step easing.
    /// When `imageA` and `imageB` share the same center (zoom-in), this looks like a smooth zoom.
    private static func synthesizeBlendFrame(
        from imageA: UIImage,
        to imageB: UIImage,
        stepIndex: Int,
        blendStepCount: Int,
        size: CGSize
    ) -> UIImage {
        let t = CGFloat(stepIndex) / CGFloat(blendStepCount + 1)
        let alpha = t * t * (3 - 2 * t) // smooth-step ease
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            imageA.draw(in: CGRect(origin: .zero, size: size))
            imageB.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: alpha)
        }
    }

    private static func formattedTimestamp(_ digitized: String?) -> String? {
        guard let digitized else { return nil }
        let parts = digitized.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let components = String(parts[1]).split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]), let minute = Int(components[1]) else { return nil }
        let ampm = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    /// `HH:mm` in the photo’s capture timezone: prefers stored EXIF-style `digitizedTime` wall clock,
    /// else formats `photo.timestamp` in the stop’s resolved place timezone (same rules as library import).
    private static func militaryTimeDisplayString(photo: RecapPhoto, placeTimeZone: TimeZone) -> String {
        if let hm = militaryHMFromDigitizedString(photo.digitizedTime) { return hm }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = placeTimeZone
        return f.string(from: photo.timestamp)
    }

    /// Parses `"yyyy:MM:dd HH:mm:ss"` and returns `HH:mm` using the hour/minute from the string (already local wall time).
    private static func militaryHMFromDigitizedString(_ digitized: String?) -> String? {
        guard let digitized else { return nil }
        let parts = digitized.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let timePart = String(parts[1])
        let components = timePart.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(String(components[0])),
              let minute = Int(String(components[1])),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// `targetSize` is in pixels so `PHImageManager` returns a full-resolution image.
    private static func loadPhoto(_ photo: RecapPhoto, targetSize: CGSize) async -> UIImage? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            if lid.hasPrefix(AppCapturePhotoService.prefix) {
                return AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            return await ImageLoader.shared.loadImage(assetIdentifier: lid, targetSize: targetSize)
        }
        guard let permanentURL = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !permanentURL.isEmpty else { return nil }
        do {
            let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: permanentURL)
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            return UIImage(data: data)
        } catch { return nil }
    }
}
