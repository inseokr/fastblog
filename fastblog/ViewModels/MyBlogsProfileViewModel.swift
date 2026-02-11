//
//  MyBlogsProfileViewModel.swift
//  Capper
//
//  Provides grouped and sorted country sections for the My Blogs profile. Uses store's
//  countrySummaries (country from blog.countryName; no reverse geocode on render).
//

import Combine
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

    init() {}

    /// Maps store summaries to CountrySection (call from view with store.countrySummaries so store updates drive UI).
    static func sections(from summaries: [CountryRecapSummary]) -> [CountrySection] {
        summaries.map { summary in
            CountrySection(
                countryName: summary.countryName,
                lastBlogDate: summary.mostRecentBlog.createdAt,
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
}
