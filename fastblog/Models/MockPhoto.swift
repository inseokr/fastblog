//
//  MockPhoto.swift
//  Capper
//

import Foundation

struct MockPhoto: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var imageName: String  // SF Symbol name or placeholder id for gradient
    var timestamp: Date
    var locationName: String?
    /// Country from reverse geocoding (for Profile country grouping).
    var countryName: String?
    var isSelected: Bool
    /// When set, this photo is from the photo library; load image via ImageLoader using this identifier.
    var localIdentifier: String?
    /// When set (e.g. from PHAsset.location), used for place grouping and map.
    var location: PhotoCoordinate?

    init(id: UUID = UUID(), imageName: String, timestamp: Date, locationName: String? = nil, countryName: String? = nil, isSelected: Bool = false, localIdentifier: String? = nil, location: PhotoCoordinate? = nil) {
        self.id = id
        self.imageName = imageName
        self.timestamp = timestamp
        self.locationName = locationName
        self.countryName = countryName
        self.isSelected = isSelected
        self.localIdentifier = localIdentifier
        self.location = location
    }
}
