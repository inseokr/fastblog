//
//  GeocodingService.swift
//  Capper
//
//  Reverse geocoding with persisted cache, rate limiting, and stable place labels.
//

import CoreLocation
import Foundation
import MapKit

// Suppress CLGeocoder deprecation warnings as migration to MKReverseGeocodingRequest is pending.
@available(iOS, deprecated: 100.0, message: "Use MKReverseGeocodingRequest")
extension CLGeocoder { }


/// Rounded to 3 decimals for cache key (~111m precision). Matches locality granularity.
func geocodeCacheKey(for location: CLLocation, precise: Bool = false) -> String {
    if precise {
        // 5 decimals ≈ 1.1 m — use for tap-to-resolve-POI so each tap gets its own lookup.
        let lat = (location.coordinate.latitude * 100_000).rounded() / 100_000
        let lon = (location.coordinate.longitude * 100_000).rounded() / 100_000
        return "\(lat),\(lon)"
    }
    let lat = (location.coordinate.latitude * 1000).rounded() / 1000
    let lon = (location.coordinate.longitude * 1000).rounded() / 1000
    return "\(lat),\(lon)"
}

struct GeocodedPlace: Codable {
    let title: String
    let subtitle: String
    let areaName: String
    let cityName: String
    let countryName: String
    /// ISO country code (e.g. "US") for clustering.
    let isoCountryCode: String
    /// Best single label for photo place: POI name, or subLocality, or locality.
    let bestPlaceLabel: String
}

// MARK: - BestPlaceLabel logic
// Strict accuracy: Venue (only if confident) > Neighborhood (subLocality) > City (locality).
// Never guess.
private func bestPlaceLabel(from pm: CLPlacemark) -> String {
    let name = pm.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let subLocality = pm.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let locality = pm.locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    // PRD: "Never guess a venue name". "Wrong names are worse than missing names".
    // Only use 'name' if it's very distinct from address/unknowns and looks like a real venue.
    // If 'name' is just a street address or similar to subLocality, skip it.
    
    if !name.isEmpty && name != subLocality && name != locality && isLikelyVenue(name) {
        return name
    }
    
    // Fallback 1: Neighborhood
    if !subLocality.isEmpty { return subLocality }
    
    // Fallback 2: City
    if !locality.isEmpty { return locality }
    
    return pm.administrativeArea ?? "Unknown Place"
}

/// Strict check for venue-like names.
private func isLikelyVenue(_ name: String) -> Bool {
    let lower = name.lowercased()
    // Validation: typically venues don't start with numbers (addresses) unless they are known brands (7-Eleven).
    // But many addresses start with numbers.
    if name.first?.isNumber == true { return false }
    
    // Avoid generic terms if they are the *only* thing, but usually they are part of a name.
    // Filter out obvious address components if they leak into 'name'.
    let addressTerms = [" st", " ave", " rd", " blvd", " lane", " dr", " drive", " street", " avenue", " road", " boulevard"]
    if addressTerms.contains(where: { lower.hasSuffix($0) }) { return false }
    
    return true
}

/// Max reverse geocode requests per minute (rate limit).
// private let geocodeRateLimitPerMinute = 30

/// Max reverse geocode requests per minute (CLGeocoder / Apple limit).
private let geocodeRateLimitPerMinute = 50

/// Async-safe rate limiter; returns wait seconds so caller sleeps outside actor (Swift 6 compliant).
private actor GeocodeRateLimiter {
    private var requestTimestamps: [Date] = []

    func waitIfNeededAndRecord() async -> TimeInterval {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        requestTimestamps = requestTimestamps.filter { $0 > oneMinuteAgo }
        let needWait: TimeInterval
        // CLGeocoder limit is ~50 per min. If we hit 40, wait up to 1-2s to space them out.
        if requestTimestamps.count >= 40, requestTimestamps.first != nil {
            needWait = min(2.0, max(0.2, 60.0 / 40.0)) // Wait nicely spaced, not 15s.
        } else {
            needWait = 0
        }
        requestTimestamps.append(Date())
        return needWait
    }

    /// Returns recommended seconds to wait before starting a batch of `estimatedNewCalls` requests,
    /// so that we stay under geocodeRateLimitPerMinute. Does not record any requests.
    func recommendedWaitBeforeBatch(estimatedNewCalls: Int) async -> TimeInterval {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let recent = requestTimestamps.filter { $0 > oneMinuteAgo }
        let currentCount = recent.count
        let headroom = geocodeRateLimitPerMinute - currentCount
        if estimatedNewCalls <= headroom { return 0 }
        let overflow = estimatedNewCalls - headroom
        let oldestFirst = recent.sorted()
        guard overflow <= oldestFirst.count else {
            return 60 // Full minute if we can't compute (safety).
        }
        let expireAt = oldestFirst[overflow - 1].addingTimeInterval(60)
        return max(0, expireAt.timeIntervalSince(now))
    }
}

@MainActor
final class GeocodingService {
    static let shared = GeocodingService()
    private let geocoder = CLGeocoder()
    private let rateLimiter = GeocodeRateLimiter()
    private var memoryCache: [String: GeocodedPlace] = [:]
    /// Timezone at location (from CLPlacemark); populated when we reverse-geocode. Used for photo digitized time in local TZ.
    private var timeZoneCache: [String: TimeZone] = [:]
    private let cacheKeyUD = "capper.geocode.persisted"

    private var geocodeCallCount = 0
    private var cacheHitCount = 0
    private var newEntryCount = 0

    private init() {
        loadPersistedCache()
        debugPrint("[Geocoding] Loaded \(memoryCache.count) cached entries from disk")
    }

