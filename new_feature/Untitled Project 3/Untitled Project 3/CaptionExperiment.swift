//
//  CaptionExperiment.swift
//  KS2-13 Photo & Video Intelligence — standalone caption experiment
//
//  A SELF-CONTAINED experiment. It does NOT depend on the Bloggo/Capper project.
//  Drop this one file into a fresh SwiftUI app (or a Swift Playground app target) and run.
//
//  It implements THREE paths we want to compare, as three simple external functions.
//  ALL THREE now also take PhotoMetadata (capture time + GPS→place) and feed it to the model:
//    ① 기존 방식      existingCaption(_:meta:)       — Vision tags → template (+ time/place suffix).
//    ② 기존 방식 개선  improvedCaption(_:meta:)       — Vision tags + metadata → iOS 26 text LLM.
//    ③ 신기술         newTechCaption(_:meta:prompt:)  — iOS 27 multimodal (image + metadata prompt).
//
//  Metadata is injected as TEXT into the prompt (Vision only ever sees pixels). Everything runs
//  on-device; only PhotoMetadataService's reverse-geocode makes a network call (see that file).
//
//  Each returns a CaptionResult with the caption and a measured elapsed time, so the runner can
//  build the 3-way comparison table (execution time / accuracy / power) from the KS2-14 plan.
//
//  Requirements:
//    ① Vision tags + template:    iOS 15+. Works right now, no LLM.
//    ② Vision tags + text LLM:    iOS 26 + Apple Intelligence on.
//    ③ Multimodal (image+text):   iOS 27 SDK (WWDC26). API names are BETA — confirm via Xcode 27
//                                 autocomplete. Guarded so the file still compiles without it.
//

import Foundation
import Vision
import UIKit
import MapKit          // ④: Apple Maps POI / reverse-geocode enrichment
import CoreLocation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Result model

enum CaptionPath: String, CaseIterable, Hashable {
    case existing            // ① 기존 방식
    case existingImproved    // ② 기존 방식 개선
    case newTech             // ③ 신기술
    case mapRich             // ④ 위치정보(Apple Maps) + 사진설명
    case pcc                 // ⑤ PCC(Private Cloud Compute) + 위도·경도 + 사진설명

    /// Short UI label.
    var label: String {
        switch self {
        case .existing:         return "① Existing"
        case .existingImproved: return "② Improved"
        case .newTech:          return "③ New"
        case .mapRich:          return "④ Map + Photo"
        case .pcc:              return "⑤ PCC"
        }
    }
}

struct CaptionResult {
    let path: CaptionPath
    let caption: String
    let elapsedMs: Double
    let detail: String        // tags used / model availability / error, for the log
}

// MARK: - Small timing helper

@inline(__always)
private func measure() -> () -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    return { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0 }
}

// MARK: - Shared prompt for multimodal paths (③④⑤)

/// English instructions + required output format for the multimodal paths.
/// Key rule: do NOT just echo a geocoded place name — INFER the specific place (e.g. a
/// restaurant/café name) by combining the GPS coordinates with visual cues in the photo.
let blogAgentInstructions = """
You are an assistant that helps a traveler keep a photo blog. You receive a photo plus location \
hints (GPS coordinates and/or nearby places). Do NOT simply repeat a geocoded place name — infer \
the most likely SPECIFIC place by combining the coordinates with visual cues in the photo \
(signage, storefront, food, interior, landmarks). If it looks like a restaurant, café, or shop, \
estimate its likely name and type, and note that it is an estimate.

After proposing a place name, check whether it is consistent with what the photo actually shows \
(for example, a food photo should map to a restaurant or café, not an unrelated business). If the \
place name and the visual description do not match, reconsider once more. If they still do not \
match, do NOT force a specific name — give only an approximate, general location \
(e.g. "a restaurant near <area>") and clearly mark it as approximate.

Always answer in English, in exactly this format:
1. Time — when the photo was taken
2. Place — your best estimate of the specific place (name + short reasoning from GPS + visual cues)
3. Description (object, background, situation, people) — what is in the photo
4. Blog text — one short, natural blog paragraph
"""

