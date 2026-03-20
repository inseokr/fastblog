// fastblog/Services/StoryPageLayout.swift

enum StoryPageLayout {

    // MARK: - Slot heights (points)
    static let pageContentHeight: CGFloat = 680
    static let footerHeight: CGFloat = 40
    static let dayHeaderHeight: CGFloat = 44
    static let dayCaptionShort: CGFloat = 56
    static let dayCaptionLong: CGFloat = 80
    static let placeTitleHeight: CGFloat = 32
    static let placeCaptionShort: CGFloat = 40
    static let placeCaptionLong: CGFloat = 64
    static let photoRowHeight: CGFloat = 200        // 1 or 2 photos
    static let overflowSlotHeight: CGFloat = 224    // label(24) + photos(200)
    static let tocHeaderHeight: CGFloat = 72
    static let tocRowHeight: CGFloat = 36

    // MARK: - Entry point
    static func buildPages(from content: StoryBookContent) -> [StoryPage] {
        var pages: [StoryPage] = []

        // 1. Cover
        pages.append(.cover(content.cover))

        // 2. TOC pages
        pages.append(contentsOf: buildTOCPages(overview: content.overview))

        // 3. Days
        let dayCount = content.days.count
        for (dayIdx, day) in content.days.enumerated() {
            let isLastDay = dayIdx == dayCount - 1

            // Map page (skip if no snapshot)
            if day.mapSnapshot != nil {
                pages.append(.dayMap(day))
            }

            // Content pages
            let nextDayName: String? = isLastDay ? nil : {
                let nextDay = content.days[dayIdx + 1]
                return nextDay.places.first?.title ?? "Day \(nextDay.dayNumber)"
            }()

            let contentPages = buildDayContentPages(
                day: day,
                isLastDay: isLastDay,
                nextDayName: nextDayName
            )
            pages.append(contentsOf: contentPages.map { .dayContent($0) })
        }

        // Mark last page of trip
        if case .dayContent(let last) = pages.last {
            let marked = DayContentPage(
                day: last.day,
                isFirstPage: last.isFirstPage,
                slots: last.slots,
                isLastPageOfDay: last.isLastPageOfDay,
                isLastPageOfTrip: true,
                nextDayName: nil
            )
            pages[pages.count - 1] = .dayContent(marked)
        }

        return pages
    }

    // MARK: - TOC
    private static func buildTOCPages(overview: BlogOverviewContent) -> [StoryPage] {
        // First pass: count pages
        let firstPageCapacity = Int((pageContentHeight - tocHeaderHeight) / tocRowHeight)
        let remaining = max(0, overview.entries.count - firstPageCapacity)
        let continuationCapacity = Int(pageContentHeight / tocRowHeight)
        let extraPages = remaining > 0 ? 1 + (remaining - 1) / continuationCapacity : 0
        let totalPages = 1 + extraPages

        // Second pass: emit pages
        var result: [StoryPage] = []
        var entryIndex = 0
        var pageIndex = 1

        while entryIndex < overview.entries.count {
            let capacity = pageIndex == 1 ? firstPageCapacity : continuationCapacity
            let slice = Array(overview.entries[entryIndex..<min(entryIndex + capacity, overview.entries.count)])
            result.append(.tableOfContents(
                entries: slice,
                overview: overview,
                pageIndex: pageIndex,
                totalPages: totalPages
            ))
            entryIndex += capacity
            pageIndex += 1
        }

        // Edge case: zero days
        if result.isEmpty {
            result.append(.tableOfContents(entries: [], overview: overview, pageIndex: 1, totalPages: 1))
        }

        return result
    }

    // MARK: - Day content pages
    private static func buildDayContentPages(
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?
    ) -> [DayContentPage] {

        var allSlots: [ContentSlot] = []

        // Day caption (only emitted once — DayContentPageView shows it only on isFirstPage)
        if let caption = day.dayCaption {
            allSlots.append(.dayCaption(caption))
        }

        // Place slots
        for place in day.places {
            allSlots.append(contentsOf: slotsForPlace(place))
        }

        // Pack slots into pages
        return packSlots(allSlots, day: day, isLastDay: isLastDay, nextDayName: nextDayName)
    }

    private static func slotsForPlace(_ place: PlaceContent) -> [ContentSlot] {
        let photoCount = place.photos.count
        if photoCount == 0 {
            return [.placeBlock(place, photoSlice: 0...0)]
        } else if photoCount <= 2 {
            return [.placeBlock(place, photoSlice: 0...(photoCount - 1))]
        } else {
            var result: [ContentSlot] = [.placeBlock(place, photoSlice: 0...1)]
            var idx = 2
            while idx < photoCount {
                let end = min(idx + 1, photoCount - 1)
                result.append(.photoOverflowContinuation(placeName: place.title, place, photoSlice: idx...end))
                idx += 2
            }
            return result
        }
    }

