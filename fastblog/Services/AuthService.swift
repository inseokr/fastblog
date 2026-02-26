//
//  AuthService.swift
//  Capper
//
//  Handles Sign In with Apple and Email OTP authentication.
//  Google Sign-In: UI wired but requires GoogleSignIn SDK (SPM) to fully activate.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import SwiftUI

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case invalidEmail
    case otpExpired
    case otpInvalid
    case networkError(String)
    case appleSignInFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidEmail:         return "Please enter a valid email address."
        case .otpExpired:           return "The code has expired. Please request a new one."
        case .otpInvalid:           return "That code doesn't match. Please try again."
        case .networkError(let m):  return "Network error: \(m)"
        case .appleSignInFailed(let m): return "Apple Sign In failed: \(m)"
        case .cancelled:            return "Sign in was cancelled."
        }
    }
}

// MARK: - AuthService

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    // MARK: Published State
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var isSignedIn: Bool { currentUser != nil }

    // MARK: Private
    private let userDefaultsKey = "bloggo.authUser.v1"

    // For Apple Sign In nonce verification
    private var currentNonce: String?

    // Email stored so it can be passed to the verify endpoint
    private var pendingEmail: String?
    
    // MARK: - JWT Storage
    private let keychainService = "com.capper.auth"
    private let keychainAccount = "jwtToken"
    
    nonisolated var currentJwtToken: String? {
        KeychainHelper.shared.read(service: keychainService, account: keychainAccount)
    }

    private func setJwtToken(_ token: String?) {
        if let token {
            KeychainHelper.shared.save(token, service: keychainService, account: keychainAccount)
        } else {
            KeychainHelper.shared.delete(service: keychainService, account: keychainAccount)
        }
    }

    /// Base URL of the deployed Cloudflare Worker.
    /// Update this once after running `wrangler deploy`.
    private let otpWorkerBase = "https://bloggo-otp-worker.<YOUR_SUBDOMAIN>.workers.dev"

    // MARK: - Init

    private override init() {
        super.init()
        loadPersistedUser()
    }

    // MARK: - Persistence

    private func loadPersistedUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else { return }
        currentUser = user
    }

    private func persist(_ user: AuthUser?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    // MARK: - Per-User Profile Photo

    /// UserDefaults key scoped to the current user's ID so each account has its own photo.
    private var profilePhotoKey: String {
        guard let id = currentUser?.id else { return "profilePhoto.anonymous" }
        return "profilePhoto.\(id)"
    }

    /// Reads or writes the locally-stored profile photo for the currently signed-in user.
    var profileImageData: Data? {
        get { UserDefaults.standard.data(forKey: profilePhotoKey) }
        set {
            if let data = newValue {
                UserDefaults.standard.set(data, forKey: profilePhotoKey)
            } else {
                UserDefaults.standard.removeObject(forKey: profilePhotoKey)
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        currentUser = nil
        persist(nil)
        setJwtToken(nil)
        Analytics.track(.authCancelled) // reuse existing or add dedicated event
    }

    // MARK: - Delete Account

    /// Deletes the user account from the backend (initiating a 30-day soft delete purge period)
    /// and clears all local account data.
    func deleteAccount() async {
        struct BasicResponse: Decodable { let result: String? }
        if let username = currentUser?.username {
            let requestData = ["username": username]
            do {
                if let body = try? JSONEncoder().encode(requestData) {
                    let _: BasicResponse = try await APIManager.shared.request(
                        endpoint: "/user/delete",
                        method: "POST",
                        body: body,
                        requiresAuth: true
                    )
                }
            } catch {
                print("Failed to notify backend about account deletion: \(error)")
            }
        }

        await MainActor.run {
            // --- Preserve Onboarding/Neighborhood Data ---
            let defaults = UserDefaults.standard
            let hasCompletedOnboarding = defaults.bool(forKey: "blogify.hasCompletedOnboarding")
            let hasCheckedExistingUser = defaults.bool(forKey: "blogify.hasCheckedExistingUser")
            let nLat = defaults.object(forKey: "blogify.neighborhoodLat")
            let nLon = defaults.object(forKey: "blogify.neighborhoodLon")
            let nRadius = defaults.object(forKey: "blogify.neighborhoodRadiusMiles")
            let nDisplayName = defaults.string(forKey: "blogify.neighborhoodDisplayName")
            let nRecentSearches = defaults.stringArray(forKey: "blogify.neighborhood.recentSearches")

            // Clear profile photo for this user
            defaults.removeObject(forKey: profilePhotoKey)
            // Clear all app-local data from UserDefaults
            if let bundleId = Bundle.main.bundleIdentifier {
                defaults.removePersistentDomain(forName: bundleId)
            }

            // --- Restore Onboarding/Neighborhood Data ---
            defaults.set(hasCompletedOnboarding, forKey: "blogify.hasCompletedOnboarding")
            defaults.set(hasCheckedExistingUser, forKey: "blogify.hasCheckedExistingUser")
            if let nLat { defaults.set(nLat, forKey: "blogify.neighborhoodLat") }
            if let nLon { defaults.set(nLon, forKey: "blogify.neighborhoodLon") }
            if let nRadius { defaults.set(nRadius, forKey: "blogify.neighborhoodRadiusMiles") }
            if let nDisplayName { defaults.set(nDisplayName, forKey: "blogify.neighborhoodDisplayName") }
            if let nRecentSearches { defaults.set(nRecentSearches, forKey: "blogify.neighborhood.recentSearches") }

            // Clear auth credentials
            persist(nil)
            setJwtToken(nil)
            currentUser = nil
        }
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                Analytics.track(.authCancelled)
            } else {
                errorMessage = AuthError.appleSignInFailed(error.localizedDescription).errorDescription
                Analytics.track(.authFailed(reason: error.localizedDescription))
            }
            isLoading = false

        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = AuthError.appleSignInFailed("Unexpected credential type.").errorDescription
                isLoading = false
                return
            }
            let name: String? = {
                guard let full = cred.fullName else { return nil }
                return [full.givenName, full.familyName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .nonEmpty
            }()
            let user = AuthUser(
                id: cred.user,
                email: cred.email,
                displayName: name,
                username: nil,
                provider: .apple,
                storageUsedBytes: 0
            )
            finishSignIn(user: user)
        }
    }
}

