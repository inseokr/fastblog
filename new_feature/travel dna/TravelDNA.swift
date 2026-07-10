//
//  TravelDNA.swift
//  Bloggo — build a "Travel DNA" from a user's photo captions.
//
//  Given (photo, caption) pairs — the caption is the description produced by the ③/④ paths —
//  this classifies each photo into a MAJOR category + SUBCATEGORY, aggregates them, and produces
//  a Travel DNA profile (persona types with counts/percent), like the concept mockup.
//
//  Two classifiers:
//    • LLM (Foundation Models, iOS 26+) with guided generation — most accurate for free text.
//    • Keyword fallback — deterministic, offline, works today with no model.
//
//  Self-contained: pass in captions (Strings). No Bloggo/Capper dependency.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Taxonomy (major → info + subcategories + fallback keywords)

enum TravelCategory: String, CaseIterable, Codable {
    case animals, nature, food, alcohol, cafe, sports, hiking, beach, culture, urban, other
}

struct CategoryInfo {
    let title: String          // persona title, e.g. "Café Explorer"
    let emoji: String
    let subcategories: [String]
    let keywords: [String]     // used by the keyword fallback
}

// Persona taxonomy. `keywords` are matched as WHOLE WORDS (see classifyByKeywords), so short
// words like "bar", "art", "sea" no longer accidentally match "harbor", "heart", "research".
// Multi-word keywords (e.g. "street food") are matched as phrases and weighted higher.
let travelTaxonomy: [TravelCategory: CategoryInfo] = [
    .animals: .init(title: "Wildlife Watcher", emoji: "🦅",
        subcategories: ["birds", "marine life", "wildlife", "pets", "zoo"],
        keywords: ["animal", "animals", "falcon", "bird", "birds", "eagle", "dog", "cat",
                   "wildlife", "raptor", "fish", "zoo", "horse", "deer", "bear", "owl",
                   "penguin", "seal", "whale", "dolphin", "squirrel"]),
    .nature: .init(title: "Nature Lover", emoji: "🌿",
        subcategories: ["forest", "river", "lake", "sunset"],
        keywords: ["nature", "forest", "woods", "tree", "trees", "pine", "pines", "canopy",
                   "river", "lake", "pond", "waterfall", "sunset", "sunrise", "garden",
                   "flower", "flowers", "meadow", "field", "greenery", "foliage"]),
    .food: .init(title: "Foodie", emoji: "🍽️",
        subcategories: ["sushi", "street food", "plated dish", "dessert"],
        keywords: ["food", "dish", "meal", "sushi", "sashimi", "beef", "bowl", "sandwich",
                   "plate", "platter", "restaurant", "dessert", "cake", "noodle", "ramen",
                   "brunch", "lunch", "dinner", "gelato", "pizza", "burger", "seafood",
                   "street food", "izakaya", "diner", "bakery", "pastry"]),
    .alcohol: .init(title: "Bar Hopper", emoji: "🍺",
        subcategories: ["beer", "wine", "cocktail", "brewery"],
        keywords: ["beer", "wine", "cocktail", "cocktails", "bar", "pub", "soju", "whisky",
                   "whiskey", "brewery", "sake", "champagne", "tavern", "winery", "nightlife"]),
    .cafe: .init(title: "Café Explorer", emoji: "☕",
        subcategories: ["latte art", "coffee", "tea", "brunch"],
        keywords: ["café", "cafe", "coffee", "latte", "latte art", "espresso", "cappuccino",
                   "bubble tea", "matcha", "barista", "mocha", "americano"]),
    .sports: .init(title: "Active Traveler", emoji: "🏃",
        subcategories: ["cycling", "skiing", "water sports", "gym"],
        keywords: ["gym", "fitness", "workout", "cycling", "bike", "bicycle", "running",
                   "soccer", "basketball", "tennis", "yoga", "ski", "skiing", "snowboard",
                   "kayak", "stadium", "golf", "marathon"]),
    .hiking: .init(title: "Trail Seeker", emoji: "🥾",
        subcategories: ["trail", "summit", "viewpoint", "suspension bridge"],
        keywords: ["hike", "hiking", "trail", "suspension bridge", "summit", "trek",
                   "viewpoint", "backpack", "peak", "trailhead", "lookout", "mountain",
                   "ridge", "cliff", "canyon", "valley"]),
    .beach: .init(title: "Coast Chaser", emoji: "🌊",
        subcategories: ["beach", "ocean", "waves", "harbor"],
        keywords: ["beach", "ocean", "sea", "waves", "wave", "harbor", "harbour", "coast",
                   "coastline", "shore", "seaside", "pier", "boardwalk", "sand", "surf",
                   "bay", "tide", "lighthouse"]),
    .culture: .init(title: "Culture Seeker", emoji: "🏛️",
        subcategories: ["museum", "landmark", "temple", "architecture"],
        keywords: ["museum", "gallery", "temple", "shrine", "church", "cathedral", "mural",
                   "landmark", "monument", "architecture", "castle", "palace", "heritage",
                   "historic", "sculpture", "exhibit"]),
    .urban: .init(title: "City Wanderer", emoji: "🌆",
        subcategories: ["skyline", "street scene", "neon", "market"],
        keywords: ["skyline", "downtown", "street", "streets", "cityscape", "city", "market",
                   "neon", "alley", "plaza", "square", "shopping", "storefront", "signage",
                   "crosswalk", "subway", "rooftop"]),
    .other: .init(title: "Explorer", emoji: "🧭", subcategories: [], keywords: [])
]

