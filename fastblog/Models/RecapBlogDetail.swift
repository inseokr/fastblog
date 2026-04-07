//
//  RecapBlogDetail.swift
//  Capper
//

import CoreLocation
import Foundation

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
    /// AI-generated trip opening narrative (5–6 lines). Shown at the top of the blog before Day 1.
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
    /// AI-generated day narrative (4–6 lines). Overrides dayCaption in display when present.
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
    /// AI-generated place narrative (4–6 lines). Overrides overallStory in display when present.
    var placeNarrative: String?
    /// Server-assigned placeIndex in user.placeVisitHistory. Set after successful blog upload.
    var cloudPlaceIndex: Int?
    /// Digitized timestamp of the earliest included photo (EXIF format "yyyy:MM:dd HH:mm:ss").
    /// Used as a cloud deduplication and update key alongside cloudPlaceIndex.
    var visitedTimeDigitized: String?
    /// Raw MKPointOfInterestCategory.rawValue set when user picks from Maps autocomplete (e.g. "MKPOICategoryRestaurant").
    var placeCategory: String?

    /// True when the user has manually typed the overall story (disables AI auto-cascade).
    var overallStoryIsManual: Bool
    /// User sentiment for this place visit. 1 = bad, 2 = neutral (default), 3 = good.
    /// Auto-extracted from caption text by local LLM; can also be set manually.
    var sentiment: Int

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
        sentiment: Int = 2
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
        self.sentiment = sentiment
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, orderIndex, placeTitle, placeSubtitle, placeTitleIsManual, representativeLocation
        case photos, noteText, overallStory, placeNarrative, overallStoryIsManual
        case cloudPlaceIndex, visitedTimeDigitized, placeCategory, sentiment
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

    init(id: UUID = UUID(), timestamp: Date, location: PhotoCoordinate? = nil, imageName: String, isIncluded: Bool = true, localIdentifier: String? = nil, caption: String? = nil, qualityScore: PhotoScore? = nil, cloudURL: String? = nil, captionIsManual: Bool = false, sentiment: Int = 2, digitizedTime: String? = nil) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, location, imageName, isIncluded, localIdentifier
        case caption, qualityScore, cloudURL, captionIsManual, sentiment, digitizedTime
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