// MARK: - Network Models

private struct SignupRequest: Encodable {
    let signupData: SignupData

    struct SignupData: Encodable {
        let username: String
        let email: String
        let password: String
        let userType: String
    }
}

private struct SignupResponse: Decodable {
    let result: String?
    let message: String?
    let status: String?   // some backends use "status" instead of "result"
}

private struct LoginRequest: Encodable {
    let username: String
    let password: String
}

private struct LoginResponse: Decodable {
    let message: String?
    let token: String?
    let user: UserPayload?
}

private struct UserPayload: Decodable {
    let _id: String?
    let email: String?
    let username: String?
    let name: String?
    let storageUsedBytes: Int64?
}

private struct UsernameCheckResponse: Decodable {
    let available: Bool?
    let message: String?
}

extension AuthService {
    
    func checkUsernameAvailability(username: String) async throws -> Bool {
        // Ideally pass via query parameter or post body depending on API standard
        // Defaulting to GET with query param
        struct EmptyResponse: Decodable {}
        
        let endpoint = "/user/availability?username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)"
        
        // As we don't know the exact response format, if it returns 200 it might be available
        // Or it returns a JSON { "available": true }
        do {
            let _: EmptyResponse = try await APIManager.shared.get(endpoint: endpoint, requiresAuth: false)
            return true
        } catch APIError.httpError(let statusCode, let message) {
            if statusCode == 409 || message.lowercased().contains("taken") {
                return false
            }
            throw APIError.httpError(statusCode: statusCode, message: message)
        }
    }
    
