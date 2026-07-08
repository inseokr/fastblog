//
//  ForgotPasswordView.swift
//  fastblog
//
//  Forgot-password screen: collects username + email and requests a password-reset link.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    /// Pre-fill from login screen (e.g. "Email or Username" field) when navigating via "Forgot Password?".
    var initialUsername: String?

    @State private var username = ""
    @State private var email = ""

    init(initialUsername: String? = nil) {
        self.initialUsername = initialUsername
    }
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSendEmail = false
    @State private var showForgotUsername = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recover Password")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                        Text("Enter your username and email address and we'll send you a reset link.")
                            .font(.subheadline)
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                    if didSendEmail {
                        successBanner
                    } else {
                        inputFields
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)

                if isLoading {
                    loadingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                if let prefill = initialUsername, !prefill.isEmpty {
                    username = prefill
                } else if username.isEmpty, let last = UserDefaults.standard.string(forKey: "blogify.lastLoginUsername") {
                    username = last
                }
            }
        }
    }

    @ViewBuilder
    private var inputFields: some View {
        VStack(spacing: 16) {
            TextField("Username", text: $username)
                .textContentType(.username)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding()
                .background(OnboardingConstants.Colors.controlBackground)
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 12)
                        .stroke(OnboardingConstants.Colors.hairline, lineWidth: 1)
                )
                .appChromeCornerRadius(12)
                .foregroundColor(OnboardingConstants.Colors.primaryText)
                .tint(OnboardingConstants.Colors.doneButtonBlue)

            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding()
                .background(OnboardingConstants.Colors.controlBackground)
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 12)
                        .stroke(OnboardingConstants.Colors.hairline, lineWidth: 1)
                )
                .appChromeCornerRadius(12)
                .foregroundColor(OnboardingConstants.Colors.primaryText)
                .tint(OnboardingConstants.Colors.doneButtonBlue)
        }

        if let err = errorMessage {
            errorRow(err)
        }

        primaryButton("Send Recovery Email", icon: "envelope.fill") {
            sendRecovery()
        }
        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty
                  || email.trimmingCharacters(in: .whitespaces).isEmpty
                  || isLoading)
        .padding(.top, 8)

        Button("Don't know your username?") {
            showForgotUsername = true
        }
        .font(.subheadline)
        .foregroundColor(OnboardingConstants.Colors.secondaryText)
        .padding(.top, 4)
        .sheet(isPresented: $showForgotUsername) {
            ForgotUsernameView()
                .environmentObject(authService)
        }
    }

    private var successBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.checkmark")
                .font(.system(size: 52))
                .foregroundColor(.green)
                .padding(.top, 24)

            Text("Check Your Inbox")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(OnboardingConstants.Colors.primaryText)

            Text("If an account with those details exists, you'll receive a password reset email shortly.")
                .font(.subheadline)
                .foregroundColor(OnboardingConstants.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            primaryButton("Done", icon: "checkmark.circle.fill") {
                dismiss()
            }
            .padding(.top, 16)
        }
    }

    private func sendRecovery() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty, !trimmedEmail.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.sendRecoveryEmail(username: trimmedUsername, email: trimmedEmail)
                withAnimation { didSendEmail = true }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red.opacity(0.85))
            Text(message)
                .font(.caption)
                .foregroundColor(.red.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut, value: message)
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(OnboardingConstants.Colors.doneButtonBlue)
            .appChromeCornerRadius(14)
            .shadow(color: OnboardingConstants.Colors.doneButtonBlue.opacity(0.28), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                OnboardingConstants.Colors.backgroundGradientTop,
                OnboardingConstants.Colors.backgroundGradientBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
        }
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthService.shared)
}
