//
//  CreatedRecapBlogStore.swift
//  fastblog
//

import Combine
import CoreLocation
import Foundation
import Photos
import SwiftUI

// MARK: - Blog Ownership & Sync Enums

/// Whether the blog belongs to an anonymous (logged-out) session or a signed-in account.
enum OwnerScope: String, Codable, Sendable {
    case anonymous
    case account
}
struct VisitedPlaceSummary: Identifiable, Equatable {
    struct RelatedBlogRef: Identifiable, Equatable {
        let blogId: UUID
        let blogTitle: String
        let blogDate: Date
        var id: UUID { blogId }
    }

    let placeId: String
    let placeName: String
    let city: String
    let country: String
    let categoryRawValue: String?
    let latestVisitDate: Date
    let year: Int
    let photos: [RecapPhoto]
    let placeCaption: String?
    let photoCaptions: [String]
    let relatedBlogs: [RelatedBlogRef]

    var id: String { placeId }

    var displayName: String {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "unknown" || trimmed == "Unknown Place" {
            return "Unknown Place"
        }
        return trimmed
    }

    var cityDisplay: String? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var heroPhoto: RecapPhoto? {
        photos.max { lhs, rhs in
            let l = lhs.qualityScore?.totalScore ?? -1
            let r = rhs.qualityScore?.totalScore ?? -1
            if l != r { return l < r }
            return lhs.timestamp < rhs.timestamp
        }
    }

    var thumbnailStrip: [RecapPhoto] {
        Array(photos.sorted(by: { $0.timestamp > $1.timestamp }).prefix(3))
    }

    var captionPreview: String? {
        if let c = placeCaption, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return c
        }
        return photoCaptions.first
    }
}

/// The cloud lifecycle state of a local blog.
enum CloudState: String, Codable, Sendable {
    /// Never uploaded; exists on-device only.
    case localOnly
    /// Uploaded and currently active (visible to public if published).
    case uploadedActive
    /// Uploaded but archived (hidden from public).
    case uploadedArchived
}

/// Sync reconciliation status for merge operations.
enum SyncStatus: String, Codable, Sendable {
    case clean
    case localOnly   // reassigned anon draft; needs explicit upload first
    case needsUpload
    case needsSync   // remote is newer; pull would update local
    case conflict    // diverged on both sides
}

/// A recap blog that was created from a draft trip. Stored so we can hide the draft from Trips and show it in Landing Recents.
struct CreatedRecapBlog: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let sourceTripId: UUID
    var title: String
    let createdAt: Date
    var coverImageName: String
    var coverAssetIdentifier: String?
    /// Number of places visited (stops).
    var totalPlaceVisitCount: Int
    /// Duration of the trip in days.
    var tripDurationDays: Int
    /// Number of selected photos
    var selectedPhotoCount: Int
    /// Primary country name
    var countryName: String?
    /// Display text for date range
    var tripDateRangeText: String?
    /// Last edit timestamp
    var lastEditedAt: Date?
    /// Start date of the trip
    var tripStartDate: Date?
    /// End date of the trip
    var tripEndDate: Date?
    /// First available note or caption
    var caption: String?
    /// Server-assigned blog key from createBlogWithPlaces. Used for share links.
    var blogKey: Int?

    // MARK: - Ownership & Sync

    /// Whether this blog was created while logged out (anonymous) or by a signed-in account.
    var ownerScope: OwnerScope
    /// The userId that owns this blog. Nil when ownerScope == .anonymous.
    var ownerUserId: String?
    /// Server-assigned id once the blog has been uploaded. Nil until first upload.
    var cloudId: String?
    /// Cloud lifecycle state.
    var cloudState: CloudState
    /// Sync reconciliation status.
    var syncStatus: SyncStatus
    /// Timestamp of the last autosave.
    var lastAutosaveAt: Date?

    init(
        id: UUID = UUID(),
        sourceTripId: UUID,
        title: String,
        createdAt: Date,
        coverImageName: String,
        coverAssetIdentifier: String? = nil,
        selectedPhotoCount: Int,
        countryName: String? = nil,
        tripDateRangeText: String? = nil,
        lastEditedAt: Date? = nil,
        tripStartDate: Date? = nil,
        tripEndDate: Date? = nil,
        totalPlaceVisitCount: Int = 0,
        tripDurationDays: Int = 1,
        caption: String? = nil,
        blogKey: Int? = nil,
        ownerScope: OwnerScope = .anonymous,
        ownerUserId: String? = nil,
        cloudId: String? = nil,
        cloudState: CloudState = .localOnly,
        syncStatus: SyncStatus = .clean,
        lastAutosaveAt: Date? = nil
    ) {
        self.id = id
        self.sourceTripId = sourceTripId
        self.title = title
        self.createdAt = createdAt
        self.coverImageName = coverImageName
        self.coverAssetIdentifier = coverAssetIdentifier
        self.selectedPhotoCount = selectedPhotoCount
        self.countryName = countryName
        self.tripDateRangeText = tripDateRangeText
        self.lastEditedAt = lastEditedAt
        self.tripStartDate = tripStartDate
        self.tripEndDate = tripEndDate
        self.totalPlaceVisitCount = totalPlaceVisitCount
        self.tripDurationDays = tripDurationDays
        self.caption = caption
        self.blogKey = blogKey
        self.ownerScope = ownerScope
        self.ownerUserId = ownerUserId
        self.cloudId = cloudId
        self.cloudState = cloudState
        self.syncStatus = syncStatus
        self.lastAutosaveAt = lastAutosaveAt
    }

    // MARK: - Codable with safe defaults for v1 → v2 migration

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self, forKey: .id)
        sourceTripId         = try c.decode(UUID.self, forKey: .sourceTripId)
        title                = try c.decode(String.self, forKey: .title)
        createdAt            = try c.decode(Date.self, forKey: .createdAt)
        coverImageName       = try c.decode(String.self, forKey: .coverImageName)
        coverAssetIdentifier = try c.decodeIfPresent(String.self, forKey: .coverAssetIdentifier)
        totalPlaceVisitCount = try c.decodeIfPresent(Int.self, forKey: .totalPlaceVisitCount) ?? 0
        tripDurationDays     = try c.decodeIfPresent(Int.self, forKey: .tripDurationDays) ?? 1
        selectedPhotoCount   = try c.decodeIfPresent(Int.self, forKey: .selectedPhotoCount) ?? 0
        countryName          = try c.decodeIfPresent(String.self, forKey: .countryName)
        tripDateRangeText    = try c.decodeIfPresent(String.self, forKey: .tripDateRangeText)
        lastEditedAt         = try c.decodeIfPresent(Date.self, forKey: .lastEditedAt)
        tripStartDate        = try c.decodeIfPresent(Date.self, forKey: .tripStartDate)
        tripEndDate          = try c.decodeIfPresent(Date.self, forKey: .tripEndDate)
        caption              = try c.decodeIfPresent(String.self, forKey: .caption)
        blogKey              = try c.decodeIfPresent(Int.self, forKey: .blogKey)
        // v2 fields – default gracefully for v1 data on disk
        ownerScope           = try c.decodeIfPresent(OwnerScope.self, forKey: .ownerScope) ?? .anonymous
        ownerUserId          = try c.decodeIfPresent(String.self, forKey: .ownerUserId)
        cloudId              = try c.decodeIfPresent(String.self, forKey: .cloudId)
        cloudState           = try c.decodeIfPresent(CloudState.self, forKey: .cloudState) ?? .localOnly
        syncStatus           = try c.decodeIfPresent(SyncStatus.self, forKey: .syncStatus) ?? .clean
        lastAutosaveAt       = try c.decodeIfPresent(Date.self, forKey: .lastAutosaveAt)
    }
}

// MARK: - Store

@MainActor
final class CreatedRecapBlogStore: ObservableObject {
    static let shared = CreatedRecapBlogStore()

    @Published private(set) var recents: [CreatedRecapBlog] = []
    /// Always false — data loads synchronously in init(). Exposed so TripsViewModel can observe it.
    @Published private(set) var isLoading = false
    /// True while a cloud sync is in progress. Views can observe this to show a loading indicator.
    @Published private(set) var isSyncing = false
    /// When true, landing shows "Recap Blog has been created!" banner; clear after 5-7 sec.
    @Published var showRecapCreatedBanner = false
    /// Set to true when a blog is created. Consumed by the view (TripsView) to trigger the banner at the appropriate time.
    @Published var pendingRecapCreated = false
    /// Set to true when a draft is saved on back navigation. Consumed by TripsView to show a toast.
    @Published var showDraftSavedToast = false
    /// Trip ID that was just discarded (user exited without saving). Consumed by TripsView to scroll the carousel back to it.
    @Published var lastDiscardedTripId: UUID?
    /// Date ranges of active drafts (from TripsViewModel) to exclude from scans. Written by TripsViewModel.updateOccupiedRanges().
    var draftOccupiedRanges: [(start: Date, end: Date)] = []
    /// When true, TripsViewModel clears trips and re-runs default scan (e.g. after archive rules change).
    @Published var needsRescan: Bool = false
    /// Day index currently being processed (geocoding + scoring) for each blog; used by RecapBlogPageView for "processing" pill state.
    @Published private(set) var processingDayIndexByBlogId: [UUID: Int] = [:]

    /// Undo info for the last split operation (not persisted).
    struct SplitUndoInfo {
        let keepId: UUID
        let newId: UUID
        let originalTitle: String
    }
    @Published var lastSplitUndoInfo: SplitUndoInfo?
    private var tripDraftsBySourceId: [UUID: TripDraft] = [:]
    /// Persisted editable blog details; Save in RecapBlogPageView writes here.
    private var blogDetailsBySourceId: [UUID: RecapBlogDetail] = [:]
    private let clusteringService = PlaceStopClusteringService()

    // MARK: - Persistence

    private static let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("CreatedBlogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dirForResource = dir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirForResource.setResourceValues(resourceValues)
        return dir
    }()

