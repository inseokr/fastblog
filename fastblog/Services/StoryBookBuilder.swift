// fastblog/Services/StoryBookBuilder.swift
import UIKit
import Photos

enum StoryBookBuilder {

    /// Matches PDF export / recap blog hero: high-res cover decode (see `PDFExportService.preloadAssets`).
    private static let coverImagePixelSize = CGSize(width: 1200, height: 1200)

    static func build(from detail: RecapBlogDetail) async throws -> StoryBookContent {
        let coverPhoto = await loadCoverPhoto(identifier: detail.selectedCoverPhotoIdentifier)
        let dateRange = dateRangeString(from: detail.days)
        let cover = CoverContent(title: detail.title, subtitle: dateRange, coverPhoto: coverPhoto)
        let overview = buildOverview(detail: detail, dateRange: dateRange, coverPhoto: coverPhoto)
        let days = try await buildDays(detail)
        return StoryBookContent(cover: cover, overview: overview, days: days)
    }

    // MARK: - Overview (TOC)
    private static func buildOverview(detail: RecapBlogDetail, dateRange: String, coverPhoto: UIImage?) -> BlogOverviewContent {
        let entries: [TOCEntry] = detail.days.enumerated().map { (idx, day) in
            let names = day.placeStops.map { $0.placeTitle }
            let moments = day.placeStops.flatMap(\.photos).filter(\.isIncluded).count
            return TOCEntry(
                dayNumber: idx + 1,
                date: day.shortDateText,
                firstPlaceName: names.first ?? "Day \(idx + 1)",
                placeNames: names,
                daySubtitle: day.dayCaption,
                momentCount: moments,
                dayStartPageNumber: 0   // computed later in StoryPageLayout.buildPages
            )
        }
        return BlogOverviewContent(
            tripTitle: detail.title,
            dateRange: dateRange,
            dayCount: detail.days.count,
            coverPhoto: coverPhoto,
            entries: entries
        )
    }

    // MARK: - Days
    private static func buildDays(_ detail: RecapBlogDetail) async throws -> [StoryDay] {
        var storyDays: [StoryDay] = []
        for (idx, day) in detail.days.enumerated() {
            let screenSize = await MainActor.run { UIScreen.main.bounds.size }
            let snapshot = await withTimeout(seconds: 10) {
                await MapSnapshotHelper.generateSnapshot(
                    for: day.placeStops,
                    size: screenSize,
                    regionPadding: 0.05,
                    showPlaceNames: false
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
        stops.enumerated().map { idx, stop in
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
            let markerType: PlaceMarkerType = {
                if idx == 0 { return .start }
                if idx == stops.count - 1 { return .end }
                return .middle
            }()
            return PlaceContent(
                title: stop.placeTitle,
                subtitle: stop.placeSubtitle,
                markerNumber: idx + 1,
                markerType: markerType,
                timestamp: formattedTimestamp(stop.visitedTimeDigitized),
                caption: caption,
                captionIsLong: captionIsLong,
                photos: photos
            )
        }
    }

    // MARK: - Helpers
    private static func loadCoverPhoto(identifier: String?) async -> UIImage? {
        guard let identifier else { return nil }
        if identifier.hasPrefix(AppCapturePhotoService.prefix) {
            return AppCapturePhotoService.shared.loadImage(identifier: identifier)
        }
        return await Task.detached {
            loadCoverPhotoFromPhotoLibrarySync(localIdentifier: identifier)
        }.value
    }

    /// Synchronous Photos load on a background thread (matches `PDFExportService` cover fetch).
    private static func loadCoverPhotoFromPhotoLibrarySync(localIdentifier: String) -> UIImage? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = true
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.resizeMode = .exact
        reqOptions.isNetworkAccessAllowed = true
        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: coverImagePixelSize,
            contentMode: .aspectFit,
            options: reqOptions
        ) { img, _ in image = img }
        return image
    }

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
        // Use the same date source as TOC rows (`shortDateText` / EXIF), not `day.date` alone, so the range matches listed days.
        return "\(first.monthDayStringForStoryBookRange()) – \(last.monthDayStringForStoryBookRange())\(last.yearSuffixForStoryBookRange())"
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
