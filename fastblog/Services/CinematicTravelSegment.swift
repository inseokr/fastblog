// fastblog/Services/CinematicTravelSegment.swift
import UIKit
import MapKit
import CoreLocation

// MARK: - TravelMode

enum TravelMode: String, Codable, CaseIterable, Equatable {
    case walking  // < 500 m  →  figure.walk
    case driving  // 500 m – 50 km  →  car.fill
    case taxi     // manual  →  car.rear.fill
    case bus      // manual  →  bus.fill
    case train    // manual  →  tram.fill
    case subway   // manual  →  tram.tunnel.fill
    case flying   // > 50 km  →  airplane (Bezier arc)

    /// Auto-detects walking / driving / flying based on distance.
    /// Bus and train are never auto-detected — they require an explicit user choice.
    static func detect(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> TravelMode {
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        if meters < 500 { return .walking }
        if meters < 50_000 { return .driving }
        return .flying
    }

    var sfSymbolName: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        case .taxi:    return "car.rear.fill"
        case .bus:     return "bus.fill"
        case .train:   return "tram.fill"
        case .subway:  return "tram.tunnel.fill"
        case .flying:  return "airplane"
        }
    }

    var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .driving: return "Car"
        case .taxi:    return "Taxi"
        case .bus:     return "Bus"
        case .train:   return "Train"
        case .subway:  return "Subway"
        case .flying:  return "Airplane"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .walking: return .systemGreen
        case .driving: return UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
        case .taxi:    return UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1)
        case .bus:     return UIColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1)
        case .train:   return UIColor(red: 0.80, green: 0.35, blue: 0.15, alpha: 1)
        case .subway:  return UIColor(red: 0.55, green: 0.20, blue: 0.90, alpha: 1)
        case .flying:  return UIColor(red: 0.22, green: 0.56, blue: 1.0, alpha: 1)
        }
    }

    var animationSeconds: Double {
        switch self {
        case .walking: return 1.5
        case .driving: return 2.0
        case .taxi:    return 2.0
        case .bus:     return 2.0
        case .train:   return 2.2
        case .subway:  return 2.0
        case .flying:  return 2.8
        }
    }

    static let fps: Double = 20
}

// MARK: - CinematicTravelSegment

enum CinematicTravelSegment {

    // MARK: - Constants

    private static let trailAlpha: CGFloat = 0.28
    private static let trailLineWidth: CGFloat = 5   // relative to pixelSize.width * factor
    private static let activePathLineWidth: CGFloat = 8
    private static let dayRecapTotalSeconds: Double = 2.2
    private static let dayRecapFPS: Double = 20

    // MARK: - Region helpers

