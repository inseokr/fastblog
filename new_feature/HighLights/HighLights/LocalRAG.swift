import Foundation
import NaturalLanguage
import CoreSpotlight
import UniformTypeIdentifiers
import CoreLocation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device RAG local store — implements Prof. Seoin's iOS 27 RAG doc pattern in a form runnable today.
///
/// The doc's RAG loop: Retrieve (local index) → Augment (inject into prompt) → Generate (on-device model).
/// - Retrieve: NLEmbedding sentence-embedding cosine (doc §2-D) + keyword Jaccard fallback + GPS proximity bonus
/// - Index donation: Core Spotlight `CSSearchableItem` (doc §2-A recommended path — also works on iOS 18)
/// - The iOS 27 `SpotlightSearchTool` tool-calling path is behind the ENABLE_IOS27_RAG flag at the bottom
///
/// Index contents (no fabricated data):
/// - .poi        : Apple Maps POI search results (live, network)
/// - .caption    : the user's own photo captions produced by this app
/// - .placeFact  : bundled PlaceFacts.json — manually curated, verified facts only (the basis for the ③-b hard rule)
struct RAGDocument: Identifiable, Codable {
    enum Kind: String, Codable { case placeFact, poi, caption }
    let id: String
    let kind: Kind
    let title: String
    let text: String
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RetrievedDoc: Identifiable {
    let doc: RAGDocument
    let score: Double
    var id: String { doc.id }
}

final class LocalRAGStore {
    private(set) var docs: [String: RAGDocument] = [:]
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    init() { loadBundledPlaceFacts() }

    func add(_ doc: RAGDocument) {
        docs[doc.id] = doc
        donateToSpotlight(doc)
    }

    /// Optional bundled PlaceFacts.json — the rule is "only add verified facts".
    /// If the file is missing, it runs without a placeFact tier → all ③-b sentences are omitted (intended hard rule).
    private func loadBundledPlaceFacts() {
        guard let url = Bundle.main.url(forResource: "PlaceFacts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let facts = try? JSONDecoder().decode([RAGDocument].self, from: data) else { return }
        for fact in facts { docs[fact.id] = fact }
    }

    /// The Retrieve step. Documents below minScore are not returned — the basis for the
    /// "omit any sentence without retrieved evidence" hard rule.
    func retrieve(query: String, near: CLLocationCoordinate2D? = nil,
                  k: Int = 3, minScore: Double = 0.30,
                  kinds: Set<RAGDocument.Kind>? = nil) -> [RetrievedDoc] {
        var scored: [RetrievedDoc] = []
        for doc in docs.values {
            if let kinds, !kinds.contains(doc.kind) { continue }
            var score = similarity(query, doc.title + ". " + doc.text)
            if let near, let dc = doc.coordinate {
                let d = CLLocation(latitude: near.latitude, longitude: near.longitude)
                    .distance(from: CLLocation(latitude: dc.latitude, longitude: dc.longitude))
                if d < 300 { score += 0.4 } else if d < 2000 { score += 0.15 }
            }
            if score >= minScore { scored.append(RetrievedDoc(doc: doc, score: score)) }
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(k))
    }

    // MARK: - Similarity

    private func similarity(_ a: String, _ b: String) -> Double {
        // Primary: NLEmbedding sentence embeddings (on-device, doc §2-D)
        if let embedding,
           let va = embedding.vector(for: a.lowercased()),
           let vb = embedding.vector(for: b.lowercased()) {
            return cosine(va, vb)
        }
        // Fallback: token Jaccard (when the simulator has no embedding asset) — ×2 to match embedding scale
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count) * 2.0
    }

    private func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    // MARK: - Core Spotlight donation (doc §2-A: step 1 of "index → attach tool → respond")

    private func donateToSpotlight(_ doc: RAGDocument) {
        let attr = CSSearchableItemAttributeSet(contentType: .text)
        attr.title = doc.title
        attr.contentDescription = doc.text
        let item = CSSearchableItem(uniqueIdentifier: doc.id,
                                    domainIdentifier: "bloggo.rag.\(doc.kind.rawValue)",
                                    attributeSet: attr)
        CSSearchableIndex.default().indexSearchableItems([item])
    }
}

// MARK: - iOS 27 path (WWDC26 beta — confirm symbols via Xcode 27 autocomplete before enabling)
// Build Settings ▸ Active Compilation Conditions ▸ add ENABLE_IOS27_RAG.
// Once indexed via donateToSpotlight above, the built-in SpotlightSearchTool searches this index during generation.
#if canImport(FoundationModels) && ENABLE_IOS27_RAG
@available(iOS 27.0, *)
enum IOS27RAG {
    static func makeSession() -> LanguageModelSession {
        LanguageModelSession(
            tools: [SpotlightSearchTool()],   // symbol name is beta — confirm via autocomplete
            instructions: "Answer using the user's own indexed photo captions and place facts when relevant. If nothing relevant is retrieved, say so — do not invent facts."
        )
    }
}
#endif
