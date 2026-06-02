//
//  BlogMenuIndicatorStore.swift
//  fastblog
//
//  Tracks blogs that are new or have unseen new moments for My Blogs tab + list badges.
//

import Foundation
import Observation

@MainActor
@Observable
final class BlogMenuIndicatorStore {
    static let shared = BlogMenuIndicatorStore()

    enum Kind: String, Codable {
        case newBlog
        case newMoments
    }

    private(set) var indicators: [UUID: Kind] = [:]

    /// Blog currently open in the recap overlay — suppresses menu badges for in-session adds.
    var focusedBlogSourceTripId: UUID?

    private let storageKey = "blogify.blogMenu.indicators"

    private init() {
        load()
    }

    var hasAnyIndicator: Bool { !indicators.isEmpty }

    func kind(forSourceTripId id: UUID) -> Kind? {
        indicators[id]
    }

    func hasIndicator(forSourceTripId id: UUID) -> Bool {
        indicators[id] != nil
    }

    func sectionHasIndicator(blogs: [CreatedRecapBlog]) -> Bool {
        blogs.contains { hasIndicator(forSourceTripId: $0.sourceTripId) }
    }

    func signalNewBlog(sourceTripId: UUID) {
        guard indicators[sourceTripId] == nil else { return }
        indicators[sourceTripId] = .newBlog
        persist()
    }

    func signalNewMoments(sourceTripId: UUID) {
        indicators[sourceTripId] = .newMoments
        persist()
    }

    /// Call when photos were added to a blog (camera, scan inject, library new moments).
    func noteMomentsAdded(to sourceTripId: UUID) {
        guard focusedBlogSourceTripId != sourceTripId else { return }
        signalNewMoments(sourceTripId: sourceTripId)
    }

    func clear(sourceTripId: UUID) {
        guard indicators.removeValue(forKey: sourceTripId) != nil else { return }
        persist()
    }

    func pruneInvalidBlogs(validSourceTripIds: Set<UUID>) {
        let pruned = indicators.filter { validSourceTripIds.contains($0.key) }
        guard pruned.count != indicators.count else { return }
        indicators = pruned
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        var loaded: [UUID: Kind] = [:]
        for (key, raw) in decoded {
            guard let id = UUID(uuidString: key),
                  let kind = Kind(rawValue: raw) else { continue }
            loaded[id] = kind
        }
        indicators = loaded
    }

    private func persist() {
        let encoded = Dictionary(uniqueKeysWithValues: indicators.map { ($0.key.uuidString, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
}
