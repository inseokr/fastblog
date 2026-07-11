//
//  BlogHighlightsContent.swift
//  Capper
//

import CoreLocation
import Foundation

enum BlogHighlightsStoryPendingStore {
    static let storageKey = "bloggo.highlightsStoryPending"

    private static let maximumStoredIds = 120

    static func ids(from rawValue: String) -> [String] {
        rawValue.isEmpty ? [] : rawValue.components(separatedBy: ",").filter { !$0.isEmpty }
    }

    static func contains(_ id: UUID, in rawValue: String) -> Bool {
        ids(from: rawValue).contains(id.uuidString)
    }

    static func appending(_ id: UUID, to rawValue: String) -> String {
        var ids = ids(from: rawValue)
        let value = id.uuidString
        ids.removeAll { $0 == value }
        ids.append(value)
        if ids.count > maximumStoredIds {
            ids.removeFirst(ids.count - maximumStoredIds)
        }
        return ids.joined(separator: ",")
    }

    static func removing(_ id: UUID, from rawValue: String) -> String {
        var ids = ids(from: rawValue)
        ids.removeAll { $0 == id.uuidString }
        return ids.joined(separator: ",")
    }

    static func markPending(_ id: UUID, defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: storageKey) ?? ""
        defaults.set(appending(id, to: rawValue), forKey: storageKey)
    }
}

struct BlogHighlightsTint: Equatable, Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let green = BlogHighlightsTint(red: 0.20, green: 0.70, blue: 0.48)
    static let amber = BlogHighlightsTint(red: 0.96, green: 0.62, blue: 0.16)
    static let blue = BlogHighlightsTint(red: 0.35, green: 0.58, blue: 0.96)
    static let purple = BlogHighlightsTint(red: 0.76, green: 0.42, blue: 0.92)
    static let rose = BlogHighlightsTint(red: 0.95, green: 0.36, blue: 0.52)
    static let cyan = BlogHighlightsTint(red: 0.20, green: 0.78, blue: 0.86)
}

struct BlogHighlightsContent: Equatable, Sendable {
    struct Stats: Equatable, Sendable {
        let dayCount: Int
        let placeCount: Int
        let photoCount: Int
    }

    struct Moment: Identifiable, Equatable, Sendable {
        let id: UUID
        let rank: Int
        let placeName: String
        let locationLine: String?
        let statLine: String
        let score: Int
        let photoCount: Int
        let assetIdentifier: String?
        let photoAssetIdentifiers: [String]
    }

