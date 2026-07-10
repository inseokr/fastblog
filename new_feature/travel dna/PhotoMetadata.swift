//
//  PhotoMetadata.swift
//  KS2-13 caption experiment — photo metadata (capture time + GPS → place name)
//
//  Reads capture time and GPS from a photo and turns them into a short text line that the
//  caption paths inject into the model prompt. All model work stays on-device; only the
//  optional reverse-geocode (coordinate → place name) makes a network call (see note below).
//
//  Two sources:
//    - PHAsset  : asset.creationDate / asset.location   (needs Photos permission)
//    - file URI : EXIF {DateTimeOriginal} / GPS dict via ImageIO (in-app camera captures)
//

import Foundation
import CoreLocation
import ImageIO
import Photos

struct PhotoMetadata: Equatable {
    var captureDate: Date?
    var coordinate: CLLocationCoordinate2D?
    var placeName: String?          // reverse-geocoded, e.g. "Han River, Seoul, South Korea"

    static let empty = PhotoMetadata()

    static func == (l: PhotoMetadata, r: PhotoMetadata) -> Bool {
        l.captureDate == r.captureDate &&
        l.coordinate?.latitude == r.coordinate?.latitude &&
        l.coordinate?.longitude == r.coordinate?.longitude &&
        l.placeName == r.placeName
    }

    /// Coarse time-of-day, mirrors Bloggo's daypart idea.
    var daypart: String? {
        guard let d = captureDate else { return nil }
        let h = Calendar.current.component(.hour, from: d)
        switch h {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }

    /// One-line context for the model prompt. Omits any missing field. Empty string if nothing known.
    func promptContext() -> String {
        var parts: [String] = []
        if let date = captureDate {
            let df = DateFormatter()
            df.dateFormat = "MMMM yyyy"
            var when = df.string(from: date)
            if let dp = daypart { when += ", \(dp)" }
            parts.append("Captured: \(when)")
        }
        if let place = placeName, !place.isEmpty {
            parts.append("Location: \(place)")
        } else if let c = coordinate {
            parts.append(String(format: "Location: %.4f, %.4f", c.latitude, c.longitude))
        }
        return parts.joined(separator: ". ")
    }

    /// Short suffix for the ① template path, e.g. " — Seoul, June 2026".
    func templateSuffix() -> String {
        var bits: [String] = []
        if let place = placeName, !place.isEmpty { bits.append(place) }
        if let date = captureDate {
            let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
            bits.append(df.string(from: date))
        }
        return bits.isEmpty ? "" : " — " + bits.joined(separator: ", ")
    }
}

// MARK: - Extraction

enum PhotoMetadataService {

    /// From a Photos library asset (has time + GPS directly).
    static func extract(from asset: PHAsset, reverseGeocode: Bool = true) async -> PhotoMetadata {
        var meta = PhotoMetadata()
        meta.captureDate = asset.creationDate
        if let loc = asset.location {
            meta.coordinate = loc.coordinate
            if reverseGeocode {
                meta.placeName = await placeName(for: loc)
            }
        }
        return meta
    }

    /// From an in-app capture file (reads EXIF/GPS if present).
    static func extract(fromFileURL url: URL, reverseGeocode: Bool = true) async -> PhotoMetadata {
        var meta = PhotoMetadata()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return meta }

        // Date from EXIF DateTimeOriginal ("yyyy:MM:dd HH:mm:ss").
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let df = DateFormatter(); df.dateFormat = "yyyy:MM:dd HH:mm:ss"
            meta.captureDate = df.date(from: s)
        }

        // GPS.
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            let coord = CLLocationCoordinate2D(latitude: latRef == "S" ? -lat : lat,
                                               longitude: lonRef == "W" ? -lon : lon)
            meta.coordinate = coord
            if reverseGeocode {
                meta.placeName = await placeName(for: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            }
        }
        return meta
    }

    // MARK: - Reverse geocoding (coordinate → place name)

    /// NETWORK CALL. Apple CLGeocoder works globally (US + Korea + everywhere).
    /// Routing note: Kakao Local API only returns addresses INSIDE Korea, so for a KR coordinate
    /// you may swap in Bloggo's KakaoLocalService for richer local names; for US/other, keep Apple.
    static func placeName(for location: CLLocation) async -> String? {
        // If you want the Kakao route for Korea, branch here on isInKorea(location) and call
        // KakaoLocalService; otherwise fall through to Apple CLGeocoder (global).
        await withCheckedContinuation { cont in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                guard let p = placemarks?.first else { cont.resume(returning: nil); return }
                // Build "Sublocality, City, Country" dropping nils.
                let parts = [p.subLocality ?? p.name, p.locality, p.country]
                    .compactMap { $0 }
                    .reduce(into: [String]()) { acc, s in if !acc.contains(s) { acc.append(s) } }
                cont.resume(returning: parts.isEmpty ? nil : parts.joined(separator: ", "))
            }
        }
    }

    /// Rough Korea bounding box, if you want to route KR → Kakao.
    static func isInKorea(_ location: CLLocation) -> Bool {
        let c = location.coordinate
        return (33.0...39.6).contains(c.latitude) && (124.5...132.0).contains(c.longitude)
    }
}
