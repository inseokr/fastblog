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
    @Published var scanState: MockScanState = .idle
    @Published var loadingMessage: String = "Loading Past Trips…"

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
    /// The earliest date covered by scanning so far (default scan = now - 90 days).
    @Published var earliestScannedDate: Date?
    /// True while the "load older trips" scan is running.
    @Published var isLoadingOlderTrips: Bool = false
    /// Progress of the load-older scan (0.0 → 1.0).
    @Published var loadOlderProgress: Double = 0
    /// Result of the load-older scan.
    @Published var olderTripsResult: FindMoreScanResult = .none

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

    /// Trips ordered newest first (for vertical list: latest at top, older at bottom).
    var visibleDraftTripsNewestFirst: [TripDraft] {
        visibleDraftTrips.sorted { lhs, rhs in
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

    func startDefaultScan() {
        showSelectPhotosIntroAfterScan = true
        scanState = .scanningDefault
        loadingMessage = "Scanning your photos…"
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        Task {
            let trips = await photoLibraryService.scanLast3Months(occupiedDateRanges: occupiedRanges)
            tripDrafts = trips
            earliestScannedDate = Calendar.current.date(byAdding: .day, value: -ScanConfig.windowDays, to: Date())
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
            // Clear "Ready to Start" trips (previous scan results), keeping only My Drafts
            let myDraftIds = TripDraftStore.draftTripIds()
            tripDrafts = tripDrafts.filter { myDraftIds.contains($0.id) }

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
            let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })
            let saved = createdRecapStore.visibleRecents
            let deduped = newTrips.filter { trip in
                !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                && !TripMatchingService.isTripSaved(draft: trip, against: saved)
            }
            if deduped.isEmpty {
                findMoreScanResult = .empty
            } else {
                withAnimation {
                    tripDrafts.append(contentsOf: deduped)
                }
                findMoreScanResult = .success(deduped.count)
                showSelectPhotosIntroAfterScan = true
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

    /// Scan the previous 90 days before `earliestScannedDate`, append new trips, update the window.
    func loadOlderTrips() {
        guard !isLoadingOlderTrips, let earliest = earliestScannedDate else { return }
        isLoadingOlderTrips = true
        loadOlderProgress = 0
        olderTripsResult = .none

        let cal = Calendar.current
        let endDate = earliest
        guard let startDate = cal.date(byAdding: .day, value: -ScanConfig.windowDays, to: endDate) else {
            isLoadingOlderTrips = false
            return
        }

        let startComps = cal.dateComponents([.year, .month], from: startDate)
        let endComps = cal.dateComponents([.year, .month], from: endDate)
        guard let sY = startComps.year, let sM = startComps.month,
              let eY = endComps.year, let eM = endComps.month else {
            isLoadingOlderTrips = false
            return
        }

        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        loadOlderScanTask = Task {
            let newTrips = await photoLibraryService.scanInDateRange(
                startYear: sY, startMonth: sM,
                endYear: eY, endMonth: eM,
                occupiedDateRanges: occupiedRanges,
                progress: { [weak self] value in
                    Task { @MainActor in
                        self?.loadOlderProgress = value
                    }
                }
            )
            guard !Task.isCancelled else { return }

            let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })
            let saved = createdRecapStore.visibleRecents
            let deduped = newTrips.filter { trip in
                !existingKeys.contains("\(trip.title)|\(trip.dateRangeText)")
                && !createdRecapStore.hasCreatedBlog(sourceTripId: trip.id)
                && !TripMatchingService.isTripSaved(draft: trip, against: saved)
            }

            if deduped.isEmpty {
                olderTripsResult = .empty
            } else {
                withAnimation {
                    tripDrafts.append(contentsOf: deduped)
                }
                olderTripsResult = .success(deduped.count)
                showSelectPhotosIntroAfterScan = false
            }
            earliestScannedDate = startDate
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
}
