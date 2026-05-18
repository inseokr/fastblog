//
//  ImageLoader.swift
//  Capper
//

import Foundation
import Photos
import UIKit

/// Ensures a `CheckedContinuation` from PhotoKit is resumed exactly once (callbacks can be odd when
/// `assetsd` disconnects or a request is cancelled).
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func resumeOnce(_ continuation: CheckedContinuation<UIImage?, Never>, returning value: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return }
        consumed = true
        continuation.resume(returning: value)
    }
}

@MainActor
final class ImageLoader {
    static let shared = ImageLoader()
    
    private let imageManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    
    init() {}

    /// Drops all decoded thumbnails / full loads held in-memory. Call after heavy one-shot work
    /// such as cinematic blog video export, which intentionally loads many full-size frames while streaming.
    func clearDecodedImageMemoryCache() {
        cache.removeAllObjects()
    }

    /// Clears cached thumbnails for one identifier (e.g. after attaching a moment video to an app capture).
    func invalidateThumbnailCache(for assetIdentifier: String) {
        let prefix = "\(assetIdentifier)-thumb-"
        // NSCache has no key enumeration; common thumbnail sizes used in grids/covers.
        let sizes = [
            CGSize(width: 200, height: 200),
            CGSize(width: 400, height: 400),
            CGSize(width: 600, height: 400),
            CGSize(width: 800, height: 800),
            CGSize(width: 1200, height: 1200)
        ]
        for size in sizes {
            let key = NSString(string: "\(prefix)\(size.width)x\(size.height)")
            cache.removeObject(forKey: key)
        }
    }

    private func fetchAsset(localIdentifier: String) async -> PHAsset? {
        for attempt in 0..<3 {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            if let asset = assets.firstObject { return asset }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        return nil
    }

    /// One `highQualityFormat` request with proper cancel/error handling.
    private func requestHighQualityImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = resizeMode
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    gate.resumeOnce(continuation, returning: nil)
                    return
                }
                gate.resumeOnce(continuation, returning: image)
            }
        }
    }

    /// Same as ``loadImage(assetIdentifier:targetSize:)`` but does not read or write the memory cache so
    /// streaming exporters (many sequential full-size loads) cannot pin dozens of bitmaps past the wire.
    ///
    /// Long cinematic exports hammer PhotoKit for minutes; when `assetsd` drops an XPC connection,
    /// a single-shot `requestImage` may return nil or never complete cleanly — retries with backoff recover most cases.
    func loadImageBypassingMemoryCache(assetIdentifier: String, targetSize: CGSize) async -> UIImage? {
        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            return AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier)
        }

        let maxAttempts = 5
        for attempt in 0..<maxAttempts {
            if Task.isCancelled { return nil }
            guard let asset = await fetchAsset(localIdentifier: assetIdentifier) else {
                if attempt < maxAttempts - 1 {
                    let ns = UInt64(100_000_000) << attempt
                    try? await Task.sleep(nanoseconds: min(ns, 800_000_000))
                }
                continue
            }

            let image = await requestHighQualityImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                resizeMode: .exact
            )
            if let image { return image }

            await Task.yield()
            let backoff = UInt64(100_000_000) << attempt
            try? await Task.sleep(nanoseconds: min(backoff, 800_000_000))
        }
        return nil
    }

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
        let key = NSString(string: "\(assetIdentifier)-thumb-\(targetSize.width)x\(targetSize.height)")
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            let image = AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier)
            if let image { cache.setObject(image, forKey: key) }
            return image
        }

        guard let asset = await fetchAsset(localIdentifier: assetIdentifier) else { return nil }

        let image = await withCheckedContinuation { continuation in
            let gate = ContinuationGate()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    gate.resumeOnce(continuation, returning: nil)
                    return
                }
                if let image {
                    self?.cache.setObject(image, forKey: key)
                }
                gate.resumeOnce(continuation, returning: image)
            }
        }
        return image
    }

    func loadImage(assetIdentifier: String, targetSize: CGSize) async -> UIImage? {
        let key = NSString(string: "\(assetIdentifier)-full-\(targetSize.width)x\(targetSize.height)")
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            let image = AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier)
            if let image { cache.setObject(image, forKey: key) }
            return image
        }

        guard let asset = await fetchAsset(localIdentifier: assetIdentifier) else { return nil }

        let image = await requestHighQualityImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            resizeMode: .fast
        )
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
    
    /// Synchronously check if image is in cache (used to prevent flash of placeholder).
    func cachedThumbnail(assetIdentifier: String, targetSize: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let key = NSString(string: "\(assetIdentifier)-thumb-\(targetSize.width)x\(targetSize.height)")
        return cache.object(forKey: key)
    }
}