    func signup(username: String, email: String, password: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        Analytics.track(.authProviderSelected(provider: "email_signup"))
        
        let payload = SignupRequest(signupData: .init(
            username: username,
            email: email,
            password: password,
            userType: "bloggo"
        ))

        let response: SignupResponse = try await APIManager.shared.post(
            endpoint: "/signup/mobile/local",
            body: payload,
            requiresAuth: false
        )
        
        // Accept any of the common success signals different backends use.
        // Debug: print the actual value so mismatches are easy to spot.
        let resultValue = response.result ?? response.status ?? response.message ?? "(nil)"
        print("📋 Signup response — result: \(resultValue)")

        let isSuccess = ["success", "ok", "created"].contains(resultValue.lowercased())
        if isSuccess || response.result == nil && response.message == nil {
            // Immediate Login (Hydration)
            try await login(email: username, password: password)
        } else {
            throw AuthError.networkError("Signup failed (server said: \(resultValue)).")
        }
    }

    func login(email: String, password: String) async throws {
        let isUsername = !email.contains("@")
        if !isUsername {
            guard isValidEmail(email) else { throw AuthError.invalidEmail }
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        Analytics.track(.authProviderSelected(provider: "email_login"))
        
        let payload = LoginRequest(username: email, password: password)
        let response: LoginResponse = try await APIManager.shared.post(
            endpoint: "/jwt_login_v1",
            body: payload,
            requiresAuth: false
        )
        
        guard response.message == "ok", let token = response.token else {
            throw AuthError.networkError("Login failed or invalid credentials.")
        }
        
        // Hydrate Global State
        setJwtToken(token)
        
        let actualEmail = response.user?.email ?? (isUsername ? "\(email)@example.com" : email)
        let actualDisplayName = response.user?.name ?? response.user?.username ?? (isUsername ? email : nil)
        let actualId = response.user?._id ?? "email-\(UUID().uuidString)"
        
        let user = AuthUser(
            id: actualId,
            email: actualEmail,
            displayName: actualDisplayName,
            username: response.user?.username,
            provider: .email,
            storageUsedBytes: response.user?.storageUsedBytes ?? 0
        )
        finishSignIn(user: user)
    }

    // MARK: - Storage Tracking

    func incrementStorageUsed(by bytes: Int64) {
        // If not initialized, assume we start from 0 for local usage
        let currentUsage = currentUser?.storageUsedBytes ?? 0
        currentUser?.storageUsedBytes = currentUsage + bytes
        persist(currentUser)
        
        // Let the general entitlements manager know as well for broad access
        EntitlementManager.shared.updateUsedBytes(currentUser?.storageUsedBytes ?? 0)
    }

    // MARK: - Helpers

    /// Checks the Worker HTTP response and throws a typed `AuthError` on failure.
    private func validateWorkerResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Try to decode a worker error message
            struct WorkerError: Decodable {
                let error: String?
                let expired: Bool?
            }
            if let body = try? JSONDecoder().decode(WorkerError.self, from: data) {
                if body.expired == true { throw AuthError.otpExpired }
                if http.statusCode == 401 { throw AuthError.otpInvalid }
                throw AuthError.networkError(body.error ?? "Unknown error (\(http.statusCode)).")
            }
            throw AuthError.networkError("Server error (\(http.statusCode)).")
        }
    }

    private func finishSignIn(user: AuthUser) {
        currentUser = user
        persist(user)
        isLoading = false
        Analytics.track(.authSuccess)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }

    // MARK: - Analytics
    
    enum Analytics {
        enum Event {
            case authCreateAccountTapped
            case authProviderSelected(provider: String)
            case authSuccess
            case authCancelled
            case authFailed(reason: String)
        }

        static func track(_ event: Event) {
            // Wire to your analytics SDK here.
            #if DEBUG
            switch event {
            case .authCreateAccountTapped:
                print("📊 auth_create_account_tapped")
            case .authProviderSelected(let p):
                print("📊 auth_provider_selected: \(p)")
            case .authSuccess:
                print("📊 auth_success")
            case .authCancelled:
                print("📊 auth_cancelled")
            case .authFailed(let r):
                print("📊 auth_failed: \(r)")
            }
            #endif
        }
    }
}

// MARK: - String Helper

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
