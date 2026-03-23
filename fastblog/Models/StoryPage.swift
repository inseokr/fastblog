// fastblog/Models/StoryPage.swift
import CoreGraphics

enum StoryPage {
    case cover(CoverContent)
    case tableOfContents(entries: [TOCEntry], overview: BlogOverviewContent, pageIndex: Int, totalPages: Int)
    case dayMap(StoryDay)
    case dayContent(DayContentPage)
}

struct DayContentPage {
    let day: StoryDay
    let isFirstPage: Bool
    let slots: [ContentSlot]
    let isLastPageOfDay: Bool
    let isLastPageOfTrip: Bool
    // Non-nil only when isLastPageOfDay == true && isLastPageOfTrip == false
    let nextDayName: String?
}

enum ContentSlot {
    case dayCaption(String)
    case placeBlock(
        PlaceContent,
        photoSlice: ClosedRange<Int>,
        photoImageHeight: CGFloat,
        photoGridLayout: PhotoGridLayout,
        storyUsesTwoColumns: Bool,
        showPlaceStory: Bool
    )
    case photoOverflowContinuation(
        placeName: String,
        PlaceContent,
        photoSlice: ClosedRange<Int>,
        photoImageHeight: CGFloat,
        photoGridLayout: PhotoGridLayout,
        showOverflowHeader: Bool
    )
    /// Remaining lines of a photo caption that did not fit under the image on the previous page(s).
    case photoCaptionContinuation(text: String)
    /// Remaining place story text that did not fit above photos on the previous page(s).
    case placeStoryContinuation(text: String)
}

enum PhotoGridLayout {
    case single
    case twoColumn
    case stackedSingles
}
