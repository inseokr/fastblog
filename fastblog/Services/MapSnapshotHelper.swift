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
        showPlaceNames: Bool = false,
        /// When set (e.g. `2` for video export), matches `ImageRenderer` / H.264 pixel scale; `nil` uses device screen scale.
        displayScale: CGFloat? = nil
    ) async -> UIImage? {
        // Build (displayNumber, coordinate, title) pairs, preserving original ordering
        // so marker #2 on the map always matches place #2 in the blog.
        var indexedCoords: [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String)] = []
        for (i, stop) in placeStops.enumerated() {
            if let loc = stop.representativeLocation {
                let c = loc.clCoordinate
                guard Self.isReasonableCoordinate(c) else { continue }
                indexedCoords.append((displayNumber: i + 1, coord: c, placeTitle: stop.placeTitle))
            }
        }
        guard !indexedCoords.isEmpty else { return nil }

        let coords = indexedCoords.map(\.coord)
        let computed = region(for: coords, padding: regionPadding)
        let region = validatedSnapshotRegion(computed, fallbackCenter: coords[0])

        let snapshotScale: CGFloat
        if let displayScale {
            snapshotScale = displayScale
        } else {
            snapshotScale = await MainActor.run { UIScreen.main.scale }
        }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = snapshotScale
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
        regionPadding: Double = 0.07,
        /// Carousel Studio day map: tighter zoom with the viewport pulled toward the first stop.
        carouselDayFirstStopFocus: Bool = false
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

            guard let unwrappedCoord = coord, Self.isReasonableCoordinate(unwrappedCoord) else { continue }

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

        // Carousel Studio day map: street-level zoom centered exactly on the first stop (START POI).
        let rawDisplayRegion: MKCoordinateRegion = {
            if carouselDayFirstStopFocus {
                let first = entries[0].coord
                let maxZoom = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
                return MKCoordinateRegion(center: first, span: maxZoom)
            }

            let baseRegion = region(for: coords, padding: regionPadding)

            // Inflate the span proportionally so the photo markers and their place-name
            // pills always stay comfortably inside the frame.  Markers take ~13 % of the
            // min canvas dimension and the pill sits just below them, so we need a
            // meaningful margin on every side regardless of how far apart the stops are.
            let markerFraction = Double(clampMarkerDiameter(size: size) / max(1, min(size.width, size.height)))
            let pillFraction = 0.05  // tighter than before so POI stay legible at street-block zoom
            // Multiplier >1 so both axes grow; applied to span, so padding scales with the trip size.
            let inflateFactor = 1.0 + (markerFraction + pillFraction) * 2.0
            let inflatedSpan = MKCoordinateSpan(
                latitudeDelta: baseRegion.span.latitudeDelta * inflateFactor,
                longitudeDelta: baseRegion.span.longitudeDelta * inflateFactor
            )
            let boundingRegion = MKCoordinateRegion(center: baseRegion.center, span: inflatedSpan)

            // Shift the viewport center toward the first stop so the day's opening location
            // sits prominently in frame.
            let first = entries[0].coord
            let biasedLat = boundingRegion.center.latitude
                + (first.latitude  - boundingRegion.center.latitude)  * 0.45
            let biasedLon = boundingRegion.center.longitude
                + (first.longitude - boundingRegion.center.longitude) * 0.45
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: biasedLat, longitude: biasedLon),
                span: boundingRegion.span
            )
        }()
        let displayRegion = validatedSnapshotRegion(rawDisplayRegion, fallbackCenter: entries[0].coord)

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

            // Carousel day map is centered on stop 1: paint stop 1 last so green START isn't covered by END.
            let markerDrawIndices: [Int] = {
                if carouselDayFirstStopFocus, entries.count > 1 {
                    return Array(1..<entries.count) + [0]
                }
                return Array(entries.indices)
            }()

            for i in markerDrawIndices {
                let entry = entries[i]
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

    // MARK: - Carousel Studio — place intro (matches cinematic focused-map framing)

    /// Included-photo coordinate for Carousel Studio snapshots when `representativeLocation` is missing.
    private static func coordinateForCarouselIncludedStop(stop: PlaceStop) -> CLLocationCoordinate2D? {
        let included = stop.photos.filter(\.isIncluded)
        guard !included.isEmpty else { return nil }
        guard let coord = stop.representativeLocation?.clCoordinate
            ?? included.first(where: { $0.location != nil })?.location?.clCoordinate
        else { return nil }
        guard isReasonableCoordinate(coord) else { return nil }
        return coord
    }

    private static func buildCarouselStudioMarkerEntries(
        drawableStops: [PlaceStop],
        focusedIndex: Int?
    ) -> [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String, isFocused: Bool)] {
        var entries: [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String, isFocused: Bool)] = []
        for (i, stop) in drawableStops.enumerated() {
            guard let coord = coordinateForCarouselIncludedStop(stop: stop) else { continue }
            let focused = focusedIndex.map { $0 == i } ?? false
            let seq = entries.count + 1
            entries.append((displayNumber: seq, coord: coord, placeTitle: stop.placeTitle, isFocused: focused))
        }
        return entries
    }

    /// Tight neighbourhood map highlighting one drawable stop (`UIScreen` scale). Other stops render as muted dots;
    /// the focused marker gets the cinematic halo plus an under-pin place-title pill — same decoration path as video export.
    static func generateCarouselPlaceIntroSnapshot(
        drawableDayStops: [PlaceStop],
        focusedDrawableIndex: Int,
        logicalSize: CGSize,
        displayScale: CGFloat? = nil
    ) async -> UIImage? {
        guard drawableDayStops.indices.contains(focusedDrawableIndex) else { return nil }
        guard let fc = coordinateForCarouselIncludedStop(stop: drawableDayStops[focusedDrawableIndex]) else {
            return nil
        }
        let entries = buildCarouselStudioMarkerEntries(
            drawableStops: drawableDayStops,
            focusedIndex: focusedDrawableIndex
        )
        guard !entries.isEmpty else { return nil }
        /// Tighter than the default snapshot floor (~110 m) so the block reads more zoomed-in.
        let zoomSpanDegrees = 0.001
        // Center the POI in the map half of the slide (no vertical bias).
        let mapCenter = CLLocationCoordinate2D(latitude: fc.latitude, longitude: fc.longitude)
        let tight = MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: zoomSpanDegrees, longitudeDelta: zoomSpanDegrees)
        )
        let region = validatedSnapshotRegion(tight, fallbackCenter: fc, minSpanFloor: zoomSpanDegrees)
        let shortest = min(logicalSize.width, logicalSize.height)
        // `drawPlaceNamePillUnderMarker` scales type from markerRadius; anchored well above legacy 14 so names read on export cards.
        let placeNameAnchorRadius = min(max(shortest * 0.086, 44), 78)
        let markerRadius = min(max(shortest * 0.056, 20), 30)
        return await renderMarkedSnapshot(
            region: region,
            entries: entries,
            logicalSize: logicalSize,
            displayScale: displayScale,
            showPlaceNamePillForFocused: true,
            showDistancePills: false,
            focusedMarkerTripRoleColors: false,
            focusedPlaceNameMarkerRadius: placeNameAnchorRadius,
            focusedMarkerRadius: markerRadius
        )
    }

    /// Degenerate / corrupt EXIF coords (NaN, non-finite lat/lon) or antimeridian spans will make
    /// `MKMapSnapshotOptions.setRegion` throw NSException — reject bad points up front.
    private static func isReasonableCoordinate(_ c: CLLocationCoordinate2D) -> Bool {
        guard c.latitude.isFinite, c.longitude.isFinite else { return false }
        return (-89.999...89.999).contains(c.latitude) && (-179.999...179.999).contains(c.longitude)
    }

    /// MapKit rejects non-finite, non-positive, or absurdly wide spans; clamps to snapshot-safe ranges.
    /// - Parameter minSpanFloor: Optional minimum lat/lon span; defaults to street-level (~220 m at mid-latitudes).
    private static func validatedSnapshotRegion(
        _ region: MKCoordinateRegion,
        fallbackCenter: CLLocationCoordinate2D,
        minSpanFloor: Double? = nil
    ) -> MKCoordinateRegion {
        let minLatDelta = minSpanFloor ?? 0.002
        let minLonDelta = minSpanFloor ?? 0.002
        /// Longitude diff from naive min/max can approach 360° when a route crosses the antimeridian;
        /// `setRegion:` throws far below that; keep the portrait within MapKit limits.
        let maxLatDelta = 160.0
        let maxLonDelta = 170.0

        let safeFallback = Self.isReasonableCoordinate(fallbackCenter)
            ? fallbackCenter
            : CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902)

        var lat = region.center.latitude
        var lon = region.center.longitude
        if !(lat.isFinite && lon.isFinite) || !Self.isReasonableCoordinate(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            lat = Self.clamp(safeFallback.latitude, -89.0...89.0)
            lon = Self.clamp(safeFallback.longitude, -179.0...179.0)
        }
        var latΔ = region.span.latitudeDelta
        var lonΔ = region.span.longitudeDelta
        if !(latΔ.isFinite && lonΔ.isFinite) || latΔ <= 0 || lonΔ <= 0 {
            latΔ = minLatDelta
            lonΔ = minLonDelta
        }
        latΔ = Self.clamp(latΔ, minLatDelta...maxLatDelta)
        lonΔ = Self.clamp(lonΔ, minLonDelta...maxLonDelta)

        lat = Self.clamp(lat, -89.0...89.0)
        lon = Self.clamp(lon, -179.0...179.0)

        let span = MKCoordinateSpan(latitudeDelta: latΔ, longitudeDelta: lonΔ)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: span)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }

    /// Calculates the bounding region for a set of coordinates with padding.
    private static func region(for coords: [CLLocationCoordinate2D], padding: Double = 0.01) -> MKCoordinateRegion {
        let filtered = coords.filter { isReasonableCoordinate($0) }
        guard let firstCoord = filtered.first else {
            let origin = coords.first ?? .init(latitude: 0, longitude: 0)
            let span = MKCoordinateSpan(latitudeDelta: max(0.05, padding * 2), longitudeDelta: max(0.05, padding * 2))
            return MKCoordinateRegion(center: origin, span: span)
        }

        if filtered.count == 1 {
            let coord = firstCoord
            let span = MKCoordinateSpan(latitudeDelta: max(0.05, padding * 2), longitudeDelta: max(0.05, padding * 2))
            return MKCoordinateRegion(center: coord, span: span)
        }

        let lats = filtered.map(\.latitude)
        let lons = filtered.map(\.longitude)
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
    private static func drawMarker(at point: CGPoint, number: Int, color: UIColor, context: CGContext, radius: CGFloat = 14) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)

        context.saveGState()

        let shadowBlur = max(4, radius * 0.28)
        context.setShadow(offset: CGSize(width: 0, height: max(2, radius * 0.14)), blur: shadowBlur,
                          color: UIColor.black.withAlphaComponent(0.4).cgColor)

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(max(2, radius * 0.14))
        context.strokeEllipse(in: rect)

        let text = "\(number)"
        let fontSize = max(11, min(radius * 0.96, 30))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        
        let stringSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (rect.midX - stringSize.width / 2).rounded(),
            y: (rect.midY - stringSize.height / 2).rounded(),
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
        let fontFloor = markerRadius >= 40 ? CGFloat(17) : CGFloat(13)
        let fontSize = max(fontFloor, markerRadius * 0.42).rounded()
        let padH = max(10, markerRadius * 0.34)
        let padV = max(5, markerRadius * 0.22)
        let relativeWidthCap: CGFloat = markerRadius >= 40 ? 0.58 : 0.44
        let maxLabelWidth = min(canvasSize.width * relativeWidthCap, markerRadius * 12)

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

        let pillRect = CGRect(
            x: originX.rounded(),
            y: originY.rounded(),
            width: labelW.rounded(),
            height: labelH.rounded()
        )

        context.saveGState()

        // White pill with a pronounced drop shadow for pop against the map.
        context.setShadow(
            offset: CGSize(width: 0, height: max(1, markerRadius * 0.1)),
            blur: max(3, markerRadius * 0.28),
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

    // MARK: - Cinematic video snapshot helpers

    /// Bounding region for every stop with a valid coordinate — same MapKit framing the PDF
    /// overview uses, for cinematic pans that start with **all** day markers in frame.
    static func regionBoundingAllStops(_ placeStops: [PlaceStop], padding: Double = 0.14) -> MKCoordinateRegion? {
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(placeStops.count)
        for stop in placeStops {
            guard let loc = stop.representativeLocation else { continue }
            let c = loc.clCoordinate
            guard isReasonableCoordinate(c) else { continue }
            coords.append(c)
        }
        guard let first = coords.first else { return nil }
        let computed = region(for: coords, padding: padding)
        return validatedSnapshotRegion(computed, fallbackCenter: first)
    }

    /// Zoomed-in map snapshot centered on a specific stop. Delegates to `renderMarkedSnapshot`.
    static func generateFocusedSnapshot(
        focusedStopIndex: Int,
        allStops: [PlaceStop],
        logicalSize: CGSize,
        displayScale: CGFloat? = nil,
        showPlaceNamePillForFocused: Bool = false
    ) async -> UIImage? {
        guard focusedStopIndex < allStops.count else { return nil }
        let focusedStop = allStops[focusedStopIndex]
        guard let focusedCoord = focusedStop.representativeLocation?.clCoordinate,
              isReasonableCoordinate(focusedCoord) else { return nil }

        let entries = buildMarkerEntries(allStops: allStops, focusedStopIndex: focusedStopIndex)
        guard !entries.isEmpty else { return nil }

        let focusedRegion = validatedSnapshotRegion(
            MKCoordinateRegion(center: focusedCoord, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)),
            fallbackCenter: focusedCoord
        )
        return await renderMarkedSnapshot(
            region: focusedRegion, entries: entries, logicalSize: logicalSize, displayScale: displayScale,
            showPlaceNamePillForFocused: showPlaceNamePillForFocused
        )
    }

    // MARK: - Animated transition / zoom frames (cinematic video)

    /// Streams interpolated map snapshots one at a time (flat memory). Prefer this over `generateInterpolatedFrames` for export.
    static func forEachInterpolatedFrame(
        from fromRegion: MKCoordinateRegion,
        to toRegion: MKCoordinateRegion,
        allStops: [PlaceStop],
        focusedStopIndex: Int,
        logicalSize: CGSize,
        displayScale: CGFloat?,
        frameCount: Int,
        /// When true, first frame matches `fromRegion` and last matches `toRegion` (good for zoom-in export).
        inclusiveEndpoints: Bool = false,
        showDistancePills: Bool = true,
        onFrame: (UIImage) async throws -> Void
    ) async throws {
        try await forEachInterpolatedFrame(
            from: fromRegion, to: toRegion,
            allStops: allStops,
            focusedStopIndexForFrame: { _ in focusedStopIndex },
            showPlaceNamePillForFrame: { _ in false },
            logicalSize: logicalSize, displayScale: displayScale,
            frameCount: frameCount, inclusiveEndpoints: inclusiveEndpoints,
            showDistancePills: showDistancePills,
            onFrame: onFrame
        )
    }

    /// Same as `forEachInterpolatedFrame(from:to:allStops:focusedStopIndex:...)` but marker focus and
    /// optional place-name pill under the focused marker can change per frame (cinematic hand-off between stops).
    static func forEachInterpolatedFrame(
        from fromRegion: MKCoordinateRegion,
        to toRegion: MKCoordinateRegion,
        allStops: [PlaceStop],
        focusedStopIndexForFrame: @escaping (Int) -> Int?,
        showPlaceNamePillForFrame: @escaping (Int) -> Bool,
        logicalSize: CGSize,
        displayScale: CGFloat?,
        frameCount: Int,
        inclusiveEndpoints: Bool = false,
        showDistancePills: Bool = true,
        onFrame: (UIImage) async throws -> Void
    ) async throws {
        guard !buildMarkerEntries(allStops: allStops, focusedStopIndex: nil).isEmpty else { return }

        for i in 0..<frameCount {
            try Task.checkCancellation()
            let t: Double
            if inclusiveEndpoints, frameCount > 1 {
                t = smoothStep(Double(i) / Double(frameCount - 1))
            } else {
                t = smoothStep(Double(i + 1) / Double(frameCount))
            }
            let lat = fromRegion.center.latitude  + (toRegion.center.latitude  - fromRegion.center.latitude)  * t
            let lon = fromRegion.center.longitude + (toRegion.center.longitude - fromRegion.center.longitude) * t
            let latΔ = fromRegion.span.latitudeDelta  + (toRegion.span.latitudeDelta  - fromRegion.span.latitudeDelta)  * t
            let lonΔ = fromRegion.span.longitudeDelta + (toRegion.span.longitudeDelta - fromRegion.span.longitudeDelta) * t
            let interpRegion = validatedSnapshotRegion(
                MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                   span: MKCoordinateSpan(latitudeDelta: latΔ, longitudeDelta: lonΔ)),
                fallbackCenter: toRegion.center
            )
            let focus = focusedStopIndexForFrame(i)
            let entries = buildMarkerEntries(allStops: allStops, focusedStopIndex: focus)
            guard !entries.isEmpty else { continue }
            let showPill = showPlaceNamePillForFrame(i)
            if let img = await renderMarkedSnapshot(
                region: interpRegion, entries: entries, logicalSize: logicalSize, displayScale: displayScale,
                showPlaceNamePillForFocused: showPill,
                showDistancePills: showDistancePills
            ) {
                try await onFrame(img)
            }
        }
    }

    /// Interpolates `frameCount` map snapshots from `fromRegion` to `toRegion` using a smooth-step
    /// curve. Prefer `forEachInterpolatedFrame` when memory must stay flat.
    static func generateInterpolatedFrames(
        from fromRegion: MKCoordinateRegion,
        to toRegion: MKCoordinateRegion,
        allStops: [PlaceStop],
        focusedStopIndex: Int,
        logicalSize: CGSize,
        frameCount: Int = 6,
        displayScale: CGFloat? = nil,
        inclusiveEndpoints: Bool = false
    ) async -> [UIImage] {
        var images: [UIImage] = []
        do {
            try await forEachInterpolatedFrame(
                from: fromRegion, to: toRegion,
                allStops: allStops, focusedStopIndexForFrame: { _ in focusedStopIndex },
                showPlaceNamePillForFrame: { _ in false },
                logicalSize: logicalSize, displayScale: displayScale, frameCount: frameCount,
                inclusiveEndpoints: inclusiveEndpoints
            ) { img in
                images.append(img)
            }
        } catch is CancellationError {
            // Return partial sequence (legacy behavior).
        } catch {
            debugPrint("[MapSnapshotHelper] generateInterpolatedFrames: \(error)")
        }
        return images
    }

    /// Convenience wrapper: pan from `fromRegion` toward `focusedCoord` arriving at 0.008° span.
    static func generateAnimatedTransitionFrames(
        from fromRegion: MKCoordinateRegion,
        to focusedCoord: CLLocationCoordinate2D,
        allStops: [PlaceStop],
        focusedStopIndex: Int,
        logicalSize: CGSize,
        frameCount: Int = 4,
        displayScale: CGFloat? = nil
    ) async -> [UIImage] {
        let toRegion = MKCoordinateRegion(
            center: focusedCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        return await generateInterpolatedFrames(
            from: fromRegion, to: toRegion,
            allStops: allStops, focusedStopIndex: focusedStopIndex,
            logicalSize: logicalSize, frameCount: frameCount, displayScale: displayScale
        )
    }

    /// Generates a marked map snapshot at a caller-specified region.
    /// Use this for the progressive zoom-in sequence at a destination.
    static func generateSnapshotAtRegion(
        region: MKCoordinateRegion,
        focusedStopIndex: Int,
        allStops: [PlaceStop],
        logicalSize: CGSize,
        displayScale: CGFloat? = nil,
        showPlaceNamePillForFocused: Bool = false,
        showFocusedMarker: Bool = true,
        showDistancePills: Bool = true
    ) async -> UIImage? {
        guard focusedStopIndex < allStops.count else { return nil }
        let entries = buildMarkerEntries(allStops: allStops, focusedStopIndex: focusedStopIndex)
        guard !entries.isEmpty else { return nil }
        let fallback = allStops[focusedStopIndex].representativeLocation?.clCoordinate
            ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902)
        let validRegion = validatedSnapshotRegion(region, fallbackCenter: fallback)
        return await renderMarkedSnapshot(
            region: validRegion, entries: entries, logicalSize: logicalSize, displayScale: displayScale,
            showPlaceNamePillForFocused: showPlaceNamePillForFocused,
            showFocusedMarker: showFocusedMarker,
            showDistancePills: showDistancePills
        )
    }

    /// Generates a transparent overlay image (same logical size/scale as a snapshot) containing only
    /// the focused-stop circle halo, coloured marker dot, and place-name pill — all drawn at a fixed
    /// size centered on the canvas.  Composite this over a map base during zoom frames so the overlay
    /// does not grow as the map is crop-scaled.
    static func generateFocusedMarkerOverlay(
        displayNumber: Int,
        totalCount: Int,
        title: String,
        logicalSize: CGSize,
        displayScale: CGFloat
    ) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(logicalSize, false, displayScale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }
        let center = CGPoint(x: logicalSize.width / 2, y: logicalSize.height / 2)
        let color: UIColor = displayNumber == 1 ? .systemGreen
            : (displayNumber == totalCount ? .systemOrange : .systemBlue)
        context.saveGState()
        context.setStrokeColor(color.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: center.x - 23, y: center.y - 23, width: 46, height: 46))
        context.restoreGState()
        drawMarker(at: center, number: displayNumber, color: color, context: context)
        drawPlaceNamePillUnderMarker(
            at: center, markerRadius: 14, title: title, context: context, canvasSize: logicalSize
        )
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    // MARK: - Shared marker snapshot helpers

    private static func buildMarkerEntries(
        allStops: [PlaceStop],
        focusedStopIndex: Int?
    ) -> [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String, isFocused: Bool)] {
        var entries: [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String, isFocused: Bool)] = []
        for (i, stop) in allStops.enumerated() {
            guard let loc = stop.representativeLocation else { continue }
            let c = loc.clCoordinate
            guard isReasonableCoordinate(c) else { continue }
            let focused = focusedStopIndex.map { $0 == i } ?? false
            entries.append((displayNumber: i + 1, coord: c, placeTitle: stop.placeTitle, isFocused: focused))
        }
        return entries
    }

    private static func renderMarkedSnapshot(
        region: MKCoordinateRegion,
        entries: [(displayNumber: Int, coord: CLLocationCoordinate2D, placeTitle: String, isFocused: Bool)],
        logicalSize: CGSize,
        displayScale: CGFloat? = nil,
        showPlaceNamePillForFocused: Bool = false,
        showFocusedMarker: Bool = true,
        showDistancePills: Bool = true,
        /// When true, focused marker is green for stop 1 and orange for the last stop (trip END).
        /// When false (Carousel place-intro), last stop stays blue so END styling never steals focus from START semantics.
        focusedMarkerTripRoleColors: Bool = true,
        /// Scales typography + paddings under the focused marker’s place-name pill (`nil` = legacy fixed value).
        focusedPlaceNameMarkerRadius: CGFloat? = nil,
        /// Radius of the numbered POI disk + halo (`nil` = legacy 14 pt).
        focusedMarkerRadius: CGFloat? = nil
    ) async -> UIImage? {
        let resolvedScale: CGFloat
        if let displayScale {
            resolvedScale = displayScale
        } else {
            resolvedScale = await MainActor.run { UIScreen.main.scale }
        }
        let opts = MKMapSnapshotter.Options()
        opts.region = region
        opts.size = logicalSize
        opts.scale = resolvedScale
        opts.mapType = .standard
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        do {
            let snapshot = try await MKMapSnapshotter(options: opts).start()
            UIGraphicsBeginImageContextWithOptions(snapshot.image.size, true, snapshot.image.scale)
            defer { UIGraphicsEndImageContext() }
            guard let context = UIGraphicsGetCurrentContext() else { return snapshot.image }
            context.interpolationQuality = .high
            snapshot.image.draw(at: .zero)

            // Dashed route polyline
            let allCoords = entries.map(\.coord)
            if allCoords.count >= 2 {
                context.saveGState()
                context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.4).cgColor)
                context.setLineWidth(3.0)
                context.setLineDash(phase: 0, lengths: [8, 5])
                context.beginPath()
                for (i, coord) in allCoords.enumerated() {
                    let pt = snapshot.point(for: coord)
                    if i == 0 { context.move(to: pt) } else { context.addLine(to: pt) }
                }
                context.strokePath()
                context.restoreGState()

                // Distance pills — one per segment, centred on the midpoint of each polyline leg.
                // Hidden when showDistancePills is false (animated video frames) or distance < 1 mile.
                if showDistancePills {
                    for i in 0..<(allCoords.count - 1) {
                        let distMeters = CLLocation(latitude: allCoords[i].latitude, longitude: allCoords[i].longitude)
                            .distance(from: CLLocation(latitude: allCoords[i + 1].latitude, longitude: allCoords[i + 1].longitude))
                        let distMiles = distMeters / 1609.344
                        guard distMiles >= 1.0 else { continue }
                        let ptA = snapshot.point(for: allCoords[i])
                        let ptB = snapshot.point(for: allCoords[i + 1])
                        let mid = CGPoint(x: (ptA.x + ptB.x) / 2, y: (ptA.y + ptB.y) / 2)
                        let distText = String(format: "%.1f mi", distMiles)
                        drawDistancePill(at: mid, text: distText, context: context, canvasSize: snapshot.image.size)
                    }
                }
            }

            let totalCount = entries.count
            for entry in entries {
                let pt = snapshot.point(for: entry.coord)
                if entry.isFocused && showFocusedMarker {
                    let color: UIColor = {
                        if focusedMarkerTripRoleColors {
                            if entry.displayNumber == 1 { return .systemGreen }
                            if entry.displayNumber == totalCount { return .systemOrange }
                            return .systemBlue
                        }
                        return entry.displayNumber == 1 ? .systemGreen : .systemBlue
                    }()
                    let markerR = focusedMarkerRadius ?? 14
                    let haloR = markerR * 1.64
                    context.saveGState()
                    context.setStrokeColor(color.withAlphaComponent(0.28).cgColor)
                    context.setLineWidth(max(2.5, markerR * 0.2))
                    context.strokeEllipse(in: CGRect(x: pt.x - haloR, y: pt.y - haloR, width: haloR * 2, height: haloR * 2))
                    context.restoreGState()
                    drawMarker(at: pt, number: entry.displayNumber, color: color, context: context, radius: markerR)
                    if showPlaceNamePillForFocused {
                        let pillRadius = focusedPlaceNameMarkerRadius ?? 14
                        drawPlaceNamePillUnderMarker(
                            at: pt,
                            markerRadius: pillRadius,
                            title: entry.placeTitle,
                            context: context,
                            canvasSize: snapshot.image.size
                        )
                    }
                } else {
                    drawSmallMutedMarker(at: pt, number: entry.displayNumber, context: context)
                }
            }
            return UIGraphicsGetImageFromCurrentImageContext() ?? snapshot.image
        } catch {
            debugPrint("[MapSnapshotHelper] renderMarkedSnapshot failed: \(error)")
            return nil
        }
    }

    private static func smoothStep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    /// Small black capsule pill with white text, centred at `point`. Used for per-segment distances.
    private static func drawDistancePill(at point: CGPoint, text: String, context: CGContext, canvasSize: CGSize) {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padH: CGFloat = 9
        let padV: CGFloat = 5
        let pillW = (textSize.width + padH * 2).rounded()
        let pillH = (textSize.height + padV * 2).rounded()
        let cornerRadius = pillH / 2

        let originX = (point.x - pillW / 2).rounded()
        let originY = (point.y - pillH / 2).rounded()

        let pillRect = CGRect(x: originX, y: originY, width: pillW, height: pillH)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 4,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius).cgPath
        context.addPath(path)
        context.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        let textRect = CGRect(
            x: pillRect.minX + padH,
            y: pillRect.minY + padV,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawSmallMutedMarker(at point: CGPoint, number: Int, context: CGContext) {
        let radius: CGFloat = 8
        context.saveGState()
        context.setFillColor(UIColor.systemGray.withAlphaComponent(0.55).cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        let numStr = "\(number)" as NSString
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let attribs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let sz = numStr.size(withAttributes: attribs)
        numStr.draw(
            at: CGPoint(x: (point.x - sz.width / 2).rounded(), y: (point.y - sz.height / 2).rounded()),
            withAttributes: attribs
        )
        context.restoreGState()
    }
}
