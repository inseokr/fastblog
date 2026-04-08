//
//  ImageLoader.swift
//  Capper
//

import Foundation
import Photos
import UIKit

@MainActor
final class ImageLoader {
    static let shared = ImageLoader()
    
    private let imageManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    
    init() {}

    /// Prime `PHCachingImageManager` so grids can paint quickly.
    /// This does *not* store to our memory `NSCache`; it just lets Photos fetch/decode ahead of time.
    func startCachingThumbnails(assetIdentifiers: [String], targetSize: CGSize) {
        let ids = assetIdentifiers.filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
        guard !ids.isEmpty else { return }
        let results = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(results.count)
        results.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    func stopCachingThumbnails(assetIdentifiers: [String], targetSize: CGSize) {
        let ids = assetIdentifiers.filter { !$0.hasPrefix(AppCapturePhotoService.prefix) }
        guard !ids.isEmpty else { return }
        let results = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(results.count)
        results.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    func loadThumbnail(assetIdentifier: String, targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        // Check memory cache first
        let key = NSString(string: "\(assetIdentifier)-thumb-\(targetSize.width)x\(targetSize.height)")
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // App-capture path
        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            let image = AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier)
            if let image { cache.setObject(image, forKey: key) }
            return image
        }

        var asset: PHAsset?
        for attempt in 0..<3 {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            asset = assets.firstObject
            if asset != nil { break }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        guard let asset else { return nil }

        let options = PHImageRequestOptions()
        // `fastFormat` returns noticeably soft images when cells scale thumbnails on retina; keep full-quality delivery.
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                if let image = image {
                    self?.cache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    func loadImage(assetIdentifier: String, targetSize: CGSize) async -> UIImage? {
        // Check memory cache first
        let key = NSString(string: "\(assetIdentifier)-full-\(targetSize.width)x\(targetSize.height)")
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // App-capture path
        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            let image = AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier)
            if let image { cache.setObject(image, forKey: key) }
            return image
        }

        var asset: PHAsset?
        for attempt in 0..<3 {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            asset = assets.firstObject
            if asset != nil { break }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        guard let asset else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, _ in
                if let image = image {
                    self?.cache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }
    
    /// Synchronously check if image is in cache (used to prevent flash of placeholder).
    func cachedThumbnail(assetIdentifier: String, targetSize: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let key = NSString(string: "\(assetIdentifier)-thumb-\(targetSize.width)x\(targetSize.height)")
        return cache.object(forKey: key)
    }
}
