//
//  TripDraftStore.swift
//  Capper
//

import Combine
import Foundation

/// Persists photo selection per trip so "My Drafts" can restore selection when user returns.
enum TripDraftStore {
    private static let key = "blogify.tripDraftSelections"

    /// True if this trip has saved selection (user started selecting photos).
    static func hasDraft(tripId: UUID) -> Bool {
        guard let ids = selectedPhotoIds(tripId: tripId) else { return false }
        return !ids.isEmpty
    }

    /// Saved selected photo IDs for this trip. Nil if never saved.
    static func selectedPhotoIds(tripId: UUID) -> Set<UUID>? {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [[String: String]],
              let entry = raw.first(where: { $0["tripId"] == tripId.uuidString }),
              let list = entry["photoIds"]?.split(separator: ",").map(String.init) else {
            return nil
        }
        let uuids = list.compactMap { UUID(uuidString: $0) }
        return uuids.isEmpty ? nil : Set(uuids)
    }

    /// Persist selected photo IDs for this trip. Call when user leaves the picker with at least one selected.
    static func saveSelection(tripId: UUID, selectedPhotoIds: Set<UUID>) {
        var raw = (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? []
        raw.removeAll { $0["tripId"] == tripId.uuidString }
        if !selectedPhotoIds.isEmpty {
            raw.append([
                "tripId": tripId.uuidString,
                "photoIds": selectedPhotoIds.map(\.uuidString).joined(separator: ",")
            ])
        }
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// Remove saved selection (e.g. after user created the blog).
    static func clearSelection(tripId: UUID) {
        var raw = (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? []
        raw.removeAll { $0["tripId"] == tripId.uuidString }
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// All trip IDs that have a draft (saved selection).
    static func draftTripIds() -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [[String: String]] else { return [] }
        return Set(raw.compactMap { entry in
            guard let s = entry["tripId"], let id = UUID(uuidString: s) else { return nil }
            return id
        })
    }

    /// Returns a copy of the trip with isSelected set from saved selection. Use when opening a draft.
    static func applySavedSelection(to trip: TripDraft) -> TripDraft {
        guard let savedIds = selectedPhotoIds(tripId: trip.id) else { return trip }
        var out = trip
        out.days = trip.days.map { day in
            var d = day
            d.photos = day.photos.map { photo in
                var p = photo
                p.isSelected = savedIds.contains(photo.id)
                return p
            }
            return d
        }
        return out
    }
}
