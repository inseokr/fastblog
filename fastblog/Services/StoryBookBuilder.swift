// fastblog/Services/StoryBookBuilder.swift
import UIKit
import Photos

enum StoryBookBuilder {

    static func build(from detail: RecapBlogDetail) async throws -> StoryBookContent {
        let displayScale = await MainActor.run { UIScreen.main.scale }
        let cover = buildCover(detail, displayScale: displayScale)
        let overview = buildOverview(detail)
        let days = try await buildDays(detail, displayScale: displayScale)
        return StoryBookContent(cover: cover, overview: overview, days: days)
    }

    // MARK: - Cover
    private static func buildCover(_ detail: RecapBlogDetail, displayScale: CGFloat) -> CoverContent {
        let dateRange = dateRangeString(from: detail.days)
        var coverImage: UIImage? = nil
        if let identifier = detail.selectedCoverPhotoIdentifier {
            coverImage = loadAndDownsample(
                localIdentifier: identifier,
                displayScale: displayScale,
                kind: .storyCover
            )
        }
        return CoverContent(title: detail.title, subtitle: dateRange, coverPhoto: coverImage)
    }

    // MARK: - Overview (TOC)
    private static func buildOverview(_ detail: RecapBlogDetail) -> BlogOverviewContent {
        let dateRange = dateRangeString(from: detail.days)
        let entries: [TOCEntry] = detail.days.enumerated().map { idx, day in
            let placeNames = day.placeStops
                .sorted(by: { $0.orderIndex < $1.orderIndex })
                .map(\.placeTitle)
            return TOCEntry(
                dayNumber: idx + 1,
                date: day.shortDateText,
                placeNames: placeNames,
                // Simple level: reuse the already AI-generated day caption (trimmed for CONTENTS line length).
                daySubtitle: {
                    let s = day.dayCaption?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let s, !s.isEmpty else { return nil }
                    let maxLen = StoryPageLayout.tocDayStoryCaptionMaxCharacters
                    if s.count <= maxLen { return s }
                    return String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }(),
                dayStartPageNumber: 0
            )
        }
        return BlogOverviewContent(
            tripTitle: detail.title,
            dateRange: dateRange,
            dayCount: detail.days.count,
            entries: entries
        )
    }

    // MARK: - Days
    private static func buildDays(_ detail: RecapBlogDetail, displayScale: CGFloat) async throws -> [StoryDay] {
        var storyDays: [StoryDay] = []
        for (idx, day) in detail.days.enumerated() {
            let screenSize = await MainActor.run { UIScreen.main.bounds.size }
            // MKMapSnapshotter (and some of MapKit internally) can behave badly with a 0-sized snapshot.
            // Your logs show CAMetalLayer drawable sizes going to 0, so clamp to a sane default.
            let snapshotSize = (screenSize.width > 0 && screenSize.height > 0)
                ? screenSize
                : CGSize(width: 600, height: 300)
            let snapshot = await withTimeout(seconds: 10) {
                // Snapshot region is padded to include numbered pins and right-side place name pills.
                await MapSnapshotHelper.generateSnapshot(
                    for: day.placeStops,
                    size: snapshotSize,
                    regionPadding: 0.01
                )
            }

            let places = buildPlaces(from: day.placeStops, displayScale: displayScale)

            storyDays.append(StoryDay(
                dayNumber: idx + 1,
                date: day.date,
                dayCaption: day.dayCaption,
                mapSnapshot: snapshot,
                places: places
            ))
        }
        return storyDays
    }

