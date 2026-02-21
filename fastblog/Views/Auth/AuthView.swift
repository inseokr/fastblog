//
//  AuthView.swift
//  Capper
//
//  Premium auth screen: Apple, Google (UI stub), and Email sign-in.
//

import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    @State private var showEmailSignUp = false
    @State private var showEmailLogin = false
    @State private var showGoogleComingSoon = false

    // Callback for post-auth navigation (e.g. continue cloud upload)
    var onAuthenticated: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack {
            // Deep gradient background
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        AuthService.Analytics.track(.authCancelled)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                }

                Spacer()

                // Logo + headings
                headerSection
                    .padding(.horizontal, 28)

                Spacer(minLength: 40)

                // Auth buttons
                buttonStack
                    .padding(.horizontal, 24)

                // Footer
                footerSection
                    .padding(.top, 24)
                    .padding(.bottom, 40)
            }

            // Full-screen loading overlay
            if authService.isLoading {
                loadingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: Binding(
            get: { authService.errorMessage != nil },
            set: { if !$0 { /* errors clear on next action */ } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authService.errorMessage ?? "")
        }
        .alert("Google Sign In", isPresented: $showGoogleComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google Sign In is coming soon. Please use Apple or Email for now.")
        }
        .sheet(isPresented: $showEmailSignUp) {
            EmailSignUpView(onAuthenticated: {
                showEmailSignUp = false
                onAuthenticated?()
                dismiss()
            })
            .environmentObject(authService)
        }
        .sheet(isPresented: $showEmailLogin) {
            EmailLoginView(onAuthenticated: {
                showEmailLogin = false
                onAuthenticated?()
                dismiss()
            })
            .environmentObject(authService)
        }
        .onChange(of: authService.currentUser) { _, user in
            if user != nil {
                onAuthenticated?()
                dismiss()
            }
        }
        .onAppear {
            AuthService.Analytics.track(.authCreateAccountTapped)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 14) {
            // App icon mark
            Image("ScanIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .shadow(color: .blue.opacity(0.4), radius: 20)

            Text("Create your account")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Save blogs to the cloud, edit on desktop,\nand access your blogs anywhere.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var buttonStack: some View {
        VStack(spacing: 14) {
            // Apple Sign In
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
                AuthService.Analytics.track(.authProviderSelected(provider: "apple"))
            } onCompletion: { result in
                authService.handleAppleSignIn(result: result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            // Google Sign In (UI stub)
            Button {
                showGoogleComingSoon = true
                AuthService.Analytics.track(.authProviderSelected(provider: "google"))
            } label: {
                HStack(spacing: 12) {
                    // Google 'G' logo
                    GoogleGLogo()
                        .frame(width: 20, height: 20)
                    Text("Continue with Google")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // Divider
            HStack {
                authDivider
                Text("OR")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                authDivider
            }

            // Email
            Button {
                showEmailSignUp = true
                AuthService.Analytics.track(.authProviderSelected(provider: "email"))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16))
                    Text("Continue with Email")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(14)
            }
            .buttonStyle(.plain)

            Text("Use the same sign in method on web to edit your recaps.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Button {
                showEmailLogin = true
            } label: {
                HStack(spacing: 0) {
                    Text("Already have an account? ")
                        .foregroundColor(.white.opacity(0.55))
                    Text("Sign in")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
        }
    }

    private var authDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(height: 1)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.04, green: 0.07, blue: 0.22), location: 0),
                .init(color: Color(red: 0.07, green: 0.04, blue: 0.20), location: 0.5),
                .init(color: Color(red: 0.03, green: 0.03, blue: 0.15), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Signing in…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Google 'G' Logo

/// Simple programmatic Google G logo that respects guidelines (no image asset needed)
private struct GoogleGLogo: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                // Blue arc (right)
                ArcShape(startAngle: -30, endAngle: 90, clockwise: false)
                    .stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: s * 0.18)
                // Red arc (top)
                ArcShape(startAngle: 90, endAngle: 210, clockwise: false)
                    .stroke(Color(red: 0.92, green: 0.26, blue: 0.21), lineWidth: s * 0.18)
                // Yellow arc (bottom-left)
                ArcShape(startAngle: 210, endAngle: 330, clockwise: false)
                    .stroke(Color(red: 0.98, green: 0.74, blue: 0.01), lineWidth: s * 0.18)
                // Green arc (bottom-right)
                ArcShape(startAngle: 330, endAngle: 360, clockwise: false)
                    .stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: s * 0.18)
                // White cutout + horizontal bar for the 'G'
                Rectangle()
                    .fill(.white)
                    .frame(width: s * 0.5, height: s * 0.18)
                    .offset(x: s * 0.12)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ArcShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2 * 0.72,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: clockwise
        )
        return p
    }
}

// MARK: - Preview

#Preview {
    AuthView()
        .environmentObject(AuthService.shared)
}
