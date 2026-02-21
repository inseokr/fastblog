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
    
    init(onAuthenticated: (() -> Void)? = nil) {
        self.onAuthenticated = onAuthenticated
    }

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome Back")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Log in to your account.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        TextField("Email or Username", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .focused($emailFocused)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(emailFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .tint(.white)
                            .submitLabel(.next)
                            .onSubmit { passwordFocused = true }

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(passwordFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .tint(.white)
                            .submitLabel(.go)
                            .onSubmit { performLogin() }
                    }

                    if let err = errorMessage {
                        errorRow(err)
                    }

                    primaryButton("Sign In", icon: "arrow.right.circle.fill") {
                        performLogin()
                    }
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
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
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { emailFocused = true }
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
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.04, green: 0.07, blue: 0.22), location: 0),
                .init(color: Color(red: 0.03, green: 0.03, blue: 0.15), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
