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
    let dateRange: String
    let dayCount: Int
    let entries: [TOCEntry]
}

struct TOCEntry {
    let dayNumber: Int
    let date: String
    let firstPlaceName: String
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
    let timestamp: String?
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
    let photos: [PhotoContent]
}

struct PhotoContent {
    let image: UIImage          // pre-downsampled to screen resolution
    let caption: String?
    let captionIsLong: Bool     // caption.count > 80
}