/// Default English user prompt for the multimodal paths.
let blogAgentPrompt = "Analyze this travel photo together with the location hints, estimate the specific place, and respond in the required format."

// MARK: - ① 기존 방식 (existing) — Vision tags + template (+ metadata suffix)

/// Pure baseline: classify with Vision, then build a caption from a deterministic template.
/// No LLM. Metadata (time/place) is appended as a plain suffix, e.g. " — Seoul, June 2026".
func existingCaption(_ image: UIImage, meta: PhotoMetadata = PhotoMetadata()) async -> CaptionResult {
    let stop = measure()
    guard let cg = image.cgImage else {
        return CaptionResult(path: .existing, caption: "Photo", elapsedMs: stop(), detail: "no cgImage")
    }
    let tags = await classifyTags(cg)
    let caption = descriptiveCaption(tags: tags, meta: meta)
    return CaptionResult(path: .existing, caption: caption, elapsedMs: stop(),
                         detail: "vision+template tags=\(tags)")
}

// MARK: - ② 기존 방식 개선 (existing improved) — Vision tags + metadata + iOS 26 text LLM

/// Same Vision tags as ①, plus metadata, refined by a TEXT-ONLY on-device LLM (iOS 26).
/// Falls back to the template (+suffix) if the model isn't available, and marks that in `detail`.
func improvedCaption(_ image: UIImage, meta: PhotoMetadata = PhotoMetadata()) async -> CaptionResult {
    let stop = measure()
    guard let cg = image.cgImage else {
        return CaptionResult(path: .existingImproved, caption: "Photo", elapsedMs: stop(), detail: "no cgImage")
    }
    let tags = await classifyTags(cg)

    if let llm = await textLLMCaption(fromTags: tags, meta: meta) {
        return CaptionResult(path: .existingImproved, caption: llm, elapsedMs: stop(),
                             detail: "vision+textLLM tags=\(tags)")
    }
    return CaptionResult(path: .existingImproved,
                         caption: descriptiveCaption(tags: tags, meta: meta),
                         elapsedMs: stop(), detail: "LLM unavailable → template fallback tags=\(tags)")
}

// MARK: - ③ 신기술 (new technology) — iOS 27 multimodal (image + metadata prompt)

/// New path: feed the image AND a prompt (with metadata) into a single on-device multimodal session.
/// NOTE: the image-attachment API is an iOS 27 (WWDC26) beta feature; the exact initializer
/// name may differ — confirm with Xcode 27 autocomplete inside `Prompt { }`. Guarded so the
/// file still builds on older SDKs (returns a clear "unavailable" result).
func newTechCaption(_ image: UIImage,
                    meta: PhotoMetadata = PhotoMetadata(),
                    prompt: String = blogAgentPrompt) async -> CaptionResult {
    let stop = measure()

    // Append the photo's location/time (read from EXIF by PhotoMetadataService) as text hints.
    let ctx = meta.promptContext()
    let fullPrompt = ctx.isEmpty ? prompt : "\(prompt)\nLocation hints: \(ctx)"

    // The iOS 27 multimodal image-attachment API is NOT in the iOS 26 SDK, so putting `image`
    // inside the prompt builder doesn't compile yet. It's gated behind a custom flag so this
    // file builds today. When you move to Xcode 27:
    //   1) Build Settings ▸ "Active Compilation Conditions" ▸ add  ENABLE_IOS27_MULTIMODAL
    //   2) Fix the exact image-attachment API via autocomplete inside `Prompt { }`.
    #if canImport(FoundationModels) && ENABLE_IOS27_MULTIMODAL
    if #available(iOS 27.0, *) {
        guard case .available = SystemLanguageModel.default.availability else {
            return CaptionResult(path: .newTech, caption: "", elapsedMs: stop(),
                                 detail: "model unavailable on this device")
        }
        let session = LanguageModelSession(instructions: blogAgentInstructions)
        do {
            // iOS 27 multimodal (WWDC26 session 241): insert the image into the prompt as an
            // Attachment, alongside the text. If Xcode autocomplete shows a different name
            // (e.g. ImageAttachment), just swap `Attachment` below — the rest stays the same.
            let multimodalPrompt = Prompt {
                fullPrompt
                Attachment(image)
            }
            let result = try await session.respond(to: multimodalPrompt)
            return CaptionResult(path: .newTech, caption: result.content, elapsedMs: stop(),
                                 detail: "multimodal(image+meta) meta=[\(ctx)]")
        } catch {
            return CaptionResult(path: .newTech, caption: "", elapsedMs: stop(),
                                 detail: "error: \(error.localizedDescription)")
        }
    }
    #endif

    // Flag OFF (or pre-iOS 27): image-in-prompt not compiled, so ③ is a placeholder.
    return CaptionResult(path: .newTech, caption: "", elapsedMs: stop(),
                         detail: "needs iOS 27 multimodal (enable ENABLE_IOS27_MULTIMODAL)")
}

