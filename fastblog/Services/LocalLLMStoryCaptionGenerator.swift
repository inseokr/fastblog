//
//  LocalLLMStoryCaptionGenerator.swift
//  fastblog
//
//  Uses Apple's on-device Foundation Models (iOS 26+, Apple Intelligence) to generate
//  blog-style captions and place stories. Falls back to template when unavailable.
//
//  Prompt architecture:
//    Base system prompt (always)
//    + Category modifier  (based on PlaceCategoryID)
//    + Name confidence modifier (based on PlaceNameConfidence)
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates blog-like captions and place stories using the on-device LLM when available.
final class LocalLLMStoryCaptionGenerator: StoryCaptionGeneratorProtocol, @unchecked Sendable {
    static let shared = LocalLLMStoryCaptionGenerator()

    /// Returns true when the on-device LLM (Apple Intelligence, iOS 26+) is available and enabled on this device.
    static var isCapable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
#endif
        return false
    }

    private let templateFallback = TemplateStoryCaptionGenerator.shared

    private init() {}

    func generateCaption(context: PhotoCaptionContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generateCaptionWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.generateCaption(context: context)
    }

    func generatePlaceStory(context: PlaceStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generatePlaceStoryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.generatePlaceStory(context: context)
    }

    func generateOverallPlaceStory(context: OverallPlaceStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generateOverallPlaceStoryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.generateOverallPlaceStory(context: context)
    }

    func generateDaySummary(context: DayStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generateDaySummaryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.generateDaySummary(context: context)
    }

    func enhanceCaption(context: EnhancePhotoCaptionContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await enhanceCaptionWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.enhanceCaption(context: context)
    }

    func enhancePlaceStory(context: EnhancePlaceStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await enhancePlaceStoryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.enhancePlaceStory(context: context)
    }

    func enhanceOverallPlaceStory(context: EnhanceOverallPlaceStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await enhanceOverallPlaceStoryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.enhanceOverallPlaceStory(context: context)
    }

    func enhanceDaySummary(context: EnhanceDayStoryContext) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await enhanceDaySummaryWithLLM(context: context) {
                return result
            }
        }
#endif
        return await templateFallback.enhanceDaySummary(context: context)
    }

    func translateText(userText: String) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await translateTextWithLLM(userText: userText) {
                return result
            }
        }
#endif
        return await templateFallback.translateText(userText: userText)
    }

    /// Analyzes the sentiment of the given caption/story text.
    /// Returns 1 (bad), 2 (neutral), or 3 (good). Falls back to 2 when LLM is unavailable.
    func analyzeSentiment(text: String) async -> Int {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await analyzeSentimentWithLLM(text: text) ?? 2
        }
#endif
        return 2
    }

    // MARK: - POI Name Classification

    /// Returns true when `name` is a concrete, specific place (landmark, venue) rather than a
    /// generic area such as a neighborhood, street, or city.
    /// Uses the on-device LLM on iOS 26+; falls back to a rule-based heuristic on older OS.
    func classifyConcretePoiName(_ name: String) async -> Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                if let result = await classifyConcretePoiNameWithLLM(name) { return result }
            }
        }
#endif
        return Self.isConcretePoiHeuristic(name)
    }

    /// Heuristic fallback: returns true only when the name clearly looks like a specific venue,
    /// not a street, administrative unit, or single generic toponym.
    static func isConcretePoiHeuristic(_ name: String) -> Bool {
        guard !name.isEmpty, name != "Unknown Place" else { return false }
        let lower = name.lowercased()
        // Addresses start with numbers
        if name.first?.isNumber == true { return false }
        // Street/road suffixes
        let streetSuffixes = [" st", " ave", " rd", " blvd", " lane", " dr", " drive",
                              " street", " avenue", " road", " boulevard", " highway",
                              " hwy", " freeway", " parkway", " pkwy"]
        if streetSuffixes.contains(where: { lower.hasSuffix($0) }) { return false }
        // Korean transliterated road/admin suffixes
        let koreanAreaTokens = ["-gu", "-dong", "-ro ", "-ro,", "-gil", "-daero", "-si ", "-si,"]
        if koreanAreaTokens.contains(where: { lower.contains($0) }) { return false }
        // Generic administrative area terms
        let areaTerms = ["district", " county", " ward", " borough", "township"]
        if areaTerms.contains(where: { lower.contains($0) }) { return false }
        // Positive signal: known POI keyword present
        let poiKeywords = ["tower", "palace", "castle", "museum", "cathedral", "basilica",
                           "station", "airport", "park ", "garden", "temple", "shrine",
                           "mall", "market", "plaza", "square", "center", "centre",
                           "hotel", "resort", "stadium", "arena", "theater", "theatre",
                           "university", "college", "hospital", "monument", "memorial",
                           "pond", "lake", "reservoir", "river", "creek", "stream",
                           "falls", "waterfall", "beach", "bay", "forest", "valley",
                           "mountain", "peak", "cliff", "cave", "island", "nature"]
        if poiKeywords.contains(where: { lower.contains($0) }) { return true }
        return false
    }

    // MARK: - Fun photo insight (grounded blurb; UI shown only when `isCapable` and Vision tags exist)

    /// Up to two blog-style sentences from on-device tags + place metadata. Returns empty when `tags` is empty.
    func generateFunPhotoInsight(
        tags: [String],
        placeName: String,
        placeSubtitle: String?,
        visitDaypart: String,
        userCaptionHint: String?,
        categoryID: PlaceCategoryID
    ) async -> String {
        guard !tags.isEmpty else { return "" }
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generateFunPhotoInsightWithLLM(
                tags: tags,
                placeName: placeName,
                placeSubtitle: placeSubtitle,
                visitDaypart: visitDaypart,
                userCaptionHint: userCaptionHint,
                categoryID: categoryID
            ) {
                return result
            }
        }
