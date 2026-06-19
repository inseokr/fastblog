//
//  RecapBlogDetail.swift
//  Capper
//

import CoreLocation
import Foundation
import Photos

/// Stores a place stop that was removed by the user, preserving all caption data so it can be restored.
struct RemovedPlaceEntry: Identifiable, Equatable, Codable, Sendable {
    /// Matches the original `PlaceStop.id`.
    var id: UUID { stop.id }
    /// The day this stop originally belonged to (used to restore it to the correct day).
    let dayId: UUID
    /// Fallback dayIndex if the parent day was also removed.
    let dayIndex: Int
    /// Original date of the day. Optional to not break old saved data.
    var dayDate: Date? = nil
    /// Full stop including `noteText` and per-photo `caption` fields.
    var stop: PlaceStop
    /// Blog cover asset id before this stop was hidden; used when restoring so the hero matches pre-removal (nil for older saved entries).
    var coverPhotoIdentifierBeforeRemoval: String? = nil
}

/// Created blog content ready to display and edit. Editable draft; Save writes back to store.
/// Trip title is set once on creation (default "Trip To [City]"); user can edit and Save persists it.
/// Cover photo selection is stored in selectedCoverPhotoIdentifier (persisted with draft).
struct RecapBlogDetail: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var days: [RecapBlogDay]
    var coverTheme: String
    var selectedCoverPhotoIdentifier: String?
    /// Country for this trip (from geocoding); used for Profile country grouping.
    var countryName: String?
    /// Server-assigned blog key after a successful upload via createBlogWithPlaces.
    var blogKey: Int?
    /// Places the user has removed from the blog. Preserved so they can be restored later.
    var removedPlaceStops: [RemovedPlaceEntry]
    /// AI-generated trip opening narrative (typically up to 3 short sentences). Shown at the top of the blog before Day 1.
    var tripNarrative: String?

    init(id: UUID = UUID(), title: String, days: [RecapBlogDay], coverTheme: String = "default", selectedCoverPhotoIdentifier: String? = nil, countryName: String? = nil, blogKey: Int? = nil, removedPlaceStops: [RemovedPlaceEntry] = [], tripNarrative: String? = nil) {
        self.id = id
        self.title = title
        self.days = days
        self.coverTheme = coverTheme
        self.selectedCoverPhotoIdentifier = selectedCoverPhotoIdentifier
        self.countryName = countryName
        self.blogKey = blogKey
        self.removedPlaceStops = removedPlaceStops
        self.tripNarrative = tripNarrative
    }

    var allIncludedPhotos: [RecapPhoto] {
        days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
    }

    var hasCloudPhotos: Bool {
        days.flatMap(\.placeStops).flatMap(\.photos).contains { $0.cloudURL != nil }
    }

    /// Drops photo rows that no longer resolve to pixels (deleted library assets, missing in-app captures),
    /// then removes place stops and days that have no photos left.
    func removingUndisplayablePhotos() -> RecapBlogDetail {
        // Batch-fetch all library photo IDs in a single PHAsset call to avoid O(n) serial fetches on the main thread.
        let libraryIds: [String] = days.flatMap(\.placeStops).flatMap(\.photos).compactMap { photo in
            guard photo.cloudURL?.isEmpty ?? true else { return nil }
            guard let lid = photo.localIdentifier, !lid.isEmpty else { return nil }
            guard !lid.hasPrefix(AppCapturePhotoService.prefix) else { return nil }
            return lid
        }
        var existingLibraryIds = Set<String>()
        if !libraryIds.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: libraryIds, options: nil)
            existingLibraryIds.reserveCapacity(fetched.count)
            fetched.enumerateObjects { asset, _, _ in existingLibraryIds.insert(asset.localIdentifier) }
        }

        var result = self
        for dayIdx in result.days.indices {
            for stopIdx in result.days[dayIdx].placeStops.indices {
                result.days[dayIdx].placeStops[stopIdx].photos.removeAll { photo in
                    if let cloud = photo.cloudURL, !cloud.isEmpty { return false }
                    guard let lid = photo.localIdentifier, !lid.isEmpty else { return true }
                    if lid.hasPrefix(AppCapturePhotoService.prefix) {
                        return !AppCapturePhotoService.shared.imageExists(identifier: lid)
                    }
                    return !existingLibraryIds.contains(lid)
                }
            }
            result.days[dayIdx].placeStops.removeAll { $0.photos.isEmpty }
            for stopIdx in result.days[dayIdx].placeStops.indices {
                result.days[dayIdx].placeStops[stopIdx].orderIndex = stopIdx
            }
        }
        result.days.removeAll { $0.placeStops.isEmpty }
        return result
    }

    /// Sets `cloudURL` on every photo whose Photos `localIdentifier` matches (after trim). Used when an asset was uploaded out-of-band (e.g. blog cover) so publish/sync sees the same URI as the server.
    mutating func setCloudURL(_ url: String, forLocalAssetIdentifier localId: String) {
        let tid = localId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else { return }
        for d in days.indices {
            for s in days[d].placeStops.indices {
                for p in days[d].placeStops[s].photos.indices {
                    let lid = days[d].placeStops[s].photos[p].localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard lid == tid else { continue }
                    days[d].placeStops[s].photos[p].cloudURL = url
                }
            }
        }
    }
}