// MARK: - ④ Map-enriched (raw lat/long → Apple Maps → "location + photo description")

/// Based on ③, but takes the RAW coordinate and enriches it via Apple Maps (MapKit): nearest POI,
/// its category, admin area, and nearby landmarks. That richer place knowledge + the raw lat/long
/// are fed into the multimodal model together with the image, so the output is
/// "where it is (place + surroundings) + what's in the photo".
///
/// RAG hook: to use a retrieval store instead of / in addition to Apple Maps, replace
/// `AppleMapsContext.nearbyPlace(_:)` with your retriever and return the same `Place` shape.
func mapRichCaption(_ image: UIImage,
                    meta: PhotoMetadata = PhotoMetadata(),
                    prompt: String = blogAgentPrompt) async -> CaptionResult {
    let stop = measure()

    // 1) Enrich the raw coordinate via Apple Maps (falls back to reverse-geocode, then EXIF text).
    var locationText = meta.promptContext()
    if let coord = meta.coordinate {
        if let place = await AppleMapsContext.nearbyPlace(coord) {
            locationText = place.describe(latitude: coord.latitude, longitude: coord.longitude,
                                          date: meta.captureDate)
        } else {
            locationText += String(format: "\nCoordinates: lat %.5f, lng %.5f", coord.latitude, coord.longitude)
        }
    }
    let fullPrompt = locationText.isEmpty ? prompt : "\(prompt)\n[Location hints (Apple Maps)]\n\(locationText)"

    #if canImport(FoundationModels) && ENABLE_IOS27_MULTIMODAL
    if #available(iOS 27.0, *) {
        guard case .available = SystemLanguageModel.default.availability else {
            return CaptionResult(path: .mapRich, caption: "", elapsedMs: stop(),
                                 detail: "model unavailable on this device")
        }
        let session = LanguageModelSession(instructions: blogAgentInstructions)
        do {
            let mmPrompt = Prompt {
                fullPrompt
                Attachment(image)
            }
            let result = try await session.respond(to: mmPrompt)
            return CaptionResult(path: .mapRich, caption: result.content, elapsedMs: stop(),
                                 detail: "map+multimodal loc=[\(locationText.replacingOccurrences(of: "\n", with: " "))]")
        } catch {
            return CaptionResult(path: .mapRich, caption: "", elapsedMs: stop(),
                                 detail: "error: \(error.localizedDescription)")
        }
    }
    #endif

    return CaptionResult(path: .mapRich, caption: "", elapsedMs: stop(),
                         detail: "needs iOS 27 multimodal (enable ENABLE_IOS27_MULTIMODAL)")
}

// MARK: - Apple Maps context (retrieval source for ④)

enum AppleMapsContext {
    struct Place {
        let name: String?
        let category: String?
        let locality: String?
        let country: String?
        let nearbyPOIs: [String]

