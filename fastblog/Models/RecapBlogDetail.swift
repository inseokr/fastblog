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

    init(id: UUID = UUID(), title: String, days: [RecapBlogDay], coverTheme: String = "default", selectedCoverPhotoIdentifier: String? = nil, countryName: String? = nil, blogKey: Int? = nil, removedPlaceStops: [RemovedPlaceEntry] = []) {
        self.id = id
        self.title = title
        self.days = days
        self.coverTheme = coverTheme
        self.selectedCoverPhotoIdentifier = selectedCoverPhotoIdentifier
        self.countryName = countryName
        self.blogKey = blogKey
        self.removedPlaceStops = removedPlaceStops
    }

    var allIncludedPhotos: [RecapPhoto] {
        days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
    }

    var hasCloudPhotos: Bool {
        days.flatMap(\.placeStops).flatMap(\.photos).contains { $0.cloudURL != nil }
    }
}

struct RecapBlogDay: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var dayIndex: Int
    var date: Date
    var placeStops: [PlaceStop]

    init(id: UUID = UUID(), dayIndex: Int, date: Date, placeStops: [PlaceStop]) {
        self.id = id
        self.dayIndex = dayIndex
        self.date = date
        self.placeStops = placeStops
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
        // Prefer EXIF local time — already correct for the timezone where photos were taken.
        if let digitized = placeStops.first?.visitedTimeDigitized {
            let components = digitized.split(separator: " ")
            if components.count == 2 {
                let exifParser = DateFormatter()
                exifParser.dateFormat = "yyyy:MM:dd"
                exifParser.timeZone = TimeZone(secondsFromGMT: 0)
                if let exifDate = exifParser.date(from: String(components[0])) {
                    let display = DateFormatter()
                    display.dateFormat = "EEEE MMM-d"
                    display.timeZone = TimeZone(secondsFromGMT: 0)
                    return display.string(from: exifDate)
                }
            }
        }
        // Fallback: stored date in device-local timezone.
        let f = DateFormatter()
        f.dateFormat = "EEEE MMM-d"
        return f.string(from: date)
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
    var representativeLocation: PhotoCoordinate?
    var photos: [RecapPhoto]
    var noteText: String?
    /// Quick summary of this place derived from photo captions (e.g. LLM summary). Shown above/below place and time.
    var overallStory: String?
    /// Server-assigned placeIndex in user.placeVisitHistory. Set after successful blog upload.
    var cloudPlaceIndex: Int?
    /// Digitized timestamp of the first included photo (EXIF format "yyyy:MM:dd HH:mm:ss").
    /// Used as a cloud deduplication and update key alongside cloudPlaceIndex.
    var visitedTimeDigitized: String?
    /// Raw MKPointOfInterestCategory.rawValue set when user picks from Maps autocomplete (e.g. "MKPOICategoryRestaurant").
    var placeCategory: String?

    /// True when the user has manually typed the overall story (disables AI auto-cascade).
    var overallStoryIsManual: Bool

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        placeTitle: String,
        placeSubtitle: String? = nil,
        representativeLocation: PhotoCoordinate? = nil,
        photos: [RecapPhoto],
        noteText: String? = nil,
        overallStory: String? = nil,
        overallStoryIsManual: Bool = false,
        cloudPlaceIndex: Int? = nil,
        visitedTimeDigitized: String? = nil,
        placeCategory: String? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.representativeLocation = representativeLocation
        self.photos = photos
        self.noteText = noteText
        self.overallStory = overallStory
        self.overallStoryIsManual = overallStoryIsManual
        self.cloudPlaceIndex = cloudPlaceIndex
        self.visitedTimeDigitized = visitedTimeDigitized
        self.placeCategory = placeCategory
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

    init(id: UUID = UUID(), timestamp: Date, location: PhotoCoordinate? = nil, imageName: String, isIncluded: Bool = true, localIdentifier: String? = nil, caption: String? = nil, qualityScore: PhotoScore? = nil, cloudURL: String? = nil, captionIsManual: Bool = false) {
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
    }
}
