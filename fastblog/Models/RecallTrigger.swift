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
    var photoCount: Int { assets.count }
    
    var thumbnailAssets: [PHAsset] {
        Array(assets.prefix(3))
    }
}
