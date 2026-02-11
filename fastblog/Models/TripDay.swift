//
//  TripDay.swift
//  Capper
//

import Foundation

struct TripDay: Identifiable, Equatable, Hashable {
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
}
