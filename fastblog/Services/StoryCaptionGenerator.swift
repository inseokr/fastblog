//
//  StoryCaptionGenerator.swift
//  fastblog
//
//  Protocol for generating photo captions and place stories from tags and metadata.
//  Use a local LLM implementation or the built-in template-based generator.
//

import Foundation

/// Input context for generating a single photo caption.
struct PhotoCaptionContext {
    let tags: [String]
}

/// Input context for generating a place-level story (note for the whole stop).
struct PlaceStoryContext {
    /// Aggregated or representative tags from this place's photos.
    let tags: [String]
    let placeName: String
    let placeSubtitle: String?
    let dateTimeText: String
    let photoCount: Int
}

/// Input context for generating an overall place summary from existing photo captions.
struct OverallPlaceStoryContext {
    /// All photo captions (stories) for this place's included photos.
    let photoCaptions: [String]
    let placeName: String
    let placeSubtitle: String?
    let dateTimeText: String
}

/// Provider that generates caption or place story text. Replace with a real local LLM when available.
protocol StoryCaptionGeneratorProtocol: Sendable {
    func generateCaption(context: PhotoCaptionContext) async -> String
    func generatePlaceStory(context: PlaceStoryContext) async -> String
    /// Very quick one-sentence summary of the place from all photo captions. Shown above/below place and time.
    func generateOverallPlaceStory(context: OverallPlaceStoryContext) async -> String
}

/// Template-based generator that weaves tags and metadata into short, blog-like text.
/// Used when the on-device LLM (Foundation Models) is unavailable.
final class TemplateStoryCaptionGenerator: StoryCaptionGeneratorProtocol, @unchecked Sendable {
    static let shared = TemplateStoryCaptionGenerator()

    private init() {}

    func generateCaption(context: PhotoCaptionContext) async -> String {
        try? await Task.sleep(nanoseconds: 300_000_000)

        let tagPart = context.tags.prefix(5).joined(separator: ", ")

        if tagPart.isEmpty {
            return "A moment worth remembering."
        }

        // Concise blog-style: one short sentence based only on photo content.
        return "This photo: \(tagPart)."
    }

    func generatePlaceStory(context: PlaceStoryContext) async -> String {
        try? await Task.sleep(nanoseconds: 400_000_000)

        let tagPart = context.tags.prefix(6).joined(separator: ", ")
        let placePart = [context.placeName, context.placeSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let timePart = context.dateTimeText
        let countPart = context.photoCount > 1 ? "\(context.photoCount) photos" : "one photo"

        if context.tags.isEmpty && placePart.isEmpty {
            return "We stopped here and took \(countPart) — a moment to look back on."
        }

        if !placePart.isEmpty && !tagPart.isEmpty {
            return "\(placePart): \(tagPart). We took \(countPart) here." + (timePart.isEmpty ? "" : " \(timePart).")
        }
        if !placePart.isEmpty {
            return "Stopped at \(placePart) and took \(countPart)." + (timePart.isEmpty ? "" : " \(timePart).")
        }
        return "This spot had \(tagPart). \(countPart) from the visit." + (timePart.isEmpty ? "" : " \(timePart).")
    }

    func generateOverallPlaceStory(context: OverallPlaceStoryContext) async -> String {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let captions = context.photoCaptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if captions.isEmpty {
            let placePart = [context.placeName, context.placeSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return placePart.isEmpty ? "A stop worth remembering." : "\(placePart) — a moment to look back on."
        }
        if captions.count == 1 {
            let one = String(captions[0].prefix(120))
            return one.count < captions[0].count ? one + "…" : one
        }
        let first = String(captions[0].prefix(60))
        return first + "… and \(captions.count - 1) more from this spot."
    }
}
