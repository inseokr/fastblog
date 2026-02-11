//
//  ProfileView.swift
//  Capper
//

import SwiftUI

/// My Blogs: dark blue background, country cards, fixed search bar and My Map button. Reused by Profile icon and See All from home.
struct ProfileView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?

    var body: some View {
        MyBlogsProfileView(createdRecapStore: createdRecapStore, selectedCreatedRecap: $selectedCreatedRecap)
            .environmentObject(createdRecapStore)
    }
}

#Preview {
    NavigationStack {
        ProfileView(selectedCreatedRecap: .constant(nil))
            .environmentObject(CreatedRecapBlogStore.shared)
    }
}
