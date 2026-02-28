//
//  PhotosAuthorizationManager.swift
//  Capper
//

import Combine
import Photos
import SwiftUI

@MainActor
final class PhotosAuthorizationManager: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = .notDetermined
    /// Number of photos the user has granted access to (meaningful in .limited).
    @Published private(set) var selectedPhotoCount: Int = 0

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        refreshPhotoCount()
    }

    func requestAccess() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = newStatus
        refreshPhotoCount()
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        refreshPhotoCount()
    }

    private func refreshPhotoCount() {
        guard status == .limited || status == .authorized else {
            selectedPhotoCount = 0
            return
        }
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        selectedPhotoCount = result.count
    }

    var isAuthorized: Bool {
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// User-facing label for the current photo library authorization status.
    var statusDisplayString: String {
        switch status {
        case .authorized:            return "Full"
        case .limited:               return "Limited"
        case .denied, .restricted:   return "None"
        case .notDetermined:         return "Not Set"
        @unknown default:            return "Unknown"
        }
    }
}