    private static let recentsURL = storageDirectory.appendingPathComponent("recents.json")
    private static let tripDraftsURL = storageDirectory.appendingPathComponent("tripDrafts.json")
    private static let blogDetailsURL = storageDirectory.appendingPathComponent("blogDetails.json")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: Self.recentsURL),
           let decoded = try? Self.decoder.decode([CreatedRecapBlog].self, from: data) {
            recents = decoded
        }
        if let data = try? Data(contentsOf: Self.tripDraftsURL),
           let decoded = try? Self.decoder.decode([UUID: TripDraft].self, from: data) {
            tripDraftsBySourceId = decoded
        }
        if let data = try? Data(contentsOf: Self.blogDetailsURL),
           let decoded = try? Self.decoder.decode([UUID: RecapBlogDetail].self, from: data) {
            blogDetailsBySourceId = decoded
        }
        
        // 🔄 Migrate Legacy Blogs: Any blog that has a blogKey but was stuck in .localOnly
        var migrated = false
        for i in recents.indices {
            if recents[i].blogKey != nil, recents[i].cloudState == .localOnly {
                recents[i].cloudState = .uploadedActive
                migrated = true
            }
        }
        if migrated {
            persistRecents()
            enforceArchiveRules()
        }
    }

    private func persistRecents() {
        if let data = try? Self.encoder.encode(recents) {
            try? data.write(to: Self.recentsURL, options: .atomic)
        }
    }

    private func persistTripDrafts() {
        if let data = try? Self.encoder.encode(tripDraftsBySourceId) {
            try? data.write(to: Self.tripDraftsURL, options: .atomic)
        }
    }

    private func persistBlogDetails() {
        if let data = try? Self.encoder.encode(blogDetailsBySourceId) {
            try? data.write(to: Self.blogDetailsURL, options: .atomic)
        }
    }

    // MARK: - Auth-Aware Migration

    /// Claims any blogs that are still `.anonymous` without an ownerUserId and assigns them to
    /// the currently signed-in user. Safe to call on every launch; it's a no-op once all blogs have been properly assigned.
    private func migrateOwnerScopeIfNeeded() {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        var didChange = false
        for idx in recents.indices
        where recents[idx].ownerScope == .anonymous && recents[idx].ownerUserId == nil {
            recents[idx].ownerScope = .account
            recents[idx].ownerUserId = userId
            didChange = true
        }
        if didChange { persistRecents() }
    }

    // MARK: - Auth-Aware Filtering

    /// Blogs visible for the given auth state.
    func visibleBlogs(for authState: AuthState) -> [CreatedRecapBlog] {
        switch authState {
        case .loggedOut:
            return recents.filter { $0.ownerScope == .anonymous }
        case .loggedIn(let userId):
            return recents.filter { $0.ownerScope == .account && $0.ownerUserId == userId }
        }
    }

    /// All blogs created while the user was signed out.
    var anonymousDrafts: [CreatedRecapBlog] {
        recents.filter { $0.ownerScope == .anonymous }
    }

    /// Reassigns every anonymous draft to the given userId.
    func importAnonymousDrafts(into userId: String) {
        for idx in recents.indices where recents[idx].ownerScope == .anonymous {
            recents[idx].ownerScope = .account
            recents[idx].ownerUserId = userId
            recents[idx].syncStatus = .localOnly
        }
        persistRecents()
    }

    /// Reassigns a single anonymous draft to the given userId.
    func importSingleAnonymousDraft(_ draft: CreatedRecapBlog, into userId: String) {
        guard let idx = recents.firstIndex(where: { $0.id == draft.id }),
              recents[idx].ownerScope == .anonymous else { return }
        recents[idx].ownerScope = .account
        recents[idx].ownerUserId = userId
        recents[idx].syncStatus = .localOnly
        persistRecents()
    }

    // MARK: - Public API

    /// Call when user completes the Create Blog sequence (before showing RecapSavedView).
    func addCreatedBlog(trip: TripDraft) {
        let startDate = trip.earliestDate
        let endDate = trip.latestDate
        let tempDetail = buildBlogDetail(from: trip)
        let placeCount = tempDetail.days.reduce(0) { $0 + $1.placeStops.count }
        let duration = trip.days.count

        // Auto-detect ownership from current auth state
        let resolvedScope: OwnerScope
        let resolvedUserId: String?
        if let user = AuthService.shared.currentUser {
            resolvedScope = .account
            resolvedUserId = user.id
        } else {
            resolvedScope = .anonymous
            resolvedUserId = nil
        }

        let blog = CreatedRecapBlog(
            sourceTripId: trip.id,
            title: trip.title,
            createdAt: Date(),
            coverImageName: trip.coverImageName,
            coverAssetIdentifier: trip.coverAssetIdentifier,
            selectedPhotoCount: trip.selectedPhotoCount,
            countryName: trip.primaryCountryDisplayName,
            tripDateRangeText: trip.tripDateRangeDisplayText,
            lastEditedAt: nil,
            tripStartDate: startDate,
            tripEndDate: endDate,
            totalPlaceVisitCount: placeCount,
            tripDurationDays: duration,
            caption: nil,
            ownerScope: resolvedScope,
            ownerUserId: resolvedUserId
        )
        tripDraftsBySourceId[trip.id] = trip
        // Cache the blog detail so that on the next scan, existingIds is populated
        // correctly and photos already in the blog are not flagged as "new moments".
        blogDetailsBySourceId[trip.id] = tempDetail
        // Set the per-blog notification cutoff to the latest photo timestamp so that
        // the very next scan does not re-surface photos already in the blog.
        if let maxDate = tempDetail.days.flatMap(\.placeStops).flatMap(\.photos).map(\.timestamp).max() {
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blog.id)
        }
        recents.insert(blog, at: 0)
        pendingRecapCreated = true
        persistRecents()
        persistTripDrafts()
    }

    /// Dismiss the "Recap Blog has been created!" banner.
    func dismissRecapCreatedBanner() {
        showRecapCreatedBanner = false
    }

    /// Whether a draft with this id has already been turned into a created blog visible to the current user.
    /// Logged-out users only see anonymous blogs; logged-in users only see their own account blogs.
    func hasCreatedBlog(sourceTripId: UUID) -> Bool {
        visibleRecents.contains { $0.sourceTripId == sourceTripId }
    }

    /// Date ranges (start, end) of created blogs visible to the current user AND active drafts.
    /// Logged-out users only exclude anonymous blog ranges; logged-in users only exclude their own.
    func occupiedDateRanges() -> [(start: Date, end: Date)] {
        let calendar = Calendar.current

        let blogRanges: [(start: Date, end: Date)] = visibleRecents.compactMap { blog in
            guard let start = blog.tripStartDate, let end = blog.tripEndDate else { return nil }
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            return (start: start, end: endOfDay)
        }
        
        let activeDraftRanges: [(start: Date, end: Date)] = draftOccupiedRanges.map { range in
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: range.end) ?? range.end
            return (start: range.start, end: endOfDay)
        }
        
        return blogRanges + activeDraftRanges
    }

    /// TripDraft snapshot for opening BlogPreviewView. Nil if not found.
    func tripDraft(for sourceTripId: UUID) -> TripDraft? {
        tripDraftsBySourceId[sourceTripId]
    }

    /// Returns a trip draft with photo selection matching the current blog content (for Edit → photo selection flow). Nil if no draft.
    func tripDraftApplyingBlogSelection(blogId: UUID) -> TripDraft? {
        guard var trip = tripDraftsBySourceId[blogId] else { return nil }
        let includedIds: Set<UUID>
        if let detail = blogDetailsBySourceId[blogId] {
            includedIds = Set(detail.days.flatMap { day in day.placeStops.flatMap { stop in stop.photos.map(\.id) } })
        } else {
            includedIds = Set(trip.days.flatMap { day in day.photos.filter(\.isSelected).map(\.id) })
        }
        for dayIdx in trip.days.indices {
            var day = trip.days[dayIdx]
            for photoIdx in day.photos.indices {
                day.photos[photoIdx].isSelected = includedIds.contains(day.photos[photoIdx].id)
            }
            trip.days[dayIdx] = day
        }
        tripDraftsBySourceId[blogId] = trip
        persistTripDrafts()
        return trip
    }

    /// Update an existing blog with a modified trip (e.g. after Edit → photo selection → Update). Rebuilds detail from trip and saves.
    func updateBlog(blogId: UUID, trip: TripDraft) async {
        tripDraftsBySourceId[blogId] = trip
        let detail = await buildBlogDetailAsync(from: trip)
        blogDetailsBySourceId[blogId] = detail
        await MainActor.run {
            guard let idx = recents.firstIndex(where: { $0.sourceTripId == blogId }) else { return }
            let old = recents[idx]
            recents[idx] = CreatedRecapBlog(
                id: old.id,
                sourceTripId: old.sourceTripId,
                title: detail.title,
                createdAt: old.createdAt,
                coverImageName: trip.coverImageName,
                coverAssetIdentifier: trip.coverAssetIdentifier,
                selectedPhotoCount: trip.selectedPhotoCount,
                countryName: detail.countryName ?? old.countryName,
                tripDateRangeText: trip.tripDateRangeDisplayText,
                lastEditedAt: Date(),
                tripStartDate: trip.earliestDate,
                tripEndDate: trip.latestDate,
                totalPlaceVisitCount: detail.days.reduce(0) { $0 + $1.placeStops.count },
                tripDurationDays: detail.days.count,
                caption: self.primaryCaption(from: detail),
                blogKey: old.blogKey,
                ownerScope: old.ownerScope,
                ownerUserId: old.ownerUserId
            )
            persistRecents()
            persistTripDrafts()
            persistBlogDetails()
            enforceArchiveRules()
        }
    }

    /// Marks a blog as uploaded to the cloud.
    func markAsUploaded(sourceTripId: UUID) {
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            recents[idx].cloudState = .uploadedActive
            persistRecents()
            enforceArchiveRules()
        }
    }

    /// Enforces cloud storage limits based on entitlements.
    func enforceArchiveRules() {
        let limit = EntitlementManager.shared.activeCloudBlogLimit
        guard let maxCloud = limit else {
            // Pro user: ensure all uploaded blogs are uploadedActive
            var changed = false
            for i in recents.indices where recents[i].cloudState == .uploadedArchived {
                recents[i].cloudState = .uploadedActive
                changed = true
            }
            if changed { persistRecents() }
            return
        }

        // Free tier: sort uploaded blogs by date and archive those beyond the limit
        let uploadedBlogs = recents.filter { $0.cloudState != .localOnly }.sorted { $0.createdAt > $1.createdAt }
        var changed = false
        for (index, blog) in uploadedBlogs.enumerated() {
            guard let idx = recents.firstIndex(where: { $0.id == blog.id }) else { continue }

            let hasLifetime = EntitlementManager.shared.lifetimeAllocatedBlogIDs.contains(blog.sourceTripId)
            let isWithinLimit = index < maxCloud

            let targetState: CloudState = (isWithinLimit || hasLifetime) ? .uploadedActive : .uploadedArchived
            if recents[idx].cloudState != targetState {
                recents[idx].cloudState = targetState
                changed = true
            }
        }
        if changed { persistRecents() }
    }

    /// Injects newly scanned photos into an existing blog's RecapBlogDetail.
    /// Each photo is matched to the appropriate RecapBlogDay by calendar date, and within
    /// that day to the closest PlaceStop by time gap (≤ gapHoursNewSegment). If no close
    /// stop exists, a new stop is appended to the day. New days are created when needed.
    /// The updated detail is saved automatically.
    func injectPhotos(_ newPhotos: [MockPhoto], intoSourceTripId sourceTripId: UUID) {
        guard !newPhotos.isEmpty else { return }
        guard var detail = blogDetailsBySourceId[sourceTripId]
                ?? tripDraftsBySourceId[sourceTripId].map({ buildBlogDetail(from: $0) }) else { return }

        let cal = Calendar.current
        let gapLimit: TimeInterval = Double(ScanConfig.gapHoursNewSegment) * 3600
        let locationLimit: Double = ScanConfig.placeClusterMeters

        // Deduplicate against photos already in the blog.
        let existingIds = Set(detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier))
        let photos = newPhotos.filter { photo in
            guard let lid = photo.localIdentifier else { return true }
            return !existingIds.contains(lid)
        }
        guard !photos.isEmpty else { return }

        // Group incoming photos by calendar day.
        let byDay = Dictionary(grouping: photos) { photo in
            cal.startOfDay(for: photo.timestamp)
        }

        var modifiedDayIndices: Set<Int> = []
        // Tracks (dayIndex, stopIndex) for newly created stops that have a location and need geocoding.
        var newStopsToGeocode: [(dayIdx: Int, stopIdx: Int)] = []

        for (dayStart, dayPhotos) in byDay.sorted(by: { $0.key < $1.key }) {
            // Find or create the matching RecapBlogDay.
            var dayIdx = detail.days.firstIndex(where: { cal.startOfDay(for: $0.date) == dayStart })
            if dayIdx == nil {
                // Create a new day and insert it in chronological order.
                let newDay = RecapBlogDay(dayIndex: 0, date: dayStart, placeStops: [])
                detail.days.append(newDay)
                detail.days.sort { $0.date < $1.date }
                // Re-assign dayIndex after sort.
                for i in detail.days.indices { detail.days[i].dayIndex = i + 1 }
                dayIdx = detail.days.firstIndex(where: { cal.startOfDay(for: $0.date) == dayStart })!
            }
            guard let di = dayIdx else { continue }

            var unmatchedRecapPhotos: [RecapPhoto] = []

            for photo in dayPhotos.sorted(by: { $0.timestamp < $1.timestamp }) {
                let recapPhoto = RecapPhoto(
                    id: photo.id,
                    timestamp: photo.timestamp,
                    location: photo.location,
                    imageName: photo.imageName,
                    isIncluded: false,
                    localIdentifier: photo.localIdentifier
                )

                // Find best matching stop by time proximity + optional location proximity.
                var bestIdx: Int? = nil
                var bestGap: TimeInterval = .greatestFiniteMagnitude
                for (si, stop) in detail.days[di].placeStops.enumerated() {
                    let stopPhotos = stop.photos
                    guard let earliest = stopPhotos.map(\.timestamp).min(),
                          let latest = stopPhotos.map(\.timestamp).max() else { continue }
                    let gapBefore = max(0, earliest.timeIntervalSince(photo.timestamp))
                    let gapAfter  = max(0, photo.timestamp.timeIntervalSince(latest))
                    let gap = min(gapBefore, gapAfter)
                    guard gap <= gapLimit else { continue }

                    // Reject if another stop was visited in the gap between this stop and the new photo.
                    // This prevents a return-visit photo from being merged into the earlier visit.
                    if gapAfter > 0 {
                        let hasInterveningStop = detail.days[di].placeStops.enumerated().contains { otherSi, other in
                            guard otherSi != si else { return false }
                            guard let otherEarliest = other.photos.map(\.timestamp).min() else { return false }
                            return otherEarliest > latest && otherEarliest < photo.timestamp
                        }
                        if hasInterveningStop { continue }
                    }

                    if let photoCoord = photo.location, let stopCoord = stop.representativeLocation {
                        let photoLoc = CLLocation(latitude: photoCoord.latitude, longitude: photoCoord.longitude)
                        let stopLoc  = CLLocation(latitude: stopCoord.latitude, longitude: stopCoord.longitude)
                        guard photoLoc.distance(from: stopLoc) <= locationLimit else { continue }
                    }

                    if gap < bestGap {
                        bestGap = gap
                        bestIdx = si
                    }
                }

                if let si = bestIdx {
                    detail.days[di].placeStops[si].photos.append(recapPhoto)
                    detail.days[di].placeStops[si].photos.sort { $0.timestamp < $1.timestamp }
                    modifiedDayIndices.insert(di)
                } else {
                    unmatchedRecapPhotos.append(recapPhoto)
                }
            }

            // Cluster unmatched photos into new place stops using the same
            // algorithm that groups photos when building the blog initially.
            if !unmatchedRecapPhotos.isEmpty {
                let inputs = unmatchedRecapPhotos.map { p in
                    ClusterPhotoInput(id: p.id, timestamp: p.timestamp, location: p.location)
                }
                let baseIndex = detail.days[di].placeStops.count
                let groups = clusteringService.placeStops(from: inputs) { idx in
                    "Stop \(baseIndex + idx + 1)"
                }
                for (orderIndex, groupInputs) in groups {
                    let groupPhotos = groupInputs.compactMap { input in
                        unmatchedRecapPhotos.first { $0.id == input.id }
                    }.sorted { $0.timestamp < $1.timestamp }
                    let repLoc = groupPhotos.compactMap(\.location).first
                    // Use "Captured Moment" for camera-only photos (no location), "Stop N" otherwise
                    let placeTitle: String
                    if repLoc == nil {
                        placeTitle = groups.count > 1 ? "Captured Moment \(orderIndex + 1)" : "Captured Moment"
                    } else {
                        placeTitle = "Stop \(detail.days[di].placeStops.count + 1)"
                    }
                    let newStopIdx = detail.days[di].placeStops.count
                    let newStop = PlaceStop(
                        orderIndex: newStopIdx,
                        placeTitle: placeTitle,
                        representativeLocation: repLoc,
                        photos: groupPhotos
                    )
                    detail.days[di].placeStops.append(newStop)
                    if repLoc != nil {
                        newStopsToGeocode.append((dayIdx: di, stopIdx: newStopIdx))
                    }
                }
                modifiedDayIndices.insert(di)
            }
        }

        saveBlogDetail(detail, asDraft: true)

        // Run same business logic as initial selection: score quality, then preselect only good-quality photos per stop.
        if !modifiedDayIndices.isEmpty {
            Task {
                // Geocode any newly created stops that have location data.
                if !newStopsToGeocode.isEmpty,
                   var geocodedDetail = blogDetailsBySourceId[sourceTripId] {
                    for entry in newStopsToGeocode {
                        let di = entry.dayIdx
                        let si = entry.stopIdx
                        guard di < geocodedDetail.days.count,
                              si < geocodedDetail.days[di].placeStops.count,
                              let coord = geocodedDetail.days[di].placeStops[si].representativeLocation else { continue }
                        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let place = await GeocodingService.shared.place(for: loc)
                        geocodedDetail.days[di].placeStops[si].placeTitle = "Near \(place.areaName)"
                        geocodedDetail.days[di].placeStops[si].placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                    }
                    saveBlogDetail(geocodedDetail, asDraft: true)
                }
                await applyPhotoQualitySelectionForBlog(sourceTripId: sourceTripId, dayIndices: Array(modifiedDayIndices))
            }
        }

        // Update blog metadata to reflect newly injected photos.
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            let allDayDates = detail.days.map(\.date)
            if let minDate = allDayDates.min(),
               (recents[idx].tripStartDate == nil || minDate < recents[idx].tripStartDate!) {
                recents[idx].tripStartDate = minDate
            }
            if let maxDate = allDayDates.max(),
               (recents[idx].tripEndDate == nil || maxDate > recents[idx].tripEndDate!) {
                recents[idx].tripEndDate = maxDate
            }
            recents[idx].tripDateRangeText = Self.formatDateRange(
                start: recents[idx].tripStartDate,
                end: recents[idx].tripEndDate
            )
            recents[idx].selectedPhotoCount = detail.days
                .flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
            recents[idx].totalPlaceVisitCount = detail.days.reduce(0) { $0 + $1.placeStops.count }
            recents[idx].tripDurationDays = detail.days.count
            // Mark as edited so the blog appears in "My blogs" / Latest (e.g. "Edited Today").
            recents[idx].lastEditedAt = Date()
            recents[idx].syncStatus = .needsUpload
            persistRecents()
        }
    }

    /// Representative coordinate for a blog (first photo with location in its trip draft). Nil if no draft or no location.
    func coordinate(for sourceTripId: UUID) -> CLLocationCoordinate2D? {
        guard let trip = tripDraftsBySourceId[sourceTripId] else { return nil }
        let first = trip.days.flatMap(\.photos).first(where: { $0.location != nil })
        return first?.location?.clCoordinate
    }

    /// Returns saved blog detail if user has edited and saved before. Otherwise nil (caller builds from trip).
    func getBlogDetail(blogId: UUID) -> RecapBlogDetail? {
        blogDetailsBySourceId[blogId]
    }

    /// Persist edited blog detail. Call when user taps Save on RecapBlogPageView. Updates the corresponding recents entry.
    /// - Parameter asDraft: If true, preserves the existing lastEditedAt (keeping it nil if it was a draft).
    func saveBlogDetail(_ detail: RecapBlogDetail, asDraft: Bool = false) {
        blogDetailsBySourceId[detail.id] = detail
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == detail.id }) else { return }
        let old = recents[idx]
        let country = (detail.countryName.flatMap { $0.isEmpty || $0 == "Unknown" ? nil : $0 }) ?? old.countryName

        // Use the dates from detail to accurately reflect removals/splits
        let newStart = detail.days.first?.date ?? old.tripStartDate
        let newEnd = detail.days.last?.date ?? old.tripEndDate
        let newDateRange = Self.formatDateRange(start: newStart, end: newEnd) ?? old.tripDateRangeText
        let newSelectedCount = detail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

        recents[idx] = CreatedRecapBlog(
            id: old.id,
            sourceTripId: old.sourceTripId,
            title: detail.title,
            createdAt: old.createdAt,
            coverImageName: detail.coverTheme,
            coverAssetIdentifier: detail.selectedCoverPhotoIdentifier,
            selectedPhotoCount: newSelectedCount,
            countryName: country,
            tripDateRangeText: newDateRange,
            lastEditedAt: asDraft ? old.lastEditedAt : Date(),
            tripStartDate: newStart,
            tripEndDate: newEnd,
            totalPlaceVisitCount: detail.days.reduce(0) { $0 + $1.placeStops.count },
            tripDurationDays: detail.days.count,
            caption: primaryCaption(from: detail),
            blogKey: old.blogKey,
            ownerScope: old.ownerScope,
            ownerUserId: old.ownerUserId
        )
        persistRecents()
        persistBlogDetails()
    }

    /// Updates the caption of a single photo across any stored blog detail that contains it.
    /// Called when the user edits a caption from the Places Visited photo modal.
    func updatePhotoCaption(photoId: UUID, newCaption: String) {
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        if detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].id == photoId {
                            detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].caption = newCaption.isEmpty ? nil : newCaption
                            detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = true
                            detailChanged = true
                        }
                    }
                }
            }
            if detailChanged {
                blogDetailsBySourceId[key] = detail
                changed = true
            }
        }
        if changed {
            persistBlogDetails()
            // Notify SwiftUI observers so views reading `visitedPlaces` (a computed property
            // derived from `blogDetailsBySourceId`) re-render immediately with the new caption.
            objectWillChange.send()
        }
    }

    /// Updates the place stop name for the stop that contains the given photo, across all stored blog details.
    /// Called when the user edits a place name from the Places Visited photo modal.
    func updatePlaceStopName(photoId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    let containsPhoto = detail.days[dayIdx].placeStops[stopIdx].photos.contains { $0.id == photoId }
                    if containsPhoto {
                        detail.days[dayIdx].placeStops[stopIdx].placeTitle = trimmed
                        detailChanged = true
                    }
                }
            }
            if detailChanged {
                blogDetailsBySourceId[key] = detail
                changed = true
            }
        }
        if changed {
            persistBlogDetails()
            objectWillChange.send()
        }
    }

    /// Sets `isIncluded = false` for the given photo across any stored blog detail that contains it.
    /// Called when the user removes a photo from the Place pull-up modal in Places Visited or My Blogs.
    /// The photo is soft-deleted (recoverable via the Manage Photos flow in the blog editor).
    func removePhotoFromBlog(photoId: UUID) {
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        if detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].id == photoId {
                            detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].isIncluded = false
                            detailChanged = true
                        }
                    }
                }
            }
            if detailChanged {
                blogDetailsBySourceId[key] = detail
                changed = true
            }
        }
        if changed {
            persistBlogDetails()
            objectWillChange.send()
        }
    }

    /// Deletes a created blog locally and from the cloud if it was published.
    func deleteBlog(sourceTripId: UUID) {
        if let key = recents.first(where: { $0.sourceTripId == sourceTripId })?.blogKey {
            Task {
                do {
                    try await APIManager.shared.deleteBlogFromCloud(blogKey: key)
                    print("✅ Successfully deleted blog (key: \(key)) from cloud.")
                } catch {
                    print("🚨 Failed to delete blog from cloud: \(error)")
                }
            }
        }
        removeLocalCopy(sourceTripId: sourceTripId)
    }

    /// Removes a created blog locally, but DOES NOT delete it from the cloud.
    func removeLocalCopy(sourceTripId: UUID) {
        recents.removeAll { $0.sourceTripId == sourceTripId }
        blogDetailsBySourceId.removeValue(forKey: sourceTripId)
        if pendingRecapCreated { pendingRecapCreated = false }
        lastDiscardedTripId = sourceTripId
        needsRescan = true
        persistRecents()
        persistBlogDetails()
        // If the user deleted the blog they were adding to from the in-app camera, clear
        // the on-the-go state so the "Start Blog" prompt will show again next camera session.
        if OnTheGoTripStore.activeBlogId == sourceTripId {
            OnTheGoTripStore.markTripAsEnded()
        }
    }

    // MARK: - Merge & Split

    /// Merges two blogs into one. The `keepId` blog absorbs all days from `absorbId`.
    /// Both IDs are `sourceTripId` values.
    func mergeBlogs(keepId: UUID, absorbId: UUID) {
        guard var keepDetail = blogDetailsBySourceId[keepId],
              let absorbDetail = blogDetailsBySourceId[absorbId],
              let keepIdx = recents.firstIndex(where: { $0.sourceTripId == keepId }) else {
            return
        }

        // 1. Combine days, merging same-date days
        var daysByDate: [String: RecapBlogDay] = [:]
        let cal = Calendar.current
        let dateKey: (Date) -> String = { date in
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
        }

        for day in keepDetail.days {
            daysByDate[dateKey(day.date)] = day
        }
        for day in absorbDetail.days {
            let key = dateKey(day.date)
            if var existing = daysByDate[key] {
                // Same calendar date — merge place stops
                var stops = existing.placeStops + day.placeStops
                stops.sort {
                    ($0.visitedTimeDigitized ?? "") < ($1.visitedTimeDigitized ?? "")
                }
                for i in stops.indices { stops[i].orderIndex = i }
                existing.placeStops = stops
                if existing.dayCaption == nil { existing.dayCaption = day.dayCaption }
                existing.isPlaceNamesResolved = existing.isPlaceNamesResolved && day.isPlaceNamesResolved
                daysByDate[key] = existing
            } else {
                daysByDate[key] = day
            }
        }

        var allDays = daysByDate.values.sorted { $0.date < $1.date }
        for i in allDays.indices { allDays[i].dayIndex = i + 1 }

        // 2. Merge removed place stops
        let mergedRemoved = keepDetail.removedPlaceStops + absorbDetail.removedPlaceStops

        // 3. Update detail
        keepDetail.days = allDays
        keepDetail.removedPlaceStops = mergedRemoved
        blogDetailsBySourceId[keepId] = keepDetail

        // 4. Update recents metadata
        let keepOld = recents[keepIdx]
        let absorbOld = recents.first { $0.sourceTripId == absorbId }
        let newStart = [keepOld.tripStartDate, absorbOld?.tripStartDate].compactMap { $0 }.min()
        let newEnd = [keepOld.tripEndDate, absorbOld?.tripEndDate].compactMap { $0 }.max()
        let totalPlaces = allDays.reduce(0) { $0 + $1.placeStops.count }
        let totalPhotos = allDays.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

        recents[keepIdx].tripStartDate = newStart
        recents[keepIdx].tripEndDate = newEnd
        recents[keepIdx].totalPlaceVisitCount = totalPlaces
        recents[keepIdx].tripDurationDays = allDays.count
        recents[keepIdx].selectedPhotoCount = totalPhotos
        recents[keepIdx].tripDateRangeText = Self.formatDateRange(start: newStart, end: newEnd)
        recents[keepIdx].lastEditedAt = Date()
        recents[keepIdx].syncStatus = .needsUpload

        // 5. Best-effort merge TripDraft
        if var keepTrip = tripDraftsBySourceId[keepId],
           let absorbTrip = tripDraftsBySourceId[absorbId] {
            var combined = keepTrip.days + absorbTrip.days
            combined.sort {
                let t0 = $0.photos.first?.timestamp ?? .distantPast
                let t1 = $1.photos.first?.timestamp ?? .distantPast
                return t0 < t1
            }
            for i in combined.indices { combined[i].dayIndex = i + 1 }
            keepTrip.days = combined
            tripDraftsBySourceId[keepId] = keepTrip
        }

        // 6. Remove the absorbed blog
        recents.removeAll { $0.sourceTripId == absorbId }
        blogDetailsBySourceId.removeValue(forKey: absorbId)
        tripDraftsBySourceId.removeValue(forKey: absorbId)

        // 7. Persist
        persistRecents()
        persistBlogDetails()
        persistTripDrafts()
        needsRescan = true
    }

    /// Splits a blog into two at the given day boundary.
    /// Days 0...afterDayIndex stay in Part 1. Days (afterDayIndex+1)... become Part 2.
    func splitBlog(blogId: UUID, afterDayIndex: Int) {
        guard let detail = blogDetailsBySourceId[blogId],
              let recentIdx = recents.firstIndex(where: { $0.sourceTripId == blogId }),
              afterDayIndex >= 0,
              afterDayIndex < detail.days.count - 1 else {
            return
        }

        let oldRecent = recents[recentIdx]

        // 1. Split days
        var part1Days = Array(detail.days[0...afterDayIndex])
        var part2Days = Array(detail.days[(afterDayIndex + 1)...])
        for i in part1Days.indices { part1Days[i].dayIndex = i + 1 }
        for i in part2Days.indices { part2Days[i].dayIndex = i + 1 }

        // 2. Split removed place stops by day
        let part1DayIds = Set(part1Days.map(\.id))
        let part1Removed = detail.removedPlaceStops.filter { part1DayIds.contains($0.dayId) }
        let part2Removed = detail.removedPlaceStops.filter { !part1DayIds.contains($0.dayId) }

        // 3. Generate titles
        let baseTitle = detail.title
            .replacingOccurrences(of: " \\(Part \\d+ of \\d+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let title1 = "\(baseTitle) (Part 1 of 2)"
        let title2 = "\(baseTitle) (Part 2 of 2)"

        // 4. Create Part 1 detail (reuse existing id)
        let detail1 = RecapBlogDetail(
            id: blogId,
            title: title1,
            days: part1Days,
            coverTheme: detail.coverTheme,
            selectedCoverPhotoIdentifier: detail.selectedCoverPhotoIdentifier,
            countryName: detail.countryName,
            blogKey: detail.blogKey,
            removedPlaceStops: part1Removed
        )

        // 5. Create Part 2 detail (new UUID)
        let newBlogId = UUID()
        let part2CoverIdentifier = part2Days.first?.placeStops.first?.photos.first(where: \.isIncluded)?.localIdentifier
        let detail2 = RecapBlogDetail(
            id: newBlogId,
            title: title2,
            days: part2Days,
            coverTheme: detail.coverTheme,
            selectedCoverPhotoIdentifier: part2CoverIdentifier,
            countryName: detail.countryName,
            removedPlaceStops: part2Removed
        )

        // 6. Update Part 1 metadata
        let start1 = part1Days.first?.date
        let end1 = part1Days.last?.date
        let places1 = part1Days.reduce(0) { $0 + $1.placeStops.count }
        let photos1 = part1Days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

        recents[recentIdx].title = title1
        recents[recentIdx].tripStartDate = start1
        recents[recentIdx].tripEndDate = end1
        recents[recentIdx].totalPlaceVisitCount = places1
        recents[recentIdx].tripDurationDays = part1Days.count
        recents[recentIdx].selectedPhotoCount = photos1
        recents[recentIdx].tripDateRangeText = Self.formatDateRange(start: start1, end: end1)
        recents[recentIdx].lastEditedAt = Date()
        recents[recentIdx].syncStatus = .needsUpload

        // 7. Create Part 2 recents entry
        let start2 = part2Days.first?.date
        let end2 = part2Days.last?.date
        let places2 = part2Days.reduce(0) { $0 + $1.placeStops.count }
        let photos2 = part2Days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

        let newRecent = CreatedRecapBlog(
            sourceTripId: newBlogId,
            title: title2,
            createdAt: Date(),
            coverImageName: detail.coverTheme,
            coverAssetIdentifier: part2CoverIdentifier,
            selectedPhotoCount: photos2,
            countryName: oldRecent.countryName,
            tripDateRangeText: Self.formatDateRange(start: start2, end: end2),
            lastEditedAt: Date(),
            tripStartDate: start2,
            tripEndDate: end2,
            totalPlaceVisitCount: places2,
            tripDurationDays: part2Days.count,
            ownerScope: oldRecent.ownerScope,
            ownerUserId: oldRecent.ownerUserId
        )
        recents.append(newRecent)

        // 8. Best-effort split TripDraft
        if let trip = tripDraftsBySourceId[blogId] {
            let splitIdx = min(afterDayIndex, trip.days.count - 1)
            if splitIdx < trip.days.count - 1 {
                var trip1 = trip
                trip1.days = Array(trip.days[0...splitIdx])
                for i in trip1.days.indices { trip1.days[i].dayIndex = i + 1 }
                trip1.title = title1
                tripDraftsBySourceId[blogId] = trip1

                var trip2Days = Array(trip.days[(splitIdx + 1)...])
                for i in trip2Days.indices { trip2Days[i].dayIndex = i + 1 }
                let trip2 = TripDraft(
                    id: newBlogId,
                    title: title2,
                    dateRangeText: Self.formatDateRange(start: start2, end: end2) ?? "",
                    days: trip2Days,
                    coverImageName: trip.coverImageName,
                    isScannedFromDefaultRange: trip.isScannedFromDefaultRange,
                    coverTheme: trip.coverTheme,
                    coverAssetIdentifier: trip.coverAssetIdentifier
                )
                tripDraftsBySourceId[newBlogId] = trip2
            }
        }

        // 9. Store undo info (in-memory only)
        lastSplitUndoInfo = SplitUndoInfo(keepId: blogId, newId: newBlogId, originalTitle: detail.title)

        // 10. Persist
        blogDetailsBySourceId[blogId] = detail1
        blogDetailsBySourceId[newBlogId] = detail2
        persistRecents()
        persistBlogDetails()
        persistTripDrafts()
        needsRescan = true
    }

    /// Splits an unsaved trip draft into two, keeping one part for the current editor and preserving the other part as a new TripDraft.
    func splitUnsavedTrip(tripId: UUID, afterDayIndex: Int, keepPart: Int) {
        guard let trip = tripDraftsBySourceId[tripId],
              afterDayIndex >= 0,
              afterDayIndex < trip.days.count - 1 else {
            return
        }
        
        // 1. Split days
        let splitIdx = afterDayIndex
        var part1Days = Array(trip.days[0...splitIdx])
        var part2Days = Array(trip.days[(splitIdx + 1)...])
        for i in part1Days.indices { part1Days[i].dayIndex = i + 1 }
        for i in part2Days.indices { part2Days[i].dayIndex = i + 1 }
        
        let baseTitle = trip.title
            .replacingOccurrences(of: " \\(Part \\d+ of \\d+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        let title1 = "\(baseTitle) (Part 1 of 2)"
        let title2 = "\(baseTitle) (Part 2 of 2)"
        
        // 2. Formulate the two TripDrafts
        let start1 = part1Days.first?.photos.first?.timestamp
        let end1 = part1Days.last?.photos.last?.timestamp
        let dateRange1 = Self.formatDateRange(start: start1, end: end1) ?? ""
        
        var trip1 = trip
        trip1.title = title1
        trip1.days = part1Days
        trip1.dateRangeText = dateRange1
        
        let start2 = part2Days.first?.photos.first?.timestamp
        let end2 = part2Days.last?.photos.last?.timestamp
        let dateRange2 = Self.formatDateRange(start: start2, end: end2) ?? ""
        
        // Provide a cover image fallback for the second part
        let part2CoverIdentifier = part2Days.first?.photos.first(where: \.isSelected)?.localIdentifier
            ?? trip.coverAssetIdentifier
        
        let newTripId = UUID()
        let trip2 = TripDraft(
            id: newTripId,
            title: title2,
            dateRangeText: dateRange2,
            days: part2Days,
            coverImageName: trip.coverImageName,
            isScannedFromDefaultRange: trip.isScannedFromDefaultRange,
            coverTheme: trip.coverTheme,
            coverAssetIdentifier: part2CoverIdentifier
        )
        
        // 3. Assign the kept part to the original tripId, and the discarded part to the new ID.
        if keepPart == 1 {
            tripDraftsBySourceId[tripId] = trip1
            tripDraftsBySourceId[newTripId] = trip2
        } else {
            // we want the editor (which continues using 'tripId') to have part 2.
            var trip2WithOriginalID = trip2
            trip2WithOriginalID.id = tripId
            
            var trip1WithNewID = trip1
            trip1WithNewID.id = newTripId
            
            tripDraftsBySourceId[tripId] = trip2WithOriginalID
            tripDraftsBySourceId[newTripId] = trip1WithNewID
        }
        
        persistTripDrafts()
        needsRescan = true
    }

    /// Undoes the last split operation by re-merging the two resulting blogs back into one.
    func undoSplit() {
        guard let info = lastSplitUndoInfo else { return }
        // Merge Part 2 back into Part 1 (keepId absorbs newId)
        mergeBlogs(keepId: info.keepId, absorbId: info.newId)
        // Restore original title on the merged blog
        if let idx = recents.firstIndex(where: { $0.sourceTripId == info.keepId }) {
            recents[idx].title = info.originalTitle
            blogDetailsBySourceId[info.keepId]?.title = info.originalTitle
            persistRecents()
            persistBlogDetails()
        }
        lastSplitUndoInfo = nil
    }

    /// Formats a date range as "Jan 15 – 20, 2025" or "Jan 15 – Feb 3, 2025".
    static func formatDateRange(start: Date?, end: Date?) -> String? {
        guard let start = start, let end = end else { return nil }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let sy = cal.component(.year, from: start)
        let sm = cal.component(.month, from: start)
        let sd = cal.component(.day, from: start)
        let ey = cal.component(.year, from: end)
        let em = cal.component(.month, from: end)
        let ed = cal.component(.day, from: end)

        fmt.dateFormat = "MMM"
        let sMonth = fmt.string(from: start)
        let eMonth = fmt.string(from: end)

        if sy == ey && sm == em && sd == ed {
            return "\(sMonth) \(sd), \(sy)"
        } else if sy == ey && sm == em {
            return "\(sMonth) \(sd) – \(ed), \(sy)"
        } else if sy == ey {
            return "\(sMonth) \(sd) – \(eMonth) \(ed), \(sy)"
        } else {
            return "\(sMonth) \(sd), \(sy) – \(eMonth) \(ed), \(ey)"
        }
    }

    // MARK: - Cloud URL Management

    /// Returns true if every included photo in the blog has been uploaded to the cloud.
    func isBlogInCloud(blogId: UUID) -> Bool {
        guard let detail = blogDetailsBySourceId[blogId] else { return false }
        let included = detail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        return !included.isEmpty && included.allSatisfy { $0.cloudURL != nil }
    }

    /// Stores the server-assigned blogKey on the blog entry for share links.
    func setBlogKey(blogId: UUID, blogKey: Int) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == blogId }) else { return }
        recents[idx].blogKey = blogKey
        recents[idx].cloudState = .uploadedActive
        persistRecents()
        enforceArchiveRules()
    }

    /// After a successful createBlogWithPlaces call, writes the server-assigned blogKey and per-stop
    /// cloudPlaceIndex / visitedTimeDigitized back into the stored blog detail so future cloud
    /// updates (edits, deletes, re-uploads) can reference the correct server-side records.
    ///
    /// - Parameters:
    ///   - blogId:       The UUID of the blog (RecapBlogDetail.id / CreatedRecapBlog.sourceTripId).
    ///   - blogKey:      The server-assigned trip key.
    ///   - detail:       The in-memory detail used during publish, as a fallback if the detail is not
    ///                   yet persisted in blogDetailsBySourceId.
    ///   - placeMapping: Ordered list of (dayIdx, stopIdx, placeIndex, visitedTimeDigitized) produced
    ///                   by APIManager.createBlogWithPlaces, one entry per successfully uploaded stop.
    func applyCloudKeys(
        blogId: UUID,
        blogKey: Int,
        detail: RecapBlogDetail,
        placeMapping: [(dayIdx: Int, stopIdx: Int, placeIndex: Int, visitedTimeDigitized: String)]
    ) {
        // Update the recents entry so share links and cloud UI work immediately.
        setBlogKey(blogId: blogId, blogKey: blogKey)

        // Prefer the already-persisted detail (may have user edits); fall back to the provided one.
        var updatedDetail = blogDetailsBySourceId[blogId] ?? detail
        updatedDetail.blogKey = blogKey

        for info in placeMapping {
            guard info.dayIdx < updatedDetail.days.count,
                  info.stopIdx < updatedDetail.days[info.dayIdx].placeStops.count else {
                print("⚠️ applyCloudKeys: out-of-range mapping (day=\(info.dayIdx), stop=\(info.stopIdx)) — skipped")
                continue
            }
            updatedDetail.days[info.dayIdx].placeStops[info.stopIdx].cloudPlaceIndex = info.placeIndex
            updatedDetail.days[info.dayIdx].placeStops[info.stopIdx].visitedTimeDigitized = info.visitedTimeDigitized
        }

        blogDetailsBySourceId[blogId] = updatedDetail
        persistBlogDetails()
        print("✅ applyCloudKeys: blogKey=\(blogKey), \(placeMapping.count) stops updated in local storage")
    }

    /// Clears all cloud URLs from a blog's photos (removes from cloud) and deletes the blog from the backend.
    func removeFromCloud(blogId: UUID) {
        // 1. Delete the blog on the backend and clear the local blogKey
        if let idx = recents.firstIndex(where: { $0.sourceTripId == blogId }),
           let key = recents[idx].blogKey {
            recents[idx].blogKey = nil
            persistRecents()
            Task {
                do {
                    try await APIManager.shared.deleteBlogFromCloud(blogKey: key)
                    print("✅ Successfully deleted blog (key: \(key)) from cloud.")
                } catch {
                    print("🚨 Failed to delete blog from cloud: \(error)")
                }
            }
            // Mark it local only so upload limit checks accurately reflect it
            recents[idx].blogKey = nil
            recents[idx].cloudState = .localOnly
            persistRecents()
        }

        // 2. Clear local cloudURLs
        guard var detail = blogDetailsBySourceId[blogId] else { return }
        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                    detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = nil
                }
            }
        }
        blogDetailsBySourceId[blogId] = detail
        persistBlogDetails()
    }

    // MARK: - Cloud Sync

    /// Fetches trips and placeVisitHistory from the backend and reconciles them with local storage.
    /// - Existing local blogs (matched by blogKey): metadata and per-stop cloud keys are refreshed.
    /// - Cloud-only blogs (no local match): a new stub blog + reconstructed detail are created.
    /// Safe to call on every launch or on manual refresh; it is a no-op when not logged in.
    func syncFromCloud() async {
        guard let user = AuthService.shared.currentUser else { return }
        let username = user.username ?? user.displayName ?? user.email ?? ""
        guard !username.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch trips and place history in parallel.
            async let tripsTask = APIManager.shared.fetchTrips(username: username)
            async let historyTask = APIManager.shared.fetchPlaceVisitHistory(username: username)
            let (tripsResp, historyResp) = try await (tripsTask, historyTask)

            let serverTrips = (tripsResp.trips ?? []).filter { $0.status != "deleted" }
            let allPlaces = historyResp.visitedHistory ?? []

            // Index places by placeIndex for O(1) lookup.
            // Use uniquingKeysWith to tolerate duplicate placeIndex from API (e.g. after logout/login).
            let placeByIndex: [Int: ServerPlaceRecord] = Dictionary(
                allPlaces.map { ($0.placeIndex, $0) },
                uniquingKeysWith: { _, new in new }
            )

            var detailsChanged = false

            for serverTrip in serverTrips {
                if let localIdx = recents.firstIndex(where: { $0.blogKey == serverTrip.blogKey }) {
                    // ── Existing local blog ──────────────────────────────────────────────
                    // Update metadata from server (server is source of truth for cloud state).
                    if let title = serverTrip.title, !title.isEmpty {
                        recents[localIdx].title = title
                    }
                    if let country = serverTrip.country, !country.isEmpty {
                        recents[localIdx].countryName = country
                    }
                    recents[localIdx].cloudState = .uploadedActive

                    let blogId = recents[localIdx].sourceTripId
                    if var detail = blogDetailsBySourceId[blogId] {
                        detail.blogKey = serverTrip.blogKey
                        // Update cloud keys + content on matching stops.
                        for placeRef in serverTrip.placeList ?? [] {
                            guard let serverPlace = placeByIndex[placeRef.placeIndex] else { continue }
                            for dayIdx in detail.days.indices {
                                for stopIdx in detail.days[dayIdx].placeStops.indices {
                                    let stop = detail.days[dayIdx].placeStops[stopIdx]
                                    let matchByIndex = stop.cloudPlaceIndex == placeRef.placeIndex
                                    let matchByTime = serverPlace.visitedTimeDigitized != nil
                                        && stop.visitedTimeDigitized == serverPlace.visitedTimeDigitized
                                    guard matchByIndex || matchByTime else { continue }

                                    // Cloud keys
                                    detail.days[dayIdx].placeStops[stopIdx].cloudPlaceIndex = serverPlace.placeIndex
                                    if let vtd = serverPlace.visitedTimeDigitized {
                                        detail.days[dayIdx].placeStops[stopIdx].visitedTimeDigitized = vtd
                                    }
                                    // Place name
                                    if let name = serverPlace.placeName, !name.isEmpty {
                                        detail.days[dayIdx].placeStops[stopIdx].placeTitle = name
                                    }
                                    // Place category (POI type from create payload or server)
                                    if let cat = serverPlace.categories?.first, !cat.isEmpty {
                                        detail.days[dayIdx].placeStops[stopIdx].placeCategory = cat
                                    }
                                    // Place-level story → noteText
                                    if let story = serverPlace.story {
                                        detail.days[dayIdx].placeStops[stopIdx].noteText = story
                                    }
                                    // Per-photo story → caption (matched by cloudURL == serverPhoto.uri)
                                    for serverPhoto in serverPlace.photoList ?? [] {
                                        guard let story = serverPhoto.story, !story.isEmpty,
                                              let uri = serverPhoto.uri else { continue }
                                        for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                                            if detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL == uri {
                                                detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].caption = story
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        blogDetailsBySourceId[blogId] = detail
                        detailsChanged = true
                    }

                } else {
                    // ── Cloud-only blog — create a local stub ────────────────────────────
                    let userId = user.id

                    let newBlogId = UUID()
                    let tripPlaces = (serverTrip.placeList ?? [])
                        .compactMap { placeByIndex[$0.placeIndex] }

                    let detail = buildDetailFromServerPlaces(
                        tripPlaces,
                        blogId: newBlogId,
                        blogKey: serverTrip.blogKey,
                        title: serverTrip.title ?? "Trip",
                        countryName: serverTrip.country
                    )

                    let startDate = serverTrip.startTimestamp.map { Date(timeIntervalSince1970: $0 / 1000) }
                    let endDate   = serverTrip.endTimestamp.map   { Date(timeIntervalSince1970: $0 / 1000) }
                    let photoCount = detail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

                    let stub = CreatedRecapBlog(
                        id: UUID(),
                        sourceTripId: newBlogId,
                        title: serverTrip.title ?? "Trip",
                        createdAt: startDate ?? Date(),
                        coverImageName: "default",
                        coverAssetIdentifier: nil,
                        selectedPhotoCount: photoCount,
                        countryName: serverTrip.country,
                        tripDateRangeText: nil,
                        lastEditedAt: nil,
                        tripStartDate: startDate,
                        tripEndDate: endDate,
                        totalPlaceVisitCount: detail.days.reduce(0) { $0 + $1.placeStops.count },
                        tripDurationDays: max(1, detail.days.count),
                        caption: nil,
                        blogKey: serverTrip.blogKey,
                        ownerScope: .account,
                        ownerUserId: userId,
                        cloudState: .uploadedActive,
                        syncStatus: .clean
                    )

                    recents.append(stub)
                    blogDetailsBySourceId[newBlogId] = detail
                    detailsChanged = true
                }
            }

            persistRecents()
            if detailsChanged { persistBlogDetails() }
            enforceArchiveRules()
            print("✅ syncFromCloud: \(serverTrips.count) trips processed")

        } catch {
            print("🚨 syncFromCloud failed: \(error)")
        }
    }

    /// Reconstructs a RecapBlogDetail from server-side place records.
    /// Used for cloud-only trips that have no local counterpart.
    private func buildDetailFromServerPlaces(
        _ places: [ServerPlaceRecord],
        blogId: UUID,
        blogKey: Int,
        title: String,
        countryName: String?
    ) -> RecapBlogDetail {
        let calendar = Calendar.current
        let digitizedFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }()

        // Group places by calendar day using visitedTimeDigitized.
        var placesByDay: [Date: [ServerPlaceRecord]] = [:]
        for place in places {
            let dayDate: Date
            if let vtd = place.visitedTimeDigitized,
               let parsed = digitizedFormatter.date(from: vtd) {
                dayDate = calendar.startOfDay(for: parsed)
            } else {
                dayDate = calendar.startOfDay(for: Date())
            }
            placesByDay[dayDate, default: []].append(place)
        }

        let sortedDays = placesByDay.keys.sorted()
        var days: [RecapBlogDay] = []

        for (dayIdx, dayDate) in sortedDays.enumerated() {
            guard let dayPlaces = placesByDay[dayDate] else { continue }
            let sortedPlaces = dayPlaces.sorted {
                ($0.visitedTimeDigitized ?? "") < ($1.visitedTimeDigitized ?? "")
            }

            var stops: [PlaceStop] = []
            for (stopIdx, serverPlace) in sortedPlaces.enumerated() {
                let photos: [RecapPhoto] = (serverPlace.photoList ?? []).compactMap { photo in
                    guard let uri = photo.uri, !uri.isEmpty else { return nil }
                    let ts: Date = photo.digitizedTime.flatMap { digitizedFormatter.date(from: $0) } ?? Date()
                    let loc = photo.coordinate.map { PhotoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                    let caption = (photo.story?.isEmpty == false) ? photo.story : nil
                    return RecapPhoto(
                        timestamp: ts,
                        location: loc,
                        imageName: "",
                        isIncluded: photo.selected ?? true,
                        localIdentifier: nil,
                        caption: caption,
                        cloudURL: uri
                    )
                }

                let coord = serverPlace.coordinate.map { PhotoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                let noteText = (serverPlace.story?.isEmpty == false) ? serverPlace.story : nil
                let placeCategory = serverPlace.categories?.first
                stops.append(PlaceStop(
                    orderIndex: stopIdx,
                    placeTitle: serverPlace.placeName ?? "Stop \(stopIdx + 1)",
                    placeSubtitle: serverPlace.visitedCity,
                    representativeLocation: coord,
                    photos: photos,
                    noteText: noteText,
                    cloudPlaceIndex: serverPlace.placeIndex,
                    visitedTimeDigitized: serverPlace.visitedTimeDigitized,
                    placeCategory: placeCategory
                ))
            }

            guard !stops.isEmpty else { continue }
            days.append(RecapBlogDay(dayIndex: dayIdx + 1, date: dayDate, placeStops: stops))
        }

        return RecapBlogDetail(
            id: blogId,
            title: title,
            days: days,
            countryName: countryName,
            blogKey: blogKey
        )
    }

    // MARK: - Build Blog Detail

    /// Build RecapBlogDetail from a TripDraft, clustered into place stops. Use when no saved detail exists.
    /// All photos in a day are clustered together; isIncluded reflects the user's original selection.
    /// This lets ManagePhotos show the full pool of photos for each stop so the user can add/remove freely.
    func buildBlogDetail(from trip: TripDraft) -> RecapBlogDetail {
        let calendar = Calendar.current
        var days: [RecapBlogDay] = []
        for day in trip.days {
            // Skip days where the user selected nothing.
            guard day.photos.contains(where: \.isSelected) else { continue }

            // Cluster ALL photos (selected + unselected) by time/location.
            let clusterInputs: [ClusterPhotoInput] = day.photos.map { photo in
                ClusterPhotoInput(id: photo.id, timestamp: photo.timestamp, location: photo.location)
            }

            let stopGroups = clusteringService.placeStops(from: clusterInputs) { index in
                "Stop \(index + 1)"
            }

            // Build stops; isIncluded mirrors the user's photo selection.
            let placeStops: [PlaceStop] = stopGroups.compactMap { orderIndex, inputs -> PlaceStop? in
                let photos: [RecapPhoto] = inputs.map { input in
                    let photo = day.photos.first { $0.id == input.id }!
                    return RecapPhoto(
                        id: photo.id,
                        timestamp: photo.timestamp,
                        location: photo.location,
                        imageName: photo.imageName,
                        isIncluded: photo.isSelected,
                        localIdentifier: photo.localIdentifier,
                        caption: nil
                    )
                }
                guard photos.contains(where: \.isIncluded) else { return nil }
                let repLoc = inputs.compactMap(\.location).first
                return PlaceStop(
                    orderIndex: orderIndex,
                    placeTitle: "Stop \(orderIndex + 1)",
                    placeSubtitle: nil,
                    representativeLocation: repLoc,
                    photos: photos,
                    noteText: nil
                )
            }

            guard !placeStops.isEmpty else { continue }
            // Use the earliest selected photo's calendar day so Day 2's date matches its photos (camera trips use 0-based dayIndex; we use 1-based for display).
            let dayDate = day.photos.filter(\.isSelected).map(\.timestamp).min().map { calendar.startOfDay(for: $0) } ?? Date()
            let oneBasedIndex = days.count + 1
            days.append(RecapBlogDay(dayIndex: oneBasedIndex, date: dayDate, placeStops: placeStops))
        }

        // Default cover: first included photo's localIdentifier, fallback to trip's cover asset.
        let firstPhotoId = days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).compactMap(\.localIdentifier).first
        let coverId = firstPhotoId ?? trip.coverAssetIdentifier
        return RecapBlogDetail(id: trip.id, title: trip.title, days: days, coverTheme: trip.coverTheme, selectedCoverPhotoIdentifier: coverId)
    }

    /// Builds blog detail, resolves place names from reverse-geocoding, generates a title, and scores photos via Vision AI.
    func buildBlogDetailAsync(from trip: TripDraft) async -> RecapBlogDetail {
        // print out debug
        print("[buildBlogDetailAsync] Building detail for trip '\(trip.title)' with \(trip.days.count) days")
        var detail = buildBlogDetail(from: trip)
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, order: Int)] = []
        var order = 0

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                let stop = detail.days[dayIdx].placeStops[stopIdx]
                if Task.isCancelled { return detail }
                if let coord = stop.representativeLocation {
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let place = await GeocodingService.shared.place(for: loc)
                    cityCandidates.append((place.cityName, order))
                    countryCandidates.append((place.countryName, order))
                    order += 1
                    var updated = detail.days[dayIdx]
                    var stopCopy = updated.placeStops[stopIdx]
                    stopCopy.placeTitle = "Near \(place.areaName)"
                    stopCopy.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                    updated.placeStops[stopIdx] = stopCopy
                    detail.days[dayIdx] = updated
                }
            }
        }

        if Task.isCancelled { return detail }

        let primaryCity = primaryCityFromCandidates(cityCandidates)
        let primaryCountry = primaryFromCandidates(countryCandidates)
        let season = seasonFromDetail(detail)
        let cityPart: String
        if primaryCity.isEmpty || primaryCity == "Unknown Place" {
            cityPart = "New Place"
        } else {
            cityPart = primaryCity
        }
        if let s = season, !s.isEmpty {
            detail.title = "Trip To \(cityPart) in \(s)"
        } else {
            detail.title = "Trip To \(cityPart)"
        }
        if !primaryCountry.isEmpty && primaryCountry != "Unknown" {
            detail.countryName = primaryCountry
        }

        // Compute visitedTimeDigitized for each stop using EXIF timezone from PHAssets.
        // This ensures the displayed visit time reflects the local timezone where photos were taken,
        // not the device's current timezone (which may differ when the user is home after travel).
        let allIncludedPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let assetIds = allIncludedPhotos.compactMap(\.localIdentifier)
        var assetMap: [String: PHAsset] = [:]
        if !assetIds.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
            result.enumerateObjects { asset, _, _ in assetMap[asset.localIdentifier] = asset }
        }
        var tzMap: [String: TimeZone] = [:]
        await withTaskGroup(of: (String, TimeZone?).self) { group in
            for (id, asset) in assetMap {
                group.addTask { (id, await APIManager.getLocalTimeZone(for: asset)) }
            }
            for await (id, tz) in group {
                if let tz { tzMap[id] = tz }
            }
        }
        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                let stop = detail.days[dayIdx].placeStops[stopIdx]
                let photos = stop.photos.filter(\.isIncluded)
                guard let firstPhoto = photos.min(by: { $0.timestamp < $1.timestamp }),
                      let asset = assetMap[firstPhoto.localIdentifier ?? ""] else {
                    print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': skipped visitedTimeDigitized (no included photos or missing asset)")
                    continue
                }

                // Collect EXIF timezones for ALL included photos in the stop, then vote.
                // This guards against one outlier photo (screenshot, foreign-device photo) with a wrong offset
                // pulling the entire stop into the wrong timezone.
                let stopOffsets: [Int] = photos.compactMap { photo -> Int? in
                    guard let id = photo.localIdentifier, let tz = tzMap[id] else { return nil }
                    // Round to nearest 15-min increment so near-duplicate offsets collapse.
                    return (tz.secondsFromGMT() / 900) * 900
                }

                let consensusOffset: Int
                if stopOffsets.isEmpty {
                    print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': no EXIF timezone for any photo — falling back to UTC")
                    consensusOffset = 0
                } else {
                    // Vote: pick the offset that appears most often.
                    var tally: [Int: Int] = [:]
                    for off in stopOffsets { tally[off, default: 0] += 1 }
                    consensusOffset = tally.max(by: { $0.value < $1.value })!.key

                    // Log any outlier photos whose offset doesn't match the winner.
                    let outliers = photos.compactMap { photo -> String? in
                        guard let id = photo.localIdentifier,
                              let tz = tzMap[id],
                              (tz.secondsFromGMT() / 900) * 900 != consensusOffset else { return nil }
                        return "\(id.prefix(8))… offset=\(tz.secondsFromGMT() / 3600)h"
                    }
                    if !outliers.isEmpty {
                        print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': outlier photo TZ(s) ignored: \(outliers.joined(separator: ", "))")
                    }
                }

                let tz = TimeZone(secondsFromGMT: consensusOffset) ?? TimeZone(identifier: "UTC")!
                let date = asset.creationDate ?? firstPhoto.timestamp
                let digitized = APIManager.digitizedTimeString(from: date, timeZone: tz)
                print("[buildBlogDetail] ✅ '\(stop.placeTitle)': visitedTimeDigitized=\(digitized), tz=\(tz.identifier) (votes: \(stopOffsets.count))")
                detail.days[dayIdx].placeStops[stopIdx].visitedTimeDigitized = digitized
            }
        }

        // Score photos with iOS Vision AI and auto-select best per place stop.
        detail = await applyPhotoQualitySelection(to: detail)
        updateCoverPhotoFromQualityScores(&detail)
        return detail
    }

    // MARK: - Day-by-day processing (rate limit 50 geocode/min)

    /// Builds blog detail with structure for all days but only processes day 0 (geocode, title, visitedTime, photo quality).
    /// Use before navigating to recap; then call continueGeocodingDays(blogId:) when the recap page loads.
    func buildBlogDetailFirstDayOnly(from trip: TripDraft) async -> RecapBlogDetail {
        var detail = buildBlogDetail(from: trip)
        guard let firstDayIdx = detail.days.indices.first else { return detail }

        // Process only day 0: geocode, then title/country from day 0, visitedTime for day 0, photo quality for day 0.
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, order: Int)] = []
        var order = 0
        for stopIdx in detail.days[firstDayIdx].placeStops.indices {
            let stop = detail.days[firstDayIdx].placeStops[stopIdx]
            if Task.isCancelled { return detail }
            if let coord = stop.representativeLocation {
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let place = await GeocodingService.shared.place(for: loc)
                cityCandidates.append((place.cityName, order))
                countryCandidates.append((place.countryName, order))
                order += 1
                var dayCopy = detail.days[firstDayIdx]
                var stopCopy = dayCopy.placeStops[stopIdx]
                stopCopy.placeTitle = "Near \(place.areaName)"
                stopCopy.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                dayCopy.placeStops[stopIdx] = stopCopy
                detail.days[firstDayIdx] = dayCopy
            }
        }
        detail.days[firstDayIdx].isPlaceNamesResolved = true

        let primaryCity = primaryCityFromCandidates(cityCandidates)
        let primaryCountry = primaryFromCandidates(countryCandidates)
        let season = seasonFromDetail(detail)
        let cityPart = (primaryCity.isEmpty || primaryCity == "Unknown Place") ? "New Place" : primaryCity
        if let s = season, !s.isEmpty {
            detail.title = "Trip To \(cityPart) in \(s)"
        } else {
            detail.title = "Trip To \(cityPart)"
        }
        if !primaryCountry.isEmpty && primaryCountry != "Unknown" {
            detail.countryName = primaryCountry
        }

        detail = await applyVisitedTimeDigitized(to: detail, dayIndices: [firstDayIdx])
        if Task.isCancelled { return detail }
        detail = await applyPhotoQualitySelection(to: detail, dayIndices: [firstDayIdx])
        updateCoverPhotoFromQualityScores(&detail)
        return detail
    }

    /// Process one more day (geocode, visitedTime, photo quality) and merge into stored detail. Call after recommended delay.
    /// Sets processingDayIndexByBlogId when starting and clears when done; notifies observers.
    func continueGeocodingDays(blogId: UUID) async {
        guard var detail = blogDetailsBySourceId[blogId],
              let trip = tripDraftsBySourceId[blogId] else { return }
        let dayIndicesToProcess = detail.days.indices.filter { !detail.days[$0].isPlaceNamesResolved }
        guard let dayIdx = dayIndicesToProcess.first else { return }

        let placeCount = detail.days[dayIdx].placeStops.count
        let delay = await GeocodingService.shared.recommendedDelayBeforeNextBatch(estimatedNewCalls: placeCount)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if Task.isCancelled { return }

        processingDayIndexByBlogId[blogId] = dayIdx
        objectWillChange.send()

        var updatedDetail = await processOneDay(detail: detail, dayIndex: dayIdx)
        if Task.isCancelled {
            processingDayIndexByBlogId.removeValue(forKey: blogId)
            objectWillChange.send()
            return
        }
        updatedDetail.days[dayIdx].isPlaceNamesResolved = true
        updateCoverPhotoFromQualityScores(&updatedDetail)
        blogDetailsBySourceId[blogId] = updatedDetail
        persistBlogDetails()
        processingDayIndexByBlogId.removeValue(forKey: blogId)
        objectWillChange.send()

        // Process next day after a short yield so UI can update.
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        await continueGeocodingDays(blogId: blogId)
    }

    /// Geocode, visitedTimeDigitized, and photo quality for a single day; does not set isPlaceNamesResolved.
    private func processOneDay(detail: RecapBlogDetail, dayIndex: Int) async -> RecapBlogDetail {
        var result = detail
        guard dayIndex < result.days.count else { return result }

        for stopIdx in result.days[dayIndex].placeStops.indices {
            let stop = result.days[dayIndex].placeStops[stopIdx]
            if Task.isCancelled { return result }
            if let coord = stop.representativeLocation {
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let place = await GeocodingService.shared.place(for: loc)
                result.days[dayIndex].placeStops[stopIdx].placeTitle = "Near \(place.areaName)"
                result.days[dayIndex].placeStops[stopIdx].placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
            }
        }

        result = await applyVisitedTimeDigitized(to: result, dayIndices: [dayIndex])
        if Task.isCancelled { return result }
        result = await applyPhotoQualitySelection(to: result, dayIndices: [dayIndex])
        return result
    }

    /// Apply visitedTimeDigitized for the given day indices only.
    private func applyVisitedTimeDigitized(to detail: RecapBlogDetail, dayIndices: [Int]) async -> RecapBlogDetail {
        var result = detail
        let daySet = Set(dayIndices)
        let photosToResolve = detail.days.enumerated().flatMap { dayIdx, day -> [(Int, Int, RecapPhoto)] in
            guard daySet.contains(dayIdx) else { return [] }
            return day.placeStops.enumerated().flatMap { stopIdx, stop in
                stop.photos.filter(\.isIncluded).map { (dayIdx, stopIdx, $0) }
            }
        }
        let assetIds = photosToResolve.map(\.2).compactMap(\.localIdentifier)
        var assetMap: [String: PHAsset] = [:]
        if !assetIds.isEmpty {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
            fetch.enumerateObjects { asset, _, _ in assetMap[asset.localIdentifier] = asset }
        }
        var tzMap: [String: TimeZone] = [:]
        await withTaskGroup(of: (String, TimeZone?).self) { group in
            for (_, _, photo) in photosToResolve {
                guard let id = photo.localIdentifier, let asset = assetMap[id] else { continue }
                group.addTask { (id, await APIManager.getLocalTimeZone(for: asset)) }
            }
            for await (id, tz) in group {
                if let tz { tzMap[id] = tz }
            }
        }
        for (dayIdx, stopIdx, _) in photosToResolve {
            guard dayIdx < result.days.count, stopIdx < result.days[dayIdx].placeStops.count else { continue }
            let stop = result.days[dayIdx].placeStops[stopIdx]
            let photos = stop.photos.filter(\.isIncluded)
            guard let firstPhoto = photos.min(by: { $0.timestamp < $1.timestamp }),
                  let _ = assetMap[firstPhoto.localIdentifier ?? ""] else { continue }
            let stopOffsets: [Int] = photos.compactMap { photo -> Int? in
                guard let id = photo.localIdentifier, let tz = tzMap[id] else { return nil }
                return (tz.secondsFromGMT() / 900) * 900
            }
            let consensusOffset = stopOffsets.isEmpty ? 0 : (stopOffsets.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }.max(by: { $0.value < $1.value })?.key ?? 0)
            let tz = TimeZone(secondsFromGMT: consensusOffset) ?? TimeZone(identifier: "UTC")!
            let asset = assetMap[firstPhoto.localIdentifier ?? ""]!
            let date = asset.creationDate ?? firstPhoto.timestamp
            let digitized = APIManager.digitizedTimeString(from: date, timeZone: tz)
            result.days[dayIdx].placeStops[stopIdx].visitedTimeDigitized = digitized
        }
        return result
    }

    /// Updates selectedCoverPhotoIdentifier to the highest-scoring included photo across all scored days.
    /// Should be called after each applyPhotoQualitySelection pass so the cover improves as scoring progresses.
    private func updateCoverPhotoFromQualityScores(_ detail: inout RecapBlogDetail) {
        let scoredPhotos = detail.days
            .flatMap(\.placeStops)
            .flatMap(\.photos)
            .filter(\.isIncluded)
            .filter({ $0.qualityScore != nil })
        print("[CoverPhoto] Scored \(scoredPhotos.count) included photo(s)")
        for photo in scoredPhotos.sorted(by: { ($0.qualityScore?.totalScore ?? 0) > ($1.qualityScore?.totalScore ?? 0) }).prefix(5) {
            let hasFace = (photo.qualityScore?.facePenalty ?? 0) > 0
            print("[CoverPhoto]   id=\(photo.localIdentifier?.prefix(8) ?? "nil")… total=\(String(format: "%.3f", photo.qualityScore?.totalScore ?? 0)) aesthetics=\(String(format: "%.3f", photo.qualityScore?.aesthetics ?? 0)) sharpness=\(String(format: "%.3f", photo.qualityScore?.sharpness ?? 0)) face=\(hasFace)")
        }
        // Prefer scenic/landscape photos (no detected faces) over photos with people.
        // Fall back to all scored photos if no face-free candidates exist.
        let scenicPhotos = scoredPhotos.filter({ ($0.qualityScore?.facePenalty ?? 0) == 0 })
        let candidates = scenicPhotos.isEmpty ? scoredPhotos : scenicPhotos
        let prevCoverId = detail.selectedCoverPhotoIdentifier
        if let bestPhoto = candidates.max(by: { ($0.qualityScore?.totalScore ?? 0) < ($1.qualityScore?.totalScore ?? 0) }),
           let bestPhotoId = bestPhoto.localIdentifier {
            let usedFallback = scenicPhotos.isEmpty && !scoredPhotos.isEmpty
            detail.selectedCoverPhotoIdentifier = bestPhotoId
            print("[CoverPhoto] Updated cover: \(prevCoverId?.prefix(8) ?? "nil")… → \(bestPhotoId.prefix(8))… (score=\(String(format: "%.3f", bestPhoto.qualityScore?.totalScore ?? 0))\(usedFallback ? ", fallback: no scenic photos" : ""))")
        } else {
            print("[CoverPhoto] No scored photos found — keeping initial cover: \(prevCoverId?.prefix(8) ?? "nil")…")
        }
    }

    /// Scores every photo using Vision AI and auto-selects the best per place stop.
    private func applyPhotoQualitySelection(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        await applyPhotoQualitySelection(to: detail, dayIndices: detail.days.indices.map { $0 })
    }

    /// Scores photos and auto-selects best per place stop for the given day indices only.
    private func applyPhotoQualitySelection(to detail: RecapBlogDetail, dayIndices: [Int]) async -> RecapBlogDetail {
        var updated = detail
        let scorer = PhotoQualityScorer.shared
        let daySet = Set(dayIndices)

        for dayIdx in updated.days.indices where daySet.contains(dayIdx) {
            for stopIdx in updated.days[dayIdx].placeStops.indices {
                if Task.isCancelled { return updated }
                let photos = updated.days[dayIdx].placeStops[stopIdx].photos
                let identifiers = photos.compactMap(\.localIdentifier)
                guard !identifiers.isEmpty else { continue }

                let scores = await scorer.scorePhotos(identifiers: identifiers)
                guard !scores.isEmpty else { continue }

                for photoIdx in updated.days[dayIdx].placeStops[stopIdx].photos.indices {
                    let photo = updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx]
                    if let id = photo.localIdentifier, let score = scores[id] {
                        updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx].qualityScore = score
                    }
                }

                let scoredPhotos = updated.days[dayIdx].placeStops[stopIdx].photos
                let topIds = scoredPhotos.autoSelectedIds()
                if !topIds.isEmpty {
                    for photoIdx in updated.days[dayIdx].placeStops[stopIdx].photos.indices {
                        let photo = updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx]
                        updated.days[dayIdx].placeStops[stopIdx].photos[photoIdx].isIncluded = topIds.contains(photo.id)
                    }
                }
            }
        }

        return updated
    }

    /// Loads blog detail, runs quality scoring and auto-selection for the given days, then saves.
    /// Used after injecting newly scanned photos so only good-quality photos are preselected.
    private func applyPhotoQualitySelectionForBlog(sourceTripId: UUID, dayIndices: [Int]) async {
        guard let detail = blogDetailsBySourceId[sourceTripId], !dayIndices.isEmpty else { return }
        let updated = await applyPhotoQualitySelection(to: detail, dayIndices: dayIndices)
        saveBlogDetail(updated, asDraft: true)
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            recents[idx].selectedPhotoCount = updated.days
                .flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
            persistRecents()
        }
    }

    // MARK: - New Moments Scan

    /// Lightweight scan for new photos that could be added to a recent blog.
    /// Returns an empty array if the blog is too old or no new photos are found.
    func scanForNewMoments(blogId: UUID) async -> [MockPhoto] {
        guard let detail = blogDetailsBySourceId[blogId] else { return [] }

        // Determine the blog's latest photo date.
        // allPhotos includes ALL photos in place groups regardless of isIncluded,
        // so the upper bound is based on every photo in the trip (selected or not).
        let allPhotos = detail.days.flatMap(\.placeStops).flatMap(\.photos)
        let latestPhotoDate = allPhotos.map(\.timestamp).max()
        let blogEndDate = detail.days.last?.date
        let scanStart = latestPhotoDate ?? blogEndDate ?? Date.distantPast

        // Only scan for blogs whose last day is within 14 days of today.
        let lastDayDate = detail.days.last?.date ?? Date.distantPast
        let daysSinceLastDay = Calendar.current.dateComponents([.day], from: lastDayDate, to: Date()).day ?? Int.max
        guard daysSinceLastDay <= 14 else { return [] }

        // Upper bound: only photos within 24 hours of the blog's last photo are
        // considered part of this blog. Photos from a separate trip days later
        // belong to a different blog and must not appear here.
        let upperBound = Calendar.current.date(byAdding: .hour, value: 24, to: scanStart) ?? scanStart

        // Apply per-blog cutoff so dismissed photos don't resurface.
        let cutoff = ScanSessionStore.lastBlogNotifiedDate(for: blogId) ?? scanStart

        // Scan photo library from cutoff to upper bound.
        let trips = await PhotoLibraryTripService.shared.scanInDateRange(
            startDate: cutoff,
            endDate: upperBound
        )

        // Collect all photos from scanned trips.
        let scannedPhotos = trips.flatMap { $0.days.flatMap(\.photos) }
        guard !scannedPhotos.isEmpty else { return [] }

        // Deduplicate against photos already in the blog, and enforce the 24-hour
        // upper bound so no photos from a later separate trip slip through.
        let existingIds = Set(allPhotos.compactMap(\.localIdentifier))
        let newPhotos = scannedPhotos.filter { photo in
            photo.timestamp > cutoff
            && photo.timestamp <= upperBound
            && (photo.localIdentifier.map { !existingIds.contains($0) } ?? true)
        }

        return newPhotos.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private Helpers

    private func primaryFromCandidates(_ candidates: [(country: String, order: Int)]) -> String {
        guard !candidates.isEmpty else { return "" }
        var count: [String: (count: Int, firstOrder: Int)] = [:]
        for (country, order) in candidates {
            if let existing = count[country] {
                count[country] = (existing.count + 1, existing.firstOrder)
            } else {
                count[country] = (1, order)
            }
        }
        let sorted = count.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.value.firstOrder < b.value.firstOrder
        }
        return sorted.first?.key ?? ""
    }

    private func seasonFromDetail(_ detail: RecapBlogDetail) -> String? {
        let months = detail.days.flatMap(\.placeStops).flatMap(\.photos).map { Calendar.current.component(.month, from: $0.timestamp) }
        guard !months.isEmpty else { return nil }
        var count: [Int: Int] = [:]
        for m in months { count[m, default: 0] += 1 }
        guard let mostFrequentMonth = count.max(by: { $0.value < $1.value })?.key else { return nil }
        return seasonName(month: mostFrequentMonth)
    }

    private func seasonName(month: Int) -> String {
        switch month {
        case 12, 1, 2: return "Winter"
        case 3, 4, 5: return "Spring"
        case 6, 7, 8: return "Summer"
        case 9, 10, 11: return "Fall"
        default: return "Winter"
        }
    }

    private func primaryCityFromCandidates(_ candidates: [(city: String, order: Int)]) -> String {
        guard !candidates.isEmpty else { return "" }
        var count: [String: (count: Int, firstOrder: Int)] = [:]
        for (city, order) in candidates {
            if let existing = count[city] {
                count[city] = (existing.count + 1, existing.firstOrder)
            } else {
                count[city] = (1, order)
            }
        }
        let sorted = count.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.value.firstOrder < b.value.firstOrder
        }
        return sorted.first?.key ?? ""
    }

    private func primaryCaption(from detail: RecapBlogDetail) -> String? {
        for day in detail.days {
            for stop in day.placeStops {
                if let note = stop.noteText, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return note
                }
            }
        }
        for day in detail.days {
            for stop in day.placeStops {
                for photo in stop.photos {
                    if let caption = photo.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return caption
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Display Helpers

    /// Blogs that have been fully uploaded to the cloud (filtered for current user).
    var cloudPublishedBlogs: [CreatedRecapBlog] {
        guard let userId = AuthService.shared.currentUser?.id else { return [] }
        return recents.filter {
            $0.ownerScope == .account &&
            $0.ownerUserId == userId &&
            isBlogInCloud(blogId: $0.sourceTripId)
        }
    }

    /// Country summaries using only cloud-published blogs (for Profile page).
    var cloudCountrySummaries: [CountryRecapSummary] {
        let published = cloudPublishedBlogs
        let grouped = Dictionary(grouping: published) { blog -> String in
            let name = blog.countryName ?? "Unknown"
            return name.isEmpty || name == "Unknown" ? "Unknown" : name
        }
        return grouped.compactMap { countryName, blogs in
            guard let mostRecent = blogs.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return CountryRecapSummary(
                countryName: countryName,
                mostRecentBlog: mostRecent,
                blogs: blogs.sorted { $0.createdAt > $1.createdAt }
            )
        }
        .sorted { $0.mostRecentBlog.createdAt > $1.mostRecentBlog.createdAt }
    }

    // MARK: - Auth-Aware Display Helpers

    /// Current auth state derived from AuthService for filtering.
    private var currentAuthState: AuthState {
        if let user = AuthService.shared.currentUser {
            return .loggedIn(userId: user.id)
        }
        return .loggedOut
    }

    /// Auth-filtered recents list for views that need the raw filtered array.
    var visibleRecents: [CreatedRecapBlog] {
        visibleBlogs(for: currentAuthState)
    }

    /// For Landing Recents section (newest first, auth-filtered).
    var displayRecents: [CreatedRecapBlog] {
        visibleRecents.sorted {
            let d1 = $0.lastEditedAt ?? $0.createdAt
            let d2 = $1.lastEditedAt ?? $1.createdAt
            return d1 > d2
        }
    }

    /// Group recents by country for Profile (auth-filtered).
    var countrySummaries: [CountryRecapSummary] {
        let filtered = visibleRecents
        let grouped = Dictionary(grouping: filtered) { blog -> String in
            let name = blog.countryName ?? "Unknown"
            return name.isEmpty || name == "Unknown" ? "Unknown" : name
        }
        return grouped.compactMap { countryName, blogs in
            guard let mostRecent = blogs.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return CountryRecapSummary(
                countryName: countryName,
                mostRecentBlog: mostRecent,
                blogs: blogs.sorted { $0.createdAt > $1.createdAt }
            )
        }
        .sorted { $0.mostRecentBlog.createdAt > $1.mostRecentBlog.createdAt }
    }

    /// Derived list of visited places aggregated across all visible blogs (latest-first).
    /// - Note: Uses persisted blogDetailsBySourceId only (no on-the-fly rebuild).
    var visitedPlaces: [VisitedPlaceSummary] {
        let blogs = visibleRecents
        var byKey: [String: (place: VisitedPlaceSummary, latest: Date)] = [:]

        for blog in blogs {
            guard let detail = blogDetailsBySourceId[blog.sourceTripId] else { continue }
            let country = (detail.countryName?.isEmpty == false ? detail.countryName : blog.countryName) ?? "Unknown"
            let relatedRef = VisitedPlaceSummary.RelatedBlogRef(
                blogId: blog.sourceTripId,
                blogTitle: blog.title,
                blogDate: blog.tripStartDate ?? blog.createdAt
            )

            for day in detail.days {
                for stop in day.placeStops {
                    let included = stop.photos.filter(\.isIncluded)
                    guard !included.isEmpty else { continue }

                    let latestVisit = included.map(\.timestamp).max() ?? (blog.tripEndDate ?? blog.createdAt)
                    let year = Calendar.current.component(.year, from: latestVisit)
                    let placeName = stop.placeTitle
                    let city = stop.placeSubtitle ?? ""

                    let placeKey: String = {
                        if let idx = stop.cloudPlaceIndex {
                            return "cloud_\(idx)"
                        }
                        if let vtd = stop.visitedTimeDigitized, !vtd.isEmpty {
                            return "vtd_\(vtd)"
                        }
                        let dayStamp = day.date.timeIntervalSince1970
                        return "local_\(blog.sourceTripId.uuidString)_\(Int(dayStamp))_\(stop.orderIndex)"
                    }()

                    let placeCaption = stop.noteText
                    let photoCaptions = included.compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    let newSummary = VisitedPlaceSummary(
                        placeId: placeKey,
                        placeName: placeName,
                        city: city,
                        country: country,
                        categoryRawValue: stop.placeCategory,
                        latestVisitDate: latestVisit,
                        year: year,
                        photos: included.sorted(by: { $0.timestamp > $1.timestamp }),
                        placeCaption: placeCaption,
                        photoCaptions: photoCaptions,
                        relatedBlogs: [relatedRef]
                    )

                    if var existing = byKey[placeKey]?.place {
                        let mergedLatest = max(existing.latestVisitDate, newSummary.latestVisitDate)
                        let mergedPhotos = (existing.photos + newSummary.photos)
                            .uniqued(by: { $0.id })
                            .sorted(by: { $0.timestamp > $1.timestamp })

                        let mergedPhotoCaptions = (existing.photoCaptions + newSummary.photoCaptions)
                            .filter { !$0.isEmpty }
                        let mergedBlogs = (existing.relatedBlogs + newSummary.relatedBlogs)
                            .uniqued(by: { $0.blogId })
                            .sorted(by: { $0.blogDate > $1.blogDate })

                        let caption = (existing.placeCaption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                            ? existing.placeCaption
                            : newSummary.placeCaption

                        existing = VisitedPlaceSummary(
                            placeId: existing.placeId,
                            placeName: existing.placeName,
                            city: existing.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? newSummary.city : existing.city,
                            country: existing.country,
                            categoryRawValue: existing.categoryRawValue ?? newSummary.categoryRawValue,
                            latestVisitDate: mergedLatest,
                            year: Calendar.current.component(.year, from: mergedLatest),
                            photos: mergedPhotos,
                            placeCaption: caption,
                            photoCaptions: mergedPhotoCaptions,
                            relatedBlogs: mergedBlogs
                        )
                        byKey[placeKey] = (existing, mergedLatest)
                    } else {
                        byKey[placeKey] = (newSummary, latestVisit)
                    }
                }
            }
        }

        return byKey.values
            .map(\.place)
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        var out: [Element] = []
        out.reserveCapacity(count)
        for e in self {
            let k = key(e)
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(e)
        }
        return out
    }
}

/// One card on the Profile: country name, last trip date, cover from most recent trip in that country.
struct CountryRecapSummary: Identifiable {
    let countryName: String
    let mostRecentBlog: CreatedRecapBlog
    let blogs: [CreatedRecapBlog]
    var id: String { countryName }
}
