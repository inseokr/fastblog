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

private struct TripPlaceSummary {
    let cityName: String?
    let countryName: String?
    let countryCode: String?

    var title: String {
        if let cityName, !cityName.isEmpty, let countryName, !countryName.isEmpty {
            return "\(cityName), \(countryName)"
        }
        if let cityName, !cityName.isEmpty {
            return cityName
        }
        if let countryName, !countryName.isEmpty {
            return "\(countryName) Trip"
        }
        return "Unknown Trip"
    }
}

/// Full access: scans the last windowDays (90). Limited access: use scanAllForLimitedAccess (no date limit, any selected photo with location).
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

#if DEBUG
    private func debugDateString(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter.string(from: date)
    }

    /// Detailed ordering trace for one day bucket. Helps verify if inversion happens in
    /// photo scan/grouping or later in UI rendering.
    private func debugLogDayOrdering(dayLabel: String, assets: [PHAsset], source: String) {
        guard !assets.isEmpty else { return }
        let byEffective = assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
        let byCreation = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let effectiveIds = byEffective.map(\.localIdentifier)
        let creationIds = byCreation.map(\.localIdentifier)
        let differs = effectiveIds != creationIds
        debugPrint("[DayOrder][\(source)] \(dayLabel) assets=\(assets.count) effectiveDiffersFromCreation=\(differs)")
        for (idx, asset) in byEffective.enumerated() {
            let creation = asset.creationDate
            let modification = asset.modificationDate
            let effective = effectiveDate(for: asset)
            let usedModification = creation.map { !calendar.isDate(effective, inSameDayAs: $0) } ?? false
            let suffix = String(asset.localIdentifier.suffix(8))
            debugPrint(
                "[DayOrder][\(source)] #\(idx + 1) id=\(suffix) " +
                "creation=\(debugDateString(creation)) " +
                "modification=\(debugDateString(modification)) " +
                "effective=\(debugDateString(effective)) " +
                "usesModification=\(usedModification)"
            )
        }
    }

    /// Same format as `APIManager.digitizedTimeString`; defined here so DEBUG scan logs avoid calling `@MainActor` APIManager from a nonisolated context.
    private static func debugFormatDigitizedTime(from date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f.string(from: date)
    }

    private func debugBuildEXIFTimeZoneMap(for assets: [PHAsset]) async -> [String: TimeZone] {
        let cap = 200
        if assets.count > cap {
            debugPrint("[Scan] debug EXIF tz map skipped for \(assets.count) assets (cap=\(cap)); logs use device calendar fallback")
            return [:]
        }
        return await APIManager.buildCaptureTimeZoneMap(for: assets, allowNetwork: false)
    }

    /// Same digitized format as the API (`yyyy:MM:dd HH:mm:ss`) in capture offset TZ when EXIF has it, else `Calendar.current` timezone.
    private func debugDigitizedLogFragment(for asset: PHAsset, tzMap: [String: TimeZone]) -> String {
        let eff = effectiveDate(for: asset)
        let tz = tzMap[asset.localIdentifier] ?? calendar.timeZone
        let s = Self.debugFormatDigitizedTime(from: eff, timeZone: tz)
        let src = tzMap[asset.localIdentifier] != nil ? "exifOffset" : "deviceCalendarFallback"
        return "digitized=\(s) tz=\(src)"
    }

    /// Photos included in the scan after filters, grouped by calendar day (output of `groupAssetsByDay`), before trips are merged.
    /// Grep Xcode console for `[Scan][PerDayPhotos]` to review counts per day, EXIF-style digitized time, and timestamps.
    private func debugLogPhotosPerScanDay(_ dayGroups: [(date: Date, assets: [PHAsset])], context: String) async {
        let flatAssets = dayGroups.flatMap(\.assets)
        let tzMap = await debugBuildEXIFTimeZoneMap(for: flatAssets)
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = calendar.timeZone
        dayFmt.dateFormat = "yyyy-MM-dd"
        let totalAssets = dayGroups.reduce(0) { $0 + $1.assets.count }
        debugPrint("[Scan][PerDayPhotos] context=\(context) calendarDays=\(dayGroups.count) totalAssets=\(totalAssets) (digitized uses EXIF offset when present, else device calendar TZ)")
        let maxPerDay = 120
        for (dayIdx, group) in dayGroups.enumerated() {
            let dayLabel = dayFmt.string(from: group.date)
            let assets = group.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
            debugPrint("[Scan][PerDayPhotos]   day \(dayIdx + 1)/\(dayGroups.count) \(dayLabel) photos=\(assets.count)")
            for (i, asset) in assets.prefix(maxPerDay).enumerated() {
                let suffix = String(asset.localIdentifier.suffix(8))
                let dig = debugDigitizedLogFragment(for: asset, tzMap: tzMap)
                debugPrint(
                    "[Scan][PerDayPhotos]     #\(i + 1) id=\(suffix) \(dig) effective=\(debugDateString(effectiveDate(for: asset))) creation=\(debugDateString(asset.creationDate)) hasGPS=\(asset.location != nil)"
                )
            }
            if assets.count > maxPerDay {
                debugPrint("[Scan][PerDayPhotos]     ... \(assets.count - maxPerDay) more not logged (cap=\(maxPerDay) per day)")
            }
        }
    }

    /// Explains which `PHAsset`s from the fetch never reach trip grouping (occupied dates, no GPS, or too close to home).
    /// Filter the console for `[Scan][Rejections]`.
    private func debugLogScanRejections(
        context: String,
        fetchStart: Date,
        fetchEnd: Date,
        screenshotSkipped: Int,
        beforeOccupied: [PHAsset],
        afterOccupied: [PHAsset],
        remaining: [PHAsset],
        occupiedRanges: [(start: Date, end: Date)],
        ignoreHomeExclusion: Bool,
        home: CLLocation?,
        minMiles: Double
    ) async {
        let tzMap = await debugBuildEXIFTimeZoneMap(for: beforeOccupied)
        let rangeFmt = DateFormatter()
        rangeFmt.locale = Locale(identifier: "en_US_POSIX")
        rangeFmt.timeZone = calendar.timeZone
        rangeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        let remIds = Set(remaining.map(\.localIdentifier))
        let afterOccIds = Set(afterOccupied.map(\.localIdentifier))
        let droppedOccupied = beforeOccupied.filter { !afterOccIds.contains($0.localIdentifier) }
        debugPrint(
            "[Scan][Rejections] context=\(context) fetch=[\(rangeFmt.string(from: fetchStart)), \(rangeFmt.string(from: fetchEnd))) screenshotsSkipped=\(screenshotSkipped) beforeOccupied=\(beforeOccupied.count) afterOccupied=\(afterOccupied.count) remaining=\(remaining.count) occupiedRanges=\(occupiedRanges.count) ignoreHome=\(ignoreHomeExclusion)"
        )
        let maxLines = 80
        func logAsset(_ prefix: String, _ asset: PHAsset, extra: String = "") {
            let suf = String(asset.localIdentifier.suffix(8))
            let dig = debugDigitizedLogFragment(for: asset, tzMap: tzMap)
            debugPrint(
                "[Scan][Rejections]   \(prefix) id=\(suf) \(dig) creation=\(debugDateString(asset.creationDate)) effective=\(debugDateString(effectiveDate(for: asset)))\(extra)"
            )
        }
        for (i, asset) in droppedOccupied.prefix(maxLines).enumerated() {
            logAsset("dropped_occupied[\(i + 1)]", asset)
        }
        if droppedOccupied.count > maxLines {
            debugPrint("[Scan][Rejections]   ... \(droppedOccupied.count - maxLines) more dropped_occupied not logged")
        }
        let notRemaining = afterOccupied.filter { !remIds.contains($0.localIdentifier) }
        for (i, asset) in notRemaining.prefix(maxLines).enumerated() {
            if asset.location == nil {
                logAsset("dropped_noGPS[\(i + 1)]", asset)
            } else if let h = home, let loc = asset.location, !ignoreHomeExclusion {
                let miles = TripPhotoFilter.distanceMiles(from: h, to: loc)
                logAsset("dropped_nearHome[\(i + 1)]", asset, extra: String(format: " distanceFromHomeMi=%.2f (need >= %.1f)", miles, minMiles))
            } else {
                logAsset("dropped_unknown[\(i + 1)]", asset)
            }
        }
        if notRemaining.count > maxLines {
            debugPrint("[Scan][Rejections]   ... \(notRemaining.count - maxLines) more post-occupied drops not logged")
        }
    }
