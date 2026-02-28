//
//  LocalLLMStoryCaptionGenerator.swift
//  fastblog
//
//  Uses Apple's on-device Foundation Models (iOS 26+, Apple Intelligence) to generate
//  blog-style captions and place stories. Falls back to template when unavailable.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates blog-like captions and place stories using the on-device LLM when available.
final class LocalLLMStoryCaptionGenerator: StoryCaptionGeneratorProtocol, @unchecked Sendable {
    static let shared = LocalLLMStoryCaptionGenerator()

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

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateCaptionWithLLM(context: PhotoCaptionContext) async -> String? {
        let tagsLine = context.tags.isEmpty ? "no specific tags" : context.tags.prefix(8).joined(separator: ", ")
        let placeLine = [context.placeName, context.placeSubtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let placePart = placeLine.isEmpty ? "" : " Place: \(placeLine)."
        let timePart = context.dateTimeText.isEmpty ? "" : " When: \(context.dateTimeText)."

        let instructions = """
            You write short, warm photo captions for a travel blog. Be concise (1–2 sentences), evocative. \
            No hashtags or emoji. Do not use first person (no "I", "we", "my") — the people in the photo could be anyone; write in a neutral or descriptive tone. \
            Output only the caption. No preamble like "Here is a short caption" or "Sure, here is..." — just the caption text.
            """
        let prompt = """
            Write one short blog-style caption for this photo. \
            Image tags: \(tagsLine).\(placePart)\(timePart) \
            Output only the caption text. No introduction, no "Here is...", no first person (I/we/my).
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generatePlaceStoryWithLLM(context: PlaceStoryContext) async -> String? {
        let tagsLine = context.tags.isEmpty ? "general visit" : context.tags.prefix(8).joined(separator: ", ")
        let placeLine = [context.placeName, context.placeSubtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let placePart = placeLine.isEmpty ? "" : " Place: \(placeLine)."
        let timePart = context.dateTimeText.isEmpty ? "" : " When: \(context.dateTimeText)."
        let countPart = context.photoCount > 1 ? " \(context.photoCount) photos from this spot." : ""

        let instructions = """
            You write brief, engaging place stories for a travel blog. One or two sentences: what the place is like or what stands out. \
            No hashtags or emoji. Do not use first person (no "I", "we", "my") — the visitors could be anyone; write in a neutral or descriptive tone. \
            Output only the story. No preamble like "Here is a short story" or "Sure, here is..." — just the story text.
            """
        let prompt = """
            Write one short blog-style sentence about this place visit. \
            Vibe/tags: \(tagsLine).\(placePart)\(timePart)\(countPart) \
            Output only the story text. No introduction, no "Here is...", no first person (I/we/my).
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func generateOverallPlaceStoryWithLLM(context: OverallPlaceStoryContext) async -> String? {
        let captions = context.photoCaptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let placeLine = [context.placeName, context.placeSubtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let placePart = placeLine.isEmpty ? "" : " Place: \(placeLine)."
        let timePart = context.dateTimeText.isEmpty ? "" : " When: \(context.dateTimeText)."

        let captionsBlock: String
        if captions.isEmpty {
            captionsBlock = "No photo captions yet."
        } else {
            captionsBlock = captions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }

        let instructions = """
            You write one very short sentence that summarizes a place visit for a travel blog. \
            You are given the place name and the existing photo captions for that place. \
            Summarize them into a single, quick headline-style sentence. No first person (no "I", "we", "my"). \
            No exact timestamp please. \
            No hashtags or emoji. Output only the summary sentence. No preamble like "Here is a summary" — just the sentence.
            """
        let prompt = """
            Summarize these photo captions into one short sentence for this place.\(placePart)\(timePart)

            Photo captions:
            \(captionsBlock)

            Output only the one-sentence summary. No introduction, no first person (I/we/my).
            """

        return await runSession(instructions: instructions, prompt: prompt)
    }

    @available(iOS 26.0, *)
    private func runSession(instructions: String, prompt: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
#endif
}
