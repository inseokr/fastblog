import Foundation

struct DatasetExporter {
    let outputDir: URL

    // MARK: - Public

    func export(records: [PhotoRecord], logLines: [String]) throws {
        try writeCSV(records: records)
        try writeJSON(records: records)
        try writeLog(records: records, logLines: logLines)
    }

    func copyPhotos(records: [PhotoRecord]) throws {
        let photosDir = outputDir.appendingPathComponent("photos")
        for record in records {
            let dest = photosDir.appendingPathComponent(record.filename)
            do {
                try FileManager.default.copyItem(at: record.sourcePath, to: dest)
            } catch {
                fputs("[ERROR] copy failed for \(record.filename): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - CSV

    private func writeCSV(records: [PhotoRecord]) throws {
        let header = "filename,latitude,longitude,timestamp,camera_model,suggested_place_name,suggested_city,suggested_country,verified_place_name,notes"
        var lines = [header]
        for r in records {
            let row = [
                csvEscape(r.filename),
                r.latitude.map { String($0) } ?? "",
                r.longitude.map { String($0) } ?? "",
                csvEscape(r.timestamp),
                csvEscape(r.cameraModel),
                csvEscape(r.suggestedPlaceName),
                csvEscape(r.suggestedCity),
                csvEscape(r.suggestedCountry),
                csvEscape(r.verifiedPlaceName),
                csvEscape(r.notes)
            ].joined(separator: ",")
            lines.append(row)
        }
        let content = lines.joined(separator: "\r\n") + "\r\n"
        try content.write(to: outputDir.appendingPathComponent("labels.csv"), atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - JSON

    private func writeJSON(records: [PhotoRecord]) throws {
        let jsonRecords = records.map(JSONRecord.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(jsonRecords)
        try data.write(to: outputDir.appendingPathComponent("dataset.json"))
    }

    // MARK: - Log

    private func writeLog(records: [PhotoRecord], logLines: [String]) throws {
        let processed = records.count
        let geocoded = records.filter { $0.suggestedCity != nil || $0.suggestedPlaceName != nil }.count
        let skippedNoGPS = logLines.filter { $0.contains("no GPS") }.count
        let errors = logLines.filter { $0.hasPrefix("[ERROR]") }.count

        let summary = "Summary: \(processed) photos processed, \(geocoded) geocoded, \(skippedNoGPS) skipped (no GPS), \(errors) errors"
        let content = (logLines + [summary]).joined(separator: "\n") + "\n"
        try content.write(to: outputDir.appendingPathComponent("export_log.txt"), atomically: true, encoding: .utf8)
    }
}

// MARK: - JSON record

// Separate Codable type so sourcePath is excluded and nil fields encode as null.
private struct JSONRecord: Encodable {
    let filename: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let camera_model: String?
    let suggested_place_name: String?
    let suggested_city: String?
    let suggested_country: String?
    let verified_place_name: String
    let notes: String

    init(_ r: PhotoRecord) {
        filename = r.filename
        latitude = r.latitude
        longitude = r.longitude
        timestamp = r.timestamp
        camera_model = r.cameraModel
        suggested_place_name = r.suggestedPlaceName
        suggested_city = r.suggestedCity
        suggested_country = r.suggestedCountry
        verified_place_name = r.verifiedPlaceName
        notes = r.notes
    }

    // Explicit encode so Optional fields write as null, not omitted.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filename, forKey: .filename)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(camera_model, forKey: .camera_model)
        try c.encode(suggested_place_name, forKey: .suggested_place_name)
        try c.encode(suggested_city, forKey: .suggested_city)
        try c.encode(suggested_country, forKey: .suggested_country)
        try c.encode(verified_place_name, forKey: .verified_place_name)
        try c.encode(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case filename, latitude, longitude, timestamp
        case camera_model, suggested_place_name, suggested_city, suggested_country
        case verified_place_name, notes
    }
}
