//
//  NewMomentsPullUpPresentationStore.swift
//  fastblog
//
//  Remembers when the user dismissed the new-moments review prompt (Later, swipe, or scrim)
//  so we do not auto-present it again for the same photo batch. A newer batch shows again.
//

import Foundation

enum NewMomentsPullUpPresentationStore {
    private static let prefix = "blogify.newMomentsPullUp.dismissedBatchMax"

    private static func key(for blogSourceTripId: UUID) -> String {
        "\(prefix).\(blogSourceTripId.uuidString)"
    }

    /// Latest max photo timestamp for a batch the user dismissed without adding via the pull-up.
    static func dismissedBatchMaxTimestamp(for blogSourceTripId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: key(for: blogSourceTripId)) as? Date
    }

    static func recordDismissal(for blogSourceTripId: UUID, batchMaxPhotoDate: Date) {
        UserDefaults.standard.set(batchMaxPhotoDate, forKey: key(for: blogSourceTripId))
    }

    static func clear(for blogSourceTripId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: blogSourceTripId))
    }
}
