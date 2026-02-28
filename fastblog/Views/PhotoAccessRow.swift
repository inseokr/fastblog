//
//  PhotoAccessRow.swift
//  fastblog
//
//  Settings row that shows current Photo Library authorization status
//  and routes the user to the correct system UI to change it.
//

import Photos
import PhotosUI
import SwiftUI

struct PhotoAccessRow: View {
    @StateObject private var manager = PhotosAuthorizationManager()
    @State private var showFullAccessOptions = false

    var body: some View {
        if manager.status == .limited {
            limitedAccessRows
        } else {
            defaultRow
        }
    }

    // MARK: - Default row (Not Set / None / Full Access)

    private var defaultRow: some View {
        Button {
            handleTap()
        } label: {
            HStack {
                Text("Photo Library Access")
                    .foregroundColor(.primary)
                Spacer()
                Text(manager.statusDisplayString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog("Photo Library Access", isPresented: $showFullAccessOptions) {
            Button("Manage Selected Photos") {
                presentLimitedPicker()
            }
            Button("Open iOS Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            manager.refreshStatus()
        }
    }

    // MARK: - Limited Access: two tappable areas

    private var limitedAccessRows: some View {
        Group {
            // Top row — opens iOS Settings to change permission level
            Button {
                openAppSettings()
            } label: {
                HStack {
                    Text("Photo Library Access")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("Limited")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)

            // Sub-row — opens Limited Library Picker to manage selected photos
            Button {
                presentLimitedPicker()
            } label: {
                HStack {
                    Text("Selected Photos")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(manager.selectedPhotoCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            manager.refreshStatus()
        }
    }

    // MARK: - Tap routing (non-limited states only)

    private func handleTap() {
        switch manager.status {
        case .notDetermined:
            Task { await manager.requestAccess() }
        case .denied, .restricted:
            openAppSettings()
        case .authorized:
            showFullAccessOptions = true
        case .limited:
            break // handled by limitedAccessRows
        @unknown default:
            openAppSettings()
        }
    }

    // MARK: - Helpers

    private func presentLimitedPicker() {
        guard let vc = topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc) { _ in
            Task { @MainActor in
                manager.refreshStatus()
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}
