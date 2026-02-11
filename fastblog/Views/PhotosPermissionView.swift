//
//  PhotosPermissionView.swift
//  Capper
//

import Photos
import SwiftUI

struct PhotosPermissionView: View {
    let status: PHAuthorizationStatus
    let onRequest: () async -> Void
    let onOpenSettings: () -> Void

    private let background = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.9))

                Text("Photo Access")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(message)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if status == .notDetermined {
                    Button {
                        Task { await onRequest() }
                    } label: {
                        Text("Allow Access to Photos")
                            .font(.headline)
                            .foregroundColor(background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                } else {
                    Button {
                        onOpenSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundColor(background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var message: String {
        switch status {
        case .notDetermined:
            return "BlogGo needs access to your photos to scan for trips from the last 3 months and build your recap blogs."
        case .denied, .restricted:
            return "Photo access was denied. Turn on access in Settings to scan your library and create recap blogs."
        default:
            return "Allow photo access to continue."
        }
    }
}
