//
//  CreatedRecapBlogStore.swift
//  Capper
//

import Combine
import CoreLocation
import Foundation
import SwiftUI


enum BlogCloudStatus: String, Codable {
    case activePublic
    case archived
}

/// A recap blog that was created from a draft trip. Stored so we can hide the draft from Trips and show it in Landing Recents.
struct CreatedRecapBlog: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let sourceTripId: UUID
    let title: String
    let createdAt: Date
    let coverImageName: String
    let coverAssetIdentifier: String?
    let selectedPhotoCount: Int
    /// Country for Profile grouping; set when blog detail is built/saved.
    let countryName: String?
    /// Trip date range for display (e.g. "Jan 15 – 20, 2025"). Set when blog is created.
    let tripDateRangeText: String?
    /// When the blog was last saved/edited. Nil until user taps Save on the blog page.
    let lastEditedAt: Date?
    /// Trip date range (start/end) for excluding these dates from future scans. Nil if not set (e.g. older blogs).
    let tripStartDate: Date?
    let tripEndDate: Date?
    /// Whether this is a cloud blog (true) or local-only (false). Defaults to false (local-only).
    var isCloud: Bool
    /// Cloud status: activePublic or archived. Only meaningful for cloud blogs.
    var cloudStatus: BlogCloudStatus
    /// Total place stops across all days. Used for display.
    var totalPlaceVisitCount: Int
    /// Number of days in the trip. Used for display.
    var tripDurationDays: Int

    init(id: UUID = UUID(), sourceTripId: UUID, title: String, createdAt: Date, coverImageName: String, coverAssetIdentifier: String? = nil, selectedPhotoCount: Int, countryName: String? = nil, tripDateRangeText: String? = nil, lastEditedAt: Date? = nil, tripStartDate: Date? = nil, tripEndDate: Date? = nil, isCloud: Bool = false, cloudStatus: BlogCloudStatus = .activePublic, totalPlaceVisitCount: Int = 0, tripDurationDays: Int = 1) {
        self.id = id
        self.sourceTripId = sourceTripId
        self.title = title
        self.createdAt = createdAt
        self.coverImageName = coverImageName
        self.coverAssetIdentifier = coverAssetIdentifier
        self.selectedPhotoCount = selectedPhotoCount
        self.countryName = countryName
        self.tripDateRangeText = tripDateRangeText
        self.lastEditedAt = lastEditedAt
        self.tripStartDate = tripStartDate
        self.tripEndDate = tripEndDate
        self.isCloud = isCloud
        self.cloudStatus = cloudStatus
        self.totalPlaceVisitCount = totalPlaceVisitCount
        self.tripDurationDays = tripDurationDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceTripId = try c.decode(UUID.self, forKey: .sourceTripId)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        coverImageName = try c.decode(String.self, forKey: .coverImageName)
        coverAssetIdentifier = try c.decodeIfPresent(String.self, forKey: .coverAssetIdentifier)
        selectedPhotoCount = try c.decode(Int.self, forKey: .selectedPhotoCount)
        countryName = try c.decodeIfPresent(String.self, forKey: .countryName)
        tripDateRangeText = try c.decodeIfPresent(String.self, forKey: .tripDateRangeText)
        lastEditedAt = try c.decodeIfPresent(Date.self, forKey: .lastEditedAt)
        tripStartDate = try c.decodeIfPresent(Date.self, forKey: .tripStartDate)
        tripEndDate = try c.decodeIfPresent(Date.self, forKey: .tripEndDate)
        isCloud = try c.decodeIfPresent(Bool.self, forKey: .isCloud) ?? false
        cloudStatus = try c.decodeIfPresent(BlogCloudStatus.self, forKey: .cloudStatus) ?? .activePublic
        totalPlaceVisitCount = try c.decodeIfPresent(Int.self, forKey: .totalPlaceVisitCount) ?? 0
        tripDurationDays = try c.decodeIfPresent(Int.self, forKey: .tripDurationDays) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceTripId, forKey: .sourceTripId)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(coverImageName, forKey: .coverImageName)
        try c.encodeIfPresent(coverAssetIdentifier, forKey: .coverAssetIdentifier)
        try c.encode(selectedPhotoCount, forKey: .selectedPhotoCount)
        try c.encodeIfPresent(countryName, forKey: .countryName)
        try c.encodeIfPresent(tripDateRangeText, forKey: .tripDateRangeText)
        try c.encodeIfPresent(lastEditedAt, forKey: .lastEditedAt)
        try c.encodeIfPresent(tripStartDate, forKey: .tripStartDate)
        try c.encodeIfPresent(tripEndDate, forKey: .tripEndDate)
        try c.encode(isCloud, forKey: .isCloud)
        try c.encode(cloudStatus, forKey: .cloudStatus)
        try c.encode(totalPlaceVisitCount, forKey: .totalPlaceVisitCount)
        try c.encode(tripDurationDays, forKey: .tripDurationDays)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceTripId, title, createdAt, coverImageName, coverAssetIdentifier, selectedPhotoCount
        case countryName, tripDateRangeText, lastEditedAt, tripStartDate, tripEndDate
        case isCloud, cloudStatus, totalPlaceVisitCount, tripDurationDays
    }
}