struct RecapBlogDay: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var dayIndex: Int
    var date: Date
    var placeStops: [PlaceStop]
    /// User-written or AI-generated caption for the whole day. Shown right below the day date text.
    var dayCaption: String?
    /// AI-generated day narrative (typically up to 3 short sentences). Overrides dayCaption in display when present.
    var dayNarrative: String?
    /// True after reverse-geocoding and photo scoring have been applied for this day (used for day-by-day rate-limited processing).
    var isPlaceNamesResolved: Bool
    /// Weather fetched from Open-Meteo for this day. Nil until weather has been resolved.
    var weather: DayWeather?
    /// True when the user has manually overridden the weather for this day. Auto-fetch is skipped.
    var weatherIsManual: Bool

    init(id: UUID = UUID(), dayIndex: Int, date: Date, placeStops: [PlaceStop], dayCaption: String? = nil, dayNarrative: String? = nil, isPlaceNamesResolved: Bool = false, weather: DayWeather? = nil, weatherIsManual: Bool = false) {
        self.id = id
        self.dayIndex = dayIndex
        self.date = date
        self.placeStops = placeStops
        self.dayCaption = dayCaption
        self.dayNarrative = dayNarrative
        self.isPlaceNamesResolved = isPlaceNamesResolved
        self.weather = weather
        self.weatherIsManual = weatherIsManual
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        dayIndex = try c.decode(Int.self, forKey: .dayIndex)
        date = try c.decode(Date.self, forKey: .date)
        placeStops = try c.decode([PlaceStop].self, forKey: .placeStops)
        dayCaption = try c.decodeIfPresent(String.self, forKey: .dayCaption)
        dayNarrative = try c.decodeIfPresent(String.self, forKey: .dayNarrative)
        isPlaceNamesResolved = try c.decodeIfPresent(Bool.self, forKey: .isPlaceNamesResolved) ?? false
        weather = try c.decodeIfPresent(DayWeather.self, forKey: .weather)
        weatherIsManual = try c.decodeIfPresent(Bool.self, forKey: .weatherIsManual) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, dayIndex, date, placeStops, dayCaption, dayNarrative, isPlaceNamesResolved, weather, weatherIsManual
    }

    var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    /// e.g. "Saturday Jan-18"
    /// Uses EXIF digitized time from the first place stop when available so the day
    /// reflects the local timezone of the capture location, not the device timezone.
    var shortDateText: String {
        let (d, tz) = displayDateAndTimeZoneForStoryBook()
        let display = DateFormatter()
        display.dateFormat = "EEEE MMM-d"
        if let tz { display.timeZone = tz }
        return display.string(from: d)
    }

    /// e.g. "Saturday, January 18" — weekday, month, and day for the day-story caption editor. Same timezone rules as `shortDateText`.
    var dayStoryDateLine: String {
        let (d, tz) = displayDateAndTimeZoneForStoryBook()
        let display = DateFormatter()
        display.dateFormat = "EEEE, MMMM d"
        if let tz { display.timeZone = tz }
        return display.string(from: d)
    }

    /// Same calendar day as `shortDateText`, used for story-book TOC / cover date range so the header matches each row.
    private func displayDateAndTimeZoneForStoryBook() -> (Date, TimeZone?) {
        if let digitized = placeStops.first?.visitedTimeDigitized {
            let components = digitized.split(separator: " ")
            if components.count == 2 {
                let exifParser = DateFormatter()
                exifParser.dateFormat = "yyyy:MM:dd"
                exifParser.timeZone = TimeZone(secondsFromGMT: 0)
                if let exifDate = exifParser.date(from: String(components[0])) {
                    return (exifDate, TimeZone(secondsFromGMT: 0))
                }
            }
        }
        return (date, nil)
    }

    /// "MMM d" for the story-book date range line (aligned with `shortDateText`).
    func monthDayStringForStoryBookRange() -> String {
        let (d, tz) = displayDateAndTimeZoneForStoryBook()
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        if let tz { fmt.timeZone = tz }
        return fmt.string(from: d)
    }

    /// ", yyyy" suffix for the end of the story-book date range (aligned with `shortDateText`).
    func yearSuffixForStoryBookRange() -> String {
        let (d, tz) = displayDateAndTimeZoneForStoryBook()
        let fmt = DateFormatter()
        fmt.dateFormat = ", yyyy"
        if let tz { fmt.timeZone = tz }
        return fmt.string(from: d)
    }

    /// Calendar date in the user's local calendar that matches `shortDateText` / EXIF capture day.
    /// Use with `CreatedRecapBlogStore.formatDateRange` instead of raw `date` (UTC midnight shifts a day west of UTC).
    var dateAlignedWithShortDateText: Date {
        if let digitized = placeStops.first?.visitedTimeDigitized {
            let parts = digitized.split(separator: " ")
            if !parts.isEmpty {
                let parser = DateFormatter()
                parser.dateFormat = "yyyy:MM:dd"
                parser.timeZone = TimeZone(secondsFromGMT: 0)
                if let exifUTCDate = parser.date(from: String(parts[0])) {
                    var utcCal = Calendar(identifier: .gregorian)
                    utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
                    var comps = utcCal.dateComponents([.year, .month, .day], from: exifUTCDate)
                    comps.hour = 12
                    comps.minute = 0
                    comps.second = 0
                    if let localNoon = Calendar.current.date(from: comps) {
                        return localNoon
                    }
                }
            }
        }
        return date
    }

    /// Trip-level date range for cover/header (aligned with `shortDateText` on each day row).
    static func tripCoverDateRangeText(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.monthDayStringForStoryBookRange()) – \(last.monthDayStringForStoryBookRange())\(last.yearSuffixForStoryBookRange())"
    }

    /// Start/end dates aligned with day row headers — use for recents metadata and occupied scan ranges.
    static func alignedTripStartDate(from days: [RecapBlogDay]) -> Date? {
        days.first?.dateAlignedWithShortDateText
    }

    static func alignedTripEndDate(from days: [RecapBlogDay]) -> Date? {
        days.last?.dateAlignedWithShortDateText
    }

    /// Stable `yyyy-MM-dd` key from EXIF digitized date (preferred) or aligned calendar day — used to merge timezone-split buckets.
    var storyBookCalendarDayKey: String {
        if let digitized = placeStops.compactMap(\.visitedTimeDigitized).first,
           let key = TripCalendarDayKey.from(digitizedTime: digitized) {
            return key
        }
        return TripCalendarDayKey.from(date: dateAlignedWithShortDateText)
    }

    /// All photos in this day that have a location (for map pins).
    var photosWithLocation: [RecapPhoto] {
        placeStops.flatMap(\.photos).filter { $0.location != nil }
    }
}

