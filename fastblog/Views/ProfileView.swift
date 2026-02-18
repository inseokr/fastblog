//
//  ProfileView.swift
//  Capper
//

import SwiftUI

/// My Blogs: dark blue background, country cards, fixed search bar and My Map button. Reused by Profile icon and See All from home.
struct ProfileView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var showTrips: Bool
    @Binding var showProfile: Bool
    @ObservedObject var tripsViewModel: TripsViewModel
    @Binding var selectedCreatedRecap: CreatedRecapBlog?

    var body: some View {
        MyBlogsProfileView(
            createdRecapStore: createdRecapStore,
            showTrips: $showTrips,
            showProfile: $showProfile,
            tripsViewModel: tripsViewModel,
            selectedCreatedRecap: $selectedCreatedRecap
        )
        .environmentObject(createdRecapStore)
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            showTrips: .constant(false),
            showProfile: .constant(true),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            selectedCreatedRecap: .constant(nil)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
