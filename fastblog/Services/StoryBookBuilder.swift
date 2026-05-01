// fastblog/Services/StoryBookBuilder.swift
import UIKit

enum StoryBookBuilder {

    /// Matches PDF export / recap blog hero: high-res cover decode (see `PDFExportService.preloadAssets`).
    private static let coverImagePixelSize = CGSize(width: 1200, height: 1200)

    static func build(from detail: RecapBlogDetail) async -> StoryBookContent {
        let coverPhoto = await loadCoverPhoto(identifier: detail.selectedCoverPhotoIdentifier)
        let dateRange = dateRangeString(from: detail.days)
        let tripTrimmed = detail.tripNarrative?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tripNarrative: String? = (tripTrimmed?.isEmpty == false) ? tripTrimmed : nil
        let cover = CoverContent(
            title: detail.title,
            subtitle: dateRange,
            coverPhoto: coverPhoto,
            tripNarrative: tripNarrative
        )
        let overview = buildOverview(detail: detail, dateRange: dateRange, coverPhoto: coverPhoto)
        let days = await buildDays(detail)
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
                daySubtitle: effectiveDayCaption(for: day),
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
    private static func buildDays(_ detail: RecapBlogDetail) async -> [StoryDay] {
        var storyDays: [StoryDay] = []
        for (idx, day) in detail.days.enumerated() {
            let screenSize = await MainActor.run { UIScreen.main.bounds.size }
            let snapshot = await withTimeout(seconds: 10) {
                await MapSnapshotHelper.generateSnapshot(
                    for: day.placeStops,
                    size: screenSize,
                    regionPadding: 0.05,
                    showPlaceNames: true
                )
            }

            let places = await buildPlaces(from: day.placeStops, targetPixelSize: screenSize)

            storyDays.append(StoryDay(
                dayNumber: idx + 1,
                date: day.date,
                dayCaption: effectiveDayCaption(for: day),
                mapSnapshot: snapshot,
                places: places
            ))
        }
        return storyDays
    }

    // MARK: - Places
    private static func buildPlaces(from stops: [PlaceStop], targetPixelSize: CGSize) async -> [PlaceContent] {
        var out: [PlaceContent] = []
        out.reserveCapacity(stops.count)
        for (idx, stop) in stops.enumerated() {
            let caption = effectivePlaceStory(for: stop)
            let captionIsLong = (caption?.count ?? 0) > 80
            let included = stop.photos.filter(\.isIncluded)
            var idToImage: [UUID: UIImage] = [:]
            await withTaskGroup(of: (UUID, UIImage?).self) { group in
                for photo in included {
                    group.addTask {
                        let img = await loadImageForRecapPhoto(photo, targetPixelSize: targetPixelSize)
                        return (photo.id, img)
                    }
                }
                for await (photoId, image) in group {
                    if let image { idToImage[photoId] = image }
                }
            }
            let photos: [PhotoContent] = included.compactMap { photo in
                guard let image = idToImage[photo.id] else { return nil }
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
            out.append(PlaceContent(
                title: stop.placeTitle,
                subtitle: stop.placeSubtitle,
                markerNumber: idx + 1,
                markerType: markerType,
                timestamp: formattedTimestamp(stop.visitedTimeDigitized),
                caption: caption,
                captionIsLong: captionIsLong,
                photos: photos
            ))
        }
        return out
    }

    // MARK: - Story text (match recap editor / `RecapBlogPageView` + `PlaceStopRowView`)

    /// User-written day caption wins; otherwise AI `dayNarrative`.
    private static func effectiveDayCaption(for day: RecapBlogDay) -> String? {
        if let c = day.dayCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        if let n = day.dayNarrative?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return nil
    }

    /// Manual overall story wins when flagged; else AI `placeNarrative`; else overall story; else place note.
    private static func effectivePlaceStory(for stop: PlaceStop) -> String? {
        let manual = stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stop.overallStoryIsManual, !manual.isEmpty { return manual }
        if let n = stop.placeNarrative?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        if !manual.isEmpty { return manual }
        if let note = stop.noteText?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
        return nil
    }

    // MARK: - Helpers
    private static func normalizedLocalID(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Same resolution order as `PDFExportService.preloadAssets`: app capture → Photo Library (via `ImageLoader`) → signed cloud URL.
    /// Used by slideshow video export and story pipeline.
    static func loadUIImage(for photo: RecapPhoto, targetPixelSize: CGSize) async -> UIImage? {
        await loadImageForRecapPhoto(photo, targetPixelSize: targetPixelSize)
    }

    private static func loadImageForRecapPhoto(_ photo: RecapPhoto, targetPixelSize: CGSize) async -> UIImage? {
        if let lid = normalizedLocalID(photo.localIdentifier) {
            if lid.hasPrefix(AppCapturePhotoService.prefix) {
                return AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            return await ImageLoader.shared.loadImage(assetIdentifier: lid, targetSize: targetPixelSize)
        }
        guard let permanentURL = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !permanentURL.isEmpty else { return nil }
        do {
            let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: permanentURL)
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func loadCoverPhoto(identifier: String?) async -> UIImage? {
        guard let lid = normalizedLocalID(identifier) else { return nil }
        if lid.hasPrefix(AppCapturePhotoService.prefix) {
            return AppCapturePhotoService.shared.loadImage(identifier: lid)
        }
        return await ImageLoader.shared.loadImage(assetIdentifier: lid, targetSize: coverImagePixelSize)
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
