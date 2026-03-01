//
//  StoryCaptionService.swift
//  fastblog
//
//  Orchestrates: collect tags from photo(s) via PhotoTagService,
//  then ask the StoryCaptionGenerator (local LLM or template) to produce caption or place story.
//

import Foundation
import CoreLocation

/// Single entry point for AI-generated photo captions and place stories.
actor StoryCaptionService {
    static let shared = StoryCaptionService()

    private let tagService = PhotoTagService.shared
    private var generator: (any StoryCaptionGeneratorProtocol) = LocalLLMStoryCaptionGenerator.shared

    /// Replace the generator (e.g. for tests or a different LLM backend).
    func setGenerator(_ newGenerator: any StoryCaptionGeneratorProtocol) {
        generator = newGenerator
    }

    /// Derives the capture-location timezone from EXIF digitized time vs photo timestamps. Returns nil when ambiguous (e.g. offset 0) or unavailable.
    private func derivedCaptureTimeZone(for stop: PlaceStop) -> TimeZone? {
        guard let digitized = stop.visitedTimeDigitized, stop.photos.count > 1 else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let localAsUTC = parser.date(from: digitized) else { return nil }
        let offsets: [Int] = stop.photos.map { Int(localAsUTC.timeIntervalSince($0.timestamp)) }
        let sorted = offsets.sorted()
        let medianOffset: Int
        if sorted.count.isMultiple(of: 2), sorted.count >= 2 {
            medianOffset = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            medianOffset = sorted[sorted.count / 2]
        }
        let roundedOffset = (medianOffset / 900) * 900
        if roundedOffset == 0 { return nil }
        return TimeZone(secondsFromGMT: roundedOffset)
    }

    /// Capture timezone for the stop: derived from digitized time first; when ambiguous (e.g. digitized in UTC) or missing, resolves from first photo's location.
    private func captureTimeZone(for stop: PlaceStop) async -> TimeZone {
        if let tz = derivedCaptureTimeZone(for: stop) { return tz }
        let photo = stop.photos.filter(\.isIncluded).first ?? stop.photos.first
        guard let loc = photo?.location else { return .current }
        let cl = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        return await GeocodingService.shared.timeZone(for: cl) ?? .current
    }

    /// Generate a caption for a single photo. Uses tags from that photo + place/time metadata.
    func generateCaption(
        photo: RecapPhoto,
        placeName: String,
        placeSubtitle: String?
    ) async -> String {
        let tags: [String]
        if let lid = photo.localIdentifier {
            tags = await tagService.tags(forLocalIdentifier: lid)
        } else {
            tags = []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateTimeText = formatter.string(from: photo.timestamp)
        let context = PhotoCaptionContext(
            tags: tags,
            placeName: placeName,
            placeSubtitle: placeSubtitle,
            dateTimeText: dateTimeText
        )
        return await generator.generateCaption(context: context)
    }

    /// Generate a place-level story from the first included photo's tags (or aggregated tags).
    /// Uses place name, subtitle, earliest photo time, and photo count.
    func generatePlaceStory(
        stop: PlaceStop,
        dayDate: Date?
    ) async -> String {
        let included = stop.photos.filter(\.isIncluded)
        let tags: [String]
        if let first = included.first, let lid = first.localIdentifier {
            tags = await tagService.tags(forLocalIdentifier: lid)
        } else {
            tags = []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = await captureTimeZone(for: stop)
        let dateTimeText: String
        if let t = included.map(\.timestamp).min() {
            dateTimeText = formatter.string(from: t)
        } else if let d = dayDate {
            dateTimeText = formatter.string(from: d)
        } else {
            dateTimeText = ""
        }
        let context = PlaceStoryContext(
            tags: tags,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            photoCount: included.count
        )
        return await generator.generatePlaceStory(context: context)
    }

    /// Generate a very quick one-sentence overall story for the place by summarizing all photo captions.
    /// Use the current captions from the stop's included photos (in order).
    func generateOverallPlaceStory(
        stop: PlaceStop,
        dayDate: Date?,
        photoCaptions: [String]
    ) async -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = await captureTimeZone(for: stop)
        let included = stop.photos.filter(\.isIncluded)
        let dateTimeText: String
        if let t = included.map(\.timestamp).min() {
            dateTimeText = formatter.string(from: t)
        } else if let d = dayDate {
            dateTimeText = formatter.string(from: d)
        } else {
            dateTimeText = ""
        }
        let context = OverallPlaceStoryContext(
            photoCaptions: photoCaptions,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText
        )
        return await generator.generateOverallPlaceStory(context: context)
    }
}