    /// - Parameter precise: If true, use a finer cache key (~1.1 m) so the exact coordinate is looked up.
    ///   Use for tap-to-resolve-POI; otherwise nearby taps can share a cache entry and show the wrong name.
    func place(for location: CLLocation, precise: Bool = false) async -> GeocodedPlace {
        let key = geocodeCacheKey(for: location, precise: precise)
        if let cached = memoryCache[key] {
            cacheHitCount += 1
            return cached
        }

        let waitSecs = await rateLimiter.waitIfNeededAndRecord()
        if waitSecs > 0 {
            debugPrint("[Geocoding] Rate limited, waiting \(String(format: "%.1f", waitSecs))s...")
            try? await Task.sleep(nanoseconds: UInt64(waitSecs * 1_000_000_000))
        }
        geocodeCallCount += 1
        if geocodeCallCount % 10 == 0 || geocodeCallCount <= 3 {
            debugPrint("[Geocoding] API call #\(geocodeCallCount) (cacheHits=\(cacheHitCount)) key=\(key)")
        }
        let (place, tz) = await performGeocodeWithTimeZone(location: location)
        memoryCache[key] = place
        if let tz = tz { timeZoneCache[key] = tz }
        newEntryCount += 1
        if newEntryCount % 10 == 0 { persistCache() }
        return place
    }

    /// Recommended seconds to wait before starting a batch of up to `estimatedNewCalls` reverse-geocode requests,
    /// so we stay under the 50/min rate limit. Call before processing the next day in recap to avoid throttling.
    func recommendedDelayBeforeNextBatch(estimatedNewCalls: Int) async -> TimeInterval {
        await rateLimiter.recommendedWaitBeforeBatch(estimatedNewCalls: estimatedNewCalls)
    }

    /// Returns timezone at the given location (where the photo was taken). Uses same reverse-geocode cache as place(for:).
    /// Call place(for:) first for that location to populate the cache, or this will trigger one geocode and cache the result.
    func timeZone(for location: CLLocation) async -> TimeZone? {
        let key = geocodeCacheKey(for: location)
        if let cached = timeZoneCache[key] { return cached }
        _ = await place(for: location)
        return timeZoneCache[key]
    }

    /// Prefer stable fields: isoCountryCode, country, locality (fallback subAdministrativeArea), subLocality (fallback name/thoroughfare).
    /// Note: CLGeocoder/reverseGeocodeLocation deprecated in iOS 26 in favor of MKReverseGeocodingRequest.
    private func performGeocode(location: CLLocation) async -> GeocodedPlace {
        let (place, _) = await performGeocodeWithTimeZone(location: location)
        return place
    }

    private func performGeocodeWithTimeZone(location: CLLocation) async -> (GeocodedPlace, TimeZone?) {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let pm = placemarks.first else {
                return (GeocodedPlace(title: "Unknown Place", subtitle: "", areaName: "Unknown Place", cityName: "Unknown Place", countryName: "Unknown", isoCountryCode: "", bestPlaceLabel: "Unknown Place"), nil)
            }
            return (geocodedPlace(from: pm), pm.timeZone)
        } catch {
            return (GeocodedPlace(title: "Unknown Place", subtitle: "", areaName: "Unknown Place", cityName: "Unknown Place", countryName: "Unknown", isoCountryCode: "", bestPlaceLabel: "Unknown Place"), nil)
        }
    }

    private func geocodedPlace(from pm: CLPlacemark) -> GeocodedPlace {
        let title = pm.name ?? pm.locality ?? pm.administrativeArea ?? "Unknown Place"
        var subtitleParts: [String] = []
        if let locality = pm.locality { subtitleParts.append(locality) }
        if let country = pm.country { subtitleParts.append(country) }
        let subtitle = subtitleParts.joined(separator: ", ")
        let areaName = pm.subLocality ?? pm.name ?? pm.thoroughfare ?? pm.locality ?? "Unknown Place"
        let cityName = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea ?? pm.name ?? "Unknown Place"
        let countryName = pm.country ?? "Unknown"
        let isoCountryCode = pm.isoCountryCode ?? ""
        let bestPlaceLabel = bestPlaceLabel(from: pm)
        return GeocodedPlace(title: title, subtitle: subtitle, areaName: areaName, cityName: cityName, countryName: countryName, isoCountryCode: isoCountryCode, bestPlaceLabel: bestPlaceLabel)
    }

    /// Flush any pending cache entries to disk. Call once after a bulk geocoding pass (e.g. end of scan).
    func flushCache() {
        guard newEntryCount > 0 else { return }
        persistCache()
        newEntryCount = 0
    }

    private func persistCache() {
        let payload = memoryCache
        let encodable = payload.mapValues { p -> [String: String] in
            ["title": p.title, "subtitle": p.subtitle, "areaName": p.areaName, "cityName": p.cityName, "countryName": p.countryName, "isoCountryCode": p.isoCountryCode, "bestPlaceLabel": p.bestPlaceLabel]
        }
        UserDefaults.standard.set(encodable, forKey: cacheKeyUD)
    }

    private func loadPersistedCache() {
        guard let raw = UserDefaults.standard.dictionary(forKey: cacheKeyUD) as? [String: [String: String]] else { return }
        for (key, dict) in raw {
            let p = GeocodedPlace(
                title: dict["title"] ?? "Unknown Place",
                subtitle: dict["subtitle"] ?? "",
                areaName: dict["areaName"] ?? "Unknown Place",
                cityName: dict["cityName"] ?? "Unknown Place",
                countryName: dict["countryName"] ?? "Unknown",
                isoCountryCode: dict["isoCountryCode"] ?? "",
                bestPlaceLabel: dict["bestPlaceLabel"] ?? dict["cityName"] ?? "Unknown Place"
            )
            memoryCache[key] = p
        }
    }
}
