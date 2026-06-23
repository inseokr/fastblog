//
//  EverydayPlaceCluster.swift
//  fastblog
//
//  Standalone place cluster for everyday moments (not nested under a blog).
//

import Foundation

struct EverydayPlaceCluster: Identifiable, Equatable, Codable, Hashable, Sendable {
    let id: UUID
    var placeTitle: String
    var placeSubtitle: String?
    var placeCategory: String?
    var representativeLocation: PhotoCoordinate?
    var captureIdentifiers: [String]
    var latestVisitDate: Date
    var noteText: String?

    init(
        id: UUID = UUID(),
        placeTitle: String,
        placeSubtitle: String? = nil,
        placeCategory: String? = nil,
        representativeLocation: PhotoCoordinate? = nil,
        captureIdentifiers: [String],
        latestVisitDate: Date,
        noteText: String? = nil
    ) {
        self.id = id
        self.placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.placeCategory = placeCategory
        self.representativeLocation = representativeLocation
        self.captureIdentifiers = captureIdentifiers
        self.latestVisitDate = latestVisitDate
        self.noteText = noteText
    }
}