// MARK: - Classification result

struct PhotoClassification: Codable, Equatable {
    let major: TravelCategory
    let subcategory: String?
    let confidence: Double     // 0–1
}

// MARK: - Travel DNA output

struct Persona: Identifiable {
    var id: String { category.rawValue }
    let category: TravelCategory
    let title: String
    let emoji: String
    let count: Int
    let percent: Double        // 0–100
    let topSubcategories: [String]
}

struct TravelDNA {
    let personas: [Persona]    // sorted, highest first
    let total: Int
    let headline: String       // e.g. "Café Explorer & Nature Lover"
    var summary: String        // one-line lifestyle blurb
}

// MARK: - Engine

enum TravelDNAEngine {

    /// Build the full Travel DNA from captions. Set `useLLM` to prefer Foundation Models.
    static func buildDNA(captions: [String], useLLM: Bool = true) async -> TravelDNA {
        var classifications: [PhotoClassification] = []
        for caption in captions {
            classifications.append(await classify(caption, useLLM: useLLM))
        }
        return aggregate(classifications)
    }

    /// Classify one caption. Tries the LLM (if requested/available), else keyword fallback.
    static func classify(_ caption: String, useLLM: Bool = true) async -> PhotoClassification {
        if useLLM, let llm = await classifyByLLM(caption) { return llm }
        return classifyByKeywords(caption)
    }

    /// Classify a batch of captions, one result per caption (same order). Lets the UI pair each
    /// photo with its category so tapping a persona shows the right photos.
    static func classifyBatch(_ captions: [String], useLLM: Bool = true) async -> [PhotoClassification] {
        var out: [PhotoClassification] = []
        out.reserveCapacity(captions.count)
        for c in captions { out.append(await classify(c, useLLM: useLLM)) }
        return out
    }

    /// A photo counts toward a persona only above this confidence (keeps unrelated photos out).
    static let categoryMembershipThreshold = 0.5

    // MARK: Keyword classifier (deterministic, offline)

    static func classifyByKeywords(_ caption: String) -> PhotoClassification {
        let text = caption.lowercased()
        // Whole-word token set (letters only) so "bar" ≠ "harbor", "art" ≠ "heart", "sea" ≠ "season".
        let tokens = Set(text.split { !$0.isLetter }.map(String.init))

        /// A keyword matches if: (multi-word) it appears as a phrase, or (single word) it's a whole
        /// token — with light plural handling. Multi-word phrases score double (more specific).
        func matchWeight(_ kw: String) -> Int {
            if kw.contains(" ") { return text.contains(kw) ? 2 : 0 }
            if tokens.contains(kw) { return 1 }
            if tokens.contains(kw + "s") { return 1 }                    // café → cafés
            if kw.hasSuffix("s"), tokens.contains(String(kw.dropLast())) { return 1 }
            return 0
        }

        var best: (cat: TravelCategory, score: Int, sub: String?) = (.other, 0, nil)
        for (cat, info) in travelTaxonomy where cat != .other {
            var score = 0
            for kw in info.keywords { score += matchWeight(kw) }
            if score > best.score {
                // Prefer a matched subcategory label; else the first matched keyword.
                let sub = info.subcategories.first { matchWeight($0) > 0 }
                    ?? info.keywords.first { matchWeight($0) > 0 }
                best = (cat, score, sub)
            }
        }
        // score 0 → .other (low confidence). 1 hit → 0.65, grows with more evidence.
        let confidence = best.score == 0 ? 0.2 : min(1.0, 0.5 + 0.15 * Double(best.score))
        return PhotoClassification(major: best.cat, subcategory: best.sub, confidence: confidence)
    }

