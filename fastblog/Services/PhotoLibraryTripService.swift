//
//  PhotoLibraryTripService.swift
//  Capper
//

import CoreLocation
import Foundation
import Photos

/// Result of a scan with counts for debugging and empty-state handling.
struct ScanResult {
    let trips: [TripDraft]
    let totalFetched: Int
    let excludedLocalCount: Int
    let remainingForTripsCount: Int
}

struct TripScanResult {
    let assets: [PHAsset]
    let draft: TripDraft
}

struct LibrarySummary {
    let totalPhotos: Int
    let prominentYears: [Int]
    let mostActiveMonths: [(year: Int, month: Int, count: Int)] // Top 3
    let recentTripSuggestions: [String] // "April 2024", "Dec 2023"
    let monthCounts: [String: Int] // "2024-05": 12
}

/// Scans the photo library for the last 90 days and builds trip drafts.
/// Only photos with valid location and strictly > minMiles from neighborhood center are included.
/// Photos without location are excluded. When neighborhood is not set, no trips are returned.
final class PhotoLibraryTripService {
    static let shared = PhotoLibraryTripService()

    private let calendar = Calendar.current
    private let radiusMiles: Double

    /// In-memory cache key: windowStart + exclusionMiles + neighborhood center (4 decimals). Nil = no cache.
    private var cachedScanKey: String?
    private var cachedTrips: [TripDraft]?

    private init(radiusMiles: Double = ScanConfig.localExclusionMiles) {
        self.radiusMiles = radiusMiles
    }

    /// Call when neighborhood center changes so the next scan is not served from stale cache.
    static func invalidateScanCache() {
        shared.cachedScanKey = nil
        shared.cachedTrips = nil
    }

    /// Fetches photos from the last windowDays, applies local exclusion, groups by day, returns trips and counts.
    /// Excludes photos whose creation date falls within any occupied range (already-created blogs) to reduce memory and avoid re-showing those trips.
    func scanLast90Days(occupiedDateRanges: [(start: Date, end: Date)] = []) async -> ScanResult {
        AppAnalytics.trackEvent(name: "trip_scan_started")
        let now = Date()
        guard let windowStart = calendar.date(byAdding: .day, value: -ScanConfig.windowDays, to: now) else {
            AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": 0])
            return ScanResult(trips: [], totalFetched: 0, excludedLocalCount: 0, remainingForTripsCount: 0)
        }

        _ = NeighborhoodStore.getNeighborhoodCenter()
        let centerKey = NeighborhoodStore.neighborhoodCenterCacheKey()
        let rangesKey = occupiedDateRanges.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }.joined(separator: ";")
        let cacheKey = "\(windowStart.timeIntervalSince1970)-\(radiusMiles)-\(centerKey)-\(rangesKey)"
        if cacheKey == cachedScanKey, let cached = cachedTrips {
            AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": cached.count, "fromCache": true])
            if cached.count > 0 {
                AppAnalytics.shared.incrementCounter("trips_detected", by: cached.count)
            }
            return ScanResult(
                trips: cached,
                totalFetched: -1,
                excludedLocalCount: -1,
                remainingForTripsCount: cached.isEmpty ? 0 : cached.flatMap { $0.days }.reduce(0) { $0 + $1.photos.count }
            )
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", windowStart as NSDate, now as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { return }
            allAssets.append(asset)
        }
        allAssets = filterOutAssetsInOccupiedRanges(allAssets, occupiedDateRanges: occupiedDateRanges)
        let totalFetched = allAssets.count

        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.localExclusionMiles
        var missingLocationCount = 0
        var excludedWithin50Count = 0
        var includedBeyond50Count = 0
        var remaining: [PHAsset] = []

