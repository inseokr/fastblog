//
//  WeatherService.swift
//  fastblog
//
//  Fetches daily weather from Open-Meteo (free, no API key).
//  Uses archive API for past dates (>7 days ago) and forecast API for recent/future dates.
//

import Foundation

// MARK: - DayWeather

struct DayWeather: Equatable, Codable, Sendable {
    var weatherCode: Int
    var tempMaxC: Double
    var tempMinC: Double
    var precipitationMm: Double

    var tempMaxF: Double { tempMaxC * 9 / 5 + 32 }
    var tempMinF: Double { tempMinC * 9 / 5 + 32 }

    /// Human-readable description from WMO weather code.
    var description: String {
        switch weatherCode {
        case 0:             return "Clear sky"
        case 1:             return "Mainly clear"
        case 2:             return "Partly cloudy"
        case 3:             return "Overcast"
        case 45, 48:        return "Foggy"
        case 51, 53, 55:    return "Drizzle"
        case 61, 63, 65:    return "Rain"
        case 71, 73, 75:    return "Snow"
        case 77:            return "Snow grains"
        case 80, 81, 82:    return "Rain showers"
        case 85, 86:        return "Snow showers"
        case 95:            return "Thunderstorm"
        case 96, 99:        return "Thunderstorm with hail"
        default:            return "Unknown"
        }
    }

    /// Single emoji representing the weather.
    var emoji: String {
        switch weatherCode {
        case 0:             return "☀️"
        case 1:             return "🌤️"
        case 2:             return "⛅️"
        case 3:             return "☁️"
        case 45, 48:        return "🌫️"
        case 51, 53, 55:    return "🌦️"
        case 61, 63, 65:    return "🌧️"
        case 71, 73, 75:    return "❄️"
        case 77:            return "🌨️"
        case 80, 81, 82:    return "🌧️"
        case 85, 86:        return "🌨️"
        case 95, 96, 99:    return "⛈️"
        default:            return "🌡️"
        }
    }

    /// Daily high / low for display using the user’s preferred unit (`°F` or `°C`).
    func temperatureHighLow(for unit: WeatherTemperatureUnit) -> (high: Int, low: Int, suffix: String) {
        switch unit {
        case .fahrenheit:
            return (Int(tempMaxF.rounded()), Int(tempMinF.rounded()), "°F")
        case .celsius:
            return (Int(tempMaxC.rounded()), Int(tempMinC.rounded()), "°C")
        }
    }
}

/// User preference for how blog day weather temperatures are shown. Stored in `UserDefaults` via `@AppStorage`.
enum WeatherTemperatureUnit: String, CaseIterable {
    case fahrenheit
    case celsius

    static let storageKey = "fastblog.weatherTemperatureUnit"

    var displayName: String {
        switch self {
        case .fahrenheit: return "Fahrenheit (°F)"
        case .celsius: return "Celsius (°C)"
        }
    }
}

/// User preference for how distances between places are shown. Stored in `UserDefaults` via `@AppStorage`.
enum DistanceUnit: String, CaseIterable {
    case miles
    case kilometers

    static let storageKey = "fastblog.distanceUnit"

    var displayName: String {
        switch self {
        case .miles: return "Miles (mi)"
        case .kilometers: return "Kilometers (km)"
        }
    }
}

// MARK: - WeatherService

@MainActor
final class WeatherService {
    static let shared = WeatherService()
    private var cache: [String: DayWeather] = [:]

    private init() {}

    /// Fetches weather for the given coordinate and calendar date.
    /// Returns nil if the data is unavailable (network error, date out of range, no location).
    func fetchWeather(latitude: Double, longitude: Double, date: Date) async -> DayWeather? {
        let dateString = isoDateString(from: date)
        let cacheKey = weatherCacheKey(latitude: latitude, longitude: longitude, dateString: dateString)
        if let cached = cache[cacheKey] { return cached }

        let baseURL: String
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        if date < sevenDaysAgo {
            baseURL = "https://archive-api.open-meteo.com/v1/archive"
        } else {
            baseURL = "https://api.open-meteo.com/v1/forecast"
        }

        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        let urlString = "\(baseURL)?latitude=\(lat)&longitude=\(lon)" +
            "&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum" +
            "&start_date=\(dateString)&end_date=\(dateString)&timezone=auto"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                print("[WeatherService] ⚠️ Non-2xx response for \(urlString)")
                return nil
            }
            guard let weather = parseWeather(from: data) else { return nil }
            cache[cacheKey] = weather
            return weather
        } catch {
            print("[WeatherService] ⚠️ Fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private helpers

    private func isoDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Cache key rounded to ~1 km (~2 decimal places) so nearby places on the same day share a result.
    private func weatherCacheKey(latitude: Double, longitude: Double, dateString: String) -> String {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        return "\(lat),\(lon),\(dateString)"
    }

    private func parseWeather(from data: Data) -> DayWeather? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: Any],
              let codes = daily["weathercode"] as? [Double],
              let maxTemps = daily["temperature_2m_max"] as? [Double],
              let minTemps = daily["temperature_2m_min"] as? [Double],
              let precip = daily["precipitation_sum"] as? [Double],
              !codes.isEmpty else {
            return nil
        }
        return DayWeather(
            weatherCode: Int(codes[0]),
            tempMaxC: maxTemps[0],
            tempMinC: minTemps[0],
            precipitationMm: precip[0]
        )
    }
}
