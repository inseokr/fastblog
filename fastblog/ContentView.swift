//
//  ContentView.swift
//  Capper
//

import SwiftUI

struct ContentView: View {
    @StateObject private var createdRecapStore = CreatedRecapBlogStore.shared
    @StateObject private var tripsViewModel: TripsViewModel
    @State private var showTrips = false
    @State private var showProfile = false
    @State private var selectedCreatedRecap: CreatedRecapBlog?
    @State private var dismissToLandingRequested = false

    init() {
        _tripsViewModel = StateObject(wrappedValue: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        NavigationStack {
            LandingView(
                showTrips: $showTrips,
                showProfile: $showProfile,
                selectedCreatedRecap: $selectedCreatedRecap,
                tripsViewModel: tripsViewModel
            )
            .navigationDestination(isPresented: $showTrips) {
                TripsView(viewModel: tripsViewModel)
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView(
                    showTrips: $showTrips,
                    showProfile: $showProfile,
                    tripsViewModel: tripsViewModel,
                    selectedCreatedRecap: $selectedCreatedRecap
                )
                .environmentObject(createdRecapStore)
            }
            .navigationDestination(item: $selectedCreatedRecap) { recap in
                RecapBlogPageView(
                    blogId: recap.sourceTripId,
                    initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
                )
            }
        }
        .environmentObject(createdRecapStore)
        .environment(\.dismissToLanding, {
            dismissToLandingRequested = true
        })
        .onChange(of: dismissToLandingRequested) { _, requested in
            if requested {
                // After blog creation, navigate to the new recap blog
                if let latest = createdRecapStore.recents.first {
                    selectedCreatedRecap = latest
                } else {
                    showTrips = false
                    showProfile = false
                    selectedCreatedRecap = nil
                }
                dismissToLandingRequested = false // Reset the request
            }
        }
    }
}

#Preview {
    ContentView()
}