#endif
        return Self.funPhotoInsightTagFallback(tags: tags, placeName: placeName, visitDaypart: visitDaypart)
    }

    private static func funPhotoInsightTagFallback(tags: [String], placeName: String, visitDaypart: String) -> String {
        let tagPart = tags.prefix(6).joined(separator: ", ")
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagPart.isEmpty {
            let suffix = place.isEmpty ? "" : " — \(place)"
            let timeSuffix = visitDaypart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " (\(visitDaypart))"
            return "The frame picks up \(tagPart)\(suffix)\(timeSuffix)."
        }
        return ""
    }

    /// Place-level “AI story”: aggregated tags + photo captions + place metadata; max two sentences.
    func generatePlaceLevelAIShortStory(
        tags: [String],
        photoCaptions: [String],
        placeName: String,
        placeSubtitle: String?,
        categoryID: PlaceCategoryID,
        visitDaypart: String,
        photoCount: Int
    ) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let result = await generatePlaceLevelAIShortStoryWithLLM(
                tags: tags,
                photoCaptions: photoCaptions,
                placeName: placeName,
                placeSubtitle: placeSubtitle,
                categoryID: categoryID,
                visitDaypart: visitDaypart,
                photoCount: photoCount
            ) {
                return result
            }
        }
#endif
        return Self.placeLevelAIShortStoryFallback(
            tags: tags,
            photoCaptions: photoCaptions,
            placeName: placeName,
            visitDaypart: visitDaypart
        )
    }

    private static func placeLevelAIShortStoryFallback(
        tags: [String],
        photoCaptions: [String],
        placeName: String,
        visitDaypart: String
    ) -> String {
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagLine = tags.prefix(4).joined(separator: ", ")
        let time = visitDaypart.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty, !tagLine.isEmpty {
            return time.isEmpty ? "\(place): \(tagLine)." : "\(place) on a \(time) — \(tagLine)."
        }
        if !place.isEmpty { return time.isEmpty ? "\(place) — a stop worth saving." : "\(place), \(time)." }
        return ""
    }

    // MARK: - Narrative Generation (LLM-only, no template fallback)

    /// Generates a short place narrative (at most 3 sentences, one per line). Returns nil when LLM is unavailable.
    func generatePlaceNarrative(context: PlaceNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generatePlaceNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

    /// Generates a short day narrative (at most 3 sentences, one per line). Returns nil when LLM is unavailable.
    func generateDayNarrative(context: DayNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateDayNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

    /// Generates a short trip opening narrative (at most 3 sentences, one per line). Returns nil when LLM is unavailable.
    func generateTripNarrative(context: TripNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateTripNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

#if canImport(FoundationModels)

    /// Rules for auto-generated **place stop** blurbs (overall row) — blog voice, not photo-caption recap.
    private static let placeStopBlogBlurbRules = """
        Place stop blurb — follow strictly:
        • Write a short travel-blog moment for this stop. Lead with the venue category and what that kind of visit usually feels like.
        • If existing photo captions are provided, treat them as optional memory seeds only — weave the mood or one detail, do not paraphrase every caption or list what each photo shows.
        • On-device photo tags are evidence for concrete visuals only when clearly supported. Tags outrank vague caption text if they conflict.
        • Do not invent people, relationships, dish names, business names, historical claims, or travel mishaps not in the hints.
        • When evidence is thin, write a simple, category-appropriate visit line that could fit most trips to this type of place — still no invented specifics.
        • Never output clock times or full calendar dates — daypart words only when timing matters.
        """

    /// Shared rules to keep on-device copy tied to trip data and reduce invented travel drama.
    private static let groundedTravelBlogRules = """
        Grounding — follow strictly:
        • Use only what this prompt supplies: place names, subtitles, tags, photo captions, user notes, weather, dates, day summaries, and listed place stories. Do not invent events, people, dialogue, schedules, prices, or historical claims.
        • Never invent travel logistics or mishaps — for example flight delays, cancellations, gate changes, long security lines, missed connections, lost luggage, overbooking, train breakdowns, or traffic disasters — unless that exact situation appears in the user’s text or in a place/day story given here.
        • At airports, train stations, bus terminals, ferry terminals, or similar hubs: the user may only have visited the building or grounds. Describe the stop in neutral, scene-level terms from the hints. Do not assume flying, boarding, departing, arriving, or any delay; those are inventions unless explicitly stated in the provided notes or stories.
        • Prefer plain, observational travel-blog prose over a dramatic plot, cliffhangers, or made-up beats to sound literary. If the hints are thin, keep the output simple and short-feeling in substance — do not fabricate a rich backstory to fill every line.
        """

    /// Brevity and anti–laundry-list rules for place/day/trip “Tell Story” narratives.
    private static let compactNarrativeFormatRules = """
        Length and shape:
        • At most 3 sentences total. Use 1, 2, or 3 only if the evidence supports it — never more than 3.
        • Output exactly one sentence per line. No blank lines between sentences. Do not prefix lines with “Sentence 1” or any meta labels.
        • Each sentence must introduce something new. Do not restate the same setting in different words (e.g. multiple sentences about sky color, air temperature, water clarity, grass, trees, or leaves).
        • Avoid a run of short “The X was Y” template lines. At most one simple weather or setting clause for the whole output unless the provided note explicitly describes a real change over time.
        • Do not contradict yourself (e.g. gray sky then blue sky, warm then cold) in one passage unless the user’s text explicitly describes that change.
        """

    /// Keeps newline-separated narratives from exceeding `maxLines` when the model over-generates.
    private static func clampNarrativeLineCount(_ text: String, maxLines: Int = 3) -> String {
        let lines = text.split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > maxLines else {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(maxLines).joined(separator: "\n")
    }

    // MARK: - Prompt Modifiers

    @available(iOS 26.0, *)
    private func categoryModifier(for category: PlaceCategoryID) -> String {
        switch category {
        case .restaurant:
            return """
                This place is categorized as a restaurant or food establishment.
                Focus on sensory details: taste, ambiance, vibe, plating, smell, atmosphere.
                Avoid generic food descriptions. Make it feel like a personal dining experience.
                """
        case .cafe:
            return """
                This place is categorized as a café or coffee shop.
                Focus on mood, warmth, aroma, the sound of conversation, the ritual of coffee.
                Make it feel intimate and unhurried.
                """
        case .beach:
            return """
                This place is categorized as a beach or coastal area.
                Focus on mood, weather, sounds, movement of water, light, calmness or energy.
                Avoid clichés like "crystal clear waters" unless it fits naturally.
                """
        case .landmark:
            return """
                This place is categorized as a well-known landmark.
                Balance emotional reflection with subtle recognition of its significance.
                Do not sound like a Wikipedia article. Make it feel personal.
                """
        case .museum:
            return """
                This place is categorized as a museum or cultural venue.
                Focus on atmosphere, discovery, the feeling of stepping into history or art.
                Keep it evocative, not encyclopedic.
                """
        case .park:
            return """
                This place is categorized as a park or natural area.
                Focus on the feeling of open space, greenery, calm, or playful energy.
                Ground it in sensory details.
                """
        case .trail:
            return """
                This place is categorized as a trail or hiking path.
                Focus on the journey, footsteps, terrain underfoot, the rhythm of walking, and what unfolds along the way.
                Capture the effort, the quiet, and the reward of being out in nature on foot.
                """
        case .mountain:
            return """
                This place is categorized as a mountain or hiking area.
                Focus on scale, physical sensation, panoramas, achievement, or raw nature.
                Make it vivid and grounded.
                """
        case .hotel:
            return """
                This place is categorized as a hotel or accommodation.
                Focus on comfort, arrival energy, views from the window, or the sense of a home base for the trip.
                """
        case .viewpoint:
            return """
                This place is categorized as a viewpoint or scenic overlook.
                Focus on what can be seen, the light, the scale, the silence or the crowd below.
                Make the view feel worth the trip.
                """
        case .event:
            return """
                This place is categorized as an event venue or entertainment space.
                Focus on atmosphere, crowd energy, anticipation, or the feeling of being part of something larger.
                """
        case .golf:
            return """
                This place is categorized as a golf course or golf entertainment venue.
                Focus on the sweep of the fairway, the satisfying crack of a well-struck shot, friendly competition, and the social energy of the round.
                Capture both the skill involved and the relaxed, outdoor enjoyment of the game.
                """
        case .music:
            return """
                This place is categorized as a music venue or concert hall.
                Focus on the energy of live sound, the crowd, the physical sensation of bass and melody filling the room.
                Capture the shared moment between performer and audience.
                """
        case .nightlife:
            return """
                This place is categorized as a bar, lounge, or nightlife venue.
                Focus on the mood, lighting, conversation, and the social energy that builds as the night goes on.
                Keep it vibrant without being generic.
                """
        case .winery:
            return """
                This place is categorized as a winery, brewery, or distillery.
                Focus on craft, the sensory experience of tasting, the setting — rolling vineyards, industrial tap rooms, or rustic barrels.
                Capture the story behind what's in the glass.
                """
        case .fitness:
            return """
                This place is categorized as a fitness center, gym, or sports facility.
                Focus on the physical energy, the push of effort, the rhythm of movement, and the satisfaction of activity.
                """
        case .shopping:
            return """
                This place is categorized as a shopping area, mall, or market.
                Focus on discovery, the variety of things to see and find, the energy of browsing, and the small wins of a good find.
                """
        case .amusementPark:
            return """
                This place is categorized as an amusement park, zoo, or aquarium.
                Focus on wonder, excitement, sensory overload in the best way — the sounds, the movement, the joy of being fully present.
                """
        case .street:
            return """
                This place is categorized as a street, transit hub, airport, station, or general city area.
                Focus on atmosphere, light, space, and small observations supported by the tags or captions.
                Do not fabricate specific facts. Do not assume flights, trains taken, delays, or arrivals/departures unless the user’s text or captions say so.
                """
        case .unknown:
            return """
                The exact type of place is unclear.
                Write a flexible, mood-focused caption based only on the atmosphere suggested by the tags.
                Avoid assuming what kind of place this is.
                """
        }
    }

    @available(iOS 26.0, *)
    private func nameConfidenceModifier(for confidence: PlaceNameConfidence, placeName: String) -> String {
        switch confidence {
        case .official:
            return """
                The official place name is known: "\(placeName)"
                You may naturally reference the name once in the caption.
                Do not explain what it is. Assume the reader already recognizes it.
                Make the name feel woven into the experience.
                """
        case .semi:
            return """
                The place name may not be precise or widely recognizable: "\(placeName)"
                Do not rely heavily on the name. Focus more on atmosphere than identity.
                Do not invent reputation or fame for this place.
                """
        case .generic:
            return """
                The place name is generic or unclear — do not use it in the caption.
                Write as if describing the experience without labeling the place.
                Focus entirely on mood and memory.
                """
        }
    }

    // MARK: - Generators

    @available(iOS 26.0, *)
    private func generateCaptionWithLLM(context: PhotoCaptionContext) async -> String? {
        let tagsLine = context.tags.isEmpty ? "general photo" : context.tags.prefix(8).joined(separator: ", ")

        let instructions = """
            You write short, vivid photo captions for a travel blog. \
            One concise sentence based only on the photo tags provided. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the text. No preamble, no labels — just the sentence.
            """
        let prompt = """
            Write one short sentence for a travel photo with these tags: \(tagsLine). \
            Output only the text. No introduction, no first person (I/we/my).
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generatePlaceStoryWithLLM(context: PlaceStoryContext) async -> String? {
        let tagsLine = context.tags.isEmpty
            ? "Aggregated on-device photo tags: none."
            : "Aggregated on-device photo tags: \(context.tags.prefix(16).joined(separator: ", "))."
        let countPart = context.photoCount > 1 ? "\nThis stop has \(context.photoCount) photos in the trip." : "\nThis stop has one photo in the trip."

        var contextLines: [String] = []
        if let tod = context.timeOfDay { contextLines.append("Approximate time of day: \(tod)") }
        if let indoor = context.isIndoor { contextLines.append("Environment: \(indoor ? "indoor" : "outdoor")") }
        let contextBlock = contextLines.isEmpty ? "" : "\n" + contextLines.joined(separator: "\n")

        let placePart: String
        switch context.nameConfidence {
        case .official, .semi:
            let line = [context.placeName, context.placeSubtitle]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            placePart = line.isEmpty ? "" : "\nPlace: \(line)."
        case .generic:
            placePart = ""
        }

        let baseSystem = """
            You write very short travel-blog blurbs for a single stop on a trip. \
            At most two sentences. Warm, readable blog voice — not marketing, not a tag list, not a photo-by-photo recap. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the blurb. No preamble or quotation marks.
            """

        let instructions = [
            baseSystem,
            Self.placeStopBlogBlurbRules,
            Self.groundedTravelBlogRules,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            Write a tiny travel-blog moment for this stop using only the evidence below.

            \(tagsLine)\(placePart)\(countPart)\(contextBlock)

            Maximum two sentences. Stay grounded in the hints.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generateOverallPlaceStoryWithLLM(context: OverallPlaceStoryContext) async -> String? {
        let captions = context.photoCaptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let placePart: String
        switch context.nameConfidence {
        case .official, .semi:
            let line = [context.placeName, context.placeSubtitle]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            placePart = line.isEmpty ? "" : " Place: \(line)."
        case .generic:
            placePart = ""
        }

        let captionsBlock = captions.isEmpty
            ? "No photo captions yet."
            : captions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let tagsLine = context.tags.prefix(8).joined(separator: ", ")
        let tagsPart = tagsLine.isEmpty ? "" : "\nPhoto analysis tags: \(tagsLine)."

        let baseSystem = """
            You write very short travel-blog blurbs for a single stop on a trip. \
            At most two sentences. Warm, readable blog voice — not marketing, not a tag list, not a photo-by-photo recap. \
            No hashtags or emoji. No first person (no "I", "we", "my"). Never output clock times or full calendar dates. \
            Output only the blurb. No preamble or quotation marks.
            """

        let instructions = [
            baseSystem,
            Self.placeStopBlogBlurbRules,
            Self.groundedTravelBlogRules,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            Write a tiny travel-blog moment for this stop using only the evidence below.\(placePart)\(tagsPart)

            \(captionsBlock.isEmpty ? "Existing photo captions from this stop: none." : "Existing photo captions from this stop (optional memory seeds — do not paraphrase each photo):\n\(captionsBlock)")

            Maximum two sentences. Stay grounded in the hints.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generateDaySummaryWithLLM(context: DayStoryContext) async -> String? {
        let stories = context.placeStories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let storiesBlock: String
        if stories.isEmpty {
            storiesBlock = "No place stories yet."
        } else {
            storiesBlock = stories.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
        let datePart = context.dayDateText.isEmpty ? "" : " Date: \(context.dayDateText)."

        let instructions = """
            You write one short sentence that summarises a travel day for a blog. \
            You are given place stories from that day. Combine only what they actually say — no new events or mishaps. \
            \(Self.groundedTravelBlogRules)
            No hashtags or emoji. No first person (no "I", "we", "my"). No date mention. \
            Output only the sentence. No preamble, no labels — just the sentence.
            """
        let prompt = """
            Summarise this travel day into one sentence.\(datePart)

            Place stories:
            \(storiesBlock)

            Output only the one-sentence day summary. No introduction, no first person (I/we/my).
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    // MARK: - User Writing Style

    /// Reads the user's saved writing style prompt from AppStorage.
    /// Falls back to the default prompt when nothing has been set.
    private var userWritingStyleInstruction: String {
        let stored = UserDefaults.standard.string(forKey: StoryWritingStyle.storageKey) ?? ""
        let style = stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? StoryWritingStyle.defaultPrompt
            : stored
        return "Additional user provided writing guideline: \(style)"
    }

    // MARK: - Language Detection

    /// Detects the dominant language of the user's text and returns an explicit instruction
    /// like "Respond in Korean." to inject into enhance prompts.
    /// Returns an empty string when the language is English or cannot be determined.
    private func languageInstruction(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage,
              lang != .undetermined,
              lang != .english else { return "" }
        let name = Locale(identifier: "en_US").localizedString(forLanguageCode: lang.rawValue) ?? lang.rawValue
        return "Respond in \(name)."
    }

    // MARK: - Enhance Generators

    @available(iOS 26.0, *)
    private func enhanceCaptionWithLLM(context: EnhancePhotoCaptionContext) async -> String? {
        let langLine = languageInstruction(for: context.userText)
        let langInstruction = langLine.isEmpty ? "" : "\n\(langLine)"

        let instructions = """
            You help people write their travel blog. \
            A user has written a rough photo caption. Complete and enrich it. \
            Keep the user's voice and key details. Complete any unfinished thought. \
            1 short sentence only — simple, warm, casual. Like texting a friend. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the caption. No preamble — just the text.
            """
        let prompt = """
            The user wrote: "\(context.userText)"\(langInstruction)
            \(userWritingStyleInstruction)

            Complete this into one short travel sentence. Output only the text.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func enhancePlaceStoryWithLLM(context: EnhancePlaceStoryContext) async -> String? {
        let langLine = languageInstruction(for: context.userText)
        let langInstruction = langLine.isEmpty ? "" : "\n\(langLine)"

        var contextLines: [String] = []
        if let tod = context.timeOfDay { contextLines.append("Time of day: \(tod)") }
        if let indoor = context.isIndoor { contextLines.append("Environment: \(indoor ? "indoor" : "outdoor")") }
        let contextBlock = contextLines.isEmpty ? "" : "\n" + contextLines.joined(separator: ", ") + "."

        let baseSystem = """
            You help people write their travel blog. \
            A user has written a rough note about a place they visited. \
            Complete and enrich it — keep their voice and key details, complete any unfinished thought. \
            Never introduce events, logistics, or mishaps (delays, cancellations, etc.) the user did not write or clearly imply. \
            1-2 short sentences max. Simple, warm, casual — like telling a friend. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the story. No preamble — just the text.
            """

        let instructions = [
            baseSystem,
            Self.groundedTravelBlogRules,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            The user wrote: "\(context.userText)"\(contextBlock)\(langInstruction)
            \(userWritingStyleInstruction)

            Complete and enrich this into a short travel blog note. Output only the story text.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func enhanceOverallPlaceStoryWithLLM(context: EnhanceOverallPlaceStoryContext) async -> String? {
        let captions = context.photoCaptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let captionsBlock = captions.isEmpty
            ? ""
            : "\nPhoto captions:\n" + captions.prefix(6).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let langLine = languageInstruction(for: context.userText)

        // Only surface the place name when it is a reliable proper noun.
        let placePart: String
        switch context.nameConfidence {
        case .official, .semi:
            let line = [context.placeName, context.placeSubtitle]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            placePart = line.isEmpty ? "" : "\nPlace: \(line)."
        case .generic:
            placePart = ""
        }

        let baseSystem = """
            You help people write their travel blog. \
            A user has written a rough summary for a place they visited. \
            Complete and enrich it — keep their voice, 1 short sentence only. \
            Simple, warm, casual — like telling a friend. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the story. No preamble — just the text.
            """

        let instructions = [
            baseSystem,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            The user wrote: "\(context.userText)"\(buildEnhanceInstructionBlock(
                userWritingStyleInstruction: userWritingStyleInstruction,
                languageInstruction: langLine,
                extraContext: [placePart, captionsBlock].joined()
            ))

            Finish this travel summary. Output only the text.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func enhanceDaySummaryWithLLM(context: EnhanceDayStoryContext) async -> String? {
        let stories = context.placeStories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let placesPart = stories.isEmpty ? "" : "Places visited: " + stories.prefix(5).joined(separator: ", ") + "."
        let datePart = context.dayDateText.isEmpty ? "" : "Date: \(context.dayDateText)."
        let langLine = languageInstruction(for: context.userText)

        let instructions = """
            You help people write their travel blog. \
            The user has started a one-sentence summary of their travel day. Your job is to complete and enrich it. \
            Rules (follow all strictly):
            • Preserve every specific detail the user already wrote.
            • Never introduce places, activities, travel mishaps, or details that the user did NOT mention.
            • No sentence repetition — the output must be a single, non-repetitive sentence.
            • No date in the output. Casual, warm, like telling a friend.
            • No hashtags. No emoji. No first person (no "I", "we", "my").
            • Output only the finished sentence. No preamble.
            """
        let prompt = """
            The user wrote: "\(context.userText)"\(buildEnhanceInstructionBlock(
                userWritingStyleInstruction: userWritingStyleInstruction,
                languageInstruction: langLine,
                extraContext: [datePart, placesPart].filter { !$0.isEmpty }.joined(separator: "\n")
            ))

            Complete this into one short day story. Output only the text.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    // MARK: - Narrative Generators

    @available(iOS 26.0, *)
    private func generatePlaceNarrativeWithLLM(context: PlaceNarrativeContext) async -> String? {
        let tagsLine = context.tags.isEmpty ? "general visit" : context.tags.prefix(10).joined(separator: ", ")
        var contextParts: [String] = []
        if let tod = context.timeOfDay { contextParts.append("Time of day: \(tod)") }
        if context.photoCount > 1 { contextParts.append("\(context.photoCount) photos taken") }
        let contextBlock = contextParts.isEmpty ? "" : "\nContext: " + contextParts.joined(separator: ", ") + "."
        let placePart: String
        switch context.nameConfidence {
        case .official, .semi:
            let line = [context.placeName, context.placeSubtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            placePart = line.isEmpty ? "" : "\nPlace: \(line)."
        case .generic:
            placePart = ""
        }
        let seedPart: String = {
            guard let s = context.existingStory else { return "" }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "" : "\nExisting note: \(t)"
        }()
        let instructions = [
            """
            You are a travel storytelling assistant in a mobile app called Bloggo.
            Write a very short travel-blog blurb about this place visit — plain language, no poetry padding.
            Stay close to the place line, tags, context, and any existing note. Do not invent plot or extra scenes.
            Rules:
            \(Self.compactNarrativeFormatRules)
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            Output only the story text. No preamble — just the lines.
            """,
            Self.groundedTravelBlogRules,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")
        let prompt = """
            Write at most 3 sentences (one sentence per line) for this place.\(placePart)\(contextBlock)\(seedPart)
            Tags: \(tagsLine).
            Output only those lines. No introduction, no first person.
            """
        guard let raw = await runSession(instructions: instructions, prompt: prompt) else { return nil }
        return Self.clampNarrativeLineCount(raw)
    }

    @available(iOS 26.0, *)
    private func generateDayNarrativeWithLLM(context: DayNarrativeContext) async -> String? {
        let placesBlock: String
        if context.placeEntries.isEmpty {
            placesBlock = "No places recorded."
        } else {
            placesBlock = context.placeEntries.enumerated().map { idx, entry in
                let story = entry.story.trimmingCharacters(in: .whitespacesAndNewlines)
                return story.isEmpty ? "\(idx + 1). \(entry.name)" : "\(idx + 1). \(entry.name): \(story)"
            }.joined(separator: "\n")
        }
        let datePart = context.dayDateText.isEmpty ? "" : "Date: \(context.dayDateText)."
        let weatherPart: String = {
            guard let w = context.weatherSummary, !w.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            return " Weather: \(w)."
        }()
        let instructions = """
            You are a travel storytelling assistant in a mobile app called Bloggo.
            Write a very short travel-blog summary of this day — plain language, no filler.
            Connect the listed places using only their names and the place stories provided — do not invent a plot, setbacks, or travel logistics not present there.
            Rules:
            \(Self.compactNarrativeFormatRules)
            • Order may follow the list when it helps readability.
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            \(Self.groundedTravelBlogRules)
            Output only the lines. No preamble — just the text.
            """
        let prompt = """
            Write at most 3 sentences (one sentence per line) for this travel day from the evidence below only.
            \(datePart)\(weatherPart)

            Places visited:
            \(placesBlock)

            Output only those lines. No first person (I/we/my).
            """
        guard let raw = await runSession(instructions: instructions, prompt: prompt) else { return nil }
        return Self.clampNarrativeLineCount(raw)
    }

    @available(iOS 26.0, *)
    private func generateTripNarrativeWithLLM(context: TripNarrativeContext) async -> String? {
        let daySummariesBlock = context.daySummaries.prefix(7).enumerated()
            .map { "Day \($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
        let locationLine = context.locationChain.isEmpty
            ? ""
            : "Locations: " + context.locationChain.joined(separator: " → ") + "."
        let instructions = """
            You are a travel storytelling assistant in a mobile app called Bloggo.
            Write a very short trip introduction for the top of a travel blog — plain language, no filler.
            Derive every beat from the trip title, date span, location line, and day summaries — no invented itinerary twists or travel mishaps.
            Rules:
            \(Self.compactNarrativeFormatRules)
            • Tone is reflective and plain, not theatrical — mood only when supported by the day summaries.
            • Reference the places visited naturally — not as a bare comma-separated list.
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            \(Self.groundedTravelBlogRules)
            Output only the lines. No preamble — just the text.
            """
        let prompt = """
            Write at most 3 sentences (one sentence per line) as the trip opening from this data only.
            Trip: \(context.tripTitle).
            Dates: \(context.dateRangeText) (\(context.dayCount) days).
            \(locationLine)

            Day summaries:
            \(daySummariesBlock)

            Output only those lines. No first person (I/we/my).
            """
        guard let raw = await runSession(instructions: instructions, prompt: prompt) else { return nil }
        return Self.clampNarrativeLineCount(raw)
    }

    // MARK: - POI Name Classification (LLM)

    @available(iOS 26.0, *)
    private func classifyConcretePoiNameWithLLM(_ name: String) async -> Bool? {
        let instructions = """
            You classify geographic names. Answer with exactly one word: YES or NO. No punctuation, no explanation.
            YES = a specific named venue, landmark, or point of interest (e.g. "Eiffel Tower", "Central Park", "McDonald's", "Gyeongbokgung Palace", "Tokyo Station", "Louvre Museum")
            NO = a neighborhood, street, road, highway, district, city, or generic area (e.g. "Gangnam-gu", "5th Avenue", "Highway 101", "Manhattan", "Shibuya", "SoHo")
            """
        let prompt = "Is \"\(name)\" a specific named venue or landmark? Answer YES or NO."
        guard let result = await runSession(instructions: instructions, prompt: prompt) else { return nil }
        return result.uppercased().hasPrefix("YES")
    }

    // MARK: - Sentiment Analysis

    @available(iOS 26.0, *)
    private func analyzeSentimentWithLLM(text: String) async -> Int? {
        // Non-English captions cause the model to respond with non-digit output (e.g. Korean
        // punctuation or words), breaking the strict single-digit parse. Translate first so the
        // classifier always sees English text.
        let analyzeText: String
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let dominant = recognizer.dominantLanguage
        let isNonEnglish = dominant != nil && dominant != .english && dominant != .undetermined
        if isNonEnglish, let translated = await translateTextWithLLM(userText: text) {
            analyzeText = translated
        } else {
            analyzeText = text
        }

        let instructions = """
            You are a sentiment classifier for travel captions. \
            Read the text and decide if the overall sentiment is positive, neutral, or negative. \
            Respond with exactly one digit: 3 for positive, 2 for neutral, 1 for negative. \
            No explanation, no punctuation — just the single digit.
            """
        let prompt = "Classify the sentiment of this travel caption:\n\"\(analyzeText)\""
        guard let result = await runSession(instructions: instructions, prompt: prompt) else { return nil }
        let digit = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if digit == "1" { return 1 }
        if digit == "3" { return 3 }
        return 2
    }

    // MARK: - Session Runner

    @available(iOS 26.0, *)
    private func buildEnhanceInstructionBlock(
        userWritingStyleInstruction: String,
        languageInstruction: String,
        extraContext: String
    ) -> String {
        let context = extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = languageInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !context.isEmpty { lines.append(context) }
        lines.append(userWritingStyleInstruction)
        if !language.isEmpty { lines.append(language) }
        return lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n")
    }

    // MARK: - Translate

    @available(iOS 26.0, *)
    private func translateTextWithLLM(userText: String) async -> String? {
        let instructions = """
            You are a translator. Translate the given text to English. \
            Output only the translated text. Preserve the original meaning and tone exactly. \
            Do not add, remove, or change any content. No preamble — just the translation.
            """
        let prompt = "Translate this to English:\n\n\(userText)"
        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func runSession(instructions: String, prompt: String) async -> String? {
        print("[LLM] runSession — prompt prefix: \(prompt.prefix(120))")
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            print("[LLM] runSession — result: \(text.prefix(120))")
            return text.isEmpty ? nil : text
        } catch {
            print("[LLM] runSession — error: \(error)")
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func generateFunPhotoInsightWithLLM(
        tags: [String],
        placeName: String,
        placeSubtitle: String?,
        visitDaypart: String,
        userCaptionHint: String?,
        categoryID: PlaceCategoryID
    ) async -> String? {
        let importantTags = Array(tags.prefix(12))
        let tagsLine = "Photo tags (on-device Vision / image analysis): \(importantTags.joined(separator: ", "))."
        let trimmedPlace = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeLine: String
        if trimmedPlace.isEmpty {
            placeLine = ""
        } else if let sub = placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            placeLine = "\nPlace name and area from the trip: \(trimmedPlace), \(sub)."
        } else {
            placeLine = "\nPlace name from the trip: \(trimmedPlace)."
        }
        let trimmedDaypart = visitDaypart.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeLine = trimmedDaypart.isEmpty ? "" : "\nApproximate time of day at capture (local): \(trimmedDaypart). Do not mention clock times or exact dates."
        let hintLine: String
        if let h = userCaptionHint?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            hintLine = "\nTraveler draft (optional tone only; must not contradict the tags): \"\(h)\""
        } else {
            hintLine = ""
        }
        let categoryBlock: String
        if categoryID == .unknown {
            categoryBlock = ""
        } else {
            categoryBlock = "\n\nPlace category hint for tone (do not invent specifics beyond tags + place name):\n" + categoryModifier(for: categoryID)
        }

        let instructions = """
            You write travel-blog microcopy: warm, readable, a little vivid — but never speculative. \
            Use ONLY facts supported by the photo tags, place name/area, optional place category hint, and approximate daypart (never clock times or exact dates). \
            Tags come from on-device Vision analysis — they are the ground truth for what appears in the image. \
            Do not invent people, relationships, events, business names, dish names, or landmarks not clearly supported. \
            At airports or transit hubs, do not assume flights, delays, or boarding unless tags or place text clearly support it. \
            At most two sentences total. Short clauses, blog cadence — not stiff, not marketing fluff. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the two sentences (or one if that fits the evidence). No preamble or quotation marks.
            """ + categoryBlock

        let prompt = """
            Turn the hints below into a tiny travel-blog moment — only what the evidence supports.\(hintLine)

            \(tagsLine)\(placeLine)\(timeLine)

            Maximum two sentences. Every phrase must be traceable to the tags, place lines, category hint, or daypart.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generatePlaceLevelAIShortStoryWithLLM(
        tags: [String],
        photoCaptions: [String],
        placeName: String,
        placeSubtitle: String?,
        categoryID: PlaceCategoryID,
        visitDaypart: String,
        photoCount: Int
    ) async -> String? {
        let tagsLine = tags.isEmpty
            ? "Aggregated on-device photo tags: none."
            : "Aggregated on-device photo tags: \(tags.prefix(16).joined(separator: ", "))."
        let caps = photoCaptions.prefix(6)
        let captionsBlock = caps.isEmpty
            ? "Existing photo captions from this stop: none."
            : "Existing photo captions from this stop (may be empty or AI — treat only as optional hints, never override clear tag facts):\n"
                + caps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let trimmedPlace = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeLine: String
        if trimmedPlace.isEmpty {
            placeLine = ""
        } else if let sub = placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            placeLine = "\nPlace: \(trimmedPlace), \(sub)."
        } else {
            placeLine = "\nPlace: \(trimmedPlace)."
        }
        let countLine = photoCount > 1 ? "\nThis stop has \(photoCount) photos in the trip." : "\nThis stop has one photo in the trip."
        let trimmedDaypart = visitDaypart.trimmingCharacters(in: .whitespacesAndNewlines)
        let daypartLine = trimmedDaypart.isEmpty ? "" : "\nApproximate time of day for the visit (from capture times): \(trimmedDaypart). Do not mention clock times or exact dates."
        let categoryBlock: String
        if categoryID == .unknown {
            categoryBlock = ""
        } else {
            categoryBlock = "\n\nPlace category hint (tone only; do not invent specifics):\n" + categoryModifier(for: categoryID)
        }

        let instructions = """
            You write very short travel-blog blurbs for a single stop on a trip. \
            At most two sentences. Warm, readable blog voice — not marketing, not a tag list, not a photo-by-photo recap. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Never output clock times or full calendar dates — daypart words only when timing matters. \
            Output only the two sentences (or one). No preamble or quotation marks.
            """ + categoryBlock + "\n\n" + Self.placeStopBlogBlurbRules + "\n\n" + Self.groundedTravelBlogRules

        let prompt = """
            Write a tiny travel-blog moment for this stop using only the evidence below.

            \(tagsLine)
            \(captionsBlock)
            \(placeLine)\(countLine)\(daypartLine)

            Maximum two sentences. Stay grounded in the hints.
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

#endif
}
