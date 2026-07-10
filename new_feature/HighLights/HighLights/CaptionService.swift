import Foundation
import UIKit
import CoreLocation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Caption generation + RAG OFF/ON comparison.
///
/// Reuses the caption paths from "Untitled Project 3":
/// - RAG OFF = the base path (see `baseCaption` below). By default this is ② `improvedCaption`
///   (Vision tags + iOS 26 text LLM, template fallback). When ENABLE_IOS27_MULTIMODAL is set it
///   switches to ④ `mapRichCaption` (raw lat/long → Apple Maps → image+text multimodal).
/// - RAG ON  = the same base path, plus LocalRAGStore retrieval to (a) correct the place name and
///   (b) inject grounded evidence sentences.
///
/// Both outputs are kept for side-by-side A/B in the UI, and the place name is exposed separately
/// so you can see exactly how much RAG changed it.
enum CaptionService {

    struct Pair {
        let noRAG: String
        let withRAG: String
        let retrieved: [RetrievedDoc]
        let placeNameNoRAG: String
        let placeNameRAG: String
        let noRAGMs: Double
        let ragMs: Double
        let basePathLabel: String     // which original path (② or ④) produced the base caption

        var placeNameChanged: Bool { placeNameNoRAG != placeNameRAG }
    }

    /// The base caption path. ④ (mapRich) is the intended production path but needs iOS 27 multimodal,
    /// so it only runs when ENABLE_IOS27_MULTIMODAL is defined; otherwise we use ② (improved), which
    /// works today. `mapRich` returns an empty string on older SDKs, so we fall back automatically.
    private static func baseCaption(_ image: UIImage, meta: PhotoMetadata) async -> (CaptionResult, String) {
        #if ENABLE_IOS27_MULTIMODAL
        let four = await mapRichCaption(image, meta: meta)   // ④ Map + Photo (multimodal)
        if !four.caption.isEmpty { return (four, "④ Map+Photo") }
        #endif
        let two = await improvedCaption(image, meta: meta)   // ② Vision tags + text LLM
        return (two, "② Improved")
    }

    static func captionPair(image: UIImage, meta: PhotoMetadata,
                            store: LocalRAGStore) async -> Pair {
        // ── RAG OFF: base path with the reverse-geocoded placeName as-is
        let (off, pathLabel) = await baseCaption(image, meta: meta)

        // ── RAG ON
        let start = DispatchTime.now().uptimeNanoseconds
        let query = [meta.placeName ?? "", off.caption].joined(separator: " ")
        let retrieved = store.retrieve(query: query, near: meta.coordinate)

        // (a) Place-name grounding: if a POI / verified-fact doc exists, correct the name to it
        var ragMeta = meta
        if let placeDoc = retrieved.first(where: { $0.doc.kind == .poi || $0.doc.kind == .placeFact }) {
            ragMeta.placeName = placeDoc.doc.title
        }

        // (b) Caption generation: if FM is available, inject retrieved context into the LLM;
        //     otherwise reuse the base path + append an evidence sentence
        var ragCaption: String
        if let llm = await groundedLLMCaption(meta: ragMeta, base: off.caption, retrieved: retrieved) {
            ragCaption = llm
        } else {
            ragCaption = (await baseCaption(image, meta: ragMeta)).0.caption
            // ③-b hard rule: only insert a fact sentence when a verified placeFact was retrieved; else omit
            if let fact = retrieved.first(where: { $0.doc.kind == .placeFact }) {
                ragCaption += " — \(fact.doc.text)"
            }
        }
        let ragMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0

        return Pair(noRAG: off.caption, withRAG: ragCaption, retrieved: retrieved,
                    placeNameNoRAG: meta.placeName ?? "(geocoding failed)",
                    placeNameRAG: ragMeta.placeName ?? "(geocoding failed)",
                    noRAGMs: off.elapsedMs, ragMs: ragMs, basePathLabel: pathLabel)
    }

    /// When FM (iOS 26+) is available: ground with "use only retrieved context, don't state unsupported facts"
    private static func groundedLLMCaption(meta: PhotoMetadata, base: String,
                                           retrieved: [RetrievedDoc]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability,
                  !retrieved.isEmpty else { return nil }
            let context = retrieved
                .map { "- [\($0.doc.kind.rawValue)] \($0.doc.title): \($0.doc.text)" }
                .joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You caption travel photos. Use ONLY the retrieved context below for place names \
                and facts. If the context does not support a fact, do NOT state it. \
                Output: one natural sentence, then 2-4 hashtags.
                """)
            let prompt = """
                Draft caption: \(base)
                Photo context: \(meta.promptContext())
                Retrieved:
                \(context)
                Rewrite the caption grounded in the retrieved context.
                """
            return try? await session.respond(to: prompt).content
        }
        #endif
        return nil
    }
}

/// Blog draft — two outputs (RAG OFF/ON).
/// OFF: place-name + time template. ON: quotes the user's own captions (「」) + verified-fact grounding.
enum BlogDraftService {

    struct Pair {
        let noRAG: String
        let withRAG: String
        let cited: [RetrievedDoc]
    }

    static func draftPair(clusters: [PlaceCluster], store: LocalRAGStore) async -> Pair {
        // ── RAG OFF
        let off = clusters.map { cluster in
            "\(timeLabel(cluster.arrival)) — stopped by \(cluster.name) for \(cluster.dwellMinutes) min. (\(cluster.photos.count) photos)"
        }.joined(separator: "\n")

        // ── RAG ON
        var cited: [RetrievedDoc] = []
        var lines: [String] = []
        for cluster in clusters {
            let hits = store.retrieve(query: cluster.name, near: cluster.center, k: 2)
            cited += hits
            var line = "\(timeLabel(cluster.arrival)) \(cluster.name) — stayed \(cluster.dwellMinutes) min."
            if let cap = hits.first(where: { $0.doc.kind == .caption }) {
                line += " That moment: 「\(cap.doc.text)」"
            }
            if let fact = hits.first(where: { $0.doc.kind == .placeFact }) {
                line += " \(fact.doc.text)"
            }
            lines.append(line)
        }
        var on = lines.joined(separator: "\n")
        if let llm = await groundedDraft(lines: lines) { on = llm }

        return Pair(noRAG: off, withRAG: on, cited: cited)
    }

    private static func groundedDraft(lines: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: """
                You write a short first-person travel blog day-summary in English. \
                Use ONLY the facts and quoted captions provided — never invent details. \
                Keep quotes in 「」 as-is. 3-5 sentences.
                """)
            return try? await session.respond(to: lines.joined(separator: "\n")).content
        }
        #endif
        return nil
    }

    private static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "h a"
        return f.string(from: date)
    }
}