#endif

    /// Call when neighborhood center changes so the next scan is not served from stale cache.
    static func invalidateScanCache() {
        shared.cachedScanKey = nil
        shared.cachedTrips = nil
    }

    /// Fetches photos from the last windowDays, applies local exclusion, groups by day, returns trips and counts.
    /// Excludes photos whose creation date falls within any occupied range (already-created blogs) to reduce memory and avoid re-showing those trips.
    func scanLast90Days(occupiedDateRanges: [(start: Date, end: Date)] = []) async -> ScanResult {
        let now = Date()
        guard let windowStart = calendar.date(byAdding: .day, value: -ScanConfig.windowDays, to: now) else {
            return ScanResult(trips: [], totalFetched: 0, excludedLocalCount: 0, remainingForTripsCount: 0)
        }

        _ = NeighborhoodStore.getNeighborhoodCenter()
        let centerKey = NeighborhoodStore.neighborhoodCenterCacheKey()
        let rangesKey = occupiedDateRanges.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }.joined(separator: ";")
        let cacheKey = "\(windowStart.timeIntervalSince1970)-\(radiusMiles)-\(centerKey)-\(rangesKey)"
        if cacheKey == cachedScanKey, let cached = cachedTrips {
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
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
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
            remaining = allAssets.filter { $0.location != nil }
            #if DEBUG
            if !allAssets.isEmpty {
                debugPrint("[Scan] Neighborhood center not set; including \(remaining.count) assets with location.")
            }
            #endif
        }

        let remainingForTripsCount = remaining.count

        guard !remaining.isEmpty else {
            cachedScanKey = cacheKey
            cachedTrips = []
            return ScanResult(trips: [], totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: 0)
        }

        #if DEBUG
        if let h = home {
            Self.assertTripFilterInvariant(remaining: remaining, home: h, minMiles: minMiles)
        }
        #endif

        // Sort by date ascending; group by calendar day then build DayClusters for Day→Trip grouping
        let sortedByDate = remaining.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        debugPrint("[Scan] Grouped into \(sortedDayGroups.count) day groups")
#if DEBUG
        await debugLogPhotosPerScanDay(sortedDayGroups, context: "scanLast90Days")
