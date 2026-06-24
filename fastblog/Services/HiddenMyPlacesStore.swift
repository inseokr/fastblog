//
//  HiddenMyPlacesStore.swift
//  fastblog
//
//  Persists place IDs the user has hidden from My Places (restorable anytime).
//

import Combine
import Foundation

@MainActor
final class HiddenMyPlacesStore: ObservableObject {
    static let shared = HiddenMyPlacesStore()

    @Published private(set) var hiddenPlaceIds: Set<String> = []

    private static let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MyPlaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let stateURL = storageDirectory.appendingPathComponent("hiddenPlaceIds.json")

    private struct PersistedState: Codable {
        var placeIds: [String]
    }

    private init() {
        loadFromDisk()
    }

    var hiddenCount: Int { hiddenPlaceIds.count }

    func isHidden(_ placeId: String) -> Bool {
        hiddenPlaceIds.contains(placeId)
    }

    func hide(placeIds: Set<String>) {
        let added = placeIds.subtracting(hiddenPlaceIds)
        guard !added.isEmpty else { return }
        hiddenPlaceIds.formUnion(added)
        persist()
        AppAnalytics.shared.trackEvent(
            name: "my_places_hidden",
            properties: ["count": added.count]
        )
    }

    func unhide(placeId: String) {
        guard hiddenPlaceIds.remove(placeId) != nil else { return }
        persist()
    }

    func unhide(placeIds: Set<String>) {
        let removed = placeIds.intersection(hiddenPlaceIds)
        guard !removed.isEmpty else { return }
        hiddenPlaceIds.subtract(removed)
        persist()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        hiddenPlaceIds = Set(state.placeIds)
    }

    private func persist() {
        let state = PersistedState(placeIds: Array(hiddenPlaceIds))
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
}
