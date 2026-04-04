//
//  TripsViewModel.swift
//  Capper
//

import Combine
import Foundation
import Photos
import SwiftUI

/// Result of a Find More scan: no result yet, no new trips in range, or success with count of new trips appended.
enum FindMoreScanResult: Equatable {
    case none
    case empty
    case success(Int)
}

#if DEBUG
/// Diagnostic report produced by `TripsViewModel.runDebugScan()`.
/// Shows what photos exist since the last scan and how they'd be classified.
struct ScanDebugInfo {
    enum TripMatch {
        case newTrip
        case existingDraft(String)
        case savedBlog(String, cutoff: Date?)

        var label: String {
            switch self {
            case .newTrip:                    return "New Trip"
            case .existingDraft(let t):       return "Draft: \(t)"
            case .savedBlog(let t, _):        return "Blog: \(t)"
            }
        }

        var isNew: Bool { if case .newTrip = self { return true }; return false }
        var isBlog: Bool { if case .savedBlog = self { return true }; return false }
    }

    struct TripEntry: Identifiable {
        var id = UUID()
        var title: String
        var dateRange: String
        var totalPhotos: Int
        var newPhotoCount: Int         // photos after lastScannedDate
        var match: TripMatch
        var within24hOfExisting: Bool  // trip start within 24 h of any draft/blog boundary
        var blogCutoff: Date?          // set when match == .savedBlog
        var photosAfterCutoff: Int     // photos that would pass the cutoff filter
    }

    var scannedAt: Date
    var lastScannedDate: Date?
    var fetchStart: Date               // actual start of the photo query window
    var entries: [TripEntry]
}
#endif

@MainActor
final class TripsViewModel: ObservableObject {
    @Published var tripDrafts: [TripDraft] = []
    /// The trips currently visible in the carousel — set explicitly by each scan so
    /// the display window is always a single, authoritative write, not a mutation of tripDrafts.
    /// When nil, falls back to the full visibleDraftTrips (default scan path).
    @Published var currentWindowTrips: [TripDraft]? = nil
    /// Remembers the last selected trip in the carousel so selection survives view recreation
    /// when navigating to a recap blog and back.
    @Published var lastSelectedVisibleTripID: UUID? = nil
    @Published var scanState: MockScanState = .idle
    @Published var loadingMessage: String = "Loading Past Trips…"
    /// Progress of the initial default scan (0.0 → 1.0). Reset to 0 on each new scan.
    @Published var defaultScanProgress: Double = 0

    /// When true, show the "Select Photos / To Create A Blog" intro after scan completes (unless user chose "Do not show again").
    @Published var showSelectPhotosIntroAfterScan: Bool = true

    /// Present Find More Trips sheet when true.
    @Published var showFindMoreSheet: Bool = false
    /// Scanning in progress inside the sheet (show overlay in sheet).
    @Published var isFindMoreScanning: Bool = false
    /// After scan completes: .empty = show empty state in sheet; .success(n) = dismiss sheet and list already updated.
    @Published var findMoreScanResult: FindMoreScanResult = .none

    /// True if the user has performed at least one custom scan via the Find More sheet.
    @Published var hasPerformedCustomScan: Bool = false

    /// Progress of the Find More scan (0.0 → 1.0).
    @Published var findMoreScanProgress: Double = 0

    // MARK: - Load Older Trips State
    /// The earliest date covered by scanning so far (start of current window).
    @Published var earliestScannedDate: Date?
    /// The latest date covered by the current window (end of current window).
    @Published var latestScannedDate: Date?
    /// True while the "load older trips" scan is running.
    @Published var isLoadingOlderTrips: Bool = false
    /// Progress of the load-older scan (0.0 → 1.0).
    @Published var loadOlderProgress: Double = 0
    /// Result of the load-older scan.
    @Published var olderTripsResult: FindMoreScanResult = .none

    // MARK: - Load Newer Trips State
    /// True while the "load newer trips" scan is running.
    @Published var isLoadingNewerTrips: Bool = false
    /// Progress of the load-newer scan (0.0 → 1.0).
    @Published var loadNewerProgress: Double = 0
    /// Result of the load-newer scan.
    @Published var newerTripsResult: FindMoreScanResult = .none

    /// Start/End year+month selected in the Find More sheet. Only scanned when user taps Scan.
    @Published var findMoreStartYear: Int = Calendar.current.component(.year, from: Date()) {
        didSet { enforceDateRangeConsistency(fromStart: true) }
    }
    @Published var findMoreStartMonth: Int = Calendar.current.component(.month, from: Date()) {
        didSet { enforceDateRangeConsistency(fromStart: true) }
    }
    @Published var findMoreEndYear: Int = Calendar.current.component(.year, from: Date()) {
        didSet { enforceDateRangeConsistency(fromStart: false) }
    }
    @Published var findMoreEndMonth: Int = Calendar.current.component(.month, from: Date()) {
        didSet { enforceDateRangeConsistency(fromStart: false) }
    }
    
    private var isEnforcingDateRange = false
    
    private func enforceDateRangeConsistency(fromStart: Bool) {
        guard !isEnforcingDateRange else { return }
        isEnforcingDateRange = true
        defer { isEnforcingDateRange = false }
        
        if findMoreStartYear > findMoreEndYear {
            if fromStart {
                findMoreEndYear = findMoreStartYear
            } else {
                findMoreStartYear = findMoreEndYear
            }
        }
        
        if findMoreStartYear == findMoreEndYear && findMoreStartMonth > findMoreEndMonth {
            if fromStart {
                findMoreEndMonth = findMoreStartMonth
            } else {
                findMoreStartMonth = findMoreEndMonth
            }
        }
    }
    
    // MARK: - NLP Parsing State
    @Published var findMoreChatInput: String = ""
    @Published var findMoreChatResponse: String? = nil
    @Published var isParsingChat: Bool = false
    @Published var needsConfirmationForParse: Bool = false
    @Published var pendingParseResult: NLPParseResult? = nil

    // MARK: - Debug Scan Info

    #if DEBUG
    /// Populated by `runDebugScan()` — shows recent-photo analysis without touching live scan state.
    @Published var debugScanInfo: ScanDebugInfo? = nil
    /// True while `runDebugScan()` is fetching from the photo library.
    @Published var isRunningDebugScan: Bool = false
    #endif

    // MARK: - New Moments State

    /// When set after a scan, new photos were detected in an existing trip since the last scan.
    /// TripsView presents an alert offering to navigate to that trip.
    @Published var newMomentsInExistingTrip: TripDraft? = nil
    /// 0-based index of the latest day in the trip with new moments. Used to open the right day.
    @Published var newMomentsLatestDayIndex: Int = 0

    // MARK: - Newly Scanned Photos

    /// Photos discovered since the previous scan. Populated by both incremental and full scans.
    @Published var newlyScannedPhotos: [MockPhoto] = []
    /// When new photos match an already-created blog rather than a draft.
    @Published var newMomentsMatchedBlog: CreatedRecapBlog? = nil
    /// Present the newly-scanned-photos sheet when true.
    @Published var showNewlyScannedSheet: Bool = false

    /// When the user tapped Create blog we ran a new-photos check first. If they tap "Later" on the sheet, open the create flow for this trip.
    @Published var pendingTripForCreateFlow: TripDraft? = nil
    /// When true, the view should set createBlogFlowTrip = pendingTripForCreateFlow and then call clearPendingCreateFlow().
    @Published var openCreateFlowForPendingTrip: Bool = false
    /// True when the new-moments sheet was shown from the Create blog tap (so "Later" should open the pending create flow).
    @Published var newMomentsSheetTriggeredByCreateButton: Bool = false

    // MARK: - Visited Cities

    /// Controls presentation of the Visited Cities sheet.
    @Published var showVisitedCitiesSheet: Bool = false
    /// City/trip candidates built from the lightweight N-year scan.
    @Published var visitedCityTrips: [VisitedCityTrip] = []
    /// Current build state of the visited-cities scan.
    @Published var visitedCitiesBuildState: VisitedCitiesBuildState = .idle
    /// The calendar year currently loaded in the visited-cities sheet (e.g. 2025).
    @Published var visitedCitiesYear: Int = Calendar.current.component(.year, from: Date())
    /// True while a full trip scan (triggered by tapping a city row) is in progress.
    @Published var isVisitedCityScanning: Bool = false
    /// Progress (0–1) of the active visited-city trip scan.
    @Published var visitedCityScanProgress: Double = 0
    /// Draft trip built from selected place cards in Places Visited.
    @Published var pendingVisitedCitiesCreateTrip: TripDraft? = nil

    /// Clears the new-moments signal after the user has ACTED on it (Go to Blog / Go to Trip).
    /// Persists the blog notification cutoff so the same photos are not surfaced again.
    func clearNewMomentsSignal() {
        if let blog = newMomentsMatchedBlog,
           let maxPhotoDate = newlyScannedPhotos.map(\.timestamp).max() {
            // Use max photo timestamp (not Date()) so only photos up to the last shown
            // photo are silenced. Genuinely newer photos still surface on the next scan.
            // Guard: if photos are empty for any reason, skip saving to avoid accidentally
            // setting a future cutoff via Date() that would silence real new photos.
            // Blog-page scanning uses `sourceTripId`; Trips-flow scanning uses `CreatedRecapBlog.id`.
            // Save under both so whichever UI the user hits next doesn't re-surface the same moments.
            ScanSessionStore.saveBlogNotifiedDate(maxPhotoDate, for: blog.id)
            ScanSessionStore.saveBlogNotifiedDate(maxPhotoDate, for: blog.sourceTripId)
        }
        resetNewMomentsState()
        pendingTripForCreateFlow = nil
        newMomentsSheetTriggeredByCreateButton = false
        openCreateFlowForPendingTrip = false
    }

    /// New-moments pull-up is shown on `RecapBlogPageView` only, not on the Trips (tap-to-blog) flow.
    private func presentNewMomentsSheetIfNeeded() {}

    /// Adds a trip draft created from the in-app camera (e.g. when user taps "Not Now"
    /// on the Start Blog prompt). Inserts at the front so it appears as the newest trip.
    /// Sets this flag so TripsView scrolls to it when the camera is dismissed.
    @Published var pendingScrollToCameraTripID: UUID? = nil

    func addCameraTripDraft(_ trip: TripDraft) {
        tripDrafts.insert(trip, at: 0)
        lastSelectedVisibleTripID = trip.id
        pendingScrollToCameraTripID = trip.id
        if var window = currentWindowTrips {
            window.insert(trip, at: 0)
            currentWindowTrips = window
        }
    }

    /// Returns a camera-created trip draft (coverImageName == "camera.fill") that matches
    /// the capture date — same day or within maxGapDaysToBridge after the draft's last day (same rule as trip scanner).
    func cameraTripDraftMatching(captureDate: Date) -> TripDraft? {
        let cal = Calendar.current
        let captureDay = cal.startOfDay(for: captureDate)
        let drafts = tripDrafts.filter { $0.coverImageName == "camera.fill" }
        for draft in drafts {
            guard let draftEnd = draft.latestDate else { continue }
            let draftEndDay = cal.startOfDay(for: draftEnd)
            let draftStartDay = cal.startOfDay(for: draft.earliestDate ?? draftEnd)
            if captureDay >= draftStartDay && captureDay <= draftEndDay { return draft }
            let dayDiff = cal.dateComponents([.day], from: draftEndDay, to: captureDay).day ?? Int.max
            if dayDiff >= 1 && dayDiff <= ScanConfig.maxGapDaysToBridge { return draft }
        }
        return nil
    }

