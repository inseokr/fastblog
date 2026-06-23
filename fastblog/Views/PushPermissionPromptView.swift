//
//  PushPermissionPromptView.swift
//  fastblog
//
//  Shown when the user is logged in but has no push token registered
//  (notification permission denied or never granted).  Includes a
//  "Do not show this again" option so repeat dismissals are respected.
//

import SwiftUI
import UserNotifications

struct PushPermissionPromptView: View {
    @Binding var isPresented: Bool
    @State private var doNotShowAgain = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .padding(.bottom, 20)

            Text("Stay in the loop")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Spacer().frame(height: 12)

            Text("Get memory recalls, My Places weekly digests, and gentle reminders to capture everyday moments. You can change this anytime in Settings → Permissions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 36)

            Button {
                Task { await enableNotifications() }
            } label: {
                Text(primaryButtonTitle)
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            Button {
                saveDoNotShowPreference()
                isPresented = false
            } label: {
                Text("Not Now")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            Toggle(isOn: $doNotShowAgain) {
                Text("Do not show this again")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .task { await refreshAuthorizationStatus() }
    }

    private var primaryButtonTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Allow Notifications"
        default:
            return "Open Settings"
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await DraftReminderNotificationManager.currentAuthorizationStatus()
    }

    private func enableNotifications() async {
        if authorizationStatus == .notDetermined {
            let granted = await DraftReminderNotificationManager.requestAuthorizationFromUser()
            await refreshAuthorizationStatus()
            if granted {
                saveDoNotShowPreference()
                isPresented = false
            }
        } else {
            saveDoNotShowPreference()
            openSettings()
            isPresented = false
        }
    }

    private func saveDoNotShowPreference() {
        if doNotShowAgain {
            UserDefaults.standard.set(true, forKey: DraftReminderNotificationManager.doNotShowPushPromptKey)
            print("[Push] User opted out of push-permission re-prompt")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Checkbox toggle style

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.orange : Color.secondary)
                    .font(.system(size: 18))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
