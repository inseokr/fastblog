// fastblog/Services/CinematicBlogVideoBuilder.swift
import UIKit
import Foundation
import MapKit

/// Builds the cinematic video frame sequence and streams each frame to the caller via
/// `frameHandler` so memory stays flat (one frame live at a time).
///
/// Per-place visual sequence:
///   1. Pan animation  — 14 true snapshots × 0.18 s (≈ 5.5 fps) — segment-fit → 0.008° at destination
///   2. Zoom-in        — 2 snapshots + 12 synthesized cross-dissolve frames × 0.14 s (≈ 7 fps)
///                       Dissolve from 0.008° → 0.003° looks like a smooth zoom (center is fixed)
///   3. Focused reveal — 0.003° with place info overlaid at bottom (2.5 s)
///   4. Photo slides   — full-pixel images, story panel when caption is non-empty
enum CinematicBlogVideoBuilder {

    // MARK: - Entry point

    /// Generates frames in order and calls `frameHandler(image, duration)` for each.
    /// The handler is expected to write the frame to video immediately; the image is
    /// released once the handler returns.
    static func buildFrames(
        from draft: RecapBlogDetail,
        logicalSize: CGSize,
        secondsPerPhoto: Double,
        progressHandler: ((Double) -> Void)? = nil,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws {
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
        let days = draft.days.filter { !$0.placeStops.isEmpty }
        let totalDays = Double(max(days.count, 1))

        for (dayIdx, day) in days.enumerated() {
            guard !Task.isCancelled else { return }

            // Day intro card
            try await frameHandler(
                autoreleasepool { drawDayIntroCard(day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize) },
                2.0
            )

            let stops = day.placeStops

            // Full route overview map
            if let routeMap = await MapSnapshotHelper.generateSnapshot(
                for: stops, size: logicalSize, regionPadding: 0.05, showPlaceNames: true
            ) {
                let annotated = autoreleasepool {
                    drawDayHeaderOverlay(on: routeMap, day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize)
                }
                try await frameHandler(annotated, 2.5)
            }

            var previousCoord: CLLocationCoordinate2D? = nil

            for (placeIdx, stop) in stops.enumerated() {
                guard !Task.isCancelled else { return }

                if let focusedCoord = stop.representativeLocation?.clCoordinate,
                   focusedCoord.latitude.isFinite, focusedCoord.longitude.isFinite {

                    let panFromRegion = segmentRegion(from: previousCoord, to: focusedCoord, padding: 0.04)
                    let wideRegion  = MKCoordinateRegion(center: focusedCoord,
                                                         span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
                    let tightRegion = MKCoordinateRegion(center: focusedCoord,
                                                         span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))

                    // 1. Pan: 14 true snapshots × 0.18 s ≈ 5.5 fps
                    let panFrames = await MapSnapshotHelper.generateInterpolatedFrames(
                        from: panFromRegion, to: wideRegion,
                        allStops: stops, focusedStopIndex: placeIdx,
                        logicalSize: logicalSize, frameCount: 14
                    )
                    for img in panFrames {
                        guard !Task.isCancelled else { return }
                        try await frameHandler(img, 0.18)
                    }

                    // 2. Zoom-in: 2 snapshots + 12 synthesized cross-dissolve frames ≈ 7 fps
                    //    Dissolving from 0.008° → 0.003° (same center) looks like a smooth zoom.
                    if let wideImg = await MapSnapshotHelper.generateSnapshotAtRegion(
                        region: wideRegion, focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize
                    ) {
                        try await frameHandler(wideImg, 0.14)

                        var tightBase = await MapSnapshotHelper.generateSnapshotAtRegion(
                            region: tightRegion, focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize
                        )
                        if tightBase == nil {
                            tightBase = await MapSnapshotHelper.generateFocusedSnapshot(
                                focusedStopIndex: placeIdx, allStops: stops, logicalSize: logicalSize
                            )
                        }

                        if let tightBase {
                            // 12 free synthesized frames — no snapshotter calls
                            let blends = synthesizeBlendFrames(from: wideImg, to: tightBase,
                                                               count: 12, size: pixelSize)
                            for img in blends {
                                guard !Task.isCancelled else { return }
                                try await frameHandler(img, 0.14)
                            }

                            // 3. Tight reveal with place overlay (hold 2.5 s)
                            let overlaid = autoreleasepool {
                                drawPlaceOverlayOnMap(mapImage: tightBase, stop: stop,
                                                      markerNumber: placeIdx + 1, totalStops: stops.count,
                                                      pixelSize: pixelSize)
                            }
                            try await frameHandler(overlaid, 2.5)
                        }
                    }

                    previousCoord = focusedCoord
                }

                // 4. Photo slides — one at a time, released after each write
                for photo in stop.includedPhotos.prefix(5) {
                    guard !Task.isCancelled else { return }
                    if let img = await loadPhoto(photo, targetSize: pixelSize) {
                        let slide = autoreleasepool {
                            drawPhotoSlide(img, caption: photo.caption,
                                           placeName: stop.placeTitle, pixelSize: pixelSize)
                        }
                        try await frameHandler(slide, secondsPerPhoto)
                    }
                }
            }

            progressHandler?(Double(dayIdx + 1) / totalDays)
        }
    }

    // MARK: - Segment region

    /// Bounding region for the A→B travel segment, capped at 0.20° to stay city-scale.
    private static func segmentRegion(
        from fromCoord: CLLocationCoordinate2D?,
        to toCoord: CLLocationCoordinate2D,
        padding: Double = 0.04
    ) -> MKCoordinateRegion {
        guard let from = fromCoord else {
            return MKCoordinateRegion(center: toCoord,
                                      span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
        }
        let minLat = min(from.latitude, toCoord.latitude)
        let maxLat = max(from.latitude, toCoord.latitude)
        let minLon = min(from.longitude, toCoord.longitude)
        let maxLon = max(from.longitude, toCoord.longitude)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: min(0.20, max(0.03, (maxLat - minLat) + padding * 2)),
                longitudeDelta: min(0.20, max(0.03, (maxLon - minLon) + padding * 2))
            )
        )
    }