        /// Human-readable English block fed into the prompt as [Location hints].
        func describe(latitude: Double, longitude: Double, date: Date?) -> String {
            var parts: [String] = []
            if let name, !name.isEmpty { parts.append("Nearest place: \(name)") }
            if let category, !category.isEmpty { parts.append("Category: \(category)") }
            let admin = [locality, country].compactMap { $0 }.joined(separator: ", ")
            if !admin.isEmpty { parts.append("Area: \(admin)") }
            if !nearbyPOIs.isEmpty { parts.append("Nearby: \(nearbyPOIs.prefix(3).joined(separator: ", "))") }
            parts.append(String(format: "Coordinates: lat %.5f, lng %.5f", latitude, longitude))
            if let date {
                let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
                parts.append("Taken: \(df.string(from: date))")
            }
            return parts.joined(separator: "\n")
        }
    }

    /// Query Apple Maps for POIs near the coordinate (network call to Apple's servers).
    static func nearbyPlace(_ coord: CLLocationCoordinate2D) async -> Place? {
        let request = MKLocalPointsOfInterestRequest(center: coord, radius: 200) // 200 m
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), let first = response.mapItems.first else {
            return await reverseGeocodePlace(coord)
        }
        let names = response.mapItems.prefix(4).compactMap { $0.name }
        return Place(
            name: first.name,
            category: prettyCategory(first.pointOfInterestCategory),
            locality: first.placemark.locality,
            country: first.placemark.country,
            nearbyPOIs: Array(names.dropFirst())
        )
    }

    /// Fallback: Apple reverse geocoding (global). Uses areasOfInterest as "nearby landmarks".
    static func reverseGeocodePlace(_ coord: CLLocationCoordinate2D) async -> Place? {
        await withCheckedContinuation { cont in
            CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            ) { placemarks, _ in
                guard let p = placemarks?.first else { cont.resume(returning: nil); return }
                cont.resume(returning: Place(
                    name: p.name ?? p.areasOfInterest?.first,
                    category: nil,
                    locality: p.locality,
                    country: p.country,
                    nearbyPOIs: p.areasOfInterest ?? []
                ))
            }
        }
    }

    /// "MKPOICategoryCafe" → "Cafe".
    static func prettyCategory(_ c: MKPointOfInterestCategory?) -> String? {
        guard let raw = c?.rawValue else { return nil }
        return raw.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}

// MARK: - ⑤ PCC (Private Cloud Compute) — raw lat/long + photo → description

/// Like ③, but runs on the PCC SERVER model instead of the on-device model, and passes the
/// RAW latitude/longitude in the prompt. PCC offers a larger model + 32K context, useful when
/// you attach lots of context (multiple images / long retrieved text). Same unified Swift API —
/// the only change vs ③ is the model passed to LanguageModelSession.
///
/// Requirements: iOS 27, Apple Intelligence, network, AND the Private Cloud Compute entitlement
/// `com.apple.developer.private-cloud-compute` (a RESTRICTED entitlement — request it on the
/// Apple Developer site; needs a paid account + approved provisioning).
///
/// ⚠️ Calling PCC WITHOUT the entitlement is a FATAL error (process crash) that `catch` cannot
/// trap — it would take the whole experiment down. So this path is gated behind a SECOND flag,
/// `ENABLE_PCC`, which is OFF by default. Turn it on (Build Settings ▸ Active Compilation
/// Conditions ▸ add ENABLE_PCC) only AFTER the entitlement is approved and added to the target.
func pccCaption(_ image: UIImage,
                meta: PhotoMetadata = PhotoMetadata(),
                prompt: String = blogAgentPrompt) async -> CaptionResult {
    let stop = measure()

    // Build the location text with RAW coordinates (this path explicitly feeds lat/long).
    var locText = ""
    if let c = meta.coordinate {
        locText = String(format: "raw GPS lat %.6f, lng %.6f", c.latitude, c.longitude)
        if let p = meta.placeName, !p.isEmpty { locText += " (near: \(p))" }
    } else {
        locText = meta.promptContext()
    }
    let fullPrompt = locText.isEmpty ? prompt : "\(prompt)\nLocation hints (raw GPS): \(locText)"

    #if canImport(FoundationModels) && ENABLE_IOS27_MULTIMODAL && ENABLE_PCC
    if #available(iOS 27.0, *) {
        do {
            // ⑤ vs ③: only this model line differs — the PCC server model.
            // If autocomplete shows a different type name, swap PrivateCloudComputeLanguageModel().
            let session = LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(),
                instructions: blogAgentInstructions
            )
            let mmPrompt = Prompt {
                fullPrompt
                Attachment(image)
            }
            let result = try await session.respond(to: mmPrompt)
            return CaptionResult(path: .pcc, caption: result.content, elapsedMs: stop(),
                                 detail: "PCC(image+latlng) loc=[\(locText)]")
        } catch {
            return CaptionResult(path: .pcc, caption: "", elapsedMs: stop(),
                                 detail: "error (PCC entitlement/network?): \(error.localizedDescription)")
        }
    }
    #endif

    // PCC disabled (default): keeps the app from crashing when the entitlement is absent.
    return CaptionResult(path: .pcc, caption: "", elapsedMs: stop(),
                         detail: "PCC off — add com.apple.developer.private-cloud-compute entitlement, then define ENABLE_PCC")
}

