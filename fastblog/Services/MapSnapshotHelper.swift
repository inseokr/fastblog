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
    static func generateSnapshot(for placeStops: [PlaceStop], size: CGSize = CGSize(width: 600, height: 300), regionPadding: Double = 0.01) async -> UIImage? {
        // Build (displayNumber, coordinate, name) triples, preserving original ordering
        // so marker #2 on the map always matches place #2 in the blog.
        var indexedCoords: [(displayNumber: Int, coord: CLLocationCoordinate2D, name: String)] = []
        for (i, stop) in placeStops.enumerated() {
            if let loc = stop.representativeLocation {
                indexedCoords.append((displayNumber: i + 1, coord: loc.clCoordinate, name: stop.placeTitle))
            }
        }
        guard !indexedCoords.isEmpty else { return nil }

        let coords = indexedCoords.map(\.coord)
        var region = region(for: coords, padding: regionPadding)
        region = regionExpandedForPlaceNameLabels(region, placeNames: indexedCoords.map(\.name), mapSize: size)

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

            // 2. Draw Markers with the correct display number
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

                drawMarker(at: point, number: entry.displayNumber, name: entry.name, color: markerColor, context: context)
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

    /// Place names are drawn in a pill to the **right** of each pin (`drawMarker`). The bounding box of
    /// coordinates alone can leave the easternmost labels clipped; zoom out (mostly in longitude) so
    /// every pin + label fits inside the snapshot.
    private static func regionExpandedForPlaceNameLabels(_ region: MKCoordinateRegion, placeNames: [String], mapSize: CGSize) -> MKCoordinateRegion {
        guard mapSize.width > 1 else { return region }

        let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont]
        var maxLabelWidth: CGFloat = 0
        for name in placeNames where !name.isEmpty {
            maxLabelWidth = max(maxLabelWidth, (name as NSString).size(withAttributes: attrs).width)
        }
        // Circle radius 14 + gap 5 + horizontal pill padding 8 + a little breathing room at the map edge.
        let markerAndGap: CGFloat = 14 + 5 + 8 + 16
        let totalRightOverflowPx = maxLabelWidth + markerAndGap
        guard totalRightOverflowPx > 0 else { return region }

        // Fraction of the map width we need as extra longitude span so the rightmost pin isn't flush to the edge.
        let horizontalMarginFraction = (totalRightOverflowPx / mapSize.width) + 0.04

        var r = region
        let lonSpan = r.span.longitudeDelta
        let latSpan = r.span.latitudeDelta
        // Expand longitude so labels to the right of the easternmost stop stay on-screen; expand latitude
        // slightly so pins aren't flush to top/bottom when we zoom out horizontally.
        r.span.longitudeDelta = min(180, lonSpan * (1 + horizontalMarginFraction))
        let latBoost = 1 + horizontalMarginFraction * 0.35
        r.span.latitudeDelta = min(180, latSpan * latBoost)
        return r
    }
    
    /// Draws a numbered circle marker with a place name label to the right.
    private static func drawMarker(at point: CGPoint, number: Int, name: String, color: UIColor, context: CGContext) {
        let radius: CGFloat = 14.0
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)

        context.saveGState()

        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.4).cgColor)

        // Fill
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)

        // Stroke (clear shadow first)
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: rect)

        // Number text
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

        // Place name label — white pill with black text to the right of the circle
        if !name.isEmpty {
            let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor.black
            ]
            let labelSize = name.size(withAttributes: labelAttrs)
            let hPad: CGFloat = 4
            let vPad: CGFloat = 2
            let pillX = point.x + radius + 5
            let pillY = point.y - labelSize.height / 2 - vPad
            let pillRect = CGRect(x: pillX, y: pillY,
                                  width: labelSize.width + hPad * 2,
                                  height: labelSize.height + vPad * 2)

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                              color: UIColor.black.withAlphaComponent(0.2).cgColor)
            let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: 4)
            UIColor.white.withAlphaComponent(0.92).setFill()
            pillPath.fill()
            context.restoreGState()

            name.draw(at: CGPoint(x: pillX + hPad, y: pillY + vPad), withAttributes: labelAttrs)
        }
    }
}
