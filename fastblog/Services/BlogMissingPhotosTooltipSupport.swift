//
//  BlogMissingPhotosTooltipSupport.swift
//  fastblog
//

import Foundation
import Photos

/// Persists per-blog "Do not show again" for the missing-photos account tooltip.
enum MissingPhotosTooltipPresentationStore {
    private static let defaultsKey = "bloggo.missingPhotosTooltipSuppressedBlogIds"

    static func isSuppressed(blogId: UUID) -> Bool {
        let ids = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        return ids.contains(blogId.uuidString)
    }

    static func suppressPermanently(blogId: UUID) {
        var arr = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let s = blogId.uuidString
        if !arr.contains(s) { arr.append(s) }
        UserDefaults.standard.set(arr, forKey: defaultsKey)
    }
}

/// Detects blogs whose included photos cannot be loaded on this device (e.g. signed in on a new phone).
enum BlogMissingPhotosEvaluator {
    /// Whether to show education for signed-in account blogs with no usable photo media.
    static func shouldOfferTooltip(
        isSignedIn: Bool,
        ownerScope: OwnerScope?,
        detail: RecapBlogDetail,
        recapSummary: CreatedRecapBlog?,
        isSuppressedForBlog: Bool
    ) -> Bool {
        guard isSignedIn, !isSuppressedForBlog else { return false }
        guard ownerScope == .account else { return false }
        // With Limited Photos access, on-device camera shots may not be resolvable by localIdentifier.
        // Avoid falsely claiming photos are from another device in that permission mode.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return false }
        return blogHasMissingOrNoResolvablePhotos(detail: detail, recapSummary: recapSummary)
    }

    static func blogHasMissingOrNoResolvablePhotos(detail: RecapBlogDetail, recapSummary: CreatedRecapBlog?) -> Bool {
        let included = detail.allIncludedPhotos
        if included.isEmpty {
            let metaCount = recapSummary?.selectedPhotoCount ?? 0
            return metaCount > 0
        }
        return included.allSatisfy { !photoHasResolvableMedia($0) }
    }

    /// True when the blog can be shown on this device: no "phantom" selected-photo metadata, and every included photo loads from cloud URL or local storage.
    /// Used after sign-in / sync to drop stale rows from another device that only referenced that device's photo library or capture files.
    static func blogIsDisplayableOnThisDevice(detail: RecapBlogDetail, recapSummary: CreatedRecapBlog?) -> Bool {
        let included = detail.allIncludedPhotos
        if included.isEmpty {
            let metaCount = recapSummary?.selectedPhotoCount ?? 0
            return metaCount == 0
        }
        return included.allSatisfy { photoHasResolvableMedia($0) }
    }

    private static func photoHasResolvableMedia(_ photo: RecapPhoto) -> Bool {
        let cloud = (photo.cloudURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cloud.isEmpty { return true }

        guard let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty else {
            return false
        }
        if lid.hasPrefix(AppCapturePhotoService.prefix) {
            return AppCapturePhotoService.shared.imageExists(identifier: lid)
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [lid], options: nil)
        return fetch.firstObject != nil
    }
}
