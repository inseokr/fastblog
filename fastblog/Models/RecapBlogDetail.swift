//
//  RecapBlogDetail.swift
//  Capper
//

import CoreLocation
import Foundation

/// Created blog content ready to display and edit. Editable draft; Save writes back to store.
/// Trip title is set once on creation (default "Trip To [City]"); user can edit and Save persists it.
/// Cover photo selection is stored in selectedCoverPhotoIdentifier (persisted with draft).
struct RecapBlogDetail: Identifiable, Equatable {
    let id: UUID
    var title: String
    var days: [RecapBlogDay]
    var coverTheme: String
    var selectedCoverPhotoIdentifier: String?
    /// Country for this trip (from geocoding); used for Profile country grouping.
    var countryName: String?

    init(id: UUID = UUID(), title: String, days: [RecapBlogDay], coverTheme: String = "default", selectedCoverPhotoIdentifier: String? = nil, countryName: String? = nil) {
        self.id = id
        self.title = title
        self.days = days
        self.coverTheme = coverTheme
        self.selectedCoverPhotoIdentifier = selectedCoverPhotoIdentifier
        self.countryName = countryName
    }
}

struct RecapBlogDay: Identifiable, Equatable {
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

    /// e.g. "Saturday 3-18"
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE M-d"
        return f.string(from: date)
    }

    /// All photos in this day that have a location (for map pins).
    var photosWithLocation: [RecapPhoto] {
        placeStops.flatMap(\.photos).filter { $0.location != nil }
    }
}

struct PlaceStop: Identifiable, Equatable {
    let id: UUID
    var orderIndex: Int
    var placeTitle: String
    var placeSubtitle: String?
    var representativeLocation: PhotoCoordinate?
    var photos: [RecapPhoto]
    var noteText: String?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        placeTitle: String,
        placeSubtitle: String? = nil,
        representativeLocation: PhotoCoordinate? = nil,
        photos: [RecapPhoto],
        noteText: String? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.representativeLocation = representativeLocation
        self.photos = photos
        self.noteText = noteText
    }

    var coverPhoto: RecapPhoto? {
        photos.first
    }

    var includedPhotos: [RecapPhoto] {
        photos.filter(\.isIncluded)
    }
}

/// Location stored as lat/lon for Equatable. Convert to CLLocationCoordinate2D for MapKit.
struct PhotoCoordinate: Equatable, Hashable {
    let latitude: Double
    let longitude: Double
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct RecapPhoto: Identifiable, Equatable {
    let id: UUID
    var timestamp: Date
    var location: PhotoCoordinate?
    var imageName: String
    var isIncluded: Bool
    var localIdentifier: String?
    /// Caption per photo; persisted with blog detail when user taps Save.
    var caption: String?

    init(id: UUID = UUID(), timestamp: Date, location: PhotoCoordinate? = nil, imageName: String, isIncluded: Bool = true, localIdentifier: String? = nil, caption: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.location = location
        self.imageName = imageName
        self.isIncluded = isIncluded
        self.localIdentifier = localIdentifier
        self.caption = caption
    }
}
