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

@MainActor
final class TripsViewModel: ObservableObject {
    @Published var tripDrafts: [TripDraft] = []
    /// The trips currently visible in the carousel — set explicitly by each scan so
    /// the display window is always a single, authoritative write, not a mutation of tripDrafts.
    /// When nil, falls back to the full visibleDraftTrips (default scan path).
    @Published var currentWindowTrips: [TripDraft]? = nil
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

    /// Trips ordered newest first — reads from currentWindowTrips when a windowed scan
    /// is active, otherwise falls back to the full visible draft list.
    var visibleDraftTripsNewestFirst: [TripDraft] {
        let source: [TripDraft]
        if let window = currentWindowTrips {
            source = window
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
    func removeTrip(id: UUID) {
        tripDrafts.removeAll { $0.id == id }
    }

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

    func startDefaultScan() {
        showSelectPhotosIntroAfterScan = true
        scanState = .scanningDefault
        loadingMessage = "Scanning your photos…"
        defaultScanProgress = 0
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        Task {
            let cal = Calendar.current
            let now = Date()
            let windowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -ScanConfig.windowDays, to: now) ?? now)
            let windowEnd = now

            // Pad the fetch start so boundary trips that started just before the window
            // are captured in full — then filtered out by earliestDate below.
            let fetchStart = cal.date(byAdding: .day, value: -Self.fetchPaddingDays, to: windowStart) ?? windowStart

            let allTrips = await photoLibraryService.scanInDateRange(
                startDate: fetchStart,
                endDate: windowEnd,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] value in
                    Task { @MainActor in
                        self?.defaultScanProgress = value
                    }
                }
            )

            // Keep only trips whose earliestDate falls within the window.
            let windowTrips = allTrips.filter { trip in
                guard let earliest = trip.earliestDate else { return false }
                return earliest >= windowStart
            }

            // Cache the window-filtered results for instant restore later.
            windowCache[windowCacheKey(start: windowStart, end: windowEnd)] = windowTrips

            tripDrafts = windowTrips
            // Reset window so the carousel shows the fresh default scan results.
            currentWindowTrips = nil
            earliestScannedDate = windowStart
            latestScannedDate = windowEnd
            scanState = .idle
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

            // Keep only trips whose earliestDate falls within the actual window [windowStart, windowEnd).
            let windowTrips = allTrips.filter { trip in
                guard let earliest = trip.earliestDate else { return false }
                return earliest >= windowStart && earliest < windowEnd
            }

            // Cache for instant restore on future visits.
            windowCache[cacheKey] = windowTrips

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

            // Keep only trips whose earliestDate falls within the actual window [windowStart, windowEnd).
            let windowTrips = allTrips.filter { trip in
                guard let earliest = trip.earliestDate else { return false }
                return earliest >= windowStart && earliest < windowEnd
            }

            // Cache for instant restore on future visits.
            windowCache[cacheKey] = windowTrips

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