@MainActor
final class CreatedRecapBlogStore: ObservableObject {
    static let shared = CreatedRecapBlogStore()

    @Published private(set) var recents: [CreatedRecapBlog] = []
    /// When true, landing shows "Recap Blog has been created!" banner; clear after 5–7 sec.
    @Published var showRecapCreatedBanner = false
    /// Set to true when a blog is created. Consumed by the view (TripsView) to trigger the banner at the appropriate time.
    @Published var pendingRecapCreated = false
    /// Set to true when a draft is saved on back navigation. Consumed by TripsView to show a toast.
    @Published var showDraftSavedToast = false
    /// Date ranges of active drafts (from TripsViewModel) to exclude from scans. Written by TripsViewModel.updateOccupiedRanges().
    var draftOccupiedRanges: [(start: Date, end: Date)] = []
    /// When true, TripsViewModel clears trips and re-runs default scan (e.g. after archive rules change).
    @Published var needsRescan: Bool = false
    private var tripDraftsBySourceId: [UUID: TripDraft] = [:]
    /// Persisted editable blog details; Save in RecapBlogPageView writes here.
    private var blogDetailsBySourceId: [UUID: RecapBlogDetail] = [:]
    private let clusteringService = PlaceStopClusteringService()

    // MARK: - Persistence

