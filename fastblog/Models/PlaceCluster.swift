//
//  PlaceCluster.swift
//  Capper
//

import Foundation
import CoreLocation

struct PlaceCluster: Identifiable, Equatable {
    let id: UUID
    var customTitle: String?
    var resolvedTitle: String  // "Finding place…" or geocoded name
    var subtitle: String       // e.g. "City, Country"
    var dateRange: String      // formatted date range
    var photoCount: Int
    var coverAssetIdentifier: String
    var assetIdentifiers: [String]
    var representativeLocation: CLLocation?  // for geocoding

    var displayTitle: String {
        customTitle ?? resolvedTitle
    }

    init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        resolvedTitle: String = "Finding place…",
        subtitle: String = "",
        dateRange: String = "",
        photoCount: Int,
        coverAssetIdentifier: String,
        assetIdentifiers: [String],
        representativeLocation: CLLocation? = nil
    ) {
        self.id = id
        self.customTitle = customTitle
        self.resolvedTitle = resolvedTitle
        self.subtitle = subtitle
        self.dateRange = dateRange
        self.photoCount = photoCount
        self.coverAssetIdentifier = coverAssetIdentifier
        self.assetIdentifiers = assetIdentifiers
        self.representativeLocation = representativeLocation
    }
}
