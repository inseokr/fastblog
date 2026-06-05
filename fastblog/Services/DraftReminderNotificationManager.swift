//
//  DraftReminderNotificationManager.swift
//  Capper
//

import UIKit
import UserNotifications

enum DraftReminderNotificationManager {
    private static let categoryIdentifier = "DRAFT_REMINDER"
    static let pendingDeviceTokenKey = "bloggo.pendingDeviceToken"
    /// True when the user allowed notifications before having a JWT (e.g. system prompt during onboarding).
    private static let notificationsGrantedPreLoginKey = "bloggo.notificationsGrantedPreLogin"
    /// True when the user ticked "Do not show this again" on the push-permission prompt.
    static let doNotShowPushPromptKey = "bloggo.pushPermission.doNotShowAgain"

    /// Call when notification permission is granted while logged out (e.g. onboarding). Ensures post-login registration runs.
    static func recordPreLoginNotificationPermissionGrant() {
        Task { @MainActor in
            guard AuthService.shared.currentJwtToken == nil else { return }
            UserDefaults.standard.set(true, forKey: notificationsGrantedPreLoginKey)
        }
    }

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        recordPreLoginNotificationPermissionGrant()
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }

    /// Called after account creation / login.
    /// - Registers the pending APNs token with the backend if permission is already granted.
    /// - Re-requests permission if it was never determined.
    /// - Returns `true` if permission is currently denied (so the caller can prompt the user to go to Settings).
    @discardableResult
    static func handlePostLoginSetup() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        print("[Push] handlePostLoginSetup — authorizationStatus: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            // User allowed notifications before login (onboarding) or earlier — register with APNs and flush token.
            UserDefaults.standard.removeObject(forKey: notificationsGrantedPreLoginKey)
            print("[Push] Permission already granted — calling registerForRemoteNotifications()")
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            if let token = UserDefaults.standard.string(forKey: pendingDeviceTokenKey) {
                print("[Push] Flushing pending device token to backend: \(token)")
                await APIManager.shared.registerDeviceToken(token)
            } else {
                print("[Push] No pending device token found in UserDefaults — APNs callback not yet received")
            }
            return false

        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: notificationsGrantedPreLoginKey)
            print("[Push] Permission not determined — deferring prompt until user opts in")
            return false

        default:
            UserDefaults.standard.removeObject(forKey: notificationsGrantedPreLoginKey)
            print("[Push] Permission denied — user should open Settings")
            // If the user previously opted out of this prompt, respect that choice.
            if UserDefaults.standard.bool(forKey: doNotShowPushPromptKey) {
                print("[Push] User opted out of push-permission re-prompt — skipping")
                return false
            }
            return true
        }
    }

    /// Schedules a local notification reminding the user to save their blog draft.
    static func scheduleDraftReminder(blogTitle: String) {
        let center = UNUserNotificationCenter.current()

        // Remove any existing draft reminders first
        center.removePendingNotificationRequests(withIdentifiers: [categoryIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Don't forget your draft!"
        content.body = "Your blog \"\(blogTitle)\" has unsaved changes. Open the app to save it as a draft."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        // Fire 10 minutes after leaving
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: categoryIdentifier, content: content, trigger: trigger)

        center.add(request)
    }

    /// Cancels any pending draft reminder (e.g. when user saves before the notification fires).
    static func cancelPendingReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [categoryIdentifier])
    }
}