    private static let storageDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CreatedBlogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let recentsURL = storageDirectory.appendingPathComponent("recents.json")
    private static let tripDraftsURL = storageDirectory.appendingPathComponent("tripDrafts.json")
    private static let blogDetailsURL = storageDirectory.appendingPathComponent("blogDetails.json")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: Self.recentsURL),
           let decoded = try? Self.decoder.decode([CreatedRecapBlog].self, from: data) {
            recents = decoded
        }
        if let data = try? Data(contentsOf: Self.tripDraftsURL),
           let decoded = try? Self.decoder.decode([UUID: TripDraft].self, from: data) {
            tripDraftsBySourceId = decoded
        }
        if let data = try? Data(contentsOf: Self.blogDetailsURL),
           let decoded = try? Self.decoder.decode([UUID: RecapBlogDetail].self, from: data) {
            blogDetailsBySourceId = decoded
        }
    }

    private func persistRecents() {
        if let data = try? Self.encoder.encode(recents) {
            try? data.write(to: Self.recentsURL, options: .atomic)
        }
    }

    private func persistTripDrafts() {
        if let data = try? Self.encoder.encode(tripDraftsBySourceId) {
            try? data.write(to: Self.tripDraftsURL, options: .atomic)
        }
    }

    private func persistBlogDetails() {
        if let data = try? Self.encoder.encode(blogDetailsBySourceId) {
            try? data.write(to: Self.blogDetailsURL, options: .atomic)
        }
    }

    /// Call when user completes the Create Blog sequence (before showing RecapSavedView).
    func addCreatedBlog(trip: TripDraft) {
        let startDate = trip.earliestDate
        let endDate = trip.latestDate
        let blog = CreatedRecapBlog(
            sourceTripId: trip.id,
            title: trip.title,
            createdAt: Date(),
            coverImageName: trip.coverImageName,
            coverAssetIdentifier: trip.coverAssetIdentifier,
            selectedPhotoCount: trip.selectedPhotoCount,
            countryName: trip.primaryCountryDisplayName,
            tripDateRangeText: trip.tripDateRangeDisplayText,
            lastEditedAt: nil,
            tripStartDate: startDate,
            tripEndDate: endDate
        )
        tripDraftsBySourceId[trip.id] = trip
        recents.insert(blog, at: 0)
        pendingRecapCreated = true
        // Do not show banner immediately; let the UI trigger it when ready (e.g. after backing out to Trips).
        // showRecapCreatedBanner = true
    }

    /// Dismiss the "Recap Blog has been created!" banner (called after auto-hide or tap).
    func dismissRecapCreatedBanner() {
        showRecapCreatedBanner = false
    }

    /// Whether a draft with this id has already been turned into a created blog.
    func hasCreatedBlog(sourceTripId: UUID) -> Bool {
        recents.contains { $0.sourceTripId == sourceTripId }
    }

    /// Date ranges (start, end) of all created blogs. Used by scan to exclude these dates and reduce memory. Each range is inclusive of the trip's earliest and latest day.
    /// Date ranges (start, end) of all created blogs AND active drafts.
    func occupiedDateRanges() -> [(start: Date, end: Date)] {
        let blogRanges: [(start: Date, end: Date)] = recents.compactMap { blog in
            guard let start = blog.tripStartDate, let end = blog.tripEndDate else { return nil }
            return (start: start, end: end)
        }
        return blogRanges + draftOccupiedRanges
    }

    /// TripDraft snapshot for opening BlogPreviewView. Nil if not found.
    func tripDraft(for sourceTripId: UUID) -> TripDraft? {
        tripDraftsBySourceId[sourceTripId]
    }

    /// Returns a trip draft with photo selection matching the current blog content (for Edit → photo selection flow). Nil if no draft.
    func tripDraftApplyingBlogSelection(blogId: UUID) -> TripDraft? {
        guard var trip = tripDraftsBySourceId[blogId] else { return nil }
        let includedIds: Set<UUID>
        if let detail = blogDetailsBySourceId[blogId] {
            includedIds = Set(detail.days.flatMap { day in day.placeStops.flatMap { stop in stop.photos.map(\.id) } })
        } else {
            includedIds = Set(trip.days.flatMap { day in day.photos.filter(\.isSelected).map(\.id) })
        }
        for dayIdx in trip.days.indices {
            var day = trip.days[dayIdx]
            for photoIdx in day.photos.indices {
                day.photos[photoIdx].isSelected = includedIds.contains(day.photos[photoIdx].id)
            }
            trip.days[dayIdx] = day
        }
        tripDraftsBySourceId[blogId] = trip
        persistTripDrafts()
        return trip
    }

    /// Update an existing blog with a modified trip (e.g. after Edit → photo selection → Update). Rebuilds detail from trip and saves.
    func updateBlog(blogId: UUID, trip: TripDraft) async {
        tripDraftsBySourceId[blogId] = trip
        let detail = await buildBlogDetailAsync(from: trip)
        blogDetailsBySourceId[blogId] = detail
        await MainActor.run {
            guard let idx = recents.firstIndex(where: { $0.sourceTripId == blogId }) else { return }
            let old = recents[idx]
            recents[idx] = CreatedRecapBlog(
                id: old.id,
                sourceTripId: old.sourceTripId,
                title: detail.title,
                createdAt: old.createdAt,
                coverImageName: trip.coverImageName,
                coverAssetIdentifier: trip.coverAssetIdentifier,
                selectedPhotoCount: trip.selectedPhotoCount,
                countryName: detail.countryName ?? old.countryName,
                tripDateRangeText: trip.tripDateRangeDisplayText,
                lastEditedAt: Date(),
                tripStartDate: trip.earliestDate,
                tripEndDate: trip.latestDate,
                isCloud: old.isCloud,
                cloudStatus: old.cloudStatus,
                totalPlaceVisitCount: detail.days.reduce(0) { $0 + $1.placeStops.count },
                tripDurationDays: detail.days.count
            )
            persistRecents()
            persistTripDrafts()
            persistBlogDetails()
            enforceArchiveRules()
        }
    }

    /// Marks a blog as uploaded to the cloud. Toggles isCloud to true.
    func markAsUploaded(sourceTripId: UUID) {
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            recents[idx].isCloud = true
            recents[idx].cloudStatus = .activePublic
            persistRecents()
            enforceArchiveRules()
        }
    }

    /// Enforces cloud storage limits based on entitlements.
    func enforceArchiveRules() {
        let limit = EntitlementManager.shared.activeCloudBlogLimit
        guard let maxCloud = limit else {
            // Pro user: ensure all cloud blogs are activePublic
            var changed = false
            for i in recents.indices where recents[i].isCloud && recents[i].cloudStatus != .activePublic {
                recents[i].cloudStatus = .activePublic
                changed = true
            }
            if changed { persistRecents() }
            return
        }

        // Free tier: sort cloud blogs by date and archive those beyond the limit
        let cloudBlogs = recents.filter(\.isCloud).sorted { $0.createdAt > $1.createdAt }
        var changed = false
        for (index, blog) in cloudBlogs.enumerated() {
            guard let idx = recents.firstIndex(where: { $0.id == blog.id }) else { continue }
            
            let hasLifetime = EntitlementManager.shared.lifetimeAllocatedBlogIDs.contains(blog.sourceTripId)
            let isWithinLimit = index < maxCloud
            
            let targetStatus: BlogCloudStatus = (isWithinLimit || hasLifetime) ? .activePublic : .archived
            if recents[idx].cloudStatus != targetStatus {
                recents[idx].cloudStatus = targetStatus
                changed = true
            }
        }
        if changed { persistRecents() }
    }

    /// Representative coordinate for a blog (first photo with location in its trip draft). Nil if no draft or no location.
    func coordinate(for sourceTripId: UUID) -> CLLocationCoordinate2D? {
        guard let trip = tripDraftsBySourceId[sourceTripId] else { return nil }
        let first = trip.days.flatMap(\.photos).first(where: { $0.location != nil })
        return first?.location?.clCoordinate
    }

    /// Returns saved blog detail if user has edited and saved before. Otherwise nil (caller builds from trip).
    func getBlogDetail(blogId: UUID) -> RecapBlogDetail? {
        blogDetailsBySourceId[blogId]
    }

    /// Persist edited blog detail. Call when user taps Save on RecapBlogPageView. Updates the corresponding recents entry (title, country, cover, lastEditedAt).
    func saveBlogDetail(_ detail: RecapBlogDetail) {
        blogDetailsBySourceId[detail.id] = detail
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == detail.id }) else { return }
        let old = recents[idx]
        let country = (detail.countryName.flatMap { $0.isEmpty || $0 == "Unknown" ? nil : $0 }) ?? old.countryName
        recents[idx] = CreatedRecapBlog(
            id: old.id,
            sourceTripId: old.sourceTripId,
            title: detail.title,
            createdAt: old.createdAt,
            coverImageName: detail.coverTheme,
            coverAssetIdentifier: detail.selectedCoverPhotoIdentifier,
            selectedPhotoCount: old.selectedPhotoCount,
            countryName: country,
            tripDateRangeText: old.tripDateRangeText,
            lastEditedAt: Date(),
            tripStartDate: old.tripStartDate,
            tripEndDate: old.tripEndDate,
            isCloud: old.isCloud,
            cloudStatus: old.cloudStatus,
            totalPlaceVisitCount: detail.days.reduce(0) { $0 + $1.placeStops.count },
            tripDurationDays: detail.days.count
        )
    }

    /// Deletes a created blog. The underlying trip draft remains in TripDraftStore (or is re-discovered by scan) and will reappear in the Trips list because hasCreatedBlog(id) will return false.
    func deleteBlog(sourceTripId: UUID) {
        recents.removeAll { $0.sourceTripId == sourceTripId }
        blogDetailsBySourceId.removeValue(forKey: sourceTripId)
        // If there was a pending banner for this blog (unlikely but possible), clear it.
        if pendingRecapCreated { pendingRecapCreated = false }
    }

    /// Build RecapBlogDetail from a TripDraft, clustered into place stops. Use when no saved detail exists.
    /// All photos in a day are clustered together; isIncluded reflects the user's original selection.
    /// This lets ManagePhotos show the full pool of photos for each stop so the user can add/remove freely.
    func buildBlogDetail(from trip: TripDraft) -> RecapBlogDetail {
        let calendar = Calendar.current
        var days: [RecapBlogDay] = []
        for day in trip.days {
            // Skip days where the user selected nothing.
            guard day.photos.contains(where: \.isSelected) else { continue }

            // Cluster ALL photos (selected + unselected) by time/location.
            let clusterInputs: [ClusterPhotoInput] = day.photos.map { photo in
                ClusterPhotoInput(id: photo.id, timestamp: photo.timestamp, location: photo.location)
            }

            let stopGroups = clusteringService.placeStops(from: clusterInputs) { index in
                "Stop \(index + 1)"
            }

            // Build stops; isIncluded mirrors the user's photo selection.
            // Stops where no photo was selected are hidden from the blog by default.
            let placeStops: [PlaceStop] = stopGroups.compactMap { orderIndex, inputs -> PlaceStop? in
                let photos: [RecapPhoto] = inputs.map { input in
                    let photo = day.photos.first { $0.id == input.id }!
                    return RecapPhoto(
                        id: photo.id,
                        timestamp: photo.timestamp,
                        location: photo.location,
                        imageName: photo.imageName,
                        isIncluded: photo.isSelected,
                        localIdentifier: photo.localIdentifier,
                        caption: nil
                    )
                }
                guard photos.contains(where: \.isIncluded) else { return nil }
                let repLoc = inputs.compactMap(\.location).first
                return PlaceStop(
                    orderIndex: orderIndex,
                    placeTitle: "Stop \(orderIndex + 1)",
                    placeSubtitle: nil,
                    representativeLocation: repLoc,
                    photos: photos,
                    noteText: nil
                )
            }

            guard !placeStops.isEmpty else { continue }
            let dayDate = day.photos.filter(\.isSelected).map(\.timestamp).min().map { calendar.startOfDay(for: $0) } ?? Date()
            days.append(RecapBlogDay(dayIndex: day.dayIndex, date: dayDate, placeStops: placeStops))
        }

        // Default cover: trip's cover asset or first included photo's localIdentifier.
        let firstPhotoId = days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).compactMap(\.localIdentifier).first
        let coverId = trip.coverAssetIdentifier ?? firstPhotoId
        return RecapBlogDetail(id: trip.id, title: trip.title, days: days, coverTheme: trip.coverTheme, selectedCoverPhotoIdentifier: coverId)
    }

    /// Builds blog detail and resolves place names from reverse-geocoded metadata. Sets default Trip Blog title to "Trip To [City Name] in [Season]" (e.g. "Trip To Busan in Winter") or "Trip To New Place" when city is unknown. Title is generated once here; if user edits and saves, getBlogDetail returns the saved title and we do not overwrite.
    func buildBlogDetailAsync(from trip: TripDraft) async -> RecapBlogDetail {
        var detail = buildBlogDetail(from: trip)
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, order: Int)] = []
        var order = 0

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                let stop = detail.days[dayIdx].placeStops[stopIdx]
                if let coord = stop.representativeLocation {
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let place = await GeocodingService.shared.place(for: loc)
                    cityCandidates.append((place.cityName, order))
                    countryCandidates.append((place.countryName, order))
                    order += 1
                    var updated = detail.days[dayIdx]
                    var stopCopy = updated.placeStops[stopIdx]
                    stopCopy.placeTitle = "Near \(place.areaName)"
                    stopCopy.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                    updated.placeStops[stopIdx] = stopCopy
                    detail.days[dayIdx] = updated
                }
            }
        }

        let primaryCity = primaryCityFromCandidates(cityCandidates)
        let primaryCountry = primaryFromCandidates(countryCandidates)
        let season = seasonFromDetail(detail)
        let cityPart: String
        if primaryCity.isEmpty || primaryCity == "Unknown Place" {
            cityPart = "New Place"
        } else {
            cityPart = primaryCity
        }
        if let s = season, !s.isEmpty {
            detail.title = "Trip To \(cityPart) in \(s)"
        } else {
            detail.title = "Trip To \(cityPart)"
        }
        if !primaryCountry.isEmpty && primaryCountry != "Unknown" {
            detail.countryName = primaryCountry
        }

        // Score photos with iOS Vision AI and auto-select best per place stop.
        detail = await applyPhotoQualitySelection(to: detail)

        return detail
    }

    /// Scores every photo in the blog detail using Vision AI, then auto-selects the best ones
    /// per place stop based on count rules:
    ///   - >5 photos  → include top 3
    ///   - 3–5 photos → include top 2
    ///   - 1–2 photos → include all
    private func applyPhotoQualitySelection(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        var updated = detail
        let scorer = PhotoQualityScorer.shared

        for dayIdx in updated.days.indices {
            for stopIdx in updated.days[dayIdx].placeStops.indices {
                let photos = updated.days[dayIdx].placeStops[stopIdx].photos
                let identifiers = photos.compactMap(\.localIdentifier)
                guard !identifiers.isEmpty else { continue }

                // Score all photos in this stop via Vision AI
                let scores = await scorer.scorePhotos(identifiers: identifiers)
                guard !scores.isEmpty else { continue }

                // Attach scores to photos
                for photoIdx in updated.days[dayIdx].placeStops[stopIdx].photos.indices {
                    let photo = updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx]
                    if let id = photo.localIdentifier, let score = scores[id] {
                        updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx].qualityScore = score
                    }
                }

                // Auto-select best photos based on count rules
                let scoredPhotos = updated.days[dayIdx].placeStops[stopIdx].photos
                let topIds = scoredPhotos.autoSelectedIds()
                if !topIds.isEmpty {
                    for photoIdx in updated.days[dayIdx].placeStops[stopIdx].photos.indices {
                        let photo = updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx]
                        updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx].isIncluded = topIds.contains(photo.id)
                    }
                }
            }
        }

        return updated
    }

    private func primaryFromCandidates(_ candidates: [(country: String, order: Int)]) -> String {
        guard !candidates.isEmpty else { return "" }
        var count: [String: (count: Int, firstOrder: Int)] = [:]
        for (country, order) in candidates {
            if let existing = count[country] {
                count[country] = (existing.count + 1, existing.firstOrder)
            } else {
                count[country] = (1, order)
            }
        }
        let sorted = count.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.value.firstOrder < b.value.firstOrder
        }
        return sorted.first?.key ?? ""
    }

    /// Season name from trip photo dates (most frequent month → season). Northern hemisphere: Dec/Jan/Feb Winter, Mar–May Spring, Jun–Aug Summer, Sep–Nov Fall.
    private func seasonFromDetail(_ detail: RecapBlogDetail) -> String? {
        let months = detail.days.flatMap(\.placeStops).flatMap(\.photos).map { Calendar.current.component(.month, from: $0.timestamp) }
        guard !months.isEmpty else { return nil }
        var count: [Int: Int] = [:]
        for m in months { count[m, default: 0] += 1 }
        guard let mostFrequentMonth = count.max(by: { $0.value < $1.value })?.key else { return nil }
        return seasonName(month: mostFrequentMonth)
    }

    private func seasonName(month: Int) -> String {
        switch month {
        case 12, 1, 2: return "Winter"
        case 3, 4, 5: return "Spring"
        case 6, 7, 8: return "Summer"
        case 9, 10, 11: return "Fall"
        default: return "Winter"
        }
    }

    /// Primary city: most frequent city in list; if tie, first chronologically (by order).
    private func primaryCityFromCandidates(_ candidates: [(city: String, order: Int)]) -> String {
        guard !candidates.isEmpty else { return "" }
        var count: [String: (count: Int, firstOrder: Int)] = [:]
        for (city, order) in candidates {
            if let existing = count[city] {
                count[city] = (existing.count + 1, existing.firstOrder)
            } else {
                count[city] = (1, order)
            }
        }
        let sorted = count.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.value.firstOrder < b.value.firstOrder
        }
        return sorted.first?.key ?? ""
    }

    /// For Landing Recents section (newest first).
    var displayRecents: [CreatedRecapBlog] {
        Array(recents)
    }

    /// Group recents by country for Profile. Each summary uses the most recent trip in that country for cover and "Last Trip" date. Sorted by most recent trip date descending.
    var countrySummaries: [CountryRecapSummary] {
        let grouped = Dictionary(grouping: recents) { blog -> String in
            let name = blog.countryName ?? "Unknown"
            return name.isEmpty || name == "Unknown" ? "Unknown" : name
        }
        return grouped.compactMap { countryName, blogs in
            guard let mostRecent = blogs.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return CountryRecapSummary(
                countryName: countryName,
                mostRecentBlog: mostRecent,
                blogs: blogs.sorted { $0.createdAt > $1.createdAt }
            )
        }
        .sorted { $0.mostRecentBlog.createdAt > $1.mostRecentBlog.createdAt }
    }
}

/// One card on the Profile: country name, last trip date, cover from most recent trip in that country.
struct CountryRecapSummary: Identifiable {
    let countryName: String
    let mostRecentBlog: CreatedRecapBlog
    let blogs: [CreatedRecapBlog]
    var id: String { countryName }
}
