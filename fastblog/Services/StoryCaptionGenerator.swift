//
//  StoryCaptionGenerator.swift
//  fastblog
//
//  Protocol for generating photo captions and place stories from tags and metadata.
//  Use a local LLM implementation or the built-in template-based generator.
//

import Foundation

// MARK: - Place Category

/// Normalized place category used to select the right prompt modifier.
enum PlaceCategoryID: String, Sendable {
    case landmark    = "LANDMARK"
    case restaurant  = "RESTAURANT"
    case cafe        = "CAFE"
    case beach       = "BEACH"
    case mountain    = "MOUNTAIN"
    case trail       = "TRAIL"
    case park        = "PARK"
    case museum      = "MUSEUM"
    case hotel       = "HOTEL"
    case street      = "STREET"
    case viewpoint   = "VIEWPOINT"
    case event       = "EVENT"
    case unknown     = "UNKNOWN"

    /// Maps Apple MKPOICategory strings and the user-visible place name to a normalized ID.
    static func from(mkCategory: String?, placeName: String? = nil) -> PlaceCategoryID {
        // Check MK category first
        if let raw = mkCategory {
            let cat = raw.lowercased()
            if cat.contains("restaurant") || cat.contains("fooddelivery") || cat.contains("dining") { return .restaurant }
            if cat.contains("cafe") || cat.contains("coffee") || cat.contains("bakery") { return .cafe }
            if cat.contains("nightlife") || cat.contains("brewery") || cat.contains("bar") { return .restaurant }
            if cat.contains("beach") || cat.contains("marina") || cat.contains("surf") { return .beach }
            if cat.contains("trail") || cat.contains("trailhead") { return .trail }
            if cat.contains("hiking") || cat.contains("mountain") || cat.contains("ski") { return .mountain }
            if cat.contains("nationalpark") || cat.contains("nature") || cat.contains("forest") { return .park }
            if cat.contains("park") || cat.contains("garden") { return .park }
            if cat.contains("museum") || cat.contains("artgallery") || cat.contains("gallery") { return .museum }
            if cat.contains("landmark") || cat.contains("monument") || cat.contains("historicsite") { return .landmark }
            if cat.contains("theater") || cat.contains("concert") || cat.contains("stadium") || cat.contains("fairground") { return .event }
            if cat.contains("hotel") || cat.contains("lodging") || cat.contains("campground") { return .hotel }
            if cat.contains("viewpoint") || cat.contains("scenic") || cat.contains("overlook") { return .viewpoint }
            if cat.contains("street") || cat.contains("transit") || cat.contains("airport") { return .street }
        }
        // Fall back to place name keywords
        if let name = placeName {
            let lower = name.lowercased()
            if lower.contains("trail") || lower.contains("trails") || lower.contains("trek") { return .trail }
            if lower.contains("hike") || lower.contains("hiking") { return .trail }
            if lower.contains("mountain") || lower.contains("peak") || lower.contains("summit") { return .mountain }
            if lower.contains("beach") || lower.contains("shore") || lower.contains("coast") { return .beach }
            if lower.contains("park") || lower.contains("garden") || lower.contains("nature") { return .park }
            if lower.contains("museum") || lower.contains("gallery") { return .museum }
            if lower.contains("viewpoint") || lower.contains("overlook") || lower.contains("scenic") { return .viewpoint }
            if lower.contains("cafe") || lower.contains("coffee") { return .cafe }
        }
        return .unknown
    }
}

// MARK: - Place Name Confidence

/// How specific / trustworthy the place name is — shapes how the LLM uses it.
enum PlaceNameConfidence: Sendable {
    case official  // Proper noun: "Eiffel Tower", "In-N-Out Burger"
    case semi      // Vague descriptor: "Near Bangkok", "Downtown LA"
    case generic   // Category-level: "Restaurant", "Unknown"

    static func from(placeName: String) -> PlaceNameConfidence {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .generic }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("near ") { return .semi }
        if lower.hasSuffix(" area") || lower.contains("downtown") || lower.contains(" district") || lower.contains("neighborhood") { return .semi }
        let genericKeywords = ["restaurant", "cafe", "coffee", "hotel", "beach", "park", "museum",
                               "bar", "shop", "store", "unknown", "street", "building", "mall", "airport"]
        if genericKeywords.contains(where: { lower == $0 }) { return .generic }
        return .official
    }
}

// MARK: - Context Types

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
    let categoryID: PlaceCategoryID
    let nameConfidence: PlaceNameConfidence
    /// Derived from the earliest photo timestamp (e.g. "morning", "golden hour", "night").
    let timeOfDay: String?
    /// Derived from Vision tags ("indoor" / "outdoor" detection). Nil when unknown.
    let isIndoor: Bool?
}

/// Input context for generating an overall place summary from existing photo captions.
struct OverallPlaceStoryContext {
    /// All photo captions (stories) for this place's included photos.
    let photoCaptions: [String]
    /// Aggregated Vision tags from included photos — used to enrich the prompt when meaningful.
    let tags: [String]
    let placeName: String
    let placeSubtitle: String?
    let dateTimeText: String
    let categoryID: PlaceCategoryID
    let nameConfidence: PlaceNameConfidence
}

