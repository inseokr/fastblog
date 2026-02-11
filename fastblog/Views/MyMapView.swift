//
//  MyMapView.swift
//  Capper
//
//  Dedicated map screen (placeholder). Reached via "My Map" button on My Blogs.
//

import MapKit
import SwiftUI

struct MyMapView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?

    var body: some View {
        ProfileMapView(createdRecapStore: createdRecapStore, selectedCreatedRecap: $selectedCreatedRecap)
            .environmentObject(createdRecapStore)
    }
}