#endif
        guard !sortedDayGroups.isEmpty else {
            cachedScanKey = cacheKey
            cachedTrips = []
            return ScanResult(trips: [], totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: remainingForTripsCount)
        }

        debugPrint("[Scan] Building day clusters (geometry only, no per-day geocoding)...")
        let dayClusters = await buildDayClusters(from: sortedDayGroups)
        debugPrint("[Scan] Day clusters built: \(dayClusters.count). Starting trip grouping...")
        let debugLogging = TripClusteringDebug.isEnabled
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
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

        let countryBoundarySplit = await splitTripsByCountryBoundary(groupingResult.trips)
        debugPrint("[Scan] Country-boundary split: \(groupingResult.trips.count) → \(countryBoundarySplit.count) trip(s)")
        let splitTrips = splitTripsByMaxDays(countryBoundarySplit, maxDays: ScanConfig.maxTripDays)
        debugPrint("[Scan] Trip grouping done: \(groupingResult.trips.count) trip(s), \(splitTrips.count) after country-boundary + 7-day split. Building trip models...")
        var trips: [TripDraft] = []
        for (tripIdx, item) in splitTrips.enumerated() {
            let tripDays = item.days
            guard !tripDays.isEmpty else { continue }
            let segment = tripDays.flatMap { $0.assets }
            let firstDate = tripDays[0].dayDate
            let lastDate = tripDays[tripDays.count - 1].dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let placeSummary = await buildTripPlaceSummary(for: tripDays)
            let title = placeSummary.title
            let coverAsset = segment.first
            let coverIdentifier = coverAsset?.localIdentifier

            debugPrint("[Scan] Trip \(tripIdx + 1)/\(splitTrips.count): \"\(title)\" (\(segment.count) photos)")

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let sortedDayAssets = dayCluster.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
#if DEBUG
                debugLogDayOrdering(
                    dayLabel: "trip=\(tripIdx + 1) day=\(dayIndex + 1) dateText=\(dateText)",
                    assets: sortedDayAssets,
                    source: "scanLast90Days"
                )
#endif
                let photos: [MockPhoto] = sortedDayAssets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: effectiveDate(for: asset),
                        locationName: placeSummary.cityName,
                        countryName: placeSummary.countryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: placeSummary.countryCode,
                    countryName: placeSummary.countryName,
                    cityName: placeSummary.cityName
                )
            }

            let daysSeasonText = "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))"
            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: true,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: daysSeasonText,
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            trips.append(draft)
        }

        debugPrint("[Scan] Day→Trip grouping produced \(trips.count) trip(s)")
        cachedScanKey = cacheKey
        cachedTrips = trips
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
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
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

        guard !remaining.isEmpty else { return [] }

        let sortedByDate = remaining.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        guard !sortedDayGroups.isEmpty else { return [] }
#if DEBUG
        await debugLogPhotosPerScanDay(sortedDayGroups, context: "scanFlexibleRange")
#endif

        let dayClusters = await buildDayClusters(from: sortedDayGroups)
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            debugLogging: TripClusteringDebug.isEnabled
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        let countryBoundarySplit = await splitTripsByCountryBoundary(groupingResult.trips)
        let splitTrips = splitTripsByMaxDays(countryBoundarySplit, maxDays: ScanConfig.maxTripDays)
        var results: [TripScanResult] = []
        for item in splitTrips {
            let tripDays = item.days
            guard !tripDays.isEmpty else { continue }
            let assets = tripDays.flatMap { $0.assets }
            let firstDate = tripDays[0].dayDate
            let lastDate = tripDays[tripDays.count - 1].dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let placeSummary = await buildTripPlaceSummary(for: tripDays)
            let title = placeSummary.title
            let coverAsset = assets.first
            let coverIdentifier = coverAsset?.localIdentifier

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let sortedDayAssets = dayCluster.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
#if DEBUG
                debugLogDayOrdering(
                    dayLabel: "trip=\(item.partNumber ?? 1) day=\(dayIndex + 1) dateText=\(dateText)",
                    assets: sortedDayAssets,
                    source: "scanFlexibleRange"
                )
#endif
                let photos: [MockPhoto] = sortedDayAssets.map { asset in
                    let coord = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: effectiveDate(for: asset),
                        locationName: placeSummary.cityName,
                        countryName: placeSummary.countryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: placeSummary.countryCode,
                    countryName: placeSummary.countryName,
                    cityName: placeSummary.cityName
                )
            }

            let daysSeasonText = "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))"
            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: daysSeasonText,
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
    /// applies local exclusion (unless ignoreHomeExclusion is true), groups by day, and returns TripDraft array.
    func scanInDateRange(
        startDate: Date,
        endDate: Date,
        occupiedDateRanges: [(start: Date, end: Date)] = [],
        ignoreHomeExclusion: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async -> [TripDraft] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
#if DEBUG
        var screenshotSkippedInRange = 0
#endif
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
#if DEBUG
                screenshotSkippedInRange += 1
#endif
                return
            }
            allAssets.append(asset)
        }
        let beforeOccupied = allAssets
        allAssets = filterOutAssetsInOccupiedRanges(allAssets, occupiedDateRanges: occupiedDateRanges)
        progress?(0.05)

        let home = ignoreHomeExclusion ? nil : NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
        var remaining: [PHAsset] = []
        if let homeLocation = home {
            for asset in allAssets {
                guard asset.location != nil else { continue }
                if TripPhotoFilter.shouldIncludeInTrips(assetLocation: asset.location, home: homeLocation, minMiles: minMiles) {
                    remaining.append(asset)
                }
            }
        } else {
            // No neighborhood set: include all assets with location so single-photo trips can appear
            remaining = allAssets.filter { $0.location != nil }
        }
        progress?(0.15)

