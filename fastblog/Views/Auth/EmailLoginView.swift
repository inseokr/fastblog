//
//  EmailLoginView.swift
//  Capper
//
//  Login with email/username and password
//

import SwiftUI

struct EmailLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    var onAuthenticated: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(onAuthenticated: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.onAuthenticated = onAuthenticated
        self.onDismiss = onDismiss
    }

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showForgotPassword = false
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome Back")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                        Text("Log in to your account.")
                            .font(.subheadline)
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        TextField("Username", text: $email)
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
                            .submitLabel(.next)
                            .onSubmit { passwordFocused = true }

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                            .padding()
                            .background(OnboardingConstants.Colors.controlBackground)
                            .overlay(
                                RoundedRectangle(appChromeBaseRadius: 12)
                                    .stroke(passwordFocused ? OnboardingConstants.Colors.doneButtonBlue : OnboardingConstants.Colors.hairline, lineWidth: 1)
                            )
                            .appChromeCornerRadius(12)
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                            .tint(OnboardingConstants.Colors.doneButtonBlue)
                            .submitLabel(.go)
                            .onSubmit { performLogin() }
                    }

                    if let err = errorMessage {
                        errorRow(err)
                    }

                    primaryButton("Log In") {
                        performLogin()
                    }
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    .padding(.top, 8)

                    Button("Forgot Password?") {
                        showForgotPassword = true
                    }
                    .font(.subheadline)
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
                    .padding(.top, 12)

                    Spacer()
                }
                .padding(.horizontal, 24)

                if isLoading {
                    loadingOverlay
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                    }
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                if let saved = UserDefaults.standard.string(forKey: "blogify.lastLoginUsername"), !saved.isEmpty {
                    email = saved
                    passwordFocused = true
                } else {
                    emailFocused = true
                }
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView(initialUsername: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces))
                    .environmentObject(authService)
            }
    }

    private func performLogin() {
        let authEmail = email.trimmingCharacters(in: .whitespaces)
        guard !authEmail.isEmpty, !password.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.login(email: authEmail, password: password)
                onAuthenticated?()
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

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
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
    EmailLoginView()
        .environmentObject(AuthService.shared)
}