    struct Fact: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case longestStay
            case shootingPeak
            case travelSpan
            case quietGap
            case topMoment
        }

        var id: String { kind.rawValue }
        let kind: Kind
        let icon: String
        let title: String
        let value: String
        let detail: String
        let tint: BlogHighlightsTint
    }

    struct ShootingPeak: Equatable, Sendable {
        let hour: Int
        let hourRange: String
        let photoCount: Int
        let line: String
    }

    struct SecondaryStat: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case travelSpan
            case longestStay
            case quietGap
        }

        var id: String { kind.rawValue }
        let kind: Kind
        let title: String
        let value: String
        let detail: String
        let tint: BlogHighlightsTint
    }

    struct TravelDNA: Equatable, Sendable {
        let name: String
        let why: String
        let iconSystemName: String
        let tint: BlogHighlightsTint
    }

    enum Page: Equatable, Identifiable, Sendable {
        case title
        case numbers
        case bestMoments([Moment])
        case shootingPeak(ShootingPeak)
        case secondaryStat(SecondaryStat)
        case travelDNA(TravelDNA)
        case endCard

        var id: String {
            switch self {
            case .title: return "title"
            case .numbers: return "numbers"
            case .bestMoments: return "bestMoments"
            case .shootingPeak: return "shootingPeak"
            case .secondaryStat(let stat): return "secondaryStat-\(stat.id)"
            case .travelDNA: return "travelDNA"
            case .endCard: return "endCard"
            }
        }

        var isEndCard: Bool {
            if case .endCard = self { return true }
            return false
        }

        var duration: TimeInterval {
            switch self {
            case .title: return 5
            case .numbers: return 5
            case .bestMoments(let moments): return max(3, TimeInterval(moments.count) * 3)
            case .shootingPeak: return 5
            case .secondaryStat: return 5
            case .travelDNA: return 6
            case .endCard: return 0
            }
        }

        var beatCount: Int {
            switch self {
            case .bestMoments(let moments): return max(1, moments.count)
            default: return 1
            }
        }
    }

    let blogId: UUID
    let title: String
    let dateRange: String
    let coverAssetIdentifier: String?
    let openingLine: String
    let stats: Stats
    let rankedMoments: [Moment]
    let facts: [Fact]
    let shootingPeak: ShootingPeak?
    let secondaryStat: SecondaryStat?
    let travelDNA: TravelDNA
    let pages: [Page]

    var isPlayable: Bool {
        pages.filter { !$0.isEndCard }.count >= 2 && pages.contains(.endCard)
    }

    static func build(
        from detail: RecapBlogDetail,
        distanceUnit: DistanceUnit = .miles
    ) -> BlogHighlightsContent {
        let includedStops = detail.days
            .flatMap(\.placeStops)
            .filter { !$0.includedPhotos.isEmpty }
        let includedPhotos = detail.allIncludedPhotos
        let stats = Stats(
            dayCount: detail.days.count,
            placeCount: includedStops.count,
            photoCount: includedPhotos.count
        )
        let dateRange = RecapBlogDay.tripCoverDateRangeText(from: detail.days)
        let coverAssetIdentifier = detail.selectedCoverPhotoIdentifier
            ?? includedPhotos
                .filter { $0.localIdentifier != nil }
                .max(by: { ($0.qualityScore?.totalScore ?? 0) < ($1.qualityScore?.totalScore ?? 0) })?
                .localIdentifier
            ?? includedPhotos.compactMap(\.localIdentifier).first

        let rankedMoments = Array(detail.highlightMomentsRanked.prefix(3)).enumerated().map { index, stop in
            let included = stop.includedPhotos
            let sortedAssetIds = included
                .sorted { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }
                .compactMap(\.localIdentifier)
            let score = Int(stop.highlightMomentScore.rounded())
            return Moment(
                id: stop.id,
                rank: index + 1,
                placeName: stop.cleanedPlaceTitle,
                locationLine: locationLine(for: stop, fallbackCountry: detail.countryName),
                statLine: "\(included.count) photo\(included.count == 1 ? "" : "s") - \(score) highlight score",
                score: score,
                photoCount: included.count,
                assetIdentifier: stop.coverPhoto?.localIdentifier ?? sortedAssetIds.first,
                photoAssetIdentifiers: sortedAssetIds
            )
        }

        let longestStay = longestStayFact(in: detail)
        let peak = shootingPeak(includedPhotos)
        let distance = totalTravelDistanceMeters(in: detail)
        let travelSpan = travelSpanFact(distance: distance, distanceUnit: distanceUnit)
        let quietGap = quietGapFact(includedPhotos)
        let topMoment = rankedMoments.first.map { moment in
            Fact(
                kind: .topMoment,
                icon: "star.fill",
                title: "Top Highlight",
                value: moment.placeName,
                detail: "\(moment.score) score - \(moment.photoCount) photo\(moment.photoCount == 1 ? "" : "s")",
                tint: .rose
            )
        }

        var facts: [Fact] = []
        if let longestStay { facts.append(longestStay) }
        if let peak {
            facts.append(
                Fact(
                    kind: .shootingPeak,
                    icon: "camera.aperture",
                    title: "Shooting Peak",
                    value: peak.hourRange,
                    detail: "\(peak.photoCount) photo\(peak.photoCount == 1 ? "" : "s") captured",
                    tint: .amber
                )
            )
        }
        if let travelSpan { facts.append(travelSpan) }
        if let quietGap { facts.append(quietGap) }
        if let topMoment { facts.append(topMoment) }

        let secondary = secondaryStat(distance: distance, distanceUnit: distanceUnit, longestStay: longestStay, quietGap: quietGap)
        let dna = travelDNA(for: detail, distance: distance)
        let openingLine = "\(stats.dayCount) day\(stats.dayCount == 1 ? "" : "s"), \(stats.placeCount) moment\(stats.placeCount == 1 ? "" : "s"), and \(stats.photoCount) photo\(stats.photoCount == 1 ? "" : "s") shaped this trip."

        var contentPages: [Page] = [.title]
        if stats.photoCount > 0 {
            contentPages.append(.numbers)
        }
        let countdownMoments = Array(rankedMoments.reversed())
        if !countdownMoments.isEmpty {
            contentPages.append(.bestMoments(countdownMoments))
        }
        if let peak {
            contentPages.append(.shootingPeak(peak))
        }
        if let secondary {
            contentPages.append(.secondaryStat(secondary))
        }
        contentPages.append(.travelDNA(dna))

        let pages = contentPages.count >= 2 ? contentPages + [.endCard] : []
        return BlogHighlightsContent(
            blogId: detail.id,
            title: detail.title,
            dateRange: dateRange,
            coverAssetIdentifier: coverAssetIdentifier,
            openingLine: openingLine,
            stats: stats,
            rankedMoments: rankedMoments,
            facts: Array(facts.prefix(5)),
            shootingPeak: peak,
            secondaryStat: secondary,
            travelDNA: dna,
            pages: pages
        )
    }

    private static func longestStayFact(in detail: RecapBlogDetail) -> Fact? {
        guard let stop = detail.days
            .flatMap(\.placeStops)
            .max(by: { $0.inferredVisitDurationSeconds < $1.inferredVisitDurationSeconds }),
            stop.inferredVisitDurationSeconds >= 10 * 60
        else { return nil }

        return Fact(
            kind: .longestStay,
            icon: "clock",
            title: "Longest Stay",
            value: stop.cleanedPlaceTitle,
            detail: durationText(seconds: stop.inferredVisitDurationSeconds),
            tint: .green
        )
    }

    private static func shootingPeak(_ photos: [RecapPhoto]) -> ShootingPeak? {
        guard !photos.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        let calendar = Calendar.current
        for photo in photos {
            counts[calendar.component(.hour, from: photo.timestamp), default: 0] += 1
        }
        guard let peak = counts.max(by: { $0.value < $1.value }) else { return nil }
        return ShootingPeak(
            hour: peak.key,
            hourRange: hourRangeText(startHour: peak.key),
            photoCount: peak.value,
            line: shootingPeakLine(hour: peak.key)
        )
    }

    private static func travelSpanFact(distance: CLLocationDistance, distanceUnit: DistanceUnit) -> Fact? {
        guard distance >= 100 else { return nil }
        return Fact(
            kind: .travelSpan,
            icon: "point.topleft.down.curvedto.point.bottomright.up",
            title: "Travel Span",
            value: formattedDistance(meters: distance, distanceUnit: distanceUnit),
            detail: "Inferred between clustered places",
            tint: .blue
        )
    }

    private static func quietGapFact(_ photos: [RecapPhoto]) -> Fact? {
        let sorted = photos.map(\.timestamp).sorted()
        guard sorted.count >= 2 else { return nil }
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        guard let maxGap = gaps.max(), maxGap >= 45 * 60 else { return nil }
        return Fact(
            kind: .quietGap,
            icon: "eye",
            title: "Quiet Gap",
            value: durationText(seconds: maxGap),
            detail: "A stretch with no photos, probably lived off-camera",
            tint: .purple
        )
    }

    private static func secondaryStat(
        distance: CLLocationDistance,
        distanceUnit: DistanceUnit,
        longestStay: Fact?,
        quietGap: Fact?
    ) -> SecondaryStat? {
        if distance >= 100 {
            let value = formattedDistance(meters: distance, distanceUnit: distanceUnit)
            return SecondaryStat(
                kind: .travelSpan,
                title: "Travel Span",
                value: value,
                detail: "Your route connected the story across \(value).",
                tint: .blue
            )
        }
        if let longestStay {
            return SecondaryStat(
                kind: .longestStay,
                title: "Longest Stay",
                value: longestStay.value,
                detail: "You lingered here for \(longestStay.detail).",
                tint: longestStay.tint
            )
        }
        if let quietGap {
            return SecondaryStat(
                kind: .quietGap,
                title: "Quiet Gap",
                value: quietGap.value,
                detail: "A little stretch of the trip happened off-camera.",
                tint: quietGap.tint
            )
        }
        return nil
    }

    private static func travelDNA(for detail: RecapBlogDetail, distance: CLLocationDistance) -> TravelDNA {
        let stops = detail.days.flatMap(\.placeStops)
        let titles = stops.map { ($0.placeTitle + " " + ($0.placeCategory ?? "")).lowercased() }.joined(separator: " ")
        if titles.contains("restaurant") || titles.contains("cafe") || titles.contains("coffee") || titles.contains("food") {
            return TravelDNA(name: "Taste Seeker", why: "Your memories clustered around meals, cafes, and local flavor.", iconSystemName: "fork.knife", tint: .amber)
        }
        if titles.contains("park") || titles.contains("beach") || titles.contains("mountain") || titles.contains("trail") {
            return TravelDNA(name: "Nature Logger", why: "Open air, landscapes, and slow-looking moments led the trip.", iconSystemName: "leaf.fill", tint: .green)
        }
        if titles.contains("museum") || titles.contains("landmark") || titles.contains("temple") || titles.contains("historic") {
            return TravelDNA(name: "Culture Seeker", why: "You kept finding places with stories older than the day.", iconSystemName: "building.columns.fill", tint: .purple)
        }
        if distance > 10_000 {
            return TravelDNA(name: "Active Traveler", why: "The route itself became part of what you remembered.", iconSystemName: "figure.walk", tint: .blue)
        }
        return TravelDNA(name: "Moment Collector", why: "You gathered the small scenes that made the trip feel yours.", iconSystemName: "camera.fill", tint: .rose)
    }

    private static func locationLine(for stop: PlaceStop, fallbackCountry: String?) -> String? {
        let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !subtitle.isEmpty {
            return subtitle
        }
        let country = fallbackCountry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return country.isEmpty ? nil : country
    }

    private static func totalTravelDistanceMeters(in detail: RecapBlogDetail) -> CLLocationDistance {
        let coords = detail.days
            .flatMap(\.placeStops)
            .compactMap { $0.representativeLocation?.clCoordinate ?? $0.photos.first?.location?.clCoordinate }
        guard coords.count >= 2 else { return 0 }
        return zip(coords, coords.dropFirst()).reduce(0) { total, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + end.distance(from: start)
        }
    }

    private static func formattedDistance(meters: CLLocationDistance, distanceUnit: DistanceUnit) -> String {
        switch distanceUnit {
        case .miles:
            return String(format: "%.1f mi", meters / 1609.34)
        case .kilometers:
            return String(format: "%.1f km", meters / 1000.0)
        }
    }

    private static func durationText(seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private static func hourRangeText(startHour: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ha"
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return "\(formatter.string(from: start).lowercased())-\(formatter.string(from: end).lowercased())"
    }

    private static func shootingPeakLine(hour: Int) -> String {
        switch hour {
        case 5..<11:
            return "Morning light was doing real work."
        case 11..<17:
            return "Afternoon was your camera's busiest shift."
        case 17..<21:
            return "Golden hour knew exactly where to find you."
        default:
            return "Night-mode energy made the album."
        }
    }
}