struct PlaceStop: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var orderIndex: Int
    var placeTitle: String
    var placeSubtitle: String?
    /// When true, prevents reverse-geocoding from overwriting `placeTitle/placeSubtitle`.
    /// Used so nearby-share imports can preserve the sender's edited place names.
    var placeTitleIsManual: Bool
    var representativeLocation: PhotoCoordinate?
    var photos: [RecapPhoto]
    var noteText: String?
    /// Quick summary of this place derived from photo captions (e.g. LLM summary). Shown above/below place and time.
    var overallStory: String?
    /// AI-generated place narrative (typically up to 3 short sentences). Overrides overallStory in display when present.
    var placeNarrative: String?
    /// Server-assigned placeIndex in user.placeVisitHistory. Set after successful blog upload.
    var cloudPlaceIndex: Int?
    /// Digitized timestamp of the earliest included photo (EXIF format "yyyy:MM:dd HH:mm:ss").
    /// Used as a cloud deduplication and update key alongside cloudPlaceIndex.
    var visitedTimeDigitized: String?
    /// Raw MKPointOfInterestCategory.rawValue set when user picks from Maps autocomplete (e.g. "MKPOICategoryRestaurant").
    var placeCategory: String?
    /// IANA timezone identifier (e.g. "America/Los_Angeles") for the place's location.
    /// Stored during blog creation so video export never needs to re-geocode for timestamps.
    var timeZoneIdentifier: String?

    /// True when the user has manually typed the overall story (disables AI auto-cascade).
    var overallStoryIsManual: Bool
    /// User sentiment for this place visit. 1 = bad, 2 = neutral (default), 3 = good.
    /// Auto-extracted from caption text by local LLM; can also be set manually.
    var sentiment: Int
    /// User-chosen transport mode to the next stop. nil = auto-detect (distance-based).
    var transportModeToNextStop: TravelMode?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        placeTitle: String,
        placeSubtitle: String? = nil,
        placeTitleIsManual: Bool = false,
        representativeLocation: PhotoCoordinate? = nil,
        photos: [RecapPhoto],
        noteText: String? = nil,
        overallStory: String? = nil,
        placeNarrative: String? = nil,
        overallStoryIsManual: Bool = false,
        cloudPlaceIndex: Int? = nil,
        visitedTimeDigitized: String? = nil,
        placeCategory: String? = nil,
        timeZoneIdentifier: String? = nil,
        sentiment: Int = 2,
        transportModeToNextStop: TravelMode? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.placeTitleIsManual = placeTitleIsManual
        self.representativeLocation = representativeLocation
        self.photos = photos
        self.noteText = noteText
        self.overallStory = overallStory
        self.placeNarrative = placeNarrative
        self.overallStoryIsManual = overallStoryIsManual
        self.cloudPlaceIndex = cloudPlaceIndex
        self.visitedTimeDigitized = visitedTimeDigitized
        self.placeCategory = placeCategory
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sentiment = sentiment
        self.transportModeToNextStop = transportModeToNextStop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        orderIndex = try c.decode(Int.self, forKey: .orderIndex)
        placeTitle = try c.decode(String.self, forKey: .placeTitle)
        placeSubtitle = try c.decodeIfPresent(String.self, forKey: .placeSubtitle)
        placeTitleIsManual = try c.decodeIfPresent(Bool.self, forKey: .placeTitleIsManual) ?? false
        representativeLocation = try c.decodeIfPresent(PhotoCoordinate.self, forKey: .representativeLocation)
        photos = try c.decode([RecapPhoto].self, forKey: .photos)
        noteText = try c.decodeIfPresent(String.self, forKey: .noteText)
        overallStory = try c.decodeIfPresent(String.self, forKey: .overallStory)
        placeNarrative = try c.decodeIfPresent(String.self, forKey: .placeNarrative)
        overallStoryIsManual = try c.decodeIfPresent(Bool.self, forKey: .overallStoryIsManual) ?? false
        cloudPlaceIndex = try c.decodeIfPresent(Int.self, forKey: .cloudPlaceIndex)
        visitedTimeDigitized = try c.decodeIfPresent(String.self, forKey: .visitedTimeDigitized)
        placeCategory = try c.decodeIfPresent(String.self, forKey: .placeCategory)
        sentiment = try c.decodeIfPresent(Int.self, forKey: .sentiment) ?? 2
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        transportModeToNextStop = try c.decodeIfPresent(TravelMode.self, forKey: .transportModeToNextStop)
    }

    private enum CodingKeys: String, CodingKey {
        case id, orderIndex, placeTitle, placeSubtitle, placeTitleIsManual, representativeLocation
        case photos, noteText, overallStory, placeNarrative, overallStoryIsManual
        case cloudPlaceIndex, visitedTimeDigitized, placeCategory, timeZoneIdentifier, sentiment
        case transportModeToNextStop
    }

    /// Display-ready place title. Cleans up raw system-generated highway names like
    /// "near 119892 US-395" → "Near US-395". Falls through unchanged for normal place names.
    var cleanedPlaceTitle: String { placeTitle.cleanedAsPlaceTitle }

    /// Derives the place-level sentiment from photo sentiments (photos with captions only)
    /// combined with the stored place-level sentiment.
    /// Returns nil when there are no captioned photos and no place caption has been analyzed yet.
    /// The caller should use `sentiment` (stored, possibly manually overridden) for display,
    /// and call this to recompute after any caption changes.
    func computeDerivedSentiment(placeCaption: String?) -> Int {
        // Collect photo sentiments — only photos that have a non-empty caption
        let photoValues: [Int] = includedPhotos
            .filter { ($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .map(\.sentiment)

        // Include the place-level sentiment only if there is actual caption text
        let hasCaptionText = !(placeCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let placeValue: Int? = hasCaptionText ? sentiment : nil

        let allValues: [Int] = photoValues + (placeValue.map { [$0] } ?? [])
        guard !allValues.isEmpty else { return 2 }
        let avg = Double(allValues.reduce(0, +)) / Double(allValues.count)
        return min(3, max(1, Int(avg.rounded())))
    }

    var coverPhoto: RecapPhoto? {
        photos.first
    }

    var includedPhotos: [RecapPhoto] {
        photos.filter(\.isIncluded)
    }
}

extension PlaceStop {
    /// Infers offset-only capture `TimeZone` from the stop visit digitized string vs each photo capture instant,
    /// using the same median-offset rounding as ``PlacePhotoModalView`` (keeps thumbnails and fullscreen in sync).
    static func inferredCaptureTimeZone(visitedDigitized: String?, photoTimestamps: [Date]) -> TimeZone? {
        guard let trimmed = visitedDigitized?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let localAsUTC = parser.date(from: trimmed) else { return nil }
        let offsets: [Int] = photoTimestamps.map { Int(localAsUTC.timeIntervalSince($0)) }
        guard !offsets.isEmpty else { return nil }
        let sorted = offsets.sorted()
        let medianOffset: Int
        if sorted.count.isMultiple(of: 2), sorted.count >= 2 {
            medianOffset = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            medianOffset = sorted[sorted.count / 2]
        }
        let roundedOffset = (medianOffset / 900) * 900
        if roundedOffset == 0 { return nil }
        return TimeZone(secondsFromGMT: roundedOffset)
    }

    /// Time zone for showing each photo’s capture instant on blog thumbnails when `RecapPhoto.digitizedTime` is nil.
    /// Order: inferred from `visitedTimeDigitized`, then stored IANA identifier, then device.
    var recapThumbnailTimeZone: TimeZone {
        Self.inferredCaptureTimeZone(visitedDigitized: visitedTimeDigitized, photoTimestamps: photos.map(\.timestamp))
            ?? timeZoneIdentifier.flatMap { TimeZone(identifier: $0) }
            ?? .current
    }
}

extension RecapBlogDetail {
    /// Highlight moments across the whole blog, sorted by score desc then by photo count desc.
    var highlightMomentsRanked: [PlaceStop] {
        days.flatMap(\.placeStops)
            .map { stop in (stop: stop, score: stop.highlightMomentScore) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.stop.includedPhotos.count != b.stop.includedPhotos.count {
                    return a.stop.includedPhotos.count > b.stop.includedPhotos.count
                }
                return a.stop.placeTitle.localizedStandardCompare(b.stop.placeTitle) == .orderedAscending
            }
            .map(\.stop)
    }
}

/// Location stored as lat/lon for Equatable. Convert to CLLocationCoordinate2D for MapKit.
struct PhotoCoordinate: Equatable, Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct RecapPhoto: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var timestamp: Date
    var location: PhotoCoordinate?
    var imageName: String
    var isIncluded: Bool
    var localIdentifier: String?
    /// Caption per photo; persisted with blog detail when user taps Save.
    var caption: String?
    /// AI quality score from PhotoQualityScorer. Nil until scored after blog creation.
    var qualityScore: PhotoScore?
    /// Cloud URL returned by the file server after upload. Nil means not yet uploaded.
    var cloudURL: String?
    /// True when the user has manually typed this photo's caption (AI wand is hidden and auto-cascade skips this photo).
    var captionIsManual: Bool
    /// Sentiment extracted from this photo's caption by the local LLM. 1=bad, 2=neutral (default), 3=good.
    /// Only meaningful when `caption` is non-nil and non-empty.
    var sentiment: Int
    /// EXIF-style digitized time string ("yyyy:MM:dd HH:mm:ss") computed at publish/upload time using the
    /// photo's capture-location timezone. Stored so that subsequent updatePhoto calls send the exact same
    /// value the backend recorded — avoids divergence from re-computing with a different TZ fallback.
    var digitizedTime: String?
    /// True when the underlying PHAsset is marked as a Favorite in the user's photo library.
    /// Populated during photo quality scoring; always false for in-app camera captures.
    var isFavorite: Bool

    init(id: UUID = UUID(), timestamp: Date, location: PhotoCoordinate? = nil, imageName: String, isIncluded: Bool = true, localIdentifier: String? = nil, caption: String? = nil, qualityScore: PhotoScore? = nil, cloudURL: String? = nil, captionIsManual: Bool = false, sentiment: Int = 2, digitizedTime: String? = nil, isFavorite: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.location = location
        self.imageName = imageName
        self.isIncluded = isIncluded
        self.localIdentifier = localIdentifier
        self.caption = caption
        self.qualityScore = qualityScore
        self.cloudURL = cloudURL
        self.captionIsManual = captionIsManual
        self.sentiment = sentiment
        self.digitizedTime = digitizedTime
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        location = try c.decodeIfPresent(PhotoCoordinate.self, forKey: .location)
        imageName = try c.decode(String.self, forKey: .imageName)
        isIncluded = try c.decodeIfPresent(Bool.self, forKey: .isIncluded) ?? true
        localIdentifier = try c.decodeIfPresent(String.self, forKey: .localIdentifier)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        qualityScore = try c.decodeIfPresent(PhotoScore.self, forKey: .qualityScore)
        cloudURL = try c.decodeIfPresent(String.self, forKey: .cloudURL)
        captionIsManual = try c.decodeIfPresent(Bool.self, forKey: .captionIsManual) ?? false
        sentiment = try c.decodeIfPresent(Int.self, forKey: .sentiment) ?? 2
        digitizedTime = try c.decodeIfPresent(String.self, forKey: .digitizedTime)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, location, imageName, isIncluded, localIdentifier
        case caption, qualityScore, cloudURL, captionIsManual, sentiment, digitizedTime, isFavorite
    }

    /// True when the recap row should show a real thumbnail: cloud URL, on-disk app capture, or an existing Photos asset.
    var hasDisplayableLocalBacking: Bool {
        if let cloud = cloudURL, !cloud.isEmpty { return true }
        guard let lid = localIdentifier, !lid.isEmpty else { return false }
        if lid.hasPrefix(AppCapturePhotoService.prefix) {
            return AppCapturePhotoService.shared.imageExists(identifier: lid)
        }
        return PHAsset.fetchAssets(withLocalIdentifiers: [lid], options: nil).firstObject != nil
    }
}

// MARK: - String + place title cleaning

extension String {
    /// Cleans up raw system-generated highway names like "near 119892 US-395" → "Near US-395".
    /// Falls through unchanged for normal place names.
    var cleanedAsPlaceTitle: String {
        let pattern = #"^[Nn]ear\s+\d+\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)),
           let routeRange = Range(match.range(at: 1), in: self) {
            return "Near \(self[routeRange])"
        }
        return self
    }
}

// MARK: - Highlight moments (optional ranking)

extension PlaceStop {
    /// Duration of this stop inferred from included photo timestamps (seconds).
    /// Returns 0 when there are fewer than 2 included photos.
    var inferredVisitDurationSeconds: TimeInterval {
        let ts = includedPhotos.map(\.timestamp).sorted()
        guard let first = ts.first, let last = ts.last, last > first else { return 0 }
        return last.timeIntervalSince(first)
    }

    /// Highlight score (0–100) for ranking moments. Always computed — no eligibility gate.
    ///
    struct HighlightScoreComponents {
        let photo: Double       // weighted points, max 15
        let duration: Double    // weighted points, max 10
        let caption: Double     // weighted points, max 30
        let sentiment: Double   // weighted points, max 45
        var total: Double { photo + duration + caption + sentiment }
    }

    /// Scoring formula (normalized then weighted):
    /// - photoScore (15%): grows from 0 at 3 photos to 1 at 10+ photos
    /// - durationScore (10%): grows from 0 at 10 mins to 1 at 60+ mins
    /// - captionScore (30%): 1 when a caption exists (place note or any photo caption)
    /// - sentimentScore (45%): 0 at negative (1), 0.5 at neutral (2), 1 at positive (3)
    var highlightScoreComponents: HighlightScoreComponents {
        let photoCount = includedPhotos.count
        let minutes = inferredVisitDurationSeconds / 60.0
        let derivedSentiment = sentiment  // use stored value — same as what the Loved It/Neutral/Terrible pill shows

        let photoScore    = min(1, max(0, (Double(photoCount) - 3.0) / 7.0))
        let durationScore = min(1, max(0, (minutes - 10.0) / 50.0))
        let captionScore  = hasAnyCaptionText ? 1.0 : 0.0
        let sentimentScore = min(1, max(0, (Double(derivedSentiment) - 1.0) / 2.0))

        return HighlightScoreComponents(
            photo:    photoScore    * 15,
            duration: durationScore * 10,
            caption:  captionScore  * 30,
            sentiment: sentimentScore * 45
        )
    }

    var highlightMomentScore: Double {
        let c = highlightScoreComponents
        return min(100, max(0, c.total))
    }

    private var hasAnyCaptionText: Bool {
        let placeCaptions = [noteText, overallStory, placeNarrative]
        if placeCaptions.contains(where: { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        return includedPhotos.contains { photo in
            !( photo.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - Calendar day keys (capture / digitized time)

/// Groups photos and blog days by the calendar date in `visitedTimeDigitized` (EXIF), not device timezone.
enum TripCalendarDayKey {
    /// `yyyy-MM-dd` from EXIF digitized string (`yyyy:MM:dd HH:mm:ss`).
    static func from(digitizedTime: String) -> String? {
        let parts = digitizedTime.split(separator: " ")
        guard let datePart = parts.first else { return nil }
        let normalized = String(datePart).replacingOccurrences(of: ":", with: "-")
        let segments = normalized.split(separator: "-")
        guard segments.count == 3,
              let y = Int(segments[0]), let m = Int(segments[1]), let d = Int(segments[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func from(date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parses trip scan `dateText` (medium style) into `yyyy-MM-dd`.
    static func from(dateText: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        guard let parsed = formatter.date(from: dateText) else { return nil }
        return from(date: parsed)
    }

    /// Local noon on that calendar day (stable `RecapBlogDay.date` for sorting and range formatting).
    static func canonicalDate(from key: String) -> Date? {
        let segments = key.split(separator: "-")
        guard segments.count == 3,
              let y = Int(segments[0]), let m = Int(segments[1]), let d = Int(segments[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)
    }
}

extension RecapBlogDetail {
    /// Merges days that share the same `storyBookCalendarDayKey` (e.g. after a flight, device TZ vs EXIF disagreed).
    func consolidatingDuplicateCalendarDays() -> RecapBlogDetail {
        guard days.count > 1 else { return self }
        var byKey: [String: RecapBlogDay] = [:]
        var keyOrder: [String] = []

        for day in days {
            let key = day.storyBookCalendarDayKey
            if var existing = byKey[key] {
                existing.placeStops.append(contentsOf: day.placeStops)
                sortPlaceStopsChronologically(&existing.placeStops)
                if existing.dayCaption == nil { existing.dayCaption = day.dayCaption }
                if existing.dayNarrative == nil { existing.dayNarrative = day.dayNarrative }
                if existing.weather == nil { existing.weather = day.weather }
                existing.isPlaceNamesResolved = existing.isPlaceNamesResolved && day.isPlaceNamesResolved
                byKey[key] = existing
            } else {
                var copy = day
                sortPlaceStopsChronologically(&copy.placeStops)
                byKey[key] = copy
                keyOrder.append(key)
            }
        }

        keyOrder.sort { lhs, rhs in
            earliestTimestamp(in: byKey[lhs]!) < earliestTimestamp(in: byKey[rhs]!)
        }

        var merged = self
        merged.days = keyOrder.enumerated().map { index, key in
            var day = byKey[key]!
            day.dayIndex = index + 1
            day.date = TripCalendarDayKey.canonicalDate(from: key) ?? day.date
            return day
        }
        return merged
    }

    private func earliestTimestamp(in day: RecapBlogDay) -> Date {
        day.placeStops.flatMap(\.photos).map(\.timestamp).min() ?? day.date
    }

    private func sortPlaceStopsChronologically(_ stops: inout [PlaceStop]) {
        stops.sort {
            ($0.photos.map(\.timestamp).min() ?? .distantFuture) < ($1.photos.map(\.timestamp).min() ?? .distantFuture)
        }
        for i in stops.indices {
            stops[i].orderIndex = i
            if stops[i].placeTitle.range(of: "^Stop \\d+$", options: .regularExpression) != nil {
                stops[i].placeTitle = "Stop \(i + 1)"
            }
        }
    }
}

// MARK: - New moments → day mapping

extension RecapBlogDetail {
    /// Maps library photos to 0-based day indices, including continuation shots after the last blog day.
    func dayIndicesForNewMomentPhotos(_ photos: [MockPhoto]) -> Set<Int> {
        guard !photos.isEmpty, !days.isEmpty else { return [] }
        return Set(photos.compactMap { dayIndexForNewMomentPhoto(at: $0.timestamp) })
    }

    func preferredDayIndexForNewMoments(
        from photos: [MockPhoto],
        fallbackDayIndex: Int? = nil
    ) -> Int? {
        if let latest = dayIndicesForNewMomentPhotos(photos).max() {
            return latest
        }
        if let fallback = fallbackDayIndex, days.indices.contains(fallback) {
            return fallback
        }
        return days.isEmpty ? nil : days.count - 1
    }

    private func dayIndexForNewMomentPhoto(at timestamp: Date) -> Int? {
        guard !days.isEmpty else { return nil }
        let photoKey = TripCalendarDayKey.from(date: timestamp)

        if let exact = days.firstIndex(where: { $0.storyBookCalendarDayKey == photoKey }) {
            return exact
        }

        let lastIdx = days.count - 1
        let lastKey = days[lastIdx].storyBookCalendarDayKey

        // Continuation trip: photos after the blog's last calendar day land on the latest day (or a new day on inject).
        if photoKey > lastKey {
            return lastIdx
        }

        if let firstKey = days.first?.storyBookCalendarDayKey, photoKey < firstKey {
            return 0
        }

        var bestIdx = 0
        for (index, day) in days.enumerated() {
            if day.storyBookCalendarDayKey <= photoKey {
                bestIdx = index
            }
        }
        return bestIdx
    }
}
