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

    /// Start/End year+month selected in the Find More sheet. Only scanned when user taps Scan.
    @Published var findMoreStartYear: Int = Calendar.current.component(.year, from: Date())
    @Published var findMoreStartMonth: Int = Calendar.current.component(.month, from: Date())
    @Published var findMoreEndYear: Int = Calendar.current.component(.year, from: Date())
    @Published var findMoreEndMonth: Int = Calendar.current.component(.month, from: Date())
    /// Tracks whether the Find More sheet has been opened at least once this session.
    /// Stays `false` until after the first open; reset only happens on first open (cold start).
    private var hasOpenedFindMoreSheet: Bool = false

    private let photoLibraryService = PhotoLibraryTripService.shared
    private let mockService = MockTripDataService.shared
    private let createdRecapStore: CreatedRecapBlogStore
    private var cancellables = Set<AnyCancellable>()

    /// Draft trips that have not yet been turned into a created recap blog. Use this for the Trips list.
    /// Created blogs never appear here, even after scanning for more trips.
    var visibleDraftTrips: [TripDraft] {
        tripDrafts.filter { !createdRecapStore.hasCreatedBlog(sourceTripId: $0.id) }
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
            findMoreEndYear = year
            findMoreEndMonth = month
            hasOpenedFindMoreSheet = true
        }
        showFindMoreSheet = true
    }

    /// Called by the UI when the user changes Start month/year. If Start is after End in the same year,
    /// auto-clamps End month up to Start month.
    func onStartSelectionChanged() {
        if findMoreStartYear == findMoreEndYear && findMoreStartMonth > findMoreEndMonth {
            findMoreEndMonth = findMoreStartMonth
        }
    }

    /// Called by the UI when the user changes End month/year. If End year is before Start year,
    /// auto-clamps Start year to match End year. If same year and End month is before Start month,
    /// auto-clamps Start month down to End month.
    func onEndSelectionChanged() {
        if findMoreEndYear < findMoreStartYear {
            findMoreStartYear = findMoreEndYear
        }
        if findMoreEndYear == findMoreStartYear && findMoreEndMonth < findMoreStartMonth {
            findMoreStartMonth = findMoreEndMonth
        }
    }

    /// Scan for trips in the selected start/end year+month range. Dedupes against existing list.
    func scanFindMoreTripsInRange() {
        guard !isFindMoreScanning else { return }
        isFindMoreScanning = true
        findMoreScanResult = .none
        let startYear = findMoreStartYear
        let startMonth = findMoreStartMonth
        let endYear = findMoreEndYear
        let endMonth = findMoreEndMonth
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        Task {
            // Clear "Ready to Start" trips (previous scan results), keeping only My Drafts
            let myDraftIds = TripDraftStore.draftTripIds()
            tripDrafts = tripDrafts.filter { myDraftIds.contains($0.id) }

            let newTrips = await photoLibraryService.scanInDateRange(
                startYear: startYear, startMonth: startMonth,
                endYear: endYear, endMonth: endMonth,
                occupiedDateRanges: occupiedRanges
            )
            let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })
            let deduped = newTrips.filter { !existingKeys.contains("\($0.title)|\($0.dateRangeText)") }
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

    func dismissFindMoreSheet() {
        showFindMoreSheet = false
        findMoreScanResult = .none
    }
}
