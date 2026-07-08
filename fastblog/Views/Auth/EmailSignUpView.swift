//
//  EmailSignUpView.swift
//  Capper
//
//  Multi-step wizard: Username -> Email -> Password (with validation)
//

import SwiftUI

private enum BloggoLegalWebURLs {
    static let privacy = URL(string: "https://bloggo.linkedspaces.com/privacy")!
    static let terms = URL(string: "https://bloggo.linkedspaces.com/terms")!
}

struct EmailSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
    @State private var showSpamAlert = false
    
    @FocusState private var usernameFocused: Bool
    @FocusState private var emailFocused: Bool

    private enum PasswordFieldFocus: Hashable {
        case primary
        case confirm
    }

    @FocusState private var passwordFieldFocus: PasswordFieldFocus?

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

    private var confirmPasswordBorderColor: Color {
        if passwordFieldFocus == .confirm {
            return OnboardingConstants.Colors.doneButtonBlue
        }
        if confirmPassword.isEmpty {
            return OnboardingConstants.Colors.hairline
        }
        return doPasswordsMatch ? Color.green.opacity(0.6) : Color.red.opacity(0.6)
    }

    var body: some View {
        ZStack {
                backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(spacing: 24) {
                                switch step {
                                case .enterUsername:
                                    usernameStep
                                case .enterEmail:
                                    emailStep
                                case .enterPassword:
                                    passwordStep(proxy: proxy)
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxHeight: .infinity)
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
                        if step == .enterUsername {
                            dismiss()
                        } else {
                            withAnimation {
                                step = Step(rawValue: step.rawValue - 1) ?? .enterUsername
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(OnboardingConstants.Colors.primaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    stepIndicator
                }
            }
            .preferredColorScheme(.light)
            .alert("Verify Your Email", isPresented: $showSpamAlert) {
                Button("Got it") { dismiss() }
            } message: {
                Text("A verification link has been sent to \(email). Tap the link in that email to complete sign-up. Don't see it? Check your spam or junk folder.")
            }
    }

    // MARK: - Steps

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
            }

            VStack(spacing: 8) {
                TextField("Your name", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($usernameFocused)
                    .padding()
                    .background(OnboardingConstants.Colors.controlBackground)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 12)
                            .stroke(usernameFocused ? OnboardingConstants.Colors.doneButtonBlue : OnboardingConstants.Colors.hairline, lineWidth: 1)
                    )
                    .appChromeCornerRadius(12)
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                    .tint(OnboardingConstants.Colors.doneButtonBlue)
                    .submitLabel(.continue)
                    .onSubmit { goToEmail() }

                if let err = errorMessage {
                    errorRow(err)
                }
            }

            primaryButton("Continue", icon: "arrow.right") {
                goToEmail()
            }
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)

            VStack(spacing: 6) {
                Text("By continuing, you are agreeing to Bloggo's")
                    .font(.caption)
                    .foregroundColor(OnboardingConstants.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    Button("Terms of Service") {
                        openURL(BloggoLegalWebURLs.terms)
                    }
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)

                    Text("and")
                        .foregroundColor(OnboardingConstants.Colors.tertiaryText)

                    Button("Privacy Policy") {
                        openURL(BloggoLegalWebURLs.privacy)
                    }
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
                }
                .font(.caption)
            }
            .padding(.top, 4)
        }
        .onAppear { usernameFocused = true }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's your email?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                Text("We need this for your account recovery.")
                    .font(.subheadline)
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
            }

            VStack(spacing: 8) {
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
                    .submitLabel(.continue)
                    .onSubmit { goToPassword() }
                    .onChange(of: email) { _, _ in
                        if errorMessage != nil { errorMessage = nil }
                    }

                if let err = errorMessage {
                    errorRow(err)
                }
            }

            primaryButton("Next", icon: "arrow.right") {
                goToPassword()
            }
            .disabled(!authService.isValidEmail(email))
        }
        .onAppear { emailFocused = true }
    }

    private func passwordStep(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Password")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                Text("Use at least 8 characters with uppercase, lowercase, number, and special character.")
                    .font(.caption)
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
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
                    .focused($passwordFieldFocus, equals: .primary)
                    .padding()
                    .background(OnboardingConstants.Colors.controlBackground)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 12)
                            .stroke(passwordFieldFocus == .primary ? OnboardingConstants.Colors.doneButtonBlue : OnboardingConstants.Colors.hairline, lineWidth: 1)
                    )
                    .appChromeCornerRadius(12)
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                    .tint(OnboardingConstants.Colors.doneButtonBlue)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(OnboardingConstants.Colors.secondaryText)
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
                    .focused($passwordFieldFocus, equals: .confirm)
                    .padding()
                    .background(OnboardingConstants.Colors.controlBackground)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 12)
                            .stroke(confirmPasswordBorderColor, lineWidth: 1)
                    )
                    .appChromeCornerRadius(12)
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                    .tint(OnboardingConstants.Colors.doneButtonBlue)
                    
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
            .id("passwordCreateAccountCTA")
            .disabled(!isPasswordValid || !doPasswordsMatch)
        }
        .onAppear { passwordFieldFocus = .primary }
        .onChange(of: passwordFieldFocus) { _, newValue in
            guard newValue == .confirm else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo("passwordCreateAccountCTA", anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { stepValue in
                let active = step == stepValue
                let past = stepValue.rawValue < step.rawValue
                Capsule()
                    .fill(active || past ? OnboardingConstants.Colors.primaryText : OnboardingConstants.Colors.hairline)
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
        guard authService.isValidEmail(trimmedEmail) else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let isAvailable = try await authService.checkEmailAvailability(email: trimmedEmail)
                if isAvailable {
                    withAnimation { step = .enterPassword }
                } else {
                    errorMessage = "An account with this email already exists."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
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
                showSpamAlert = true
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
    EmailSignUpView()
        .environmentObject(AuthService.shared)
}
