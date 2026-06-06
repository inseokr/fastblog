//
//  ScanPhotoAccessSheet.swift
//  fastblog
//

import Photos
import SwiftUI

/// Contextual photo-library prompt when the user starts a trip scan without Bloggo captures or library access.
struct ScanPhotoAccessSheet: View {
    @ObservedObject var photoAuth: PhotosAuthorizationManager
    var onGranted: () -> Void
    var onUseCamera: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    private var isDeniedOrRestricted: Bool {
        switch photoAuth.status {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

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
                Spacer(minLength: 12)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.18), radius: 16, y: 8)
                    .padding(.bottom, 24)

                VStack(spacing: 14) {
                    Text("Scan your camera roll")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(primaryMessage)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Text("Your photos stay private on your device.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 4)
                }

                Spacer()

                VStack(spacing: 12) {
                    if isDeniedOrRestricted {
                        Button {
                            openSettings()
                        } label: {
                            Text("Open Settings")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OnboardingConstants.Colors.doneButtonBlue)
                                .clipShape(Capsule())
                        }
                    } else {
                        Button {
                            requestPhotoAccess()
                        } label: {
                            Text(isRequesting ? "Requesting…" : "Find My Trips")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OnboardingConstants.Colors.doneButtonBlue)
                                .clipShape(Capsule())
                        }
                        .disabled(isRequesting)
                    }

                    Button(action: onUseCamera) {
                        Text("Use Camera Instead")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    }

                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            photoAuth.refreshStatus()
        }
        .onChange(of: photoAuth.status) { _, newStatus in
            guard isDeniedOrRestricted else { return }
            switch newStatus {
            case .authorized, .limited:
                onGranted()
                dismiss()
            default:
                break
            }
        }
    }

    private var primaryMessage: String {
        if isDeniedOrRestricted {
            return "Photo access is off. Turn it on in Settings for full or limited access, or capture new moments with Bloggo's camera."
        }
        return "Bloggo needs access to your camera roll to find trips from photos you've already taken. You can allow full or limited access."
    }

    private func requestPhotoAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            AppAnalytics.shared.trackEvent(name: "photo_permission_prompted")
            await photoAuth.requestAccess()
            isRequesting = false
            switch photoAuth.status {
            case .authorized, .limited:
                AppAnalytics.shared.trackEvent(name: "photo_permission_granted")
                onGranted()
                dismiss()
            case .denied, .restricted:
                break
            default:
                break
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ScanPhotoAccessSheet(
        photoAuth: PhotosAuthorizationManager(),
        onGranted: {},
        onUseCamera: {},
        onDismiss: {}
    )
}
