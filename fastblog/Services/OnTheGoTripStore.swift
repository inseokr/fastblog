//
//  OnTheGoTripStore.swift
//  fastblog
//
//  Tracks the "on the go" blog state — a blog created from a currently ongoing trip.
//  When the user is still traveling and has already created a blog, this store
//  detects new moments (continuation trip drafts) and surfaces the popup.
//

import Foundation

enum OnTheGoTripStore {
    private static let prefix = "blogify.onTheGo"
    private static let activeBlogIdKey       = "\(prefix).activeBlogId"
    private static let activeBlogTitleKey    = "\(prefix).activeBlogTitle"
    private static let tripEndDateKey        = "\(prefix).tripEndDate"
    private static let tripCountryKey        = "\(prefix).tripCountry"
    private static let hasNewMomentsKey      = "\(prefix).hasNewMoments"
    private static let newMomentsDayIndexKey = "\(prefix).newMomentsDayIndex"

    // MARK: - Read

    static var activeBlogId: UUID? {
        guard let s = UserDefaults.standard.string(forKey: activeBlogIdKey) else { return nil }
        return UUID(uuidString: s)
    }

    static var activeBlogTitle: String? {
        UserDefaults.standard.string(forKey: activeBlogTitleKey)
    }

    static var tripEndDate: Date? {
        UserDefaults.standard.object(forKey: tripEndDateKey) as? Date
    }

    static var tripCountry: String? {
        UserDefaults.standard.string(forKey: tripCountryKey)
    }

    static var hasNewMoments: Bool {
        UserDefaults.standard.bool(forKey: hasNewMomentsKey)
    }

    /// The 0-based day index inside the blog to scroll to when showing new moments.
    static var newMomentsDayIndex: Int? {
        guard UserDefaults.standard.object(forKey: newMomentsDayIndexKey) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: newMomentsDayIndexKey)
    }

    // MARK: - Write

    /// Call when a blog is created and the trip's end date is recent (still travelling).
    static func markTripAsActive(blogId: UUID, title: String, tripEndDate: Date, country: String?) {
        UserDefaults.standard.set(blogId.uuidString, forKey: activeBlogIdKey)
        UserDefaults.standard.set(title, forKey: activeBlogTitleKey)
        UserDefaults.standard.set(tripEndDate, forKey: tripEndDateKey)
        UserDefaults.standard.set(country, forKey: tripCountryKey)
        clearNewMoments()
    }

    /// Explicitly end tracking (trip finished or user dismissed for too long).
    static func markTripAsEnded() {
        UserDefaults.standard.removeObject(forKey: activeBlogIdKey)
        UserDefaults.standard.removeObject(forKey: activeBlogTitleKey)
        UserDefaults.standard.removeObject(forKey: tripEndDateKey)
        UserDefaults.standard.removeObject(forKey: tripCountryKey)
        clearNewMoments()
    }

    /// Call when a scan detects continuation photos for the active blog.
    /// `dayIndex` is the 0-based index of the latest day in the blog to highlight.
    static func signalNewMoments(dayIndex: Int) {
        UserDefaults.standard.set(true, forKey: hasNewMomentsKey)
        UserDefaults.standard.set(dayIndex, forKey: newMomentsDayIndexKey)
    }

    /// Clear the new-moments notification after the user sees the popup.
    static func clearNewMoments() {
        UserDefaults.standard.set(false, forKey: hasNewMomentsKey)
        UserDefaults.standard.removeObject(forKey: newMomentsDayIndexKey)
    }

    // MARK: - Helpers

    /// Returns true while the active trip is still considered ongoing.
    /// A trip is ongoing if its end date is within `maxDays` days from today.
    static func isTripStillOngoing(maxDays: Int = 14) -> Bool {
        guard let endDate = tripEndDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: endDate, to: Date()).day ?? Int.max
        return days <= maxDays
    }
}
