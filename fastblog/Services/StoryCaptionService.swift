//
//  StoryCaptionService.swift
//  fastblog
//
//  Orchestrates: collect tags from photo(s) via PhotoTagService,
//  then ask the StoryCaptionGenerator (local LLM or template) to produce caption or place story.
//

import CoreGraphics
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
        let context = PhotoCaptionContext(tags: tags)
        return await generator.generateCaption(context: context)
    }

    /// Generate a caption for an in-app capture (UIImage/CGImage). Uses Vision tags from the image.
    func generateCaptionForImage(cgImage: CGImage) async -> String {
        let tags = await tagService.tags(for: cgImage)
        let context = PhotoCaptionContext(tags: tags)
        return await generator.generateCaption(context: context)
    }

    /// Derives a human-readable time-of-day label from a timestamp.
    private func timeOfDayLabel(from date: Date, in timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        switch hour {
        case 5..<9:   return "morning"
        case 9..<12:  return "late morning"
        case 12..<14: return "midday"
        case 14..<17: return "afternoon"
        case 17..<20: return "golden hour"
        default:      return "night"
        }
    }

    /// Detects indoor/outdoor from Vision tags. Returns nil when uncertain.
    private func isIndoor(from tags: [String]) -> Bool? {
        let lower = tags.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("indoor") || $0.contains("interior") }) { return true }
        if lower.contains(where: { $0.contains("outdoor") || $0.contains("exterior") }) { return false }
        return nil
    }

    /// Generate a place-level story from the first included photo's tags (or aggregated tags).
    /// Uses place name, subtitle, earliest photo time, and photo count.
    func generatePlaceStory(
        stop: PlaceStop,
        dayDate: Date?
    ) async -> String {
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(3) {
            if let lid = photo.localIdentifier {
                let photoTags = await tagService.tags(forLocalIdentifier: lid)
                for t in photoTags where !tagSet.contains(t) { tagSet.append(t) }
            }
        }
        let tags = tagSet
        let tz = await captureTimeZone(for: stop)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz
        let dateTimeText: String
        let earliestDate: Date?
        if let t = included.map(\.timestamp).min() {
            dateTimeText = formatter.string(from: t)
            earliestDate = t
        } else if let d = dayDate {
            dateTimeText = formatter.string(from: d)
            earliestDate = d
        } else {
            dateTimeText = ""
            earliestDate = nil
        }
        let context = PlaceStoryContext(
            tags: tags,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            photoCount: included.count,
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle),
            timeOfDay: earliestDate.map { timeOfDayLabel(from: $0, in: tz) },
            isIndoor: isIndoor(from: tags)
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
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(3) {
            if let lid = photo.localIdentifier {
                let photoTags = await tagService.tags(forLocalIdentifier: lid)
                for t in photoTags where !tagSet.contains(t) { tagSet.append(t) }
            }
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
        let context = OverallPlaceStoryContext(
            photoCaptions: photoCaptions,
            tags: tagSet,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle)
        )
        return await generator.generateOverallPlaceStory(context: context)
    }

    // MARK: - Enhance (user has written a draft)

    /// Completes and enriches the user's photo caption draft using available metadata.
    func enhanceCaption(
        photo: RecapPhoto,
        userText: String,
        placeName: String,
        placeSubtitle: String?
    ) async -> String {
        let tags: [String]
        if let lid = photo.localIdentifier {
            tags = await tagService.tags(forLocalIdentifier: lid)
        } else {
            tags = []
        }
        let context = EnhancePhotoCaptionContext(userText: userText, tags: tags)
        return await generator.enhanceCaption(context: context)
    }

    /// Completes and enriches the user's place story draft using place metadata and photo tags.
    func enhancePlaceStory(
        stop: PlaceStop,
        userText: String,
        dayDate: Date?
    ) async -> String {
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(3) {
            if let lid = photo.localIdentifier {
                let photoTags = await tagService.tags(forLocalIdentifier: lid)
                for t in photoTags where !tagSet.contains(t) { tagSet.append(t) }
            }
        }
        let tz = await captureTimeZone(for: stop)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz
        let dateTimeText: String
        let earliestDate: Date?
        if let t = included.map(\.timestamp).min() {
            dateTimeText = formatter.string(from: t)
            earliestDate = t
        } else if let d = dayDate {
            dateTimeText = formatter.string(from: d)
            earliestDate = d
        } else {
            dateTimeText = ""
            earliestDate = nil
        }
        let context = EnhancePlaceStoryContext(
            userText: userText,
            tags: tagSet,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            photoCount: included.count,
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle),
            timeOfDay: earliestDate.map { timeOfDayLabel(from: $0, in: tz) },
            isIndoor: isIndoor(from: tagSet)
        )
        return await generator.enhancePlaceStory(context: context)
    }

    /// Completes and enriches the user's overall place story draft using photo captions and metadata.
    func enhanceOverallPlaceStory(
        stop: PlaceStop,
        userText: String,
        dayDate: Date?,
        photoCaptions: [String]
    ) async -> String {
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(3) {
            if let lid = photo.localIdentifier {
                let photoTags = await tagService.tags(forLocalIdentifier: lid)
                for t in photoTags where !tagSet.contains(t) { tagSet.append(t) }
            }
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
        let context = EnhanceOverallPlaceStoryContext(
            userText: userText,
            photoCaptions: photoCaptions,
            tags: tagSet,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle)
        )
        return await generator.enhanceOverallPlaceStory(context: context)
    }

    /// Completes and enriches the user's day story draft using place stories as context.
    func enhanceDaySummary(day: RecapBlogDay, userText: String) async -> String {
        let placeStories = day.placeStops.map { stop -> String in
            let story = stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return story.isEmpty ? stop.placeTitle : story
        }
        let context = EnhanceDayStoryContext(
            userText: userText,
            dayDateText: day.shortDateText,
            placeStories: placeStories
        )
        return await generator.enhanceDaySummary(context: context)
    }

    // MARK: - Day Summary

    /// Generate a one-sentence summary of the whole day from all place stories.
    /// Falls back to place titles when no overallStory is set for a stop.
    func generateDaySummary(day: RecapBlogDay) async -> String {
        let placeStories = day.placeStops.map { stop -> String in
            let story = stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return story.isEmpty ? stop.placeTitle : story
        }
        let context = DayStoryContext(
            dayDateText: day.shortDateText,
            placeStories: placeStories
        )
        return await generator.generateDaySummary(context: context)
    }

}
