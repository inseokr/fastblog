//
//  MyBlogsProfileViewModel.swift
//  Capper
//
//  Provides grouped and sorted country sections for the My Blogs profile. Uses store's
//  countrySummaries (country from blog.countryName; no reverse geocode on render).
//

import Combine
import Foundation
import SwiftUI

/// UI-facing section: one card per country with latest cover and last blog date.
struct CountrySection: Identifiable, Equatable, Hashable {
    let countryName: String
    let lastBlogDate: Date
    let latestCoverBlog: CreatedRecapBlog
    let blogs: [CreatedRecapBlog]
    var id: String { countryName }

    static func == (lhs: CountrySection, rhs: CountrySection) -> Bool {
        lhs.countryName == rhs.countryName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(countryName)
    }
}

@MainActor
final class MyBlogsProfileViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var unsavedTrips: [TripDraft] = []
    @Published var isScanning = false

    private let photoLibraryService = PhotoLibraryTripService.shared
    private let createdRecapStore = CreatedRecapBlogStore.shared
    private var cancellables = Set<AnyCancellable>()

    private static let dismissedTripsKey = "bloggo.dismissedUnsavedTrips"

    init() {
        observeStoreChanges()
    }

    /// Maps store summaries to CountrySection (call from view with store.countrySummaries so store updates drive UI).
    static func sections(from summaries: [CountryRecapSummary]) -> [CountrySection] {
        summaries.map { summary in
            CountrySection(
                countryName: summary.countryName,
                lastBlogDate: summary.mostRecentBlog.tripEndDate ?? summary.mostRecentBlog.tripStartDate ?? summary.mostRecentBlog.createdAt,
                latestCoverBlog: summary.mostRecentBlog,
                blogs: summary.blogs
            )
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filter sections by country name or blog title (real-time); empty search shows all.
    func filteredSections(from sections: [CountrySection]) -> [CountrySection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return sections }
        return sections.filter { section in
            section.countryName.lowercased().contains(query) ||
            section.blogs.contains(where: { $0.title.lowercased().contains(query) })
        }
    }

    // MARK: - Unsaved Trips Logic

    func loadUnsavedTrips() {
        guard !isScanning else { return }
        isScanning = true
        
        Task {
            // We pass an empty array of occupied ranges to get ALL detected trips in the last 90 days.
            // We then filter them ourselves using the strict matching service against the store.
            // This ensures we have the full context for matching (e.g. overlap checks).
            let result = await photoLibraryService.scanLast90Days(occupiedDateRanges: [])
            let detected = result.trips

            let dismissed = Self.loadDismissedKeys()
            let filtered = detected.filter { draft in
                !createdRecapStore.isDraftRedundantWithSavedBlogs(draft)
                && !dismissed.contains(Self.dismissKey(for: draft))
            }
            
            self.unsavedTrips = filtered.sorted { ($0.earliestDate ?? .distantPast) > ($1.earliestDate ?? .distantPast) }
            self.isScanning = false
        }
    }

    private func observeStoreChanges() {
        createdRecapStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshUnsavedTrips()
            }
            .store(in: &cancellables)
    }

    private func refreshUnsavedTrips() {
        // Simple re-filter without re-scanning if we already have the list.
        // If we don't have it, load it.
        if unsavedTrips.isEmpty && !isScanning {
            loadUnsavedTrips()
        } else {
            let dismissed = Self.loadDismissedKeys()
            unsavedTrips = unsavedTrips.filter { draft in
                !createdRecapStore.isDraftRedundantWithSavedBlogs(draft)
                && !dismissed.contains(Self.dismissKey(for: draft))
            }
        }
    }

    // MARK: - Dismissed trips persistence

    /// Dismiss all currently visible unsaved trips so they don't reappear.
    func dismissAllUnsavedTrips() {
        var dismissed = Self.loadDismissedKeys()
        for trip in unsavedTrips {
            dismissed.insert(Self.dismissKey(for: trip))
        }
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedTripsKey)
        unsavedTrips = []
    }

    /// Stable fingerprint for a trip based on its date range (survives re-scans).
    private static func dismissKey(for trip: TripDraft) -> String {
        let start = trip.earliestDate?.timeIntervalSince1970 ?? 0
        let end = trip.latestDate?.timeIntervalSince1970 ?? 0
        return "\(start)_\(end)"
    }

    private static func loadDismissedKeys() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: dismissedTripsKey) ?? []
        return Set(array)
    }
}