    // MARK: LLM classifier (Foundation Models guided generation)

    #if canImport(FoundationModels)
    /// Structured output the model must fill (guided generation keeps it valid).
    @Generable
    struct CaptionTag {
        @Guide(description: "Major category. Exactly one of: animals, nature, food, alcohol, cafe, sports, hiking, beach, culture, urban, other")
        var major: String
        @Guide(description: "A one- or two-word specific subcategory, e.g. sushi, latte, falcon, suspension bridge, mountain")
        var subcategory: String
    }
    #endif

    static func classifyByLLM(_ caption: String) async -> PhotoClassification? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(
                instructions: "You tag travel photos by lifestyle category from a caption. Choose the single best major category and a specific subcategory."
            )
            do {
                let response = try await session.respond(
                    to: "Caption: \"\(caption)\". Tag it.",
                    generating: CaptionTag.self
                )
                let tag = response.content
                let major = TravelCategory(rawValue: tag.major.lowercased()) ?? .other
                let sub = tag.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
                return PhotoClassification(major: major,
                                           subcategory: sub.isEmpty ? nil : sub,
                                           confidence: 0.9)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Aggregation → personas

    static func aggregate(_ classifications: [PhotoClassification]) -> TravelDNA {
        let total = max(classifications.count, 1)

        // Group by major category.
        let grouped = Dictionary(grouping: classifications, by: { $0.major })

        var personas: [Persona] = grouped.map { (cat, items) in
            let info = travelTaxonomy[cat] ?? travelTaxonomy[.other]!
            // Most common subcategories within this group.
            let subCounts = items.compactMap { $0.subcategory?.lowercased() }
                .reduce(into: [:]) { $0[$1, default: 0] += 1 }
            let topSubs = subCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            return Persona(
                category: cat,
                title: info.title,
                emoji: info.emoji,
                count: items.count,
                percent: Double(items.count) / Double(total) * 100.0,
                topSubcategories: Array(topSubs)
            )
        }
        // Sort by count desc, drop "other" unless it's all we have.
        personas.sort { $0.count > $1.count }
        let meaningful = personas.filter { $0.category != .other }
        let ranked = meaningful.isEmpty ? personas : meaningful

        let headline = ranked.prefix(2).map { $0.title }.joined(separator: " & ")
        let summary = templateSummary(ranked, total: total)

        return TravelDNA(personas: ranked, total: classifications.count,
                         headline: headline.isEmpty ? "Explorer" : headline, summary: summary)
    }

    // MARK: Lifestyle blurb

    /// Deterministic one-liner. Call `lifestyleSummary(_:)` for an LLM-written version.
    static func templateSummary(_ personas: [Persona], total: Int) -> String {
        guard let top = personas.first else { return "Not enough photos yet." }
        let second = personas.dropFirst().first
        if let second {
            return "You travel like a \(top.title.lowercased()) with a love of \(second.title.lowercased()) moments."
        }
        return "You travel like a \(top.title.lowercased())."
    }

    /// Optional: an LLM-written lifestyle paragraph from the aggregated DNA.
    static func lifestyleSummary(_ dna: TravelDNA) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let breakdown = dna.personas.prefix(4)
                .map { "\($0.title) \(Int($0.percent))%" }.joined(separator: ", ")
            let session = LanguageModelSession(
                instructions: "You describe a traveler's lifestyle warmly in 1–2 sentences, second person."
            )
            if let r = try? await session.respond(to: "Category mix: \(breakdown). Describe this traveler's style.") {
                return r.content
            }
        }
        #endif
        return dna.summary
    }
}
