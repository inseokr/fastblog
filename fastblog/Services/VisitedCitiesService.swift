//
//  VisitedCitiesService.swift
//  fastblog
//

import CoreLocation
import Foundation
import Photos

// MARK: - Model

struct VisitedCityTrip: Identifiable, Codable {
    var id: UUID = UUID()
    let cityName: String
    let countryName: String
    let startDate: Date
    let endDate: Date
    let dayCount: Int
    let photoCount: Int
    let coverAssetIdentifier: String?
    /// IANA id from reverse-geocode at the place cell; used so date labels match capture-timezone wall times (e.g. preview digitized line).
    let displayTimeZoneIdentifier: String?

    var displayTitle: String {
        if cityName.isEmpty {
            return countryName.isEmpty ? "Trip" : countryName
        }
        if countryName.isEmpty || countryName == cityName {
            return cityName
        }
        return "\(cityName), \(countryName)"
    }

    var displaySubtitle: String {
        dateRangeText
    }

    /// Uses `displayTimeZoneIdentifier` when set (capture region); else device zone. Single calendar day → one string (not "Jan 5 – Jan 5").
    var dateRangeText: String {
        let tz = displayTimeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale.current
        if cal.isDate(startDate, inSameDayAs: endDate) {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            f.timeZone = tz
            f.locale = Locale.current
            f.calendar = cal
            return f.string(from: startDate)
        }
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = tz
        f.locale = Locale.current
        return f.string(from: startDate, to: endDate)
    }
}

// MARK: - Build State

enum VisitedCitiesBuildState: Equatable {
    case idle
    case building(Double) // progress 0.0–1.0
    case done
}

// MARK: - Service

/// Per-year photo scan:
/// • All photos per calendar day (falls back through assets if the first has bad GPS)
/// • Home-exclusion filtering (reuses NeighborhoodStore + TripPhotoFilter)
/// • Phase 4a: assign every day to a 0.5° grid cell (no API calls)
/// • Phase 4b: reverse-geocode only UNIQUE grid cells — drastically reduces API calls
/// • Groups consecutive same-city days into VisitedCityTrip candidates
/// • Persists results to UserDefaults (valid for 3 days, keyed by userId + year)
final class VisitedCitiesService {
    static let shared = VisitedCitiesService()
    private init() {}

    private let calendar = Calendar.current

    // MARK: - Cache

    private static let cacheKeyPrefix = "visitedCities.v6"
    private static let cacheMaxAge: TimeInterval = 3 * 24 * 3600 // 3 days

    private struct Cache: Codable {
        let savedAt: Date
        let trips: [VisitedCityTrip]
    }

    private func cacheKey(userId: String, year: Int) -> String {
        "\(Self.cacheKeyPrefix).\(userId).year\(year)"
    }

    func loadCached(userId: String, year: Int) -> [VisitedCityTrip]? {
        let key = cacheKey(userId: userId, year: year)
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let cache = try? JSONDecoder().decode(Cache.self, from: data),
            Date().timeIntervalSince(cache.savedAt) < Self.cacheMaxAge
        else { return nil }
        return cache.trips
    }

