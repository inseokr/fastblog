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

    func loadThumbnail(assetIdentifier: String, targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        // Check memory cache first
        let key = NSString(string: "\(assetIdentifier)-thumb-\(targetSize.width)x\(targetSize.height)")
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
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

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

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
