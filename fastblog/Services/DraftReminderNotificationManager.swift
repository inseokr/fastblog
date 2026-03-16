//
//  DraftReminderNotificationManager.swift
//  Capper
//

import UIKit
import UserNotifications

enum DraftReminderNotificationManager {
    private static let categoryIdentifier = "DRAFT_REMINDER"
    static let pendingDeviceTokenKey = "bloggo.pendingDeviceToken"

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
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

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            // Already approved — ensure we're registered and flush any pending token.
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            if let token = UserDefaults.standard.string(forKey: pendingDeviceTokenKey) {
                await APIManager.shared.registerDeviceToken(token)
            }
            return false

        case .notDetermined:
            // Permission not yet requested (or reset). Ask once more now that an account exists.
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
            return false

        default:
            // Denied — caller should prompt the user to open Settings.
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