// MARK: - Shared building blocks

/// Vision VNClassifyImageRequest → top tag identifiers. Uses Apple's precision/recall filter,
/// then falls back to the top-N by confidence so we never come back empty for a normal photo.
private func classifyTags(_ cg: CGImage, limit: Int = 6) async -> [String] {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch {
                cont.resume(returning: []); return
            }
            let sorted = (request.results ?? []).sorted { $0.confidence > $1.confidence }
            // Apple's recommended filter for classification.
            var picked = sorted.filter { $0.hasMinimumRecall(0.01, forPrecision: 0.7) }
            if picked.isEmpty { picked = Array(sorted.prefix(limit)) }   // fallback: top-N
            let tags = picked.prefix(limit)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            cont.resume(returning: Array(tags))
        }
    }
}

/// Descriptive template caption (no model): "At <place>, showing <tags> (<date>). #tag #tag".
/// Used by ① and as ②'s fallback so the output explains where + what, not just words.
private func descriptiveCaption(tags: [String], meta: PhotoMetadata) -> String {
    let subjects = Array(tags.prefix(3))
    var head: String
    if let place = meta.placeName, !place.isEmpty {
        head = subjects.isEmpty ? "At \(place)" : "At \(place), showing \(subjects.joined(separator: ", "))"
    } else {
        head = subjects.isEmpty ? "Photo" : "Showing \(subjects.joined(separator: ", "))"
    }
    if let date = meta.captureDate {
        let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
        head += " (\(df.string(from: date)))"
    }
    let tags = hashtagLine(from: tags)
    return tags.isEmpty ? head + "." : "\(head). \(tags)"
}

/// "#beach #sunset" from tags (spaces stripped, lowercased).
private func hashtagLine(from tags: [String], max: Int = 4) -> String {
    tags.prefix(max)
        .map { "#" + $0.replacingOccurrences(of: " ", with: "").lowercased() }
        .joined(separator: " ")
}

/// iOS 26 text-only Foundation Models: turn tags (+ metadata) into one caption sentence.
/// Returns nil if the model isn't available (older OS, AI off, unsupported chip).
private func textLLMCaption(fromTags tags: [String], meta: PhotoMetadata = PhotoMetadata()) async -> String? {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(
            instructions: """
            You are a travel blog assistant. From photo tags and optional context (time, place), \
            write ONE natural sentence describing where the photo is and what it shows, \
            then add 2–4 relevant hashtags on the same line. \
            Example: "Morning coffee by the harbor in Vancouver. #coffee #harbor #morning"
            """
        )
        let ctx = meta.promptContext()
        var prompt = "Tags: \(tags.joined(separator: ", "))."
        if !ctx.isEmpty { prompt += " Context: \(ctx)." }
        prompt += " Write the caption sentence followed by hashtags."
        do { return try await session.respond(to: prompt).content }
        catch { return nil }
    }
    #endif
    return nil
}

// MARK: - Experiment runner (3 paths)

/// One photo + its metadata. Use the SAME samples for all three paths.
struct PhotoSample {
    let image: UIImage
    let meta: PhotoMetadata
}

