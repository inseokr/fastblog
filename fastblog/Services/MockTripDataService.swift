//
//  MockTripDataService.swift
//  Capper
//

import Foundation

enum MockScanState {
    case idle
    case scanningDefault
    case scanningMore
}

final class MockTripDataService {
    static let shared = MockTripDataService()

    private let defaultScanDelay: TimeInterval = 1.5
    private let moreScanDelay: TimeInterval = 1.8

    /// Cache for the default "last 3 months" scan. Once processed, we don't re-load this range.
    private var cachedDefaultTrips: [TripDraft]?
    /// Cache for Find More range scans: key "year-startMonth-endMonth" → trips. Same range returns cached result.
    private var cachedRangeTrips: [String: [TripDraft]] = [:]

    private let defaultTripTitles = [
        "Iceland Ring Road", "Morocco Explorer", "Tokyo Week", "Paris Highlights",
        "California Coast", "Alps Hiking", "Barcelona Escape", "London & Edinburgh"
    ]
    private let moreTripTitles = [
        "Northern Lights", "Santorini Sunsets", "Kyoto Temples", "Amsterdam Canals",
        "New York City", "Swiss Mountains", "Rome & Florence", "Sydney & Melbourne"
    ]
    private let coverThemes = ["iceland", "morocco", "tokyo", "paris", "california", "alps", "barcelona", "london"]
    private let createdAgoOptions = ["2 weeks ago", "3 weeks ago", "1 month ago", "6 weeks ago", "2 months ago"]
    private let seasonYearOptions = ["Spring 2024", "Summer 2024", "Fall 2024", "Winter 2024", "Spring 2024"]

    private init() {}

    /// Scans the default "last 3 months" range. First call runs the delay and caches; subsequent calls return cache (no delay).
    func scanLast3Months() async -> [TripDraft] {
        if let cached = cachedDefaultTrips {
            return cached
        }
        try? await Task.sleep(nanoseconds: UInt64(defaultScanDelay * 1_000_000_000))
        let trips = makeTrips(count: 8, fromTitles: defaultTripTitles, isDefaultRange: true)
        cachedDefaultTrips = trips
        return trips
    }

    func scanMoreTrips() async -> [TripDraft] {
        try? await Task.sleep(nanoseconds: UInt64(moreScanDelay * 1_000_000_000))
        return makeTrips(count: 6, fromTitles: moreTripTitles, isDefaultRange: false)
    }

    /// Returns 3–8 country names for the given year. Deterministic; no network. Use when year changes to show a lightweight summary so the UI feels fast. Does not perform a scan.
    func getCountrySummaryForYear(_ year: Int) -> [String] {
        let allCountries = ["Iceland", "Morocco", "Japan", "France", "United States", "Switzerland", "Spain", "United Kingdom", "Greece", "Italy", "Netherlands", "Australia"]
        let count = 3 + (year % 6)
        return (0..<min(count, allCountries.count)).map { i in
            allCountries[(year + i) % allCountries.count]
        }
    }

    /// Simulates scanning for trips in a year/month range. Cached by range: once a range is scanned, we return cache (no delay).
    func scanTripsInRange(year: Int, startMonth: Int, endMonth: Int) async -> [TripDraft] {
        let key = "\(year)-\(startMonth)-\(endMonth)"
        if let cached = cachedRangeTrips[key] {
            return cached
        }
        try? await Task.sleep(nanoseconds: UInt64(1_500_000_000))
        let trips = makeTripsForRange(year: year, startMonth: startMonth, endMonth: endMonth)
        cachedRangeTrips[key] = trips
        return trips
    }

