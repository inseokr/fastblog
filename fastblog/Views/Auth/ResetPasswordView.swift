//
//  ResetPasswordView.swift
//  fastblog
//
//  Set new password using token from reset link (deep link or route param).
//

import SwiftUI

struct ResetPasswordView: View {
    let token: String
    var onSuccess: (() -> Void)?

    @EnvironmentObject private var authService: AuthService

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false

    private var passwordsMatch: Bool { !newPassword.isEmpty && newPassword == confirmPassword }
    private var isPasswordLengthValid: Bool { newPassword.count >= 8 }
    private var hasUppercase: Bool { newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var hasLowercase: Bool { newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var hasNumber: Bool { newPassword.rangeOfCharacter(from: .decimalDigits) != nil }
    private var hasSpecialChar: Bool { newPassword.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{};':\"\\|,.<>/?")) != nil }

    private var isPasswordValid: Bool {
        isPasswordLengthValid && hasUppercase && hasLowercase && hasNumber && hasSpecialChar
    }
    private var canSubmit: Bool {
        isPasswordValid && passwordsMatch && !isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set New Password")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                        Text("Use at least 8 characters with uppercase, lowercase, number, and special character.")
                            .font(.caption)
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        // New Password field with show/hide toggle
                        ZStack(alignment: .trailing) {
                            Group {
                                if showPassword {
                                    TextField("New Password", text: $newPassword)
                                } else {
                                    SecureField("New Password", text: $newPassword)
                                }
                            }
                            .textContentType(.newPassword)
                            .padding()
                            .background(OnboardingConstants.Colors.controlBackground)
                            .overlay(
                                RoundedRectangle(appChromeBaseRadius: 12)
                                    .stroke(OnboardingConstants.Colors.hairline, lineWidth: 1)
                            )
                            .appChromeCornerRadius(12)
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                            .tint(OnboardingConstants.Colors.doneButtonBlue)

                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye" : "eye.slash")
                                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
                                    .padding(.trailing, 16)
                            }
                        }

                        // Requirements checklist
                        VStack(alignment: .leading, spacing: 6) {
                            requirementRow("8+ chars", isValid: isPasswordLengthValid)
                            requirementRow("Uppercase", isValid: hasUppercase)
                            requirementRow("Lowercase", isValid: hasLowercase)
                            requirementRow("Number", isValid: hasNumber)
                            requirementRow("Special (@#$!)", isValid: hasSpecialChar)
                        }

                        // Confirm Password field
                        ZStack(alignment: .trailing) {
                            Group {
                                if showPassword {
                                    TextField("Confirm Password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm Password", text: $confirmPassword)
                                }
                            }
                            .textContentType(.newPassword)
                            .padding()
                            .background(OnboardingConstants.Colors.controlBackground)
                            .overlay(
                                RoundedRectangle(appChromeBaseRadius: 12)
                                    .stroke(
                                        confirmPassword.isEmpty ? OnboardingConstants.Colors.hairline
                                            : passwordsMatch ? Color.green.opacity(0.6)
                                            : Color.red.opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                            .appChromeCornerRadius(12)
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                            .tint(OnboardingConstants.Colors.doneButtonBlue)

                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text("Mismatched")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .padding(.trailing, 16)
                            }
                        }
                    }

                    if let err = errorMessage {
                        errorRow(err)
                    }

                    primaryButton("Reset Password", icon: "lock.rotation.open") {
                        submitReset()
                    }
                    .disabled(!canSubmit)
                    .padding(.top, 8)

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
                    Button("Cancel") {
                        onSuccess?()
                    }
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
                }
            }
            .preferredColorScheme(.light)
            .alert("Password Reset", isPresented: $showSuccessAlert) {
                Button("OK") {
                    showSuccessAlert = false
                    onSuccess?()
                }
            } message: {
                Text("Your password has been reset. You can sign in with your new password.")
            }
        }
    }

    private func submitReset() {
        guard canSubmit else { return }
        errorMessage = nil
        if !isPasswordValid {
            errorMessage = "Password must be 8+ characters with uppercase, lowercase, number, and special character."
            return
        }
        if !passwordsMatch {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true
        Task {
            do {
                try await authService.resetPassword(token: token, newPassword: newPassword, confirmPassword: confirmPassword)
                showSuccessAlert = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func requirementRow(_ text: String, isValid: Bool) -> some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isValid ? .green : OnboardingConstants.Colors.tertiaryText)
                .font(.system(size: 14))
            Text(text)
                .font(.caption)
                .foregroundColor(isValid ? .green : OnboardingConstants.Colors.secondaryText)
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
    ResetPasswordView(token: "preview-token", onSuccess: {})
        .environmentObject(AuthService.shared)
}
