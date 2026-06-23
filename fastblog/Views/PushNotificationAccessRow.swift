//
//  PushNotificationAccessRow.swift
//  fastblog
//
//  Settings row for push notification permission — mirrors PhotoAccessRow.
//

import SwiftUI
import UserNotifications

struct PushNotificationAccessRow: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack {
                Text("Notifications")
                    .foregroundColor(.primary)
                Spacer()
                Text(statusDisplayString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .task { await refreshStatus() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            Task { await refreshStatus() }
        }
    }

    private var statusDisplayString: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "On"
        case .denied:
            return "Off"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func handleTap() {
        switch authorizationStatus {
        case .notDetermined:
            Task {
                _ = await DraftReminderNotificationManager.requestAuthorizationFromUser()
                await refreshStatus()
            }
        case .denied:
            openAppSettings()
        case .authorized, .provisional, .ephemeral:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
