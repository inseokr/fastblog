//
//  PushPermissionPromptView.swift
//  fastblog
//
//  Shown when the user is logged in but has no push token registered
//  (notification permission denied or never granted).  Includes a
//  "Do not show this again" option so repeat dismissals are respected.
//

import SwiftUI

struct PushPermissionPromptView: View {
    @Binding var isPresented: Bool
    @State private var doNotShowAgain = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Spacer().frame(height: 32)

            // Icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .padding(.bottom, 20)

            // Title
            Text("Stay in the loop")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Spacer().frame(height: 12)

            // Body
            Text("Enable push notifications to get reminders about your blog drafts, updates on your trips, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 36)

            // Primary CTA — opens Settings so the user can flip the toggle
            Button {
                doNotShowAgain = false
                saveDoNotShowPreference()
                openSettings()
                isPresented = false
            } label: {
                Text("Enable Notifications")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            // Secondary — dismiss without opening Settings
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

            // Do-not-show toggle
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
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.hidden)
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
