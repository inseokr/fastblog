import Foundation
import UIKit
import ImageIO
import CoreLocation

/// Real photo loader — no fake image generation.
/// Drag a "TripPhotos" folder (blue folder reference) of your 20 photos into the Xcode project;
/// it reads each photo's EXIF capture time and GPS as-is and feeds the pipeline.
/// ⚠️ Screenshots / messenger-saved copies have their EXIF stripped — prefer original HEIC/JPEG.
enum TripPhotoLoader {

    static func load() -> [PhotoItem] {
        var urls: [URL] = []
        let exts = ["jpg", "jpeg", "png", "heic", "heif", "JPG", "JPEG", "PNG", "HEIC", "HEIF"]
        for ext in exts {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "TripPhotos") ?? []
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        urls = Array(Set(urls)).sorted { $0.lastPathComponent < $1.lastPathComponent }

        var items: [PhotoItem] = []
        for (index, url) in urls.enumerated() {
            guard let data = try? Data(contentsOf: url),
                  let image = downsampled(data: data, maxPixel: 1400) else { continue }
            let meta = exif(from: data)
            items.append(PhotoItem(
                image: image,
                // No EXIF capture time → spread evenly across a day by filename order (honest fallback)
                timestamp: meta.date ?? fallbackDate(index: index, total: urls.count),
                coordinate: meta.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                hasGPS: meta.coordinate != nil))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - EXIF

    private static func exif(from data: Data) -> (date: Date?, coordinate: CLLocationCoordinate2D?) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }

        var date: Date?
        if let exifDict = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = (exifDict[kCGImagePropertyExifDateTimeOriginal] as? String)
                  ?? (exifDict[kCGImagePropertyExifDateTimeDigitized] as? String) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: raw)
        }

        var coord: CLLocationCoordinate2D?
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double, lat != 0 || lon != 0 {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            coord = CLLocationCoordinate2D(latitude: latRef == "S" ? -lat : lat,
                                           longitude: lonRef == "W" ? -lon : lon)
        }
        return (date, coord)
    }

    /// Downsample for Vision/memory efficiency (ImageIO thumbnail — doesn't decode the full original)
    private static func downsampled(data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true   // apply EXIF orientation
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }

    private static func fallbackDate(index: Int, total: Int) -> Date {
        let base = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let span = 10.0 * 3600  // 09:00–19:00
        let offset = total <= 1 ? 0 : span * Double(index) / Double(total - 1)
        return base.addingTimeInterval(offset)
    }
}
