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

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = newStatus
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
}
