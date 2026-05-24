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

    private static let dailyVariables =
        "weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum"
    private static let retryableStatusCodes: Set<Int> = [502, 503, 504]
    private static let maxAttempts = 3

    private init() {}

    /// Fetches weather for the given coordinate and calendar date.
    /// Returns nil if the data is unavailable (network error, date out of range, no location).
    func fetchWeather(latitude: Double, longitude: Double, date: Date) async -> DayWeather? {
        let results = await fetchWeather(
            requests: [(date: date, latitude: latitude, longitude: longitude)]
        )
        let key = weatherCacheKey(
            latitude: latitude,
            longitude: longitude,
            dateString: isoDateString(from: date)
        )
        return results[key]
    }

    /// Fetches weather for multiple days, batching by coordinate bucket and date range.
    func fetchWeather(
        requests: [(date: Date, latitude: Double, longitude: Double)]
    ) async -> [String: DayWeather] {
        guard !requests.isEmpty else { return [:] }

        var results: [String: DayWeather] = [:]
        var uncached: [(date: Date, latitude: Double, longitude: Double)] = []

        for req in requests {
            let dateString = isoDateString(from: req.date)
            let key = weatherCacheKey(
                latitude: req.latitude,
                longitude: req.longitude,
                dateString: dateString
            )
            if let cached = cache[key] {
                results[key] = cached
            } else {
                uncached.append(req)
            }
        }

        guard !uncached.isEmpty else { return results }

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let groups = Dictionary(grouping: uncached) { req in
            coordinateBucket(latitude: req.latitude, longitude: req.longitude)
        }

        for (bucket, group) in groups {
            let sorted = group.sorted { $0.date < $1.date }
            guard let firstDate = sorted.first?.date,
                  let lastDate = sorted.last?.date,
                  let sample = sorted.first else { continue }

            let startString = isoDateString(from: firstDate)
            let endString = isoDateString(from: lastDate)
            let usesHistorical = firstDate < sevenDaysAgo

            debugLog(
                "batch \(sorted.count) day(s) bucket=\(bucket) " +
                "range=\(startString)…\(endString) historical=\(usesHistorical)"
            )

            let byDate = await fetchDailyRange(
                latitude: sample.latitude,
                longitude: sample.longitude,
                startDateString: startString,
                endDateString: endString,
                usesHistorical: usesHistorical
            )

            for req in sorted {
                let dateString = isoDateString(from: req.date)
                let key = weatherCacheKey(
                    latitude: req.latitude,
                    longitude: req.longitude,
                    dateString: dateString
                )
                if let weather = byDate[dateString] {
                    cache[key] = weather
                    results[key] = weather
                }
            }
        }

        return results
    }

    /// Lookup key returned by `fetchWeather(requests:)`.
    func cacheKey(latitude: Double, longitude: Double, date: Date) -> String {
        weatherCacheKey(
            latitude: latitude,
            longitude: longitude,
            dateString: isoDateString(from: date)
        )
    }

    /// Clears in-memory cache (useful when re-running weather after debugging).
    func clearCacheForDebug() {
        let count = cache.count
        cache.removeAll()
        debugLog("cleared cache (\(count) entries)")
    }

    // MARK: - Network

    private struct WeatherEndpoint {
        let kind: String
        let baseURL: String
    }

    private func fetchDailyRange(
        latitude: Double,
        longitude: Double,
        startDateString: String,
        endDateString: String,
        usesHistorical: Bool
    ) async -> [String: DayWeather] {
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        let query =
            "latitude=\(lat)&longitude=\(lon)" +
            "&daily=\(Self.dailyVariables)" +
            "&start_date=\(startDateString)&end_date=\(endDateString)&timezone=auto"

        let endpoints: [WeatherEndpoint]
        if usesHistorical {
            endpoints = [
                WeatherEndpoint(kind: "archive", baseURL: "https://archive-api.open-meteo.com/v1/archive"),
                WeatherEndpoint(
                    kind: "historical-forecast",
                    baseURL: "https://historical-forecast-api.open-meteo.com/v1/forecast"
                ),
            ]
        } else {
            endpoints = [
                WeatherEndpoint(kind: "forecast", baseURL: "https://api.open-meteo.com/v1/forecast"),
            ]
        }

        for endpoint in endpoints {
            let urlString = "\(endpoint.baseURL)?\(query)"
            guard let url = URL(string: urlString) else {
                debugLog("invalid URL: \(urlString)")
                continue
            }
            debugLog("trying \(endpoint.kind): \(urlString)")
            switch await dataWithRetry(from: url, apiKind: endpoint.kind) {
            case .success(let data):
                if let byDate = parseDailyRange(from: data) {
                    debugLog("\(endpoint.kind) OK: \(byDate.count) day(s)")
                    return byDate
                }
                debugLog("\(endpoint.kind) parse failed: \(debugBodyPreview(data))")
            case .failure(let error):
                debugLog("\(endpoint.kind) failed: \(error)")
            }
        }

        return [:]
    }

    private enum FetchResult {
        case success(Data)
        case failure(String)
    }

    private func dataWithRetry(from url: URL, apiKind: String) async -> FetchResult {
        let urlString = url.absoluteString
        for attempt in 1...Self.maxAttempts {
            let started = ContinuousClock.now
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let elapsedMs = started.duration(to: ContinuousClock.now).milliseconds
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure("non-HTTP response after \(elapsedMs)ms")
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    debugLog("\(apiKind) HTTP \(httpResponse.statusCode) in \(elapsedMs)ms (\(data.count) bytes)")
                    return .success(data)
                }

                let status = httpResponse.statusCode
                let retryable = Self.retryableStatusCodes.contains(status)
                if retryable, attempt < Self.maxAttempts {
                    debugLog(
                        "\(apiKind) HTTP \(status) attempt \(attempt)/\(Self.maxAttempts) " +
                        "(\(elapsedMs)ms), retrying…"
                    )
                    try await Task.sleep(for: .seconds(attempt))
                    continue
                }

                debugLog(
                    "\(apiKind) HTTP \(status) (\(elapsedMs)ms)\n" +
                    "  URL: \(urlString)\n" +
                    "  Body: \(debugBodyPreview(data))"
                )
                return .failure("HTTP \(status)")
            } catch {
                let elapsedMs = started.duration(to: ContinuousClock.now).milliseconds
                if attempt < Self.maxAttempts {
                    debugLog("\(apiKind) error attempt \(attempt): \(error) (\(elapsedMs)ms), retrying…")
                    try? await Task.sleep(for: .seconds(attempt))
                    continue
                }
                return .failure("\(error) after \(elapsedMs)ms")
            }
        }
        return .failure("exhausted retries")
    }

    // MARK: - Parsing

    private func parseDailyRange(from data: Data) -> [String: DayWeather]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let reason = json["reason"] as? String {
            debugLog("API error reason: \(reason)")
            return nil
        }
        guard let daily = json["daily"] as? [String: Any],
              let times = daily["time"] as? [String],
              let codes = daily["weathercode"] as? [Double],
              let maxTemps = daily["temperature_2m_max"] as? [Double],
              let minTemps = daily["temperature_2m_min"] as? [Double],
              let precip = daily["precipitation_sum"] as? [Double],
              !times.isEmpty else {
            if let daily = json["daily"] as? [String: Any] {
                debugLog("daily keys present but arrays missing/empty: \(daily.keys.sorted())")
            } else {
                debugLog("JSON missing \"daily\"; top-level keys: \(json.keys.sorted())")
            }
            return nil
        }

        var byDate: [String: DayWeather] = [:]
        for index in times.indices {
            guard index < codes.count,
                  index < maxTemps.count,
                  index < minTemps.count,
                  index < precip.count else { break }
            let code = codes[index]
            let maxT = maxTemps[index]
            let minT = minTemps[index]
            guard code.isFinite, maxT.isFinite, minT.isFinite else { continue }
            byDate[times[index]] = DayWeather(
                weatherCode: Int(code),
                tempMaxC: maxT,
                tempMinC: minT,
                precipitationMm: precip[index]
            )
        }
        return byDate.isEmpty ? nil : byDate
    }

    // MARK: - Private helpers

    private func isoDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// ~1 km buckets for batching nearby stops on the same trip.
    private func coordinateBucket(latitude: Double, longitude: Double) -> String {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }

    /// Cache key rounded to ~1 km (~2 decimal places) so nearby places on the same day share a result.
    private func weatherCacheKey(latitude: Double, longitude: Double, dateString: String) -> String {
        "\(coordinateBucket(latitude: latitude, longitude: longitude)),\(dateString)"
    }

    private func debugLog(_ message: String) {
        print("[WeatherService] \(message)")
    }

    private func debugBodyPreview(_ data: Data, maxLength: Int = 400) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, not UTF-8>"
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "…"
    }
}

private extension Duration {
    var milliseconds: Int {
        Int((Double(components.seconds) + Double(components.attoseconds) / 1e18) * 1000)
    }
}