        if let homeLocation = home {
            for asset in allAssets {
                let hasLocation = asset.location != nil
                if !hasLocation {
                    missingLocationCount += 1
                    continue
                }
                let include = TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: homeLocation, minMiles: minMiles)
                if include {
                    includedBeyond50Count += 1
                    remaining.append(asset)
                } else {
                    excludedWithin50Count += 1
                }
            }
            #if DEBUG
            Self.logTripFilterSample(assets: allAssets, home: homeLocation, minMiles: minMiles, sampleSize: 30)
            debugPrint("[Scan] totalFetched=\(totalFetched) missingLocation=\(missingLocationCount) excludedWithin50mi=\(excludedWithin50Count) includedBeyond50mi=\(includedBeyond50Count)")
            #endif
        } else {
            if !allAssets.isEmpty {
                debugPrint("[Scan] Neighborhood center not set; no trips returned. Set neighborhood in onboarding.")
            }
        }

        let remainingForTripsCount = remaining.count

        guard !remaining.isEmpty else {
            cachedScanKey = cacheKey
            cachedTrips = []
            AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": 0])
            return ScanResult(trips: [], totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: 0)
        }

        #if DEBUG
        if let h = home {
            Self.assertTripFilterInvariant(remaining: remaining, home: h, minMiles: minMiles)
        }
        #endif

        // Sort by date ascending; group by calendar day then build DayClusters for Day→Trip grouping
        let sortedByDate = remaining.sorted { (a, b) in
            (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        debugPrint("[Scan] Grouped into \(sortedDayGroups.count) day groups")
        guard !sortedDayGroups.isEmpty else {
            cachedScanKey = cacheKey
            cachedTrips = []
            return ScanResult(trips: [], totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: remainingForTripsCount)
        }

        debugPrint("[Scan] Building day clusters (centroid geocoding, 1 call/day)...")
        let dayClusters = await buildDayClusters(from: sortedDayGroups)
        await GeocodingService.shared.flushCache()
        debugPrint("[Scan] Day clusters built: \(dayClusters.count). Starting trip grouping...")
        let debugLogging = TripClusteringDebug.isEnabled
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            neighborhoodRadiusMiles: ScanConfig.neighborhoodRadiusMiles,
            countryFallbackMaxMiles: ScanConfig.countryFallbackMaxMiles,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            multiCityDayMaxMiles: ScanConfig.multiCityDayMaxMiles,
            debugLogging: debugLogging
        )
        if debugLogging {
            for (tripIdx, reasons) in groupingResult.mergeReasons.enumerated() {
                for (dayIdx, reason) in reasons.enumerated() {
                    debugPrint("[TripClustering] trip=\(tripIdx) day=\(dayIdx) reason=\(reason.rawValue)")
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        debugPrint("[Scan] Trip grouping done: \(groupingResult.trips.count) trip(s). Building trip models...")
        var trips: [TripDraft] = []
        for (tripIdx, tripDays) in groupingResult.trips.enumerated() {
            guard !tripDays.isEmpty else { continue }
            let segment = tripDays.flatMap { $0.assets }
            let firstDate = tripDays.first!.dayDate
            let lastDate = tripDays.last!.dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let title = defaultTripTitle(for: tripDays)
            let coverAsset = segment.first
            let coverIdentifier = coverAsset?.localIdentifier

            debugPrint("[Scan] Trip \(tripIdx + 1)/\(groupingResult.trips.count): \"\(title)\" (\(segment.count) photos)")

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let photos: [MockPhoto] = dayCluster.assets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    // Use day-level geocoded data from cluster — no per-photo geocoding during scan phase
                    let placeName: String? = (!dayCluster.cityName.isEmpty && dayCluster.cityName != "?") ? dayCluster.cityName : nil
                    let photoCountryName: String? = (!dayCluster.countryName.isEmpty && dayCluster.countryName != "Unknown") ? dayCluster.countryName : nil
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: asset.creationDate ?? Date(),
                        locationName: placeName,
                        countryName: photoCountryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: dayCluster.countryCode,
                    countryName: dayCluster.countryName,
                    cityName: dayCluster.cityName
                )
            }

            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: true,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))",
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            trips.append(draft)
        }

        debugPrint("[Scan] Day→Trip grouping produced \(trips.count) trip(s)")
        cachedScanKey = cacheKey
        cachedTrips = trips

        AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": trips.count])
        if trips.count > 0 {
            AppAnalytics.shared.incrementCounter("trips_detected", by: trips.count)
        }
        return ScanResult(trips: trips, totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: remainingForTripsCount)
    }

    /// Same as scanLast90Days() but returns only trips (for existing callers). Uses windowDays (default 60) and local exclusion. Pass occupiedDateRanges to exclude already-created blog dates.
    func scanLast3Months(occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [TripDraft] {
        let result = await scanLast90Days(occupiedDateRanges: occupiedDateRanges)
        return result.trips
    }

    /// Flexible scan for memories. Returns TripScanResult (assets + draft) for better recall handling.
    func scanFlexibleRange(start: Date, end: Date, occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [TripScanResult] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { return }
            allAssets.append(asset)
        }
        allAssets = filterOutAssetsInOccupiedRanges(allAssets, occupiedDateRanges: occupiedDateRanges)

        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.localExclusionMiles
        var remaining: [PHAsset] = []
        if let homeLocation = home {
            for asset in allAssets {
                guard asset.location != nil else { continue }
                if TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: homeLocation, minMiles: minMiles) {
                    remaining.append(asset)
                }
            }
        } else {
            remaining = allAssets.filter { $0.location != nil }
        }

        guard !remaining.isEmpty else {
            AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": 0])
            return []
        }

        let sortedByDate = remaining.sorted { (a, b) in
            (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        guard !sortedDayGroups.isEmpty else { return [] }

        let dayClusters = await buildDayClusters(from: sortedDayGroups)
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            neighborhoodRadiusMiles: ScanConfig.neighborhoodRadiusMiles,
            countryFallbackMaxMiles: ScanConfig.countryFallbackMaxMiles,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            multiCityDayMaxMiles: ScanConfig.multiCityDayMaxMiles,
            debugLogging: TripClusteringDebug.isEnabled
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        var results: [TripScanResult] = []
        for tripDays in groupingResult.trips {
            guard !tripDays.isEmpty else { continue }
            let assets = tripDays.flatMap { $0.assets }
            let firstDate = tripDays.first!.dayDate
            let lastDate = tripDays.last!.dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let title = defaultTripTitle(for: tripDays)
            let coverAsset = assets.first
            let coverIdentifier = coverAsset?.localIdentifier

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let photos: [MockPhoto] = dayCluster.assets.map { asset in
                    let coord = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    // Use day-level geocoded data from cluster — no per-photo geocoding during scan phase
                    let placeName: String? = (!dayCluster.cityName.isEmpty && dayCluster.cityName != "?") ? dayCluster.cityName : nil
                    let photoCountryName: String? = (!dayCluster.countryName.isEmpty && dayCluster.countryName != "Unknown") ? dayCluster.countryName : nil
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: asset.creationDate ?? Date(),
                        locationName: placeName,
                        countryName: photoCountryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: dayCluster.countryCode,
                    countryName: dayCluster.countryName,
                    cityName: dayCluster.cityName
                )
            }

            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))",
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            results.append(TripScanResult(assets: assets, draft: draft))
        }
        return results
    }

    /// Excludes assets whose creation date falls within any occupied range (start...end inclusive).
    private func filterOutAssetsInOccupiedRanges(_ assets: [PHAsset], occupiedDateRanges: [(start: Date, end: Date)]) -> [PHAsset] {
        guard !occupiedDateRanges.isEmpty else { return assets }
        return assets.filter { asset in
            guard let creation = asset.creationDate else { return true }
            for range in occupiedDateRanges {
                if creation >= range.start && creation <= range.end { return false }
            }
            return true
        }
    }

    /// Scan for trips across a start year+month to end year+month (cross-year capable).
    /// Falls through to the single-year variant when both years match.
    func scanInDateRange(startYear: Int, startMonth: Int, endYear: Int, endMonth: Int, occupiedDateRanges: [(start: Date, end: Date)] = [], progress: ((Double) -> Void)? = nil) async -> [TripDraft] {
        // Build the actual date span
        var startComps = DateComponents(); startComps.year = startYear; startComps.month = startMonth; startComps.day = 1
        guard let startDate = calendar.date(from: startComps).map({ calendar.startOfDay(for: $0) }) else { return [] }
        var endComps = DateComponents(); endComps.year = endYear; endComps.month = endMonth; endComps.day = 1
        guard let endMonthStart = calendar.date(from: endComps),
              let endDate = calendar.date(byAdding: .month, value: 1, to: endMonthStart) else { return [] }

        return await scanInDateRange(startDate: startDate, endDate: endDate, occupiedDateRanges: occupiedDateRanges, progress: progress)
    }

    /// Scan for trips in a custom year/month range. Uses same local exclusion and segmentation as default scan. Does not use the default-scan cache. Excludes photos in occupiedDateRanges (already-created blogs).
    func scanInDateRange(year: Int, startMonth: Int, endMonth: Int, occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [TripDraft] {
        var comps = DateComponents()
        comps.year = year; comps.month = startMonth; comps.day = 1
        guard let start = calendar.date(from: comps).map({ calendar.startOfDay(for: $0) }) else { return [] }
        comps.month = endMonth
        guard let endMonthStart = calendar.date(from: comps),
              let end = calendar.date(byAdding: .month, value: 1, to: endMonthStart) else { return [] }
        return await scanInDateRange(startDate: start, endDate: end, occupiedDateRanges: occupiedDateRanges)
    }

    /// Core date-range scanner used by all public overloads. Fetches photos in [startDate, endDate),
    /// applies local exclusion, groups by day, and returns TripDraft array.
    func scanInDateRange(startDate: Date, endDate: Date, occupiedDateRanges: [(start: Date, end: Date)] = [], progress: ((Double) -> Void)? = nil) async -> [TripDraft] {
        AppAnalytics.trackEvent(name: "trip_scan_started")
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { return }
            allAssets.append(asset)
        }
        allAssets = filterOutAssetsInOccupiedRanges(allAssets, occupiedDateRanges: occupiedDateRanges)
        progress?(0.05)

        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.localExclusionMiles
        var remaining: [PHAsset] = []
        if let homeLocation = home {
            for asset in allAssets {
                guard asset.location != nil else { continue }
                if TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: homeLocation, minMiles: minMiles) {
                    remaining.append(asset)
                }
            }
        }
        progress?(0.15)

        guard !remaining.isEmpty else { return [] }

        let sortedByDate = remaining.sorted { (a, b) in
            (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        guard !sortedDayGroups.isEmpty else {
            AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": 0])
            return []
        }
        progress?(0.25)

        let dayClusters = await buildDayClusters(from: sortedDayGroups, progress: progress)
        progress?(0.90)
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            neighborhoodRadiusMiles: ScanConfig.neighborhoodRadiusMiles,
            countryFallbackMaxMiles: ScanConfig.countryFallbackMaxMiles,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            multiCityDayMaxMiles: ScanConfig.multiCityDayMaxMiles,
            debugLogging: TripClusteringDebug.isEnabled
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        var trips: [TripDraft] = []
        for tripDays in groupingResult.trips {
            guard !tripDays.isEmpty else { continue }
            let segment = tripDays.flatMap { $0.assets }
            let firstDate = tripDays.first!.dayDate
            let lastDate = tripDays.last!.dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let title = defaultTripTitle(for: tripDays)
            let coverAsset = segment.first
            let coverIdentifier = coverAsset?.localIdentifier

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let photos: [MockPhoto] = dayCluster.assets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    let placeName: String? = (!dayCluster.cityName.isEmpty && dayCluster.cityName != "?") ? dayCluster.cityName : nil
                    let photoCountryName: String? = (!dayCluster.countryName.isEmpty && dayCluster.countryName != "Unknown") ? dayCluster.countryName : nil
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: asset.creationDate ?? Date(),
                        locationName: placeName,
                        countryName: photoCountryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: dayCluster.countryCode,
                    countryName: dayCluster.countryName,
                    cityName: dayCluster.cityName
                )
            }

            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))",
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            trips.append(draft)
        }
        progress?(1.0)

        AppAnalytics.trackEvent(name: "trip_scan_completed", properties: ["tripsDetected": trips.count])
        if trips.count > 0 {
            AppAnalytics.shared.incrementCounter("trips_detected", by: trips.count)
        }
        return trips
    }


    /// Splits assets into segments: a gap larger than gapHours between consecutive photos starts a new segment (new trip).
    private func segmentByTemporalGap(_ assets: [PHAsset], gapHours: Int) -> [[PHAsset]] {
        guard !assets.isEmpty else { return [] }
        let gapSeconds = TimeInterval(gapHours) * 3600
        var segments: [[PHAsset]] = []
        var current: [PHAsset] = [assets[0]]
        for i in 1..<assets.count {
            let prev = assets[i - 1]
            let curr = assets[i]
            let t1 = prev.creationDate ?? .distantPast
            let t2 = curr.creationDate ?? .distantPast
            if t2.timeIntervalSince(t1) > gapSeconds {
                if !current.isEmpty {
                    segments.append(current)
                }
                current = [curr]
            } else {
                current.append(curr)
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    /// Cache key for a location (~111m precision) to match GeocodingService and dedupe geocode calls.
    private func locationCacheKey(for location: CLLocation) -> String {
        geocodeCacheKey(for: location)
    }

    /// Resolves place (bestPlaceLabel, city, country, isoCountryCode) for unique coordinates. Uses cached + rate-limited geocoding.
    private func resolveLocationNames(for assets: [PHAsset]) async -> [String: GeocodedPlace] {
        var seen = Set<String>()
        var uniqueLocations: [CLLocation] = []
        for asset in assets {
            guard let loc = asset.location else { continue }
            let key = locationCacheKey(for: loc)
            if seen.contains(key) { continue }
            seen.insert(key)
            uniqueLocations.append(loc)
        }
        var result: [String: GeocodedPlace] = [:]
        for loc in uniqueLocations {
            let place = await GeocodingService.shared.place(for: loc)
            result[locationCacheKey(for: loc)] = place
        }
        return result
    }

    /// Title for a trip draft from its date range (e.g. "Dec 1 – 5, 2025").
    private func tripTitle(from firstDate: Date, to lastDate: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d"
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let sameYear = calendar.isDate(firstDate, equalTo: lastDate, toGranularity: .year)
        let sameMonth = calendar.isDate(firstDate, equalTo: lastDate, toGranularity: .month)
        if sameYear && sameMonth {
            let startDay = calendar.component(.day, from: firstDate)
            let endDay = calendar.component(.day, from: lastDate)
            if startDay == endDay {
                return "\(dayFormatter.string(from: firstDate)), \(yearFormatter.string(from: firstDate))"
            }
            return "\(dayFormatter.string(from: firstDate)) – \(endDay), \(yearFormatter.string(from: firstDate))"
        }
        if sameYear {
            return "\(dayFormatter.string(from: firstDate)) – \(dayFormatter.string(from: lastDate)), \(yearFormatter.string(from: firstDate))"
        }
        return "\(dayFormatter.string(from: firstDate)) – \(dayFormatter.string(from: lastDate))"
    }

    /// Groups assets by calendar day, but handles late-night events (midnight bridge).
    /// Uses each photo's EXIF capture timezone (OffsetTimeOriginal) so that photos taken
    /// abroad are bucketed by the local date at the destination, not the device's timezone.
    /// If photos are in early morning (e.g. 00:00-04:00) and within 2 hours of previous day's last photo,
    /// they are conceptually part of the "previous day".
    private func groupAssetsByDay(_ assets: [PHAsset]) async -> [(date: Date, assets: [PHAsset])] {
        // Fetch EXIF capture timezone for every asset in parallel.
        // Falls back to device timezone when EXIF offset is absent (e.g. screenshots).
        var tzMap: [String: TimeZone] = [:]
        await withTaskGroup(of: (String, TimeZone?).self) { group in
            for asset in assets {
                group.addTask {
                    (asset.localIdentifier, await APIManager.getLocalTimeZone(for: asset))
                }
            }
            for await (id, tz) in group {
                if let tz { tzMap[id] = tz }
            }
        }

        // Returns a Gregorian calendar set to the asset's capture timezone.
        func localCalendar(for asset: PHAsset) -> Calendar {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tzMap[asset.localIdentifier] ?? calendar.timeZone
            return cal
        }

        // Initial grouping by local calendar day (using each photo's capture timezone)
        var byDay: [Date: [PHAsset]] = [:]
        for asset in assets {
            guard let creation = asset.creationDate else { continue }
            let cal = localCalendar(for: asset)
            let startOfDay = cal.startOfDay(for: creation)
            byDay[startOfDay, default: []].append(asset)
        }

        // Sort dates to process sequentially
        let sortedDates = byDay.keys.sorted()

        // We will build a new list of groups, potentially merging
        var finalGroups: [(date: Date, assets: [PHAsset])] = []

        for date in sortedDates {
            guard let assetsForDay = byDay[date] else { continue }
            // Sort assets for this day
            let sortedAssets = assetsForDay.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

            // Check if we can merge "early morning" photos to the PREVIOUS group
            if let lastGroup = finalGroups.last,
               let lastAssetOfPrevDay = lastGroup.assets.last,
               let prevEnd = lastAssetOfPrevDay.creationDate {

                var keptInCurrentDay: [PHAsset] = []

                for asset in sortedAssets {
                    guard let current = asset.creationDate else {
                        keptInCurrentDay.append(asset)
                        continue
                    }

                    // Use the photo's capture timezone for the hour check so that
                    // "before 5 AM" means 5 AM at the destination, not on the device.
                    let cal = localCalendar(for: asset)
                    let hour = cal.component(.hour, from: current)
                    let gap = current.timeIntervalSince(prevEnd)
                    let gapHours = gap / 3600.0

                    if hour < 5 && gapHours <= Double(ScanConfig.midnightBridgeHours) {
                        // Move to previous day
                        finalGroups[finalGroups.count - 1].assets.append(asset)
                    } else {
                        keptInCurrentDay.append(asset)
                    }
                }

                if !keptInCurrentDay.isEmpty {
                    finalGroups.append((date: date, assets: keptInCurrentDay))
                }
            } else {
                finalGroups.append((date: date, assets: sortedAssets))
            }
        }

        return finalGroups
    }

    /// Builds DayCluster for each day group using centroid-only geocoding.
    /// Geocodes only the coarsened day centroid (~1.1km grid) — 1 call per unique area per day
    /// instead of 1 call per unique photo coordinate. Reduces geocoding calls by 10–50×.
    private func buildDayClusters(from dayGroups: [(date: Date, assets: [PHAsset])], progress: ((Double) -> Void)? = nil) async -> [DayCluster] {
        var clusters: [DayCluster] = []
        let total = dayGroups.count
        debugPrint("[Scan] Building \(total) day clusters (centroid-only geocoding)...")

        for (idx, group) in dayGroups.enumerated() {
            let assetsWithLocation = group.assets.filter { $0.location != nil }
            guard !assetsWithLocation.isEmpty else { continue }

            // 1. Compute day centroid from raw GPS — no geocoding needed
            var latSum = 0.0, lonSum = 0.0
            var rawCoords: [CLLocationCoordinate2D] = []
            for asset in assetsWithLocation {
                let coord = asset.location!.coordinate
                latSum += coord.latitude
                lonSum += coord.longitude
                rawCoords.append(coord)
            }
            let n = Double(rawCoords.count)
            let dayCentroid = CLLocationCoordinate2D(latitude: latSum / n, longitude: lonSum / n)

            // 2. Geocode ONLY the coarsened centroid (~1.1km grid).
            // Days in the same city area share one cached result, cutting redundant API calls.
            let coarseLat = (dayCentroid.latitude * 100).rounded() / 100
            let coarseLon = (dayCentroid.longitude * 100).rounded() / 100
            let centroidLocation = CLLocation(latitude: coarseLat, longitude: coarseLon)
            let centroidPlace = await GeocodingService.shared.place(for: centroidLocation)
            let countryCode = centroidPlace.isoCountryCode
            let countryName = centroidPlace.countryName == "Unknown" ? "" : centroidPlace.countryName
            let cityName: String
            if !centroidPlace.cityName.isEmpty && centroidPlace.cityName != "Unknown Place" {
                cityName = centroidPlace.cityName
            } else if !centroidPlace.areaName.isEmpty && centroidPlace.areaName != "Unknown Place" {
                cityName = centroidPlace.areaName
            } else {
                cityName = ""
            }

            // 3. Geographic spread via raw GPS — replaces geocoded city-centroid approach.
            // Sampling keeps the O(n²) max-distance check fast for large photo days.
            let sampleCoords: [CLLocationCoordinate2D]
            if rawCoords.count > 30 {
                let step = rawCoords.count / 30
                sampleCoords = stride(from: 0, to: rawCoords.count, by: step).map { rawCoords[$0] }
            } else {
                sampleCoords = rawCoords
            }
            let maxDistanceWithinDayMiles = GeoDistanceHelper.maxPairwiseDistanceMiles(sampleCoords)

            if (idx + 1) % 5 == 0 || idx == 0 || total <= 5 {
                debugPrint("[Scan] Day \(idx + 1)/\(total): \(cityName.isEmpty ? "?" : cityName), \(countryCode.isEmpty ? "?" : countryCode) spread=\(String(format: "%.1f", maxDistanceWithinDayMiles))mi (\(rawCoords.count) photos)")
            }

            clusters.append(DayCluster(
                dayDate: group.date,
                dayCentroid: dayCentroid,
                countryCode: countryCode,
                countryName: countryName,
                cityName: cityName,
                cityCentroids: [dayCentroid],
                maxDistanceWithinDayMiles: maxDistanceWithinDayMiles,
                assets: group.assets
            ))

            // Report progress: 0.25 → 0.85 proportional to days processed
            if total > 0 {
                let fraction = Double(idx + 1) / Double(total)
                progress?(0.25 + fraction * 0.60)
            }
        }
        return clusters
    }

    /// Default trip title: "{TopCity}, {Country}" or "{TopCity} Area, {Country}" if multiple cities within 100 mi, or "{Country} Trip" if no city.
    private func defaultTripTitle(for tripDays: [DayCluster]) -> String {
        let allCities = tripDays.map(\.cityName).filter { !$0.isEmpty }
        let countryName = tripDays.first?.countryName ?? "Unknown"
        _ = tripDays.first?.countryCode ?? ""
        if allCities.isEmpty {
            return "\(countryName) Trip"
        }
        var cityCounts: [String: Int] = [:]
        for c in allCities { cityCounts[c, default: 0] += 1 }
        let topCity = cityCounts.max(by: { $0.value < $1.value })?.key ?? allCities[0]
        let uniqueCities = Set(allCities)
        if uniqueCities.count > 1 {
            return "\(topCity) Area, \(countryName)"
        }
        return "\(topCity), \(countryName)"
    }

    // MARK: - Library Summary Scan

    /// Quickly scans the library (last 5 years) to find active trip months.
    /// Returns a summary with top active months and suggestions.
    func scanLibrarySummary() async -> LibrarySummary {
        let now = Date()
        let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now) ?? .distantPast
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", fiveYearsAgo as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { return }
            allAssets.append(asset)
        }
        
        // Filter for "Trip" photos (non-local)
        // We do a lighter pass here: just check logic, maybe skip complex clustering
        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.localExclusionMiles
        
        var tripAssets: [PHAsset] = []
        if let homeLocation = home {
            for asset in allAssets {
                guard asset.location != nil else { continue }
                if TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: homeLocation, minMiles: minMiles) {
                    tripAssets.append(asset)
                }
            }
        } else {
            // If no home set, maybe just take everything? or empty?
            // "Scan" implies looking for trips. If no home, everything is a trip?
            // Let's assume everything with location is a trip candidate if no home set (unlikely in app flow but possible)
            tripAssets = allAssets.filter { $0.location != nil }
        }
        
        // Group by Year-Month
        var monthCounts: [String: Int] = [:] // "2024-05": 45
        var yearCounts: [Int: Int] = [:]
        
        for asset in tripAssets {
            guard let date = asset.creationDate else { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = String(format: "%04d-%02d", year, month)
            
            monthCounts[key, default: 0] += 1
            yearCounts[year, default: 0] += 1
        }
        
        // Top 3 Active Months
        let sortedMonths = monthCounts.sorted { $0.value > $1.value }.prefix(3)
        var mostActiveMonths: [(year: Int, month: Int, count: Int)] = []
        for (key, count) in sortedMonths {
            let parts = key.split(separator: "-")
            if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) {
                mostActiveMonths.append((year: y, month: m, count: count))
            }
        }
        
        // Prominent Years (more than 20 photos)
        let prominentYears = yearCounts.filter { $0.value > 20 }.keys.sorted(by: >)
        
        // Recent Trip Suggestions (Recent 2 months with > 10 photos, not current month)
        // Sort keys descending (time)
        let chronologicallySortedMonths = monthCounts.keys.sorted(by: >)
        var count = 0
        var recentSuggestions: [String] = []
        let currentMonthKey = String(format: "%04d-%02d", calendar.component(.year, from: now), calendar.component(.month, from: now))
        
        let monthNameFormatter = DateFormatter()
        monthNameFormatter.dateFormat = "MMMM yyyy"
        
        for key in chronologicallySortedMonths {
            if key == currentMonthKey { continue } // Skip current in-progress month
            if let c = monthCounts[key], c > 10 {
                let parts = key.split(separator: "-")
                if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) {
                    var comps = DateComponents()
                    comps.year = y
                    comps.month = m
                    if let date = calendar.date(from: comps) {
                        recentSuggestions.append(monthNameFormatter.string(from: date))
                        count += 1
                    }
                }
            }
            if count >= 2 { break }
        }
        
        return LibrarySummary(
            totalPhotos: tripAssets.count,
            prominentYears: prominentYears,
            mostActiveMonths: mostActiveMonths,
            recentTripSuggestions: recentSuggestions,
            monthCounts: monthCounts
        )
    }

    // MARK: - Trip filter debug (DEBUG only)


    #if DEBUG
    private static func logTripFilterSample(assets: [PHAsset], home: CLLocation, minMiles: Double, sampleSize: Int) {
        let lat = (home.coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (home.coordinate.longitude * 10_000).rounded() / 10_000
        debugPrint("[TripFilter] home=(\(lat), \(lon)) radiusThresholdMiles=\(minMiles)")
        let sample = Array(assets.prefix(sampleSize))
        for asset in sample {
            let suffix = String(asset.localIdentifier.suffix(6))
            let hasLocation = asset.location != nil
            var coordStr = "nil"
            var distanceStr = "nil"
            var reason: String
            if let loc = asset.location {
                let la = (loc.coordinate.latitude * 10_000).rounded() / 10_000
                let lo = (loc.coordinate.longitude * 10_000).rounded() / 10_000
                coordStr = "(\(la), \(lo))"
                let miles = TripPhotoFilter.distanceMiles(from: home, to: loc)
                let milesRounded = (miles * 100).rounded() / 100
                distanceStr = "\(milesRounded)"
                reason = miles >= minMiles ? "included" : "excluded"
            } else {
                reason = "excluded_no_location"
            }
            debugPrint("[TripFilter] idSuffix=\(suffix) hasLocation=\(hasLocation) coord=\(coordStr) distanceMiles=\(distanceStr) \(reason)")
        }
    }

    private static func assertTripFilterInvariant(remaining: [PHAsset], home: CLLocation, minMiles: Double) {
        for asset in remaining {
            assert(TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: home, minMiles: minMiles),
                   "Trip invariant: asset \(String(asset.localIdentifier.suffix(6))) must be >= \(minMiles) mi from home")
        }
    }
    #endif
}