    func saveCache(_ trips: [VisitedCityTrip], userId: String, year: Int) {
        let key = cacheKey(userId: userId, year: year)
        if let data = try? JSONEncoder().encode(Cache(savedAt: Date(), trips: trips)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clearCache(userId: String, year: Int) {
        UserDefaults.standard.removeObject(forKey: cacheKey(userId: userId, year: year))
    }

    // MARK: - Build

    /// Scans photos taken during `year` (Jan 1 – Dec 31, capped at today).
    /// Reports progress 0.0 → 1.0 via `progress`.
    func buildVisitedCities(
        year: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> [VisitedCityTrip] {

        let now = Date()

        // Exact year window
        var startComps = DateComponents(); startComps.year = year; startComps.month = 1;  startComps.day = 1
        var endComps   = DateComponents(); endComps.year   = year; endComps.month   = 12; endComps.day   = 31
        guard
            let windowStart = calendar.date(from: startComps),
            let windowEndRaw = calendar.date(from: endComps)
        else { return [] }
        let windowEnd = min(windowEndRaw, now)
        guard windowStart <= windowEnd else { return [] }

        // ── Phase 1: Fetch located, non-screenshot images in the year window ──
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            windowStart as NSDate, windowEnd as NSDate, PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var allAssets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot),
                  asset.location != nil else { return }
            allAssets.append(asset)
        }
        progress(0.05)

        // ── Phase 2: Home exclusion ──
        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
        let filtered: [PHAsset]
        if let homeLocation = home {
            filtered = allAssets.filter {
                TripPhotoFilter.shouldIncludeInTrips(
                    assetLocation: $0.location, home: homeLocation, minMiles: minMiles)
            }
        } else {
            filtered = allAssets
        }
        progress(0.10)
        guard !filtered.isEmpty else { return [] }

        // ── Phase 2.5: Capture timezone per asset (local EXIF only — no iCloud download) ──
        // Buckets yyyy-MM-dd in that zone. Missing offset uses device calendar; phase 4b sets display TZ from geocoded cells.
        if Task.isCancelled { return [] }
        let tzByAssetId = await APIManager.buildCaptureTimeZoneMap(for: filtered, allowNetwork: false)
        progress(0.13)

        // ── Phase 3: Collect ALL assets per calendar day (local day in capture timezone) ──
        // Keeping every asset lets Phase 4a fall back through photos when
        // the first one has bad or missing GPS metadata.
        var dayMap: [String: [PHAsset]] = [:]
        for asset in filtered {
            guard let date = asset.creationDate else { continue }
            let tz = tzByAssetId[asset.localIdentifier] ?? TimeZone.current
            let dayFmt = DateFormatter()
            dayFmt.locale = Locale(identifier: "en_US_POSIX")
            dayFmt.calendar = Calendar(identifier: .gregorian)
            dayFmt.timeZone = tz
            dayFmt.dateFormat = "yyyy-MM-dd"
            dayMap[dayFmt.string(from: date), default: []].append(asset)
        }
        let sortedDays = dayMap.keys.sorted()
        progress(0.15)
        guard !sortedDays.isEmpty else { return [] }

        // ── Phase 4a: Assign every day to a 0.5° grid cell (no API calls) ──
        // For each day, iterate its assets until we find one with a GPS fix.
        // 0.5° ≈ 55 km — coarse enough to deduplicate within a city.
        struct GridCell: Hashable {
            let latBucket: Int  // Int(lat * 2, rounded)
            let lonBucket: Int  // Int(lon * 2, rounded)
        }

        // dayCell[dateKey] = the grid cell for that day (if any asset had GPS)
        var dayCell: [String: (cell: GridCell, assetId: String)] = [:]
        // uniqueCells preserves insertion order so geocoding goes chronologically
        var uniqueCells: [GridCell] = []
        var seenCells = Set<GridCell>()

        for dateKey in sortedDays {
            guard let assets = dayMap[dateKey] else { continue }
            for asset in assets {
                guard let loc = asset.location else { continue }
                let cell = GridCell(
                    latBucket: Int((loc.coordinate.latitude  * 2.0).rounded()),
                    lonBucket: Int((loc.coordinate.longitude * 2.0).rounded())
                )
                dayCell[dateKey] = (cell: cell, assetId: asset.localIdentifier)
                if seenCells.insert(cell).inserted { uniqueCells.append(cell) }
                break   // first asset with GPS is enough for cell assignment
            }
        }
        progress(0.20)
        guard !uniqueCells.isEmpty else { return [] }

        // ── Phase 4b: Geocode each unique cell ONCE ──
        // Typical trip has ≤ 20 unique locations regardless of duration,
        // so this replaces hundreds of day-level calls with a handful.
        var cellResult: [GridCell: (city: String, country: String, timeZone: TimeZone?)] = [:]
        let geocoder = CLGeocoder()
        let cellTotal = Double(uniqueCells.count)

        // Build a lookup: cell → a representative asset to geocode
        // (the first day in that cell that has a located asset)
        var cellRepresentative: [GridCell: CLLocation] = [:]
        for dateKey in sortedDays {
            guard
                let info = dayCell[dateKey],
                cellRepresentative[info.cell] == nil,
                let asset = dayMap[dateKey]?.first(where: { $0.location != nil }),
                let loc = asset.location
            else { continue }
            cellRepresentative[info.cell] = loc
        }

        for (ci, cell) in uniqueCells.enumerated() {
            if Task.isCancelled { return [] }
            guard let location = cellRepresentative[cell] else { continue }

            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                let p    = placemarks.first
                let city = p?.locality ?? p?.subLocality ?? p?.administrativeArea ?? ""
                let ctry = p?.country ?? ""
                cellResult[cell] = (city: city, country: ctry, timeZone: p?.timeZone)
                print("[VisitedCities] cell(\(cell.latBucket),\(cell.lonBucket)) → \(city), \(ctry)")
            } catch {
                // Leave cell out of results; don't poison future lookups
                print("[VisitedCities] geocode failed for cell(\(cell.latBucket),\(cell.lonBucket)): \(error)")
            }

            // Rate-limit: CLGeocoder allows ~50 req/min; 0.5 s gap is safe
            if ci < uniqueCells.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            progress(0.20 + (Double(ci + 1) / cellTotal) * 0.70)
        }

        progress(0.92)
        if Task.isCancelled { return [] }

        // ── Phase 4c: Build dayEntries by mapping each day to its cell's result ──
        var dayEntries: [(dateKey: String, city: String, country: String, assetId: String, timeZoneIdentifier: String?, coord: CLLocationCoordinate2D?)] = []
        for dateKey in sortedDays {
            guard
                let info   = dayCell[dateKey],
                let result = cellResult[info.cell],
                !result.city.isEmpty || !result.country.isEmpty
            else { continue }
            let tzId = result.timeZone?.identifier ?? tzByAssetId[info.assetId]?.identifier
            let coord = dayMap[dateKey]?.first(where: { $0.location != nil })?.location?.coordinate
            dayEntries.append((dateKey: dateKey, city: result.city, country: result.country, assetId: info.assetId, timeZoneIdentifier: tzId, coord: coord))
            print("[VisitedCities] day \(dateKey) → \(result.city), \(result.country)")
        }

        // ── Phase 5: Group consecutive same-city days into trip segments ──
        let trips = groupIntoTrips(dayEntries: dayEntries, dayMap: dayMap)
        print("[VisitedCities] \(year): grouped into \(trips.count) trip(s)")
        for t in trips {
            print("[VisitedCities]   \(t.cityName), \(t.countryName)  \(t.startDate) → \(t.endDate)  (\(t.dayCount) days)")
        }
        progress(1.0)
        return trips
    }