    // MARK: - Places
    private static func buildPlaces(from stops: [PlaceStop], displayScale: CGFloat) -> [PlaceContent] {
        let orderedStops = stops.sorted(by: { $0.orderIndex < $1.orderIndex })
        return orderedStops.enumerated().map { idx, stop in
            let caption = stop.overallStory ?? stop.noteText
            let captionIsLong = (caption?.count ?? 0) > 80
            let photos = stop.photos
                .filter { $0.isIncluded }
                .compactMap { photo -> PhotoContent? in
                    guard let identifier = photo.localIdentifier else { return nil }
                    guard let image = loadAndDownsample(
                        localIdentifier: identifier,
                        displayScale: displayScale,
                        kind: .storyInline
                    ) else { return nil }
                    let photoCaption = photo.caption
                    return PhotoContent(
                        image: image,
                        caption: photoCaption,
                        captionIsLong: (photoCaption?.count ?? 0) > 80,
                        assetLocalIdentifier: identifier
                    )
                }
            let markerNumber = idx + 1
            let markerType: PlaceMarkerType = {
                if idx == 0 { return .start }
                if idx == orderedStops.count - 1 { return .end }
                return .middle
            }()

            return PlaceContent(
                title: stop.placeTitle,
                subtitle: stop.placeSubtitle,
                markerNumber: markerNumber,
                markerType: markerType,
                timestamp: formattedTimestamp(stop.visitedTimeDigitized),
                caption: caption,
                captionIsLong: captionIsLong,
                photos: photos
            )
        }
    }

    // MARK: - Helpers
    private enum PhotoLoadKind {
        /// Full-bleed cover: must match display pixel density or it looks soft when SwiftUI scales to fill the screen.
        case storyCover
        /// Exactly one photo on the whole day page (after packing); layout often stretches it to fill leftover height — highest budget.
        case storyHeroSoloPage
        /// Full-width day photos (single or stacked singles) when they dominate the page — same budget as cover.
        case storyHeroFullBleed
        /// The lone full-width photo on a 2+1 or 1+2 page (paired with a two-column row). Slightly lower tier than full-bleed.
        case storyHeroMixedSingle
        /// Inline story photos: smaller on screen; keep a tighter pixel budget for memory.
        case storyInline
    }

    private static func heroCacheKeySuffix(for kind: PhotoLoadKind) -> String {
        switch kind {
        case .storyCover: return "c"
        case .storyHeroSoloPage: return "o"
        case .storyHeroFullBleed: return "f"
        case .storyHeroMixedSingle: return "m"
        case .storyInline: return "i"
        }
    }

