//
//  PlaceDataExportManifest.swift
//  fastblog
//
//  Manifest schema for the "Export Places Data" zip (Places Visited → Manage → Export Places Data).
//

import Foundation

struct PlaceDataExportManifest: Codable, Equatable, Sendable {
    let exportedAt: Date
    let placeCount: Int
    let places: [PlaceDataExportEntry]
}

struct PlaceDataExportEntry: Codable, Equatable, Sendable {
    let id: String
    let placeName: String
    /// Human-readable category label (e.g. "Restaurant").
    let category: String
    /// Raw MapKit POI category (e.g. "MKPOICategoryRestaurant").
    let categoryRaw: String
    let latitude: Double
    let longitude: Double
    /// Capture timestamp of the exported photo.
    let timestamp: Date
    /// Path inside the archive, e.g. "photos/0001.jpg".
    let photoFileName: String
}
