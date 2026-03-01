//
//  StoryCaptionService.swift
//  fastblog
//
//  Orchestrates: collect tags from photo(s) via PhotoTagService,
//  then ask the StoryCaptionGenerator (local LLM or template) to produce caption or place story.
//

import Foundation

/// Single entry point for AI-generated photo captions and place stories.
actor StoryCaptionService {
    static let shared = StoryCaptionService()

    private let tagService = PhotoTagService.shared
    private var generator: (any StoryCaptionGeneratorProtocol) = LocalLLMStoryCaptionGenerator.shared

    /// Replace the generator (e.g. for tests or a different LLM backend).
    func setGenerator(_ newGenerator: any StoryCaptionGeneratorProtocol) {
        generator = newGenerator
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
