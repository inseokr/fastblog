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

    /// Year and month range selected in the sheet. Only scan when user taps Scan Trips.
    @Published var findMoreYear: Int = Calendar.current.component(.year, from: Date())
    @Published var findMoreStartMonth: Int = 1
    @Published var findMoreEndMonth: Int = 12
    /// Cities visited in the selected year/month range (for "Cities Visited" section). Loaded when sheet opens or range changes.
    @Published var findMoreCities: [String] = []
    @Published var findMoreCitiesLoading: Bool = false

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
        updateOccupiedRanges()
    }

    func addDraft(_ draft: TripDraft) {
        tripDrafts.insert(draft, at: 0)
        updateOccupiedRanges()
    }

    func createDraft(from recall: RecallTrigger) -> TripDraft {
        createDraft(from: recall.assets, title: recall.title)
    }

    func createDraft(from reminder: SmartReminder) -> TripDraft {
        createDraft(from: reminder.assets, title: reminder.title)
    }

    private func createDraft(from assets: [PHAsset], title: String) -> TripDraft {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        let groups = Dictionary(grouping: assets) { asset in
            calendar.startOfDay(for: asset.creationDate ?? Date())
        }
        let sortedDates = groups.keys.sorted()
        
        var tripDays: [TripDay] = []
        for (index, date) in sortedDates.enumerated() {
            let dayAssets = (groups[date] ?? []).sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            let photos = dayAssets.map { asset in
                MockPhoto(
                    imageName: "photo",
                    timestamp: asset.creationDate ?? Date(),
                    isSelected: false,
                    localIdentifier: asset.localIdentifier
                )
            }
            tripDays.append(TripDay(
                dayIndex: index + 1,
                dateText: formatter.string(from: date),
                photos: photos
            ))
        }
        
        let firstDate = sortedDates.first ?? Date()
        let lastDate = sortedDates.last ?? Date()
        let dateRange = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
        
        return TripDraft(
            title: title,
            dateRangeText: dateRange,
            days: tripDays,
            coverImageName: "default",
            isScannedFromDefaultRange: false,
            coverAssetIdentifier: assets.first?.localIdentifier
        )
    }

    private func updateOccupiedRanges() {
        let ranges = tripDrafts.compactMap { draft -> (start: Date, end: Date)? in
            guard let start = draft.earliestDate, let end = draft.latestDate else { return nil }
            return (start, end)
        }
        CreatedRecapBlogStore.shared.draftOccupiedRanges = ranges
    }

    init(createdRecapStore: CreatedRecapBlogStore) {
        self.createdRecapStore = createdRecapStore
        createdRecapStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        createdRecapStore.$needsRescan
            .receive(on: RunLoop.main)
            .filter { $0 }
            .sink { [weak self] (_: Bool) in
                guard let self else { return }
                createdRecapStore.needsRescan = false
                self.tripDrafts = []
                self.startDefaultScan()
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        guard scanState == .idle, tripDrafts.isEmpty else { return }
        openFindMoreSheet()
    }

    /// Runs the default scan for the last N days (ScanConfig.windowDays). Used when no timeline selection is shown.
    func startDefaultScan() {
        showSelectPhotosIntroAfterScan = true
        scanState = .scanningDefault
        loadingMessage = "Scanning your photos…"
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        Task {
            let trips = await photoLibraryService.scanLast3Months(occupiedDateRanges: occupiedRanges)
            tripDrafts = trips
            updateOccupiedRanges()
            scanState = .idle
        }
    }

    /// Opens the Find More Trips sheet. Defaults to last 2 months (reduces geocoding rate limit usage). Does not scan.
    func openFindMoreSheet() {
        findMoreScanResult = .none
        let now = Date()
        let cal = Calendar.current
        findMoreYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        findMoreStartMonth = max(1, currentMonth - 1)
        findMoreEndMonth = currentMonth
        showFindMoreSheet = true
    }

    /// Loads cities visited in the selected year/month range (for "Cities Visited" section). Call when sheet opens or when year/start/end month changes.
    func loadFindMoreCities() {
        findMoreCitiesLoading = true
        findMoreCities = []
        let year = findMoreYear
        let startMonth = min(findMoreStartMonth, findMoreEndMonth)
        let endMonth = max(findMoreStartMonth, findMoreEndMonth)
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        Task {
            let cities = await photoLibraryService.fetchCityNamesInRange(year: year, startMonth: startMonth, endMonth: endMonth, occupiedDateRanges: occupiedRanges)
            findMoreCities = cities
            findMoreCitiesLoading = false
        }
    }

    /// Scan for trips in the selected year/month range using the photo library. Dedupes against existing list. Updates tripDrafts and findMoreScanResult. Dismisses sheet on success.
    func scanFindMoreTripsInRange(query: String? = nil) {
        guard !isFindMoreScanning else { return }
        isFindMoreScanning = true
        findMoreScanResult = .none
        let year = findMoreYear
        let startMonth = min(findMoreStartMonth, findMoreEndMonth)
        let endMonth = max(findMoreStartMonth, findMoreEndMonth)
        let occupiedRanges = createdRecapStore.occupiedDateRanges()
        
        let searchQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        Task {
            // Clear "Ready to Start" trips (previous scan results), keeping only My Drafts
            let myDraftIds = TripDraftStore.draftTripIds()
            tripDrafts = tripDrafts.filter { myDraftIds.contains($0.id) }

            let newTrips = await photoLibraryService.scanInDateRange(year: year, startMonth: startMonth, endMonth: endMonth, occupiedDateRanges: occupiedRanges)
            let existingKeys = Set(tripDrafts.map { "\($0.title)|\($0.dateRangeText)" })
            
            var deduped = newTrips.filter { !existingKeys.contains("\($0.title)|\($0.dateRangeText)") }
            
            if let filter = searchQuery, !filter.isEmpty {
                deduped = deduped.filter { trip in
                    let titleMatch = trip.title.localizedCaseInsensitiveContains(filter)
                    let locationMatch = trip.days.contains { day in
                        (day.cityName?.localizedCaseInsensitiveContains(filter) ?? false) ||
                        (day.countryName?.localizedCaseInsensitiveContains(filter) ?? false)
                    }
                    return titleMatch || locationMatch
                }
            }
            
            if deduped.isEmpty {
                findMoreScanResult = .empty
            } else {
                withAnimation {
                    tripDrafts.append(contentsOf: deduped)
                    updateOccupiedRanges()
                }
                findMoreScanResult = .success(deduped.count)
                showSelectPhotosIntroAfterScan = true
            }
            loadFindMoreCities()
            isFindMoreScanning = false
        }
    }

    func dismissFindMoreSheet() {
        showFindMoreSheet = false
        findMoreScanResult = .none
        chatMessages = []
    }

    // MARK: - Find More Trips Agent

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isUser: Bool
        var suggestions: [String] = [] // Chips to show below message
    }

    @Published var chatMessages: [ChatMessage] = []
    @Published var isAgentScanning: Bool = false

    func submitChatMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // 1. User Message
        let userMsg = ChatMessage(text: text, isUser: true)
        chatMessages.append(userMsg)
        
        // 2. Process Intent
        let response = FindMoreTripsAgent.process(input: text)
        
        // 3. Execute Action
        switch response.action {
        case .search(let year, let start, let end, let location):
            findMoreYear = year
            findMoreStartMonth = start
            findMoreEndMonth = end
            // Trigger cities reload
            // loadFindMoreCities() is observing changes, so it triggers automatically
            
            let assistantMsg = ChatMessage(text: response.text, isUser: false)
            chatMessages.append(assistantMsg)
            
            if let loc = location {
                // If location is provided, automatically trigger scan with filter
                scanFindMoreTripsInRange(query: loc)
            }
            
        case .insight(let type):
            let assistantMsg = ChatMessage(text: response.text, isUser: false)
            chatMessages.append(assistantMsg)
            performInsightAnalysis(type: type)

        case .scanLibrary:
            performAgentScan()
            
        case .none:
            let assistantMsg = ChatMessage(text: response.text, isUser: false)
            chatMessages.append(assistantMsg)
        }
    }
    
    func performAgentScan() {
        guard !isAgentScanning else { return }
        isAgentScanning = true
        
        let loadingMsg = ChatMessage(text: "Scanning your library for trips...", isUser: false)
        chatMessages.append(loadingMsg)
        
        Task {
            let summary = await photoLibraryService.scanLibrarySummary()
            
            // Remove loading message logic could be complex with append, 
            // but for now we just append the result.
            // Ideally we'd replace the last message, but strictly appending is fine for MVP.
            
            var resultText = "Scan complete. You have \(summary.totalPhotos) photos."
            if !summary.mostActiveMonths.isEmpty {
                let months = summary.mostActiveMonths.map { "\($0.count) in \(DateFormatter().monthSymbols[$0.month-1]) \($0.year)" }.joined(separator: ", ")
                resultText += "\n\nMost active times: \(months)."
            }
            
            var chips: [String] = []
            for suggestion in summary.recentTripSuggestions {
                chips.append("Show trips from \(suggestion)")
            }
            // Add generic suggestions if empty
            if chips.isEmpty && !summary.prominentYears.isEmpty {
                chips.append("Show trips from \(summary.prominentYears[0])")
            }
            
            let resultMsg = ChatMessage(text: resultText, isUser: false, suggestions: chips)
            
            await MainActor.run {
                // simple dedupe if user spams check?
                chatMessages.append(resultMsg)
                isAgentScanning = false
            }
        }
    }

    func performInsightAnalysis(type: InsightType) {
        guard !isAgentScanning else { return }
        isAgentScanning = true
        
        Task {
            let summary = await photoLibraryService.scanLibrarySummary()
            let (resultText, year, start, end) = computeInsight(type: type, summary: summary)
            
            await MainActor.run {
                if let y = year, let s = start, let e = end {
                    self.findMoreYear = y
                    self.findMoreStartMonth = s
                    self.findMoreEndMonth = e
                    // Auto-load cities triggered by @Published
                }
                
                let msg = ChatMessage(text: resultText, isUser: false)
                self.chatMessages.append(msg)
                self.isAgentScanning = false
            }
        }
    }
    
    private func computeInsight(type: InsightType, summary: LibrarySummary) -> (text: String, year: Int?, start: Int?, end: Int?) {
        switch type {
        case .busiestSeason:
            // Sum counts by season
            var seasonCounts: [FindMoreTripsAgent.Season: Int] = [.spring: 0, .summer: 0, .fall: 0, .winter: 0]
            
            // We also want to know which Year was most active for that season to set the filter
            // Key: Season, Value: (Year, Count)
            var bestYearForSeason: [FindMoreTripsAgent.Season: (year: Int, count: Int)] = [:]
            
            for (key, count) in summary.monthCounts {
                let parts = key.split(separator: "-")
                guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { continue }
                
                let season = season(for: m)
                seasonCounts[season, default: 0] += count
                
                let currentMax = bestYearForSeason[season]?.count ?? -1
                // Approximate: we only have monthly data here, so we track "best month count in that season" as proxy for "best year"
                // Ideally we'd sum up the whole season for that year, but this is a decent heuristic for "find a good year"
                if count > currentMax {
                    bestYearForSeason[season] = (y, count)
                }
            }
            
            guard let topSeason = seasonCounts.max(by: { $0.value < $1.value })?.key else {
                return ("I couldn't find enough data to determine your busiest season.", nil, nil, nil)
            }
            
            let bestYear = bestYearForSeason[topSeason]?.year ?? Calendar.current.component(.year, from: Date())
            let totalPhotos = seasonCounts[topSeason] ?? 0
            
            return ("Your busiest season is \(topSeason.rawValue.capitalized) (approx. \(totalPhotos) photos). Showing trips from \(topSeason.rawValue) \(bestYear).", bestYear, topSeason.months.start, topSeason.months.end)
            
        case .bestTrip:
            // "Best" interpreted as most active single month
            guard let top = summary.mostActiveMonths.first else {
                return ("I couldn't find any significant trips in your library.", nil, nil, nil)
            }
            
            let monthName = DateFormatter().monthSymbols[top.month - 1]
            return ("Your most active time was \(monthName) \(top.year) with \(top.count) photos. Filtering for that active month.", top.year, top.month, top.month)
        }
    }
    
    private func season(for month: Int) -> FindMoreTripsAgent.Season {
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
        }
    }
}
