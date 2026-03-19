import Foundation

/// Generates and persists a UUID-based anonymous device identifier.
/// This ID is stable across sessions and survives app restarts.
/// When the user authenticates, their account userId is set separately
/// in AppAnalytics so events can be attributed to a real account.
final class AnalyticsIdentity {
    static let shared = AnalyticsIdentity()

    private let udKey = "bloggo.analytics.anonymousId"

    /// Stable anonymous ID, created once on first launch.
    let anonymousId: String

    private init() {
        if let existing = UserDefaults.standard.string(forKey: "bloggo.analytics.anonymousId"),
           !existing.isEmpty {
            anonymousId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "bloggo.analytics.anonymousId")
            anonymousId = newId
        }
    }
}
