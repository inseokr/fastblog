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

    // MARK: - Narrative Generation (LLM-only, no template fallback)

    /// Generates a 4–6 line narrative for a place visit. Returns nil when LLM is unavailable.
    func generatePlaceNarrative(context: PlaceNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generatePlaceNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

    /// Generates a 4–6 line narrative for a travel day. Returns nil when LLM is unavailable.
    func generateDayNarrative(context: DayNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateDayNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

    /// Generates a 5–6 line trip opening narrative. Returns nil when LLM is unavailable.
    func generateTripNarrative(context: TripNarrativeContext) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateTripNarrativeWithLLM(context: context)
        }
#endif
        return nil
    }

#if canImport(FoundationModels)

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
        case .street:
            return """
                This place is categorized as a street or general city area.
                Focus on atmosphere, movement, culture, small observations.
                Do not fabricate specific facts about the location.
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
        let tagsLine = context.tags.isEmpty ? "general visit" : context.tags.prefix(8).joined(separator: ", ")
        let timePart = context.dateTimeText.isEmpty ? "" : " When: \(context.dateTimeText)."
        let countPart = context.photoCount > 1 ? " \(context.photoCount) photos from this stop." : ""

        var contextLines: [String] = []
        if let tod = context.timeOfDay { contextLines.append("Time of day: \(tod)") }
        if let indoor = context.isIndoor { contextLines.append("Environment: \(indoor ? "indoor" : "outdoor")") }
        let contextBlock = contextLines.isEmpty ? "" : "\nContext:\n" + contextLines.joined(separator: "\n")

        let baseSystem = """
            You are a travel storytelling assistant inside a mobile app called Bloggo.
            Your job is to generate a short, engaging, emotionally inviting caption for a place visited during a trip.
            The caption should:
            • Feel natural and human
            • Be warm and vivid
            • Avoid sounding robotic or generic
            • Stay under 3 sentences
            • Focus on experience, atmosphere, and memory
            Do not invent false historical facts. Do not exaggerate unrealistically.
            Keep it grounded and authentic.
            No hashtags or emoji. No first person (no "I", "we", "my").
            Output only the caption text. No preamble like "Here is a caption" — just the caption.
            """

        let instructions = [
            baseSystem,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            Write a short story for this place visit.
            Tags: \(tagsLine).\(timePart)\(countPart)\(contextBlock)

            Output only the text. No introduction, no first person.
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
        let timePart = context.dateTimeText.isEmpty ? "" : " When: \(context.dateTimeText)."

        let captionsBlock = captions.isEmpty
            ? "No photo captions yet."
            : captions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let tagsLine = context.tags.prefix(8).joined(separator: ", ")
        let tagsPart = tagsLine.isEmpty ? "" : "\nPhoto analysis tags: \(tagsLine)."

        let baseSystem = """
            You are a travel storytelling assistant inside a mobile app called Bloggo.
            Your job is to write one very short sentence that summarizes a place visit for a travel blog.
            The sentence should feel natural, warm, and vivid.
            No hashtags or emoji. No first person (no "I", "we", "my"). No exact timestamp.
            Output only the sentence. No preamble, no labels — just the sentence.
            """

        let instructions = [
            baseSystem,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")

        let prompt = """
            Summarize these photo captions into one short sentence for this place.\(placePart)\(timePart)\(tagsPart)

            Photo captions:
            \(captionsBlock)

            Output only the text. No introduction, no first person.
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
            You write one short, vivid sentence that summarises a travel day for a blog. \
            You are given place stories from that day. Blend them into a single evocative sentence. \
            No hashtags or emoji. No first person (no "I", "we", "my"). No date mention. \
            Output only the sentence. No preamble, no labels — just the sentence.
            """
        let prompt = """
            Summarise this travel day into one vivid sentence.\(datePart)

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
        let tagsLine = context.tags.isEmpty ? "" : "\nPhoto tags: \(context.tags.prefix(8).joined(separator: ", "))."
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
        let tagsLine = context.tags.isEmpty ? "" : "\nPhoto tags: \(context.tags.prefix(8).joined(separator: ", "))."
        let timePart = context.dateTimeText.isEmpty ? "" : "\nVisited: \(context.dateTimeText)."
        let countPart = context.photoCount > 1 ? "\n\(context.photoCount) photos from this stop." : ""
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
            1-2 short sentences max. Simple, warm, casual — like telling a friend. \
            No hashtags or emoji. No first person (no "I", "we", "my"). \
            Output only the story. No preamble — just the text.
            """

        let instructions = [
            baseSystem,
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
        let langInstruction = langLine.isEmpty ? "" : "\n\(langLine)"

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
            • Never introduce places, activities, or details that the user did NOT mention.
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
            Write a vivid, personal travel story about a place visit in 4 to 6 lines of flowing prose.
            Rules:
            • 4 to 6 lines only — no bullet points, no headers.
            • Each sentence on its own line, separated by a single newline.
            • Rich sensory and emotional detail. Capture atmosphere and memory.
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            Output only the story text. No preamble — just the story.
            """,
            categoryModifier(for: context.categoryID),
            nameConfidenceModifier(for: context.nameConfidence, placeName: context.placeName)
        ].joined(separator: "\n\n")
        let prompt = """
            Write a 4-6 line travel story for this place.\(placePart)\(contextBlock)\(seedPart)
            Tags: \(tagsLine).
            Output only the story. No introduction, no first person.
            """
        return await runSession(instructions: instructions, prompt: prompt)
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
            Write a vivid, personal day story in 4 to 6 lines of flowing prose.
            Weave together the places and moments of the day into one coherent story arc.
            Rules:
            • 4 to 6 lines only — no bullet points, no headers.
            • Each sentence on its own line, separated by a single newline.
            • Show the rhythm of the day — where it started, how it flowed, how it felt.
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            Output only the story. No preamble — just the text.
            """
        let prompt = """
            Write a 4-6 line story for this travel day.
            \(datePart)\(weatherPart)

            Places visited:
            \(placesBlock)

            Output only the story. No first person (I/we/my).
            """
        return await runSession(instructions: instructions, prompt: prompt)
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
            Write a vivid trip opening story in 5 to 6 lines of flowing prose.
            This will appear at the top of the travel blog as the introduction.
            Rules:
            • 5 to 6 lines only — no bullet points, no headers.
            • Each sentence on its own line, separated by a single newline.
            • Capture the spirit and mood of the whole trip in an evocative opening.
            • Reference the places visited naturally — not as a list.
            • No hashtags, no emoji, no first person (no "I", "we", "my").
            • No labels, quotes, captions, or meta-text of any kind.
            • \(userWritingStyleInstruction)
            Output only the story. No preamble — just the text.
            """
        let prompt = """
            Write a 5-6 line opening story for this trip blog.
            Trip: \(context.tripTitle).
            Dates: \(context.dateRangeText) (\(context.dayCount) days).
            \(locationLine)

            Day summaries:
            \(daySummariesBlock)

            Output only the story. No first person (I/we/my).
            """
        return await runSession(instructions: instructions, prompt: prompt)
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

#endif
}
