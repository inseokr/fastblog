//
//  MemoryRecallService.swift
//  Capper
//

import Photos
import Foundation
import CoreLocation

final class MemoryRecallService {
    static let shared = MemoryRecallService()

    private let calendar = Calendar.current

    private init() {}

    /// Generates a daily recall from already-saved blogs. No photo library scan or geocoding.
    func generateDailyRecall() async -> RecallTrigger? {
        let blogs = await CreatedRecapBlogStore.shared.recents
        guard !blogs.isEmpty else { return nil }
        let now = Date()

        if let recall = onThisDayRecall(from: blogs, for: now) { return recall }
        if let recall = seasonalRecall(from: blogs, for: now) { return recall }
        if let recall = activeMonthRecall(from: blogs) { return recall }
        return nil
    }

    // MARK: - On This Day

    private func onThisDayRecall(from blogs: [CreatedRecapBlog], for now: Date) -> RecallTrigger? {
        let todayMonth = calendar.component(.month, from: now)
        let todayDay   = calendar.component(.day, from: now)
        let thisYear   = calendar.component(.year, from: now)

        let candidates = blogs.compactMap { blog -> (blog: CreatedRecapBlog, yearOffset: Int)? in
            guard let start = blog.tripStartDate else { return nil }
            let m = calendar.component(.month, from: start)
            let d = calendar.component(.day, from: start)
            let y = calendar.component(.year, from: start)
            guard m == todayMonth, d == todayDay, y < thisYear else { return nil }
            return (blog, thisYear - y)
        }.sorted { $0.yearOffset < $1.yearOffset }

        guard let best = candidates.first else { return nil }
        let assets = fetchCoverAssets(for: best.blog)
        guard !assets.isEmpty else { return nil }

        let yearLabel = best.yearOffset == 1 ? "1 year ago" : "\(best.yearOffset) years ago"
        let subtitle  = best.blog.tripStartDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return RecallTrigger(
            type: .onThisDay,
            title: "\(yearLabel) today: \(best.blog.title)",
            subtitle: subtitle,
            assets: assets,
            date: best.blog.tripStartDate!,
            cityName: best.blog.countryName
        )
    }

    // MARK: - Seasonal

    private func seasonalRecall(from blogs: [CreatedRecapBlog], for now: Date) -> RecallTrigger? {
        guard let lastYear = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
        let season = currentSeason(for: now)
        let (start, end) = seasonRange(for: lastYear)

        let best = blogs
            .filter { blog in
                guard let s = blog.tripStartDate else { return false }
                return s >= start && s < end
            }
            .max(by: { $0.selectedPhotoCount < $1.selectedPhotoCount })

        guard let blog = best else { return nil }
        let assets = fetchCoverAssets(for: blog)
        guard !assets.isEmpty else { return nil }

        let seasonName = season.rawValue.capitalized
        let subtitle = blog.tripDateRangeText ?? monthRangeText(start: start, end: end)
        return RecallTrigger(
            type: .seasonal,
            title: "Last \(seasonName): \(blog.title)",
            subtitle: subtitle,
            assets: assets,
            date: start,
            cityName: blog.countryName
        )
    }

    // MARK: - Active Month

    private func activeMonthRecall(from blogs: [CreatedRecapBlog]) -> RecallTrigger? {
        let best = blogs.max(by: { $0.selectedPhotoCount < $1.selectedPhotoCount })
        guard let blog = best else { return nil }
        let assets = fetchCoverAssets(for: blog)
        guard !assets.isEmpty else { return nil }

        return RecallTrigger(
            type: .activeMonth,
            title: blog.title,
            subtitle: "\(blog.selectedPhotoCount) memories captured",
            assets: assets,
            date: blog.tripStartDate ?? blog.createdAt,
            cityName: blog.countryName
        )
    }

    // MARK: - Helpers

    /// Fetches just the cover asset for a blog. Single identifier lookup — no scanning, no geocoding.
    private func fetchCoverAssets(for blog: CreatedRecapBlog) -> [PHAsset] {
        guard let identifier = blog.coverAssetIdentifier else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard result.count > 0 else { return [] }
        return [result.object(at: 0)]
    }

    private func currentSeason(for date: Date) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .fall
        default:     return .winter
        }
    }

    private func seasonRange(for date: Date) -> (start: Date, end: Date) {
        let year = calendar.component(.year, from: date)
        let season = currentSeason(for: date)
        var comps = DateComponents()
        comps.year = year
        switch season {
        case .spring: comps.month = 3
        case .summer: comps.month = 6
        case .fall:   comps.month = 9
        case .winter: comps.month = 12
        }
        comps.day = 1
        let start = calendar.date(from: comps)!
        let end   = calendar.date(byAdding: .month, value: 3, to: start)!
        return (start, end)
    }

    private enum Season: String {
        case spring, summer, fall, winter
    }

    private func monthRangeText(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return "\(f.string(from: start)) – \(f.string(from: calendar.date(byAdding: .day, value: -1, to: end)!))"
    }
}
