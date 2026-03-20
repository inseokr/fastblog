// fastblog/Services/StoryBookBuilder.swift
import UIKit
import Photos

enum StoryBookBuilder {

    static func build(from detail: RecapBlogDetail) async throws -> StoryBookContent {
        let cover = buildCover(detail)
        let overview = buildOverview(detail)
        let days = try await buildDays(detail)
        return StoryBookContent(cover: cover, overview: overview, days: days)
    }

    // MARK: - Cover
    private static func buildCover(_ detail: RecapBlogDetail) -> CoverContent {
        let dateRange = dateRangeString(from: detail.days)
        var coverImage: UIImage? = nil
        if let identifier = detail.selectedCoverPhotoIdentifier {
            coverImage = loadAndDownsample(localIdentifier: identifier)
        }
        return CoverContent(title: detail.title, subtitle: dateRange, coverPhoto: coverImage)
    }

    // MARK: - Overview (TOC)
    private static func buildOverview(_ detail: RecapBlogDetail) -> BlogOverviewContent {
        let dateRange = dateRangeString(from: detail.days)
        let entries: [TOCEntry] = detail.days.enumerated().map { idx, day in
            TOCEntry(
                dayNumber: idx + 1,
                date: day.shortDateText,
                firstPlaceName: day.placeStops.first?.placeTitle ?? "Day \(idx + 1)"
            )
        }
        return BlogOverviewContent(dateRange: dateRange, dayCount: detail.days.count, entries: entries)
    }

    // MARK: - Days
    private static func buildDays(_ detail: RecapBlogDetail) async throws -> [StoryDay] {
        var storyDays: [StoryDay] = []
        for (idx, day) in detail.days.enumerated() {
            let snapshot = await withTimeout(seconds: 10) {
                await MapSnapshotHelper.generateSnapshot(
                    for: day.placeStops,
                    size: CGSize(width: 390, height: 280)
                )
            }

            let places = buildPlaces(from: day.placeStops)

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
    private static func buildPlaces(from stops: [PlaceStop]) -> [PlaceContent] {
        stops.map { stop in
            let caption = stop.overallStory ?? stop.noteText
            let captionIsLong = (caption?.count ?? 0) > 80
            let photos = stop.photos
                .filter { $0.isIncluded }
                .compactMap { photo -> PhotoContent? in
                    guard let identifier = photo.localIdentifier else { return nil }
                    guard let image = loadAndDownsample(localIdentifier: identifier) else { return nil }
                    let photoCaption = photo.caption
                    return PhotoContent(
                        image: image,
                        caption: photoCaption,
                        captionIsLong: (photoCaption?.count ?? 0) > 80
                    )
                }
            return PlaceContent(
                title: stop.placeTitle,
                timestamp: formattedTimestamp(stop.visitedTimeDigitized),
                caption: caption,
                captionIsLong: captionIsLong,
                photos: photos
            )
        }
    }

    // MARK: - Helpers
    private static func loadAndDownsample(localIdentifier: String) -> UIImage? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        let targetSize = UIScreen.main.bounds.size
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .highQualityFormat
        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: reqOptions
        ) { img, _ in image = img }
        return image
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
