import Foundation
import MapKit
import UIKit
import SwiftUI

/// Generates static map images for PDF Export using MKMapSnapshotter and CGContext.
class MapSnapshotHelper {
    
    /// Generates a snapshot of the map for a given day's place stops.
    /// Draws the polyline route and numbered markers onto the resulting image.
    /// Marker numbers match each stop's 1-based position in the original array
    /// so they line up with the numbered list in the PDF.
    /// - Parameters:
    ///   - showPlaceNames: When true, draws each stop's `placeTitle` in a white pill
    ///     directly below its marker (Story Mode map pages — matches the Social Post
    ///     Studio map slide styling).
    static func generateSnapshot(
        for placeStops: [PlaceStop],
        size: CGSize = CGSize(width: 600, height: 300),
        regionPadding: Double = 0.01,
        showPlaceNames: Bool = false
    ) async -> UIImage? {
        // Build (displayNumber, coordinate, title) pairs, preserving original ordering
        // so marker #2 on the map always matches place #2 in the blog.
        var indexedCoords: [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String)] = []
        for (i, stop) in placeStops.enumerated() {
            if let loc = stop.representativeLocation {
                indexedCoords.append((displayNumber: i + 1, coord: loc.clCoordinate, placeTitle: stop.placeTitle))
            }
        }
        guard !indexedCoords.isEmpty else { return nil }

        let coords = indexedCoords.map(\.coord)
        let region = region(for: coords, padding: regionPadding)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = await MainActor.run { UIScreen.main.scale }
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()

            UIGraphicsBeginImageContextWithOptions(snapshot.image.size, true, snapshot.image.scale)
            defer { UIGraphicsEndImageContext() }

            guard let context = UIGraphicsGetCurrentContext() else { return snapshot.image }

            // Draw the base map
            snapshot.image.draw(at: .zero)

            // 1. Draw Polyline
            if coords.count >= 2 {
                context.saveGState()
                context.setStrokeColor(UIColor.systemBlue.cgColor)
                context.setLineWidth(4.0)
                context.setLineCap(.round)
                context.setLineJoin(.round)

                context.beginPath()
                for (i, coord) in coords.enumerated() {
                    let point = snapshot.point(for: coord)
                    if i == 0 {
                        context.move(to: point)
                    } else {
                        context.addLine(to: point)
                    }
                }
                context.strokePath()
                context.restoreGState()
            }