    // MARK: - Grouping

    private func groupIntoTrips(
        dayEntries: [(dateKey: String, city: String, country: String, assetId: String, timeZoneIdentifier: String?, coord: CLLocationCoordinate2D?)],
        dayMap: [String: [PHAsset]]
    ) -> [VisitedCityTrip] {
        guard !dayEntries.isEmpty else { return [] }

        let maxGapDays = 3  // bridge gaps up to 3 days in the same city
        // Nearby areas in the same metro region (e.g. Fremont → Menlo Park, ~35 km) should be
        // treated as one trip even when geocoding returns different city names.
        let nearbyThresholdMeters: CLLocationDistance = 55_000 // ~1 grid cell (0.5°)

        var trips: [VisitedCityTrip] = []
        var startKey        = dayEntries[0].dateKey
        var endKey          = dayEntries[0].dateKey
        var curCity         = dayEntries[0].city
        var curCtry         = dayEntries[0].country
        var curCoord        = dayEntries[0].coord
        var coverAsset      = dayEntries[0].assetId
        var curTzId         = dayEntries[0].timeZoneIdentifier
        var dayCount        = 1
        var photoCount      = dayMap[dayEntries[0].dateKey]?.count ?? 0
        var curMaxDayPhotos = photoCount

        func flush() {
            let tz = (curTzId.flatMap { TimeZone(identifier: $0) }) ?? TimeZone.current
            guard
                let start = Self.startOfCalendarDay(dateKey: startKey, timeZone: tz),
                let end = Self.startOfCalendarDay(dateKey: endKey, timeZone: tz)
            else { return }
            trips.append(VisitedCityTrip(
                cityName: curCity, countryName: curCtry,
                startDate: start, endDate: end,
                dayCount: dayCount, photoCount: photoCount,
                coverAssetIdentifier: coverAsset,
                displayTimeZoneIdentifier: curTzId
            ))
        }

        for i in 1..<dayEntries.count {
            let prev = dayEntries[i - 1]
            let cur  = dayEntries[i]

            let gap = Self.gregorianCalendarDaysBetween(prev.dateKey, cur.dateKey) ?? 999

            let sameCityCountry = cur.city == curCity && cur.country == curCtry

            // Same country + within nearby threshold → treat as the same destination even if
            // geocoding returned different city names (e.g. driving around the same metro area).
            let nearbyInSameCountry: Bool = {
                guard !sameCityCountry, cur.country == curCtry,
                      let a = curCoord, let b = cur.coord else { return false }
                let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                return dist <= nearbyThresholdMeters
            }()

            let samePlace = sameCityCountry || nearbyInSameCountry

            if samePlace && gap <= maxGapDays {
                endKey      = cur.dateKey
                dayCount   += 1
                let dayPhotos = dayMap[cur.dateKey]?.count ?? 0
                photoCount += dayPhotos
                // When merging nearby-but-differently-named days, use the city that has the most
                // photos so the trip label reflects where the user actually spent the most time.
                if nearbyInSameCountry && dayPhotos > curMaxDayPhotos {
                    curCity         = cur.city
                    curTzId         = cur.timeZoneIdentifier ?? curTzId
                    curMaxDayPhotos = dayPhotos
                }
            } else {
                flush()
                startKey        = cur.dateKey
                endKey          = cur.dateKey
                curCity         = cur.city
                curCtry         = cur.country
                curCoord        = cur.coord
                coverAsset      = cur.assetId
                curTzId         = cur.timeZoneIdentifier
                dayCount        = 1
                photoCount      = dayMap[cur.dateKey]?.count ?? 0
                curMaxDayPhotos = photoCount
            }
        }
        flush()

        return trips.reversed() // newest first
    }

    /// Pure Gregorian day difference for yyyy-MM-dd keys (labels are timezone-agnostic calendar dates).
    private static func gregorianCalendarDaysBetween(_ a: String, _ b: String) -> Int? {
        let pa = a.split(separator: "-").compactMap { Int($0) }
        let pb = b.split(separator: "-").compactMap { Int($0) }
        guard pa.count == 3, pb.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let d1 = cal.date(from: DateComponents(year: pa[0], month: pa[1], day: pa[2])),
              let d2 = cal.date(from: DateComponents(year: pb[0], month: pb[1], day: pb[2])) else { return nil }
        return cal.dateComponents([.day], from: d1, to: d2).day
    }

    private static func startOfCalendarDay(dateKey: String, timeZone: TimeZone) -> Date? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
