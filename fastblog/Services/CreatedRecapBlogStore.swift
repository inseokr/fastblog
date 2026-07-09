//
//  CreatedRecapBlogStore.swift
//  fastblog
//

import Combine
import CoreLocation
import Foundation

extension Notification.Name {
    /// Posted when a created blog is removed locally (`userInfo["sourceTripId"]: UUID`).
    static let bloggoCreatedBlogDeleted = Notification.Name("bloggo.createdBlogDeleted")
}
import Photos
import SwiftUI

extension Notification.Name {
    /// Posted when persisted trip drafts change (e.g. after split) so TripsViewModel can refresh in-memory drafts.
    static let tripDraftsDidChangeInStore = Notification.Name("tripDraftsDidChangeInStore")
}

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
        /// The place row in the blog timeline; used to scroll there when opening from Places Visited.
        let placeStopId: UUID
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
    /// True when this place comes from everyday moments only (not linked to a trip blog).
    var isEverydayOnly: Bool

    var id: String { placeId }

    init(
        placeId: String,
        placeName: String,
        city: String,
        country: String,
        categoryRawValue: String?,
        latestVisitDate: Date,
        year: Int,
        photos: [RecapPhoto],
        placeCaption: String?,
        photoCaptions: [String],
        relatedBlogs: [RelatedBlogRef],
        isEverydayOnly: Bool = false
    ) {
        self.placeId = placeId
        self.placeName = placeName
        self.city = city
        self.country = country
        self.categoryRawValue = categoryRawValue
        self.latestVisitDate = latestVisitDate
        self.year = year
        self.photos = photos
        self.placeCaption = placeCaption
        self.photoCaptions = photoCaptions
        self.relatedBlogs = relatedBlogs
        self.isEverydayOnly = isEverydayOnly
    }

    var displayName: String {
        Self.displayTitle(from: placeName)
    }

    static func displayTitle(from rawPlaceName: String) -> String {
        let trimmed = rawPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "unknown" || trimmed == "Unknown Place" {
            return "Unknown Place"
        }
        if PlacePlaceholderNaming.isResolvablePlaceholder(trimmed) {
            return PlacePlaceholderNaming.unsetPlaceDisplayTitle
        }
        return trimmed.cleanedAsPlaceTitle
    }

    /// My Places grid title — drops redundant `Near ` so two-column cells don't truncate to "Near …".
    var compactListTitle: String {
        Self.compactListTitle(from: displayName)
    }

    /// Grid/map label: prefers hero capture `meta.json` when it already has a resolved name (O(1); no blog scan).
    func gridListTitle() -> String {
        let heroMeta = heroPhoto.flatMap { photo -> String? in
            guard let raw = AppCapturePhotoService.shared.metadata(captureId: photo.id)?.placeTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !PlacePlaceholderNaming.isResolvablePlaceholder(raw) else { return nil }
            return raw
        }
        let resolved = heroMeta.map { Self.displayTitle(from: $0) } ?? displayName
        return Self.compactListTitle(from: resolved)
    }

    static func compactListTitle(from displayName: String) -> String {
        if displayName == PlacePlaceholderNaming.unsetPlaceDisplayTitle { return displayName }
        guard displayName.hasPrefix("Near ") else { return displayName }
        let suffix = String(displayName.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty, suffix != "Unknown Place" else { return displayName }
        return suffix
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

    var representativeCoordinate: CLLocationCoordinate2D? {
        photos.compactMap { $0.location?.clCoordinate }.first
    }

    /// True when two My Places rows refer to the same visit (shared photos or same resolved name + GPS cluster).
    func isSamePlace(as other: VisitedPlaceSummary) -> Bool {
        if sharesPhotos(with: other) { return true }

        let titleA = gridListTitle()
        let titleB = other.gridListTitle()
        guard titleA.caseInsensitiveCompare(titleB) == .orderedSame else { return false }
        guard titleA != PlacePlaceholderNaming.unsetPlaceDisplayTitle,
              titleA != "Unknown Place" else { return false }
        guard let coordA = representativeCoordinate,
              let coordB = other.representativeCoordinate else { return false }
        let locA = CLLocation(latitude: coordA.latitude, longitude: coordA.longitude)
        let locB = CLLocation(latitude: coordB.latitude, longitude: coordB.longitude)
        return locA.distance(from: locB) <= ScanConfig.placeClusterMeters
    }

    /// Merges an everyday-only row into a blog-linked row without duplicating photos.
    func mergedWithEveryday(_ everyday: VisitedPlaceSummary) -> VisitedPlaceSummary {
        let mergedPhotos = (photos + everyday.photos)
            .uniqued(by: { $0.localIdentifier ?? $0.id.uuidString })
            .sorted(by: { $0.timestamp > $1.timestamp })
        let mergedLatest = max(latestVisitDate, everyday.latestVisitDate)
        let mergedName = Self.preferredPlaceName(
            primary: placeName,
            secondary: everyday.placeName,
            preferSecondary: everyday.latestVisitDate > latestVisitDate
        )
        return VisitedPlaceSummary(
            placeId: placeId,
            placeName: mergedName,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? everyday.city : city,
            country: country,
            categoryRawValue: categoryRawValue ?? everyday.categoryRawValue,
            latestVisitDate: mergedLatest,
            year: Calendar.current.component(.year, from: mergedLatest),
            photos: mergedPhotos,
            placeCaption: placeCaption ?? everyday.placeCaption,
            photoCaptions: (photoCaptions + everyday.photoCaptions).filter { !$0.isEmpty },
            relatedBlogs: relatedBlogs,
            isEverydayOnly: relatedBlogs.isEmpty && isEverydayOnly && everyday.isEverydayOnly
        )
    }

    private func sharesPhotos(with other: VisitedPlaceSummary) -> Bool {
        let selfIds = Set(photos.map(\.id))
        let otherIds = Set(other.photos.map(\.id))
        if !selfIds.isDisjoint(with: otherIds) { return true }
        let selfLocalIds = Set(photos.compactMap(\.localIdentifier).filter { !$0.isEmpty })
        let otherLocalIds = Set(other.photos.compactMap(\.localIdentifier).filter { !$0.isEmpty })
        return !selfLocalIds.isDisjoint(with: otherLocalIds)
    }

    private static func preferredPlaceName(primary: String, secondary: String, preferSecondary: Bool) -> String {
        let primaryResolved = !PlacePlaceholderNaming.isResolvablePlaceholder(primary)
        let secondaryResolved = !PlacePlaceholderNaming.isResolvablePlaceholder(secondary)
        if preferSecondary {
            if secondaryResolved { return secondary }
            if primaryResolved { return primary }
            return secondary
        }
        if primaryResolved { return primary }
        if secondaryResolved { return secondary }
        return primary
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
    /// True after the user taps Save on the recap editor (`saveBlogDetail` with `asDraft: false`). Used for guest save limits; not set by autosave or caption-only patches.
    var hasCommittedRecapSave: Bool
    /// True after `RecapBlogPageView` has been dismissed at least once. Draft-only blogs keep `lastEditedAt == nil`; this avoids showing the first-visit "Save as Draft?" exit sheet on every reopen when nothing changed.
    var hasCompletedInitialRecapExit: Bool

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
        lastAutosaveAt: Date? = nil,
        hasCommittedRecapSave: Bool = false,
        hasCompletedInitialRecapExit: Bool = false
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
        self.hasCommittedRecapSave = hasCommittedRecapSave
        self.hasCompletedInitialRecapExit = hasCompletedInitialRecapExit
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
        hasCommittedRecapSave = try c.decodeIfPresent(Bool.self, forKey: .hasCommittedRecapSave) ?? false
        hasCompletedInitialRecapExit = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialRecapExit) ?? false
    }
}

// MARK: - Store

@MainActor
final class CreatedRecapBlogStore: ObservableObject {
    static let shared = CreatedRecapBlogStore()

    @Published private(set) var recents: [CreatedRecapBlog] = []
    /// Always false — data loads synchronously in init(). Exposed so TripsViewModel can observe it.
    @Published private(set) var isLoading = false
    /// When true, landing shows the "Your blog is ready" banner; clear after 5-7 sec.
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
    /// Incremented when a guest attempts a second recap Save (distinct blog); RecapBlogPageView presents the sign-in sheet.
    @Published private(set) var guestSecondSaveBlockedSignal: UInt64 = 0

    /// Undo info for the last split operation (not persisted).
    struct SplitUndoInfo {
        let keepId: UUID
        let newId: UUID
        let originalTitle: String
    }
    @Published var lastSplitUndoInfo: SplitUndoInfo?

    /// Snapshot to restore after the last merge-from-manage-flow (not persisted).
    struct MergeUndoInfo {
        let recentsSnapshot: [CreatedRecapBlog]
        let keepId: UUID
        let absorbId: UUID
        let keepDetail: RecapBlogDetail
        let absorbDetail: RecapBlogDetail
        let keepTripDraft: TripDraft?
        let absorbTripDraft: TripDraft?
    }
    @Published var lastMergeUndoInfo: MergeUndoInfo?
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

        // Guest save limit: infer legacy "saved from recap" from lastEditedAt for anonymous blogs.
        var didMigrateCommittedSave = false
        for i in recents.indices where recents[i].ownerScope == .anonymous {
            if !recents[i].hasCommittedRecapSave, recents[i].lastEditedAt != nil {
                recents[i].hasCommittedRecapSave = true
                didMigrateCommittedSave = true
            }
        }
        if didMigrateCommittedSave { persistRecents() }