#if DEBUG
        await debugLogScanRejections(
            context: "scanInDateRange",
            fetchStart: startDate,
            fetchEnd: endDate,
            screenshotSkipped: screenshotSkippedInRange,
            beforeOccupied: beforeOccupied,
            afterOccupied: allAssets,
            remaining: remaining,
            occupiedRanges: occupiedDateRanges,
            ignoreHomeExclusion: ignoreHomeExclusion,
            home: home,
            minMiles: minMiles
        )
        if let h = home, !allAssets.isEmpty {
            Self.logTripFilterSample(assets: allAssets, home: h, minMiles: minMiles, sampleSize: min(50, allAssets.count))
        }
#endif

        guard !remaining.isEmpty else { return [] }

        progress?(0.18)
        let sortedByDate = remaining.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        guard !sortedDayGroups.isEmpty else { return [] }
#if DEBUG
        await debugLogPhotosPerScanDay(sortedDayGroups, context: "scanInDateRange")
#endif
        progress?(0.25)

        let dayClusters = await buildDayClusters(from: sortedDayGroups, progress: progress)
        progress?(0.90)
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            debugLogging: TripClusteringDebug.isEnabled
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        let countryBoundarySplit = await splitTripsByCountryBoundary(groupingResult.trips)
        let splitTrips = splitTripsByMaxDays(countryBoundarySplit, maxDays: ScanConfig.maxTripDays)
        var trips: [TripDraft] = []
        for item in splitTrips {
            let tripDays = item.days
            guard !tripDays.isEmpty else { continue }
            let segment = tripDays.flatMap { $0.assets }
            let firstDate = tripDays[0].dayDate
            let lastDate = tripDays[tripDays.count - 1].dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let placeSummary = await buildTripPlaceSummary(for: tripDays)
            let title = placeSummary.title
            let coverAsset = segment.first
            let coverIdentifier = coverAsset?.localIdentifier

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let sortedDayAssets = dayCluster.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
#if DEBUG
                debugLogDayOrdering(
                    dayLabel: "trip=\(item.partNumber ?? 1) day=\(dayIndex + 1) dateText=\(dateText)",
                    assets: sortedDayAssets,
                    source: "scanInDateRange"
                )
#endif
                let photos: [MockPhoto] = sortedDayAssets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: effectiveDate(for: asset),
                        locationName: placeSummary.cityName,
                        countryName: placeSummary.countryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: placeSummary.countryCode,
                    countryName: placeSummary.countryName,
                    cityName: placeSummary.cityName
                )
            }

            let daysSeasonText = "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))"
            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: daysSeasonText,
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            trips.append(draft)
        }
        progress?(1.0)
        return trips
    }

    /// For Limited Photo Access: fetches all photos the app can see (user’s selection), no date window.
    /// Includes any asset with location + timestamp; no 50-mile-from-home filter so every selected photo can form a trip.
    func scanAllForLimitedAccess(occupiedDateRanges: [(start: Date, end: Date)] = [], progress: ((Double) -> Void)? = nil) async -> [TripDraft] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var allAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { return }
            allAssets.append(asset)
        }
        allAssets = filterOutAssetsInOccupiedRanges(allAssets, occupiedDateRanges: occupiedDateRanges)
        progress?(0.05)

        let remaining = allAssets.filter { $0.location != nil }
        progress?(0.15)

        guard !remaining.isEmpty else { return [] }

        progress?(0.18)
        let sortedByDate = remaining.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
        let dayGroups = await groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        guard !sortedDayGroups.isEmpty else { return [] }
#if DEBUG
        await debugLogPhotosPerScanDay(sortedDayGroups, context: "scanAllForLimitedAccess")
