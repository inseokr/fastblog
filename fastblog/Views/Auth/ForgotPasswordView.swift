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

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recover Password")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Enter your username and email address and we'll send you a reset link.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))
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
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .preferredColorScheme(.dark)
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
                .background(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .appChromeCornerRadius(12)
                .foregroundColor(.white)
                .tint(.white)

            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding()
                .background(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .appChromeCornerRadius(12)
                .foregroundColor(.white)
                .tint(.white)
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
    }

    private var successBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.checkmark")
                .font(.system(size: 52))
                .foregroundColor(.green)
                .padding(.top, 24)

            Text("Check Your Inbox")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("If an account with those details exists, you'll receive a password reset email shortly.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
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
            .foregroundColor(Color(red: 0.05, green: 0.08, blue: 0.22))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white)
            .appChromeCornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundGradient: some View {
        Color(red: 5/255, green: 10/255, blue: 48/255)
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
