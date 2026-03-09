//
//  ScanSessionStore.swift
//  fastblog
//
//  Persists the last photo-scan date per user so the app can detect
//  new photos since the previous scan and offer incremental scanning.
//  "guest" is used as the user ID for unauthenticated sessions.
//

import Foundation

/// Stores the last successful scan timestamp keyed by user ID.
/// Survives app kill/relaunch via UserDefaults. Each user account
/// (and guest mode) has an independent entry.
enum ScanSessionStore {
    private static let keyPrefix = "blogify.scanSession.lastScannedDate"

    private static func key(for userId: String) -> String {
        "\(keyPrefix).\(userId)"
    }

    // MARK: - Read

    /// Returns the date of the last default scan for this user. Nil if never scanned.
    static func lastScannedDate(for userId: String) -> Date? {
        UserDefaults.standard.object(forKey: key(for: userId)) as? Date
    }

    // MARK: - Write

    /// Persists the scan timestamp for this user.
    static func saveLastScannedDate(_ date: Date, for userId: String) {
        UserDefaults.standard.set(date, forKey: key(for: userId))
    }

    /// Removes the stored scan date (e.g. on explicit logout or when forcing a full rescan).
    static func clearLastScannedDate(for userId: String) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }

    // MARK: - Per-Blog New-Moments Tracking

    private static let blogNotifiedKeyPrefix = "blogify.scanSession.blogNotified"

    private static func blogKey(for blogId: UUID) -> String {
        "\(blogNotifiedKeyPrefix).\(blogId.uuidString)"
    }

    /// Returns the date we last notified the user about new moments for `blogId`. Nil = never notified.
    static func lastBlogNotifiedDate(for blogId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: blogKey(for: blogId)) as? Date
    }

    /// Persists the notification timestamp for a blog so repeat alerts are suppressed.
    static func saveBlogNotifiedDate(_ date: Date, for blogId: UUID) {
        UserDefaults.standard.set(date, forKey: blogKey(for: blogId))
    }
}
