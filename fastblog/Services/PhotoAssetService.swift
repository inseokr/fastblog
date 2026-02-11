//
//  PhotoAssetService.swift
//  Capper
//

import Foundation
import Photos
import UIKit

final class PhotoAssetService {
    static let shared = PhotoAssetService()

    private init() {}

    /// Resolve PhotosPickerItem identifiers to PHAsset instances.
    func fetchAssets(identifiers: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        // Preserve order by identifier
        return identifiers.compactMap { id in
            assets.first { $0.localIdentifier == id }
        }
    }
}
