//
//  CreatedRecapBlogStore.swift
//  fastblog
//

import Combine
import CoreLocation
import Foundation
import SwiftUI

// MARK: - Blog Ownership & Sync Enums

/// Whether the blog belongs to an anonymous (logged-out) session or a signed-in account.
enum OwnerScope: String, Codable, Sendable {
    case anonymous
    case account
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
    /// Date ranges of active drafts (from TripsViewModel) to exclude from scans. Written by TripsViewModel.updateOccupiedRanges().
    var draftOccupiedRanges: [(start: Date, end: Date)] = []
    /// When true, TripsViewModel clears trips and re-runs default scan (e.g. after archive rules change).
    @Published var needsRescan: Bool = false
    private var tripDraftsBySourceId: [UUID: TripDraft] = [:]
    /// Persisted editable blog details; Save in RecapBlogPageView writes here.
    private var blogDetailsBySourceId: [UUID: RecapBlogDetail] = [:]
    private let clusteringService = PlaceStopClusteringService()

    // MARK: - Persistence

    private static let storageDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CreatedBlogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
        recents[idx] = CreatedRecapBlog(
            id: old.id,
            sourceTripId: old.sourceTripId,
            title: detail.title,
            createdAt: old.createdAt,
            coverImageName: detail.coverTheme,
            coverAssetIdentifier: detail.selectedCoverPhotoIdentifier,
            selectedPhotoCount: old.selectedPhotoCount,
            countryName: country,
            tripDateRangeText: old.tripDateRangeText,
            lastEditedAt: asDraft ? old.lastEditedAt : Date(),
            tripStartDate: old.tripStartDate,
            tripEndDate: old.tripEndDate,
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
        recents.removeAll { $0.sourceTripId == sourceTripId }
        blogDetailsBySourceId.removeValue(forKey: sourceTripId)
        if pendingRecapCreated { pendingRecapCreated = false }
        persistRecents()
        persistBlogDetails()
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
        persistRecents()
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
            let placeByIndex: [Int: ServerPlaceRecord] = Dictionary(
                uniqueKeysWithValues: allPlaces.map { ($0.placeIndex, $0) }
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
                stops.append(PlaceStop(
                    orderIndex: stopIdx,
                    placeTitle: serverPlace.placeName ?? "Stop \(stopIdx + 1)",
                    placeSubtitle: serverPlace.visitedCity,
                    representativeLocation: coord,
                    photos: photos,
                    noteText: noteText,
                    cloudPlaceIndex: serverPlace.placeIndex,
                    visitedTimeDigitized: serverPlace.visitedTimeDigitized
                ))
            }

            guard !stops.isEmpty else { continue }
            days.append(RecapBlogDay(dayIndex: dayIdx, date: dayDate, placeStops: stops))
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
            let dayDate = day.photos.filter(\.isSelected).map(\.timestamp).min().map { calendar.startOfDay(for: $0) } ?? Date()
            days.append(RecapBlogDay(dayIndex: day.dayIndex, date: dayDate, placeStops: placeStops))
        }

        // Default cover: trip's cover asset or first included photo's localIdentifier.
        let firstPhotoId = days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).compactMap(\.localIdentifier).first
        let coverId = trip.coverAssetIdentifier ?? firstPhotoId
        return RecapBlogDetail(id: trip.id, title: trip.title, days: days, coverTheme: trip.coverTheme, selectedCoverPhotoIdentifier: coverId)
    }

    /// Builds blog detail, resolves place names from reverse-geocoding, generates a title, and scores photos via Vision AI.
    func buildBlogDetailAsync(from trip: TripDraft) async -> RecapBlogDetail {
        var detail = buildBlogDetail(from: trip)
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, order: Int)] = []
        var order = 0

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                let stop = detail.days[dayIdx].placeStops[stopIdx]
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

        // Score photos with iOS Vision AI and auto-select best per place stop.
        detail = await applyPhotoQualitySelection(to: detail)

        return detail
    }

    /// Scores every photo using Vision AI, then auto-selects the best per place stop.
    private func applyPhotoQualitySelection(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        var updated = detail
        let scorer = PhotoQualityScorer.shared

        for dayIdx in updated.days.indices {
            for stopIdx in updated.days[dayIdx].placeStops.indices {
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
}

/// One card on the Profile: country name, last trip date, cover from most recent trip in that country.
struct CountryRecapSummary: Identifiable {
    let countryName: String
    let mostRecentBlog: CreatedRecapBlog
    let blogs: [CreatedRecapBlog]
    var id: String { countryName }
}