    private static func slotHeight(_ slot: ContentSlot) -> CGFloat {
        switch slot {
        case .dayCaption(let text):
            return text.count > 80 ? dayCaptionLong : dayCaptionShort
        case .placeBlock(let place, _):
            var h: CGFloat = placeTitleHeight
            if let caption = place.caption {
                h += caption.count > 80 ? placeCaptionLong : placeCaptionShort
            }
            if !place.photos.isEmpty { h += photoRowHeight }
            return h
        case .photoOverflowContinuation:
            return overflowSlotHeight
        }
    }

    /// Returns borrow slots for place 2 if it fits on the current page after place 1.
    private static func borrowSlots(for place: PlaceContent, remainingSpace: CGFloat) -> [ContentSlot] {
        let photoCount = place.photos.count
        let captionIsLong = (place.caption?.count ?? 0) > 80

        let fullBorrowThreshold: CGFloat = 272
        let nameOnlyThreshold: CGFloat = 32

        if remainingSpace >= fullBorrowThreshold {
            if photoCount == 0 {
                return [.placeBlock(place, photoSlice: 0...0)]
            } else if photoCount <= 2 {
                return [.placeBlock(place, photoSlice: 0...(photoCount - 1))]
            } else {
                return [.placeBlock(place, photoSlice: 0...1)]
            }
        } else if remainingSpace >= nameOnlyThreshold && !captionIsLong {
            let nameOnly = PlaceContent(
                title: place.title,
                timestamp: place.timestamp,
                caption: nil,
                captionIsLong: false,
                photos: []
            )
            return [.placeBlock(nameOnly, photoSlice: 0...0)]
        }
        return []
    }

    private static func packSlots(
        _ slots: [ContentSlot],
        day: StoryDay,
        isLastDay: Bool,
        nextDayName: String?
    ) -> [DayContentPage] {

        var pages: [DayContentPage] = []
        var currentSlots: [ContentSlot] = []
        var usedHeight: CGFloat = dayHeaderHeight
        var isFirstPage = true
        var slotIdx = 0
        var didBorrowOnFirstPage = false

        while slotIdx < slots.count {
            let slot = slots[slotIdx]
            let h = slotHeight(slot)

            if usedHeight + h > pageContentHeight && !currentSlots.isEmpty {
                pages.append(DayContentPage(
                    day: day,
                    isFirstPage: isFirstPage,
                    slots: currentSlots,
                    isLastPageOfDay: false,
                    isLastPageOfTrip: false,
                    nextDayName: nil
                ))
                currentSlots = []
                usedHeight = 0
                isFirstPage = false
            } else if usedHeight + h > pageContentHeight {
                #if DEBUG
                assertionFailure("StoryPageLayout: slot overflows fresh page")
                #endif
            }

            currentSlots.append(slot)
            usedHeight += h
            slotIdx += 1

            // Peek-ahead borrow: after place 1's last slot on the first page, try to borrow place 2
            if isFirstPage && !didBorrowOnFirstPage,
               case .placeBlock(let place1, _) = slot,
               slotIdx < slots.count,
               case .placeBlock(let place2, _) = slots[slotIdx] {

                let p1PhotoCount = place1.photos.count
                guard p1PhotoCount <= 2 else { continue }

                let remaining = pageContentHeight - usedHeight
                let borrowed = borrowSlots(for: place2, remainingSpace: remaining)

                if !borrowed.isEmpty {
                    let borrowedHeight = borrowed.reduce(0) { $0 + slotHeight($1) }
                    let minNextPageHeight: CGFloat = (placeTitleHeight + photoRowHeight) * 2
                    let remainingAfterBorrow = pageContentHeight - borrowedHeight
                    if remainingAfterBorrow >= minNextPageHeight {
                        currentSlots.append(contentsOf: borrowed)
                        usedHeight += borrowedHeight
                        didBorrowOnFirstPage = true
                        slotIdx += 1
                    }
                }
            }
        }

        // Final page
        pages.append(DayContentPage(
            day: day,
            isFirstPage: isFirstPage,
            slots: currentSlots,
            isLastPageOfDay: true,
            isLastPageOfTrip: false,
            nextDayName: isLastDay ? nil : nextDayName
        ))

        return pages
    }
}
