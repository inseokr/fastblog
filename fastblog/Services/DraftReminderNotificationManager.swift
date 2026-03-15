//
//  DraftReminderNotificationManager.swift
//  Capper
//

import UIKit
import UserNotifications

enum DraftReminderNotificationManager {
    private static let categoryIdentifier = "DRAFT_REMINDER"

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
