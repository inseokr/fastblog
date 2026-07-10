import Foundation
import CoreLocation

/// Feature ③: Prof. Kim's 5-stage curation funnel.
/// 1 Quality(blur) → 2 Diversity(dedup) → 3 Aesthetics → 4 Narrative(time-of-day arc) → 5 Saliency
enum CurationPipeline {

    static func run(_ photos: [PhotoItem], targetRange: ClosedRange<Int> = 12...20) -> [FunnelStage] {
        var stages: [FunnelStage] = []
        stages.append(FunnelStage(name: "Original", criterion: "All photos with GPS", survivors: photos))

        // Stage 1 — Quality: Laplacian variance < 100 → dropped
        let s1 = photos.filter { $0.sharpness >= 100 }
        stages.append(FunnelStage(name: "1 Quality", criterion: "Laplacian var ≥ 100", survivors: s1))

        // Stage 2 — Diversity: same place + shot within 5 min → keep only the top-aesthetic one
        let s2 = dedupe(s1)
        stages.append(FunnelStage(name: "2 Diversity", criterion: "Near-duplicates → 1", survivors: s2))

        // Stage 3 — Aesthetics: cut the bottom 40%
        let sorted = s2.sorted { $0.aestheticScore > $1.aestheticScore }
        let keepCount = max(1, Int(Double(sorted.count) * 0.6))
        let s3 = Array(sorted.prefix(keepCount))
        stages.append(FunnelStage(name: "3 Aesthetics", criterion: "Remove bottom 40%", survivors: s3))

        // Stage 4 — Narrative: compress to target count while preserving ≥1 morning/midday/evening shot
        let s4 = narrativeArc(s3, target: targetRange.upperBound)
        stages.append(FunnelStage(name: "4 Narrative", criterion: "Preserve morning·midday·evening arc", survivors: s4))

        // Stage 5 — Saliency: remove photos with no clear subject (but keep a minimum count)
        var s5 = s4.filter { $0.hasSaliency }
        if s5.count < targetRange.lowerBound { s5 = s4 }   // avoid over-cutting
        stages.append(FunnelStage(name: "5 Saliency", criterion: "Salient subject present", survivors: s5))

        return stages
    }

    /// Hero (cover) photo = the top-aesthetic among the final survivors — input for feature ①
    static func heroPhoto(from stages: [FunnelStage]) -> PhotoItem? {
        stages.last?.survivors.max { $0.aestheticScore < $1.aestheticScore }
    }

    // MARK: - private

    private static func dedupe(_ photos: [PhotoItem]) -> [PhotoItem] {
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        var result: [PhotoItem] = []
        var group: [PhotoItem] = []

        func flush() {
            if let best = group.max(by: { $0.aestheticScore < $1.aestheticScore }) {
                result.append(best)
            }
            group.removeAll()
        }

        for photo in sorted {
            if let last = group.last,
               photo.timestamp.timeIntervalSince(last.timestamp) < 300,
               isNearby(photo, last) {
                group.append(photo)
            } else {
                flush()
                group = [photo]
            }
        }
        flush()
        return result
    }

    /// Nearby if within 120m (when both have GPS), or by time alone when GPS is absent
    private static func isNearby(_ a: PhotoItem, _ b: PhotoItem) -> Bool {
        guard a.hasGPS, b.hasGPS else { return true }
        let la = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
        let lb = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
        return la.distance(from: lb) < 120
    }

    /// Compress to `target` photos while preserving the time-of-day distribution
    /// (morning 5–11, midday 11–17, evening 17–23).
    /// Prof. Kim 💡: "12 morning-only photos make a flat blog" — guarantee ≥1 per slot.
    private static func narrativeArc(_ photos: [PhotoItem], target: Int) -> [PhotoItem] {
        guard photos.count > target else { return photos }
        let calendar = Calendar.current
        func slot(_ p: PhotoItem) -> Int {
            let h = calendar.component(.hour, from: p.timestamp)
            switch h { case 5..<11: return 0; case 11..<17: return 1; default: return 2 }
        }
        var bySlot: [Int: [PhotoItem]] = [:]
        for p in photos { bySlot[slot(p), default: []].append(p) }

        var picked: [PhotoItem] = []
        // Secure one representative (top-aesthetic) per time slot first
        for s in 0...2 {
            if let best = bySlot[s]?.max(by: { $0.aestheticScore < $1.aestheticScore }) {
                picked.append(best)
            }
        }
        // Fill remaining slots by overall aesthetic ranking
        let pickedIDs = Set(picked.map(\.id))
        let rest = photos.filter { !pickedIDs.contains($0.id) }
            .sorted { $0.aestheticScore > $1.aestheticScore }
        picked.append(contentsOf: rest.prefix(max(0, target - picked.count)))
        return picked.sorted { $0.timestamp < $1.timestamp }
    }
}