/// Runs all three paths over the same samples N times and prints a comparison log (paste into doc).
enum CaptionExperimentRunner {

    struct Row {
        let index: Int
        let existing: CaptionResult        // ①
        let improved: CaptionResult        // ②
        let newTech: CaptionResult         // ③
        let mapRich: CaptionResult         // ④
        let pcc: CaptionResult             // ⑤
    }

    /// Runs ONE path for one photo.
    private static func runOne(_ p: CaptionPath, _ image: UIImage, _ meta: PhotoMetadata) async -> CaptionResult {
        switch p {
        case .existing:         return await existingCaption(image, meta: meta)
        case .existingImproved: return await improvedCaption(image, meta: meta)
        case .newTech:          return await newTechCaption(image, meta: meta)
        case .mapRich:          return await mapRichCaption(image, meta: meta)
        case .pcc:              return await pccCaption(image, meta: meta)
        }
    }

    /// - Parameters:
    ///   - samples: fixed photo set with metadata (same set for all paths).
    ///   - repeats: repeat count per image for time averaging.
    ///   - paths: which of ①②③④⑤ to run. Unselected paths are marked "skipped".
    static func run(samples: [PhotoSample],
                    repeats: Int = 10,
                    paths: Set<CaptionPath> = Set(CaptionPath.allCases)) async -> [Row] {
        var rows: [Row] = []
        for (i, sample) in samples.enumerated() {
            let image = sample.image, meta = sample.meta
            var times: [CaptionPath: [Double]] = [:]
            var last: [CaptionPath: CaptionResult] = [:]

            for _ in 0..<max(repeats, 1) {
                for p in CaptionPath.allCases where paths.contains(p) {
                    let r = await runOne(p, image, meta)
                    times[p, default: []].append(r.elapsedMs)
                    last[p] = r
                }
            }

            func result(_ p: CaptionPath) -> CaptionResult {
                if let r = last[p], let ts = times[p], !ts.isEmpty {
                    return CaptionResult(path: p, caption: r.caption,
                                         elapsedMs: ts.reduce(0,+) / Double(ts.count), detail: r.detail)
                }
                return CaptionResult(path: p, caption: "", elapsedMs: 0, detail: "skipped")
            }

            rows.append(Row(index: i,
                            existing: result(.existing),
                            improved: result(.existingImproved),
                            newTech:  result(.newTech),
                            mapRich:  result(.mapRich),
                            pcc:      result(.pcc)))
        }
        printCSV(rows)
        return rows
    }

    /// Prints a CSV block for pasting into the results table.
    static func printCSV(_ rows: [Row]) {
        print("idx,existing_ms,existing_caption,improved_ms,improved_caption,newtech_ms,newtech_caption,maprich_ms,maprich_caption,pcc_ms,pcc_caption,pcc_detail")
        for r in rows {
            let line = [
                "\(r.index)",
                String(format: "%.1f", r.existing.elapsedMs), "\"\(r.existing.caption)\"",
                String(format: "%.1f", r.improved.elapsedMs), "\"\(r.improved.caption)\"",
                String(format: "%.1f", r.newTech.elapsedMs),  "\"\(r.newTech.caption)\"",
                String(format: "%.1f", r.mapRich.elapsedMs),  "\"\(r.mapRich.caption)\"",
                String(format: "%.1f", r.pcc.elapsedMs),      "\"\(r.pcc.caption)\"",
                "\"\(r.pcc.detail)\""
            ].joined(separator: ",")
            print(line)
        }
        if !rows.isEmpty {
            func avg(_ f: (Row) -> Double) -> Double { rows.map(f).reduce(0,+)/Double(rows.count) }
            print(String(format: "AVG,%.1f,,%.1f,,%.1f,,%.1f,,%.1f,,",
                         avg { $0.existing.elapsedMs },
                         avg { $0.improved.elapsedMs },
                         avg { $0.newTech.elapsedMs },
                         avg { $0.mapRich.elapsedMs },
                         avg { $0.pcc.elapsedMs }))
        }
    }
}