    private static func loadAndDownsample(localIdentifier: String, displayScale: CGFloat, kind: PhotoLoadKind) -> UIImage? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        // PHImageManager targetSize is in pixels; StoryRenderMetrics are in points — multiply by scale or we load ~1× bitmaps.
        let rawSize = StoryRenderMetrics.clampedScreenSize
        let maxPixelLongEdge: CGFloat
        switch kind {
        case .storyCover, .storyHeroFullBleed:
            maxPixelLongEdge = 4096
        case .storyHeroSoloPage:
            maxPixelLongEdge = 4608
        case .storyHeroMixedSingle:
            maxPixelLongEdge = 3072
        case .storyInline:
            maxPixelLongEdge = 1024
        }
        var pixelW = rawSize.width * displayScale
        var pixelH = rawSize.height * displayScale
        let longEdge = max(pixelW, pixelH)
        if longEdge > maxPixelLongEdge, longEdge > 0 {
            let r = maxPixelLongEdge / longEdge
            pixelW *= r
            pixelH *= r
        }
        let targetSize = CGSize(width: ceil(pixelW), height: ceil(pixelH))
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.resizeMode = .exact
        let contentMode: PHImageContentMode = {
            switch kind {
            case .storyCover, .storyHeroSoloPage, .storyHeroFullBleed, .storyHeroMixedSingle:
                return .aspectFill
            case .storyInline:
                return .aspectFit
            }
        }()
        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: reqOptions
        ) { img, _ in image = img }
        return image
    }

    // MARK: - Hero photo quality (full-width slots)

    /// After `StoryPageLayout.buildPages`, reloads full-width slots: half-width `.twoColumn` stays on the inline budget;
    /// mixed 2+1 / 1+2 pages use a mid tier for the lone full-width photo; solo-photo pages use the top tier; other full-width heroes match cover.
    static func applyHeroPhotoQuality(to pages: inout [StoryPage], displayScale: CGFloat) {
        let allHeroIds = collectHeroAssetIdentifiers(from: pages)
        guard !allHeroIds.isEmpty else { return }
        let mixedSingleIds = collectMixedLayoutSingleHeroIdentifiers(from: pages)
        let soloPageIds = collectSoloPageSingleHeroIdentifiers(from: pages)
        var cache: [String: UIImage] = [:]
        for i in pages.indices {
            guard case .dayContent(let dc) = pages[i] else { continue }
            let updatedDay = upgradeDayForHeroPhotos(
                dc.day,
                soloPhotoIds: soloPageIds,
                mixedHeroIds: mixedSingleIds,
                allHeroIds: allHeroIds,
                displayScale: displayScale,
                cache: &cache
            )
            pages[i] = .dayContent(
                DayContentPage(
                    day: updatedDay,
                    isFirstPage: dc.isFirstPage,
                    slots: dc.slots,
                    isLastPageOfDay: dc.isLastPageOfDay,
                    isLastPageOfTrip: dc.isLastPageOfTrip,
                    nextDayName: dc.nextDayName
                )
            )
        }
    }

    private static func collectHeroAssetIdentifiers(from pages: [StoryPage]) -> Set<String> {
        var ids = Set<String>()
        for page in pages {
            guard case .dayContent(let dc) = page else { continue }
            for slot in dc.slots {
                switch slot {
                case .placeBlock(let place, let slice, _, let layout):
                    insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
                case .photoOverflowContinuation(_, let place, let slice, _, let layout, _):
                    insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
                case .dayCaption:
                    break
                }
            }
        }
        return ids
    }

    private static func insertHeroAssetIds(
        from place: PlaceContent,
        slice: ClosedRange<Int>,
        layout: PhotoGridLayout,
        into ids: inout Set<String>
    ) {
        guard layout != .twoColumn else { return }
        let lo = slice.lowerBound
        let hi = min(slice.upperBound, place.photos.count - 1)
        guard lo <= hi else { return }
        for i in lo...hi {
            if let id = place.photos[i].assetLocalIdentifier {
                ids.insert(id)
            }
        }
    }

    private static func photoCountInSlot(_ slot: ContentSlot) -> Int {
        switch slot {
        case .placeBlock(let place, let slice, _, _):
            guard !place.photos.isEmpty else { return 0 }
            let lo = slice.lowerBound
            let hi = min(slice.upperBound, place.photos.count - 1)
            guard lo <= hi else { return 0 }
            return hi - lo + 1
        case .photoOverflowContinuation(_, let place, let slice, _, _, _):
            guard !place.photos.isEmpty else { return 0 }
            let lo = slice.lowerBound
            let hi = min(slice.upperBound, place.photos.count - 1)
            guard lo <= hi else { return 0 }
            return hi - lo + 1
        case .dayCaption:
            return 0
        }
    }

    /// The lone `.single` photo on a page with exactly three photos in two slots (one two-column + one single), e.g. 2+1 or 1+2.
    private static func collectMixedLayoutSingleHeroIdentifiers(from pages: [StoryPage]) -> Set<String> {
        var ids = Set<String>()
        for page in pages {
            guard case .dayContent(let dc) = page else { continue }
            let slots = dc.slots
            let photoSlotIndices = slots.indices.filter { photoCountInSlot(slots[$0]) > 0 }
            let total = photoSlotIndices.reduce(0) { $0 + photoCountInSlot(slots[$1]) }
            guard total == 3, photoSlotIndices.count == 2 else { continue }
            let i0 = photoSlotIndices[0]
            let i1 = photoSlotIndices[1]
            let c0 = photoCountInSlot(slots[i0])
            let c1 = photoCountInSlot(slots[i1])
            guard (c0 == 2 && c1 == 1) || (c0 == 1 && c1 == 2) else { continue }
            let singleIndex = c0 == 1 ? i0 : i1
            let singleSlot = slots[singleIndex]
            switch singleSlot {
            case .placeBlock(let place, let slice, _, let layout):
                guard layout == .single else { continue }
                insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
            case .photoOverflowContinuation(_, let place, let slice, _, let layout, _):
                guard layout == .single else { continue }
                insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
            case .dayCaption:
                break
            }
        }
        return ids
    }

    /// One photo total on the page (e.g. only slot with a photo, or day caption + one place with one photo) — gets the top decode budget.
    private static func collectSoloPageSingleHeroIdentifiers(from pages: [StoryPage]) -> Set<String> {
        var ids = Set<String>()
        for page in pages {
            guard case .dayContent(let dc) = page else { continue }
            let slots = dc.slots
            let photoSlotIndices = slots.indices.filter { photoCountInSlot(slots[$0]) > 0 }
            let total = photoSlotIndices.reduce(0) { $0 + photoCountInSlot(slots[$1]) }
            guard total == 1, let onlyIdx = photoSlotIndices.first else { continue }
            let slot = slots[onlyIdx]
            switch slot {
            case .placeBlock(let place, let slice, _, let layout):
                guard layout == .single else { continue }
                insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
            case .photoOverflowContinuation(_, let place, let slice, _, let layout, _):
                guard layout == .single else { continue }
                insertHeroAssetIds(from: place, slice: slice, layout: layout, into: &ids)
            case .dayCaption:
                break
            }
        }
        return ids
    }

    private static func upgradeDayForHeroPhotos(
        _ day: StoryDay,
        soloPhotoIds: Set<String>,
        mixedHeroIds: Set<String>,
        allHeroIds: Set<String>,
        displayScale: CGFloat,
        cache: inout [String: UIImage]
    ) -> StoryDay {
        let places = day.places.map {
            upgradePlaceForHeroPhotos(
                $0,
                soloPhotoIds: soloPhotoIds,
                mixedHeroIds: mixedHeroIds,
                allHeroIds: allHeroIds,
                displayScale: displayScale,
                cache: &cache
            )
        }
        return StoryDay(
            dayNumber: day.dayNumber,
            date: day.date,
            dayCaption: day.dayCaption,
            mapSnapshot: day.mapSnapshot,
            places: places
        )
    }

    private static func upgradePlaceForHeroPhotos(
        _ place: PlaceContent,
        soloPhotoIds: Set<String>,
        mixedHeroIds: Set<String>,
        allHeroIds: Set<String>,
        displayScale: CGFloat,
        cache: inout [String: UIImage]
    ) -> PlaceContent {
        let photos = place.photos.map { photo -> PhotoContent in
            guard let id = photo.assetLocalIdentifier, allHeroIds.contains(id) else { return photo }
            let kind: PhotoLoadKind = {
                if soloPhotoIds.contains(id) { return .storyHeroSoloPage }
                if mixedHeroIds.contains(id) { return .storyHeroMixedSingle }
                return .storyHeroFullBleed
            }()
            let cacheKey = "\(id)-\(heroCacheKeySuffix(for: kind))"
            if let cached = cache[cacheKey] {
                return PhotoContent(
                    image: cached,
                    caption: photo.caption,
                    captionIsLong: photo.captionIsLong,
                    assetLocalIdentifier: id
                )
            }
            guard let img = loadAndDownsample(localIdentifier: id, displayScale: displayScale, kind: kind) else { return photo }
            cache[cacheKey] = img
            return PhotoContent(
                image: img,
                caption: photo.caption,
                captionIsLong: photo.captionIsLong,
                assetLocalIdentifier: id
            )
        }
        return PlaceContent(
            title: place.title,
            subtitle: place.subtitle,
            markerNumber: place.markerNumber,
            markerType: place.markerType,
            timestamp: place.timestamp,
            caption: place.caption,
            captionIsLong: place.captionIsLong,
            photos: photos
        )
    }

    private static func formattedTimestamp(_ digitized: String?) -> String? {
        guard let digitized else { return nil }
        let parts = digitized.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let timePart = String(parts[1])
        let components = timePart.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        let ampm = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    private static func dateRangeString(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = ", yyyy"
        return "\(fmt.string(from: first.date)) – \(fmt.string(from: last.date))\(yearFmt.string(from: last.date))"
    }

    // MARK: - Timeout helper
    private static func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
