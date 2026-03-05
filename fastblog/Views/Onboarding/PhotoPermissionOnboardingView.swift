//
//  PhotoPermissionOnboardingView.swift
//  Capper
//

import Photos
import SwiftUI

struct PhotoPermissionOnboardingView: View {
    @ObservedObject var photoAuth: PhotosAuthorizationManager
    /// Called after the permission request completes with the resulting status.
    var onResult: ((PHAuthorizationStatus) -> Void)? = nil

    // Staggered animation phases (similar to ProblemStatementView)
    @State private var showIcon = false
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showTrustLine = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop,
                    OnboardingConstants.Colors.backgroundGradientBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                
                // Icon Header
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.2), radius: 20, y: 10)
                    .padding(.bottom, 40)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.8)

                // Copy
                VStack(spacing: 16) {
                    Text("Find trips automatically")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo groups photos by date and location to build recap blogs.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)
                    
                    Text("Photos stay on your device. Upload is optional.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 40)
                        .opacity(showTrustLine ? 1 : 0)
                        .offset(y: showTrustLine ? 0 : 8)
                }
                
                Spacer()

                // Button
                VStack(spacing: 8) {
                    Button {
                        Task {
                            let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                            if current == .authorized || current == .limited {
                                // Already granted (e.g. reinstall) — skip system dialog
                                onResult?(current)
                            } else {
                                await photoAuth.requestAccess()
                                onResult?(photoAuth.status)
                            }
                        }
                    } label: {
                        Text("Allow Photo Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)
                    }

                    Button {
                        Task {
                            await requestLimitedAccess()
                        }
                    } label: {
                        Text("Choose specific photos instead")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startStaggeredAnimation()
        }
    }

    /// Request limited photo access: if not yet determined, triggers the system
    /// permission dialog (where the user can choose "Select Photos…"). If already
    /// limited, directly presents the limited library picker to add/change photos.
    private func requestLimitedAccess() async {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if currentStatus == .notDetermined {
            // System dialog lets the user pick "Select Photos…" for limited access
            await photoAuth.requestAccess()
            if photoAuth.status == .limited {
                await presentLimitedPicker()
                photoAuth.refreshStatus()
            }
            onResult?(photoAuth.status)
        } else if currentStatus == .limited {
            // Already limited — show picker so user can add/change photos
            await presentLimitedPicker()
            photoAuth.refreshStatus()
            onResult?(photoAuth.status)
        } else {
            // Already authorized, denied, etc. — just proceed
            onResult?(currentStatus)
        }
    }

    /// Present Apple's limited library picker and wait for completion.
    @MainActor
    private func presentLimitedPicker() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC) { _ in
                continuation.resume()
            }
        }
    }

    private func startStaggeredAnimation() {
        let duration: TimeInterval = 0.5

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showIcon = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.2)) {
            showHeadline = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.5)) {
            showBody = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.8)) {
            showTrustLine = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.1)) {
            showButton = true
        }
    }
}

#Preview {
    PhotoPermissionOnboardingView(photoAuth: PhotosAuthorizationManager())
}
