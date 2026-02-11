//
//  RecentRecapStore.swift
//  Capper
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class RecentRecapStore: ObservableObject {
    static let shared = RecentRecapStore()

    @Published private(set) var recents: [RecentRecap] = []
    private var tripDraftsByID: [UUID: TripDraft] = [:]
    private let maxRecents = 5

    private init() {}

    /// Call when user creates a blog from a trip (e.g. from TripDayPickerView Create Blog).
    func addRecent(trip: TripDraft) {
        let recap = RecentRecap(
            title: trip.title,
            createdAt: Date(),
            coverImageName: trip.coverImageName,
            tripId: trip.id,
            selectedPhotoCount: trip.selectedPhotoCount
        )
        tripDraftsByID[trip.id] = trip
        recents.insert(recap, at: 0)
        if recents.count > maxRecents {
            let removed = recents.removeLast()
            tripDraftsByID[removed.tripId] = nil
        }
    }

    /// TripDraft for opening BlogPreviewView. Nil if not found.
    func tripDraft(for id: UUID) -> TripDraft? {
        tripDraftsByID[id]
    }

    /// Up to 5 items for the landing section.
    var displayRecents: [RecentRecap] {
        Array(recents.prefix(maxRecents))
    }
}
