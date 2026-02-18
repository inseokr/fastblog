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
    
    /// Scans library for memories and generates a high-quality daily recall trigger.
    func generateDailyRecall() async -> RecallTrigger? {
        let now = Date()
        
        // 1. Try "On This Day" (High Priority)
        if let onThisDay = await generateOnThisDayRecall(for: now) {
            return onThisDay
        }
        
        // 2. Try "City Repeat" (Interesting Insight)
        if let cityRepeat = await generateCityRepeatRecall() {
            return cityRepeat
        }
        
        // 3. Try "Seasonal" (Broader context)
        if let seasonal = await generateSeasonalRecall(for: now) {
            return seasonal
        }
        
        // 4. Try "Active Month" (Fallback)
        if let activeMonth = await generateActiveMonthRecall() {
            return activeMonth
        }
        
        return nil
    }
    
    // MARK: - On This Day
    
    private func generateOnThisDayRecall(for date: Date) async -> RecallTrigger? {
        let occupied = CreatedRecapBlogStore.shared.occupiedDateRanges()
        let years = Array(1...10) // Check last 10 years (expanded history)
        
        for yearOffset in years {
            guard let targetDate = calendar.date(byAdding: .year, value: -yearOffset, to: date) else { continue }
            
            // Fetch photos from a 48h window around this day
            let start = calendar.date(byAdding: .hour, value: -24, to: targetDate)!
            let end = calendar.date(byAdding: .hour, value: 24, to: targetDate)!
            
            // Use refined scanner logic
            let trips = await PhotoLibraryTripService.shared.scanFlexibleRange(start: start, end: end, occupiedDateRanges: occupied)
            
            // Pick the largest trip that matches the date
            guard let bestTrip = trips.max(by: { $0.assets.count < $1.assets.count }), bestTrip.assets.count >= 5 else { continue }
            
            let cityName = bestTrip.draft.days.first?.cityName
            let yearString = yearOffset == 1 ? "1 year ago" : "\(yearOffset) years ago"
            let title = cityName != nil ? "\(yearString) today, you were in \(cityName!)" : "\(yearString) today"
            
            return RecallTrigger(
                type: .onThisDay,
                title: title,
                subtitle: targetDate.formatted(date: .abbreviated, time: .omitted),
                assets: bestTrip.assets,
                date: targetDate,
                cityName: cityName
            )
        }
        
        return nil
    }
    
    // MARK: - City Repeat
    
    private func generateCityRepeatRecall() async -> RecallTrigger? {
        // This requires a more complex scan of library history.
        // For efficiency, we can use the existing scanLibrarySummary or a lighter version.
        _ = await PhotoLibraryTripService.shared.scanLibrarySummary()
        
        // Logic: if user has a lot of photos in one city across different dates, highlight it.
        // For MVP, we'll keep it simple: find a city where they have many photos.
        // Implementation detail: we need city-level counts which aren't in LibrarySummary yet.
        // Let's skip for now or provide a mock-able version.
        return nil
    }
    
    // MARK: - Seasonal
    
    private func generateSeasonalRecall(for date: Date) async -> RecallTrigger? {
        guard let lastYear = calendar.date(byAdding: .year, value: -1, to: date) else { return nil }
        let occupied = CreatedRecapBlogStore.shared.occupiedDateRanges()
        
        let season = currentSeason(for: date)
        let (start, end) = seasonRange(for: lastYear)
        
        // Use refined scanner logic for the whole season
        let trips = await PhotoLibraryTripService.shared.scanFlexibleRange(start: start, end: end, occupiedDateRanges: occupied)
        
        // Pick the most significant unsaved trip from last year's season
        guard let bestTrip = trips.max(by: { $0.assets.count < $1.assets.count }), bestTrip.assets.count >= 10 else { return nil }
        
        let cityName = bestTrip.draft.days.first?.cityName
        let seasonName = season.rawValue.capitalized
        let title = cityName != nil ? "Last \(seasonName), you visited \(cityName!)" : "Last \(seasonName)"
        
        return RecallTrigger(
            type: .seasonal,
            title: title,
            subtitle: "Surfaced from your \(monthRangeText(start: start, end: end)) memories",
            assets: bestTrip.assets,
            date: bestTrip.assets.first?.creationDate ?? lastYear,
            cityName: cityName
        )
    }
    
    // MARK: - Active Month
    
    private func generateActiveMonthRecall() async -> RecallTrigger? {
        let summary = await PhotoLibraryTripService.shared.scanLibrarySummary()
        guard let top = summary.mostActiveMonths.first else { return nil }
        let occupied = CreatedRecapBlogStore.shared.occupiedDateRanges()
        
        var comps = DateComponents()
        comps.year = top.year
        comps.month = top.month
        comps.day = 1
        guard let start = calendar.date(from: comps) else { return nil }
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        
        // Use refined scanner logic to find trips in that active month
        let trips = await PhotoLibraryTripService.shared.scanFlexibleRange(start: start, end: end, occupiedDateRanges: occupied)
        
        if let bestTrip = trips.max(by: { $0.assets.count < $1.assets.count }), bestTrip.assets.count >= 10 {
            let cityName = bestTrip.draft.days.first?.cityName
            let monthName = DateFormatter().monthSymbols[top.month - 1]
            let title = cityName != nil ? "Your trip to \(cityName!) in \(monthName)" : "\(monthName) \(top.year)"
            
            return RecallTrigger(
                type: .activeMonth,
                title: title,
                subtitle: "\(bestTrip.assets.count) memories captured",
                assets: bestTrip.assets,
                date: start,
                cityName: cityName
            )
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func resolveCityName(for assets: [PHAsset]) async -> String? {
        let locationWithAuth = assets.compactMap { $0.location }
        guard let first = locationWithAuth.first else { return nil }
        
        let place = await GeocodingService.shared.place(for: first)
        return place.cityName.isEmpty ? nil : place.cityName
    }
    
    private func currentSeason(for date: Date) -> Season {
        let month = calendar.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
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
        case .fall: comps.month = 9
        case .winter: comps.month = 12
        }
        comps.day = 1
        
        let start = calendar.date(from: comps)!
        let end = calendar.date(byAdding: .month, value: 3, to: start)!
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
