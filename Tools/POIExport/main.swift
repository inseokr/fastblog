import Foundation

// MARK: - Validate arguments

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: poi-export <path-to-photos>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let inputURL = URL(fileURLWithPath: inputPath)
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDir), isDir.boolValue else {
    fputs("Error: '\(inputPath)' does not exist or is not a directory\n", stderr)
    exit(1)
}

let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("POI_Test_Dataset")
guard !FileManager.default.fileExists(atPath: outputURL.path) else {
    fputs("Error: Output directory '\(outputURL.path)' already exists — remove it first\n", stderr)
    exit(1)
}

// MARK: - Set up output directories

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputURL.appendingPathComponent("photos"), withIntermediateDirectories: true)
} catch {
    fputs("Error creating output directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// MARK: - Pipeline

let (records, extractLog) = EXIFExtractor.extractAll(from: inputURL)
print("Extracted metadata from \(records.count) photo(s). Starting geocoding…")

var mutableRecords = records
var allLog = extractLog
await ReverseGeocoder.geocode(records: &mutableRecords, log: &allLog)

let exporter = DatasetExporter(outputDir: outputURL)
do {
    try exporter.export(records: mutableRecords, logLines: allLog)
    try exporter.copyPhotos(records: mutableRecords)
} catch {
    fputs("Export failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

print("Done. Output: \(outputURL.path)")