            // 2. Draw Markers with the correct display number (and optional place name)
            for (i, entry) in indexedCoords.enumerated() {
                let point = snapshot.point(for: entry.coord)

                let isFirst = (i == 0)
                let isLast = (i == indexedCoords.count - 1)

                let markerColor: UIColor
                if isFirst {
                    markerColor = .systemGreen
                } else if isLast {
                    markerColor = .systemOrange
                } else {
                    markerColor = .systemBlue
                }

                drawMarker(at: point, number: entry.displayNumber, color: markerColor, context: context)

                if showPlaceNames {
                    // Match the Social Post Studio map slide: white capsule pill directly
                    // under the marker. `drawMarker` uses a 14 pt radius.
                    drawPlaceNamePillUnderMarker(
                        at: point,
                        markerRadius: 14,
                        title: entry.placeTitle,
                        context: context,
                        canvasSize: snapshot.image.size
                    )
                }
            }

            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            return finalImage ?? snapshot.image

        } catch {
            debugPrint("[MapSnapshotHelper] Map snapshot failed: \(error)")
            return nil
        }
    }

    /// Static photo-route snapshot for Social Post Studio.
    /// - Photos: one circular photo marker per place (uses `markerImagesByStopId`).
    /// - Start / end: green **START** (or **START & END** if one stop) and orange **END** pills
    ///   above the photo, matching `MapDayView`; middle stops keep a numbered corner badge.
    /// - Labels: place name "pills" rendered *under* the photo markers.
    /// - Route stroke: always blue (matches the Studio requirement).
    static func generatePhotoRouteSnapshot(
        for placeStops: [PlaceStop],
        markerImagesByStopId: [UUID: UIImage],
        size: CGSize,
        regionPadding: Double = 0.07
    ) async -> UIImage? {
        // Keep ordering stable: route polyline + marker numbering follow the original placeStops order.
        struct MarkerEntry {
            let stopId: UUID
            let displayNumber: Int
            let coord: CLLocationCoordinate2D
            let placeTitle: String
            let markerImage: UIImage?
        }

        var entries: [MarkerEntry] = []
        entries.reserveCapacity(placeStops.count)

        var displayIndex = 0
        for stop in placeStops {
            let included = stop.includedPhotos
            guard !included.isEmpty else { continue }

            let coord: CLLocationCoordinate2D? = stop.representativeLocation?.clCoordinate
                ?? included.first(where: { $0.location != nil })?.location?.clCoordinate

            guard let unwrappedCoord = coord else { continue }

            displayIndex += 1
            entries.append(
                MarkerEntry(
                    stopId: stop.id,
                    displayNumber: displayIndex,
                    coord: unwrappedCoord,
                    placeTitle: stop.placeTitle,
                    markerImage: markerImagesByStopId[stop.id]
                )
            )
        }

        guard !entries.isEmpty else { return nil }

        let coords = entries.map(\.coord)
        let baseRegion = region(for: coords, padding: regionPadding)

        // Inflate the span proportionally so the photo markers and their place-name
        // pills always stay comfortably inside the frame.  Markers take ~13 % of the
        // min canvas dimension and the pill sits just below them, so we need a
        // meaningful margin on every side regardless of how far apart the stops are.
        let markerFraction = Double(clampMarkerDiameter(size: size) / max(1, min(size.width, size.height)))
        let pillFraction = 0.12  // approximate pill height + gap, as a fraction of min dimension
        // Multiplier >1 so both axes grow; applied to span, so padding scales with the trip size.
        let inflateFactor = 1.0 + (markerFraction + pillFraction) * 2.0
        let inflatedSpan = MKCoordinateSpan(
            latitudeDelta: baseRegion.span.latitudeDelta * inflateFactor,
            longitudeDelta: baseRegion.span.longitudeDelta * inflateFactor
        )
        let boundingRegion = MKCoordinateRegion(center: baseRegion.center, span: inflatedSpan)

        // Shift the viewport center 25 % toward the first stop so the start of the
        // route sits more prominently in frame.  The span is unchanged so all later
        // stops remain fully inside the snapshot.
        let displayRegion: MKCoordinateRegion = {
            let first = entries[0].coord
            let biasedLat = boundingRegion.center.latitude
                + (first.latitude  - boundingRegion.center.latitude)  * 0.25
            let biasedLon = boundingRegion.center.longitude
                + (first.longitude - boundingRegion.center.longitude) * 0.25
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: biasedLat, longitude: biasedLon),
                span: boundingRegion.span
            )
        }()

        let options = MKMapSnapshotter.Options()
        options.region = displayRegion
        options.size = size
        options.scale = await MainActor.run { UIScreen.main.scale }
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()

            UIGraphicsBeginImageContextWithOptions(snapshot.image.size, true, snapshot.image.scale)
            defer { UIGraphicsEndImageContext() }

            guard let context = UIGraphicsGetCurrentContext() else { return snapshot.image }

            // Draw the base map
            snapshot.image.draw(at: .zero)

            // 1) Draw the polyline route
            if coords.count >= 2 {
                // Scale line width with the canvas so it reads well at both preview and full export sizes.
                let routeLineWidth = max(4, size.width * 0.006)

                context.saveGState()
                context.setLineCap(.round)
                context.setLineJoin(.round)

                // Helper: build the route path.
                func addRoutePath() {
                    context.beginPath()
                    for (i, coord) in coords.enumerated() {
                        let point = snapshot.point(for: coord)
                        if i == 0 { context.move(to: point) } else { context.addLine(to: point) }
                    }
                }

                // White backing stroke — improves contrast on light map tiles.
                addRoutePath()
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.7).cgColor)
                context.setLineWidth(routeLineWidth + 4)
                context.strokePath()

                // Accent stroke on top.
                addRoutePath()
                context.setStrokeColor(UIColor(red: 0.22, green: 0.56, blue: 1.0, alpha: 1.0).cgColor)
                context.setLineWidth(routeLineWidth)
                context.strokePath()

                context.restoreGState()
            }

            // 2) Draw photo markers + place pills under markers
            let markerDiameter = clampMarkerDiameter(size: snapshot.image.size)
            let markerRadius = markerDiameter / 2

            for (i, entry) in entries.enumerated() {
                let isFirst = i == 0
                let isLast = i == entries.count - 1

                guard let image = entry.markerImage else { continue }

                let point = snapshot.point(for: entry.coord)
                let borderColor: UIColor = {
                    if isFirst { return .systemGreen }
                    if isLast { return .systemOrange }
                    return UIColor.systemBlue
                }()

                drawPhotoMarker(
                    at: point,
                    markerDiameter: markerDiameter,
                    image: image,
                    displayNumber: entry.displayNumber,
                    isFirst: isFirst,
                    isLast: isLast,
                    borderColor: borderColor,
                    canvasSize: snapshot.image.size,
                    context: context
                )

                drawPlaceNamePillUnderMarker(
                    at: point,
                    markerRadius: markerRadius,
                    title: entry.placeTitle,
                    context: context,
                    canvasSize: snapshot.image.size
                )
            }

            return UIGraphicsGetImageFromCurrentImageContext() ?? snapshot.image
        } catch {
            debugPrint("[MapSnapshotHelper] Photo route snapshot failed: \(error)")
            return nil
        }
    }
    
    /// Calculates the bounding region for a set of coordinates with padding.
    private static func region(for coords: [CLLocationCoordinate2D], padding: Double = 0.01) -> MKCoordinateRegion {
        if coords.count == 1 {
            let coord = coords[0]
            let span = MKCoordinateSpan(latitudeDelta: max(0.05, padding * 2), longitudeDelta: max(0.05, padding * 2))
            return MKCoordinateRegion(center: coord, span: span)
        }

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) + padding * 2),
            longitudeDelta: max(0.01, (maxLon - minLon) + padding * 2)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(center: center, span: span)
    }
    
    /// Draws a neat little numbered circle marker onto the map.
    private static func drawMarker(at point: CGPoint, number: Int, color: UIColor, context: CGContext) {
        let radius: CGFloat = 14.0
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        
        context.saveGState()
        
        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        
        // Fill
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
        
        // Stroke
        context.setShadow(offset: .zero, blur: 0, color: nil) // remove shadow for stroke
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: rect)
        
        // Text
        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        
        let stringSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.midX - stringSize.width / 2,
            y: rect.midY - stringSize.height / 2,
            width: stringSize.width,
            height: stringSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        
        context.restoreGState()
    }

    private static func clampMarkerDiameter(size: CGSize) -> CGFloat {
        // Scaled generously so markers read clearly at both full export (1080 px) and
        // the small in-app preview (~260 px), where the image is scaled down ~4×.
        let raw = min(size.width, size.height) * 0.13
        return min(max(raw, 64), 140)
    }

    private static func drawPhotoMarker(
        at center: CGPoint,
        markerDiameter: CGFloat,
        image: UIImage,
        displayNumber: Int,
        isFirst: Bool,
        isLast: Bool,
        borderColor: UIColor,
        canvasSize: CGSize,
        context: CGContext
    ) {
        let radius = markerDiameter / 2
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: markerDiameter, height: markerDiameter)

        context.saveGState()

        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.4).cgColor)

        // Photo clipped circle
        context.addEllipse(in: rect)
        context.clip()
        image.draw(in: rect)

        // Restore clip so border + badge can draw normally.
        context.restoreGState()

        // Border stroke
        context.saveGState()
        context.addEllipse(in: rect)
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(3.0)
        context.strokePath()
        context.restoreGState()

        // Match `MapDayView.PlaceMarkerView`: START / END (or START & END) pills above the
        // photo for endpoints; numbered navy badge only for middle stops.
        if isFirst || isLast {
            let pillText: String
            let fill: UIColor
            if isFirst && isLast {
                pillText = "START & END"
                fill = .systemGreen
            } else if isFirst {
                pillText = "START"
                fill = .systemGreen
            } else {
                pillText = "END"
                fill = .systemOrange
            }
            drawStartEndPillAbovePhotoMarker(
                photoCircleRect: rect,
                text: pillText,
                fillColor: fill,
                canvasSize: canvasSize,
                context: context
            )
        } else {
            drawOrderNumberBadgeOnPhoto(
                photoCircleRect: rect,
                number: displayNumber,
                markerDiameter: markerDiameter,
                context: context
            )
        }
    }

    /// Green / orange capsule above the circular photo — same role as `startEndBadge` in `MapDayView`.
    private static func drawStartEndPillAbovePhotoMarker(
        photoCircleRect: CGRect,
        text: String,
        fillColor: UIColor,
        canvasSize: CGSize,
        context: CGContext
    ) {
        let markerRadius = photoCircleRect.width / 2
        let fontSize = max(10, min(markerRadius * 0.36, 22))
        let padH = max(7, markerRadius * 0.28)
        let padV = max(3, markerRadius * 0.14)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let labelW = size.width + padH * 2
        let labelH = size.height + padV * 2
        let cornerRadius = labelH / 2
        let gap = max(4, markerRadius * 0.12)

        let margin = max(6, markerRadius * 0.2)
        var originX = photoCircleRect.midX - labelW / 2
        originX = min(max(originX, margin), canvasSize.width - margin - labelW)

        var originY = photoCircleRect.minY - gap - labelH
        if originY < margin {
            originY = margin
        }

        let pillRect = CGRect(x: originX, y: originY, width: labelW, height: labelH)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: max(1, markerRadius * 0.08)),
            blur: max(3, markerRadius * 0.25),
            color: UIColor.black.withAlphaComponent(0.4).cgColor
        )
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius).cgPath
        context.addPath(path)
        context.setFillColor(fillColor.withAlphaComponent(0.95).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(max(1, markerRadius * 0.06))
        context.addPath(path)
        context.strokePath()

        let drawTextRect = CGRect(
            x: pillRect.minX + padH,
            y: pillRect.minY + padV,
            width: pillRect.width - padH * 2,
            height: pillRect.height - padV * 2
        )
        (text as NSString).draw(in: drawTextRect, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawOrderNumberBadgeOnPhoto(
        photoCircleRect: CGRect,
        number: Int,
        markerDiameter: CGFloat,
        context: CGContext
    ) {
        let badgeRadius = max(10, markerDiameter * 0.22)
        let badgeCenter = CGPoint(
            x: photoCircleRect.minX + badgeRadius * 0.9,
            y: photoCircleRect.minY + badgeRadius * 0.9
        )
        let badgeRect = CGRect(
            x: badgeCenter.x - badgeRadius,
            y: badgeCenter.y - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        )

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                          color: UIColor.black.withAlphaComponent(0.5).cgColor)
        context.setFillColor(UIColor(red: 0.04, green: 0.06, blue: 0.18, alpha: 0.92).cgColor)
        context.addEllipse(in: badgeRect)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(max(1.5, badgeRadius * 0.12))
        context.addEllipse(in: badgeRect)
        context.strokePath()

        let text = "\(number)"
        let font = UIFont.systemFont(ofSize: badgeRadius * 0.92, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let drawRect = CGRect(
            x: badgeCenter.x - textSize.width / 2,
            y: badgeCenter.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: drawRect, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawPlaceNamePillUnderMarker(
        at markerCenter: CGPoint,
        markerRadius: CGFloat,
        title: String,
        context: CGContext,
        canvasSize: CGSize
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Scale typography and spacing proportionally with the marker so everything
        // looks consistent whether rendering a small preview or a full 1080 px export.
        let fontSize = max(13, markerRadius * 0.42)
        let padH = max(10, markerRadius * 0.34)
        let padV = max(5, markerRadius * 0.22)
        let maxLabelWidth = min(canvasSize.width * 0.44, markerRadius * 10)

        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        // Dark text on white pill — legible on any map style.
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(white: 0.1, alpha: 1.0),
            .paragraphStyle: paragraph
        ]

        let measured = (trimmed as NSString).boundingRect(
            with: CGSize(width: maxLabelWidth, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs,
            context: nil
        )

        let labelW = min(ceil(measured.width) + padH * 2, maxLabelWidth + padH * 2)
        let labelH = ceil(measured.height) + padV * 2
        // True capsule — radius equals half the height.
        let cornerRadius = labelH / 2

        let margin = max(8, markerRadius * 0.3)
        var originX = markerCenter.x - labelW / 2
        originX = min(max(originX, margin), canvasSize.width - margin - labelW)

        let verticalGap = max(5, markerRadius * 0.22)
        var originY = markerCenter.y + markerRadius + verticalGap
        if originY + labelH > canvasSize.height - margin {
            originY = markerCenter.y - markerRadius - verticalGap - labelH
        }

        let pillRect = CGRect(x: originX, y: originY, width: labelW, height: labelH)

        context.saveGState()

        // White pill with a pronounced drop shadow for pop against the map.
        context.setShadow(
            offset: CGSize(width: 0, height: max(1, markerRadius * 0.1)),
            blur: max(4, markerRadius * 0.35),
            color: UIColor.black.withAlphaComponent(0.42).cgColor
        )
        let bgPath = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius).cgPath
        context.addPath(bgPath)
        context.setFillColor(UIColor.white.withAlphaComponent(0.94).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // Label text
        let drawTextRect = CGRect(
            x: pillRect.minX + padH,
            y: pillRect.minY + padV,
            width: pillRect.width - padH * 2,
            height: pillRect.height - padV * 2
        )
        (trimmed as NSString).draw(
            with: drawTextRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs,
            context: nil
        )

        context.restoreGState()
    }
}
