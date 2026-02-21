//
//  AuthStateManager.swift
//  Capper
//
//  Typed auth state machine derived from AuthService.
//  Drives UI section visibility and the anonymous-draft import flow.
//

import Combine
import Foundation
import SwiftUI

// MARK: - AuthState

/// The two possible states of the authentication machine.
enum AuthState: Equatable {
    case loggedOut
    case loggedIn(userId: String)
}

// MARK: - AuthStateManager

@MainActor
final class AuthStateManager: ObservableObject {
    static let shared = AuthStateManager()

    // MARK: Published

    @Published private(set) var authState: AuthState = .loggedOut

    /// Set to true when the import-drafts modal should be presented.
    @Published var showImportDraftsModal = false

    // MARK: Private

    /// Prevents the import prompt from appearing more than once per login session.
    private(set) var hasShownImportPromptThisSession = false

    /// Persisted across launches: true only when the user *explicitly* signed out.
    /// This ensures the import modal is never triggered by a silent launch restore.
    private let didSignOutKey = "bloggo.authState.didSignOut"
    private var didSignOutSinceLastSession: Bool {
        get { UserDefaults.standard.bool(forKey: didSignOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: didSignOutKey) }
    }

    private var previousState: AuthState = .loggedOut
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    private init() {
        // Derive auth state from AuthService's current user.
        AuthService.shared.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                let oldState = self.authState
                if let user {
                    self.authState = .loggedIn(userId: user.id)
                } else {
                    // Only mark as explicitly signed-out if we were previously signed in.
                    // (i.e. not the initial cold-start where previous state is also loggedOut)
                    if case .loggedIn = oldState {
                        self.didSignOutSinceLastSession = true
                    }
                    self.authState = .loggedOut
                    // Reset so the prompt can appear again on next login.
                    self.hasShownImportPromptThisSession = false
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Import Prompt

    /// Call after login completes. Shows the import modal exactly once per session
    /// **only if the user explicitly signed out** before signing back in.
    func checkAndPromptImportIfNeeded() {
        guard case .loggedIn = authState,
              !hasShownImportPromptThisSession,
              didSignOutSinceLastSession,                      // ← must have actually signed out
              !CreatedRecapBlogStore.shared.anonymousDrafts.isEmpty else { return }
        hasShownImportPromptThisSession = true
        didSignOutSinceLastSession = false                     // consume the flag
        showImportDraftsModal = true
    }

    // MARK: - Convenience

    var isLoggedIn: Bool {
        if case .loggedIn = authState { return true }
        return false
    }

    var currentUserId: String? {
        if case .loggedIn(let id) = authState { return id }
        return nil
    }
}
