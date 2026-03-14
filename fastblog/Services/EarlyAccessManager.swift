//
//  EarlyAccessManager.swift
//  fastblog
//
//  Manages early-access waitlist registration.
//  Calls the backend API to register the signed-in user and tracks
//  local registration state in UserDefaults.
//

import Foundation

@MainActor
final class EarlyAccessManager {
    static let shared = EarlyAccessManager()

    private let hasRegisteredKey = "bloggo.earlyAccess.hasRegistered"

    private init() {}

    /// Whether this device has already successfully registered for the waitlist.
    var hasRegistered: Bool {
        UserDefaults.standard.bool(forKey: hasRegisteredKey)
    }

    /// Updates local waitlist state from the current user level (e.g. after login or refresh).
    /// Premium/influencer users are treated as past the waitlist.
    func syncFromUserLevel(_ level: UserLevel) {
        if level.isPremiumOrAbove {
            UserDefaults.standard.set(true, forKey: hasRegisteredKey)
        }
    }

    /// Registers the current signed-in user on the waitlist via the backend API.
    /// Safe to call multiple times — skips if already registered locally.
    func registerWaitlist() async {
        guard !hasRegistered else { return }
        let user = AuthService.shared.currentUser
        let userName = user?.username ?? user?.displayName ?? user?.email ?? ""
        let email = user?.email ?? ""
        do {
            try await APIManager.shared.registerWaitlist(userName: userName, email: email)
            UserDefaults.standard.set(true, forKey: hasRegisteredKey)
        } catch {
            print("⚠️ EarlyAccessManager: waitlist registration failed – \(error.localizedDescription)")
        }
    }
}
