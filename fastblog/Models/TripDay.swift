//
//  TripDay.swift
//  Capper
//

import Foundation

struct TripDay: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var dayIndex: Int
    var dateText: String
    var photos: [MockPhoto]
    /// ISO country code for this day (from geocoding).
    var countryCode: String?
    var countryName: String?
    /// Primary city name for this day.
    var cityName: String?

    init(id: UUID = UUID(), dayIndex: Int, dateText: String, photos: [MockPhoto] = [], countryCode: String? = nil, countryName: String? = nil, cityName: String? = nil) {
        self.id = id
        self.dayIndex = dayIndex
        self.dateText = dateText
        self.photos = photos
        self.countryCode = countryCode
        self.countryName = countryName
        self.cityName = cityName
    }

    /// Calendar date aligned with `dateText` for range formatting (local noon avoids timezone day shifts).
    var dateAlignedForRange: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        guard let parsed = formatter.date(from: dateText) else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: parsed)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)
    }
}
