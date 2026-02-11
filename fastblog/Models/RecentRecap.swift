//
//  RecentRecap.swift
//  Capper
//

import Foundation

struct RecentRecap: Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let createdAt: Date
    let coverImageName: String
    let tripId: UUID
    let selectedPhotoCount: Int

    init(id: UUID = UUID(), title: String, createdAt: Date, coverImageName: String, tripId: UUID, selectedPhotoCount: Int) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.coverImageName = coverImageName
        self.tripId = tripId
        self.selectedPhotoCount = selectedPhotoCount
    }
}