/// Input context for generating a one-sentence summary of an entire travel day.
struct DayStoryContext {
    /// Human-readable date string (e.g. "Saturday Jan-18").
    let dayDateText: String
    /// Each place's overallStory or placeTitle as fallback, in visit order.
    let placeStories: [String]
}

// MARK: - Enhance Context Types

/// Input for enhancing a user-written photo caption.
struct EnhancePhotoCaptionContext {
    /// The user's raw draft text to complete/enrich.
    let userText: String
    let tags: [String]
}

/// Input for enhancing a user-written place story.
struct EnhancePlaceStoryContext {
    /// The user's raw draft text to complete/enrich.
    let userText: String
    let tags: [String]
    let placeName: String
    let placeSubtitle: String?
    let dateTimeText: String
    let photoCount: Int
    let categoryID: PlaceCategoryID
    let nameConfidence: PlaceNameConfidence
    let timeOfDay: String?
    let isIndoor: Bool?
}

/// Input for enhancing a user-written day story.
struct EnhanceDayStoryContext {
    /// The user's raw draft text to complete/enrich.
    let userText: String
    let dayDateText: String
    /// Each place's overallStory or placeTitle as fallback, in visit order.
    let placeStories: [String]
}

/// Input for enhancing a user-written overall place story.
struct EnhanceOverallPlaceStoryContext {
    /// The user's raw draft text to complete/enrich.
    let userText: String
    let photoCaptions: [String]
    let tags: [String]
    let placeName: String
    let placeSubtitle: String?
    let dateTimeText: String
    let categoryID: PlaceCategoryID
    let nameConfidence: PlaceNameConfidence
}

// MARK: - Protocol

/// Provider that generates caption or place story text. Replace with a real local LLM when available.
protocol StoryCaptionGeneratorProtocol: Sendable {
    func generateCaption(context: PhotoCaptionContext) async -> String
    func generatePlaceStory(context: PlaceStoryContext) async -> String
    /// Very quick one-sentence summary of the place from all photo captions. Shown above/below place and time.
    func generateOverallPlaceStory(context: OverallPlaceStoryContext) async -> String
    /// One-sentence summary of the whole day from all place stories.
    func generateDaySummary(context: DayStoryContext) async -> String

    // MARK: Enhance (user has written a draft — LLM completes/enriches it)

    /// Completes and enriches the user's photo caption draft.
    func enhanceCaption(context: EnhancePhotoCaptionContext) async -> String
    /// Completes and enriches the user's place story draft.
    func enhancePlaceStory(context: EnhancePlaceStoryContext) async -> String
    /// Completes and enriches the user's overall place story draft.
    func enhanceOverallPlaceStory(context: EnhanceOverallPlaceStoryContext) async -> String
    /// Completes and enriches the user's day story draft.
    func enhanceDaySummary(context: EnhanceDayStoryContext) async -> String
}

// MARK: - Template Fallback

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

        return "This photo: \(tagPart)."
    }

    func generatePlaceStory(context: PlaceStoryContext) async -> String {
        try? await Task.sleep(nanoseconds: 400_000_000)

        let tagPart = context.tags.prefix(6).joined(separator: ", ")
        let placePart: String
        switch context.nameConfidence {
        case .official, .semi:
            placePart = [context.placeName, context.placeSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .generic:
            placePart = ""
        }
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
            let placePart: String
            switch context.nameConfidence {
            case .official, .semi:
                placePart = [context.placeName, context.placeSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            case .generic:
                placePart = ""
            }
            return placePart.isEmpty ? "A stop worth remembering." : "\(placePart) — a moment to look back on."
        }
        if captions.count == 1 {
            let one = String(captions[0].prefix(120))
            return one.count < captions[0].count ? one + "…" : one
        }
        let first = String(captions[0].prefix(60))
        return first + "… and \(captions.count - 1) more from this spot."
    }

    func generateDaySummary(context: DayStoryContext) async -> String {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let stories = context.placeStories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if stories.isEmpty {
            return context.dayDateText.isEmpty ? "A full day of exploring." : "\(context.dayDateText) — a day to remember."
        }
        let names = stories.prefix(3).joined(separator: ", ")
        return "\(context.dayDateText): \(names)."
    }

    // MARK: Enhance (template fallback — returns user text as-is; LLM not available)

    func enhanceCaption(context: EnhancePhotoCaptionContext) async -> String {
        context.userText
    }

    func enhancePlaceStory(context: EnhancePlaceStoryContext) async -> String {
        context.userText
    }

    func enhanceOverallPlaceStory(context: EnhanceOverallPlaceStoryContext) async -> String {
        context.userText
    }

    func enhanceDaySummary(context: EnhanceDayStoryContext) async -> String {
        context.userText
    }
}
