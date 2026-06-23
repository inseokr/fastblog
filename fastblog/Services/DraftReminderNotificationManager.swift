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

    /// Presents the system notification permission dialog when status is not determined.
    @discardableResult
    static func requestAuthorizationFromUser() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                _ = await handlePostLoginSetup()
            }
            return granted
        case .authorized, .provisional, .ephemeral:
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            _ = await handlePostLoginSetup()
            return true
        default:
            return false
        }
    }

    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

    private static let everydayReturnIdentifier = "EVERYDAY_RETURN_REMINDER"
    private static let placesWeeklyDigestIdentifier = "PLACES_WEEKLY_DIGEST"

    /// Remind the user to return after capturing everyday moments (fires in 3 days).
    static func scheduleEverydayReturnReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [everydayReturnIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Your places are waiting"
        content.body = "Open Bloggo to revisit the moments you saved in My Places."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: everydayReturnIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Weekly digest when the user has recent places activity.
    static func schedulePlacesWeeklyDigestIfNeeded(placeCount: Int) {
        guard placeCount > 0 else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [placesWeeklyDigestIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Your week in My Places"
        let noun = placeCount == 1 ? "place" : "places"
        content.body = "You visited \(placeCount) \(noun) recently — see your week in My Places."
        content.sound = .default

        var date = DateComponents()
        date.weekday = 1
        date.hour = 18
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: placesWeeklyDigestIdentifier, content: content, trigger: trigger)
        center.add(request)
    }
}