#endif
        progress?(0.25)

        let dayClusters = await buildDayClusters(from: sortedDayGroups, progress: progress)
        progress?(0.90)
        let groupingResult = DayToTripGrouper.groupDaysIntoTrips(
            days: dayClusters,
            maxGapDaysToBridge: ScanConfig.maxGapDaysToBridge,
            debugLogging: TripClusteringDebug.isEnabled
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        let countryBoundarySplit = await splitTripsByCountryBoundary(groupingResult.trips)
        let splitTrips = splitTripsByMaxDays(countryBoundarySplit, maxDays: ScanConfig.maxTripDays)
        var trips: [TripDraft] = []
        for item in splitTrips {
            let tripDays = item.days
            guard !tripDays.isEmpty else { continue }
            let segment = tripDays.flatMap { $0.assets }
            let firstDate = tripDays[0].dayDate
            let lastDate = tripDays[tripDays.count - 1].dayDate
            let dateRangeText = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let placeSummary = await buildTripPlaceSummary(for: tripDays)
            let title = placeSummary.title
            let coverAsset = segment.first
            let coverIdentifier = coverAsset?.localIdentifier

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let sortedDayAssets = dayCluster.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
                let photos: [MockPhoto] = sortedDayAssets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: effectiveDate(for: asset),
                        locationName: placeSummary.cityName,
                        countryName: placeSummary.countryName,
                        isSelected: false,
                        localIdentifier: asset.localIdentifier,
                        location: coord
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: dateText,
                    photos: photos,
                    countryCode: placeSummary.countryCode,
                    countryName: placeSummary.countryName,
                    cityName: placeSummary.cityName
                )
            }

            let daysSeasonText = "\(tripDaysModels.count) days • \(monthYearFormatter.string(from: firstDate))"
            let draft = TripDraft(
                title: title,
                dateRangeText: dateRangeText,
                days: tripDaysModels,
                coverImageName: "default",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "From your photo library",
                daysSeasonText: daysSeasonText,
                coverTheme: "default",
                coverAssetIdentifier: coverIdentifier
            )
            trips.append(draft)
        }
        progress?(1.0)
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

    /// Splits trips longer than maxDays into Part 1, Part 2, etc. Each part becomes a separate blog. Returns (days, partNumber, totalParts); partNumber/totalParts are nil for unsplit trips.
    private func splitTripsByMaxDays(_ trips: [[DayCluster]], maxDays: Int) -> [(days: [DayCluster], partNumber: Int?, totalParts: Int?)] {
        var result: [(days: [DayCluster], partNumber: Int?, totalParts: Int?)] = []
        for trip in trips {
            if trip.count <= maxDays {
                result.append((days: trip, partNumber: nil as Int?, totalParts: nil as Int?))
            } else {
                let chunks = stride(from: 0, to: trip.count, by: maxDays).map { start in
                    Array(trip[start..<min(start + maxDays, trip.count)])
                }
                for (zeroBased, chunk) in chunks.enumerated() {
                    result.append((days: chunk, partNumber: zeroBased + 1, totalParts: chunks.count))
                }
            }
        }
        return result
    }

    /// Splits trips at country boundaries when the distance between consecutive days with different countries
    /// exceeds `ScanConfig.flyingDistanceMilesThreshold`. Short cross-border drives (e.g. Paris→Brussels)
    /// are kept in one trip; intercontinental jumps are split into separate blogs.
    ///
    /// Fast-path: if no consecutive day pair exceeds the flying distance threshold, skips geocoding entirely.
    /// This makes single-country trips essentially free (one distance check per adjacent day pair, no network).
    private func splitTripsByCountryBoundary(_ trips: [[DayCluster]]) async -> [[DayCluster]] {
        var result: [[DayCluster]] = []
        for trip in trips {
            guard trip.count >= 2 else {
                result.append(trip)
                continue
            }

            // Fast-path: if no adjacent day pair exceeds the flying threshold, the trip can't need a country
            // split regardless of geocode results — skip geocoding entirely for the common single-country case.
            let anyPairExceedsThreshold = zip(trip, trip.dropFirst()).contains { a, b in
                GeoDistanceHelper.haversineMiles(a.dayCentroid, b.dayCentroid) > ScanConfig.flyingDistanceMilesThreshold
            }
            guard anyPairExceedsThreshold else {
                result.append(trip)
                continue
            }

            // Only trips with at least one large jump get geocoded.
            // Geocode each day's centroid to get its ISO country code.
            var countryCodes: [String] = []
            for day in trip {
                let loc = CLLocation(latitude: day.dayCentroid.latitude, longitude: day.dayCentroid.longitude)
                let place = await GeocodingService.shared.place(for: loc)
                countryCodes.append(place.isoCountryCode)
            }

            // Walk days, splitting where a country change AND flying distance both occur.
            var currentSegment: [DayCluster] = [trip[0]]
            var lastKnownCountry = countryCodes[0]

            for i in 1..<trip.count {
                let prevCountry = lastKnownCountry
                let currCountry = countryCodes[i]

                var shouldSplit = false
                if !prevCountry.isEmpty && !currCountry.isEmpty && prevCountry != currCountry {
                    let dist = GeoDistanceHelper.haversineMiles(trip[i - 1].dayCentroid, trip[i].dayCentroid)
                    if dist > ScanConfig.flyingDistanceMilesThreshold {
                        shouldSplit = true
                        debugPrint(
                            "[TripSplit][Country] \(prevCountry)→\(currCountry) dist=\(String(format: "%.0f", dist))mi " +
                            "— splitting trip at day \(i + 1)"
                        )
                    } else {
                        debugPrint(
                            "[TripSplit][Country] \(prevCountry)→\(currCountry) dist=\(String(format: "%.0f", dist))mi " +
                            "— within drive threshold, keeping in same trip"
                        )
                    }
                }

                if shouldSplit {
                    result.append(currentSegment)
                    currentSegment = [trip[i]]
                } else {
                    currentSegment.append(trip[i])
                }

                if !currCountry.isEmpty {
                    lastKnownCountry = currCountry
                }
            }
            result.append(currentSegment)
        }
        return result
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

    /// Returns the date that best represents when a photo belongs in a trip timeline.
    ///
    /// Trip grouping and recap headings should be based on when the photo was actually
    /// captured, not when it was later edited or re-imported into the library. Using
    /// modificationDate here can shift a real trip from January into February/March and
    /// make the trip summary disagree with EXIF-backed day headings.
    ///
    /// We therefore prefer PHAsset.creationDate and only fall back to modificationDate
    /// when creationDate is missing.
    private func effectiveDate(for asset: PHAsset) -> Date {
        asset.creationDate ?? asset.modificationDate ?? .distantPast
    }

    /// Groups assets by calendar day, but handles late-night events (midnight bridge).
    /// Uses each photo's EXIF capture timezone (OffsetTimeOriginal) so that photos taken
    /// abroad are bucketed by the local date at the destination, not the device's timezone.
    /// If photos are in early morning (e.g. 00:00-04:00) and within 2 hours of previous day's last photo,
    /// they are conceptually part of the "previous day".
    private func groupAssetsByDay(_ assets: [PHAsset]) async -> [(date: Date, assets: [PHAsset])] {
        // Local EXIF only (no iCloud download). Falls back to device timezone when offset is absent or not on disk.
        let tzMap = await APIManager.buildCaptureTimeZoneMap(for: assets, allowNetwork: false)

        // Returns a Gregorian calendar set to the asset's capture timezone.
        func localCalendar(for asset: PHAsset) -> Calendar {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tzMap[asset.localIdentifier] ?? calendar.timeZone
            return cal
        }

        // Initial grouping by local calendar day (using each photo's capture timezone).
        // IMPORTANT: use a Y-M-D key instead of raw Date as dictionary key.
        // If we keyed by raw Date (startOfDay in each asset's timezone), two different
        // timezones can produce different Date values that still format to the same
        // visible date in UI (e.g. "Mar 6"), leading to duplicate "Day N" labels.
        var byDay: [String: (date: Date, assets: [PHAsset])] = [:]
        for asset in assets {
            let effective = effectiveDate(for: asset)
            guard effective != .distantPast else { continue }
            let cal = localCalendar(for: asset)
            let comps = cal.dateComponents([.year, .month, .day], from: effective)
            guard let year = comps.year, let month = comps.month, let day = comps.day else { continue }
            let key = String(format: "%04d-%02d-%02d", year, month, day)
            // Canonical day date in device calendar to keep display labels stable.
            let canonicalDate = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
                ?? cal.startOfDay(for: effective)
            if byDay[key] == nil {
                byDay[key] = (date: canonicalDate, assets: [asset])
            } else {
                byDay[key]?.assets.append(asset)
            }
        }

        // Sort dates to process sequentially
        let sortedDays = byDay.values.sorted { $0.date < $1.date }

        // We will build a new list of groups, potentially merging
        var finalGroups: [(date: Date, assets: [PHAsset])] = []

        for day in sortedDays {
            let date = day.date
            let assetsForDay = day.assets
            // Sort assets for this day
            let sortedAssets = assetsForDay.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }

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

#if DEBUG
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        for (idx, group) in finalGroups.enumerated() {
            debugLogDayOrdering(
                dayLabel: "group=\(idx + 1) day=\(fmt.string(from: group.date))",
                assets: group.assets,
                source: "groupAssetsByDay"
            )
        }
#endif

        return finalGroups
    }

    /// Builds DayCluster for each day group using geometry only.
    /// Reverse-geocoding is deferred until trips are formed so we only call the geocoder
    /// once per trip instead of once per day.
    private func buildDayClusters(from dayGroups: [(date: Date, assets: [PHAsset])], progress: ((Double) -> Void)? = nil) async -> [DayCluster] {
        var clusters: [DayCluster] = []
        let total = dayGroups.count
        debugPrint("[Scan] Building \(total) day clusters (geometry only)...")

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

            // 2. Geographic spread via raw GPS.
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
                debugPrint("[Scan] Day \(idx + 1)/\(total): spread=\(String(format: "%.1f", maxDistanceWithinDayMiles))mi (\(rawCoords.count) photos)")
            }

            clusters.append(DayCluster(
                dayDate: group.date,
                dayCentroid: dayCentroid,
                countryCode: "",
                countryName: "",
                cityName: "",
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

    /// Reverse-geocodes the first location-bearing photo in the trip.
    /// This avoids centroid drift for border crossings or multi-city trips.
    private func buildTripPlaceSummary(for tripDays: [DayCluster]) async -> TripPlaceSummary {
        let representativeAsset = tripDays
            .flatMap { day in
                day.assets.sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
            }
            .first { $0.location != nil }

        guard let coordinate = representativeAsset?.location?.coordinate else {
            return TripPlaceSummary(cityName: nil, countryName: nil, countryCode: nil)
        }
        let place = await GeocodingService.shared.place(
            for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )

        let cityName: String?
        if !place.cityName.isEmpty && place.cityName != "Unknown Place" {
            cityName = place.cityName
        } else if !place.areaName.isEmpty && place.areaName != "Unknown Place" {
            cityName = place.areaName
        } else {
            cityName = nil
        }

        let countryName: String? = {
            guard !place.countryName.isEmpty, place.countryName != "Unknown" else { return nil }
            return place.countryName
        }()
        let countryCode: String? = place.isoCountryCode.isEmpty ? nil : place.isoCountryCode
        return TripPlaceSummary(cityName: cityName, countryName: countryName, countryCode: countryCode)
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
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
        
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

    // MARK: - Bloggo Gallery merge

    /// Merges in-app camera captures (bloggo-capture:) from AppCapturePhotoService into
    /// a TripDraft array produced by a PHAsset scan. Photos whose calendar day matches an
    /// existing TripDay are injected into that day. Remaining captures are clustered by
    /// calendar-day gaps (using maxGapDaysToBridge) and appended as new TripDraft entries.
    ///
    /// - Parameters:
    ///   - trips: The TripDraft array from a prior PHAsset scan.
    ///   - occupiedDateRanges: Date ranges already covered by saved blogs (excludes those captures).
    ///   - scanStart: Earliest timestamp to include (pass .distantPast for limited-access scans).
    ///   - scanEnd: Latest timestamp to include (exclusive).
    func mergingBloggoCaptures(
        into trips: [TripDraft],
        occupiedDateRanges: [(start: Date, end: Date)],
        scanStart: Date,
        scanEnd: Date,
        savedCaptureIdentifiers: Set<String> = []
    ) -> [TripDraft] {
        let captureService = AppCapturePhotoService.shared
        let captureIds = captureService.allCaptureIds()
#if DEBUG
        let dbgFmt = ISO8601DateFormatter()
        debugPrint("[BloGGoMerge] start — captureIds=\(captureIds.count)  existingTrips=\(trips.count)  scanStart=\(dbgFmt.string(from: scanStart))  scanEnd=\(dbgFmt.string(from: scanEnd))")
        if let hc = NeighborhoodStore.getNeighborhoodCenter() {
            debugPrint("[BloGGoMerge] home=(\(String(format: "%.4f", hc.coordinate.latitude)), \(String(format: "%.4f", hc.coordinate.longitude)))  minMiles=\(NeighborhoodStore.effectiveTripMinMilesFromHome)")
        } else {
            debugPrint("[BloGGoMerge] home=nil (no home-distance filter)")
        }
#endif
        guard !captureIds.isEmpty else {
#if DEBUG
            debugPrint("[BloGGoMerge] → no captures on disk, returning unchanged trips")
#endif
            return trips
        }

#if DEBUG
        let home = NeighborhoodStore.getNeighborhoodCenter()
        let minMiles = NeighborhoodStore.effectiveTripMinMilesFromHome
#endif

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium

        // Collect and filter captures.
        // In-app captures are always user-intentional, so we intentionally skip:
        //   - the location-required gate and home-distance filter (used for PHAsset scanning)
        //   - the occupiedDateRanges filter (so a capture taken inside a published blog's
        //     date range still surfaces as its own "Bloggo Captures" card in the carousel,
        //     in addition to whatever the at-capture-time camera flow did with it)
        // Hard exclusions: outside the scan window, or already part of a saved blog.
        var candidates: [(id: UUID, info: AppCapturePhotoService.CaptureInfo)] = []
        for uuid in captureIds {
            guard let info = captureService.metadata(captureId: uuid) else {
#if DEBUG
                debugPrint("[BloGGoMerge] ✗ \(uuid.uuidString.prefix(8)) — metadata load FAILED (corrupt/missing meta.json?)")
#endif
                continue
            }
            let ts = info.timestamp
            guard ts >= scanStart && ts < scanEnd else {
#if DEBUG
                debugPrint("[BloGGoMerge] ✗ \(uuid.uuidString.prefix(8)) — OUT OF SCAN WINDOW  ts=\(dbgFmt.string(from: ts))  scanStart=\(dbgFmt.string(from: scanStart))  scanEnd=\(dbgFmt.string(from: scanEnd))")
#endif
                continue
            }
            let captureIdentifier = AppCapturePhotoService.identifier(for: uuid)
            guard !savedCaptureIdentifiers.contains(captureIdentifier) else {
#if DEBUG
                debugPrint("[BloGGoMerge] ✗ \(uuid.uuidString.prefix(8)) — already in saved blog, skipping")
#endif
                continue
            }
#if DEBUG
            let inOccupied = occupiedDateRanges.contains { ts >= $0.start && ts <= $0.end }
            let occupiedNote = inOccupied ? " (inside published-blog range — kept anyway)" : ""
            if let loc = info.location, let homeLocation = home {
                let clLoc = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                let distMi = TripPhotoFilter.distanceMiles(from: homeLocation, to: clLoc)
                let withinHome = distMi < minMiles
                debugPrint("[BloGGoMerge] ✓ \(uuid.uuidString.prefix(8)) — CANDIDATE  ts=\(dbgFmt.string(from: ts))  loc=(\(String(format: "%.4f", loc.latitude)), \(String(format: "%.4f", loc.longitude)))  distFromHome=\(String(format: "%.1f", distMi))mi\(withinHome ? " (would have been excluded by PHAsset rule — kept for in-app capture)" : "")\(occupiedNote)")
            } else if info.location == nil {
                debugPrint("[BloGGoMerge] ✓ \(uuid.uuidString.prefix(8)) — CANDIDATE (no GPS)  ts=\(dbgFmt.string(from: ts))\(occupiedNote)")
            } else {
                debugPrint("[BloGGoMerge] ✓ \(uuid.uuidString.prefix(8)) — CANDIDATE  ts=\(dbgFmt.string(from: ts))  loc=(\(String(format: "%.4f", info.location!.latitude)), \(String(format: "%.4f", info.location!.longitude)))\(occupiedNote)")
            }
#endif
            candidates.append((id: uuid, info: info))
        }
#if DEBUG
        debugPrint("[BloGGoMerge] candidates after filters: \(candidates.count)/\(captureIds.count)")
#endif
        guard !candidates.isEmpty else {
#if DEBUG
            debugPrint("[BloGGoMerge] → all captures filtered out, returning unchanged trips")
#endif
            return trips
        }

        candidates.sort { $0.info.timestamp < $1.info.timestamp }

        var updatedTrips = trips
        var orphans: [(id: UUID, info: AppCapturePhotoService.CaptureInfo)] = []

        for capture in candidates {
            let captureDay = calendar.startOfDay(for: capture.info.timestamp)
            let identifier = AppCapturePhotoService.identifier(for: capture.id)
            let photo = MockPhoto(
                imageName: "camera.fill",
                timestamp: capture.info.timestamp,
                isSelected: true,
                localIdentifier: identifier,
                location: capture.info.location,
                caption: capture.info.caption
            )
            var injected = false
            outer: for i in 0..<updatedTrips.count {
                for j in 0..<updatedTrips[i].days.count {
                    guard let dayDate = formatter.date(from: updatedTrips[i].days[j].dateText),
                          calendar.isDate(dayDate, inSameDayAs: captureDay) else { continue }
                    if let existingIdx = updatedTrips[i].days[j].photos.firstIndex(where: { $0.localIdentifier == identifier }) {
                        updatedTrips[i].days[j].photos[existingIdx].location = capture.info.location
                        if let caption = capture.info.caption {
                            updatedTrips[i].days[j].photos[existingIdx].caption = caption
                        }
                        injected = true
#if DEBUG
                        debugPrint("[BloGGoMerge] ✓ \(capture.id.uuidString.prefix(8)) — refreshed in trip[\(i)] day[\(j)] \"\(updatedTrips[i].days[j].dateText)\"")
#endif
                        break outer
                    }
                    updatedTrips[i].days[j].photos.append(photo)
                    updatedTrips[i].days[j].photos.sort { $0.timestamp < $1.timestamp }
                    injected = true
#if DEBUG
                    debugPrint("[BloGGoMerge] ✓ \(capture.id.uuidString.prefix(8)) — INJECTED into trip[\(i)] \"\(updatedTrips[i].title)\" day[\(j)] \"\(updatedTrips[i].days[j].dateText)\"")
#endif
                    break outer
                }
            }
            if !injected {
#if DEBUG
                let captureDayText = formatter.string(from: captureDay)
                let tripDayTexts = updatedTrips.flatMap { $0.days.map(\.dateText) }
                debugPrint("[BloGGoMerge] ✗ \(capture.id.uuidString.prefix(8)) — NO MATCHING TRIP DAY → orphan  captureDay=\(captureDayText)  existingDays=[\(tripDayTexts.joined(separator: ", "))]")
#endif
                orphans.append(capture)
            }
        }

        guard !orphans.isEmpty else {
#if DEBUG
            debugPrint("[BloGGoMerge] → no orphans, done. totalTrips=\(updatedTrips.count)")
#endif
            return updatedTrips
        }
#if DEBUG
        debugPrint("[BloGGoMerge] orphans=\(orphans.count) → clustering into new trips")
#endif

        // Cluster orphans into trip-sized groups using maxGapDaysToBridge
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMM yyyy"

        var clusters: [[(id: UUID, info: AppCapturePhotoService.CaptureInfo)]] = []
        var current: [(id: UUID, info: AppCapturePhotoService.CaptureInfo)] = []
        for (idx, capture) in orphans.enumerated() {
            if idx == 0 {
                current.append(capture)
            } else {
                let prevDay = calendar.startOfDay(for: orphans[idx - 1].info.timestamp)
                let thisDay = calendar.startOfDay(for: capture.info.timestamp)
                let gap = calendar.dateComponents([.day], from: prevDay, to: thisDay).day ?? 0
                if gap <= ScanConfig.maxGapDaysToBridge + 1 {
                    current.append(capture)
                } else {
                    clusters.append(current)
                    current = [capture]
                }
            }
        }
        if !current.isEmpty { clusters.append(current) }

        for cluster in clusters {
            let dayGroups = Dictionary(grouping: cluster) {
                calendar.startOfDay(for: $0.info.timestamp)
            }
            let sortedDays = dayGroups.sorted { $0.key < $1.key }
            let tripDays: [TripDay] = sortedDays.enumerated().map { dayIndex, entry in
                let (dayDate, caps) = entry
                let sorted = caps.sorted { $0.info.timestamp < $1.info.timestamp }
                let photos = sorted.map { cap in
                    MockPhoto(
                        imageName: "camera.fill",
                        timestamp: cap.info.timestamp,
                        isSelected: true,
                        localIdentifier: AppCapturePhotoService.identifier(for: cap.id),
                        location: cap.info.location,
                        caption: cap.info.caption
                    )
                }
                return TripDay(
                    dayIndex: dayIndex + 1,
                    dateText: formatter.string(from: dayDate),
                    photos: photos
                )
            }
            guard !tripDays.isEmpty else { continue }
            let firstDate = sortedDays[0].key
            let lastDate = sortedDays[sortedDays.count - 1].key
            let sameDay = calendar.isDate(firstDate, inSameDayAs: lastDate)
            let dateRangeText = sameDay
                ? formatter.string(from: firstDate)
                : "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            let daysSeasonText = "\(tripDays.count) day\(tripDays.count == 1 ? "" : "s") • \(monthYearFormatter.string(from: firstDate))"
            let coverId = tripDays.first?.photos.first?.localIdentifier
            let newTrip = TripDraft(
                title: "Bloggo Captures",
                dateRangeText: dateRangeText,
                days: tripDays,
                coverImageName: "camera.fill",
                isScannedFromDefaultRange: true,
                draftCreatedAgoText: "From Bloggo Gallery",
                daysSeasonText: daysSeasonText,
                coverTheme: "default",
                coverAssetIdentifier: coverId
            )
#if DEBUG
            debugPrint("[BloGGoMerge] + new orphan trip \"\(newTrip.title)\" \(dateRangeText)  days=\(tripDays.count)  photos=\(tripDays.reduce(0) { $0 + $1.photos.count })")
#endif
            updatedTrips.append(newTrip)
        }

#if DEBUG
        debugPrint("[BloGGoMerge] done. totalTrips=\(updatedTrips.count)")
#endif
        updatedTrips.sort { a, b in
            guard let da = a.days.first.flatMap({ formatter.date(from: $0.dateText) }),
                  let db = b.days.first.flatMap({ formatter.date(from: $0.dateText) }) else { return false }
            return da > db
        }
        return updatedTrips
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
