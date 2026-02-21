//
//  EmailSignUpView.swift
//  Capper
//
//  Multi-step wizard: Username -> Email -> Password (with validation)
//

import SwiftUI

struct EmailSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    var onAuthenticated: (() -> Void)?
    
    init(onAuthenticated: (() -> Void)? = nil) {
        self.onAuthenticated = onAuthenticated
    }

    enum Step: Int, CaseIterable {
        case enterUsername = 0
        case enterEmail
        case enterPassword
    }

    @State private var step: Step = .enterUsername
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @FocusState private var usernameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    // Validation
    private var isPasswordLengthValid: Bool { password.count >= 8 }
    private var hasUppercase: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var hasLowercase: Bool { password.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var hasNumber: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    private var hasSpecialChar: Bool { password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{};':\"\\|,.<>/?")) != nil }
    
    private var isPasswordValid: Bool {
        isPasswordLengthValid && hasUppercase && hasLowercase && hasNumber && hasSpecialChar
    }
    
    private var doPasswordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    stepIndicator
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            switch step {
                            case .enterUsername:
                                usernameStep
                            case .enterEmail:
                                emailStep
                            case .enterPassword:
                                passwordStep
                            }
                        }
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
                ToolbarItem(placement: .navigationBarLeading) {
                    if step != .enterUsername {
                        Button {
                            // Go back one step
                            withAnimation {
                                step = Step(rawValue: step.rawValue - 1) ?? .enterUsername
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if step == .enterUsername {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Steps

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(spacing: 8) {
                TextField("Your name", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($usernameFocused)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(usernameFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .tint(.white)
                    .submitLabel(.continue)
                    .onSubmit { goToEmail() }

                if let err = errorMessage {
                    errorRow(err)
                }
            }

            primaryButton("Next", icon: "arrow.right") {
                goToEmail()
            }
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { usernameFocused = true }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's your email?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("We need this for your account recovery.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(spacing: 8) {
                TextField("Email address", text: $email)
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
                    .submitLabel(.continue)
                    .onSubmit { goToPassword() }

                if let err = errorMessage {
                    errorRow(err)
                }
            }

            primaryButton("Next", icon: "arrow.right") {
                goToPassword()
            }
            .disabled(!email.contains("@") || email.contains(" "))
        }
        .onAppear { emailFocused = true }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Password")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Use at least 8 characters with uppercase, lowercase, number, and special character.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(spacing: 16) {
                // Password Field
                ZStack(alignment: .trailing) {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.newPassword)
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

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.trailing, 16)
                    }
                }

                // Requirements Grid
                VStack(alignment: .leading, spacing: 6) {
                    requirementRow("8+ chars", isValid: isPasswordLengthValid)
                    requirementRow("Uppercase", isValid: hasUppercase)
                    requirementRow("Lowercase", isValid: hasLowercase)
                    requirementRow("Number", isValid: hasNumber)
                    requirementRow("Special (@#$!)", isValid: hasSpecialChar)
                }

                // Confirm Password Field
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
                    .background(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(confirmPassword.isEmpty ? Color.white.opacity(0.2) : (doPasswordsMatch ? Color.green.opacity(0.6) : Color.red.opacity(0.6)), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .tint(.white)
                    
                    if !confirmPassword.isEmpty && !doPasswordsMatch {
                        Text("Mismatched")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.trailing, 16)
                    }
                }

                if let err = errorMessage {
                    errorRow(err)
                }
            }

            primaryButton("Create Account", icon: "checkmark.circle.fill") {
                performSignUp()
            }
            .disabled(!isPasswordValid || !doPasswordsMatch)
        }
        .onAppear { passwordFocused = true }
    }
    
    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { stepValue in
                let active = step == stepValue
                let past = stepValue.rawValue < step.rawValue
                Capsule()
                    .fill(active || past ? Color.white : Color.white.opacity(0.25))
                    .frame(width: active ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35), value: step)
            }
        }
    }

    // MARK: - Logic

    private func goToEmail() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let isAvailable = try await authService.checkUsernameAvailability(username: trimmedUsername)
                if isAvailable {
                    withAnimation { step = .enterEmail }
                } else {
                    errorMessage = "That username is already taken."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func goToPassword() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard trimmedEmail.contains("@") else { return }
        errorMessage = nil
        withAnimation { step = .enterPassword }
    }

    private func performSignUp() {
        guard isPasswordValid, doPasswordsMatch else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signup(
                    username: username.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                onAuthenticated?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func requirementRow(_ text: String, isValid: Bool) -> some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isValid ? .green : .white.opacity(0.5))
                .font(.system(size: 14))
            Text(text)
                .font(.caption)
                .foregroundColor(isValid ? .green : .white.opacity(0.7))
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
    EmailSignUpView()
        .environmentObject(AuthService.shared)
}
