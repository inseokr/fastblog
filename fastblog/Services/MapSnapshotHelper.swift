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
    ///   - showPlaceNames: When true, draws each stop's `placeTitle` beside its marker (Story Mode map pages).
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
        options.scale = UIScreen.main.scale
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

                if showPlaceNames {
                    drawPlaceNameLabel(
                        besideMarkerCenter: point,
                        title: entry.placeTitle,
                        context: context,
                        canvasSize: snapshot.image.size
                    )
                }

                drawMarker(at: point, number: entry.displayNumber, color: markerColor, context: context)
            }

            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            return finalImage ?? snapshot.image

        } catch {
            debugPrint("[MapSnapshotHelper] Map snapshot failed: \(error)")
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

    /// Renders a truncated place title in a pill anchored to a marker.
    private static func drawPlaceNameLabel(
        besideMarkerCenter point: CGPoint,
        title: String,
        context: CGContext,
        canvasSize: CGSize
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let markerRadius: CGFloat = 14
        let maxLabelWidth = min(240, canvasSize.width * 0.42)
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]
        let textRect = (trimmed as NSString).boundingRect(
            with: CGSize(width: maxLabelWidth, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let padH: CGFloat = 8
        let padV: CGFloat = 4
        let labelW = min(textRect.width + padH * 2, maxLabelWidth + padH * 2)
        let labelH = ceil(textRect.height) + padV * 2
        // Prefer placing label to the right, otherwise flip to the left to keep clear marker-to-label alignment.
        let rightOriginX = point.x + markerRadius + 6
        let leftOriginX = point.x - markerRadius - 6 - labelW
        let fitsRight = rightOriginX + labelW <= canvasSize.width - 8
        let fitsLeft = leftOriginX >= 8
        let isRightSide: Bool
        var originX: CGFloat
        if fitsRight || (!fitsLeft && point.x <= canvasSize.width * 0.5) {
            isRightSide = true
            originX = rightOriginX
        } else {
            isRightSide = false
            originX = leftOriginX
        }
        var origin = CGPoint(x: originX, y: point.y - labelH / 2)

        // Keep label inside the image.
        let margin: CGFloat = 8
        if origin.x + labelW > canvasSize.width - margin {
            origin.x = max(margin, canvasSize.width - margin - labelW)
        }
        origin.y = min(max(origin.y, margin), canvasSize.height - margin - labelH)

        let bgRect = CGRect(origin: origin, size: CGSize(width: labelW, height: labelH))
        context.saveGState()

        // Draw a tiny connector so the label clearly points to the marker.
        let connectorStartX = isRightSide ? point.x + markerRadius : point.x - markerRadius
        let connectorEndX = isRightSide ? bgRect.minX : bgRect.maxX
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: connectorStartX, y: point.y))
        context.addLine(to: CGPoint(x: connectorEndX, y: point.y))
        context.strokePath()

        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 6).cgPath
        context.addPath(path)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        let drawTextRect = CGRect(
            x: origin.x + padH,
            y: origin.y + padV,
            width: labelW - padH * 2,
            height: labelH - padV * 2
        )
        (trimmed as NSString).draw(
            with: drawTextRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        context.restoreGState()
    }
}
