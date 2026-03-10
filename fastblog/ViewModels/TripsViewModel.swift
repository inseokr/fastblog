//
//  TripsViewModel.swift
//  Capper
//

import Combine
import Foundation
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

    /// Clears the new-moments signal after the user has ACTED on it (Go to Blog / Go to Trip).
    /// Persists the blog notification cutoff so the same photos are not surfaced again.
    func clearNewMomentsSignal() {
        if let blog = newMomentsMatchedBlog,
           let maxPhotoDate = newlyScannedPhotos.map(\.timestamp).max() {
            // Use max photo timestamp (not Date()) so only photos up to the last shown
            // photo are silenced. Genuinely newer photos still surface on the next scan.
            // Guard: if photos are empty for any reason, skip saving to avoid accidentally
            // setting a future cutoff via Date() that would silence real new photos.
            ScanSessionStore.saveBlogNotifiedDate(maxPhotoDate, for: blog.id)
        }
        resetNewMomentsState()
        pendingTripForCreateFlow = nil
        newMomentsSheetTriggeredByCreateButton = false
        openCreateFlowForPendingTrip = false
    }

    /// Presents the new-moments sheet after a brief delay so the view
    /// has finished transitioning from the scan loading state to the main content.
    private func presentNewMomentsSheetIfNeeded() {
        guard !newlyScannedPhotos.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.showNewlyScannedSheet = true
                }
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
                if let blog = matchedBlog, !blogPhotos.isEmpty {
                    self.newlyScannedPhotos = blogPhotos
                    self.newMomentsMatchedBlog = blog
                    self.newMomentsInExistingTrip = nil
                    self.newMomentsLatestDayIndex = 0
                    self.presentNewMomentsSheetIfNeeded()
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
    /// Tracks the running load-older scan task so it can be cancelled.
    private var loadOlderScanTask: Task<Void, Never>?
    /// Tracks the running load-newer scan task so it can be cancelled.
    private var loadNewerScanTask: Task<Void, Never>?

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
    /// This preserves Episode 1 for long trips that start just before the window
    /// but continue into it.
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
        let saved = createdRecapStore.visibleRecents
        let myDraftIds = TripDraftStore.draftTripIds()
        let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })

        let deduped = windowTrips.filter { trip in
            !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
            && !createdRecapStore.hasCreatedBlog(sourceTripId: trip.id)
            && !TripMatchingService.isTripSaved(draft: trip, against: saved)
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
        let saved = createdRecapStore.visibleRecents
        return tripDrafts.filter { draft in
            !createdRecapStore.hasCreatedBlog(sourceTripId: draft.id)
            && !TripMatchingService.isTripSaved(draft: draft, against: saved)
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
            let saved = createdRecapStore.visibleRecents
            source = window.filter { draft in
                !createdRecapStore.hasCreatedBlog(sourceTripId: draft.id)
                && !TripMatchingService.isTripSaved(draft: draft, against: saved)
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

    func startDefaultScan() {
        showSelectPhotosIntroAfterScan = true
        scanState = .scanningDefault
        loadingMessage = "Loading your trips…"
        defaultScanProgress = 0
        newlyScannedPhotos = []
        newMomentsMatchedBlog = nil
        showNewlyScannedSheet = false
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        let userId = currentUserId
        let previousLastScanned = ScanSessionStore.lastScannedDate(for: userId)

        #if DEBUG
        debugPrint("[Scan] ──── startDefaultScan ────")
        debugPrint("[Scan] lastScannedDate = \(scanDbg(previousLastScanned))")
        debugPrint("[Scan] tripDrafts.count = \(tripDrafts.count)")
        debugPrint("[Scan] savedBlogs.count = \(createdRecapStore.visibleRecents.count)")
        for (i, blog) in createdRecapStore.visibleRecents.enumerated() {
            debugPrint("[Scan]   blog[\(i)] \"\(blog.title)\" createdAt=\(scanDbg(blog.createdAt)) start=\(scanDbg(blog.tripStartDate)) end=\(scanDbg(blog.tripEndDate)) country=\(blog.countryName ?? "nil")")
        }
        debugPrint("[Scan] occupiedRanges.count = \(occupiedRanges.count)")
        for (i, r) in occupiedRanges.enumerated() {
            debugPrint("[Scan]   range[\(i)] = \(scanDbg(r.start)) → \(scanDbg(r.end))")
        }
        #endif

        Task {
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
                let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: lastDate) ?? lastDate

                #if DEBUG
                debugPrint("[Scan] mode = INCREMENTAL")
                debugPrint("[Scan] fetchStart = \(scanDbg(fetchStart))  (lastScanned − \(Self.fetchPaddingDays)d)")
                debugPrint("[Scan] fetchEnd   = \(scanDbg(windowEnd))")
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
                let incrementalWindowStart = cal.startOfDay(for: lastDate)
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
    private func collectNewPhotosForSavedBlogs(from trips: [TripDraft]) {
        #if DEBUG
        debugPrint("[Scan] collectNewPhotosForSavedBlogs: checking \(trips.count) trip(s)")
        #endif
        var blogPhotos: [MockPhoto] = []
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
                blogPhotos.append(contentsOf: recentPhotos)
                if newMomentsMatchedBlog == nil { newMomentsMatchedBlog = blog }
            }
        }
        #if DEBUG
        debugPrint("[Scan] collectNewPhotosForSavedBlogs: total new = \(blogPhotos.count), showSheet = \(!blogPhotos.isEmpty)")
        #endif
        if !blogPhotos.isEmpty {
            newlyScannedPhotos.append(contentsOf: blogPhotos)
        }
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
                collectedNewPhotos.append(contentsOf: photos)
                if !photos.isEmpty && newMomentsMatchedBlog == nil { newMomentsMatchedBlog = blog }
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: matched saved blog \"\(blog.title)\" cutoff=\(scanDbg(cutoff)) totalPhotos=\(allPhotos.count) existingInBlog=\(existingIds.count) afterFilter=\(photos.count)")
                for p in allPhotos {
                    let afterCutoff = p.timestamp > cutoff
                    let alreadyInBlog = p.localIdentifier.map { existingIds.contains($0) } ?? false
                    let kept = afterCutoff && !alreadyInBlog
                    debugPrint("[Scan]   photo id=\(p.localIdentifier?.suffix(8) ?? "nil") ts=\(scanDbg(p.timestamp)) afterCutoff=\(afterCutoff) alreadyInBlog=\(alreadyInBlog) → kept=\(kept)")
                }
                #endif
                continue
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
            } else {
                // 3. Unrelated — new standalone trip. Only collect genuinely new photos.
                remainingNew.append(newTrip)
                let newPhotos = newTrip.days.flatMap(\.photos).filter { $0.timestamp > lastScanned }
                collectedNewPhotos.append(contentsOf: newPhotos)
                #if DEBUG
                debugPrint("[Scan] mergeIncremental: new standalone trip \"\(newTrip.title)\" days=\(newTrip.days.count) photos=\(newTrip.totalPhotoCount) genuinelyNew=\(newPhotos.count)")
                #endif
            }
        }

        let saved = createdRecapStore.visibleRecents
        let deduped = remainingNew.filter {
            !createdRecapStore.hasCreatedBlog(sourceTripId: $0.id)
            && !TripMatchingService.isTripSaved(draft: $0, against: saved)
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
            let dayDiff   = cal.dateComponents([.day], from: blogEndDay, to: tripStart).day ?? Int.max
            let continues = dayDiff >= 0 && dayDiff <= 7

            #if DEBUG
            let blogCountry = blog.countryName ?? "nil"
            let tripCountry = trip.primaryCountryDisplayName ?? "nil"
            debugPrint("[Scan]   blog \"\(blog.title)\" blogStart=\(scanDbg(blogStartDay)) blogEnd=\(scanDbg(blogEndDay)) overlaps=\(overlaps) dayDiff=\(dayDiff) continues=\(continues) blogCountry=\(blogCountry) tripCountry=\(tripCountry)")
            #endif

            guard overlaps || continues else { continue }

            if let bc = blog.countryName?.lowercased(), !bc.isEmpty,
               let tc = trip.primaryCountryDisplayName?.lowercased(), !tc.isEmpty {
                if bc == tc {
                    #if DEBUG
                    debugPrint("[Scan]   → MATCHED blog \"\(blog.title)\" (country match)")
                    #endif
                    return blog
                }
                #if DEBUG
                debugPrint("[Scan]   → country mismatch: blog=\(bc) trip=\(tc), skip")
                #endif
            } else {
                #if DEBUG
                debugPrint("[Scan]   → MATCHED blog \"\(blog.title)\" (no country filter)")
                #endif
                return blog
            }
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
            let continuationPhotos = continuationDrafts.flatMap { $0.days.flatMap(\.photos) }
            newlyScannedPhotos.append(contentsOf: continuationPhotos)
            newlyScannedPhotos = dedupePhotosByLocalId(newlyScannedPhotos)
            if newMomentsMatchedBlog == nil { newMomentsMatchedBlog = activeBlog }
            OnTheGoTripStore.signalNewMoments(dayIndex: lastDayIndex)
            debugPrint("[detectNewMomentsForOnTheGoTrip] signaled new moments, lastDayIndex=\(lastDayIndex), continuationPhotos=\(continuationPhotos.count), newlyScannedPhotos.total=\(newlyScannedPhotos.count)")
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
            let saved = createdRecapStore.visibleRecents
            let deduped = newTrips.filter { trip in
                !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                && !TripMatchingService.isTripSaved(draft: trip, against: saved)
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

    // MARK: - Load Older Trips

    /// True when the current window's end date is far enough in the past that a newer window exists.
    var canLoadNewerTrips: Bool {
        guard let latest = latestScannedDate else { return false }
        // Allow if the window end is more than 7 days before today (i.e. not the live window).
        return (Calendar.current.dateComponents([.day], from: latest, to: Date()).day ?? 0) >= 7
    }

    /// Scan the previous 90 days before `earliestScannedDate`, **replace** the displayed trips
    /// with only the new window, and slide both date bounds back.
    /// Serves from the session cache when the window was already scanned.
    func loadOlderTrips() {
        guard !isLoadingOlderTrips, let earliest = earliestScannedDate else { return }

        let cal = Calendar.current
        let windowEnd = cal.startOfDay(for: earliest)
        guard let windowStart = cal.date(byAdding: .day, value: -ScanConfig.windowDays, to: windowEnd) else { return }

        let cacheKey = windowCacheKey(start: windowStart, end: windowEnd)

        // ── Cache hit — restore instantly, no scan needed. ──
        if let cached = windowCache[cacheKey] {
            olderTripsResult = .none              // reset so .onChange fires
            let count = applyWindowTrips(cached, windowStart: windowStart, windowEnd: windowEnd)
            olderTripsResult = count > 0 ? .success(count) : .empty
            return
        }

        // ── Cache miss — full photo scan. ──
        isLoadingOlderTrips = true
        loadOlderProgress = 0
        olderTripsResult = .none
        AppAnalytics.shared.trackEvent(name: "trip_scan_started")

        // Pad the fetch range so trips straddling a window boundary are built in full.
        let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: windowStart) ?? windowStart
        let fetchEnd = cal.date(byAdding: .day, value: Self.fetchPaddingDays, to: windowEnd) ?? windowEnd

        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        loadOlderScanTask = Task {
            let allTrips = await photoLibraryService.scanInDateRange(
                startDate: fetchStart,
                endDate: fetchEnd,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] value in
                    Task { @MainActor in self?.loadOlderProgress = value }
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
            olderTripsResult = count > 0 ? .success(count) : .empty
            isLoadingOlderTrips = false
        }
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