    /// Bounding map region that shows both `a` and `b` with padding scaled to travel mode.
    static func travelRegion(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        mode: TravelMode
    ) -> MKCoordinateRegion {
        let minLat = min(a.latitude, b.latitude)
        let maxLat = max(a.latitude, b.latitude)
        let minLon = min(a.longitude, b.longitude)
        let maxLon = max(a.longitude, b.longitude)
        let padFactor: Double = mode == .flying ? 0.65 : 0.55
        let latSpan = max(0.008, maxLat - minLat) * (1 + padFactor * 2)
        let lonSpan = max(0.008, maxLon - minLon) * (1 + padFactor * 2)
        let minSpan: Double
        switch mode {
        case .walking:         minSpan = 0.005
        case .driving, .taxi:  minSpan = 0.018
        case .bus, .subway:    minSpan = 0.018
        case .train:           minSpan = 0.040
        case .flying:          minSpan = 0.8
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(160, max(minSpan, latSpan)),
                                   longitudeDelta: min(170, max(minSpan, lonSpan)))
        )
    }

    // MARK: - Bezier arc helpers (quadratic; control point arced above the mid-point)

    static func arcControlPoint(from p0: CGPoint, to p2: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (p0.x + p2.x) / 2, y: (p0.y + p2.y) / 2)
        let dx = p2.x - p0.x, dy = p2.y - p0.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.1 else { return mid }
        let perpX = -dy / len, perpY = dx / len
        // Lift toward the top of the screen (negative Y) by choosing the sign of the
        // perpendicular that points upward.
        let sign: CGFloat = perpY <= 0 ? 1 : -1
        let lift = len * 0.30
        return CGPoint(x: mid.x + sign * perpX * lift, y: mid.y + sign * perpY * lift)
    }

    static func quadBezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    /// Tangent angle (radians) at parameter `t` on the quadratic Bezier.
    static func quadBezierTangentAngle(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGFloat {
        let mt = 1 - t
        let tx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
        let ty = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        return atan2(ty, tx)
    }

    // MARK: - Vehicle icon

    private static func drawVehicle(
        mode: TravelMode,
        at center: CGPoint,
        angle: CGFloat,
        pixelWidth: CGFloat,
        context: CGContext
    ) {
        let radius = pixelWidth * 0.046
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)

        // White circle with coloured shadow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 10,
                          color: UIColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: circleRect)
        context.restoreGState()

        // Coloured border
        context.setStrokeColor(mode.tintColor.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(max(2, radius * 0.12))
        context.strokeEllipse(in: circleRect)

        // SF Symbol inside, rotated to face direction of travel
        let iconPt = radius * 0.95
        guard let rawImage = UIImage(
            systemName: mode.sfSymbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: iconPt, weight: .semibold)
        ) else { return }
        let tinted = rawImage.withTintColor(mode.tintColor, renderingMode: .alwaysOriginal)

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)

        switch mode {
        case .flying:
            // Rotate airplane to face direction of travel.
            context.rotate(by: angle)
        case .walking, .driving, .taxi, .bus, .train, .subway:
            // Flip horizontally when moving leftward so the icon faces the right way.
            if cos(angle) < 0 { context.scaleBy(x: -1, y: 1) }
        }

        tinted.draw(in: CGRect(x: -iconPt / 2, y: -iconPt / 2, width: iconPt, height: iconPt))
        context.restoreGState()
    }

    // MARK: - Single travel frame composite

    private static func buildTravelFrame(
        baseImage: UIImage,
        snapshot: MKMapSnapshotter.Snapshot,
        fromPt: CGPoint,               // snapshot logical-space point
        toPt: CGPoint,
        mode: TravelMode,
        revealProgress: CGFloat,       // 0…1 how much of the path is drawn
        vehicleProgress: CGFloat,      // 0…1 position of vehicle along path
        visitedTrailCoords: [CLLocationCoordinate2D],
        pixelSize: CGSize
    ) -> UIImage {
        // Convert from snapshot logical space → pixelSize drawing space.
        let snapshotW = max(1, snapshot.image.size.width)
        let scale = pixelSize.width / snapshotW
        let toPixel = { (pt: CGPoint) -> CGPoint in
            CGPoint(x: pt.x * scale, y: pt.y * scale)
        }
        let fromPx = toPixel(fromPt)
        let toPx   = toPixel(toPt)
        let ctrlPx = arcControlPoint(from: fromPx, to: toPx)

        let lineW = max(3, pixelSize.width * 0.006)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.interpolationQuality = .high
            cg.setShouldAntialias(true)

            // --- Base map (fills frame) ---
            baseImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            // --- Persistent trail: all previously visited stop connections ---
            if visitedTrailCoords.count >= 2 {
                let pts = visitedTrailCoords.map { toPixel(snapshot.point(for: $0)) }
                cg.saveGState()
                cg.setStrokeColor(UIColor.systemBlue.withAlphaComponent(trailAlpha).cgColor)
                cg.setLineWidth(lineW * 0.7)
                cg.setLineDash(phase: 0, lengths: [lineW * 1.5, lineW])
                cg.setLineCap(.round)
                cg.beginPath()
                for (i, pt) in pts.enumerated() {
                    if i == 0 { cg.move(to: pt) } else { cg.addLine(to: pt) }
                }
                cg.strokePath()
                cg.restoreGState()
            }

            // --- Current segment path reveal ---
            let p = min(1, max(0, revealProgress))
            guard p > 0.001 else { return }

            cg.saveGState()
            cg.setLineWidth(lineW)
            cg.setLineCap(.round)
            cg.setStrokeColor(mode.tintColor.cgColor)

            if mode == .flying {
                // Quadratic Bezier arc revealed up to parameter `p`
                let steps = max(2, Int(p * 32))
                cg.beginPath()
                cg.move(to: fromPx)
                for i in 1...steps {
                    let t = p * CGFloat(i) / CGFloat(steps)
                    cg.addLine(to: quadBezierPoint(t: t, p0: fromPx, p1: ctrlPx, p2: toPx))
                }
                cg.strokePath()
            } else {
                // Straight line
                let endPt = CGPoint(x: fromPx.x + (toPx.x - fromPx.x) * p,
                                    y: fromPx.y + (toPx.y - fromPx.y) * p)
                cg.beginPath()
                cg.move(to: fromPx)
                cg.addLine(to: endPt)
                cg.strokePath()
            }
            cg.restoreGState()

            // --- Vehicle icon at head of path ---
            let vp = min(1, max(0.001, vehicleProgress))
            let vehiclePos: CGPoint
            let vehicleAngle: CGFloat
            if mode == .flying {
                vehiclePos = quadBezierPoint(t: vp, p0: fromPx, p1: ctrlPx, p2: toPx)
                vehicleAngle = quadBezierTangentAngle(t: vp, p0: fromPx, p1: ctrlPx, p2: toPx)
            } else {
                vehiclePos = CGPoint(x: fromPx.x + (toPx.x - fromPx.x) * vp,
                                     y: fromPx.y + (toPx.y - fromPx.y) * vp)
                vehicleAngle = atan2(toPx.y - fromPx.y, toPx.x - fromPx.x)
            }
            drawVehicle(mode: mode, at: vehiclePos, angle: vehicleAngle,
                        pixelWidth: pixelSize.width, context: cg)
        }
    }

    // MARK: - Main travel transition

    /// Replaces the plain photo→map cross-dissolve with a travel animation.
    /// Returns the last emitted frame so the caller can chain it into the next transition.
    @discardableResult
    static func emitTravelTransitionFrames(
        fromImage: UIImage,
        fromStop: PlaceStop,
        toStop: PlaceStop,
        visitedTrailCoords: [CLLocationCoordinate2D],
        modeOverride: TravelMode? = nil,
        logicalSize: CGSize,
        pixelSize: CGSize,
        displayScale: CGFloat,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws -> UIImage? {
        guard let fromCoord = fromStop.representativeLocation?.clCoordinate,
              let toCoord   = toStop.representativeLocation?.clCoordinate,
              fromCoord.latitude.isFinite, fromCoord.longitude.isFinite,
              toCoord.latitude.isFinite,   toCoord.longitude.isFinite else { return nil }

        let mode = modeOverride ?? TravelMode.detect(from: fromCoord, to: toCoord)
        let region = travelRegion(from: fromCoord, to: toCoord, mode: mode)

        guard let (baseImage, snapshot) = await MapSnapshotHelper.generateSnapshotForTravel(
            region: region,
            travelStops: [fromStop, toStop],
            fromStopIndex: 0,
            toStopIndex: 1,
            logicalSize: logicalSize,
            displayScale: displayScale
        ) else { return nil }

        let fromPt = snapshot.point(for: fromCoord)
        let toPt   = snapshot.point(for: toCoord)

        let totalDuration = mode.animationSeconds
        let totalFrames   = max(14, Int(totalDuration * TravelMode.fps))
        let dt            = totalDuration / Double(totalFrames)

        // Phase split: dissolve-in 25% | path animation 60% | hold 15%
        let dissolveFrames = max(6, totalFrames / 4)
        let holdFrames     = max(3, totalFrames * 15 / 100)
        let animFrames     = totalFrames - dissolveFrames - holdFrames

        // Phase 1 — dissolve from fromImage to base travel map
        for fi in 0..<dissolveFrames {
            try Task.checkCancellation()
            let t = easeInOutCubic(CGFloat(fi + 1) / CGFloat(dissolveFrames))
            let frame = autoreleasepool {
                blendImages(from: fromImage, to: baseImage, progress: t, size: pixelSize)
            }
            try await frameHandler(frame, dt)
        }

        // Phase 2 — path reveal + vehicle movement
        for fi in 0..<animFrames {
            try Task.checkCancellation()
            let rawT = animFrames > 1 ? CGFloat(fi) / CGFloat(animFrames - 1) : 1
            let t    = easeInOutCubic(rawT)
            let frame = autoreleasepool {
                buildTravelFrame(
                    baseImage: baseImage, snapshot: snapshot,
                    fromPt: fromPt, toPt: toPt,
                    mode: mode, revealProgress: t, vehicleProgress: t,
                    visitedTrailCoords: visitedTrailCoords, pixelSize: pixelSize
                )
            }
            try await frameHandler(frame, dt)
        }

        // Phase 3 — hold at fully revealed
        let lastFrame = autoreleasepool {
            buildTravelFrame(
                baseImage: baseImage, snapshot: snapshot,
                fromPt: fromPt, toPt: toPt,
                mode: mode, revealProgress: 1, vehicleProgress: 1,
                visitedTrailCoords: visitedTrailCoords, pixelSize: pixelSize
            )
        }
        for _ in 0..<holdFrames {
            try Task.checkCancellation()
            try await frameHandler(lastFrame, dt)
        }

        return lastFrame
    }

    // MARK: - Day recap flyover

    /// End-of-day summary: the day overview map with all stops' connections drawing in sequence.
    /// Starts by dissolving from `fromImage` (the last emitted frame) to the day overview map.
    /// Returns the last emitted frame.
    @discardableResult
    static func emitDayRecapFlyover(
        fromImage: UIImage,
        dayStops: [PlaceStop],
        logicalSize: CGSize,
        pixelSize: CGSize,
        displayScale: CGFloat,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws -> UIImage? {
        let coords: [CLLocationCoordinate2D] = dayStops.compactMap {
            guard let c = $0.representativeLocation?.clCoordinate,
                  c.latitude.isFinite, c.longitude.isFinite else { return nil }
            return c
        }
        guard coords.count >= 2 else { return nil }

        guard let region = MapSnapshotHelper.regionBoundingAllStops(dayStops, padding: 0.20) else { return nil }
        let safeRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(latitudeDelta: min(160, max(0.005, region.span.latitudeDelta)),
                                   longitudeDelta: min(170, max(0.005, region.span.longitudeDelta)))
        )

        guard let (baseImage, snapshot) = await MapSnapshotHelper.generateSnapshotForTravel(
            region: safeRegion,
            travelStops: dayStops,
            fromStopIndex: 0,
            toStopIndex: dayStops.count - 1,
            logicalSize: logicalSize,
            displayScale: displayScale
        ) else { return nil }

        let snapshotW = max(1, snapshot.image.size.width)
        let scale = pixelSize.width / snapshotW
        let pixelCoords = coords.map { c -> CGPoint in
            let pt = snapshot.point(for: c)
            return CGPoint(x: pt.x * scale, y: pt.y * scale)
        }

        let segCount    = coords.count - 1
        let totalSecs   = dayRecapTotalSeconds
        let dissolveIn  = totalSecs * 0.18
        let animSecs    = totalSecs * 0.62
        let holdSecs    = totalSecs * 0.20

        let perSegSecs  = animSecs / Double(segCount)
        let perSegFrames = max(5, Int(perSegSecs * dayRecapFPS))
        let perSegDt    = perSegSecs / Double(perSegFrames)

        // Dissolve in to base map
        let dissolveFrames = max(6, Int(dissolveIn * dayRecapFPS))
        let dissolveDt     = dissolveIn / Double(dissolveFrames)
        for fi in 0..<dissolveFrames {
            try Task.checkCancellation()
            let t = easeInOutCubic(CGFloat(fi + 1) / CGFloat(dissolveFrames))
            let frame = autoreleasepool {
                blendImages(from: fromImage, to: baseImage, progress: t, size: pixelSize)
            }
            try await frameHandler(frame, dissolveDt)
        }

        // Animate each segment appearing in sequence
        for segIdx in 0..<segCount {
            try Task.checkCancellation()
            let fromPx = pixelCoords[segIdx]
            let toPx   = pixelCoords[segIdx + 1]

            for fi in 0..<perSegFrames {
                try Task.checkCancellation()
                let t = easeInOutCubic(CGFloat(fi + 1) / CGFloat(perSegFrames))
                let frame = autoreleasepool {
                    buildRecapFrame(
                        baseImage: baseImage,
                        pixelCoords: pixelCoords,
                        revealedSegments: segIdx,
                        currentFromPx: fromPx, currentToPx: toPx,
                        currentSegReveal: t,
                        pixelSize: pixelSize
                    )
                }
                try await frameHandler(frame, perSegDt)
            }
        }

        // Hold — all connections fully drawn
        let finalFrame = autoreleasepool {
            buildRecapFrame(
                baseImage: baseImage, pixelCoords: pixelCoords,
                revealedSegments: segCount,
                currentFromPx: .zero, currentToPx: .zero,
                currentSegReveal: 0, pixelSize: pixelSize
            )
        }
        try await frameHandler(finalFrame, holdSecs)
        return finalFrame
    }

    private static func buildRecapFrame(
        baseImage: UIImage,
        pixelCoords: [CGPoint],
        revealedSegments: Int,
        currentFromPx: CGPoint,
        currentToPx: CGPoint,
        currentSegReveal: CGFloat,
        pixelSize: CGSize
    ) -> UIImage {
        let lineW = max(4, pixelSize.width * 0.006)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.interpolationQuality = .high
            baseImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            // Fully revealed segments
            if revealedSegments > 0 {
                cg.saveGState()
                cg.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.80).cgColor)
                cg.setLineWidth(lineW)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.beginPath()
                cg.move(to: pixelCoords[0])
                for i in 1...min(revealedSegments, pixelCoords.count - 1) {
                    cg.addLine(to: pixelCoords[i])
                }
                cg.strokePath()
                cg.restoreGState()
            }

            // Current segment partially revealed
            let p = min(1, max(0, currentSegReveal))
            if p > 0.001 {
                let endPt = CGPoint(x: currentFromPx.x + (currentToPx.x - currentFromPx.x) * p,
                                    y: currentFromPx.y + (currentToPx.y - currentFromPx.y) * p)
                cg.saveGState()
                cg.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.80).cgColor)
                cg.setLineWidth(lineW)
                cg.setLineCap(.round)
                cg.beginPath()
                cg.move(to: currentFromPx)
                cg.addLine(to: endPt)
                cg.strokePath()

                // Moving dot at the path head
                let dotR = lineW * 2.0
                cg.setFillColor(UIColor.systemBlue.cgColor)
                cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                             color: UIColor.black.withAlphaComponent(0.4).cgColor)
                cg.fillEllipse(in: CGRect(x: endPt.x - dotR, y: endPt.y - dotR,
                                          width: dotR * 2, height: dotR * 2))
                cg.restoreGState()
            }

            // Destination marker dots for revealed stops
            let maxRevealed = min(revealedSegments, pixelCoords.count - 1)
            for i in 0...max(0, maxRevealed) {
                guard i < pixelCoords.count else { break }
                let pt = pixelCoords[i]
                let dotR = lineW * 2.2
                let color: UIColor = i == 0 ? .systemGreen
                    : (i == pixelCoords.count - 1 ? .systemOrange : .systemBlue)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 4,
                             color: UIColor.black.withAlphaComponent(0.35).cgColor)
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: pt.x - dotR, y: pt.y - dotR,
                                          width: dotR * 2, height: dotR * 2))
                cg.restoreGState()
            }
        }
    }

    // MARK: - Shared helpers

    static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        let u = min(1, max(0, t))
        if u < 0.5 { return 4 * u * u * u }
        let v = 2 * u - 2
        return 1 + v * v * v / 2
    }

    static func blendImages(from a: UIImage, to b: UIImage, progress: CGFloat, size: CGSize) -> UIImage {
        let u = min(1, max(0, progress))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            a.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: 1 - u)
            b.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: u)
        }
    }
}
