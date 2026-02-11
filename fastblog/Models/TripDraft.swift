//
//  TripDraft.swift
//  Capper
//

import CoreLocation
import Foundation

struct TripDraft: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var dateRangeText: String
    var days: [TripDay]
    var coverImageName: String  // SF Symbol or asset name
    var isScannedFromDefaultRange: Bool
    /// e.g. "2 weeks ago", "1 month ago"
    var draftCreatedAgoText: String
    /// e.g. "10 days • Spring 2024"
    var daysSeasonText: String
    /// Theme for photo-like cover: iceland, morocco, tokyo, etc.
    var coverTheme: String
    /// When set, show this asset as the cover image instead of theme gradient (e.g. from photo library scan).
    var coverAssetIdentifier: String?

    init(id: UUID = UUID(), title: String, dateRangeText: String, days: [TripDay], coverImageName: String, isScannedFromDefaultRange: Bool, draftCreatedAgoText: String = "Draft created recently", daysSeasonText: String = "", coverTheme: String = "default", coverAssetIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.dateRangeText = dateRangeText
        self.days = days
        self.coverImageName = coverImageName
        self.isScannedFromDefaultRange = isScannedFromDefaultRange
        self.draftCreatedAgoText = draftCreatedAgoText
        self.daysSeasonText = daysSeasonText
        self.coverTheme = coverTheme
        self.coverAssetIdentifier = coverAssetIdentifier
    }

    /// Center coordinate for map annotation (average of all photo locations). Nil if no photos have location.
    var centerCoordinate: CLLocationCoordinate2D? {
        let coords = days.flatMap(\.photos).compactMap(\.location)
        guard !coords.isEmpty else { return nil }
        let lat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
        let lon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var totalPhotoCount: Int {
        days.reduce(0) { $0 + $1.photos.count }
    }

    var selectedPhotoCount: Int {
        days.reduce(0) { $0 + $1.photos.filter(\.isSelected).count }
    }

    /// Earliest date in the trip (from first day) for sorting. Nil if unparseable.
    var earliestDate: Date? {
        guard let first = days.first else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter.date(from: first.dateText)
    }

    /// Latest date in the trip (from last day). Nil if unparseable. Used for excluding blog dates from scan.
    var latestDate: Date? {
        guard let last = days.last else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter.date(from: last.dateText)
    }

    /// City that has the most photos in this trip (from photo locationName). Fallback: parse "Trip To X" from title, else "New Place".
    var cityWithMostPhotosDisplayName: String {
        let allPhotos = days.flatMap(\.photos)
        let withCity = allPhotos.compactMap { p -> String? in
            let name = p.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name != nil && !name!.isEmpty) ? name : nil
        }
        if withCity.isEmpty {
            if title.hasPrefix("Trip To ") {
                let rest = String(title.dropFirst("Trip To ".count))
                if let inRange = rest.range(of: " in ") {
                    return String(rest[..<inRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return rest.trimmingCharacters(in: .whitespaces)
            }
            if let country = primaryCountryDisplayName, !country.isEmpty {
                return country
            }
            return "New Place"
        }
        var count: [String: Int] = [:]
        for city in withCity { count[city, default: 0] += 1 }
        return count.max(by: { $0.value < $1.value })?.key ?? "New Place"
    }

    /// Country that has the most photos in this trip (from photo countryName). Nil if none.
    var primaryCountryDisplayName: String? {
        let allPhotos = days.flatMap(\.photos)
        let withCountry = allPhotos.compactMap { p -> String? in
            let name = p.countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name != nil && !name!.isEmpty && name != "Unknown") ? name : nil
        }
        if withCountry.isEmpty { return nil }
        var count: [String: Int] = [:]
        for c in withCountry { count[c, default: 0] += 1 }
        return count.max(by: { $0.value < $1.value })?.key
    }

    /// Primary default format: "{TopCity}, {Country}" or "{TopCity} Area, {Country}" or "{Country} Trip". Used when scan sets title and for blog title.
    var defaultBlogTitleGeoFormat: String {
        let city = cityWithMostPhotosDisplayName
        let country = primaryCountryDisplayName ?? "Unknown"
        if city.isEmpty || city == "New Place" {
            return "\(country) Trip"
        }
        let allCityNames = days.flatMap(\.photos).compactMap { $0.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let uniqueCities = Set(allCityNames)
        if uniqueCities.count > 1 {
            return "\(city) Area, \(country)"
        }
        return "\(city), \(country)"
    }

    /// Default blog title: prefers geo format (TopCity, Country), then "Trip to [City] in [Season]" when season is set.
    var defaultBlogTitle: String {
        let season = seasonDisplayText
        let geo = defaultBlogTitleGeoFormat
        if season.isEmpty { return geo }
        if geo.hasSuffix(" Trip") {
            return geo
        }
        return "\(geo) in \(season)"
    }

    /// Season from trip dates (earliest date month): Winter, Spring, Summer, Fall.
    var seasonDisplayText: String {
        guard let date = earliestDate else { return "" }
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 12, 1, 2: return "Winter"
        case 3, 4, 5: return "Spring"
        case 6, 7, 8: return "Summer"
        case 9, 10, 11: return "Fall"
        default: return "Winter"
        }
    }

    /// Trip dates in "Jan 15 - 20 2025" style for display on the Drafts list.
    var tripDateRangeDisplayText: String {
        guard let first = days.first, let last = days.last else {
            return dateRangeText
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        guard let startDate = formatter.date(from: first.dateText),
              let endDate = formatter.date(from: last.dateText) else {
            return first.dateText == last.dateText ? first.dateText : dateRangeText
        }
        let cal = Calendar.current
        let startMonth = cal.component(.month, from: startDate)
        let endMonth = cal.component(.month, from: endDate)
        let startYear = cal.component(.year, from: startDate)
        let endYear = cal.component(.year, from: endDate)
        let startDay = cal.component(.day, from: startDate)
        let endDay = cal.component(.day, from: endDate)
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMM"
        let startMonthStr = monthFormatter.string(from: startDate)
        let endMonthStr = monthFormatter.string(from: endDate)
        let yearStr = String(startYear)
        if startDate == endDate {
            return "\(startMonthStr) \(startDay) \(yearStr)"
        }
        if startMonth == endMonth && startYear == endYear {
            return "\(startMonthStr) \(startDay) - \(endDay) \(yearStr)"
        }
        return "\(startMonthStr) \(startDay) - \(endMonthStr) \(endDay) \(endYear == startYear ? yearStr : String(endYear))"
    }
}