    /// Appends photos to an existing camera trip draft. Merges into existing days or adds new days.
    func appendPhotosToCameraDraft(tripId: UUID, newPhotos: [MockPhoto]) {
        guard let idx = tripDrafts.firstIndex(where: { $0.id == tripId }),
              tripDrafts[idx].coverImageName == "camera.fill" else { return }
        let cal = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateStyle = .medium
        let byDay = Dictionary(grouping: newPhotos) { cal.startOfDay(for: $0.timestamp) }
        let days: [TripDay] = byDay.sorted { $0.key < $1.key }.enumerated().map { index, pair in
            let dayStart = pair.key
            let dayPhotos = pair.value.sorted { $0.timestamp < $1.timestamp }
            return TripDay(dayIndex: index, dateText: dateFormatter.string(from: dayStart), photos: dayPhotos)
        }
        let stubTrip = TripDraft(
            title: "",
            dateRangeText: "",
            days: days,
            coverImageName: "camera.fill",
            isScannedFromDefaultRange: false
        )
        let (merged, didChange) = appendDaysFromTrip(stubTrip, into: tripDrafts[idx])
        if didChange {
            tripDrafts[idx] = merged
            lastSelectedVisibleTripID = tripId
            pendingScrollToCameraTripID = tripId
            if var window = currentWindowTrips, let wi = window.firstIndex(where: { $0.id == tripId }) {
                var w = window
                w[wi] = merged
                currentWindowTrips = w
            }
        }
    }

    /// Removes a photo by id from a camera trip draft (e.g. when user trashes it from Photos Captured modal).
    func removePhotoFromCameraDraft(tripId: UUID, photoId: UUID) {
        guard let idx = tripDrafts.firstIndex(where: { $0.id == tripId }),
              tripDrafts[idx].coverImageName == "camera.fill" else { return }
        var draft = tripDrafts[idx]
        var changed = false
        draft.days = draft.days.map { day in
            let beforeCount = day.photos.count
            let newPhotos = day.photos.filter { $0.id != photoId }
            if newPhotos.count != beforeCount { changed = true }
            return TripDay(id: day.id, dayIndex: day.dayIndex, dateText: day.dateText, photos: newPhotos, countryCode: day.countryCode, countryName: day.countryName, cityName: day.cityName)
        }
        if changed {
            tripDrafts[idx] = draft
            if var window = currentWindowTrips, let wi = window.firstIndex(where: { $0.id == tripId }) {
                var w = window
                w[wi] = draft
                currentWindowTrips = w
            }
        }
    }

