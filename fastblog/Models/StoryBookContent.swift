// fastblog/Models/StoryBookContent.swift
import UIKit

/// Google search URL for a place — shared by story-mode UI (`Link`) and story-mode PDF link annotations.
enum StoryPlaceGoogleSearch {
    static func url(placeName: String, placeSubtitle: String?) -> URL? {
        let trimmedPlaceName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !trimmedPlaceName.isEmpty { parts.append(trimmedPlaceName) }
        if let trimmedSubtitle, !trimmedSubtitle.isEmpty { parts.append(trimmedSubtitle) }

        let query = parts.joined(separator: ", ")
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

struct StoryBookContent {
    let cover: CoverContent
    let overview: BlogOverviewContent
    let days: [StoryDay]
}

struct CoverContent {
    let title: String
    let subtitle: String        // e.g. "March 12–19, 2025"
    let coverPhoto: UIImage?    // nil → gradient placeholder (EC-5)
    /// AI trip-opening narrative; shown under the title block when non-empty (matches recap editor).
    let tripNarrative: String?
}

struct BlogOverviewContent {
    let tripTitle: String
    let dateRange: String
    let dayCount: Int
    /// Trip cover for the TOC hero strip (same asset as the book cover when available).
    let coverPhoto: UIImage?
    let entries: [TOCEntry]
}

struct TOCEntry {
    let dayNumber: Int
    let date: String
    let firstPlaceName: String
    let placeNames: [String]
    let daySubtitle: String?
    /// Included photos in this day (for “N moments” on the TOC).
    let momentCount: Int
    var dayStartPageNumber: Int
}

struct StoryDay {
    let dayNumber: Int
    let date: Date
    let dayCaption: String?     // nil → skip caption block (EC-3)
    let mapSnapshot: UIImage?   // nil → skip map page (EC-7)
    let places: [PlaceContent]
}

struct PlaceContent {
    let title: String
    let subtitle: String?       // e.g. city/state derived from PlaceStop.placeSubtitle
    let markerNumber: Int       // 1-based position within the day
    let markerType: PlaceMarkerType
    let timestamp: String?
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
    let photos: [PhotoContent]
}

enum PlaceMarkerType {
    case start
    case middle
    case end
}

struct PhotoContent {
    let image: UIImage          // pre-downsampled to screen resolution (or first-frame thumbnail for video)
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
    /// Non-nil when this item is a video clip. Drives play-overlay rendering and inline playback.
    let videoLocalIdentifier: String?

    var isVideo: Bool { videoLocalIdentifier != nil }

    init(image: UIImage, caption: String?, captionIsLong: Bool, videoLocalIdentifier: String? = nil) {
        self.image = image
        self.caption = caption
        self.captionIsLong = captionIsLong
        self.videoLocalIdentifier = videoLocalIdentifier
    }
}
