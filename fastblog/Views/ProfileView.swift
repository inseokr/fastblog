//
//  ProfileView.swift
//  Capper
//

import SwiftUI

/// My Blogs: dark blue background, country cards, fixed search bar and My Map button. Reused by Profile icon and See All from home.
struct ProfileView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @Binding var selectedCreatedRecap: CreatedRecapBlog?

    var body: some View {
        ProfilePageView(selectedCreatedRecap: $selectedCreatedRecap)
            .environmentObject(createdRecapStore)
            .environmentObject(authService)
    }
}

#Preview {
    NavigationStack {
        ProfileView(selectedCreatedRecap: .constant(nil))
            .environmentObject(CreatedRecapBlogStore.shared)
            .environmentObject(AuthService.shared)
    }
}