    // MARK: - Day Intro Card

    private static func drawDayIntroCard(day: RecapBlogDay, dayNumber: Int, pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor(red: 5/255, green: 10/255, blue: 48/255, alpha: 1).cgColor,
                    UIColor(red: 2/255, green: 5/255, blue: 30/255, alpha: 1).cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h), options: []
            )

            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: w * 0.15, y: h * 0.45))
            cg.addLine(to: CGPoint(x: w * 0.85, y: h * 0.45))
            cg.strokePath()

            let dayStr = "DAY \(dayNumber)" as NSString
            let dayFont = UIFont.systemFont(ofSize: w * 0.082, weight: .black)
            let dayAttribs: [NSAttributedString.Key: Any] = [.font: dayFont, .foregroundColor: UIColor.white, .kern: w * 0.008]
            let daySize = dayStr.size(withAttributes: dayAttribs)
            dayStr.draw(at: CGPoint(x: (w - daySize.width) / 2, y: h * 0.36), withAttributes: dayAttribs)

            let dateFont = UIFont.systemFont(ofSize: w * 0.04, weight: .medium)
            let dateAttribs: [NSAttributedString.Key: Any] = [.font: dateFont,
                                                               .foregroundColor: UIColor.white.withAlphaComponent(0.65)]
            let dateStr = day.dayStoryDateLine as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)
            dateStr.draw(at: CGPoint(x: (w - dateSize.width) / 2, y: h * 0.50), withAttributes: dateAttribs)

            if let subtitle = day.placeStops.first?.placeSubtitle, !subtitle.isEmpty {
                let cityFont = UIFont.systemFont(ofSize: w * 0.034, weight: .regular)
                let cityAttribs: [NSAttributedString.Key: Any] = [
                    .font: cityFont,
                    .foregroundColor: UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.75)
                ]
                let cityStr = subtitle as NSString
                let citySize = cityStr.size(withAttributes: cityAttribs)
                cityStr.draw(at: CGPoint(x: (w - citySize.width) / 2, y: h * 0.565), withAttributes: cityAttribs)
            }
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

            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.65).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h * 0.28), options: []
            )

            let dayFont = UIFont.systemFont(ofSize: w * 0.058, weight: .bold)
            let dayAttribs: [NSAttributedString.Key: Any] = [.font: dayFont, .foregroundColor: UIColor.white]
            let dayStr = "DAY \(dayNumber)" as NSString
            let daySize = dayStr.size(withAttributes: dayAttribs)
            dayStr.draw(at: CGPoint(x: 22, y: 28), withAttributes: dayAttribs)

            let dateFont = UIFont.systemFont(ofSize: w * 0.036, weight: .regular)
            let dateAttribs: [NSAttributedString.Key: Any] = [.font: dateFont,
                                                               .foregroundColor: UIColor.white.withAlphaComponent(0.82)]
            (day.shortDateText as NSString).draw(at: CGPoint(x: 22, y: 28 + daySize.height + 4),
                                                 withAttributes: dateAttribs)
        }
    }

    // MARK: - Focused Map with Place Info Overlay

    private static func drawPlaceOverlayOnMap(
        mapImage: UIImage, stop: PlaceStop, markerNumber: Int, totalStops: Int, pixelSize: CGSize
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

            // Place story / notes
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
                (storyText as NSString).draw(
                    with: CGRect(x: titleX, y: nextY, width: maxW, height: maxH),
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                    attributes: storyAttribs, context: nil
                )
            }
        }
    }

    // MARK: - Photo Slide

    private static func drawPhotoSlide(
        _ photo: UIImage, caption: String?, placeName: String, pixelSize: CGSize
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

            // Top gradient — contrast backing for place name pill
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h * 0.22), options: []
            )

            // Bottom gradient — taller when story caption is present
            let gradEndFrac: CGFloat = hasStory ? 0.38 : 0.52
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.75).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * gradEndFrac), options: []
            )

            // Place name pill — centered at top, clear of status bar / crop
            let placeFont = UIFont.systemFont(ofSize: w * 0.038, weight: .semibold)
            let placeStr = placeName as NSString
            let placeAttribs: [NSAttributedString.Key: Any] = [.font: placeFont, .foregroundColor: UIColor.white]
            let placeSize = placeStr.size(withAttributes: placeAttribs)
            let pPX: CGFloat = 16, pPY: CGFloat = 9
            let pillW = min(placeSize.width + pPX * 2, w - 64)
            let pillRect = CGRect(x: (w - pillW) / 2, y: 72,
                                   width: pillW, height: placeSize.height + pPY * 2)
            UIColor.black.withAlphaComponent(0.52).setFill()
            UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2).fill()
            placeStr.draw(in: CGRect(x: pillRect.minX + pPX, y: pillRect.minY + pPY,
                                      width: pillW - pPX * 2, height: placeSize.height + 2),
                          withAttributes: placeAttribs)

            // Story caption — centered, with 14% bottom safe margin (clears social platform UI chrome)
            if hasStory, let cap = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                let storyFont = UIFont.systemFont(ofSize: w * 0.042, weight: .medium)
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 5
                para.lineBreakMode = .byWordWrapping
                para.alignment = .center
                let storyAttribs: [NSAttributedString.Key: Any] = [
                    .font: storyFont, .foregroundColor: UIColor.white, .paragraphStyle: para
                ]
                let maxW = w - 80
                let measured = (cap as NSString).boundingRect(
                    with: CGSize(width: maxW, height: storyFont.lineHeight * 4 + 16),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs, context: nil
                )
                let bottomSafeMargin: CGFloat = h * 0.14
                let capRect = CGRect(x: (w - maxW) / 2,
                                      y: h - bottomSafeMargin - ceil(measured.height),
                                      width: maxW, height: ceil(measured.height))
                (cap as NSString).draw(with: capRect,
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        attributes: storyAttribs, context: nil)
            }
        }
    }

    // MARK: - Helpers

    /// Synthesizes `count` cross-dissolve frames between two already-rendered images.
    /// No MKMapSnapshotter calls — pure pixel blending with smooth-step easing.
    /// When `imageA` and `imageB` share the same center (zoom-in), this looks like a smooth zoom.
    private static func synthesizeBlendFrames(
        from imageA: UIImage,
        to imageB: UIImage,
        count: Int,
        size: CGSize
    ) -> [UIImage] {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return (1...count).map { i in
            let t  = CGFloat(i) / CGFloat(count + 1)
            let alpha = t * t * (3 - 2 * t)           // smooth-step ease
            return autoreleasepool {
                renderer.image { _ in
                    imageA.draw(in: CGRect(origin: .zero, size: size))
                    imageB.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: alpha)
                }
            }
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