    private func makeTripsForRange(year: Int, startMonth: Int, endMonth: Int) -> [TripDraft] {
        let monthCount = max(1, endMonth - startMonth + 1)
        let titles = ["Northern Lights", "Santorini Sunsets", "Kyoto Temples", "Amsterdam Canals", "New York City", "Swiss Mountains", "Rome & Florence", "Sydney & Melbourne"]
        let seasonYear = seasonLabel(year: year, month: startMonth)
        let createdAgo = "Draft created \(["1 month ago", "2 months ago", "3 months ago"][year % 3])"
        var trips: [TripDraft] = []
        for i in 0..<min(6, monthCount + 2) {
            let title = titles[(year + i) % titles.count]
            let dayCount = 2 + (i % 3)
            let days = makeDaysInRange(year: year, startMonth: startMonth, endMonth: endMonth, tripIndex: i, dayCount: dayCount)
            guard !days.isEmpty else { continue }
            let firstDay = days.first?.dateText ?? ""
            let lastDay = days.last?.dateText ?? ""
            let dateRange = "\(firstDay) – \(lastDay)"
            let theme = coverThemes[i % coverThemes.count]
            let daysSeason = "\(days.count) days • \(seasonYear)"
            trips.append(TripDraft(
                title: title,
                dateRangeText: dateRange,
                days: days,
                coverImageName: theme,
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: createdAgo,
                daysSeasonText: daysSeason,
                coverTheme: theme
            ))
        }
        return trips
    }

    private func seasonLabel(year: Int, month: Int) -> String {
        let season: String
        switch month {
        case 12, 1, 2: season = "Winter"
        case 3...5: season = "Spring"
        case 6...8: season = "Summer"
        default: season = "Fall"
        }
        return "\(season) \(year)"
    }

    private func makeDaysInRange(year: Int, startMonth: Int, endMonth: Int, tripIndex: Int, dayCount: Int) -> [TripDay] {
        var days: [TripDay] = []
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = startMonth
        comps.day = 1
        guard let startDate = calendar.date(from: comps) else { return [] }
        for d in 0..<dayCount {
            let dayOffset = (tripIndex * 7 + d) % 28
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateText = formatter.string(from: date)
            let photoCount = 10 + (tripIndex * 3 + d) % 25
            let photos = makePhotos(count: photoCount, baseDate: date, dayIndex: d)
            days.append(TripDay(dayIndex: d + 1, dateText: dateText, photos: photos))
        }
        return days.sorted { ($0.photos.first?.timestamp ?? .distantPast) < ($1.photos.first?.timestamp ?? .distantPast) }
    }

    private func makeTrips(count: Int, fromTitles titles: [String], isDefaultRange: Bool) -> [TripDraft] {
        var trips: [TripDraft] = []
        for i in 0..<count {
            let title = titles[i % titles.count]
            let dayCount = 2 + (i % 4)
            let days = makeDays(count: dayCount, tripIndex: i)
            let firstDay = days.first?.dateText ?? ""
            let lastDay = days.last?.dateText ?? ""
            let dateRange = "\(firstDay) – \(lastDay)"
            let theme = coverThemes[i % coverThemes.count]
            let daysSeason = "\(dayCount + 6) days • \(seasonYearOptions[i % seasonYearOptions.count])"
            let createdAgo = "Draft created \(createdAgoOptions[i % createdAgoOptions.count])"
            trips.append(TripDraft(
                title: title,
                dateRangeText: dateRange,
                days: days,
                coverImageName: theme,
                isScannedFromDefaultRange: isDefaultRange,
                draftCreatedAgoText: createdAgo,
                daysSeasonText: daysSeason,
                coverTheme: theme
            ))
        }
        return trips
    }

    private func makeDays(count: Int, tripIndex: Int) -> [TripDay] {
        let calendar = Calendar.current
        let now = Date()
        var days: [TripDay] = []
        for d in 0..<count {
            let dayOffset = (tripIndex * 10 + d) % 90
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateText = formatter.string(from: date)
            let photoCount = 10 + (tripIndex * 3 + d) % 31
            let photos = makePhotos(count: photoCount, baseDate: date, dayIndex: d)
            days.append(TripDay(dayIndex: d + 1, dateText: dateText, photos: photos))
        }
        return days
    }

    private func makePhotos(count: Int, baseDate: Date, dayIndex: Int) -> [MockPhoto] {
        let calendar = Calendar.current
        let symbols = ["photo", "camera", "mountain.2", "leaf", "water.waves", "sun.max", "building.2", "airplane", "car", "fork.knife"]
        return (0..<count).map { i in
            let hour = (i * 2 + dayIndex) % 24
            let minute = (i * 7) % 60
            var comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
            comps.hour = hour
            comps.minute = minute
            let ts = calendar.date(from: comps) ?? baseDate
            let sym = symbols[(dayIndex + i) % symbols.count]
            return MockPhoto(imageName: sym, timestamp: ts, locationName: nil, isSelected: false)
        }
    }
}
