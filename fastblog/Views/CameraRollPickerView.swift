//
//  CameraRollPickerView.swift
//  fastblog
//
//  PhotosUI types (PHPickerViewController, PHPickerResult) must compile in a translation
//  unit that imports PhotosUI; kept separate from TripsView.swift for reliable resolution.

import CoreLocation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Wraps PHPickerViewController so users can manually select photos from their library.
/// Returns the PHAsset localIdentifiers of the chosen photos via `onComplete`.
struct CameraRollPickerView: UIViewControllerRepresentable {
    let onComplete: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // 0 = unlimited
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([String]) -> Void
        init(onComplete: @escaping ([String]) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap { $0.assetIdentifier }
            picker.dismiss(animated: true)
            onComplete(identifiers)
        }
    }
}

// MARK: - Single-image import (copy pixels into app storage)

/// Picks one photo from the library, loads image data, and resolves date/location from `PHAsset` when available.
struct SinglePhotoLibraryPickerView: UIViewControllerRepresentable {
    let onComplete: (UIImage?, Date, CLLocation?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: (UIImage?, Date, CLLocation?) -> Void
        init(onComplete: @escaping (UIImage?, Date, CLLocation?) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                DispatchQueue.main.async { self.onComplete(nil, Date(), nil) }
                return
            }
            var resolvedDate = Date()
            var resolvedLocation: CLLocation?
            if let id = result.assetIdentifier {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                if let asset = assets.firstObject {
                    resolvedDate = asset.creationDate ?? resolvedDate
                    resolvedLocation = asset.location
                }
            }
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async { self.onComplete(nil, resolvedDate, resolvedLocation) }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.onComplete(object as? UIImage, resolvedDate, resolvedLocation)
                }
            }
        }
    }
}
