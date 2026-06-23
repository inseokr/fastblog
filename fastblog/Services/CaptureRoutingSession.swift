//
//  CaptureRoutingSession.swift
//  fastblog
//
//  Camera-scoped routing state: everyday moments vs trip blog.
//

import Foundation

enum CaptureRoutingMode: Equatable {
    case everyday
    case tripBlog(UUID)
}

/// User-selected camera destination: everyday moments (My Places) vs trip blogs.
enum CaptureDestinationMode: String, CaseIterable {
    case daily
    case trips

    var iconName: String {
        switch self {
        case .daily: return "house.fill"
        case .trips: return "suitcase.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .daily: return "Daily mode, saves near home to My Places"
        case .trips: return "Trip mode, starts blogs when you travel"
        }
    }

    var toggled: CaptureDestinationMode {
        self == .daily ? .trips : .daily
    }
}

/// Tracks per-outing capture routing (resets after 24h gap).
@MainActor
final class CaptureRoutingSession: ObservableObject {
    static let outingGapSeconds: TimeInterval = 86_400

    @Published private(set) var mode: CaptureRoutingMode = .everyday
    @Published private(set) var declinedBlogPromptThisOuting = false
    @Published private(set) var showedTripPromptThisOuting = false
    @Published private(set) var showedNearHomeBlogModePromptThisOuting = false

    private static let nearHomeAlertSuppressedKey = "bloggo.nearHomeAlertSuppressed"

    private var lastCaptureDate: Date?
    private var lastPromptLocation: PhotoCoordinate?

    func resetOutingIfNeeded(for captureDate: Date) {
        if let last = lastCaptureDate,
           captureDate.timeIntervalSince(last) > Self.outingGapSeconds {
            startNewOuting()
        }
        lastCaptureDate = captureDate
    }

    func startNewOuting() {
        mode = .everyday
        declinedBlogPromptThisOuting = false
        showedTripPromptThisOuting = false
        showedNearHomeBlogModePromptThisOuting = false
        lastPromptLocation = nil
    }

    func markDeclinedBlogPrompt() {
        declinedBlogPromptThisOuting = true
        showedTripPromptThisOuting = true
        mode = .everyday
    }

    func markAcceptedTripBlog(blogId: UUID) {
        mode = .tripBlog(blogId)
        showedTripPromptThisOuting = true
        declinedBlogPromptThisOuting = false
    }

    func setTripBlogIfActive(_ blogId: UUID) {
        mode = .tripBlog(blogId)
    }

    /// Whether to show the trip blog prompt. Near home is allowed when Trip mode is on.
    func shouldShowTripPrompt(isNearHome: Bool, isTripsMode: Bool = false, location: PhotoCoordinate?) -> Bool {
        if isNearHome && !isTripsMode { return false }
        if case .tripBlog = mode { return false }
        if declinedBlogPromptThisOuting { return false }
        if showedTripPromptThisOuting { return false }
        if let loc = location, let last = lastPromptLocation {
            let dist = haversineMeters(lat1: last.latitude, lon1: last.longitude, lat2: loc.latitude, lon2: loc.longitude)
            if dist < 500 { return false }
        }
        return true
    }

    func recordTripPromptShown(at location: PhotoCoordinate?) {
        showedTripPromptThisOuting = true
        lastPromptLocation = location
    }

    /// First near-home capture while Trip mode is on — offer to switch to Daily (My Places).
    func shouldShowNearHomeBlogModePrompt(isTripsMode: Bool) -> Bool {
        guard isTripsMode else { return false }
        if showedNearHomeBlogModePromptThisOuting { return false }
        if UserDefaults.standard.bool(forKey: Self.nearHomeAlertSuppressedKey) { return false }
        return true
    }

    func markNearHomeBlogModePromptShown() {
        showedNearHomeBlogModePromptThisOuting = true
    }

    var isEverydayMode: Bool {
        if case .everyday = mode { return true }
        return false
    }

    var activeTripBlogId: UUID? {
        if case .tripBlog(let id) = mode { return id }
        return nil
    }

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
