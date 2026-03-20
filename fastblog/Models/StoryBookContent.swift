// fastblog/Models/StoryBookContent.swift
import UIKit

struct StoryBookContent {
    let cover: CoverContent
    let overview: BlogOverviewContent
    let days: [StoryDay]
}

struct CoverContent {
    let title: String
    let subtitle: String        // e.g. "March 12–19, 2025"
    let coverPhoto: UIImage?    // nil → gradient placeholder (EC-5)
}

struct BlogOverviewContent {
    let tripTitle: String
    let dateRange: String
    let dayCount: Int
    let entries: [TOCEntry]
}

struct TOCEntry {
    let dayNumber: Int
    let date: String
    let placeNames: [String]
    /// AI-generated curated subtitle for the day (simple level: reuse `dayCaption`)
    let daySubtitle: String?
    /// Book page (1-based) where this day section starts in story mode.
    /// Computed during `StoryPageLayout.buildPages`.
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
    /// e.g. city/state derived from `PlaceStop.placeSubtitle`.
    let subtitle: String?
    /// 1-based position within the day; used for start/middle/end marker styling.
    let markerNumber: Int
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
    let image: UIImage          // pre-downsampled to screen resolution
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
    /// PHAsset local id when loaded from the library; used to reload at hero quality after layout.
    let assetLocalIdentifier: String?
}
