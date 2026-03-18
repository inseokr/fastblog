//
//  GoogleAuthManager.swift
//  fastblog
//
//  Google OAuth sign-in. Add the GoogleSignIn Swift package and set GIDClientID in Info.plist.
//

import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()

    #if canImport(GoogleSignIn)
    @Published private(set) var currentUser: GIDGoogleUser?
    #else
    @Published private(set) var currentUser: (any Any)? = nil
    #endif
    @Published private(set) var signInError: Error?

    var isSignedIn: Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.currentUser != nil
        #else
        return false
        #endif
    }

    private init() {
        #if canImport(GoogleSignIn)
        configureIfNeeded()
        #endif
    }

    #if canImport(GoogleSignIn)
    private func configureIfNeeded() {
        guard GIDSignIn.sharedInstance.configuration == nil else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.hasPrefix("YOUR_") else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// Call at app launch to restore a previous sign-in session.
    func restorePreviousSignIn() {
        configureIfNeeded()
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                self?.currentUser = user
                self?.signInError = error
            }
        }
    }

    /// Start the Google sign-in flow. Pass the window's root view controller for presentation.
    /// - Parameter completion: Called with the signed-in user on success, or an error on failure. Optional for backward compatibility.
    func signIn(presenting: UIViewController?, completion: ((Result<GIDGoogleUser, Error>) -> Void)? = nil) {
        signInError = nil
        configureIfNeeded()
        let presentingVC = presenting ?? rootViewController()
        guard let presentingVC else {
            let err = NSError(domain: "GoogleAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No view controller to present from"])
            signInError = err
            completion?(.failure(err))
            return
        }
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC) { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    self?.signInError = error
                    completion?(.failure(error))
                } else if let user = result?.user {
                    self?.currentUser = user
                    self?.signInError = nil
                    completion?(.success(user))
                } else {
                    let err = NSError(domain: "GoogleAuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Sign-in completed with no user"])
                    self?.signInError = err
                    completion?(.failure(err))
                }
            }
        }
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        signInError = nil
        #endif
    }

    /// Handle the OAuth callback URL. Call from `.onOpenURL` in your App.
    static func handleURL(_ url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    private func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return nil }
        return window.rootViewController
    }
    #else
    func restorePreviousSignIn() {}
    func signIn(presenting: UIViewController?, completion: ((Result<Any, Error>) -> Void)? = nil) {
        let err = NSError(domain: "GoogleAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Add GoogleSignIn Swift package to enable sign-in"])
        signInError = err
        completion?(.failure(err))
    }
    func signOut() {}
    static func handleURL(_ url: URL) -> Bool { false }
    #endif
}
