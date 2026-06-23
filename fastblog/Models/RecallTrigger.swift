//
//  RecallTrigger.swift
//  Capper
//

import Photos
import Foundation

enum RecallType: String, Codable {
    case onThisDay
    case seasonal
    case cityRepeat
    case activeMonth
}

struct RecallTrigger: Identifiable {
    let id: UUID = UUID()
    let type: RecallType
    let title: String
    let subtitle: String
    let assets: [PHAsset]
    let date: Date
    
    // Metadata for the recall
    var cityName: String?
    /// In-app capture UUIDs for everyday-moment recalls (when `assets` is empty).
    var everydayCaptureIds: [UUID] = []
    var photoCount: Int { max(assets.count, everydayCaptureIds.count) }
    
    var thumbnailAssets: [PHAsset] {
        Array(assets.prefix(3))
    }
}