        refreshRecentsDateMetadataFromBlogDetails()
        refreshRecentsCountryFromBlogDetails()
        backfillMissingCountriesIfNeeded()
        stripEverydayCapturesFromAllBlogs()
    }

    /// Merges blog days that share the same EXIF digitized calendar date (fixes duplicate "May 22" rows after flights).
    private func consolidateAllBlogDetailsDuplicateCalendarDays() {
        var didChange = false
        for (id, detail) in blogDetailsBySourceId {
            let consolidated = detail.consolidatingDuplicateCalendarDays()
            guard consolidated.days.count != detail.days.count else { continue }
            blogDetailsBySourceId[id] = consolidated
            didChange = true
        }
        if didChange { persistBlogDetails() }
    }

    /// Realigns landing-page date ranges with day row headers (fixes legacy off-by-one tripStartDate/tripEndDate).
    private func refreshRecentsDateMetadataFromBlogDetails() {
        var didChange = false
        for idx in recents.indices {
            guard let detail = blogDetailsBySourceId[recents[idx].sourceTripId],
                  !detail.days.isEmpty else { continue }
            let start = RecapBlogDay.alignedTripStartDate(from: detail.days)
            let end = RecapBlogDay.alignedTripEndDate(from: detail.days)
            let range = Self.formatDateRange(start: start, end: end)
            if recents[idx].tripStartDate != start || recents[idx].tripEndDate != end || recents[idx].tripDateRangeText != range {
                recents[idx].tripStartDate = start
                recents[idx].tripEndDate = end
                recents[idx].tripDateRangeText = range
                didChange = true
            }
        }
        if didChange { persistRecents() }
    }

    private func persistRecents() {
        guard let data = try? Self.encoder.encode(recents) else { return }
        Task.detached(priority: .utility) { try? data.write(to: Self.recentsURL, options: .atomic) }
    }

    private func persistTripDrafts() {
        guard let data = try? Self.encoder.encode(tripDraftsBySourceId) else { return }
        Task.detached(priority: .utility) { try? data.write(to: Self.tripDraftsURL, options: .atomic) }
    }

    private func persistBlogDetails() {
        guard let data = try? Self.encoder.encode(blogDetailsBySourceId) else { return }
        Task.detached(priority: .utility) { try? data.write(to: Self.blogDetailsURL, options: .atomic) }
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

    /// Materializes a trip received via nearby share (new identities + bloggo-capture assets) and adds it like a new blog draft.
    func importNearbySharedTrip(manifest: TripShareManifestV1, images: [Data], reelsByOrder: [Int: Data] = [:]) throws {
        let trip = try TripShareImporter.makeTripDraft(manifest: manifest, images: images, reelsByOrder: reelsByOrder)
        addCreatedBlog(trip: trip)
    }

    /// Registers a blog received via Blog Drop (cloud-based sharing). All stories are already
    /// embedded in the `RecapBlogDetail` produced by `BlogDropService.importDrop`.
    func importBlogDrop(_ importedDetail: RecapBlogDetail) {
        guard let trip = TripShareBlogDraftBuilder.tripDraft(from: importedDetail) else { return }
        addCreatedBlog(trip: trip)
        saveBlogDetail(importedDetail, asDraft: false)
    }

    /// Materializes a recap blog received via nearby share (preserves captions and stories) and adds it like a new blog.
    /// - Note: We create the `CreatedRecapBlog` entry using a derived `TripDraft`, then overwrite the stored `RecapBlogDetail`
    ///   so the imported detail (captions/stories/place notes) is preserved exactly.
    func importNearbySharedRecapBlog(
        manifest: TripShareRecapManifestV1,
        images: [Data],
        reelsByOrder: [Int: Data] = [:]
    ) throws -> [String] {
        let importedDetail = try TripShareRecapImporter.makeRecapBlogDetail(
            manifest: manifest,
            images: images,
            reelsByOrder: reelsByOrder
        )
        guard let trip = TripShareBlogDraftBuilder.tripDraft(from: importedDetail) else {
            // Should not happen: importer always sets local identifiers for exported photos.
            throw TripShareRecapExportError.noExportableIncludedPhotos
        }
        addCreatedBlog(trip: trip)
        saveBlogDetail(importedDetail, asDraft: false)
        let captureIds = importedDetail.allIncludedPhotos.compactMap(\.localIdentifier)
        return Array(captureIds.prefix(manifest.photos.count))
    }

    /// Restores list metadata from `createdRecapBlog.json` after a ZIP backup import.
    func applyBlogBackupCreatedRecapPayload(_ payload: BlogBackupCreatedRecapPayload, sourceTripId: UUID) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) else { return }
        let old = recents[idx]
        recents[idx] = CreatedRecapBlog(
            id: old.id,
            sourceTripId: old.sourceTripId,
            title: payload.title,
            createdAt: payload.createdAt,
            coverImageName: payload.coverImageName,
            coverAssetIdentifier: old.coverAssetIdentifier,
            selectedPhotoCount: payload.selectedPhotoCount,
            countryName: payload.countryName,
            tripDateRangeText: payload.tripDateRangeText,
            lastEditedAt: payload.lastEditedAt,
            tripStartDate: payload.tripStartDate,
            tripEndDate: payload.tripEndDate,
            totalPlaceVisitCount: payload.totalPlaceVisitCount,
            tripDurationDays: payload.tripDurationDays,
            caption: payload.caption,
            blogKey: nil,
            ownerScope: old.ownerScope,
            ownerUserId: old.ownerUserId,
            cloudId: nil,
            cloudState: .localOnly,
            syncStatus: .localOnly,
            lastAutosaveAt: old.lastAutosaveAt,
            hasCommittedRecapSave: payload.hasCommittedRecapSave,
            hasCompletedInitialRecapExit: payload.hasCompletedInitialRecapExit
        )
        persistRecents()
    }

    /// Call when user completes the Create Blog sequence (before showing RecapSavedView).
    func addCreatedBlog(trip: TripDraft) {
        let blogTrip = tripDraftExcludingEverydayCaptures(trip)
        guard blogTrip.days.contains(where: { $0.photos.contains(where: \.isSelected) }) else { return }
        let startDate = blogTrip.earliestDate
        let endDate = blogTrip.latestDate
        var tempDetail = buildBlogDetail(from: blogTrip)
        if let country = trip.primaryCountryDisplayName, isValidCountryName(country) {
            tempDetail.countryName = country
        }
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
        tripDraftsBySourceId[trip.id] = blogTrip
        // Cache the blog detail so that on the next scan, existingIds is populated
        // correctly and photos already in the blog are not flagged as "new moments".
        blogDetailsBySourceId[trip.id] = tempDetail
        // Set the per-blog notification cutoff to the latest photo timestamp so that
        // the very next scan does not re-surface photos already in the blog.
        //
        // Important: `RecapBlogPageView` scans using the Trip's `sourceTripId` (not
        // `CreatedRecapBlog.id`), so we persist the cutoff under BOTH UUIDs to keep
        // Trips-flow + Blog-page scans consistent.
        if let maxDate = tempDetail.days.flatMap(\.placeStops).flatMap(\.photos).map(\.timestamp).max() {
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blog.id)
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: trip.id) // RecapBlogPageView uses this
        }
        recents.insert(blog, at: 0)
        pendingRecapCreated = true
        let locationLabel = tempDetail.days.first?.placeStops.first?.placeTitle ?? ""
        AppAnalytics.shared.trackEvent(
            name: "blog_created",
            properties: [
                "sourceTripId": trip.id.uuidString,
                "blogTitle": trip.title,
                "countryName": trip.primaryCountryDisplayName ?? "",
                "locationLabel": locationLabel,
            ],
            context: AnalyticsContext(blogId: trip.id.uuidString)
        )
        persistRecents()
        persistTripDrafts()
        // Persist details immediately so the blog survives a background kill.
        persistBlogDetails()
        unlinkEverydayCapturesNowInBlog(blogTrip.days.flatMap(\.photos).compactMap(\.localIdentifier))
        BlogMenuIndicatorStore.shared.signalNewBlog(sourceTripId: trip.id)
    }

    /// Creates a trip blog from everyday (My Places) captures and removes them from the everyday store.
    @discardableResult
    func createTripBlogFromEverydayPhotos(_ photos: [RecapPhoto], preferredTitle: String? = nil) -> UUID? {
        let identifiers = Set(photos.compactMap(\.localIdentifier))
        let mockPhotos = EverydayMomentsStore.shared.promoteCapturesToBlog(identifiers: identifiers)
        guard !mockPhotos.isEmpty else { return nil }

        let cal = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateStyle = .medium
        let byDay = Dictionary(grouping: mockPhotos) { cal.startOfDay(for: $0.timestamp) }
        let sortedDays = byDay.sorted { $0.key < $1.key }
        let days: [TripDay] = sortedDays.enumerated().map { index, pair in
            TripDay(
                dayIndex: index,
                dateText: dateFormatter.string(from: pair.key),
                photos: pair.value.sorted { $0.timestamp < $1.timestamp }
            )
        }
        let tripId = UUID()
        let locationName = mockPhotos.first?.locationName ?? "Captured Moment"
        let countryName = mockPhotos.first?.countryName
        let title = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredTitle!
            : (locationName != "Captured Moment" ? locationName : "Trip")
        let dateRangeStr: String
        if let first = sortedDays.first?.key, let last = sortedDays.last?.key {
            dateRangeStr = first == last
                ? dateFormatter.string(from: first)
                : "\(dateFormatter.string(from: first)) – \(dateFormatter.string(from: last))"
        } else {
            dateRangeStr = dateFormatter.string(from: Date())
        }
        let trip = TripDraft(
            id: tripId,
            title: title,
            dateRangeText: dateRangeStr,
            days: days,
            coverImageName: "camera.fill",
            isScannedFromDefaultRange: false,
            draftCreatedAgoText: "Draft created recently",
            daysSeasonText: "",
            coverTheme: "default",
            coverAssetIdentifier: mockPhotos.first?.localIdentifier
        )
        addCreatedBlog(trip: trip)
        return tripId
    }

    /// Dismiss the "Your blog is ready" banner.
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
    /// Pass `excludingSourceTripIds` to omit specific blogs (e.g. active on-the-go trip) so the library scan can still find Photos assets on those calendar days.
    func occupiedDateRanges(excludingSourceTripIds: Set<UUID> = []) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current

        let blogRanges: [(start: Date, end: Date)] = visibleRecents.compactMap { blog in
            guard !excludingSourceTripIds.contains(blog.sourceTripId) else { return nil }
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

    /// Latest photo timestamp in saved blog detail (any stop). Nil if detail not loaded.
    func latestPhotoTimestamp(forSourceTripId sourceTripId: UUID) -> Date? {
        guard let detail = blogDetailsBySourceId[sourceTripId] else { return nil }
        let stamps = detail.days.flatMap(\.placeStops).flatMap(\.photos).map(\.timestamp)
        return stamps.max()
    }

    /// In-app capture identifiers (`bloggo-capture:`) present in any visible recap blog.
    /// Used to skip captures that are already part of a saved blog when merging Bloggo captures into trip drafts.
    func allInAppCaptureIdentifiersInVisibleBlogs() -> Set<String> {
        var ids = Set<String>()
        for blog in visibleRecents {
            guard let detail = blogDetailsBySourceId[blog.sourceTripId] else { continue }
            for lid in detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier) {
                guard lid.hasPrefix(AppCapturePhotoService.prefix) else { continue }
                ids.insert(lid)
            }
        }
        return ids
    }

    /// Photos library asset ids (`PHAsset.localIdentifier`) present in any visible recap blog.
    /// Excludes in-app captures (`bloggo-capture:`) so we can tell when a scanned trip has library photos not yet in a blog.
    func allPhotoLibraryLocalIdentifiersInVisibleBlogs() -> Set<String> {
        var ids = Set<String>()
        for blog in visibleRecents {
            guard let detail = blogDetailsBySourceId[blog.sourceTripId] else { continue }
            for lid in detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier) {
                guard !lid.hasPrefix(AppCapturePhotoService.prefix) else { continue }
                ids.insert(lid)
            }
        }
        return ids
    }

    /// True when `TripMatchingService` would hide this draft as a duplicate of a saved blog **and**
    /// the draft's library photos are accounted for by an existing blog (fully, mostly, or by the
    /// matching blog being an in-app-capture-only blog whose iPhone counterpart this draft is).
    func isDraftRedundantWithSavedBlogs(_ draft: TripDraft) -> Bool {
        guard TripMatchingService.isTripSaved(draft: draft, against: visibleRecents) else { return false }
        let libraryIds = draft.days.flatMap(\.photos).compactMap(\.localIdentifier)
            .filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
        // A trip whose photos are exclusively in-app captures is never redundant with library-backed blogs.
        if libraryIds.isEmpty { return false }

        // If the matched blog was built entirely from in-app captures (no PHAsset photos),
        // this draft is the iPhone camera counterpart of the same trip.
        // Suppress it so New Moments handles routing, not Tap to Blog.
        for blog in visibleRecents where TripMatchingService.isTripSaved(draft: draft, against: [blog]) {
            if let detail = blogDetailsBySourceId[blog.sourceTripId] {
                let hasLibraryPhoto = detail.days.flatMap(\.placeStops).flatMap(\.photos)
                    .compactMap(\.localIdentifier)
                    .contains { !$0.hasPrefix(AppCapturePhotoService.prefix) }
                if !hasLibraryPhoto { return true }
            }
        }

        let known = allPhotoLibraryLocalIdentifiersInVisibleBlogs()
        // All photos already in a blog — clean duplicate.
        if libraryIds.allSatisfy({ known.contains($0) }) { return true }
        // Majority overlap: most photos are in the blog but one extra day remains (e.g. Day 4
        // from iPhone camera when Bloggo camera blog only covered Days 1–3).
        let matchedCount = libraryIds.filter { known.contains($0) }.count
        return Double(matchedCount) / Double(libraryIds.count) >= 0.60
    }

    /// TripDraft snapshot for opening BlogPreviewView. Nil if not found.
    func tripDraft(for sourceTripId: UUID) -> TripDraft? {
        tripDraftsBySourceId[sourceTripId]
    }

    /// All persisted trip drafts (e.g. split parts stored after `splitUnsavedTrip`).
    func allTripDrafts() -> [TripDraft] {
        Array(tripDraftsBySourceId.values)
    }

    /// Returns a trip draft with photo selection matching the current blog content (for Edit → photo selection flow). Nil if no draft.
    func tripDraftApplyingBlogSelection(blogId: UUID) -> TripDraft? {
        guard var trip = tripDraftsBySourceId[blogId] else { return nil }
        let includedIds: Set<UUID>
        if let detail = blogDetailsBySourceId[blogId] {
            includedIds = Set(detail.days.flatMap { day in day.placeStops.flatMap { stop in stop.photos.filter(\.isIncluded).map(\.id) } })
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
                ownerUserId: old.ownerUserId,
                hasCommittedRecapSave: old.hasCommittedRecapSave,
                hasCompletedInitialRecapExit: old.hasCompletedInitialRecapExit
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

    /// Updates the cover photo of a blog identified by its source trip ID.
    func updateCoverAsset(sourceTripId: UUID, localIdentifier: String) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) else { return }
        recents[idx].coverAssetIdentifier = localIdentifier
        persistRecents()
    }

    /// Injects newly scanned photos into an existing blog's RecapBlogDetail.
    /// Each photo is matched to the appropriate RecapBlogDay by EXIF/capture calendar date, and within
    /// that day to the closest PlaceStop by time gap (≤ gapHoursNewSegment). If no close
    /// stop exists, a new stop is appended to the day. New days are created when needed.
    /// The updated detail is saved automatically.
    /// `yyyy-MM-dd` calendar day per photo using EXIF capture offset when available (same as library scan).
    private func calendarDayKeys(for photos: [MockPhoto]) async -> [UUID: String] {
        var keys: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, String).self) { group in
            for photo in photos {
                group.addTask {
                    let key = await Self.calendarDayKey(for: photo)
                    return (photo.id, key)
                }
            }
            for await (id, key) in group {
                keys[id] = key
            }
        }
        return keys
    }

    private static func calendarDayKey(for photo: MockPhoto) async -> String {
        if let lid = photo.localIdentifier,
           !lid.hasPrefix(AppCapturePhotoService.prefix) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [lid], options: nil)
            if let asset = result.firstObject {
                let tz = await APIManager.getLocalTimeZone(for: asset) ?? .current
                return TripCalendarDayKey.from(date: photo.timestamp, timeZone: tz)
            }
        }
        return TripCalendarDayKey.from(date: photo.timestamp)
    }

    func injectPhotos(
        _ newPhotos: [MockPhoto],
        intoSourceTripId sourceTripId: UUID,
        notifyMenuIndicator: Bool = true
    ) {
        guard !newPhotos.isEmpty else { return }
        Task {
            await injectPhotosAsync(
                newPhotos,
                intoSourceTripId: sourceTripId,
                notifyMenuIndicator: notifyMenuIndicator
            )
        }
    }

    /// Awaits injection so callers can navigate to the correct day after photos are in the blog.
    func injectPhotosAndWait(
        _ newPhotos: [MockPhoto],
        intoSourceTripId sourceTripId: UUID,
        notifyMenuIndicator: Bool = true
    ) async {
        guard !newPhotos.isEmpty else { return }
        await injectPhotosAsync(
            newPhotos,
            intoSourceTripId: sourceTripId,
            notifyMenuIndicator: notifyMenuIndicator
        )
    }

    /// Injects photos grouped by capture-timezone calendar day (same rule as library scan / digitizedTime).
    private func injectPhotosAsync(
        _ newPhotos: [MockPhoto],
        intoSourceTripId sourceTripId: UUID,
        notifyMenuIndicator: Bool
    ) async {
        guard !newPhotos.isEmpty else { return }
        guard var detail = blogDetailsBySourceId[sourceTripId]
                ?? tripDraftsBySourceId[sourceTripId].map({ buildBlogDetail(from: $0) }) else { return }

        let gapLimit: TimeInterval = Double(ScanConfig.gapHoursNewSegment) * 3600
        let locationLimit: Double = ScanConfig.placeClusterMeters

        // Deduplicate against photos already in the blog.
        let existingIds = Set(detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier))
        let photos = newPhotos.filter { photo in
            guard let lid = photo.localIdentifier, !lid.isEmpty else { return false }
            guard !existingIds.contains(lid) else { return false }
            return !EverydayMomentsStore.shared.containsCapture(identifier: lid)
        }
        guard !photos.isEmpty else { return }

        let dayKeys = await calendarDayKeys(for: photos)
        let byDay = Dictionary(grouping: photos) { dayKeys[$0.id] ?? TripCalendarDayKey.from(date: $0.timestamp) }

        var modifiedDayIndices: Set<Int> = []
        /// New stops that need reverse-geocode — keyed by `PlaceStop.id` so reordering below does not break lookups.
        var newStopsToGeocode: [(dayIdx: Int, stopId: UUID)] = []

        for (dayKey, dayPhotos) in byDay.sorted(by: { $0.key < $1.key }) {
            let dayDate = TripCalendarDayKey.canonicalDate(from: dayKey) ?? dayPhotos.map(\.timestamp).min() ?? Date()
            var dayIdx = detail.days.firstIndex(where: { $0.storyBookCalendarDayKey == dayKey })
            if dayIdx == nil {
                let newDay = RecapBlogDay(dayIndex: 0, date: dayDate, placeStops: [])
                detail.days.append(newDay)
                detail.days.sort { $0.date < $1.date }
                for i in detail.days.indices { detail.days[i].dayIndex = i + 1 }
                dayIdx = detail.days.firstIndex(where: { $0.storyBookCalendarDayKey == dayKey })!
            }
            guard let di = dayIdx else { continue }

            var unmatchedRecapPhotos: [RecapPhoto] = []

            for photo in dayPhotos.sorted(by: { $0.timestamp < $1.timestamp }) {
                let isInAppCapture = photo.localIdentifier?.hasPrefix(AppCapturePhotoService.prefix) ?? false
                let recapPhoto = RecapPhoto(
                    id: photo.id,
                    timestamp: photo.timestamp,
                    location: locationForInjectedMockPhoto(photo),
                    imageName: photo.imageName,
                    isIncluded: isInAppCapture,   // camera captures are always shown; library photos scored later
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
                    var newStop = PlaceStop(
                        orderIndex: newStopIdx,
                        placeTitle: placeTitle,
                        representativeLocation: repLoc,
                        photos: groupPhotos
                    )
                    applySavedAppCapturePlaceMetadata(to: &newStop)
                    detail.days[di].placeStops.append(newStop)
                    if newStop.representativeLocation != nil, !newStop.placeTitleIsManual {
                        newStopsToGeocode.append((dayIdx: di, stopId: newStop.id))
                    }
                }
                modifiedDayIndices.insert(di)
            }

            // New stops were appended at the end; merge may leave groups out of chronological order
            // (e.g. in-app capture between two library stops). Match `buildBlogDetail(from:)`.
            if modifiedDayIndices.contains(di) {
                sortPlaceStopsChronologically(&detail.days[di].placeStops)
            }
        }

        detail = detail.consolidatingDuplicateCalendarDays()
        saveBlogDetail(detail, asDraft: true)

        // Run same business logic as initial selection: score quality, then preselect only good-quality photos per stop.
        if !modifiedDayIndices.isEmpty {
            // Geocode any newly created stops that have location data.
            if !newStopsToGeocode.isEmpty,
               var geocodedDetail = blogDetailsBySourceId[sourceTripId] {
                    for entry in newStopsToGeocode {
                        let di = entry.dayIdx
                        guard di < geocodedDetail.days.count,
                              let si = geocodedDetail.days[di].placeStops.firstIndex(where: { $0.id == entry.stopId }),
                              let coord = geocodedDetail.days[di].placeStops[si].representativeLocation else { continue }
                        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let place = await GeocodingService.shared.place(for: loc)
                            if !geocodedDetail.days[di].placeStops[si].placeTitleIsManual {
                                let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(areaName: place.areaName, coordinate: loc.coordinate)
                                geocodedDetail.days[di].placeStops[si].placeTitle = resolvedTitle
                                geocodedDetail.days[di].placeStops[si].placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                                if let cat = resolvedCategory, geocodedDetail.days[di].placeStops[si].placeCategory == nil {
                                    geocodedDetail.days[di].placeStops[si].placeCategory = cat
                                }
                                syncAppCaptureMetaFromResolvedStop(geocodedDetail.days[di].placeStops[si])
                            }
                    }
                geocodedDetail = geocodedDetail.consolidatingDuplicateCalendarDays()
                saveBlogDetail(geocodedDetail, asDraft: true)
            }
            await applyPhotoQualitySelectionForBlog(sourceTripId: sourceTripId, dayIndices: Array(modifiedDayIndices))
            await continueGeocodingDays(blogId: sourceTripId)
            if var finalDetail = blogDetailsBySourceId[sourceTripId] {
                finalDetail = finalDetail.consolidatingDuplicateCalendarDays()
                saveBlogDetail(finalDetail, asDraft: true)
            }
        }

        // Update blog metadata to reflect newly injected photos.
        guard let savedDetail = blogDetailsBySourceId[sourceTripId] else { return }
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            let newStart = RecapBlogDay.alignedTripStartDate(from: savedDetail.days)
            let newEnd = RecapBlogDay.alignedTripEndDate(from: savedDetail.days)
            if let minDate = newStart,
               (recents[idx].tripStartDate == nil || minDate < recents[idx].tripStartDate!) {
                recents[idx].tripStartDate = minDate
            }
            if let maxDate = newEnd,
               (recents[idx].tripEndDate == nil || maxDate > recents[idx].tripEndDate!) {
                recents[idx].tripEndDate = maxDate
            }
            recents[idx].tripDateRangeText = Self.formatDateRange(
                start: recents[idx].tripStartDate,
                end: recents[idx].tripEndDate
            )
            recents[idx].selectedPhotoCount = savedDetail.days
                .flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
            recents[idx].totalPlaceVisitCount = savedDetail.days.reduce(0) { $0 + $1.placeStops.count }
            recents[idx].tripDurationDays = savedDetail.days.count
            if !isValidCountryName(recents[idx].countryName),
               let country = resolvedCountryName(for: recents[idx]) {
                recents[idx].countryName = country
            }
            // Mark as edited so the blog appears in "My blogs" / Latest (e.g. "Edited Today").
            recents[idx].lastEditedAt = Date()
            recents[idx].syncStatus = .needsUpload
            persistRecents()
        }

        if notifyMenuIndicator {
            BlogMenuIndicatorStore.shared.noteMomentsAdded(to: sourceTripId)
        }

        unlinkEverydayCapturesNowInBlog(photos.compactMap(\.localIdentifier))
    }

    /// Representative coordinate for a blog: first itinerary place with a location (saved blog detail), else first GPS photo in the trip draft.
    func coordinate(for sourceTripId: UUID) -> CLLocationCoordinate2D? {
        if let detail = blogDetailsBySourceId[sourceTripId] {
            for day in detail.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
                for stop in day.placeStops.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    if let c = stop.representativeLocation?.clCoordinate { return c }
                    let included = stop.photos.filter(\.isIncluded)
                    if let p = included.first(where: { $0.location != nil }), let loc = p.location {
                        return loc.clCoordinate
                    }
                }
            }
        }
        guard let trip = tripDraftsBySourceId[sourceTripId] else { return nil }
        let first = trip.days.flatMap(\.photos).first(where: { $0.location != nil })
        return first?.location?.clCoordinate
    }

    /// Returns saved blog detail if user has edited and saved before. Otherwise nil (caller builds from trip).
    func getBlogDetail(blogId: UUID) -> RecapBlogDetail? {
        blogDetailsBySourceId[blogId]?.removingUndisplayablePhotos()
    }

    /// Persist edited blog detail. Call when user taps Save on RecapBlogPageView. Updates the corresponding recents entry.
    /// - Parameter asDraft: If true, preserves the existing lastEditedAt (keeping it nil if it was a draft).
    /// - Returns: `false` if a guest hit the second-blog save limit (nothing persisted); otherwise `true` unless the blog id is missing from recents after writing detail.
    @discardableResult
    func saveBlogDetail(_ detail: RecapBlogDetail, asDraft: Bool = false, skipGuestSecondSaveGuard: Bool = false) -> Bool {
        if !skipGuestSecondSaveGuard,
           !asDraft,
           AuthService.shared.currentUser == nil,
           let idx = recents.firstIndex(where: { $0.sourceTripId == detail.id }),
           recents[idx].ownerScope == .anonymous,
           !recents[idx].hasCommittedRecapSave {
            let otherCommitted = recents.contains {
                $0.ownerScope == .anonymous && $0.hasCommittedRecapSave && $0.sourceTripId != detail.id
            }
            if otherCommitted {
                guestSecondSaveBlockedSignal += 1
                return false
            }
        }

        let sanitized = detail.removingUndisplayablePhotos()
        blogDetailsBySourceId[sanitized.id] = sanitized
        syncAppCaptureCaptionsFromBlogDetail(sanitized)
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == detail.id }) else { return false }
        let old = recents[idx]
        let country = primaryCountryFromDetail(sanitized, trip: tripDraftsBySourceId[sanitized.id])
            ?? countryNameFromBlogTitle(sanitized.title)
            ?? old.countryName
        if isValidCountryName(country) {
            var detailWithCountry = sanitized
            detailWithCountry.countryName = country
            blogDetailsBySourceId[sanitized.id] = detailWithCountry
        }

        // Use EXIF-aligned dates so recents / scan ranges match day row headers.
        let newStart = RecapBlogDay.alignedTripStartDate(from: detail.days) ?? old.tripStartDate
        let newEnd = RecapBlogDay.alignedTripEndDate(from: detail.days) ?? old.tripEndDate
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
            ownerUserId: old.ownerUserId,
            hasCommittedRecapSave: asDraft ? old.hasCommittedRecapSave : true,
            hasCompletedInitialRecapExit: old.hasCompletedInitialRecapExit
        )
        if !asDraft {
            let locationLabel = detail.days.first?.placeStops.first?.placeTitle ?? ""
            AppAnalytics.shared.trackEvent(
                name: "blog_saved",
                properties: [
                    "sourceTripId": detail.id.uuidString,
                    "blogTitle": detail.title,
                    "countryName": country ?? "",
                    "locationLabel": locationLabel,
                ],
                context: AnalyticsContext(blogId: detail.id.uuidString)
            )
        }
        persistRecents()
        persistBlogDetails()
        return true
    }

    /// Writes a cloud URL onto every stored photo row matching the asset id (e.g. after cover-only upload).
    func applyCloudURLToLocalPhoto(blogId: UUID, localIdentifier: String, cloudURL: String) {
        guard var detail = getBlogDetail(blogId: blogId) else { return }
        detail.setCloudURL(cloudURL, forLocalAssetIdentifier: localIdentifier)
        saveBlogDetail(detail)
    }

    /// Updates the caption of a single photo across any stored blog detail that contains it.
    /// Called when the user edits a caption from the Places Visited photo modal.
    func updatePhotoCaption(photoId: UUID, newCaption: String) {
        var changed = false
        var changedSourceIds: Set<UUID> = []
        var appCaptureIdToSync: UUID?
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        if detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].id == photoId {
                            if appCaptureIdToSync == nil,
                               let lid = detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].localIdentifier,
                               let captureId = AppCapturePhotoService.uuid(from: lid) {
                                appCaptureIdToSync = captureId
                            }
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
                changedSourceIds.insert(key)
            }
        }
        if let cid = appCaptureIdToSync {
            let trimmed = newCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            try? AppCapturePhotoService.shared.updateCaption(captureId: cid, caption: trimmed.isEmpty ? nil : trimmed)
        }
        if changed {
            persistBlogDetails()
            for sourceId in changedSourceIds {
                patchRecentsAfterDetailCaptionEdit(sourceTripId: sourceId)
            }
            persistRecents()
            // Notify SwiftUI observers so views reading `visitedPlaces` (a computed property
            // derived from `blogDetailsBySourceId`) re-render immediately with the new caption.
            objectWillChange.send()
        }
    }

    /// Keeps **Bloggo Gallery** `meta.json` captions in sync when the user edits or clears captions in the blog.
    /// Only affects photos whose `localIdentifier` is `bloggo-capture:<uuid>`.
    private func syncAppCaptureCaptionsFromBlogDetail(_ detail: RecapBlogDetail) {
        for day in detail.days {
            for stop in day.placeStops {
                for photo in stop.photos {
                    guard let lid = photo.localIdentifier,
                          let captureId = AppCapturePhotoService.uuid(from: lid) else { continue }
                    let trimmed = (photo.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalCaption: String? = trimmed.isEmpty ? nil : trimmed
                    try? AppCapturePhotoService.shared.updateCaption(captureId: captureId, caption: finalCaption)
                }
            }
        }
    }

    /// Non-empty caption from any persisted `RecapBlogDetail` row for this Bloggo capture (`bloggo-capture:<uuid>`).
    /// Used so **Bloggo Gallery** can show the same caption as the blog when `meta.json` was never synced.
    func captionForAppCaptureInStoredBlogs(captureId: UUID) -> String? {
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops {
                    for photo in stop.photos {
                        guard photo.localIdentifier == assetId else { continue }
                        let trimmed = (photo.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                }
            }
        }
        return nil
    }

    /// After a caption is saved from **Bloggo Gallery** (in-app camera storage), copies it into every blog
    /// whose `RecapPhoto.localIdentifier` matches this capture (`bloggo-capture:<uuid>`).
    func syncPhotoCaptionFromAppCapture(captureId: UUID, caption: String?) {
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption: String? = (trimmed == nil || trimmed?.isEmpty == true) ? nil : trimmed
        var changed = false
        var changedSourceIds: Set<UUID> = []
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        guard detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].localIdentifier == assetId else { continue }
                        detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].caption = finalCaption
                        detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = true
                        detailChanged = true
                    }
                }
            }
            if detailChanged {
                blogDetailsBySourceId[key] = detail
                changed = true
                changedSourceIds.insert(key)
            }
        }
        if changed {
            persistBlogDetails()
            for sourceId in changedSourceIds {
                patchRecentsAfterDetailCaptionEdit(sourceTripId: sourceId)
            }
            persistRecents()
            objectWillChange.send()
        }
    }

    /// Keeps My Blogs / recents line in sync when a caption is edited outside RecapBlogPageView.
    private func patchRecentsAfterDetailCaptionEdit(sourceTripId: UUID) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }),
              let detail = blogDetailsBySourceId[sourceTripId] else { return }
        recents[idx].caption = primaryCaption(from: detail)
        recents[idx].lastEditedAt = Date()
        recents[idx].syncStatus = .needsUpload
    }

    /// First `RecapPhoto.id` in any stored blog whose `localIdentifier` is this Bloggo capture.
    func recapPhotoIdForAppCapture(captureId: UUID) -> UUID? {
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops {
                    if let photo = stop.photos.first(where: { $0.localIdentifier == assetId }) {
                        return photo.id
                    }
                }
            }
        }
        return nil
    }

    /// Map pin center for a Bloggo capture: saved `meta.json` coordinates, then blog stop representative location.
    func mapCenterCoordinateForAppCapture(captureId: UUID) -> CLLocationCoordinate2D? {
        if let meta = AppCapturePhotoService.shared.metadata(captureId: captureId),
           let coord = meta.location?.clCoordinate {
            return coord
        }
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { $0.localIdentifier == assetId }) {
                    return stop.representativeLocation?.clCoordinate
                        ?? stop.photos.first(where: { $0.localIdentifier == assetId })?.location?.clCoordinate
                }
            }
        }
        return nil
    }

    /// Display name for a Bloggo capture: `meta.json` first, then any saved blog stop (skips `Stop N` placeholders).
    func placeTitleForAppCapture(captureId: UUID) -> String? {
        if let metaTitle = AppCapturePhotoService.shared.metadata(captureId: captureId)?.placeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !metaTitle.isEmpty,
           !PlacePlaceholderNaming.isResolvablePlaceholder(metaTitle) {
            return metaTitle
        }
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { $0.localIdentifier == assetId }) {
                    let title = stop.placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !PlacePlaceholderNaming.isResolvablePlaceholder(title) else { continue }
                    return title
                }
            }
        }
        return nil
    }

    /// Reverse-geocodes a Bloggo capture when its title is still a placeholder (`Stop N`, etc.).
    /// Uses a safe `Near …` label (neighborhood / area / city) — never auto-picks a specific venue.
    func resolveAppCapturePlaceIfNeeded(
        captureId: UUID,
        fallbackCoordinate: CLLocationCoordinate2D? = nil
    ) async {
        let existing = placeTitleForAppCapture(captureId: captureId) ?? ""
        guard PlacePlaceholderNaming.isResolvablePlaceholder(existing) else { return }

        let meta = AppCapturePhotoService.shared.metadata(captureId: captureId)
        guard let coord = meta?.location?.clCoordinate ?? fallbackCoordinate else { return }

        let (finalTitle, subtitle) = await GeocodingService.shared.autoCaptureNearPlaceTitle(at: coord)
        let trimmedTitle = finalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              !PlacePlaceholderNaming.isResolvablePlaceholder(trimmedTitle) else { return }

        updatePlaceStopFromAppCapture(
            captureId: captureId,
            newName: trimmedTitle,
            category: nil,
            coordinate: coord,
            subtitle: subtitle
        )
    }

    /// Mirrors a stop's place fields onto each `bloggo-capture:` meta file in that stop, so the
    /// Bloggo Gallery (which reads the meta cache first) reflects the current name.
    /// - Parameter force: `false` for auto-geocode passes — skips captures the user already edited
    ///   directly so a rescan can't revert a deliberate edit. `true` for an explicit manual rename
    ///   (e.g. from the Blog view or My Places), which should always win.
    func syncAppCaptureMetaFromResolvedStop(_ stop: PlaceStop, force: Bool = false) {
        let title = stop.placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !PlacePlaceholderNaming.isResolvablePlaceholder(title) else { return }
        let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let coord = stop.representativeLocation?.clCoordinate
        for photo in stop.photos {
            guard let lid = photo.localIdentifier,
                  let captureId = AppCapturePhotoService.uuid(from: lid) else { continue }
            if !force, AppCapturePhotoService.shared.hasUserEditedPlaceMetadata(captureId: captureId) {
                continue
            }
            try? AppCapturePhotoService.shared.updatePlaceMetadata(
                captureId: captureId,
                placeTitle: title,
                placeSubtitle: subtitle?.isEmpty == true ? nil : subtitle,
                placeCategory: stop.placeCategory,
                coordinate: coord
            )
        }
    }

    /// Applies saved `meta.json` place fields onto a clustered stop (and its in-app capture photo rows).
    private func applySavedAppCapturePlaceMetadata(to stop: inout PlaceStop) {
        let captureService = AppCapturePhotoService.shared
        var savedMeta: AppCapturePhotoService.CaptureInfo?
        for photo in stop.photos {
            guard let lid = photo.localIdentifier,
                  let captureId = AppCapturePhotoService.uuid(from: lid),
                  let meta = captureService.metadata(captureId: captureId) else { continue }
            if let title = meta.placeTitle,
               !PlacePlaceholderNaming.isResolvablePlaceholder(title) {
                savedMeta = meta
                break
            }
            if savedMeta == nil { savedMeta = meta }
        }
        guard let meta = savedMeta else { return }

        if let title = meta.placeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           !PlacePlaceholderNaming.isResolvablePlaceholder(title) {
            stop.placeTitle = title
            stop.placeTitleIsManual = true
            let sub = meta.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            stop.placeSubtitle = sub.isEmpty ? nil : sub
            stop.placeCategory = meta.placeCategory
        }

        guard let savedLoc = meta.location else { return }
        stop.representativeLocation = savedLoc
        for photoIdx in stop.photos.indices {
            guard let lid = stop.photos[photoIdx].localIdentifier,
                  AppCapturePhotoService.uuid(from: lid) != nil else { continue }
            stop.photos[photoIdx].location = savedLoc
        }
    }

    /// Keeps persisted trip drafts aligned when the user edits a capture in Bloggo Gallery.
    private func syncTripDraftPhotosForAppCapture(
        captureId: UUID,
        coordinate: CLLocationCoordinate2D?,
        caption: String?
    ) {
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        let photoCoord = coordinate.map { PhotoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        var changed = false
        for key in tripDraftsBySourceId.keys {
            guard var trip = tripDraftsBySourceId[key] else { continue }
            var tripChanged = false
            for dayIdx in trip.days.indices {
                for photoIdx in trip.days[dayIdx].photos.indices {
                    guard trip.days[dayIdx].photos[photoIdx].localIdentifier == assetId else { continue }
                    if let photoCoord {
                        trip.days[dayIdx].photos[photoIdx].location = photoCoord
                    }
                    if let caption {
                        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        trip.days[dayIdx].photos[photoIdx].caption = trimmed.isEmpty ? nil : trimmed
                    }
                    tripChanged = true
                }
            }
            if tripChanged {
                tripDraftsBySourceId[key] = trip
                changed = true
            }
        }
        if changed { persistTripDrafts() }
    }

    private func locationForInjectedMockPhoto(_ photo: MockPhoto) -> PhotoCoordinate? {
        guard let lid = photo.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: lid),
              let metaLoc = AppCapturePhotoService.shared.metadata(captureId: captureId)?.location else {
            return photo.location
        }
        return metaLoc
    }

    /// City / country subtitle for a Bloggo capture: `meta.json` first, then saved blog stop.
    func placeSubtitleForAppCapture(captureId: UUID) -> String? {
        if let metaSub = AppCapturePhotoService.shared.metadata(captureId: captureId)?.placeSubtitle?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !metaSub.isEmpty {
            return metaSub
        }
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { $0.localIdentifier == assetId }) {
                    let sub = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return sub.isEmpty ? nil : sub
                }
            }
        }
        return nil
    }

    /// POI category on this Bloggo capture: `meta.json` first, then saved blog stop.
    func placeCategoryForAppCapture(captureId: UUID) -> String? {
        if let metaCat = AppCapturePhotoService.shared.metadata(captureId: captureId)?.placeCategory?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !metaCat.isEmpty {
            return metaCat
        }
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        for (_, detail) in blogDetailsBySourceId {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { $0.localIdentifier == assetId }) {
                    return stop.placeCategory
                }
            }
        }
        return nil
    }

    /// Saves place name / location edits from **Bloggo Gallery** for a `bloggo-capture:` asset.
    func updatePlaceStopFromAppCapture(
        captureId: UUID,
        newName: String,
        category: String?,
        coordinate: CLLocationCoordinate2D?,
        subtitle: String
    ) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let subTrimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        try? AppCapturePhotoService.shared.updatePlaceMetadata(
            captureId: captureId,
            placeTitle: trimmedName,
            placeSubtitle: subTrimmed.isEmpty ? nil : subTrimmed,
            placeCategory: category,
            coordinate: coordinate
        )

        syncAppCapturePlaceInBlogs(
            captureId: captureId,
            newName: trimmedName,
            category: category,
            coordinate: coordinate,
            subtitle: subTrimmed
        )
        syncTripDraftPhotosForAppCapture(
            captureId: captureId,
            coordinate: coordinate,
            caption: nil
        )
        objectWillChange.send()
    }

    /// Updates every blog stop / photo row for this `bloggo-capture:` identifier.
    private func syncAppCapturePlaceInBlogs(
        captureId: UUID,
        newName: String,
        category: String?,
        coordinate: CLLocationCoordinate2D?,
        subtitle: String
    ) {
        let assetId = AppCapturePhotoService.identifier(for: captureId)
        let photoCoord = coordinate.map { PhotoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let subTrimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        var targetMomentKeys = Set<String>()
        for detail in blogDetailsBySourceId.values {
            for day in detail.days {
                for stop in day.placeStops {
                    guard stop.photos.contains(where: { $0.localIdentifier == assetId }) else { continue }
                    if let vtd = stop.visitedTimeDigitized, !vtd.isEmpty {
                        targetMomentKeys.insert(vtd)
                    }
                }
            }
        }

        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    let stop = detail.days[dayIdx].placeStops[stopIdx]
                    let containsAsset = stop.photos.contains { $0.localIdentifier == assetId }
                    let sameMoment = stop.visitedTimeDigitized.map { targetMomentKeys.contains($0) } ?? false
                    guard containsAsset || sameMoment else { continue }

                    detail.days[dayIdx].placeStops[stopIdx].placeTitle = newName
                    detail.days[dayIdx].placeStops[stopIdx].placeTitleIsManual = true
                    detail.days[dayIdx].placeStops[stopIdx].placeCategory = category
                    detail.days[dayIdx].placeStops[stopIdx].placeSubtitle = subTrimmed.isEmpty ? nil : subTrimmed
                    if let coordinate {
                        detail.days[dayIdx].placeStops[stopIdx].representativeLocation = photoCoord
                    }

                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        guard detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].localIdentifier == assetId else { continue }
                        if let photoCoord {
                            detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].location = photoCoord
                        }
                    }
                    detailChanged = true
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

    /// My Places everyday captures are not in blog details; mirror place edits into capture `meta.json`.
    private func syncPlacesVisitedEditToAppCaptureMetadata(
        photoId: UUID,
        newName: String,
        category: String?,
        coordinate: CLLocationCoordinate2D?,
        subtitle: String
    ) {
        guard AppCapturePhotoService.shared.metadata(captureId: photoId) != nil else { return }
        updatePlaceStopFromAppCapture(
            captureId: photoId,
            newName: newName,
            category: category,
            coordinate: coordinate,
            subtitle: subtitle
        )
    }

    /// Updates the place stop name, category, coordinate, and subtitle for every stop that contains
    /// `photoId` or any id in `additionalPhotoIds`.
    /// Called when the user saves a place name edit from the Places Visited photo modal (via `EditPlaceStopNameSheet`).
    /// - Note: A single card in "My Places" can visually merge photos from *multiple* underlying
    ///   `PlaceStop`s (different days/blogs sharing a `visitedTimeDigitized`, or a blog stop merged
    ///   with an Everyday cluster by name+proximity in `isSamePlace`). Pass every photo id currently
    ///   shown on that card via `additionalPhotoIds` so the rename reaches all of them — otherwise only
    ///   the stop containing `photoId` (typically the first photo) gets renamed and its siblings keep
    ///   showing their old auto-resolved title.
    func updatePlaceStopFromPlacesVisited(photoId: UUID, additionalPhotoIds: [UUID] = [], newName: String, category: String?, coordinate: CLLocationCoordinate2D?, subtitle: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subTrimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetIds = Set([photoId] + additionalPhotoIds)
        var targetMomentKeys = Set<String>()
        for detail in blogDetailsBySourceId.values {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { targetIds.contains($0.id) }) {
                    if let vtd = stop.visitedTimeDigitized, !vtd.isEmpty {
                        targetMomentKeys.insert(vtd)
                    }
                }
            }
        }
        var changed = false
        var updatedStops: [PlaceStop] = []
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    let stop = detail.days[dayIdx].placeStops[stopIdx]
                    let containsPhoto = stop.photos.contains { targetIds.contains($0.id) }
                    let sameMoment = stop.visitedTimeDigitized.map { targetMomentKeys.contains($0) } ?? false
                    if containsPhoto || sameMoment {
                        detail.days[dayIdx].placeStops[stopIdx].placeTitle = trimmed
                        detail.days[dayIdx].placeStops[stopIdx].placeTitleIsManual = true
                        // `EditPlaceStopNameSheet` passes the resolved category (including nil to clear after a rename).
                        detail.days[dayIdx].placeStops[stopIdx].placeCategory = category
                        if let coordinate {
                            detail.days[dayIdx].placeStops[stopIdx].representativeLocation = PhotoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        }
                        detail.days[dayIdx].placeStops[stopIdx].placeSubtitle = subTrimmed.isEmpty ? nil : subTrimmed
                        detailChanged = true
                        updatedStops.append(detail.days[dayIdx].placeStops[stopIdx])
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
        // `photoId` is a `RecapPhoto.id`, which for trip/blog photos is the capture *moment's* UUID —
        // not the `bloggo-capture:` UUID `syncPlacesVisitedEditToAppCaptureMetadata` expects. Resolve
        // the real capture ids via each stop's photo `localIdentifier`s instead.
        for stop in updatedStops {
            syncAppCaptureMetaFromResolvedStop(stop, force: true)
        }
        // Covers the everyday/local-capture case, where a target id genuinely is the capture UUID
        // (these photos aren't in `blogDetailsBySourceId`, so the loop above found nothing for them).
        for id in targetIds {
            syncPlacesVisitedEditToAppCaptureMetadata(
                photoId: id,
                newName: trimmed,
                category: category,
                coordinate: coordinate,
                subtitle: subTrimmed
            )
        }
    }

    /// Updates only `placeCategory` for the stop that contains the given photo (Places Visited category chip / picker).
    func updatePlaceStopCategoryFromPlacesVisited(photoId: UUID, category: String?) {
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    let containsPhoto = detail.days[dayIdx].placeStops[stopIdx].photos.contains { $0.id == photoId }
                    if containsPhoto {
                        detail.days[dayIdx].placeStops[stopIdx].placeCategory = category
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

    /// Updates the place stop name for every stop that contains `photoId` or any id in `additionalPhotoIds`.
    /// Called when the user edits a place name from the Places Visited photo modal.
    /// - Note: see `updatePlaceStopFromPlacesVisited` — pass every photo id shown on the merged
    ///   "My Places" card via `additionalPhotoIds`, or siblings from a different underlying stop keep
    ///   their old title.
    func updatePlaceStopName(photoId: UUID, additionalPhotoIds: [UUID] = [], newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetIds = Set([photoId] + additionalPhotoIds)
        var targetMomentKeys = Set<String>()
        for detail in blogDetailsBySourceId.values {
            for day in detail.days {
                for stop in day.placeStops where stop.photos.contains(where: { targetIds.contains($0.id) }) {
                    if let vtd = stop.visitedTimeDigitized, !vtd.isEmpty {
                        targetMomentKeys.insert(vtd)
                    }
                }
            }
        }
        var changed = false
        var updatedStops: [PlaceStop] = []
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    let stop = detail.days[dayIdx].placeStops[stopIdx]
                    let containsPhoto = stop.photos.contains { targetIds.contains($0.id) }
                    let sameMoment = stop.visitedTimeDigitized.map { targetMomentKeys.contains($0) } ?? false
                    if containsPhoto || sameMoment {
                        detail.days[dayIdx].placeStops[stopIdx].placeTitle = trimmed
                        let cat = detail.days[dayIdx].placeStops[stopIdx].placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if cat.isEmpty {
                            detail.days[dayIdx].placeStops[stopIdx].placeCategory =
                                PlacePOICategoryPresentation.inferredCategoryRaw(fromPlaceTitle: trimmed)
                        }
                        detailChanged = true
                        updatedStops.append(detail.days[dayIdx].placeStops[stopIdx])
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
        // See `updatePlaceStopFromPlacesVisited` — a target id is not the capture UUID for trip photos.
        for stop in updatedStops {
            syncAppCaptureMetaFromResolvedStop(stop, force: true)
        }
        for id in targetIds {
            guard let meta = AppCapturePhotoService.shared.metadata(captureId: id) else { continue }
            syncPlacesVisitedEditToAppCaptureMetadata(
                photoId: id,
                newName: trimmed,
                category: meta.placeCategory,
                coordinate: meta.location?.clCoordinate,
                subtitle: meta.placeSubtitle ?? ""
            )
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

    /// Sets `isIncluded = false` for photos whose `localIdentifier` matches these app-capture UUIDs (after files were deleted from the Bloggo gallery).
    func excludeAppCapturesFromBlogs(captureIds: Set<UUID>) {
        guard !captureIds.isEmpty else { return }
        let identifiers = Set(captureIds.map { AppCapturePhotoService.identifier(for: $0) })
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for dayIdx in detail.days.indices {
                for stopIdx in detail.days[dayIdx].placeStops.indices {
                    for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                        if let lid = detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].localIdentifier,
                           identifiers.contains(lid) {
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

    /// Syncs user-entered captions from the camera session into the blog detail.
    /// Called when the camera is dismissed so captions typed after real-time injection are preserved.
    func syncCaptions(_ captions: [(photoId: UUID, caption: String)]) {
        guard !captions.isEmpty else { return }
        var changed = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            var detailChanged = false
            for (photoId, caption) in captions {
                for dayIdx in detail.days.indices {
                    for stopIdx in detail.days[dayIdx].placeStops.indices {
                        for photoIdx in detail.days[dayIdx].placeStops[stopIdx].photos.indices {
                            if detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].id == photoId {
                                detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].caption = caption
                                detail.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = true
                                detailChanged = true
                            }
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

    /// Persists that the recap editor was dismissed at least once for this blog (see `CreatedRecapBlog.hasCompletedInitialRecapExit`).
    func markInitialRecapEditorExit(for sourceTripId: UUID) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) else { return }
        guard !recents[idx].hasCompletedInitialRecapExit else { return }
        recents[idx].hasCompletedInitialRecapExit = true
        persistRecents()
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
        BlogMenuIndicatorStore.shared.clear(sourceTripId: sourceTripId)
        NotificationCenter.default.post(
            name: .bloggoCreatedBlogDeleted,
            object: nil,
            userInfo: ["sourceTripId": sourceTripId]
        )
    }

    // MARK: - Merge & Split

    /// Removes trailing ` (Part N of M)` suffixes added by `splitBlog`, for display and merge naming.
    static func titleByStrippingSplitPartSuffix(_ title: String) -> String {
        title
            .replacingOccurrences(of: " \\(Part \\d+ of \\d+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Latest photo timestamp for a blog/draft, falling back to stored trip end date.
    func effectiveEndTimestamp(forSourceTripId sourceTripId: UUID) -> Date? {
        if let detail = blogDetailsBySourceId[sourceTripId] {
            let photoTs = detail.days.flatMap(\.placeStops).flatMap(\.photos).map(\.timestamp).max()
            if let photoTs { return photoTs }
        }
        if let draft = tripDraftsBySourceId[sourceTripId] {
            return draft.effectiveEndTimestamp
        }
        return recents.first(where: { $0.sourceTripId == sourceTripId })?.tripEndDate
    }

    /// Best saved blog for an in-app capture when multiple trips match (e.g. split parts or same-day segments).
    func bestMatchingBlog(forCapture captureTimestamp: Date) -> CreatedRecapBlog? {
        if let activeId = OnTheGoTripStore.activeBlogId, AuthService.shared.isSignedIn,
           !hasCreatedBlog(sourceTripId: activeId) {
            OnTheGoTripStore.markTripAsEnded()
        }

        var pool = visibleRecents
        if let activeId = OnTheGoTripStore.activeBlogId,
           OnTheGoTripStore.isTripStillOngoing(),
           hasCreatedBlog(sourceTripId: activeId),
           !pool.contains(where: { $0.sourceTripId == activeId }),
           let activeBlog = recents.first(where: { $0.sourceTripId == activeId }) {
            pool.append(activeBlog)
        }

        var candidates: [(CreatedRecapBlog, Date)] = []
        for blog in pool {
            guard let end = effectiveEndTimestamp(forSourceTripId: blog.sourceTripId),
                  captureTimestamp.timeIntervalSince(end) <= 86400 else { continue }
            candidates.append((blog, end))
        }

        let splitBaseTitles = Set(
            candidates
                .filter { $0.0.title.contains("(Part ") }
                .map { Self.titleByStrippingSplitPartSuffix($0.0.title) }
        )
        for blog in pool where splitBaseTitles.contains(Self.titleByStrippingSplitPartSuffix(blog.title)) {
            guard !candidates.contains(where: { $0.0.sourceTripId == blog.sourceTripId }) else { continue }
            guard let end = effectiveEndTimestamp(forSourceTripId: blog.sourceTripId),
                  captureTimestamp.timeIntervalSince(end) <= 86400 else { continue }
            candidates.append((blog, end))
        }

        return TripCaptureMatcher.bestMatch(
            candidates: candidates.map { (item: $0.0, end: $0.1) },
            captureTimestamp: captureTimestamp
        )
    }

    /// Merges two blogs into one. The `keepId` blog absorbs all days from `absorbId`.
    /// Both IDs are `sourceTripId` values.
    /// - Parameter mergedTitle: When set, updates the kept blog’s title in recaps, detail, and trip draft. Pass `nil` to leave the kept blog’s title unchanged.
    /// - Parameter recordMergeUndo: When true (default), stores a snapshot for `undoMerge()`. Pass false for internal merges (e.g. `undoSplit`).
    func mergeBlogs(keepId: UUID, absorbId: UUID, mergedTitle: String? = nil, recordMergeUndo: Bool = true) {
        guard var keepDetail = blogDetailsBySourceId[keepId],
              let absorbDetail = blogDetailsBySourceId[absorbId],
              let keepIdx = recents.firstIndex(where: { $0.sourceTripId == keepId }),
              recents.contains(where: { $0.sourceTripId == absorbId }) else {
            return
        }

        let mergeUndoSnapshot: MergeUndoInfo? = recordMergeUndo
            ? MergeUndoInfo(
                recentsSnapshot: recents,
                keepId: keepId,
                absorbId: absorbId,
                keepDetail: keepDetail,
                absorbDetail: absorbDetail,
                keepTripDraft: tripDraftsBySourceId[keepId],
                absorbTripDraft: tripDraftsBySourceId[absorbId]
            )
            : nil

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
        if let mergedTitle, !mergedTitle.isEmpty {
            keepDetail.title = mergedTitle
        }
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
        recents[keepIdx].hasCommittedRecapSave = keepOld.hasCommittedRecapSave || absorbOld?.hasCommittedRecapSave == true
        if let mergedTitle, !mergedTitle.isEmpty {
            recents[keepIdx].title = mergedTitle
        }

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
            if let mergedTitle, !mergedTitle.isEmpty {
                keepTrip.title = mergedTitle
            }
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

        if let mergeUndoSnapshot {
            lastMergeUndoInfo = mergeUndoSnapshot
            lastSplitUndoInfo = nil
        } else {
            lastMergeUndoInfo = nil
        }
    }

    /// Restores the two blogs and list order from before the last `mergeBlogs` that recorded undo.
    func undoMerge() {
        guard let info = lastMergeUndoInfo else { return }
        recents = info.recentsSnapshot
        blogDetailsBySourceId[info.keepId] = info.keepDetail
        blogDetailsBySourceId[info.absorbId] = info.absorbDetail
        if let d = info.keepTripDraft {
            tripDraftsBySourceId[info.keepId] = d
        } else {
            tripDraftsBySourceId.removeValue(forKey: info.keepId)
        }
        if let d = info.absorbTripDraft {
            tripDraftsBySourceId[info.absorbId] = d
        } else {
            tripDraftsBySourceId.removeValue(forKey: info.absorbId)
        }
        lastMergeUndoInfo = nil
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
        let baseTitle = Self.titleByStrippingSplitPartSuffix(detail.title)
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

        // 6. Update Part 1 metadata (EXIF-aligned dates so range matches day row headers)
        let start1 = part1Days.first?.dateAlignedWithShortDateText
        let end1 = part1Days.last?.dateAlignedWithShortDateText
        let places1 = part1Days.reduce(0) { $0 + $1.placeStops.count }
        let photos1 = part1Days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count

        recents[recentIdx].title = title1
        recents[recentIdx].tripStartDate = start1
        recents[recentIdx].tripEndDate = end1
        recents[recentIdx].totalPlaceVisitCount = places1
        recents[recentIdx].tripDurationDays = part1Days.count
        recents[recentIdx].selectedPhotoCount = photos1
        recents[recentIdx].tripDateRangeText = Self.formatDateRange(start: start1, end: end1)
        recents[recentIdx].lastEditedAt = oldRecent.hasCommittedRecapSave ? Date() : oldRecent.lastEditedAt
        recents[recentIdx].syncStatus = .needsUpload
        recents[recentIdx].hasCommittedRecapSave = oldRecent.hasCommittedRecapSave

        // 7. Create Part 2 recents entry
        let start2 = part2Days.first?.dateAlignedWithShortDateText
        let end2 = part2Days.last?.dateAlignedWithShortDateText
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
            lastEditedAt: nil,
            tripStartDate: start2,
            tripEndDate: end2,
            totalPlaceVisitCount: places2,
            tripDurationDays: part2Days.count,
            ownerScope: oldRecent.ownerScope,
            ownerUserId: oldRecent.ownerUserId,
            hasCommittedRecapSave: false
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
                trip1.dateRangeText = Self.formatDateRange(start: start1, end: end1) ?? ""
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
        lastMergeUndoInfo = nil

        // 10. Persist
        blogDetailsBySourceId[blogId] = detail1
        blogDetailsBySourceId[newBlogId] = detail2
        persistRecents()
        persistBlogDetails()
        persistTripDrafts()
        needsRescan = true
        NotificationCenter.default.post(name: .tripDraftsDidChangeInStore, object: nil)
    }

    /// After `splitBlog`, swaps Part 1 and Part 2 payloads so the editor at `keepId` shows Part 2. `lastSplitUndoInfo` ids are unchanged for `undoSplit`.
    func focusSplitPart(keepPart: Int) {
        guard keepPart == 2,
              let info = lastSplitUndoInfo,
              let part1Detail = blogDetailsBySourceId[info.keepId],
              let part2Detail = blogDetailsBySourceId[info.newId],
              let keepIdx = recents.firstIndex(where: { $0.sourceTripId == info.keepId }),
              let newIdx = recents.firstIndex(where: { $0.sourceTripId == info.newId }) else {
            return
        }

        let keepId = info.keepId
        let newId = info.newId

        blogDetailsBySourceId[keepId] = RecapBlogDetail(
            id: keepId,
            title: part2Detail.title,
            days: part2Detail.days,
            coverTheme: part2Detail.coverTheme,
            selectedCoverPhotoIdentifier: part2Detail.selectedCoverPhotoIdentifier,
            countryName: part2Detail.countryName,
            blogKey: part1Detail.blogKey,
            removedPlaceStops: part2Detail.removedPlaceStops,
            tripNarrative: part2Detail.tripNarrative
        )
        blogDetailsBySourceId[newId] = RecapBlogDetail(
            id: newId,
            title: part1Detail.title,
            days: part1Detail.days,
            coverTheme: part1Detail.coverTheme,
            selectedCoverPhotoIdentifier: part1Detail.selectedCoverPhotoIdentifier,
            countryName: part1Detail.countryName,
            blogKey: part2Detail.blogKey,
            removedPlaceStops: part1Detail.removedPlaceStops,
            tripNarrative: part1Detail.tripNarrative
        )

        let keepIdentity = recents[keepIdx]
        let newIdentity = recents[newIdx]
        var keepDisplay = keepIdentity
        var newDisplay = newIdentity
        swapSplitRecentDisplayFields(&keepDisplay, &newDisplay)
        recents[keepIdx] = recentRow(display: keepDisplay, identity: keepIdentity)
        recents[newIdx] = recentRow(display: newDisplay, identity: newIdentity)

        if let trip1 = tripDraftsBySourceId[keepId], let trip2 = tripDraftsBySourceId[newId] {
            var focusedTrip = trip2
            focusedTrip.id = keepId
            var otherTrip = trip1
            otherTrip.id = newId
            tripDraftsBySourceId[keepId] = focusedTrip
            tripDraftsBySourceId[newId] = otherTrip
        }

        persistRecents()
        persistBlogDetails()
        persistTripDrafts()
        needsRescan = true
        NotificationCenter.default.post(name: .tripDraftsDidChangeInStore, object: nil)
    }

    private func swapSplitRecentDisplayFields(_ keep: inout CreatedRecapBlog, _ new: inout CreatedRecapBlog) {
        swap(&keep.title, &new.title)
        swap(&keep.coverImageName, &new.coverImageName)
        swap(&keep.coverAssetIdentifier, &new.coverAssetIdentifier)
        swap(&keep.totalPlaceVisitCount, &new.totalPlaceVisitCount)
        swap(&keep.tripDurationDays, &new.tripDurationDays)
        swap(&keep.selectedPhotoCount, &new.selectedPhotoCount)
        swap(&keep.tripDateRangeText, &new.tripDateRangeText)
        swap(&keep.lastEditedAt, &new.lastEditedAt)
        swap(&keep.tripStartDate, &new.tripStartDate)
        swap(&keep.tripEndDate, &new.tripEndDate)
        swap(&keep.caption, &new.caption)
    }

    private func recentRow(display: CreatedRecapBlog, identity: CreatedRecapBlog) -> CreatedRecapBlog {
        CreatedRecapBlog(
            id: identity.id,
            sourceTripId: identity.sourceTripId,
            title: display.title,
            createdAt: identity.createdAt,
            coverImageName: display.coverImageName,
            coverAssetIdentifier: display.coverAssetIdentifier,
            selectedPhotoCount: display.selectedPhotoCount,
            countryName: identity.countryName,
            tripDateRangeText: display.tripDateRangeText,
            lastEditedAt: display.lastEditedAt,
            tripStartDate: display.tripStartDate,
            tripEndDate: display.tripEndDate,
            totalPlaceVisitCount: display.totalPlaceVisitCount,
            tripDurationDays: display.tripDurationDays,
            caption: display.caption,
            blogKey: identity.blogKey,
            ownerScope: identity.ownerScope,
            ownerUserId: identity.ownerUserId,
            cloudId: identity.cloudId,
            cloudState: identity.cloudState,
            syncStatus: identity.syncStatus,
            lastAutosaveAt: identity.lastAutosaveAt,
            hasCommittedRecapSave: identity.hasCommittedRecapSave,
            hasCompletedInitialRecapExit: identity.hasCompletedInitialRecapExit
        )
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
        
        let baseTitle = Self.titleByStrippingSplitPartSuffix(trip.title)
        
        let title1 = "\(baseTitle) (Part 1 of 2)"
        let title2 = "\(baseTitle) (Part 2 of 2)"
        
        // 2. Formulate the two TripDrafts (dateText-aligned ranges match day rows / landing cards)
        let start1 = part1Days.first?.dateAlignedForRange
        let end1 = part1Days.last?.dateAlignedForRange
        let dateRange1 = Self.formatDateRange(start: start1, end: end1) ?? ""
        
        var trip1 = trip
        trip1.title = title1
        trip1.days = part1Days
        trip1.dateRangeText = dateRange1
        
        let start2 = part2Days.first?.dateAlignedForRange
        let end2 = part2Days.last?.dateAlignedForRange
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
        NotificationCenter.default.post(name: .tripDraftsDidChangeInStore, object: nil)
    }

    /// Undoes the last split operation by re-merging the two resulting blogs back into one.
    func undoSplit() {
        guard let info = lastSplitUndoInfo else { return }
        // Merge Part 2 back into Part 1 (keepId absorbs newId)
        mergeBlogs(keepId: info.keepId, absorbId: info.newId, recordMergeUndo: false)
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

    // MARK: - Cloud sync (disabled)

    /// Stub — server trip reconciliation is disabled; blogs remain on-device only.
    func syncFromCloud() async {}

    // MARK: - Build Blog Detail

    /// Orders place stops by earliest photo time (same rule as `buildBlogDetail(from:)`), fixes `orderIndex`, and renumbers auto-generated `Stop N` titles.
    private func sortPlaceStopsChronologically(_ stops: inout [PlaceStop]) {
        stops.sort {
            let t0 = $0.photos.map(\.timestamp).min() ?? .distantFuture
            let t1 = $1.photos.map(\.timestamp).min() ?? .distantFuture
            return t0 < t1
        }
        for i in stops.indices {
            stops[i].orderIndex = i
            guard !stops[i].placeTitleIsManual else { continue }
            if stops[i].placeTitle.range(of: "^Stop \\d+$", options: .regularExpression) != nil {
                stops[i].placeTitle = "Stop \(i + 1)"
            }
        }
    }

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
            var placeStops: [PlaceStop] = stopGroups.compactMap { orderIndex, inputs -> PlaceStop? in
                var photos: [RecapPhoto] = inputs.map { input in
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
                }.sorted { $0.timestamp < $1.timestamp }
                guard photos.contains(where: \.isIncluded) else { return nil }

                // Cap included photos to maxAutoIncludedCount() using time-spread.
                // Quality scoring runs later (async) and will refine this selection.
                let includedPhotos = photos.filter(\.isIncluded)
                if includedPhotos.count > includedPhotos.maxAutoIncludedCount() {
                    let topIds = includedPhotos.autoSelectedIds()
                    for j in photos.indices where photos[j].isIncluded {
                        photos[j].isIncluded = topIds.contains(photos[j].id)
                    }
                }
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
            // Re-sort stops by earliest photo timestamp and re-index after filtering.
            placeStops.sort { ($0.photos.first?.timestamp ?? .distantFuture) < ($1.photos.first?.timestamp ?? .distantFuture) }
            for i in placeStops.indices {
                placeStops[i].orderIndex = i
                placeStops[i].placeTitle = "Stop \(i + 1)"
            }
            for i in placeStops.indices {
                applySavedAppCapturePlaceMetadata(to: &placeStops[i])
            }

            guard !placeStops.isEmpty else { continue }
            let dayDate = day.calendarDayKey.flatMap { TripCalendarDayKey.canonicalDate(from: $0) }
                ?? day.photos.filter(\.isSelected).map(\.timestamp).min().map { calendar.startOfDay(for: $0) }
                ?? Date()
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
        var detail = buildBlogDetail(from: trip)
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, weight: Int, order: Int)] = []
        var order = 0

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                let stop = detail.days[dayIdx].placeStops[stopIdx]
                if Task.isCancelled { return detail }
                if let coord = stop.representativeLocation {
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let place = await GeocodingService.shared.place(for: loc)
                    // timeZone is now in cache (place() populates it) — grab it and persist it
                    let tz = await GeocodingService.shared.timeZone(for: loc)
                    cityCandidates.append((place.cityName, order))
                    let weight = max(1, stop.photos.filter(\.isIncluded).count)
                    countryCandidates.append((place.countryName, weight, order))
                    order += 1
                    var updated = detail.days[dayIdx]
                    var stopCopy = updated.placeStops[stopIdx]
                    if !stopCopy.placeTitleIsManual {
                        let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(areaName: place.areaName, coordinate: loc.coordinate)
                        stopCopy.placeTitle = resolvedTitle
                        stopCopy.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                        if let cat = resolvedCategory, stopCopy.placeCategory == nil {
                            stopCopy.placeCategory = cat
                        }
                    }
                    stopCopy.timeZoneIdentifier = tz?.identifier
                    updated.placeStops[stopIdx] = stopCopy
                    detail.days[dayIdx] = updated
                }
            }
        }

        if Task.isCancelled { return detail }

        let primaryCity = primaryCityFromCandidates(cityCandidates)
        let primaryCountry = primaryFromWeightedCandidates(countryCandidates)
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
        if let primaryCountry, !primaryCountry.isEmpty && primaryCountry != "Unknown" {
            detail.countryName = primaryCountry
        }

        // Compute visitedTimeDigitized for each stop using EXIF timezone from PHAssets,
        // or metadata from AppCapturePhotoService for bloggo-capture: photos.
        let allIncludedPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        // Only fetch PHAssets for non-app-capture identifiers.
        let phAssetIds = allIncludedPhotos.compactMap(\.localIdentifier).filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
        var assetMap: [String: PHAsset] = [:]
        if !phAssetIds.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: phAssetIds, options: nil)
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
                guard let firstPhoto = photos.min(by: { $0.timestamp < $1.timestamp }) else {
                    print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': skipped visitedTimeDigitized (no included photos)")
                    continue
                }

                // App-capture: use stored digitizedTime directly.
                if let firstId = firstPhoto.localIdentifier, firstId.hasPrefix(AppCapturePhotoService.prefix),
                   let meta = AppCapturePhotoService.shared.metadata(identifier: firstId) {
                    print("[buildBlogDetail] ✅ '\(stop.placeTitle)': visitedTimeDigitized=\(meta.digitizedTime) (app-capture)")
                    detail.days[dayIdx].placeStops[stopIdx].visitedTimeDigitized = meta.digitizedTime
                    continue
                }

                guard let asset = assetMap[firstPhoto.localIdentifier ?? ""] else {
                    print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': skipped visitedTimeDigitized (missing PHAsset)")
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
                    // No EXIF timezone (e.g. in-app camera photos) — use device timezone instead of UTC.
                    let deviceOffset = (TimeZone.current.secondsFromGMT() / 900) * 900
                    print("[buildBlogDetail] ⚠️ '\(stop.placeTitle)': no EXIF timezone for any photo — falling back to device timezone (offset \(deviceOffset / 3600)h)")
                    consensusOffset = deviceOffset
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

        // Fetch weather for each day from Open-Meteo.
        detail = await applyWeather(to: detail)

        // Infer transport mode for each consecutive stop pair using on-device LLM (iOS 26+).
        // visitedTimeDigitized must be set above before this runs.
        if #available(iOS 26, *) {
            detail = await applyTransportModeInference(to: detail)
        }

        return detail
    }

    @available(iOS 26, *)
    private func applyTransportModeInference(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        var result = detail
        for dayIdx in result.days.indices {
            let stops = result.days[dayIdx].placeStops
            for stopIdx in stops.indices {
                guard !Task.isCancelled else { return result }
                guard result.days[dayIdx].placeStops[stopIdx].transportModeToNextStop == nil else { continue }
                guard stopIdx + 1 < stops.count else { continue }
                let a = result.days[dayIdx].placeStops[stopIdx]
                let b = result.days[dayIdx].placeStops[stopIdx + 1]
                result.days[dayIdx].placeStops[stopIdx].transportModeToNextStop = await TravelMode.infer(from: a, to: b)
            }
        }
        return result
    }

    /// Called when a blog page opens. Fills in any missing transport modes using the on-device LLM.
    /// No-op on iOS < 26 or if all stops already have a stored mode.
    func inferTransportModesIfNeeded(for blogId: UUID) async {
        guard #available(iOS 26, *) else { return }
        guard var detail = blogDetailsBySourceId[blogId] else { return }
        let needsInference = detail.days.contains { day in
            day.placeStops.dropLast().contains { $0.transportModeToNextStop == nil }
        }
        guard needsInference else { return }
        detail = await applyTransportModeInference(to: detail)
        blogDetailsBySourceId[blogId] = detail
        saveBlogDetail(detail, asDraft: true)
    }

    // MARK: - Day-by-day processing (rate limit 50 geocode/min)

    /// Builds blog detail with structure for all days but only processes day 0 (geocode, title, visitedTime, photo quality).
    /// Use before navigating to recap; then call continueGeocodingDays(blogId:) when the recap page loads.
    func buildBlogDetailFirstDayOnly(from trip: TripDraft, onProgress: ((Double) -> Void)? = nil) async -> RecapBlogDetail {
        // Progress budget: geocoding 0.05→0.30, visitedTime 0.30→0.97 (scoring/cover/weather are background)
        var detail = buildBlogDetail(from: trip)
        onProgress?(0.05)
        guard let firstDayIdx = detail.days.indices.first else { return detail }

        // Process only day 0: geocode, then title/country from day 0, visitedTime for day 0, photo quality for day 0.
        var cityCandidates: [(city: String, order: Int)] = []
        var countryCandidates: [(country: String, weight: Int, order: Int)] = []
        var order = 0
        let geocodableStops = detail.days[firstDayIdx].placeStops.indices.filter {
            detail.days[firstDayIdx].placeStops[$0].representativeLocation != nil
        }
        let stopTotal = max(1, geocodableStops.count)
        var stopsDone = 0
        for stopIdx in detail.days[firstDayIdx].placeStops.indices {
            applySavedAppCapturePlaceMetadata(to: &detail.days[firstDayIdx].placeStops[stopIdx])
            let stop = detail.days[firstDayIdx].placeStops[stopIdx]
            if Task.isCancelled { return detail }
            if let coord = stop.representativeLocation {
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let place = await GeocodingService.shared.place(for: loc)
                cityCandidates.append((place.cityName, order))
                let weight = max(1, stop.photos.filter(\.isIncluded).count)
                countryCandidates.append((place.countryName, weight, order))
                order += 1
                var dayCopy = detail.days[firstDayIdx]
                var stopCopy = dayCopy.placeStops[stopIdx]
                if !stopCopy.placeTitleIsManual {
                    let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(areaName: place.areaName, coordinate: loc.coordinate)
                    stopCopy.placeTitle = resolvedTitle
                    stopCopy.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                    if let cat = resolvedCategory, stopCopy.placeCategory == nil {
                        stopCopy.placeCategory = cat
                    }
                    syncAppCaptureMetaFromResolvedStop(stopCopy)
                }
                dayCopy.placeStops[stopIdx] = stopCopy
                detail.days[firstDayIdx] = dayCopy
                stopsDone += 1
                onProgress?(0.05 + 0.25 * Double(stopsDone) / Double(stopTotal))
            }
        }
        detail.days[firstDayIdx].isPlaceNamesResolved = true

        let primaryCity = primaryCityFromCandidates(cityCandidates)
        let primaryCountry = primaryFromWeightedCandidates(countryCandidates)
        let season = seasonFromDetail(detail)
        let cityPart = (primaryCity.isEmpty || primaryCity == "Unknown Place") ? "New Place" : primaryCity
        if let s = season, !s.isEmpty {
            detail.title = "Trip To \(cityPart) in \(s)"
        } else {
            detail.title = "Trip To \(cityPart)"
        }
        // Multi-day blogs: defer country until all days are geocoded (avoids day-0-only bias).
        if detail.days.count == 1 {
            if let primaryCountry, !primaryCountry.isEmpty && primaryCountry != "Unknown" {
                detail.countryName = primaryCountry
            }
        } else if let tripCountry = trip.primaryCountryDisplayName, isValidCountryName(tripCountry) {
            detail.countryName = tripCountry
        }

        detail = await applyVisitedTimeDigitized(to: detail, dayIndices: [firstDayIdx])
        onProgress?(0.97)
        if Task.isCancelled { return detail }
        // Photo scoring, cover selection, and weather are all done after the blog is shown:
        // - resolved days (day 0) via scoreResolvedDaysInBackground(blogId:)
        // - remaining days via continueGeocodingDays → processOneDay
        return detail
    }

    /// Scores photos for any day already marked isPlaceNamesResolved, then updates the cover.
    /// Call from the blog page after buildBlogDetailFirstDayOnly so day 0 is scored without
    /// blocking the creation animation.
    func scoreResolvedDaysInBackground(blogId: UUID) async {
        guard var detail = blogDetailsBySourceId[blogId] else { return }
        let resolvedIndices = detail.days.indices.filter { detail.days[$0].isPlaceNamesResolved }
        guard !resolvedIndices.isEmpty else { return }
        let (updated, didScoreAny) = await applyPhotoQualitySelection(to: detail, dayIndices: resolvedIndices)
        detail = updated
        if didScoreAny {
            updateCoverPhotoFromQualityScores(&detail)
        }
        detail = await applyWeather(to: detail)
        blogDetailsBySourceId[blogId] = detail
        saveBlogDetail(detail, asDraft: true)
        objectWillChange.send()
    }

    /// Process one more day (geocode, visitedTime, photo quality) and merge into stored detail. Call after recommended delay.
    /// Sets processingDayIndexByBlogId when starting and clears when done; notifies observers.
    func continueGeocodingDays(blogId: UUID) async {
        // Only `blogDetailsBySourceId` is needed to geocode and persist; requiring a trip draft caused silent no-ops
        // when detail existed without `tripDraftsBySourceId` (e.g. persistence edge cases).
        guard let detail = blogDetailsBySourceId[blogId] else { return }
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
        updatedDetail = applyResolvedCountry(to: updatedDetail)
        // Update cover only after all days are fully scored so we pick the globally best photo.
        if updatedDetail.days.allSatisfy(\.isPlaceNamesResolved) {
            updateCoverPhotoFromQualityScores(&updatedDetail)
            updatedDetail = updatedDetail.consolidatingDuplicateCalendarDays()
            updatedDetail = applyResolvedCountry(to: updatedDetail)
        }
        blogDetailsBySourceId[blogId] = updatedDetail
        saveBlogDetail(updatedDetail, asDraft: true)
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
            applySavedAppCapturePlaceMetadata(to: &result.days[dayIndex].placeStops[stopIdx])
            var stop = result.days[dayIndex].placeStops[stopIdx]
            if stop.representativeLocation == nil {
                stop.representativeLocation = stop.photos.compactMap(\.location).first
                result.days[dayIndex].placeStops[stopIdx].representativeLocation = stop.representativeLocation
            }
            if Task.isCancelled { return result }
            if let coord = stop.representativeLocation {
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let place = await GeocodingService.shared.place(for: loc)
                if !result.days[dayIndex].placeStops[stopIdx].placeTitleIsManual {
                    let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(areaName: place.areaName, coordinate: loc.coordinate)
                    result.days[dayIndex].placeStops[stopIdx].placeTitle = resolvedTitle
                    result.days[dayIndex].placeStops[stopIdx].placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                    if let cat = resolvedCategory, result.days[dayIndex].placeStops[stopIdx].placeCategory == nil {
                        result.days[dayIndex].placeStops[stopIdx].placeCategory = cat
                    }
                    syncAppCaptureMetaFromResolvedStop(result.days[dayIndex].placeStops[stopIdx])
                }
            }
        }

        result = await applyVisitedTimeDigitized(to: result, dayIndices: [dayIndex])
        if Task.isCancelled { return result }
        let (scored, _) = await applyPhotoQualitySelection(to: result, dayIndices: [dayIndex])
        result = scored
        result = await applyWeather(to: result)
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
        // Only fetch PHAssets for non-app-capture identifiers.
        let phAssetIds = photosToResolve.map(\.2).compactMap(\.localIdentifier).filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
        var assetMap: [String: PHAsset] = [:]
        if !phAssetIds.isEmpty {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: phAssetIds, options: nil)
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
            guard let firstPhoto = photos.min(by: { $0.timestamp < $1.timestamp }) else { continue }

            // App-capture: use stored digitizedTime directly.
            if let firstId = firstPhoto.localIdentifier, firstId.hasPrefix(AppCapturePhotoService.prefix),
               let meta = AppCapturePhotoService.shared.metadata(identifier: firstId) {
                result.days[dayIdx].placeStops[stopIdx].visitedTimeDigitized = meta.digitizedTime
                continue
            }

            guard assetMap[firstPhoto.localIdentifier ?? ""] != nil else { continue }
            let stopOffsets: [Int] = photos.compactMap { photo -> Int? in
                guard let id = photo.localIdentifier, let tz = tzMap[id] else { return nil }
                return (tz.secondsFromGMT() / 900) * 900
            }
            let deviceOffset = (TimeZone.current.secondsFromGMT() / 900) * 900
            let consensusOffset = stopOffsets.isEmpty ? deviceOffset : (stopOffsets.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }.max(by: { $0.value < $1.value })?.key ?? deviceOffset)
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
            print("[CoverPhoto]   id=\(photo.localIdentifier?.prefix(8) ?? "nil")… total=\(String(format: "%.3f", photo.qualityScore?.totalScore ?? 0)) aesthetics=\(String(format: "%.3f", photo.qualityScore?.aesthetics ?? 0)) sharpness=\(String(format: "%.3f", photo.qualityScore?.sharpness ?? 0))")
        }
        let prevCoverId = detail.selectedCoverPhotoIdentifier
        if let bestPhoto = scoredPhotos.max(by: { ($0.qualityScore?.totalScore ?? 0) < ($1.qualityScore?.totalScore ?? 0) }),
           let bestPhotoId = bestPhoto.localIdentifier {
            detail.selectedCoverPhotoIdentifier = bestPhotoId
            print("[CoverPhoto] Updated cover: \(prevCoverId?.prefix(8) ?? "nil")… → \(bestPhotoId.prefix(8))… (score=\(String(format: "%.3f", bestPhoto.qualityScore?.totalScore ?? 0)))")
        } else {
            // Camera / in-app captures are not in the photo library — pick first included capture with a still on disk.
            let fallbackId = detail.days
                .flatMap(\.placeStops)
                .flatMap(\.photos)
                .filter(\.isIncluded)
                .compactMap(\.localIdentifier)
                .first { id in
                    id.hasPrefix(AppCapturePhotoService.prefix)
                        && AppCapturePhotoService.shared.imageExists(identifier: id)
                }
            if let fallbackId {
                detail.selectedCoverPhotoIdentifier = fallbackId
                print("[CoverPhoto] Fallback cover from in-app capture: \(prevCoverId?.prefix(8) ?? "nil")… → \(fallbackId.prefix(8))…")
            } else {
                print("[CoverPhoto] No scored photos found — keeping initial cover: \(prevCoverId?.prefix(8) ?? "nil")…")
            }
        }
    }

    /// Scores every photo using Vision AI and auto-selects the best per place stop.
    private func applyPhotoQualitySelection(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        let (updated, _) = await applyPhotoQualitySelection(to: detail, dayIndices: detail.days.indices.map { $0 })
        return updated
    }

    /// Scores photos missing `qualityScore` and auto-selects best per place stop for the given day indices only.
    /// Returns whether any photo was newly scored (false when every photo already had a score).
    private func applyPhotoQualitySelection(
        to detail: RecapBlogDetail,
        dayIndices: [Int]
    ) async -> (RecapBlogDetail, didScoreAny: Bool) {
        var updated = detail
        let scorer = PhotoQualityScorer.shared
        let daySet = Set(dayIndices)
        var didScoreAny = false

        for dayIdx in updated.days.indices where daySet.contains(dayIdx) {
            for stopIdx in updated.days[dayIdx].placeStops.indices {
                if Task.isCancelled { return (updated, didScoreAny) }
                if await scorePhotosIfNeeded(
                    &updated.days[dayIdx].placeStops[stopIdx].photos,
                    scorer: scorer
                ) {
                    didScoreAny = true
                }
            }
        }

        return (updated, didScoreAny)
    }

    /// Scores library and in-app photos missing `qualityScore`. Re-applies smart selection only when at least one photo was newly scored.
    private func scorePhotosIfNeeded(
        _ photos: inout [RecapPhoto],
        scorer: PhotoQualityScorer
    ) async -> Bool {
        let hadAnyScoreBeforeThisPass = photos.contains { $0.qualityScore != nil }
        let identifiersToScore = Set(photos.localIdentifiersForQualityScoring())
        let libraryIdsToScore = identifiersToScore.filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }

        var didScoreNew = false

        if !libraryIdsToScore.isEmpty {
            let scores = await scorer.scorePhotos(identifiers: Array(libraryIdsToScore))
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(libraryIdsToScore), options: nil)
            var favoriteIdentifiers: Set<String> = []
            fetchResult.enumerateObjects { asset, _, _ in
                if asset.isFavorite { favoriteIdentifiers.insert(asset.localIdentifier) }
            }

            for photoIdx in photos.indices {
                let photo = photos[photoIdx]
                if let id = photo.localIdentifier, libraryIdsToScore.contains(id) {
                    photos[photoIdx].isFavorite = favoriteIdentifiers.contains(id)
                }
                guard photo.qualityScore == nil,
                      let id = photo.localIdentifier,
                      let score = scores[id] else { continue }
                photos[photoIdx].qualityScore = score
                didScoreNew = true
            }
        }

        for photoIdx in photos.indices {
            guard photos[photoIdx].qualityScore == nil,
                  let id = photos[photoIdx].localIdentifier,
                  id.hasPrefix(AppCapturePhotoService.prefix),
                  identifiersToScore.contains(id) else { continue }
            if let score = await scorer.scoreAppCapture(identifier: id) {
                photos[photoIdx].qualityScore = score
                didScoreNew = true
            }
        }

        guard didScoreNew, !hadAnyScoreBeforeThisPass else { return didScoreNew }

        // Initial auto-select only when no photo in this stop had been scored before.
        let topIds = photos.autoSelectedIds()
        guard !topIds.isEmpty else { return true }

        for photoIdx in photos.indices {
            photos[photoIdx].isIncluded = topIds.contains(photos[photoIdx].id)
        }
        return true
    }

    /// Fetches Open-Meteo weather for each day using the first available coordinate.
    /// Days that already have weather or have no location data are skipped.
    private func applyWeather(to detail: RecapBlogDetail) async -> RecapBlogDetail {
        var updated = detail
        let tripRange = detail.days.map(\.date).min().map { min in
            let max = detail.days.map(\.date).max() ?? min
            return "\(TripCalendarDayKey.from(date: min))…\(TripCalendarDayKey.from(date: max))"
        } ?? "—"
        print(
            "[WeatherService] applyWeather start: \(detail.days.count) days, " +
            "trip=\(detail.title), range=\(tripRange)"
        )

        var pending: [(dayIdx: Int, date: Date, latitude: Double, longitude: Double)] = []
        var skippedManual = 0
        var skippedExisting = 0
        var skippedNoLocation = 0

        for dayIdx in updated.days.indices {
            if Task.isCancelled { return updated }
            let day = updated.days[dayIdx]
            if day.weatherIsManual {
                skippedManual += 1
                continue
            }
            if day.weather != nil {
                skippedExisting += 1
                continue
            }
            guard let coord = day.placeStops.compactMap(\.representativeLocation).first else {
                skippedNoLocation += 1
                continue
            }
            pending.append((dayIdx, day.date, coord.latitude, coord.longitude))
        }

        if pending.isEmpty {
            print(
                "[WeatherService] applyWeather done: nothing to fetch " +
                "(skipped manual=\(skippedManual) existing=\(skippedExisting) noLocation=\(skippedNoLocation))"
            )
            return updated
        }

        let weatherByKey = await WeatherService.shared.fetchWeather(
            requests: pending.map { (date: $0.date, latitude: $0.latitude, longitude: $0.longitude) }
        )

        var fetched = 0
        var failed = 0
        for item in pending {
            let key = WeatherService.shared.cacheKey(
                latitude: item.latitude,
                longitude: item.longitude,
                date: item.date
            )
            if let weather = weatherByKey[key] {
                updated.days[item.dayIdx].weather = weather
                fetched += 1
                let dayIndex = updated.days[item.dayIdx].dayIndex
                print(
                    "[WeatherService] ✅ Day \(dayIndex): \(weather.emoji) \(weather.description), " +
                    "\(String(format: "%.0f", weather.tempMaxC))°C / \(String(format: "%.0f", weather.tempMinC))°C"
                )
            } else {
                failed += 1
                let day = updated.days[item.dayIdx]
                print(
                    "[WeatherService] ⚠️ Day \(day.dayIndex): no weather data " +
                    "(calendarKey=\(day.storyBookCalendarDayKey), coord=\(item.latitude), \(item.longitude))"
                )
            }
        }

        print(
            "[WeatherService] applyWeather done: fetched=\(fetched) failed=\(failed) " +
            "skipped(manual=\(skippedManual) existing=\(skippedExisting) noLocation=\(skippedNoLocation))"
        )
        return updated
    }

    /// Loads blog detail, runs quality scoring and auto-selection for the given days, then saves.
    /// Used after injecting newly scanned photos so only good-quality photos are preselected.
    private func applyPhotoQualitySelectionForBlog(sourceTripId: UUID, dayIndices: [Int]) async {
        guard let detail = blogDetailsBySourceId[sourceTripId], !dayIndices.isEmpty else { return }
        let (updated, didScoreAny) = await applyPhotoQualitySelection(to: detail, dayIndices: dayIndices)
        guard didScoreAny else { return }
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

        // Trips → Create leaves `lastEditedAt` nil until the user taps Save on the recap.
        // Do not prompt for New Moments on that first session; same rule as `hasBlogBeenSavedToDevice` on RecapBlogPageView.
        if let recent = recents.first(where: { $0.sourceTripId == blogId }), recent.lastEditedAt == nil {
            return []
        }

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
        // Use the same home-radius exclusion as trip discovery (`TripPhotoFilter` / Set Home range).
        // Otherwise iPhone Camera shots taken at home (still within the 24h continuation window) appear
        // as "new moments" and inherit the scanned trip's place title, which mismatches GPS.
        let trips = await PhotoLibraryTripService.shared.scanInDateRange(
            startDate: cutoff,
            endDate: upperBound,
            ignoreHomeExclusion: false
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

    /// Full rescan triggered manually from Blog Settings.
    /// Scans from the blog's first day to now. New photos are automatically injected:
    /// - Photos matching an existing stop are added with isIncluded = false (unselected).
    /// - Photos that don't belong to any existing stop are clustered into new place stops,
    ///   quality-scored to auto-select the best photos, and reverse-geocoded.
    /// Returns the number of new stops created and photos silently added to existing stops.
    func performFullRescanAndInject(blogId: UUID) async -> (newStops: Int, addedToExisting: Int) {
        guard let detail = blogDetailsBySourceId[blogId] else { return (0, 0) }

        let firstDayDate = detail.days.first?.date ?? Date.distantPast
        let scanStart = Calendar.current.startOfDay(for: firstDayDate)
        let scanEnd = Date()

        let trips = await PhotoLibraryTripService.shared.scanInDateRange(
            startDate: scanStart,
            endDate: scanEnd,
            ignoreHomeExclusion: true
        )

        let scannedPhotos = trips.flatMap { $0.days.flatMap(\.photos) }
        guard !scannedPhotos.isEmpty else { return (0, 0) }

        let existingIds = Set(detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier))
        let newPhotos = scannedPhotos.filter { photo in
            photo.localIdentifier.map { !existingIds.contains($0) } ?? true
        }.sorted { $0.timestamp < $1.timestamp }

        guard !newPhotos.isEmpty else { return (0, 0) }

        return await injectPhotosFromRescan(
            newPhotos,
            intoSourceTripId: blogId,
            notifyMenuIndicator: true
        )
    }

    /// Injects photos from a full rescan with differentiated treatment for existing vs. new stops.
    /// Photos matched to existing stops are added unselected; photos forming new groups get
    /// their own PlaceStop with quality-based auto-selection and reverse geocoding.
    private func injectPhotosFromRescan(
        _ newPhotos: [MockPhoto],
        intoSourceTripId sourceTripId: UUID,
        notifyMenuIndicator: Bool
    ) async -> (newStops: Int, addedToExisting: Int) {
        guard !newPhotos.isEmpty,
              var detail = blogDetailsBySourceId[sourceTripId] else { return (0, 0) }

        let gapLimit: TimeInterval = Double(ScanConfig.gapHoursNewSegment) * 3600
        let locationLimit: Double = ScanConfig.placeClusterMeters

        let existingIds = Set(detail.days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier))
        let photos = newPhotos.filter { photo in
            guard let lid = photo.localIdentifier, !lid.isEmpty else { return false }
            guard !existingIds.contains(lid) else { return false }
            return !EverydayMomentsStore.shared.containsCapture(identifier: lid)
        }
        guard !photos.isEmpty else { return (0, 0) }

        let dayKeys = await calendarDayKeys(for: photos)
        let byDay = Dictionary(grouping: photos) { dayKeys[$0.id] ?? TripCalendarDayKey.from(date: $0.timestamp) }

        var newStopIds: [UUID] = []
        var addedToExisting = 0
        var newStopsToGeocode: [(dayIdx: Int, stopId: UUID)] = []

        for (dayKey, dayPhotos) in byDay.sorted(by: { $0.key < $1.key }) {
            let dayDate = TripCalendarDayKey.canonicalDate(from: dayKey) ?? dayPhotos.map(\.timestamp).min() ?? Date()
            var dayIdx = detail.days.firstIndex(where: { $0.storyBookCalendarDayKey == dayKey })
            if dayIdx == nil {
                let newDay = RecapBlogDay(dayIndex: 0, date: dayDate, placeStops: [])
                detail.days.append(newDay)
                detail.days.sort { $0.date < $1.date }
                for i in detail.days.indices { detail.days[i].dayIndex = i + 1 }
                dayIdx = detail.days.firstIndex(where: { $0.storyBookCalendarDayKey == dayKey })!
            }
            guard let di = dayIdx else { continue }

            var unmatchedRecapPhotos: [RecapPhoto] = []

            for photo in dayPhotos.sorted(by: { $0.timestamp < $1.timestamp }) {
                let isInAppCapture = photo.localIdentifier?.hasPrefix(AppCapturePhotoService.prefix) ?? false
                let recapPhoto = RecapPhoto(
                    id: photo.id,
                    timestamp: photo.timestamp,
                    location: locationForInjectedMockPhoto(photo),
                    imageName: photo.imageName,
                    isIncluded: isInAppCapture,
                    localIdentifier: photo.localIdentifier
                )

                // Match to the closest existing stop within gap + location thresholds.
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

                    if gap < bestGap { bestGap = gap; bestIdx = si }
                }

                if let si = bestIdx {
                    // Existing stop: add unselected, skip quality scoring for this stop.
                    detail.days[di].placeStops[si].photos.append(recapPhoto)
                    detail.days[di].placeStops[si].photos.sort { $0.timestamp < $1.timestamp }
                    addedToExisting += 1
                } else {
                    unmatchedRecapPhotos.append(recapPhoto)
                }
            }

            // Cluster unmatched photos into new place stops.
            if !unmatchedRecapPhotos.isEmpty {
                let inputs = unmatchedRecapPhotos.map { ClusterPhotoInput(id: $0.id, timestamp: $0.timestamp, location: $0.location) }
                let baseIndex = detail.days[di].placeStops.count
                let groups = clusteringService.placeStops(from: inputs) { idx in "Stop \(baseIndex + idx + 1)" }
                for (orderIndex, groupInputs) in groups {
                    let groupPhotos = groupInputs.compactMap { input in
                        unmatchedRecapPhotos.first { $0.id == input.id }
                    }.sorted { $0.timestamp < $1.timestamp }
                    let repLoc = groupPhotos.compactMap(\.location).first
                    let placeTitle: String
                    if repLoc == nil {
                        placeTitle = groups.count > 1 ? "Captured Moment \(orderIndex + 1)" : "Captured Moment"
                    } else {
                        placeTitle = "Stop \(detail.days[di].placeStops.count + 1)"
                    }
                    var newStop = PlaceStop(
                        orderIndex: detail.days[di].placeStops.count,
                        placeTitle: placeTitle,
                        representativeLocation: repLoc,
                        photos: groupPhotos
                    )
                    applySavedAppCapturePlaceMetadata(to: &newStop)
                    detail.days[di].placeStops.append(newStop)
                    newStopIds.append(newStop.id)
                    if newStop.representativeLocation != nil, !newStop.placeTitleIsManual {
                        newStopsToGeocode.append((dayIdx: di, stopId: newStop.id))
                    }
                }
            }

            sortPlaceStopsChronologically(&detail.days[di].placeStops)
        }

        detail = detail.consolidatingDuplicateCalendarDays()
        saveBlogDetail(detail, asDraft: true)

        // Geocode new stops, then quality-score only those stops (leave existing stops untouched).
        Task {
            if !newStopsToGeocode.isEmpty,
               var geocodedDetail = blogDetailsBySourceId[sourceTripId] {
                for entry in newStopsToGeocode {
                    let di = entry.dayIdx
                    guard di < geocodedDetail.days.count,
                          let si = geocodedDetail.days[di].placeStops.firstIndex(where: { $0.id == entry.stopId }),
                          let coord = geocodedDetail.days[di].placeStops[si].representativeLocation else { continue }
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let place = await GeocodingService.shared.place(for: loc)
                    if !geocodedDetail.days[di].placeStops[si].placeTitleIsManual {
                        let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(areaName: place.areaName, coordinate: loc.coordinate)
                        geocodedDetail.days[di].placeStops[si].placeTitle = resolvedTitle
                        geocodedDetail.days[di].placeStops[si].placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
                        if let cat = resolvedCategory, geocodedDetail.days[di].placeStops[si].placeCategory == nil {
                            geocodedDetail.days[di].placeStops[si].placeCategory = cat
                        }
                        syncAppCaptureMetaFromResolvedStop(geocodedDetail.days[di].placeStops[si])
                    }
                }
                geocodedDetail = geocodedDetail.consolidatingDuplicateCalendarDays()
                saveBlogDetail(geocodedDetail, asDraft: true)
            }
            if !newStopIds.isEmpty {
                await applyPhotoQualitySelectionForStops(sourceTripId: sourceTripId, stopIds: Set(newStopIds))
            }
            if var finalDetail = blogDetailsBySourceId[sourceTripId] {
                finalDetail = finalDetail.consolidatingDuplicateCalendarDays()
                saveBlogDetail(finalDetail, asDraft: true)
            }
        }

        // Update blog metadata.
        guard let savedDetail = blogDetailsBySourceId[sourceTripId] else {
            return (newStops: newStopIds.count, addedToExisting: addedToExisting)
        }
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            let newStart = RecapBlogDay.alignedTripStartDate(from: savedDetail.days)
            let newEnd = RecapBlogDay.alignedTripEndDate(from: savedDetail.days)
            if let minDate = newStart,
               (recents[idx].tripStartDate == nil || minDate < recents[idx].tripStartDate!) {
                recents[idx].tripStartDate = minDate
            }
            if let maxDate = newEnd,
               (recents[idx].tripEndDate == nil || maxDate > recents[idx].tripEndDate!) {
                recents[idx].tripEndDate = maxDate
            }
            recents[idx].tripDateRangeText = Self.formatDateRange(start: recents[idx].tripStartDate, end: recents[idx].tripEndDate)
            recents[idx].selectedPhotoCount = savedDetail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
            recents[idx].totalPlaceVisitCount = savedDetail.days.reduce(0) { $0 + $1.placeStops.count }
            recents[idx].tripDurationDays = savedDetail.days.count
            recents[idx].lastEditedAt = Date()
            recents[idx].syncStatus = .needsUpload
            persistRecents()
        }

        if notifyMenuIndicator {
            BlogMenuIndicatorStore.shared.noteMomentsAdded(to: sourceTripId)
        }

        unlinkEverydayCapturesNowInBlog(photos.compactMap(\.localIdentifier))

        return (newStops: newStopIds.count, addedToExisting: addedToExisting)
    }

    /// Scores and auto-selects photos only within the specified stop IDs.
    /// Used after a full rescan so existing stops are not re-scored.
    private func applyPhotoQualitySelectionForStops(sourceTripId: UUID, stopIds: Set<UUID>) async {
        guard var detail = blogDetailsBySourceId[sourceTripId], !stopIds.isEmpty else { return }
        let scorer = PhotoQualityScorer.shared
        var didScoreAny = false

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                guard stopIds.contains(detail.days[dayIdx].placeStops[stopIdx].id) else { continue }
                if Task.isCancelled { return }
                if await scorePhotosIfNeeded(
                    &detail.days[dayIdx].placeStops[stopIdx].photos,
                    scorer: scorer
                ) {
                    didScoreAny = true
                }
            }
        }

        guard didScoreAny else { return }

        saveBlogDetail(detail, asDraft: true)
        if let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) {
            recents[idx].selectedPhotoCount = detail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
            persistRecents()
        }
    }

    // MARK: - Country backfill

    private var isBackfillingCountries = false

    /// Reverse-geocodes blogs missing a country so My Blogs groups them correctly.
    func backfillMissingCountriesIfNeeded() {
        guard !isBackfillingCountries else { return }
        Task { await backfillMissingCountries() }
    }

    private func backfillMissingCountries() async {
        let blogsNeedingCountry = recents.filter { blog in
            if let detail = blogDetailsBySourceId[blog.sourceTripId],
               let expected = primaryCountryFromDetail(detail, trip: tripDraftsBySourceId[blog.sourceTripId]) {
                return blog.countryName != expected
            }
            return !isValidCountryName(resolvedCountryName(for: blog))
        }
        guard !blogsNeedingCountry.isEmpty else { return }
        isBackfillingCountries = true
        defer {
            isBackfillingCountries = false
            objectWillChange.send()
        }

        var recentsChanged = false
        var detailsChanged = false

        for blog in blogsNeedingCountry {
            if Task.isCancelled { return }

            if let detail = blogDetailsBySourceId[blog.sourceTripId],
               let country = primaryCountryFromDetail(detail, trip: tripDraftsBySourceId[blog.sourceTripId]),
               let idx = recents.firstIndex(where: { $0.sourceTripId == blog.sourceTripId }) {
                recents[idx].countryName = country
                recentsChanged = true
                var updated = detail
                updated.countryName = country
                blogDetailsBySourceId[blog.sourceTripId] = updated
                detailsChanged = true
                continue
            }

            guard let detail = blogDetailsBySourceId[blog.sourceTripId] else { continue }
            let stopCount = detail.days.flatMap(\.placeStops).filter { stop in
                stop.representativeLocation != nil || stop.photos.contains { $0.location != nil }
            }.count
            if stopCount > 0 {
                let delay = await GeocodingService.shared.recommendedDelayBeforeNextBatch(estimatedNewCalls: min(stopCount, 5))
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }

            let (updatedDetail, country) = await resolveCountryByGeocodingDetail(detail)
            guard let country, isValidCountryName(country) else { continue }

            blogDetailsBySourceId[blog.sourceTripId] = updatedDetail
            detailsChanged = true
            if let idx = recents.firstIndex(where: { $0.sourceTripId == blog.sourceTripId }) {
                recents[idx].countryName = country
                recentsChanged = true
            }
        }

        if detailsChanged { persistBlogDetails() }
        if recentsChanged { persistRecents() }
    }

    private func resolveCountryByGeocodingDetail(_ detail: RecapBlogDetail) async -> (RecapBlogDetail, String?) {
        var detail = detail
        var candidates: [(country: String, weight: Int, order: Int)] = []
        var geocodeCache: [String: String] = [:]
        var order = 0

        for dayIdx in detail.days.indices {
            for stopIdx in detail.days[dayIdx].placeStops.indices {
                var stop = detail.days[dayIdx].placeStops[stopIdx]
                if stop.representativeLocation == nil {
                    stop.representativeLocation = stop.photos.compactMap(\.location).first
                    detail.days[dayIdx].placeStops[stopIdx].representativeLocation = stop.representativeLocation
                }
                let weight = max(1, stop.photos.filter(\.isIncluded).count)

                if let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !subtitle.isEmpty,
                   let country = countryFromPlaceSubtitle(subtitle),
                   isValidCountryName(country) {
                    candidates.append((country, weight, order))
                    order += 1
                    continue
                }

                guard let coord = stop.representativeLocation else { continue }
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let cacheKey = geocodeCacheKey(for: loc)

                let countryName: String?
                if let cached = geocodeCache[cacheKey] {
                    countryName = cached.isEmpty ? nil : cached
                } else {
                    let place = await GeocodingService.shared.place(for: loc)
                    countryName = isValidCountryName(place.countryName) ? place.countryName : nil
                    geocodeCache[cacheKey] = countryName ?? ""
                    if detail.days[dayIdx].placeStops[stopIdx].placeSubtitle == nil, !place.subtitle.isEmpty {
                        detail.days[dayIdx].placeStops[stopIdx].placeSubtitle = place.subtitle
                    }
                }

                if let countryName, isValidCountryName(countryName) {
                    candidates.append((countryName, weight, order))
                    order += 1
                }
            }
        }

        let country = primaryFromWeightedCandidates(candidates)
            ?? primaryCountryFromDetail(detail)
        if let country, isValidCountryName(country) {
            detail.countryName = country
            return (detail, country)
        }
        return (detail, nil)
    }

    private func applyResolvedCountry(to detail: RecapBlogDetail) -> RecapBlogDetail {
        var detail = detail
        if let country = primaryCountryFromDetail(detail, trip: tripDraftsBySourceId[detail.id])
            ?? countryNameFromBlogTitle(detail.title) {
            detail.countryName = country
        }
        return detail
    }

    // MARK: - Private Helpers

    private func isValidCountryName(_ name: String?) -> Bool {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return false }
        return trimmed != "Unknown"
    }

    /// Best available country for grouping/display — photo-weighted majority across all place stops.
    func resolvedCountryName(for blog: CreatedRecapBlog) -> String? {
        if let detail = blogDetailsBySourceId[blog.sourceTripId],
           let fromDetail = primaryCountryFromDetail(detail, trip: tripDraftsBySourceId[blog.sourceTripId]) {
            return fromDetail
        }
        if let trip = tripDraftsBySourceId[blog.sourceTripId],
           isValidCountryName(trip.primaryCountryDisplayName),
           let name = trip.primaryCountryDisplayName {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isValidCountryName(blog.countryName), let name = blog.countryName {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return countryNameFromBlogTitle(blog.title)
    }

    private func countryGroupingKey(for blog: CreatedRecapBlog) -> String {
        if let country = resolvedCountryName(for: blog) { return country }
        if let label = interimLocationLabel(for: blog) { return label }
        return "Unknown-\(blog.sourceTripId.uuidString)"
    }

    private func interimLocationLabel(for blog: CreatedRecapBlog) -> String? {
        if let detail = blogDetailsBySourceId[blog.sourceTripId] {
            for day in detail.days {
                for stop in day.placeStops {
                    let title = stop.placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty, !title.hasPrefix("Stop "), title != "Captured Moment" {
                        return title
                    }
                    if let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !subtitle.isEmpty {
                        let city = subtitle.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let city, !city.isEmpty { return city }
                    }
                }
            }
        }
        if let city = cityFromTripToTitle(blog.title) { return city }
        if let trip = tripDraftsBySourceId[blog.sourceTripId] {
            let city = trip.cityWithMostPhotosDisplayName
            if !city.isEmpty, city != "New Place" { return city }
        }
        return nil
    }

    private func cityFromTripToTitle(_ title: String) -> String? {
        guard title.hasPrefix("Trip To ") else { return nil }
        var rest = String(title.dropFirst("Trip To ".count))
        if let inRange = rest.range(of: " in ") {
            rest = String(rest[..<inRange.lowerBound])
        }
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "New Place" ? nil : trimmed
    }

    private func countryFromPlaceSubtitle(_ subtitle: String) -> String? {
        let parts = subtitle.components(separatedBy: ", ").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        return last
    }

    /// Photo-weighted majority country from geocoded place subtitles across all stops.
    private func primaryCountryFromDetail(_ detail: RecapBlogDetail, trip: TripDraft? = nil) -> String? {
        var candidates: [(country: String, weight: Int, order: Int)] = []
        var order = 0
        for day in detail.days {
            for stop in day.placeStops {
                let weight = max(1, stop.photos.filter(\.isIncluded).count)
                if let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !subtitle.isEmpty,
                   let country = countryFromPlaceSubtitle(subtitle),
                   isValidCountryName(country) {
                    candidates.append((country, weight, order))
                    order += 1
                }
            }
        }
        if let fromStops = primaryFromWeightedCandidates(candidates) { return fromStops }
        if let trip, let country = trip.primaryCountryDisplayName, isValidCountryName(country) {
            return country
        }
        return nil
    }

    /// Backfills and corrects `countryName` on saved blogs from photo-weighted place data.
    private func refreshRecentsCountryFromBlogDetails() {
        var recentsChanged = false
        var detailsChanged = false
        for idx in recents.indices {
            let sourceTripId = recents[idx].sourceTripId
            guard let detail = blogDetailsBySourceId[sourceTripId] else { continue }
            guard let resolved = primaryCountryFromDetail(detail, trip: tripDraftsBySourceId[sourceTripId])
                ?? countryNameFromBlogTitle(detail.title) else { continue }
            if recents[idx].countryName != resolved {
                recents[idx].countryName = resolved
                recentsChanged = true
            }
            if detail.countryName != resolved {
                var updated = detail
                updated.countryName = resolved
                blogDetailsBySourceId[sourceTripId] = updated
                detailsChanged = true
            }
        }
        if detailsChanged { persistBlogDetails() }
        if recentsChanged { persistRecents() }
    }

    private func primaryFromWeightedCandidates(_ candidates: [(country: String, weight: Int, order: Int)]) -> String? {
        guard !candidates.isEmpty else { return nil }
        var totals: [String: (weight: Int, firstOrder: Int)] = [:]
        for (country, weight, order) in candidates where isValidCountryName(country) {
            if let existing = totals[country] {
                totals[country] = (existing.weight + weight, existing.firstOrder)
            } else {
                totals[country] = (weight, order)
            }
        }
        let sorted = totals.sorted { a, b in
            if a.value.weight != b.value.weight { return a.value.weight > b.value.weight }
            return a.value.firstOrder < b.value.firstOrder
        }
        return sorted.first?.key
    }

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

    private func countryNameFromBlogTitle(_ title: String) -> String? {
        var base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix(" Trip") {
            let country = String(base.dropLast(" Trip".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidCountryName(country) { return country }
        }
        if let inRange = base.range(of: " in ", options: .backwards) {
            base = String(base[..<inRange.lowerBound])
        }
        guard let commaIdx = base.lastIndex(of: ",") else { return nil }
        let country = String(base[base.index(after: commaIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidCountryName(country) ? country : nil
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
        let grouped = Dictionary(grouping: published) { countryGroupingKey(for: $0) }
        return grouped.compactMap { countryName, blogs in
            guard let mostRecent = blogs.max(by: {
                ($0.tripEndDate ?? $0.tripStartDate ?? $0.createdAt) < ($1.tripEndDate ?? $1.tripStartDate ?? $1.createdAt)
            }) else { return nil }
            return CountryRecapSummary(
                countryName: countryName,
                mostRecentBlog: mostRecent,
                blogs: blogs.sorted {
                    ($0.tripEndDate ?? $0.tripStartDate ?? $0.createdAt) > ($1.tripEndDate ?? $1.tripStartDate ?? $1.createdAt)
                }
            )
        }
        .sorted {
            ($0.mostRecentBlog.tripEndDate ?? $0.mostRecentBlog.tripStartDate ?? $0.mostRecentBlog.createdAt) >
            ($1.mostRecentBlog.tripEndDate ?? $1.mostRecentBlog.tripStartDate ?? $1.mostRecentBlog.createdAt)
        }
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
        let grouped = Dictionary(grouping: filtered) { countryGroupingKey(for: $0) }
        return grouped.compactMap { countryName, blogs in
            guard let mostRecent = blogs.max(by: {
                ($0.tripEndDate ?? $0.tripStartDate ?? $0.createdAt) < ($1.tripEndDate ?? $1.tripStartDate ?? $1.createdAt)
            }) else { return nil }
            return CountryRecapSummary(
                countryName: countryName,
                mostRecentBlog: mostRecent,
                blogs: blogs.sorted {
                    ($0.tripEndDate ?? $0.tripStartDate ?? $0.createdAt) > ($1.tripEndDate ?? $1.tripStartDate ?? $1.createdAt)
                }
            )
        }
        .sorted {
            ($0.mostRecentBlog.tripEndDate ?? $0.mostRecentBlog.tripStartDate ?? $0.mostRecentBlog.createdAt) >
            ($1.mostRecentBlog.tripEndDate ?? $1.mostRecentBlog.tripStartDate ?? $1.mostRecentBlog.createdAt)
        }
    }

    /// Derived list of visited places aggregated across all visible blogs and everyday moments (latest-first).
    /// - Note: Uses persisted blogDetailsBySourceId only (no on-the-fly rebuild) plus EverydayMomentsStore.
    var visitedPlaces: [VisitedPlaceSummary] {
        let blogPlaces = blogDerivedVisitedPlaces
        let everydayPlaces = EverydayMomentsStore.shared.visitedPlaceSummaries
        return mergeVisitedPlaceSummaries(blogPlaces: blogPlaces, everydayPlaces: everydayPlaces)
    }

    private var blogDerivedVisitedPlaces: [VisitedPlaceSummary] {
        let blogs = visibleRecents
        var byKey: [String: (place: VisitedPlaceSummary, latest: Date)] = [:]

        for blog in blogs {
            guard let detail = blogDetailsBySourceId[blog.sourceTripId] else { continue }
            let country = (detail.countryName?.isEmpty == false ? detail.countryName : blog.countryName) ?? "Unknown"
            for day in detail.days {
                for stop in day.placeStops {
                    let relatedRef = VisitedPlaceSummary.RelatedBlogRef(
                        blogId: blog.sourceTripId,
                        blogTitle: blog.title,
                        blogDate: blog.tripStartDate ?? blog.createdAt,
                        placeStopId: stop.id
                    )
                    let included = stop.photos.filter(\.isIncluded).filter {
                        guard let lid = $0.localIdentifier else { return true }
                        return !EverydayMomentsStore.shared.containsCapture(identifier: lid)
                    }
                    guard !included.isEmpty else { continue }

                    let latestVisit = included.map(\.timestamp).max() ?? (blog.tripEndDate ?? blog.createdAt)
                    let year = Calendar.current.component(.year, from: latestVisit)
                    let placeName = stop.placeTitle.cleanedAsPlaceTitle
                    let city = stop.placeSubtitle ?? ""
                    let resolvedCategoryRaw = stop.placeCategory
                        ?? PlacePOICategoryPresentation.inferredCategoryRaw(fromPlaceTitle: placeName)

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
                        categoryRawValue: resolvedCategoryRaw,
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

                        let mergedName = newSummary.latestVisitDate > existing.latestVisitDate
                            ? newSummary.placeName
                            : existing.placeName

                        existing = VisitedPlaceSummary(
                            placeId: existing.placeId,
                            placeName: mergedName,
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

    /// Drops My Places captures from the everyday store once they belong to a trip blog.
    private func unlinkEverydayCapturesNowInBlog(_ localIdentifiers: [String]) {
        let ids = Set(localIdentifiers.filter { $0.hasPrefix(AppCapturePhotoService.prefix) })
        guard !ids.isEmpty else { return }
        EverydayMomentsStore.shared.removeCaptures(identifiers: ids)
    }

    /// Removes My Places (daily) captures from blog details and trip drafts.
    /// Daily moments belong in My Places until explicitly promoted via `createTripBlogFromEverydayPhotos`.
    func stripEverydayCapturesFromAllBlogs(identifiers: Set<String>? = nil) {
        let rawIds = identifiers ?? EverydayMomentsStore.shared.everydayCaptureIdentifiers
        let everydayIds = Set(rawIds.filter { $0.hasPrefix(AppCapturePhotoService.prefix) })
        guard !everydayIds.isEmpty else { return }

        var detailsChanged = false
        for key in blogDetailsBySourceId.keys {
            guard var detail = blogDetailsBySourceId[key] else { continue }
            let stripped = stripEverydayCaptures(from: &detail, identifiers: everydayIds)
            guard stripped else { continue }
            detail = detail.consolidatingDuplicateCalendarDays()
            blogDetailsBySourceId[key] = detail
            detailsChanged = true
            refreshRecapMetadataAfterEverydayStrip(sourceTripId: key, detail: detail)
        }

        var draftsChanged = false
        for key in tripDraftsBySourceId.keys {
            guard var trip = tripDraftsBySourceId[key] else { continue }
            guard stripEverydayCaptures(from: &trip, identifiers: everydayIds) else { continue }
            tripDraftsBySourceId[key] = trip
            draftsChanged = true
        }

        if detailsChanged {
            persistBlogDetails()
            objectWillChange.send()
        }
        if draftsChanged {
            persistTripDrafts()
        }
    }

    private func tripDraftExcludingEverydayCaptures(_ trip: TripDraft) -> TripDraft {
        var copy = trip
        stripEverydayCaptures(from: &copy, identifiers: EverydayMomentsStore.shared.everydayCaptureIdentifiers)
        return copy
    }

    /// Removes My Places daily captures from trip drafts (e.g. after Tap to Blog scan).
    func filterTripDraftsExcludingEverydayCaptures(_ trips: [TripDraft]) -> [TripDraft] {
        let ids = EverydayMomentsStore.shared.everydayCaptureIdentifiers
        guard !ids.isEmpty else { return trips }
        return trips.compactMap { trip in
            var copy = trip
            _ = stripEverydayCaptures(from: &copy, identifiers: ids)
            return copy.days.isEmpty ? nil : copy
        }
    }

    /// `bloggo-capture:` ids that must not appear in Tap to Blog scans (saved blogs + My Places daily).
    func bloggoCaptureIdentifiersExcludedFromTripScan() -> Set<String> {
        allInAppCaptureIdentifiersInVisibleBlogs()
            .union(EverydayMomentsStore.shared.everydayCaptureIdentifiers)
    }

    @discardableResult
    private func stripEverydayCaptures(from detail: inout RecapBlogDetail, identifiers: Set<String>) -> Bool {
        guard !identifiers.isEmpty else { return false }
        var changed = false
        for dayIdx in detail.days.indices {
            var keptStops: [PlaceStop] = []
            for var stop in detail.days[dayIdx].placeStops {
                let before = stop.photos.count
                stop.photos.removeAll { photo in
                    guard let lid = photo.localIdentifier else { return false }
                    return identifiers.contains(lid)
                }
                if stop.photos.count != before { changed = true }
                guard !stop.photos.isEmpty else { continue }
                keptStops.append(stop)
            }
            if keptStops.count != detail.days[dayIdx].placeStops.count { changed = true }
            detail.days[dayIdx].placeStops = keptStops
            sortPlaceStopsChronologically(&detail.days[dayIdx].placeStops)
        }
        let nonEmptyDays = detail.days.filter { !$0.placeStops.isEmpty }
        if nonEmptyDays.count != detail.days.count {
            changed = true
            detail.days = nonEmptyDays.enumerated().map { index, day in
                var copy = day
                copy.dayIndex = index + 1
                return copy
            }
        }
        return changed
    }

    @discardableResult
    private func stripEverydayCaptures(from trip: inout TripDraft, identifiers: Set<String>) -> Bool {
        guard !identifiers.isEmpty else { return false }
        var changed = false
        for dayIdx in trip.days.indices {
            let before = trip.days[dayIdx].photos.count
            trip.days[dayIdx].photos.removeAll { photo in
                guard let lid = photo.localIdentifier else { return false }
                return identifiers.contains(lid)
            }
            if trip.days[dayIdx].photos.count != before { changed = true }
        }
        let nonEmptyDays = trip.days.filter { !$0.photos.isEmpty }
        if nonEmptyDays.count != trip.days.count {
            changed = true
            trip.days = nonEmptyDays
        }
        return changed
    }

    private func refreshRecapMetadataAfterEverydayStrip(sourceTripId: UUID, detail: RecapBlogDetail) {
        guard let idx = recents.firstIndex(where: { $0.sourceTripId == sourceTripId }) else { return }
        recents[idx].selectedPhotoCount = detail.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded).count
        recents[idx].totalPlaceVisitCount = detail.days.reduce(0) { $0 + $1.placeStops.count }
        recents[idx].tripDurationDays = detail.days.count
        recents[idx].tripStartDate = RecapBlogDay.alignedTripStartDate(from: detail.days)
        recents[idx].tripEndDate = RecapBlogDay.alignedTripEndDate(from: detail.days)
        recents[idx].tripDateRangeText = Self.formatDateRange(
            start: recents[idx].tripStartDate,
            end: recents[idx].tripEndDate
        )
        persistRecents()
    }

    private func mergeVisitedPlaceSummaries(
        blogPlaces: [VisitedPlaceSummary],
        everydayPlaces: [VisitedPlaceSummary]
    ) -> [VisitedPlaceSummary] {
        var merged = blogPlaces

        for everyday in everydayPlaces {
            if everyday.isEverydayOnly {
                merged.append(everyday)
                continue
            }
            if let matchIndex = merged.firstIndex(where: { $0.isSamePlace(as: everyday) }) {
                merged[matchIndex] = merged[matchIndex].mergedWithEveryday(everyday)
            } else {
                merged.append(everyday)
            }
        }

        return merged.sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
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
