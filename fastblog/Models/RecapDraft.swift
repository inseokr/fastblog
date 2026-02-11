//
//  RecapDraft.swift
//  Capper
//

import Foundation

struct RecapDraft {
    var clusters: [PlaceCluster]
    var createdDate: Date

    init(clusters: [PlaceCluster] = [], createdDate: Date = Date()) {
        self.clusters = clusters
        self.createdDate = createdDate
    }
}