    /// Called when the user taps the Create blog button (selected trip card). Runs a quick
    /// check for new photos since the last scan that belong to an existing blog. If found,
    /// presents the new-moments sheet; otherwise opens the create flow for the given trip.
    func initiateCreateBlogFlow(trip: TripDraft) {
        pendingTripForCreateFlow = trip
        newMomentsSheetTriggeredByCreateButton = true

        let userId = currentUserId
        let lastScanned = ScanSessionStore.lastScannedDate(for: userId)

        guard let lastDate = lastScanned else {
            openCreateFlowForPendingTrip = true
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let cal = Calendar.current
            let now = Date()
            let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: lastDate) ?? lastDate

            let newTrips = await photoLibraryService.scanInDateRange(
                startDate: fetchStart,
                endDate: now,
                occupiedDateRanges: []
            )
            let incrementalWindowStart = cal.startOfDay(for: lastDate)
            let incrementalTrips = newTrips.filter { trip in
                self.tripOverlapsWindow(trip, windowStart: incrementalWindowStart, windowEnd: now)
            }

            var blogPhotos: [MockPhoto] = []
            var matchedBlog: CreatedRecapBlog? = nil
            for t in incrementalTrips {
                guard let blog = self.findMatchingSavedBlog(for: t) else { continue }
                let allPhotos = t.days.flatMap(\.photos)
                let cutoff = ScanSessionStore.lastBlogNotifiedDate(for: blog.id) ?? .distantPast
                let recent = allPhotos.filter { $0.timestamp > cutoff }
                if !recent.isEmpty {
                    blogPhotos.append(contentsOf: recent)
                    if matchedBlog == nil { matchedBlog = blog }
                }
            }

            await MainActor.run {
                if matchedBlog != nil, !blogPhotos.isEmpty {
                    // Trips no longer shows the pull-up; open create flow. New moments surface on the blog.
                    self.resetNewMomentsState()
                    self.newMomentsSheetTriggeredByCreateButton = false
                    self.openCreateFlowForPendingTrip = true
                } else {
                    self.openCreateFlowForPendingTrip = true
                }
            }
        }
    }

    /// Called when the user taps "Later" on the new-moments sheet and that sheet was
    /// shown from the Create blog button. Opens the create flow for the pending trip.
    func dismissNewMomentsAndOpenPendingCreateFlow() {
        resetNewMomentsState()
        newMomentsSheetTriggeredByCreateButton = false
        openCreateFlowForPendingTrip = true
    }

    /// Call after the view has set createBlogFlowTrip from the pending trip. Clears pending state.
    func clearPendingCreateFlow() {
        pendingTripForCreateFlow = nil
        openCreateFlowForPendingTrip = false
        newMomentsSheetTriggeredByCreateButton = false
    }

    /// Clears only the in-memory new-moments state WITHOUT persisting a cutoff.
    /// Use for "Later" dismissal — the same photos will re-appear on the next scan.
    func resetNewMomentsState() {
        newMomentsInExistingTrip = nil
        newMomentsLatestDayIndex = 0
        newlyScannedPhotos = []
        newMomentsMatchedBlog = nil
    }

    // MARK: - Debug Scan Logic

    #if DEBUG
    /// Fetches photos from the last scanned date to now, groups them into trips using the
    /// same clustering logic as the real scan, and annotates each trip with whether it
    /// matches an existing draft (within 24 h) or a saved blog (with its cutoff).
    /// Purely informative — does not modify new-moments state or present the sheet.
    func runDebugScan() {
        guard !isRunningDebugScan else { return }
        isRunningDebugScan = true
        let userId = currentUserId
        let lastScanned = ScanSessionStore.lastScannedDate(for: userId)
        let now = Date()
        let cal = Calendar.current
        // Scan window: last 24 h at minimum, or since last scan (whichever is earlier).
        let since24h = cal.date(byAdding: .hour, value: -24, to: now) ?? now
        let fetchStart = lastScanned.map { min($0, since24h) } ?? since24h

        Task {
            let trips = await photoLibraryService.scanInDateRange(
                startDate: fetchStart,
                endDate: now,
                occupiedDateRanges: []
            )

            let entries: [ScanDebugInfo.TripEntry] = trips.map { trip in
                let allPhotos = trip.days.flatMap(\.photos)
                let newPhotos: [MockPhoto]
                if let last = lastScanned {
                    newPhotos = allPhotos.filter { $0.timestamp > last }
                } else {
                    newPhotos = allPhotos
                }

                // Check blog match first.
                let match: ScanDebugInfo.TripMatch
                var cutoff: Date? = nil
                var afterCutoff = 0
                if let blog = findMatchingSavedBlog(for: trip) {
                    cutoff = ScanSessionStore.lastBlogNotifiedDate(for: blog.id)
                    afterCutoff = allPhotos.filter { $0.timestamp > (cutoff ?? .distantPast) }.count
                    match = .savedBlog(blog.title, cutoff: cutoff)
                } else if let existing = tripDrafts.first(where: { areTripsRelated($0, trip) }) {
                    match = .existingDraft(existing.title)
                } else {
                    match = .newTrip
                }

                // Within-24h check: is the trip's start within 24 h of any draft end OR start?
                let within24h: Bool = {
                    guard let tripStart = trip.earliestDate else { return false }
                    for draft in tripDrafts {
                        if let dEnd = draft.latestDate, abs(tripStart.timeIntervalSince(dEnd)) < 86400 { return true }
                        if let dStart = draft.earliestDate, abs(tripStart.timeIntervalSince(dStart)) < 86400 { return true }
                    }
                    for blog in createdRecapStore.visibleRecents {
                        if let bEnd = blog.tripEndDate, abs(tripStart.timeIntervalSince(bEnd)) < 86400 { return true }
                        if let bStart = blog.tripStartDate, abs(tripStart.timeIntervalSince(bStart)) < 86400 { return true }
                    }
                    return false
                }()

                return ScanDebugInfo.TripEntry(
                    title: trip.title,
                    dateRange: trip.dateRangeText,
                    totalPhotos: allPhotos.count,
                    newPhotoCount: newPhotos.count,
                    match: match,
                    within24hOfExisting: within24h,
                    blogCutoff: cutoff,
                    photosAfterCutoff: afterCutoff
                )
            }

            await MainActor.run {
                self.debugScanInfo = ScanDebugInfo(
                    scannedAt: now,
                    lastScannedDate: lastScanned,
                    fetchStart: fetchStart,
                    entries: entries
                )
                self.isRunningDebugScan = false
            }
        }
    }
    #endif

    /// Current user ID for per-user scan-session storage. "guest" for unauthenticated.
    private var currentUserId: String {
        AuthStateManager.shared.currentUserId ?? "guest"
    }

    /// Tracks whether the Find More sheet has been opened at least once this session.
    /// Stays `false` until after the first open; reset only happens on first open (cold start).
    private var hasOpenedFindMoreSheet: Bool = false

    /// Tracks the running Find More scan task so it can be cancelled.
    private var findMoreScanTask: Task<Void, Never>?
    /// Tracks the running visited-cities build task so it can be cancelled.
    private var visitedCitiesBuildTask: Task<Void, Never>?
    /// Tracks the running visited-city trip-scan task so it can be cancelled.
    private var visitedCityScanTask: Task<Void, Never>?
    /// Tracks the running load-older scan task so it can be cancelled.
    private var loadOlderScanTask: Task<Void, Never>?
    /// Tracks the running load-newer scan task so it can be cancelled.
    private var loadNewerScanTask: Task<Void, Never>?
    /// Tracks the running default scan task so it can be cancelled.
    private var defaultScanTask: Task<Void, Never>?

    // MARK: - Session Window Cache
    /// In-memory cache: normalized window key → scanned trips for that window.
    /// Naturally cleared on app restart (not persisted to disk).
    private var windowCache: [String: [TripDraft]] = [:]

    /// Normalized cache key for a window. Uses startOfDay for both boundaries
    /// so keys match even when the exact timestamps differ slightly.
    private func windowCacheKey(start: Date, end: Date) -> String {
        let cal = Calendar.current
        let s = Int(cal.startOfDay(for: start).timeIntervalSince1970)
        let e = Int(cal.startOfDay(for: end).timeIntervalSince1970)
        return "\(s)-\(e)"
    }

    /// Keep a trip when any portion overlaps the visible window.
    /// This preserves long trips that start just before the window but continue into it.
    private func tripOverlapsWindow(_ trip: TripDraft, windowStart: Date, windowEnd: Date) -> Bool {
        guard let start = trip.earliestDate else { return false }
        let end = trip.latestDate ?? start
        return end >= windowStart && start < windowEnd
    }

    /// Apply a set of window-filtered trips: dedup against created blogs and saved drafts,
    /// then update `tripDrafts`, `currentWindowTrips`, and date bounds.
    /// Returns the number of trips that survived dedup (0 = empty).
    @discardableResult
    private func applyWindowTrips(
        _ windowTrips: [TripDraft],
        windowStart: Date,
        windowEnd: Date,
        setCurrentWindow: Bool = true
    ) -> Int {
        let myDraftIds = TripDraftStore.draftTripIds()
        let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })

        let deduped = windowTrips.filter { trip in
            guard !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                && !createdRecapStore.hasCreatedBlog(sourceTripId: trip.id)
                && !createdRecapStore.isDraftRedundantWithSavedBlogs(trip)
            else { return false }
            // Avoid adding a scanned trip whose photos are already in an existing draft (e.g. camera capture).
            let tripPhotoIds = Set(trip.days.flatMap(\.photos).compactMap(\.localIdentifier))
            guard !tripPhotoIds.isEmpty else { return true }
            let isPhotoDuplicateOfDraft = tripDrafts.contains { existing in
                let existingIds = Set(existing.days.flatMap(\.photos).compactMap(\.localIdentifier))
                return tripPhotoIds.isSubset(of: existingIds)
            }
            return !isPhotoDuplicateOfDraft
        }

        if !deduped.isEmpty {
            let keptDrafts = tripDrafts.filter { myDraftIds.contains($0.id) }
            tripDrafts = keptDrafts + deduped
            if setCurrentWindow { currentWindowTrips = deduped }
            showSelectPhotosIntroAfterScan = false
        }

        earliestScannedDate = windowStart
        latestScannedDate   = windowEnd
        return deduped.count
    }

    private let photoLibraryService = PhotoLibraryTripService.shared
    private let mockService = MockTripDataService.shared
    private let createdRecapStore: CreatedRecapBlogStore
    private var cancellables = Set<AnyCancellable>()

    /// Draft trips that have not yet been turned into a created recap blog. Use this for the Trips list.
    /// Filters by both UUID match and date/location overlap so trips never survive a re-scan.
    var visibleDraftTrips: [TripDraft] {
        return tripDrafts.filter { draft in
            !createdRecapStore.hasCreatedBlog(sourceTripId: draft.id)
            && !createdRecapStore.isDraftRedundantWithSavedBlogs(draft)
        }
    }

    /// Trips where the user has started selecting photos but not created the blog. Shown in "My Drafts" section.
    var myDrafts: [TripDraft] {
        let draftIds = TripDraftStore.draftTripIds()
        return visibleDraftTrips.filter { draftIds.contains($0.id) }
    }

    /// Trips that have not been started (no saved photo selection). Shown in "Ready to Start" section.
    var readyToStartTrips: [TripDraft] {
        let draftIds = TripDraftStore.draftTripIds()
        return visibleDraftTrips.filter { !draftIds.contains($0.id) }
    }

    /// My Drafts ordered newest first.
    var myDraftsNewestFirst: [TripDraft] {
        myDrafts.sorted { lhs, rhs in (lhs.earliestDate ?? .distantPast) > (rhs.earliestDate ?? .distantPast) }
    }

    /// Ready to Start ordered newest first.
    var readyToStartNewestFirst: [TripDraft] {
        readyToStartTrips.sorted { lhs, rhs in (lhs.earliestDate ?? .distantPast) > (rhs.earliestDate ?? .distantPast) }
    }

    /// Trips grouped by month (year-month) for display. Each element: (monthKey, displayTitle, trips). Newest month first.
    var readyToStartGroupedByMonth: [(monthKey: String, displayTitle: String, trips: [TripDraft])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale.current
        let grouped = Dictionary(grouping: readyToStartNewestFirst) { trip -> String in
            guard let date = trip.earliestDate else { return "Unknown" }
            return "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
        }
        return grouped
            .map { key, trips in
                let display: String
                if key == "Unknown" {
                    display = "Other"
                } else if let first = trips.first, let date = first.earliestDate {
                    display = formatter.string(from: date)
                } else {
                    display = "Other"
                }
                return (monthKey: key, displayTitle: display, trips: trips.sorted { ($0.earliestDate ?? .distantPast) > ($1.earliestDate ?? .distantPast) })
            }
            .sorted { $0.monthKey > $1.monthKey }
    }

    /// My Drafts grouped by month. Newest month first.
    var myDraftsGroupedByMonth: [(monthKey: String, displayTitle: String, trips: [TripDraft])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale.current
        let grouped = Dictionary(grouping: myDraftsNewestFirst) { trip -> String in
            guard let date = trip.earliestDate else { return "Unknown" }
            return "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
        }
        return grouped
            .map { key, trips in
                let display: String
                if key == "Unknown" {
                    display = "Other"
                } else if let first = trips.first, let date = first.earliestDate {
                    display = formatter.string(from: date)
                } else {
                    display = "Other"
                }
                return (monthKey: key, displayTitle: display, trips: trips.sorted { ($0.earliestDate ?? .distantPast) > ($1.earliestDate ?? .distantPast) })
            }
            .sorted { $0.monthKey > $1.monthKey }
    }

    /// Trips ordered newest first — reads from the active window when present, but still
    /// applies the same created/draft filtering so saved trips disappear immediately.
    var visibleDraftTripsNewestFirst: [TripDraft] {
        let source: [TripDraft]
        if let window = currentWindowTrips {
            source = window.filter { draft in
                !createdRecapStore.hasCreatedBlog(sourceTripId: draft.id)
                && !createdRecapStore.isDraftRedundantWithSavedBlogs(draft)
            }
        } else {
            source = visibleDraftTrips
        }
        return source.sorted { lhs, rhs in
            (lhs.earliestDate ?? .distantPast) > (rhs.earliestDate ?? .distantPast)
        }
    }

    /// True when the scan has completed but results are weak: no trips found, or only
    /// a single 1-day trip detected. Used to decide when to surface the "Add More Photos"
    /// nudge for Limited access users.
    var scanResultIsWeak: Bool {
        guard scanState == .idle else { return false }
        if tripDrafts.isEmpty { return true }
        if tripDrafts.count == 1,
           let only = tripDrafts.first,
           only.days.count <= 1 { return true }
        return false
    }

    /// Trip to pass into the picker: applies saved selection if this is a draft, otherwise returns the trip as-is.
    func tripForPicker(_ trip: TripDraft) -> TripDraft {
        TripDraftStore.hasDraft(tripId: trip.id)
            ? TripDraftStore.applySavedSelection(to: trip)
            : trip
    }

    /// Remove a trip from the list (e.g. after it was turned into a created blog). Keeps tripDrafts in sync.
    /// Note: We no longer physically remove trips here. visibleDraftTripsNewestFirst already
    /// filters out trips that have a created blog (via hasCreatedBlog / TripMatchingService).
    /// Keeping trips in the arrays lets them reappear automatically if the blog is later discarded.
    func removeTrip(id: UUID) { }

    init(createdRecapStore: CreatedRecapBlogStore) {
        self.createdRecapStore = createdRecapStore
        createdRecapStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func onAppear() {
        guard scanState == .idle, tripDrafts.isEmpty else { return }
        if createdRecapStore.isLoading {
            // Wait for store to load before scanning so occupiedDateRanges is accurate
            createdRecapStore.$isLoading
                .filter { !$0 }
                .first()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.startDefaultScan()
                }
                .store(in: &cancellables)
        } else {
            startDefaultScan()
        }
    }

    /// Number of days to pad photo fetches beyond the window edges so that
    /// trips straddling a boundary are captured in full.
    private static let fetchPaddingDays = 10

    #if DEBUG
    private static let scanDebugFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    private func scanDbg(_ date: Date?) -> String {
        guard let d = date else { return "nil" }
        return Self.scanDebugFmt.string(from: d)
    }
    #endif

    /// Deduplicates photos by localIdentifier so the same asset is not added multiple times.
    private func dedupePhotosByLocalId(_ photos: [MockPhoto]) -> [MockPhoto] {
        var seen = Set<String>()
        return photos.filter { photo in
            guard let id = photo.localIdentifier else { return true }
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
    }

    func cancelDefaultScan() {
        defaultScanTask?.cancel()
        defaultScanTask = nil
        scanState = .idle
        defaultScanProgress = 0
    }

    /// When true, skips incremental scan and runs a full-window scan (e.g. after user selects more photos in Limited Library picker).
    func startDefaultScan(forceFullScan: Bool = false) {
        if forceFullScan {
            PhotoLibraryTripService.invalidateScanCache()
        }
        showSelectPhotosIntroAfterScan = true
        scanState = .scanningDefault
        loadingMessage = "Loading your recent trips…"
        defaultScanProgress = 0
        newlyScannedPhotos = []
        newMomentsMatchedBlog = nil
        showNewlyScannedSheet = false
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")
        /// While the active on-the-go blog’s latest photo is under 24 hours old, re-scan whole calendar days from trip start through now: omit only that blog from occupied ranges (so library assets on day 1 are not stripped) and widen incremental fetch / overlap window to `tripStartDate`.
        let activeOnTheGoBlogId = OnTheGoTripStore.activeBlogId
        let latestPhotoForActiveOnTheGo: Date? = {
            guard let id = activeOnTheGoBlogId else { return nil }
            if let t = createdRecapStore.latestPhotoTimestamp(forSourceTripId: id) { return t }
            return createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == id })?.tripEndDate
                ?? OnTheGoTripStore.tripEndDate
        }()
        let scanFullCalendarDaysForFreshOnTheGo = activeOnTheGoBlogId != nil
            && OnTheGoTripStore.isTripStillOngoing()
            && (latestPhotoForActiveOnTheGo.map { Date().timeIntervalSince($0) < 24 * 3600 } ?? false)
        let occupiedRangesExcludedBlogIds: Set<UUID> = {
            guard scanFullCalendarDaysForFreshOnTheGo, let id = activeOnTheGoBlogId else { return Set() }
            return Set([id])
        }()
        let occupiedRanges = createdRecapStore.occupiedDateRanges(excludingSourceTripIds: occupiedRangesExcludedBlogIds)
        let userId = currentUserId
        let previousLastScanned = forceFullScan ? nil : ScanSessionStore.lastScannedDate(for: userId)

        #if DEBUG
        debugPrint("[Scan] ──── startDefaultScan ────")
        debugPrint("[Scan] lastScannedDate = \(scanDbg(previousLastScanned))")
        debugPrint("[Scan] tripDrafts.count = \(tripDrafts.count)")
        debugPrint("[Scan] savedBlogs.count = \(createdRecapStore.visibleRecents.count)")
        debugPrint("[Scan] freshOnTheGo24h=\(scanFullCalendarDaysForFreshOnTheGo) latestPhoto=\(scanDbg(latestPhotoForActiveOnTheGo)) excludeBlogFromOccupied=\(occupiedRangesExcludedBlogIds.map(\.uuidString).joined(separator: ","))")
        for (i, blog) in createdRecapStore.visibleRecents.enumerated() {
            debugPrint("[Scan]   blog[\(i)] \"\(blog.title)\" createdAt=\(scanDbg(blog.createdAt)) start=\(scanDbg(blog.tripStartDate)) end=\(scanDbg(blog.tripEndDate)) country=\(blog.countryName ?? "nil")")
        }
        debugPrint("[Scan] occupiedRanges.count = \(occupiedRanges.count)")
        for (i, r) in occupiedRanges.enumerated() {
            debugPrint("[Scan]   range[\(i)] = \(scanDbg(r.start)) → \(scanDbg(r.end))")
        }
        #endif

        defaultScanTask = Task {
            let isLimitedAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited

            if isLimitedAccess {
                // Limited access: no date window — use all selected photos with location + timestamp.
                #if DEBUG
                debugPrint("[Scan] mode = LIMITED (all selected photos)")
                #endif

                let allTrips = await photoLibraryService.scanAllForLimitedAccess(
                    occupiedDateRanges: occupiedRanges,
                    progress: { [weak self] value in
                        Task { @MainActor in self?.defaultScanProgress = value }
                    }
                )

                tripDrafts = allTrips
                currentWindowTrips = nil
                if let first = allTrips.first?.days.first?.photos.first?.timestamp,
                   let last = allTrips.last?.days.last?.photos.last?.timestamp {
                    earliestScannedDate = first
                    latestScannedDate = last
                } else {
                    earliestScannedDate = nil
                    latestScannedDate = nil
                }

                AppAnalytics.shared.trackEvent(name: "trip_scan_completed")
                AppAnalytics.shared.incrementCounter("trips_detected", by: allTrips.count)
                ScanSessionStore.saveLastScannedDate(Date(), for: userId)
                scanState = .idle
                presentNewMomentsSheetIfNeeded()
                return
            }

            let cal = Calendar.current
            let now = Date()
            let fullWindowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -ScanConfig.windowDays, to: now) ?? now)
            let windowEnd = now

            // Incremental scan: only fetch photos since the last scan when we already have
            // trips in memory. Saves time and allows merging new moments into existing trips.
            let canDoIncremental = previousLastScanned != nil
                && previousLastScanned! > fullWindowStart
                && !tripDrafts.isEmpty

            #if DEBUG
            debugPrint("[Scan] canDoIncremental = \(canDoIncremental)  (hasLastScanned=\(previousLastScanned != nil) lastScanned>\(scanDbg(fullWindowStart))=\(previousLastScanned.map { $0 > fullWindowStart } ?? false) tripDrafts.isEmpty=\(tripDrafts.isEmpty))")
            #endif

            if canDoIncremental, let lastDate = previousLastScanned {
                loadingMessage = "Checking for new moments…"

                // Pad behind lastDate so trips that straddle the boundary are complete.
                var fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: lastDate) ?? lastDate
                // Fresh on-the-go blog: include every calendar day from trip start through now (not only since lastScanned).
                var incrementalWindowStart = cal.startOfDay(for: lastDate)
                if scanFullCalendarDaysForFreshOnTheGo,
                   let goId = activeOnTheGoBlogId,
                   let activeBlog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == goId }),
                   let tripStart = activeBlog.tripStartDate {
                    let blogDayStart = cal.startOfDay(for: tripStart)
                    let expandedFetch = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: blogDayStart) ?? blogDayStart
                    fetchStart = min(fetchStart, expandedFetch)
                    incrementalWindowStart = min(incrementalWindowStart, blogDayStart)
                }

                #if DEBUG
                debugPrint("[Scan] mode = INCREMENTAL")
                debugPrint("[Scan] fetchStart = \(scanDbg(fetchStart))  (lastScanned − \(Self.fetchPaddingDays)d, or blog start if fresh on-the-go)")
                debugPrint("[Scan] fetchEnd   = \(scanDbg(windowEnd))")
                debugPrint("[Scan] incrementalWindowStart = \(scanDbg(incrementalWindowStart))")
                #endif

                // Pass empty occupied ranges so photos in saved-blog date
                // ranges are still found and can be matched to the blog.
                let newTrips = await photoLibraryService.scanInDateRange(
                    startDate: fetchStart,
                    endDate: windowEnd,
                    occupiedDateRanges: [],
                    progress: { [weak self] value in
                        Task { @MainActor in self?.defaultScanProgress = value }
                    }
                )

                // Keep only trips that overlap the incremental window.
                // Use startOfDay because trip dates are day-granular (midnight),
                // while lastDate is a precise timestamp within the day.
                let incrementalTrips = newTrips.filter { trip in
                    tripOverlapsWindow(trip, windowStart: incrementalWindowStart, windowEnd: windowEnd)
                }

                #if DEBUG
                debugPrint("[Scan] scanned trips = \(newTrips.count), after window filter = \(incrementalTrips.count)")
                #endif

                ScanSessionStore.saveLastScannedDate(now, for: userId)
                AppAnalytics.shared.trackEvent(name: "trip_scan_completed")

                #if DEBUG
                debugPrint("[Scan] saved lastScannedDate = \(scanDbg(now))")
                #endif

                mergeIncrementalTrips(incrementalTrips, since: lastDate)
                scanState = .idle
                presentNewMomentsSheetIfNeeded()

            } else {
                // Full scan: first launch, no in-memory trips, or last scan is too old.
                let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: fullWindowStart) ?? fullWindowStart

                #if DEBUG
                debugPrint("[Scan] mode = FULL")
                debugPrint("[Scan] fetchStart = \(scanDbg(fetchStart))  (windowStart − \(Self.fetchPaddingDays)d)")
                debugPrint("[Scan] fetchEnd   = \(scanDbg(windowEnd))")
                #endif

                let allTrips = await photoLibraryService.scanInDateRange(
                    startDate: fetchStart,
                    endDate: windowEnd,
                    occupiedDateRanges: occupiedRanges,
                    progress: { [weak self] value in
                        Task { @MainActor in self?.defaultScanProgress = value }
                    }
                )

                let windowTrips = allTrips.filter { trip in
                    tripOverlapsWindow(trip, windowStart: fullWindowStart, windowEnd: windowEnd)
                }

                windowCache[windowCacheKey(start: fullWindowStart, end: windowEnd)] = windowTrips

                #if DEBUG
                debugPrint("[Scan] scanned trips = \(allTrips.count), after window filter = \(windowTrips.count)")
                #endif

                AppAnalytics.shared.trackEvent(name: "trip_scan_completed")
                AppAnalytics.shared.incrementCounter("trips_detected", by: windowTrips.count)

                tripDrafts = windowTrips
                currentWindowTrips = nil
                earliestScannedDate = fullWindowStart
                latestScannedDate = windowEnd

                // Detect new moments in draft trips since the last scan.
                if let lastDate = previousLastScanned {
                    detectNewMomentsInTrips(windowTrips, since: lastDate)
                }

                // Always run the saved-blog micro-scan so we detect photos for created blogs
                // even on the very first scan (previousLastScanned may be nil).
                // Scan the full 90-day window so we never miss older photos.
                #if DEBUG
                debugPrint("[Scan] FULL: micro-scan for saved-blog photos (full window)")
                #endif

                let blogCheckTrips = await photoLibraryService.scanInDateRange(
                    startDate: fetchStart,
                    endDate: windowEnd,
                    occupiedDateRanges: []
                )

                #if DEBUG
                debugPrint("[Scan] FULL: micro-scan returned \(blogCheckTrips.count) trip(s)")
                #endif

                collectNewPhotosForSavedBlogs(from: blogCheckTrips)

                #if DEBUG
                debugPrint("[Scan] FULL: newlyScannedPhotos=\(newlyScannedPhotos.count) matchedBlog=\(newMomentsMatchedBlog?.title ?? "none") showSheet=\(!newlyScannedPhotos.isEmpty)")
                #endif

                // Record the scan date so the next launch can do an incremental check.
                ScanSessionStore.saveLastScannedDate(now, for: userId)

                #if DEBUG
                debugPrint("[Scan] saved lastScannedDate = \(scanDbg(now))")
                #endif

                scanState = .idle

                detectNewMomentsForOnTheGoTrip(scannedDrafts: windowTrips)
                newlyScannedPhotos = dedupePhotosByLocalId(newlyScannedPhotos)
                presentNewMomentsSheetIfNeeded()
            }
        }
    }

    // MARK: - New Moments Detection (full-scan path)

    /// After a full scan, checks whether any draft trip contains photos taken after `lastScanned`.
    /// Collects the new photos and signals the first such trip for UI prompting.
    private func detectNewMomentsInTrips(_ trips: [TripDraft], since lastScanned: Date) {
        var collected: [MockPhoto] = []
        for trip in trips {
            let newPhotos = trip.days.flatMap { $0.photos.filter { $0.timestamp > lastScanned } }
            if !newPhotos.isEmpty {
                collected.append(contentsOf: newPhotos)
                if newMomentsInExistingTrip == nil {
                    newMomentsInExistingTrip = trip
                    newMomentsLatestDayIndex = max(0, trip.days.count - 1)
                }
            }
        }
        if !collected.isEmpty {
            newlyScannedPhotos.append(contentsOf: collected)
        }
    }

    /// After a full scan, checks for new photos that belong to saved blogs.
    /// The main scan excluded these via `occupiedDateRanges`; this uses a
    /// micro-scan result run without that filter.
    /// Only the single latest blog (by lastEditedAt ?? createdAt) is honored — one trip at a time.
    private func collectNewPhotosForSavedBlogs(from trips: [TripDraft]) {
        #if DEBUG
        debugPrint("[Scan] collectNewPhotosForSavedBlogs: checking \(trips.count) trip(s)")
        #endif
        var candidates: [(blog: CreatedRecapBlog, photos: [MockPhoto])] = []
        for trip in trips {
            guard let blog = findMatchingSavedBlog(for: trip) else { continue }
            let allPhotos = trip.days.flatMap(\.photos)
            let cutoff = ScanSessionStore.lastBlogNotifiedDate(for: blog.id) ?? blog.tripEndDate ?? blog.createdAt
            let existingIds = Set(
                createdRecapStore.getBlogDetail(blogId: blog.sourceTripId)?
                    .days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier) ?? []
            )
            let recentPhotos = allPhotos.filter { p in
                p.timestamp > cutoff && (p.localIdentifier.map { !existingIds.contains($0) } ?? true)
            }
            #if DEBUG
            debugPrint("[Scan]   trip \"\(trip.title)\" cutoff=\(scanDbg(cutoff)) totalPhotos=\(allPhotos.count) existingInBlog=\(existingIds.count) afterCutoff=\(recentPhotos.count)")
            for p in allPhotos {
                let afterCutoff = p.timestamp > cutoff
                let alreadyInBlog = p.localIdentifier.map { existingIds.contains($0) } ?? false
                let kept = afterCutoff && !alreadyInBlog
                debugPrint("[Scan]     photo id=\(p.localIdentifier?.suffix(8) ?? "nil") ts=\(scanDbg(p.timestamp)) afterCutoff=\(afterCutoff) alreadyInBlog=\(alreadyInBlog) → kept=\(kept)")
            }
            #endif
            if !recentPhotos.isEmpty {
                candidates.append((blog, recentPhotos))
            }
        }
        // Merge by blog (same blog can match multiple trips), then only honor the latest blog.
        let byBlog = Dictionary(grouping: candidates, by: { $0.blog.id })
        let blogsWithNewPhotos: [(CreatedRecapBlog, [MockPhoto])] = byBlog.compactMap { _, pairs in
            guard let first = pairs.first else { return nil }
            let blog = first.blog
            let photos = dedupePhotosByLocalId(pairs.flatMap(\.photos))
            return photos.isEmpty ? nil : (blog, photos)
        }
        if let latest = latestBlog(blogsWithNewPhotos.map(\.0)) {
            let photos = blogsWithNewPhotos.first(where: { $0.0.id == latest.id })?.1 ?? []
            if !photos.isEmpty {
                newMomentsMatchedBlog = latest
                newlyScannedPhotos.append(contentsOf: photos)
            }
        }
        #if DEBUG
        debugPrint("[Scan] collectNewPhotosForSavedBlogs: candidates=\(candidates.count), latest only, new = \(newlyScannedPhotos.count)")
        #endif
    }

    // MARK: - Incremental Scan Merging

    /// Merges newly-scanned trips (incremental path) into the existing `tripDrafts`.
    /// Photos are merged into matching days and new days are appended.
    /// Also matches against saved blogs so new photos for an existing blog are tracked.
    /// `since` is the previous lastScannedDate — only photos after this time are shown as new.
    private func mergeIncrementalTrips(_ newTrips: [TripDraft], since lastScanned: Date) {
        guard !newTrips.isEmpty else {
            #if DEBUG
            debugPrint("[Scan] mergeIncremental: no new trips to merge")
            #endif
            return
        }

        #if DEBUG
        debugPrint("[Scan] mergeIncremental: processing \(newTrips.count) new trip(s), since=\(scanDbg(lastScanned))")
        #endif

        var updatedExistingTrip: TripDraft? = nil
        var remainingNew: [TripDraft] = []
        var collectedNewPhotos: [MockPhoto] = []
        var savedBlogNewPhotos: [(blog: CreatedRecapBlog, photos: [MockPhoto])] = []

        for newTrip in newTrips {
            // 1. Check saved blogs first — new photos may belong to an already-created blog.
            if let blog = findMatchingSavedBlog(for: newTrip) {
                let allPhotos = newTrip.days.flatMap(\.photos)
                // Use tripEndDate (or createdAt) as the fallback cutoff — photos taken
                // during the trip are already in the blog; only photos taken after the
                // trip ended are genuinely new. .distantPast would surface all trip photos.
                let cutoff = ScanSessionStore.lastBlogNotifiedDate(for: blog.id) ?? blog.tripEndDate ?? blog.createdAt
                let existingIds = Set(
                    createdRecapStore.getBlogDetail(blogId: blog.sourceTripId)?
                        .days.flatMap(\.placeStops).flatMap(\.photos).compactMap(\.localIdentifier) ?? []
                )
                let photos = allPhotos.filter { p in
                    p.timestamp > cutoff && (p.localIdentifier.map { !existingIds.contains($0) } ?? true)
                }
                if !photos.isEmpty { savedBlogNewPhotos.append((blog, photos)) }
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: matched saved blog \"\(blog.title)\" cutoff=\(scanDbg(cutoff)) totalPhotos=\(allPhotos.count) existingInBlog=\(existingIds.count) afterFilter=\(photos.count)")
                for p in allPhotos {
                    let afterCutoff = p.timestamp > cutoff
                    let alreadyInBlog = p.localIdentifier.map { existingIds.contains($0) } ?? false
                    let kept = afterCutoff && !alreadyInBlog
                    debugPrint("[Scan]   photo id=\(p.localIdentifier?.suffix(8) ?? "nil") ts=\(scanDbg(p.timestamp)) afterCutoff=\(afterCutoff) alreadyInBlog=\(alreadyInBlog) → kept=\(kept)")
                }
                #endif
                // Library photos not yet in the blog still need a trip card / merge pass (blogs from in-app camera only store `bloggo-capture:` ids).
                let libraryIdsInScan = Set(
                    allPhotos.compactMap(\.localIdentifier).filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
                )
                let hasLibraryAssetsNotInBlog = libraryIdsInScan.contains { !existingIds.contains($0) }
                if !hasLibraryAssetsNotInBlog {
                    continue
                }
            }

            // 2. Check existing drafts — merge photos into matching trip.
            if let idx = tripDrafts.firstIndex(where: { areTripsRelated($0, newTrip) }) {
                let beforeIds = Set(tripDrafts[idx].days.flatMap(\.photos).compactMap(\.localIdentifier))
                let (merged, didChange) = appendDaysFromTrip(newTrip, into: tripDrafts[idx])
                tripDrafts[idx] = merged
                if didChange {
                    let freshPhotos = merged.days.flatMap(\.photos).filter { p in
                        guard let lid = p.localIdentifier else { return false }
                        return !beforeIds.contains(lid)
                    }
                    collectedNewPhotos.append(contentsOf: freshPhotos)
                    if updatedExistingTrip == nil { updatedExistingTrip = merged }
                }
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: merged into draft \"\(tripDrafts[idx].title)\" didChange=\(didChange) days=\(merged.days.count) photos=\(merged.totalPhotoCount)")
                #endif
            } else if let idx = existingDraftIndexContainingAllPhotos(of: newTrip) {
                // 3a. Scanned trip is a photo-duplicate of an existing draft (e.g. same capture in camera draft).
                // Merge into that draft so we never show two trips with the same photo(s).
                let beforeIds = Set(tripDrafts[idx].days.flatMap(\.photos).compactMap(\.localIdentifier))
                let (merged, didChange) = appendDaysFromTrip(newTrip, into: tripDrafts[idx])
                tripDrafts[idx] = merged
                if didChange {
                    let freshPhotos = merged.days.flatMap(\.photos).filter { p in
                        guard let lid = p.localIdentifier else { return false }
                        return !beforeIds.contains(lid)
                    }
                    collectedNewPhotos.append(contentsOf: freshPhotos)
                    if updatedExistingTrip == nil { updatedExistingTrip = merged }
                }
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: merged duplicate into existing draft \"\(tripDrafts[idx].title)\" (all photos already in draft) didChange=\(didChange)")
                #endif
            } else {
                // 3b. Unrelated — new standalone trip. Only collect genuinely new photos.
                remainingNew.append(newTrip)
                let newPhotos = newTrip.days.flatMap(\.photos).filter { $0.timestamp > lastScanned }
                collectedNewPhotos.append(contentsOf: newPhotos)
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: new standalone trip \"\(newTrip.title)\" days=\(newTrip.days.count) photos=\(newTrip.totalPhotoCount) genuinelyNew=\(newPhotos.count)")
                #endif
            }
        }

        // Only honor the single latest blog for new moments (one trip at a time).
        let byBlog = Dictionary(grouping: savedBlogNewPhotos, by: { $0.blog.id })
        let blogsWithNewPhotos: [(CreatedRecapBlog, [MockPhoto])] = byBlog.compactMap { _, pairs in
            let blog = pairs[0].blog
            let photos = dedupePhotosByLocalId(pairs.flatMap(\.photos))
            return photos.isEmpty ? nil : (blog, photos)
        }
        if let latest = latestBlog(blogsWithNewPhotos.map(\.0)) {
            let photos = blogsWithNewPhotos.first(where: { $0.0.id == latest.id })?.1 ?? []
            if !photos.isEmpty {
                newMomentsMatchedBlog = latest
                collectedNewPhotos.append(contentsOf: photos)
            }
        }

        let deduped = remainingNew.filter {
            !createdRecapStore.hasCreatedBlog(sourceTripId: $0.id)
            && !createdRecapStore.isDraftRedundantWithSavedBlogs($0)
        }
        if !deduped.isEmpty {
            tripDrafts.append(contentsOf: deduped)
            showSelectPhotosIntroAfterScan = false
        }

        newlyScannedPhotos = dedupePhotosByLocalId(collectedNewPhotos)

        #if DEBUG
        debugPrint("[Scan] ──── mergeIncremental RESULT ────")
        debugPrint("[Scan]   mergedIntoDraft=\(updatedExistingTrip != nil)")
        debugPrint("[Scan]   newStandalone=\(deduped.count)")
        debugPrint("[Scan]   collectedNewPhotos=\(collectedNewPhotos.count)")
        debugPrint("[Scan]   matchedBlog=\(newMomentsMatchedBlog?.title ?? "none")")
        debugPrint("[Scan]   totalDrafts=\(tripDrafts.count)")
        for p in collectedNewPhotos {
            debugPrint("[Scan]   newPhoto: id=\(p.localIdentifier?.suffix(8) ?? "nil") ts=\(scanDbg(p.timestamp))")
        }
        debugPrint("[Scan] ──────────────────────────────")
        #endif

        if let updated = updatedExistingTrip {
            newMomentsInExistingTrip = updated
            newMomentsLatestDayIndex = max(0, updated.days.count - 1)
        } else if newMomentsMatchedBlog == nil, let firstNew = deduped.first {
            newMomentsInExistingTrip = firstNew
            newMomentsLatestDayIndex = max(0, firstNew.days.count - 1)
        }

        AppAnalytics.shared.incrementCounter("trips_detected", by: remainingNew.count)
        detectNewMomentsForOnTheGoTrip(scannedDrafts: tripDrafts)
    }

    /// Picks the single "latest" blog (most likely current trip) by tripEndDate.
    /// We only ever surface new moments for one blog; users can't be on multiple trips at once.
    private func latestBlog(_ blogs: [CreatedRecapBlog]) -> CreatedRecapBlog? {
        blogs.max(by: {
            let dateA = $0.tripEndDate ?? $0.lastEditedAt ?? $0.createdAt
            let dateB = $1.tripEndDate ?? $1.lastEditedAt ?? $1.createdAt
            return dateA < dateB
        })
    }

    /// Returns true if `a` is strictly newer than `b` (by tripEndDate).
    private func isBlogNewer(_ a: CreatedRecapBlog, than b: CreatedRecapBlog) -> Bool {
        let dateA = a.tripEndDate ?? a.lastEditedAt ?? a.createdAt
        let dateB = b.tripEndDate ?? b.lastEditedAt ?? b.createdAt
        return dateA > dateB
    }

    /// Returns a saved blog whose date range overlaps or continues from the given trip.
    /// Comparisons are day-granular because trip dates are midnight-based (parsed from
    /// dateText) while blog dates may carry intra-day time components.
    private func findMatchingSavedBlog(for trip: TripDraft) -> CreatedRecapBlog? {
        guard let tripStart = trip.earliestDate else {
            #if DEBUG
            debugPrint("[Scan] findMatchingSavedBlog: trip has no earliestDate, skipping")
            #endif
            return nil
        }
        let tripEnd = trip.latestDate ?? tripStart
        let cal = Calendar.current

        #if DEBUG
        debugPrint("[Scan] findMatchingSavedBlog: trip \"\(trip.title)\" tripStart=\(scanDbg(tripStart)) tripEnd=\(scanDbg(tripEnd)) checking \(createdRecapStore.visibleRecents.count) blog(s)")
        #endif

        for blog in createdRecapStore.visibleRecents {
            guard let blogStart = blog.tripStartDate, let blogEnd = blog.tripEndDate else {
                #if DEBUG
                debugPrint("[Scan]   blog \"\(blog.title)\" — no start/end date, skip")
                #endif
                continue
            }

            let blogStartDay = cal.startOfDay(for: blogStart)
            let blogEndDay   = cal.startOfDay(for: blogEnd)

            let overlaps  = tripEnd >= blogStartDay && tripStart <= blogEndDay
            let hourDiff  = cal.dateComponents([.hour], from: blogEnd, to: tripStart).hour ?? Int.max
            let continues = hourDiff >= 0 && hourDiff <= 24

            #if DEBUG
            debugPrint("[Scan]   blog \"\(blog.title)\" blogStart=\(scanDbg(blogStartDay)) blogEnd=\(scanDbg(blogEndDay)) overlaps=\(overlaps) hourDiff=\(hourDiff) continues=\(continues)")
            #endif

            guard overlaps || continues else { continue }

            #if DEBUG
            debugPrint("[Scan]   → MATCHED blog \"\(blog.title)\" (date overlap/continuation)")
            #endif
            return blog
        }
        #if DEBUG
        debugPrint("[Scan] findMatchingSavedBlog: no match found")
        #endif
        return nil
    }

    /// Returns true when `newTrip` overlaps with or is a temporal continuation
    /// of `existing` (starts within 7 days of the existing trip's end date).
    private func areTripsRelated(_ existing: TripDraft, _ newTrip: TripDraft) -> Bool {
        guard let existingStart = existing.earliestDate,
              let existingEnd = existing.latestDate,
              let newStart = newTrip.earliestDate else { return false }
        let newEnd = newTrip.latestDate ?? newStart

        let countriesMatch: Bool = {
            guard let ec = existing.primaryCountryDisplayName?.lowercased(), !ec.isEmpty,
                  let nc = newTrip.primaryCountryDisplayName?.lowercased(), !nc.isEmpty else {
                return true
            }
            return ec == nc
        }()

        // Overlapping date ranges → same trip (e.g. new photo falls within existing trip dates).
        if newEnd >= existingStart && newStart <= existingEnd {
            return countriesMatch
        }

        // Forward continuation: new trip starts within 7 days after existing trip ends.
        let dayDiff = Calendar.current.dateComponents([.day], from: existingEnd, to: newStart).day ?? Int.max
        guard dayDiff >= 0 && dayDiff <= 7 else { return false }
        return countriesMatch
    }

    /// Returns the index of an existing draft that already contains every photo (by localIdentifier)
    /// of `newTrip`. Used to avoid showing the same captured photo in two trips (camera draft + scanned).
    private func existingDraftIndexContainingAllPhotos(of newTrip: TripDraft) -> Int? {
        let newIds = Set(newTrip.days.flatMap(\.photos).compactMap(\.localIdentifier))
        guard !newIds.isEmpty else { return nil }
        return tripDrafts.firstIndex { existing in
            let existingIds = Set(existing.days.flatMap(\.photos).compactMap(\.localIdentifier))
            return newIds.isSubset(of: existingIds)
        }
    }

    /// Merges `newTrip` into `existing`: new photos are added to matching days,
    /// and entirely new days are appended. Returns `(merged, didChange)`.
    private func appendDaysFromTrip(_ newTrip: TripDraft, into existing: TripDraft) -> (TripDraft, Bool) {
        var merged = existing
        var didChange = false

        let existingDates = Set(existing.days.map(\.dateText))

        for newDay in newTrip.days where existingDates.contains(newDay.dateText) {
            guard let dayIdx = merged.days.firstIndex(where: { $0.dateText == newDay.dateText }) else { continue }
            let existingIds = Set(merged.days[dayIdx].photos.compactMap(\.localIdentifier))
            let freshPhotos = newDay.photos.filter { photo in
                guard let lid = photo.localIdentifier else { return false }
                return !existingIds.contains(lid)
            }
            if !freshPhotos.isEmpty {
                merged.days[dayIdx].photos.append(contentsOf: freshPhotos)
                merged.days[dayIdx].photos.sort { $0.timestamp < $1.timestamp }
                didChange = true
            }
        }

        let uniqueNewDays = newTrip.days.filter { !existingDates.contains($0.dateText) }
        if !uniqueNewDays.isEmpty {
            didChange = true
            let fmt = DateFormatter()
            fmt.locale = Locale.current
            fmt.dateStyle = .medium

            var allDays = (merged.days + uniqueNewDays).sorted {
                (fmt.date(from: $0.dateText) ?? .distantPast) < (fmt.date(from: $1.dateText) ?? .distantPast)
            }
            allDays = allDays.enumerated().map { idx, day in
                var d = day; d.dayIndex = idx; return d
            }
            merged.days = allDays
        }

        return (merged, didChange)
    }

    /// Drops photos outside `[rangeStart, rangeEnd]` (inclusive), removes empty days, reindexes days,
    /// and refreshes `dateRangeText` / `daysSeasonText`. Used when the user picks a place card span
    /// but the library scan merged a longer multi-day trip that only overlaps that span.
    private func trimTripDraftToPhotoTimestamps(_ trip: TripDraft, rangeStart: Date, rangeEnd: Date) -> TripDraft {
        print("[TrimToDates] rangeStart=\(rangeStart) rangeEnd=\(rangeEnd)")
        var result = trip
        var newDays: [TripDay] = []
        for day in trip.days {
            let kept = day.photos.filter { photo in
                let pass = photo.timestamp >= rangeStart && photo.timestamp <= rangeEnd
                if !pass {
                    print("[TrimToDates] DROPPED photo ts=\(photo.timestamp) (before rangeStart or after rangeEnd)")
                }
                return pass
            }
            guard !kept.isEmpty else { continue }
            print("[TrimToDates] DAY kept=\(kept.count) photos, first=\(kept.first?.timestamp.description ?? "-") last=\(kept.last?.timestamp.description ?? "-")")
            var d = day
            d.photos = kept.sorted { $0.timestamp < $1.timestamp }
            newDays.append(d)
        }
        newDays = newDays.enumerated().map { idx, day in
            var d = day
            d.dayIndex = idx
            return d
        }
        result.days = newDays
        if let first = newDays.first, let last = newDays.last {
            result.dateRangeText = first.dateText == last.dateText
                ? first.dateText
                : "\(first.dateText) – \(last.dateText)"
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMM yyyy"
            let parseFmt = DateFormatter()
            parseFmt.locale = Locale.current
            parseFmt.dateStyle = .medium
            if let firstDate = parseFmt.date(from: first.dateText) {
                let suffix = monthYearFormatter.string(from: firstDate)
                result.daysSeasonText = "\(newDays.count) day\(newDays.count == 1 ? "" : "s") • \(suffix)"
            }
        }
        return result
    }

    /// After a default scan, check whether any scanned drafts are temporal continuations
    /// of the user's currently active on-the-go blog.  When they are, signal new moments
    /// so the next "Tap to Blog" tap shows the update popup.
    private func detectNewMomentsForOnTheGoTrip(scannedDrafts: [TripDraft]) {
        debugPrint("[detectNewMomentsForOnTheGoTrip] called with \(scannedDrafts.count) scanned drafts")

        guard let activeBlogId = OnTheGoTripStore.activeBlogId,
              OnTheGoTripStore.isTripStillOngoing() else {
            if OnTheGoTripStore.activeBlogId != nil && !OnTheGoTripStore.isTripStillOngoing() {
                OnTheGoTripStore.markTripAsEnded()
            }
            debugPrint("[detectNewMomentsForOnTheGoTrip] no active on-the-go trip or trip ended, skipping")
            return
        }

        guard let activeBlog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == activeBlogId }),
              let blogEndDate = activeBlog.tripEndDate else {
            debugPrint("[detectNewMomentsForOnTheGoTrip] active blog not found or no tripEndDate")
            return
        }

        let cal = Calendar.current

        // A continuation draft starts within 7 days of the blog's last day.
        let continuationDrafts = scannedDrafts.filter { draft in
            guard let earliest = draft.earliestDate else { return false }
            let dayDiff = cal.dateComponents([.day], from: blogEndDate, to: earliest).day ?? Int.max
            return dayDiff >= 0 && dayDiff <= 7
        }

        debugPrint("[detectNewMomentsForOnTheGoTrip] blogEndDate=\(blogEndDate), continuationDrafts.count=\(continuationDrafts.count)")

        if !continuationDrafts.isEmpty {
            let lastDayIndex = max(0, activeBlog.tripDurationDays - 1)
            // Apply the same cutoff filter used in collectNewPhotosForSavedBlogs so that
            // already-notified photos are not re-surfaced on every scan while the trip
            // is still considered "ongoing".
            let cutoff = ScanSessionStore.lastBlogNotifiedDate(for: activeBlog.id) ?? blogEndDate
            let continuationPhotos = continuationDrafts.flatMap { $0.days.flatMap(\.photos) }
                .filter { $0.timestamp > cutoff }
            guard !continuationPhotos.isEmpty else {
                debugPrint("[detectNewMomentsForOnTheGoTrip] no new continuation photos after cutoff (\(cutoff)); skipping")
                return
            }
            // Only honor one blog (latest). If we already have a match, keep it only if it's the same or newer.
            var didHonorThisBlog = false
            if let existing = newMomentsMatchedBlog {
                if existing.sourceTripId == activeBlog.sourceTripId {
                    newlyScannedPhotos.append(contentsOf: continuationPhotos)
                    newlyScannedPhotos = dedupePhotosByLocalId(newlyScannedPhotos)
                    didHonorThisBlog = true
                } else if isBlogNewer(activeBlog, than: existing) {
                    newMomentsMatchedBlog = activeBlog
                    newlyScannedPhotos = dedupePhotosByLocalId(continuationPhotos)
                    didHonorThisBlog = true
                }
                // else existing is newer, don't add on-the-go
            } else {
                newMomentsMatchedBlog = activeBlog
                newlyScannedPhotos.append(contentsOf: continuationPhotos)
                newlyScannedPhotos = dedupePhotosByLocalId(newlyScannedPhotos)
                didHonorThisBlog = true
            }
            if didHonorThisBlog {
                OnTheGoTripStore.signalNewMoments(dayIndex: lastDayIndex)
            }
            debugPrint("[detectNewMomentsForOnTheGoTrip] signaled new moments, lastDayIndex=\(lastDayIndex), continuationPhotos=\(continuationPhotos.count), newlyScannedPhotos.total=\(newlyScannedPhotos.count), didHonorThisBlog=\(didHonorThisBlog)")
        }
    }

    /// Opens the Find More Trips sheet.
    /// On the first open of a session (cold start), resets Start/End year+month to current month/year.
    /// On subsequent opens within the same session, preserves the user's last selection.
    func openFindMoreSheet() {
        findMoreScanResult = .none
        if !hasOpenedFindMoreSheet {
            let now = Date()
            let cal = Calendar.current
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            findMoreStartYear = year
            findMoreStartMonth = month
            findMoreEndYear  = year
            findMoreEndMonth = month
            hasOpenedFindMoreSheet = true
        }
        showFindMoreSheet = true
    }

    /// End must be on or after Start for a scan to make sense.
    var isDateRangeValid: Bool {
        let startTotal = findMoreStartYear * 12 + findMoreStartMonth
        let endTotal   = findMoreEndYear   * 12 + findMoreEndMonth
        return endTotal >= startTotal
    }

    // MARK: - NLP Parsing Chat

    func submitFindMoreChat() {
        guard !findMoreChatInput.isEmpty else { return }
        
        isParsingChat = true
        findMoreChatResponse = "Thinking..."
        needsConfirmationForParse = false
        pendingParseResult = nil
        
        let inputText = findMoreChatInput
        
        Task {
            let result = await FindMoreTripsAgent.process(
                input: inputText,
                currentStart: (year: findMoreStartYear, month: findMoreStartMonth),
                currentEnd: (year: findMoreEndYear, month: findMoreEndMonth)
            )
            
            await MainActor.run {
                self.isParsingChat = false
                self.findMoreChatResponse = result.answerText
                
                if let sY = result.startYear, let sM = result.startMonth,
                   let eY = result.endYear, let eM = result.endMonth {
                    
                    if result.intent == .query_place_presence {
                        // For yes/no checking, the agent has inferred the range.
                        self.findMoreStartYear = sY
                        self.findMoreStartMonth = sM
                        self.findMoreEndYear = eY
                        self.findMoreEndMonth = eM
                        self.scanFindMoreTripsInRange()
                    }
                    else if result.intent == .set_range {
                        if result.confidence >= 0.8 && !result.needsConfirmation {
                            self.findMoreStartYear = sY
                            self.findMoreStartMonth = sM
                            self.findMoreEndYear = eY
                            self.findMoreEndMonth = eM
                            self.scanFindMoreTripsInRange()
                        } else {
                            self.needsConfirmationForParse = true
                            self.pendingParseResult = result
                        }
                    }
                }
            }
        }
    }
    
    func confirmPendingParse() {
        if let result = pendingParseResult,
           let sY = result.startYear, let sM = result.startMonth,
           let eY = result.endYear, let eM = result.endMonth {
            self.findMoreStartYear = sY
            self.findMoreStartMonth = sM
            self.findMoreEndYear = eY
            self.findMoreEndMonth = eM
            self.needsConfirmationForParse = false
            self.pendingParseResult = nil
            self.scanFindMoreTripsInRange()
        }
    }
    
    func cancelPendingParse() {
        self.needsConfirmationForParse = false
        self.pendingParseResult = nil
        self.findMoreChatResponse = nil
    }

    /// Scan for trips in the selected start/end year+month range. Dedupes against existing list.
    func scanFindMoreTripsInRange() {
        guard !isFindMoreScanning else { return }
        isFindMoreScanning = true
        findMoreScanProgress = 0
        findMoreScanResult = .none
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")
        let startYear = findMoreStartYear
        let startMonth = findMoreStartMonth
        let endYear = findMoreEndYear
        let endMonth = findMoreEndMonth
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        findMoreScanTask = Task {
            // Keep My Drafts for dedup context
            let myDraftIds = TripDraftStore.draftTripIds()
            let draftOnlyTrips = tripDrafts.filter { myDraftIds.contains($0.id) }

            let newTrips = await photoLibraryService.scanInDateRange(
                startYear: startYear, startMonth: startMonth,
                endYear: endYear, endMonth: endMonth,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] value in
                    Task { @MainActor in
                        self?.findMoreScanProgress = value
                    }
                }
            )
            guard !Task.isCancelled else { return }
            hasPerformedCustomScan = true
            let existingKeys = Set(draftOnlyTrips.map { "\($0.title)|\($0.dateRangeText)" })
            let deduped = newTrips.filter { trip in
                !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                && !createdRecapStore.isDraftRedundantWithSavedBlogs(trip)
            }
            AppAnalytics.shared.trackEvent(name: "trip_scan_completed")
            AppAnalytics.shared.incrementCounter("trips_detected", by: newTrips.count)
            
            if deduped.isEmpty {
                findMoreScanResult = .empty
            } else {
                withAnimation {
                    tripDrafts = draftOnlyTrips + deduped
                }
                findMoreScanResult = .success(deduped.count)
                showSelectPhotosIntroAfterScan = false
                
                // Reset the window so the carousel shows the fresh scan results
                // instead of stale loadOlder/loadNewer trips.
                currentWindowTrips = nil

                // Update the scanned date bounds to match the Find More range.
                let cal = Calendar.current
                var startComps = DateComponents(); startComps.year = startYear; startComps.month = startMonth; startComps.day = 1
                var endComps = DateComponents(); endComps.year = endYear; endComps.month = endMonth; endComps.day = 1
                if let s = cal.date(from: startComps) {
                    earliestScannedDate = cal.startOfDay(for: s)
                }
                if let e = cal.date(from: endComps),
                   let endOfRange = cal.date(byAdding: .month, value: 1, to: e) {
                    latestScannedDate = endOfRange
                }

                // Cache the Find More results for instant restore.
                if let ws = earliestScannedDate, let we = latestScannedDate {
                    windowCache[windowCacheKey(start: ws, end: we)] = newTrips
                }

                // Record last-scanned date only when the selected end range is the current month.
                // Older-timeline scans should not update the incremental baseline.
                let now = Date()
                let cal2 = Calendar.current
                if endYear == cal2.component(.year, from: now) && endMonth == cal2.component(.month, from: now) {
                    ScanSessionStore.saveLastScannedDate(now, for: currentUserId)
                }
            }

            isFindMoreScanning = false
        }
    }

    /// Cancel an in-progress Find More scan.
    func cancelFindMoreScan() {
        findMoreScanTask?.cancel()
        findMoreScanTask = nil
        isFindMoreScanning = false
        findMoreScanProgress = 0
    }

    func dismissFindMoreSheet() {
        showFindMoreSheet = false
        findMoreScanResult = .none
    }

    // MARK: - Visited Cities

    /// Opens the sheet and starts building the city list if not already done.
    func openVisitedCitiesSheet() {
        showVisitedCitiesSheet = true
    }

    /// Loads visited cities for `year`. Returns immediately if cached;
    /// otherwise starts a background scan. Clears previous trips before scanning.
    func loadVisitedCities(year: Int) {
        visitedCitiesBuildTask?.cancel()
        visitedCitiesBuildTask = nil
        visitedCitiesYear = year

        if let cached = VisitedCitiesService.shared.loadCached(userId: currentUserId, year: year) {
            visitedCityTrips = cached
            visitedCitiesBuildState = .done
            return
        }

        visitedCityTrips = []
        visitedCitiesBuildState = .building(0)
        visitedCitiesBuildTask = Task {
            let trips = await VisitedCitiesService.shared.buildVisitedCities(year: year) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .building = self.visitedCitiesBuildState {
                        self.visitedCitiesBuildState = .building(p)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            VisitedCitiesService.shared.saveCache(trips, userId: currentUserId, year: year)
            visitedCityTrips = trips
            visitedCitiesBuildState = .done
        }
    }

    /// Clears cache for the current year and re-runs the scan.
    func refreshVisitedCities() {
        VisitedCitiesService.shared.clearCache(userId: currentUserId, year: visitedCitiesYear)
        loadVisitedCities(year: visitedCitiesYear)
    }

    /// Walks `visitedCityTrips` outward from `cityTrip` and merges all neighbors
    /// that are part of the same continuous travel block.
    ///
    /// "Continuous" is measured by counting uncovered calendar days between consecutive
    /// trips — days that no detected trip spans. This day-by-day count is more reliable
    /// than a raw date-diff because some days silently disappear from detection when
    /// photos lack valid GPS metadata. A threshold of 5 uncovered days tolerates those
    /// gaps without merging unrelated trips.
    private func continuousDateRange(for cityTrip: VisitedCityTrip) -> (start: Date, end: Date) {
        let maxUncoveredDays = 5
        let cal = Calendar.current
        let sorted = visitedCityTrips.sorted { $0.startDate < $1.startDate }
        guard let idx = sorted.firstIndex(where: { $0.id == cityTrip.id }) else {
            return (cityTrip.startDate, cityTrip.endDate)
        }

        // Build a set of every calendar day that is covered by at least one detected trip.
        var coveredDays = Set<Date>()
        for trip in sorted {
            var day = cal.startOfDay(for: trip.startDate)
            let end = cal.startOfDay(for: trip.endDate)
            while day <= end {
                coveredDays.insert(day)
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }

        /// Counts calendar days in the open interval (from, to) that are NOT in coveredDays.
        func uncoveredDays(from: Date, to: Date) -> Int {
            var count = 0
            var day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from))!
            let limit = cal.startOfDay(for: to)
            while day < limit {
                if !coveredDays.contains(day) { count += 1 }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
            return count
        }

        var lo = idx
        var hi = idx

        while lo > 0 {
            let gap = uncoveredDays(from: sorted[lo - 1].endDate, to: sorted[lo].startDate)
            if gap <= maxUncoveredDays { lo -= 1 } else { break }
        }
        while hi < sorted.count - 1 {
            let gap = uncoveredDays(from: sorted[hi].endDate, to: sorted[hi + 1].startDate)
            if gap <= maxUncoveredDays { hi += 1 } else { break }
        }
        return (sorted[lo].startDate, sorted[hi].endDate)
    }

    /// Runs a full trip scan over the continuous block of visited-city trips that
    /// surrounds the tapped entry (neighboring places with ≤ 2-day gaps are included).
    func scanVisitedCityTrip(_ cityTrip: VisitedCityTrip) {
        guard !isVisitedCityScanning else { return }
        isVisitedCityScanning = true
        visitedCityScanProgress = 0

        let cal = Calendar.current
        let (expandedStart, expandedEnd) = continuousDateRange(for: cityTrip)
        // 1 day before the earliest continuous trip so transit photos are captured
        let startDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: expandedStart)) ?? expandedStart
        // 1 day after the latest continuous trip's end
        let endDate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: expandedEnd)) ?? expandedEnd
        let occupiedRanges = createdRecapStore.occupiedDateRanges()

        let dbgFmt = ISO8601DateFormatter()
        dbgFmt.formatOptions = [.withFullDate]
        print("[VisitedCity] Tapped: \(cityTrip.displayTitle)")
        print("[VisitedCity]   cityTrip.startDate  : \(dbgFmt.string(from: cityTrip.startDate))")
        print("[VisitedCity]   cityTrip.endDate    : \(dbgFmt.string(from: cityTrip.endDate))")
        print("[VisitedCity]   expandedStart       : \(dbgFmt.string(from: expandedStart))")
        print("[VisitedCity]   expandedEnd         : \(dbgFmt.string(from: expandedEnd))")
        print("[VisitedCity]   scan startDate      : \(dbgFmt.string(from: startDate))")
        print("[VisitedCity]   scan endDate        : \(dbgFmt.string(from: endDate))")

        visitedCityScanTask = Task {
            let newTrips = await photoLibraryService.scanInDateRange(
                startDate: startDate,
                endDate: endDate,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] p in
                    Task { @MainActor [weak self] in self?.visitedCityScanProgress = p }
                }
            )
            guard !Task.isCancelled else {
                isVisitedCityScanning = false
                return
            }

            let myDraftIds = TripDraftStore.draftTripIds()
            let draftOnlyTrips = tripDrafts.filter { myDraftIds.contains($0.id) }
            let existingKeys = Set(draftOnlyTrips.map { "\($0.title)|\($0.dateRangeText)" })
            let deduped = newTrips.filter { trip in
                !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                    && !createdRecapStore.isDraftRedundantWithSavedBlogs(trip)
            }

            withAnimation {
                if !deduped.isEmpty {
                    tripDrafts = draftOnlyTrips + deduped
                }
                currentWindowTrips = nil
            }
            isVisitedCityScanning = false
        }
    }

    /// Cancels an in-progress visited-city trip scan.
    func cancelVisitedCityScan() {
        visitedCityScanTask?.cancel()
        isVisitedCityScanning = false
        visitedCityScanProgress = 0
    }

    /// Builds a single trip from selected place cards and exposes it via
    /// `pendingVisitedCitiesCreateTrip` for the create-blog flow.
    /// Returns false when no photos/trips could be built in the selected range.
    func createTripFromVisitedCitiesSelection(_ selected: [VisitedCityTrip]) async -> Bool {
        guard !selected.isEmpty else { return false }
        let cal = Calendar.current
        let selectedStart = selected.map(\.startDate).min() ?? Date()
        let selectedEnd = selected.map(\.endDate).max() ?? selectedStart

        // Use the destination timezone from the trip so that "start of day" and "end of day"
        // are computed at the travel location, not on the device.
        // trip.startDate is already midnight in the destination TZ (set by VisitedCitiesService),
        // but Calendar.current.startOfDay() would shift it to midnight in the DEVICE timezone —
        // causing photos from the previous calendar day at the destination to slip through.
        let destTzId = selected.compactMap(\.displayTimeZoneIdentifier).first
        let destTz = destTzId.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        var destCal = Calendar(identifier: .gregorian)
        destCal.timeZone = destTz

        let selectionDayStart = destCal.startOfDay(for: selectedStart)
        let selectionDayEnd = destCal.startOfDay(for: selectedEnd)
        let selectionSpanDays = (destCal.dateComponents([.day], from: selectionDayStart, to: selectionDayEnd).day ?? 0) + 1
        // Multi-place selections are capped at 7 calendar days in the UI; single-place rows can exceed 7 days with a warning.
        if selectionSpanDays > 7, selected.count > 1 { return false }

        // Pad both edges to avoid clipping transit/arrival/departure moments.
        let fetchStart = cal.date(byAdding: .day, value: -2, to: selectionDayStart) ?? selectedStart
        let endOfSelectedDay = destCal.date(bySettingHour: 23, minute: 59, second: 59, of: selectedEnd) ?? selectedEnd
        let fetchEnd = cal.date(byAdding: .day, value: 2, to: endOfSelectedDay) ?? endOfSelectedDay

        let deviceTz = TimeZone.current
        print("[CreateBlog][TZ] device=\(deviceTz.identifier) dest=\(destTz.identifier)")
        print("[CreateBlog][TZ] trip.startDate=\(selectedStart) selectionDayStart=\(selectionDayStart) endOfSelectedDay=\(endOfSelectedDay)")
        print("[CreateBlog][TZ] fetchStart=\(fetchStart) fetchEnd=\(fetchEnd)")

        let scanned = await photoLibraryService.scanInDateRange(
            startDate: fetchStart,
            endDate: fetchEnd,
            occupiedDateRanges: []
        )

        guard !scanned.isEmpty else { return false }

        // Keep trips that overlap the selected span, then merge them into one draft.
        let overlapping = scanned.filter { trip in
            guard let start = trip.earliestDate else { return false }
            let end = trip.latestDate ?? start
            return end >= selectedStart && start <= endOfSelectedDay
        }

        guard !overlapping.isEmpty else { return false }
        guard var merged = overlapping.first else { return false }
        if overlapping.count > 1 {
            for trip in overlapping.dropFirst() {
                let (combined, _) = appendDaysFromTrip(trip, into: merged)
                merged = combined
            }
        }

        merged = trimTripDraftToPhotoTimestamps(merged, rangeStart: selectionDayStart, rangeEnd: endOfSelectedDay)
        guard merged.days.contains(where: { !$0.photos.isEmpty }) else { return false }

        // Select all photos for immediate blog creation path.
        for dayIdx in merged.days.indices {
            for photoIdx in merged.days[dayIdx].photos.indices {
                merged.days[dayIdx].photos[photoIdx].isSelected = true
            }
        }

        let titleCity = selected.first?.cityName ?? merged.cityWithMostPhotosDisplayName
        let titleCountry = selected.first?.countryName ?? (merged.primaryCountryDisplayName ?? "Trip")
        merged.title = titleCity.isEmpty ? titleCountry : "\(titleCity), \(titleCountry)"
        merged.coverAssetIdentifier = selected.first?.coverAssetIdentifier ?? merged.coverAssetIdentifier
        merged.coverImageName = "photo"
        merged.isScannedFromDefaultRange = false

        pendingVisitedCitiesCreateTrip = merged
        return true
    }

    func clearPendingVisitedCitiesCreateTrip() {
        pendingVisitedCitiesCreateTrip = nil
    }

    /// Builds a TripDraft from manually selected photo library asset identifiers (camera roll picker).
    /// Photos are grouped by calendar day; location data is used when available but not required.
    func buildTripDraftFromCameraRollSelection(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        assets.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        guard !assets.isEmpty else { return }

        let cal = Calendar.current
        var dayGroups: [(date: Date, assets: [PHAsset])] = []
        for asset in assets {
            let date = asset.creationDate ?? Date()
            let dayStart = cal.startOfDay(for: date)
            if let last = dayGroups.last, cal.isDate(last.date, inSameDayAs: dayStart) {
                dayGroups[dayGroups.count - 1].assets.append(asset)
            } else {
                dayGroups.append((date: dayStart, assets: [asset]))
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let tripDays: [TripDay] = dayGroups.enumerated().map { dayIndex, group in
            let photos: [MockPhoto] = group.assets.map { asset in
                let coord: PhotoCoordinate? = asset.location.map {
                    PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }
                return MockPhoto(
                    imageName: "photo",
                    timestamp: asset.creationDate ?? group.date,
                    locationName: nil,
                    countryName: nil,
                    isSelected: true,
                    localIdentifier: asset.localIdentifier,
                    location: coord
                )
            }
            return TripDay(
                dayIndex: dayIndex + 1,
                dateText: formatter.string(from: group.date),
                photos: photos
            )
        }

        let firstDate = dayGroups.first!.date
        let lastDate = dayGroups.last!.date
        let dateRangeText = cal.isDate(firstDate, inSameDayAs: lastDate)
            ? formatter.string(from: firstDate)
            : "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"

        let draft = TripDraft(
            title: "Camera Roll Selection",
            dateRangeText: dateRangeText,
            days: tripDays,
            coverImageName: "photo",
            isScannedFromDefaultRange: false,
            draftCreatedAgoText: "From your camera roll",
            daysSeasonText: "\(tripDays.count) day\(tripDays.count == 1 ? "" : "s")",
            coverTheme: "default",
            coverAssetIdentifier: assets.first?.localIdentifier
        )

        await MainActor.run { pendingVisitedCitiesCreateTrip = draft }
    }

    // MARK: - Load Older Trips

    /// True when the current window's end date is far enough in the past that a newer window exists.
    var canLoadNewerTrips: Bool {
        guard let latest = latestScannedDate else { return false }
        // Allow if the window end is more than 7 days before today (i.e. not the live window).
        return (Calendar.current.dateComponents([.day], from: latest, to: Date()).day ?? 0) >= 7
    }

    /// Scan the previous 90-day windows before `earliestScannedDate`, sliding back up to 4 times
    /// until at least 3 visible trips are found (or all attempts are exhausted).
    /// Replaces the displayed trips with the first qualifying window.
    func loadOlderTrips() {
        guard !isLoadingOlderTrips, let earliest = earliestScannedDate else { return }

        let cal = Calendar.current
        isLoadingOlderTrips = true
        loadOlderProgress = 0
        olderTripsResult = .none
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")

        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        loadOlderScanTask = Task {
            var currentWindowEnd = cal.startOfDay(for: earliest)
            var finalTrips: [TripDraft] = []
            var finalWindowStart = currentWindowEnd
            var finalWindowEnd = currentWindowEnd

            for _ in 1...4 {
                guard let windowStart = cal.date(byAdding: .day, value: -ScanConfig.windowDays, to: currentWindowEnd) else { break }
                let windowEnd = currentWindowEnd
                let cacheKey = windowCacheKey(start: windowStart, end: windowEnd)

                let windowTrips: [TripDraft]
                if let cached = windowCache[cacheKey] {
                    windowTrips = cached
                } else {
                    // Pad the fetch range so trips straddling a window boundary are built in full.
                    let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: windowStart) ?? windowStart
                    let fetchEnd = cal.date(byAdding: .day, value: Self.fetchPaddingDays, to: windowEnd) ?? windowEnd

                    let allTrips = await photoLibraryService.scanInDateRange(
                        startDate: fetchStart,
                        endDate: fetchEnd,
                        occupiedDateRanges: occupiedRanges,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.loadOlderProgress = value }
                        }
                    )
                    guard !Task.isCancelled else {
                        isLoadingOlderTrips = false
                        return
                    }

                    windowTrips = allTrips.filter { trip in
                        tripOverlapsWindow(trip, windowStart: windowStart, windowEnd: windowEnd)
                    }
                    windowCache[cacheKey] = windowTrips
                }

                finalTrips = windowTrips
                finalWindowStart = windowStart
                finalWindowEnd = windowEnd

                // Count visible trips (excluding already-created blogs).
                let visibleCount = windowTrips.filter { trip in
                    !createdRecapStore.hasCreatedBlog(sourceTripId: trip.id)
                        && !createdRecapStore.isDraftRedundantWithSavedBlogs(trip)
                }.count

                if visibleCount >= 3 { break }

                // Not enough trips — slide window further back.
                currentWindowEnd = windowStart
            }

            AppAnalytics.shared.trackEvent(name: "trip_scan_completed")
            AppAnalytics.shared.incrementCounter("trips_detected", by: finalTrips.count)

            let count = applyWindowTrips(finalTrips, windowStart: finalWindowStart, windowEnd: finalWindowEnd)
            olderTripsResult = count > 0 ? .success(count) : .empty
            isLoadingOlderTrips = false
        }
    }

    /// Triggers `loadOlderTrips()` automatically when no trips are currently visible
    /// and no custom scan has been performed. Called from the empty state on appear.
    func autoLoadOlderTripsIfNeeded() {
        guard visibleDraftTripsNewestFirst.isEmpty,
              !hasPerformedCustomScan,
              !isLoadingOlderTrips,
              scanState == .idle else { return }
        loadOlderTrips()
    }

    /// Cancel an in-progress load-older scan.
    func cancelLoadOlderTrips() {
        loadOlderScanTask?.cancel()
        loadOlderScanTask = nil
        isLoadingOlderTrips = false
        loadOlderProgress = 0
    }

    // MARK: - Load Newer Trips

    /// Scan the 90 days after `latestScannedDate`, **replace** the displayed trips
    /// with only the new window, and slide both date bounds forward.
    /// Serves from the session cache when the window was already scanned.
    func loadNewerTrips() {
        guard !isLoadingNewerTrips, let latest = latestScannedDate else { return }

        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: latest)
        // Cap the end date at today so we never scan into the future.
        let rawEnd = cal.date(byAdding: .day, value: ScanConfig.windowDays, to: windowStart) ?? Date()
        let windowEnd = min(rawEnd, Date())

        let cacheKey = windowCacheKey(start: windowStart, end: windowEnd)

        // ── Cache hit — restore instantly, no scan needed. ──
        if let cached = windowCache[cacheKey] {
            newerTripsResult = .none              // reset so .onChange fires
            let count = applyWindowTrips(cached, windowStart: windowStart, windowEnd: windowEnd)
            newerTripsResult = count > 0 ? .success(count) : .empty
            return
        }

        // ── Cache miss — full photo scan. ──
        isLoadingNewerTrips = true
        loadNewerProgress = 0
        newerTripsResult = .none
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")

        // Pad the fetch range so trips straddling a window boundary are built in full.
        let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: windowStart) ?? windowStart
        let fetchEnd = cal.date(byAdding: .day, value: Self.fetchPaddingDays, to: windowEnd) ?? windowEnd

        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        loadNewerScanTask = Task {
            let allTrips = await photoLibraryService.scanInDateRange(
                startDate: fetchStart,
                endDate: fetchEnd,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] value in
                    Task { @MainActor in self?.loadNewerProgress = value }
                }
            )
            guard !Task.isCancelled else { return }

            // Keep trips that overlap the actual window [windowStart, windowEnd).
            let windowTrips = allTrips.filter { trip in
                tripOverlapsWindow(trip, windowStart: windowStart, windowEnd: windowEnd)
            }

            // Cache for instant restore on future visits.
            windowCache[cacheKey] = windowTrips

            AppAnalytics.shared.trackEvent(name: "trip_scan_completed")
            AppAnalytics.shared.incrementCounter("trips_detected", by: windowTrips.count)

            let count = applyWindowTrips(windowTrips, windowStart: windowStart, windowEnd: windowEnd)
            newerTripsResult = count > 0 ? .success(count) : .empty
            isLoadingNewerTrips = false
        }
    }

    /// Cancel an in-progress load-newer scan.
    func cancelLoadNewerTrips() {
        loadNewerScanTask?.cancel()
        loadNewerScanTask = nil
        isLoadingNewerTrips = false
        loadNewerProgress = 0
    }
}
