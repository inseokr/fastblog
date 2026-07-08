import Foundation
import ImageIO

struct PhotoRecord {
    let filename: String
    let sourcePath: URL
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let cameraModel: String?

    var suggestedPlaceName: String?
    var suggestedCity: String?
    var suggestedCountry: String?

    var mapkitPlaceName: String?
    var mapkitCategory: String?
    var mapkitCity: String?
    var mapkitCountry: String?

    let verifiedPlaceName: String = ""
    let notes: String = ""
}

struct EXIFExtractor {
    private static let supportedExtensions = ["jpg", "jpeg", "heic", "png"]

    static func extractAll(from directory: URL) -> (records: [PhotoRecord], log: [String]) {
        var records: [PhotoRecord] = []
        var log: [String] = []

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                log.append("[SKIP] \(url.lastPathComponent) — unsupported extension")
                continue
            }
            guard let record = extract(from: url) else {
                log.append("[ERROR] \(url.lastPathComponent) — unreadable")
                continue
            }
            records.append(record)
            log.append("[OK] \(url.lastPathComponent)")
        }

        return (records, log)
    }

    static func extract(from url: URL) -> PhotoRecord? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let gpsDic = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let exifDic = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiffDic = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let (lat, lon) = extractCoordinates(from: gpsDic)
        let timestamp = extractTimestamp(from: exifDic)
        let cameraModel = tiffDic?[kCGImagePropertyTIFFModel] as? String

        return PhotoRecord(
            filename: url.lastPathComponent,
            sourcePath: url,
            latitude: lat,
            longitude: lon,
            timestamp: timestamp,
            cameraModel: cameraModel
        )
    }

    // MARK: - Private

    private static func extractCoordinates(from gps: [CFString: Any]?) -> (Double?, Double?) {
        guard let gps,
              let latValue = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lonValue = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return (nil, nil)
        }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        return (latRef == "S" ? -latValue : latValue, lonRef == "W" ? -lonValue : lonValue)
    }

    private static func extractTimestamp(from exif: [CFString: Any]?) -> String? {
        guard let exif,
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              raw.count >= 19 else { return nil }
        // "YYYY:MM:DD HH:MM:SS" → "YYYY-MM-DDTHH:MM:SS"
        var chars = Array(raw)
        chars[4] = "-"; chars[7] = "-"; chars[10] = "T"
        return String(chars)
    }
}
