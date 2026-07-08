//
//  ForgotUsernameView.swift
//  fastblog
//
//  Lets users recover their username by entering the email address
//  they signed up with. The backend sends the username to that address.
//

import SwiftUI

struct ForgotUsernameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSendEmail = false

    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find Your Username")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                        Text("Enter the email address you signed up with and we'll send your username to it.")
                            .font(.subheadline)
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                    if didSendEmail {
                        successBanner
                    } else {
                        inputSection
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
            .onAppear { emailFocused = true }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var inputSection: some View {
        VStack(spacing: 16) {
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused($emailFocused)
                .padding()
                .background(OnboardingConstants.Colors.controlBackground)
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 12)
                        .stroke(emailFocused ? OnboardingConstants.Colors.doneButtonBlue : OnboardingConstants.Colors.hairline, lineWidth: 1)
                )
                .appChromeCornerRadius(12)
                .foregroundColor(OnboardingConstants.Colors.primaryText)
                .tint(OnboardingConstants.Colors.doneButtonBlue)
                .submitLabel(.send)
                .onSubmit { sendReminder() }
                .onChange(of: email) { _, _ in
                    if errorMessage != nil { errorMessage = nil }
                }

            if let err = errorMessage {
                errorRow(err)
            }
        }

        primaryButton("Send Username", icon: "envelope.fill") {
            sendReminder()
        }
        .disabled(!authService.isValidEmail(email.trimmingCharacters(in: .whitespaces)) || isLoading)
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
                .foregroundColor(OnboardingConstants.Colors.primaryText)

            Text("If an account is registered with that email, we've sent the username to it.")
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

    // MARK: - Logic

    private func sendReminder() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard authService.isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.requestUsernameReminder(email: trimmedEmail)
                withAnimation { didSendEmail = true }
            } catch {
                // Show success anyway — never reveal whether an email exists.
                withAnimation { didSendEmail = true }
            }
            isLoading = false
        }
    }

    // MARK: - Helpers

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
    ForgotUsernameView()
        .environmentObject(AuthService.shared)
}
