//
//  CreatedRecapBlogStore.swift
//  Capper
//

import Combine
import CoreLocation
import Foundation
import SwiftUI

/// A recap blog that was created from a draft trip. Stored so we can hide the draft from Trips and show it in Landing Recents.
struct CreatedRecapBlog: Identifiable, Equatable, Hashable {
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

    init(id: UUID = UUID(), sourceTripId: UUID, title: String, createdAt: Date, coverImageName: String, coverAssetIdentifier: String? = nil, selectedPhotoCount: Int, countryName: String? = nil, tripDateRangeText: String? = nil, lastEditedAt: Date? = nil, tripStartDate: Date? = nil, tripEndDate: Date? = nil) {
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
    }
}

@MainActor
final class CreatedRecapBlogStore: ObservableObject {
    static let shared = CreatedRecapBlogStore()

    @Published private(set) var recents: [CreatedRecapBlog] = []
    /// When true, landing shows "Recap Blog has been created!" banner; clear after 5–7 sec.
    @Published var showRecapCreatedBanner = false
    private var tripDraftsBySourceId: [UUID: TripDraft] = [:]
    /// Persisted editable blog details; Save in RecapBlogPageView writes here.
    private var blogDetailsBySourceId: [UUID: RecapBlogDetail] = [:]
    private let clusteringService = PlaceStopClusteringService()

    private init() {}

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
        showRecapCreatedBanner = true
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
    func occupiedDateRanges() -> [(start: Date, end: Date)] {
        recents.compactMap { blog in
            guard let start = blog.tripStartDate, let end = blog.tripEndDate else { return nil }
            return (start, end)
        }
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
            tripEndDate: trip.latestDate
            )
        }
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
            tripEndDate: old.tripEndDate
        )
    }

    /// Build RecapBlogDetail from a TripDraft (selected photos only, clustered into place stops). Use when no saved detail exists.
    func buildBlogDetail(from trip: TripDraft) -> RecapBlogDetail {
        let calendar = Calendar.current
        var days: [RecapBlogDay] = []
        for day in trip.days {
            let selectedPhotos = day.photos.filter(\.isSelected)
            guard !selectedPhotos.isEmpty else { continue }

            let clusterInputs: [ClusterPhotoInput] = selectedPhotos.map { photo in
                ClusterPhotoInput(id: photo.id, timestamp: photo.timestamp, location: photo.location)
            }

            let stopGroups = clusteringService.placeStops(from: clusterInputs) { index in
                "Stop \(index + 1)"
            }

            let placeStops: [PlaceStop] = stopGroups.map { orderIndex, inputs in
                let photos: [RecapPhoto] = inputs.map { input in
                    let photo = selectedPhotos.first { $0.id == input.id }!
                    return RecapPhoto(
                        id: photo.id,
                        timestamp: photo.timestamp,
                        location: photo.location,
                        imageName: photo.imageName,
                        isIncluded: true,
                        localIdentifier: photo.localIdentifier,
                        caption: nil
                    )
                }
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

            let dayDate = selectedPhotos.map(\.timestamp).min().map { calendar.startOfDay(for: $0) } ?? Date()
            days.append(RecapBlogDay(dayIndex: day.dayIndex, date: dayDate, placeStops: placeStops))
        }

        // Default cover: trip's cover asset or first photo's localIdentifier (used in blog 1x1 preview).
        let firstPhotoId = days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier).first
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
        return detail
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
