// fastblog/Models/StoryPage.swift

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
    case placeBlock(PlaceContent, photoSlice: ClosedRange<Int>)
    case photoOverflowContinuation(placeName: String, PlaceContent, photoSlice: ClosedRange<Int>)
}
