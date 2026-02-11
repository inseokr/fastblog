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

/// Scans the photo library for the last N days (ScanConfig.windowDays, default 60) and builds trip drafts.
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
        let dayGroups = groupAssetsByDay(sortedByDate)
        let sortedDayGroups = dayGroups.sorted { $0.date < $1.date }
        debugPrint("[Scan] Grouped into \(sortedDayGroups.count) day groups")
        guard !sortedDayGroups.isEmpty else {
            cachedScanKey = cacheKey
            cachedTrips = []
            return ScanResult(trips: [], totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: remainingForTripsCount)
        }

        debugPrint("[Scan] Building day clusters (geocoding unique locations)...")
        let dayClusters = await buildDayClusters(from: sortedDayGroups)
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

        debugPrint("[Scan] Trip grouping done: \(groupingResult.trips.count) trip(s). Resolving photo-level locations...")
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
            let locationNames = await resolveLocationNames(for: segment)

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let photos: [MockPhoto] = dayCluster.assets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    var placeName: String?
                    var countryName: String?
                    if let loc = asset.location {
                        let key = locationCacheKey(for: loc)
                        if let place = locationNames[key] {
                            placeName = place.bestPlaceLabel.isEmpty || place.bestPlaceLabel == "Unknown Place" ? nil : place.bestPlaceLabel
                            if placeName == nil, !place.cityName.isEmpty && place.cityName != "Unknown Place" { placeName = place.cityName }
                            if placeName == nil, !place.areaName.isEmpty && place.areaName != "Unknown Place" { placeName = place.areaName }
                            countryName = (place.countryName.isEmpty || place.countryName == "Unknown") ? nil : place.countryName
                        }
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: asset.creationDate ?? Date(),
                        locationName: placeName,
                        countryName: countryName,
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
        return ScanResult(trips: trips, totalFetched: totalFetched, excludedLocalCount: excludedWithin50Count + missingLocationCount, remainingForTripsCount: remainingForTripsCount)
    }

    /// Same as scanLast90Days() but returns only trips (for existing callers). Uses windowDays (default 60) and local exclusion. Pass occupiedDateRanges to exclude already-created blog dates.
    func scanLast3Months(occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [TripDraft] {
        let result = await scanLast90Days(occupiedDateRanges: occupiedDateRanges)
        return result.trips
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

    /// Scan for trips in a custom year/month range. Uses same local exclusion and segmentation as default scan. Does not use the default-scan cache. Excludes photos in occupiedDateRanges (already-created blogs).
    func scanInDateRange(year: Int, startMonth: Int, endMonth: Int, occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [TripDraft] {
        let startDate: Date
        let endDate: Date
        var comps = DateComponents()
        comps.year = year
        comps.month = startMonth
        comps.day = 1
        guard let start = calendar.date(from: comps) else { return [] }
        startDate = calendar.startOfDay(for: start)
        comps.month = endMonth
        guard let endMonthStart = calendar.date(from: comps) else { return [] }
        guard let end = calendar.date(byAdding: .month, value: 1, to: endMonthStart) else { return [] }
        endDate = end

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

        guard !remaining.isEmpty else { return [] }

        let sortedByDate = remaining.sorted { (a, b) in
            (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
        let dayGroups = groupAssetsByDay(sortedByDate)
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

            let locationNames = await resolveLocationNames(for: segment)

            let tripDaysModels: [TripDay] = tripDays.enumerated().map { dayIndex, dayCluster in
                let dateText = formatter.string(from: dayCluster.dayDate)
                let photos: [MockPhoto] = dayCluster.assets.map { asset in
                    let coord: PhotoCoordinate? = asset.location.map { loc in
                        PhotoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                    }
                    var placeName: String?
                    var countryName: String?
                    if let loc = asset.location {
                        let key = locationCacheKey(for: loc)
                        if let place = locationNames[key] {
                            placeName = place.bestPlaceLabel.isEmpty || place.bestPlaceLabel == "Unknown Place" ? nil : place.bestPlaceLabel
                            if placeName == nil, !place.cityName.isEmpty && place.cityName != "Unknown Place" { placeName = place.cityName }
                            if placeName == nil, !place.areaName.isEmpty && place.areaName != "Unknown Place" { placeName = place.areaName }
                            countryName = (place.countryName.isEmpty || place.countryName == "Unknown") ? nil : place.countryName
                        }
                    }
                    return MockPhoto(
                        imageName: "photo",
                        timestamp: asset.creationDate ?? Date(),
                        locationName: placeName,
                        countryName: countryName,
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
        return trips
    }

    /// Fetches unique city names from photos in the given year/month range (for "Cities Visited" preview). Applies same location and exclusion rules. Excludes photos in occupiedDateRanges.
    func fetchCityNamesInRange(year: Int, startMonth: Int, endMonth: Int, occupiedDateRanges: [(start: Date, end: Date)] = []) async -> [String] {
        var comps = DateComponents()
        comps.year = year
        comps.month = startMonth
        comps.day = 1
        guard let start = calendar.date(from: comps) else { return [] }
        let startDate = calendar.startOfDay(for: start)
        comps.month = endMonth
        guard let endMonthStart = calendar.date(from: comps) else { return [] }
        guard let endDate = calendar.date(byAdding: .month, value: 1, to: endMonthStart) else { return [] }

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

        let locationNames = await resolveLocationNames(for: remaining)
        var citySet = Set<String>()
        for (_, place) in locationNames {
            let name = (!place.cityName.isEmpty && place.cityName != "Unknown Place") ? place.cityName : place.areaName
            if !name.isEmpty && name != "Unknown Place" {
                citySet.insert(name)
            }
        }
        return citySet.sorted()
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
    /// If photos are in early morning (e.g. 00:00-04:00) and within 2 hours of previous day's last photo,
    /// they are conceptually part of the "previous day".
    private func groupAssetsByDay(_ assets: [PHAsset]) -> [(date: Date, assets: [PHAsset])] {
        // Initial grouping by standard calendar day
        var byDay: [Date: [PHAsset]] = [:]
        for asset in assets {
            guard let creation = asset.creationDate else { continue }
            let startOfDay = calendar.startOfDay(for: creation)
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
                    
                    // Check if early morning (e.g. < 4 AM relative to day start)
                    // Config: midnightBridgeHours = 2. So we check up to 2AM? 
                    // PRD says: "Photos crossing midnight may stay in the same Day if Time gap <= 2 hours".
                    // The "2 hours" is gap to previous photo. 
                    // Usually "late night" implies e.g. up to 4AM or 5AM. 
                    // Let's check hour component.
                    let hour = calendar.component(.hour, from: current)
                    
                    // Assuming early morning if hour < 5 checks. 
                    // But critical check is GAP to prevEnd.
                    let gap = current.timeIntervalSince(prevEnd)
                    let gapHours = gap / 3600.0
                    
                    if hour < 5 && gapHours <= Double(ScanConfig.midnightBridgeHours) {
                        // Move to previous day
                        finalGroups[finalGroups.count - 1].assets.append(asset)
                        // Update prevEnd for chain logic? 
                        // If we move it, it becomes the new "last asset". 
                        // But wait, we need to compare next photo to THIS one.
                        // Yes, effectively we are appending to the last group.
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

    /// Builds DayCluster for each day group: centroid, country/city from geocoding, city centroids, maxDistanceWithinDayMiles.
    private func buildDayClusters(from dayGroups: [(date: Date, assets: [PHAsset])]) async -> [DayCluster] {
        var clusters: [DayCluster] = []
        let total = dayGroups.count
        for (idx, group) in dayGroups.enumerated() {
            let assetsWithLocation = group.assets.filter { $0.location != nil }
            guard !assetsWithLocation.isEmpty else { continue }

            if (idx + 1) % 5 == 0 || idx == 0 {
                debugPrint("[Scan] buildDayClusters: day \(idx + 1)/\(total) (\(assetsWithLocation.count) photos with location)")
            }
            let locationNames = await resolveLocationNames(for: group.assets)
            var latSum = 0.0, lonSum = 0.0
            var countryCodeCounts: [String: Int] = [:]
            var countryCodeToName: [String: String] = [:]
            var cityToCoords: [String: [(lat: Double, lon: Double)]] = [:]

            for asset in assetsWithLocation {
                guard let loc = asset.location else { continue }
                let key = locationCacheKey(for: loc)
                let place = locationNames[key]
                let code = place?.isoCountryCode.isEmpty == false ? place!.isoCountryCode : (place?.countryName ?? "?")
                countryCodeCounts[code, default: 0] += 1
                if let name = place?.countryName { countryCodeToName[code] = name }

                let city = (place?.cityName.isEmpty == false) ? place!.cityName : (place?.areaName ?? "?")
                let lat = loc.coordinate.latitude
                let lon = loc.coordinate.longitude
                cityToCoords[city, default: []].append((lat, lon))
                latSum += lat
                lonSum += lon
            }

            let n = Double(assetsWithLocation.count)
            let dayCentroid = CLLocationCoordinate2D(latitude: latSum / n, longitude: lonSum / n)
            let dominantCode = countryCodeCounts.max(by: { $0.value < $1.value })?.key ?? ""
            let countryCode = dominantCode
            let countryName = countryCodeToName[dominantCode] ?? "Unknown"
            let dominantCity = cityToCoords.max(by: { $0.value.count < $1.value.count })
            let cityName = dominantCity?.key ?? ""

            var cityCentroids: [CLLocationCoordinate2D] = []
            for (_, coords) in cityToCoords {
                let clat = coords.map(\.lat).reduce(0, +) / Double(coords.count)
                let clon = coords.map(\.lon).reduce(0, +) / Double(coords.count)
                cityCentroids.append(CLLocationCoordinate2D(latitude: clat, longitude: clon))
            }
            let maxDistanceWithinDayMiles = GeoDistanceHelper.maxPairwiseDistanceMiles(cityCentroids)

            clusters.append(DayCluster(
                dayDate: group.date,
                dayCentroid: dayCentroid,
                countryCode: countryCode,
                countryName: countryName,
                cityName: cityName,
                cityCentroids: cityCentroids,
                maxDistanceWithinDayMiles: maxDistanceWithinDayMiles,
                assets: group.assets
            ))
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
