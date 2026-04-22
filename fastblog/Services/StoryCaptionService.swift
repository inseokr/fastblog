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

    /// Derives a human-readable time-of-day label from a timestamp (blog-style buckets, no clock).
    private func timeOfDayLabel(from date: Date, in timeZone: TimeZone) -> String {
        VisitDaypart.label(for: date, in: timeZone)
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
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle),
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
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle),
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
        placeSubtitle: String?,
        translateOutputToEnglish: Bool = false
    ) async -> String {
        let tags: [String]
        if let lid = photo.localIdentifier {
            tags = await tagService.tags(forLocalIdentifier: lid)
        } else {
            tags = []
        }
        let context = EnhancePhotoCaptionContext(
            userText: userText,
            tags: tags,
            translateOutputToEnglish: translateOutputToEnglish
        )
        return await generator.enhanceCaption(context: context)
    }

    /// Completes and enriches the user's place story draft using place metadata and photo tags.
    func enhancePlaceStory(
        stop: PlaceStop,
        userText: String,
        dayDate: Date?,
        translateOutputToEnglish: Bool = false
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
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle),
            timeOfDay: earliestDate.map { timeOfDayLabel(from: $0, in: tz) },
            isIndoor: isIndoor(from: tagSet),
            translateOutputToEnglish: translateOutputToEnglish
        )
        return await generator.enhancePlaceStory(context: context)
    }

    /// Completes and enriches the user's overall place story draft using photo captions and metadata.
    func enhanceOverallPlaceStory(
        stop: PlaceStop,
        userText: String,
        dayDate: Date?,
        photoCaptions: [String],
        translateOutputToEnglish: Bool = false
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
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle),
            translateOutputToEnglish: translateOutputToEnglish
        )
        return await generator.enhanceOverallPlaceStory(context: context)
    }

    /// Translates the user's text to English without any enhancement or story generation.
    func translateText(userText: String) async -> String {
        await generator.translateText(userText: userText)
    }

    /// Analyzes the sentiment of a caption or place story.
    /// Returns 1 (bad), 2 (neutral), or 3 (good). Falls back to 2 when LLM is unavailable.
    func analyzeSentiment(text: String) async -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 2 }
        return await LocalLLMStoryCaptionGenerator.shared.analyzeSentiment(text: trimmed)
    }

    // MARK: - Narrative Generation (LLM-only, hidden when not capable)

    /// Generates a 4–6 line narrative for a place visit. Returns nil when the on-device LLM is unavailable.
    func generatePlaceNarrative(stop: PlaceStop, dayDate: Date?) async -> String? {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return nil }
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(5) {
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
        let earliestDate = included.map(\.timestamp).min() ?? dayDate
        let dateTimeText = earliestDate.map { formatter.string(from: $0) } ?? ""
        let context = PlaceNarrativeContext(
            tags: tagSet,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            dateTimeText: dateTimeText,
            photoCount: included.count,
            categoryID: PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle),
            nameConfidence: PlaceNameConfidence.from(placeName: stop.placeTitle),
            timeOfDay: earliestDate.map { timeOfDayLabel(from: $0, in: tz) },
            existingStory: stop.overallStory
        )
        return await LocalLLMStoryCaptionGenerator.shared.generatePlaceNarrative(context: context)
    }

    /// Generates a 4–6 line narrative for a travel day. Returns nil when the on-device LLM is unavailable.
    func generateDayNarrative(day: RecapBlogDay) async -> String? {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return nil }
        let placeEntries = day.placeStops.map { stop -> (name: String, story: String) in
            (name: stop.placeTitle, story: stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        let context = DayNarrativeContext(
            dayDateText: day.shortDateText,
            placeEntries: placeEntries,
            weatherSummary: day.weather?.emoji
        )
        return await LocalLLMStoryCaptionGenerator.shared.generateDayNarrative(context: context)
    }

    /// Generates a 5–6 line trip opening narrative. Returns nil when the on-device LLM is unavailable.
    func generateTripNarrative(detail: RecapBlogDetail) async -> String? {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return nil }
        var locationSet: [String] = []
        for day in detail.days {
            for stop in day.placeStops {
                let loc = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? stop.placeSubtitle!
                    : stop.placeTitle
                if !loc.isEmpty && !locationSet.contains(loc) { locationSet.append(loc) }
            }
        }
        let daySummaries = detail.days.map { day -> String in
            let caption = day.dayCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return caption.isEmpty ? day.placeStops.prefix(3).map(\.placeTitle).joined(separator: ", ") : caption
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let startText = detail.days.first.map { formatter.string(from: $0.date) } ?? ""
        let endText = detail.days.last.map { formatter.string(from: $0.date) } ?? ""
        let dateRangeText = [startText, endText].filter { !$0.isEmpty }.joined(separator: " – ")
        let context = TripNarrativeContext(
            tripTitle: detail.title,
            dateRangeText: dateRangeText,
            dayCount: detail.days.count,
            locationChain: Array(locationSet.prefix(8)),
            daySummaries: daySummaries
        )
        return await LocalLLMStoryCaptionGenerator.shared.generateTripNarrative(context: context)
    }

    /// Completes and enriches the user's day story draft using place stories as context.
    func enhanceDaySummary(day: RecapBlogDay, userText: String, translateOutputToEnglish: Bool = false) async -> String {
        let placeStories = day.placeStops.map { stop -> String in
            let story = stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return story.isEmpty ? stop.placeTitle : story
        }
        let context = EnhanceDayStoryContext(
            userText: userText,
            dayDateText: day.shortDateText,
            placeStories: placeStories,
            translateOutputToEnglish: translateOutputToEnglish
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

    // MARK: - Fun photo insight (Apple Intelligence / on-device LLM only)

    /// True when on-device image analysis produced at least one non-empty tag for this photo asset.
    func photoHasAnalyzedVisionTags(photo: RecapPhoto) async -> Bool {
        guard let lid = photo.localIdentifier, !lid.isEmpty else { return false }
        let tags = await tagService.tags(forLocalIdentifier: lid)
        return tags.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Up to two blog-style sentences grounded in Vision tags, place, category, and approximate daypart (no clock times).
    func generateFunPhotoInsight(
        photo: RecapPhoto,
        placeName: String,
        placeSubtitle: String?,
        placeCategoryMK: String?,
        visitTimeZone: TimeZone? = nil,
        userCaptionHint: String?
    ) async -> String {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return "" }
        let tags: [String]
        if let lid = photo.localIdentifier {
            tags = await tagService.tags(forLocalIdentifier: lid)
        } else {
            tags = []
        }
        let trimmedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmedTags.isEmpty else { return "" }
        let categoryID = PlaceCategoryID.from(mkCategory: placeCategoryMK, placeName: placeName)
        let daypart = VisitDaypart.label(for: photo.timestamp, in: visitTimeZone ?? .current)
        return await LocalLLMStoryCaptionGenerator.shared.generateFunPhotoInsight(
            tags: trimmedTags,
            placeName: placeName,
            placeSubtitle: placeSubtitle,
            visitDaypart: daypart,
            userCaptionHint: userCaptionHint,
            categoryID: categoryID
        )
    }

    /// Up to two blog-style sentences for the **place** row, using aggregated tags, photo captions, place metadata, and daypart.
    func generatePlaceLevelAIShortStory(stop: PlaceStop, dayDate: Date?) async -> String {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return "" }
        let included = stop.photos.filter(\.isIncluded)
        var tagSet: [String] = []
        for photo in included.prefix(6) {
            if let lid = photo.localIdentifier {
                let photoTags = await tagService.tags(forLocalIdentifier: lid)
                for t in photoTags where !tagSet.contains(t) { tagSet.append(t) }
            }
        }
        let trimmedTags = tagSet.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let captions = included.map { ($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let tz = await captureTimeZone(for: stop)
        let earliest = included.map(\.timestamp).min() ?? dayDate
        let daypart = earliest.map { VisitDaypart.label(for: $0, in: tz) } ?? ""
        let categoryID = PlaceCategoryID.from(mkCategory: stop.placeCategory, placeName: stop.placeTitle)
        return await LocalLLMStoryCaptionGenerator.shared.generatePlaceLevelAIShortStory(
            tags: trimmedTags,
            photoCaptions: captions,
            placeName: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            categoryID: categoryID,
            visitDaypart: daypart,
            photoCount: included.count
        )
    }

}
