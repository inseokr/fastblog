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
    @State private var showSeeAll = false
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
                showSeeAll: $showSeeAll,
                selectedCreatedRecap: $selectedCreatedRecap,
                tripsViewModel: tripsViewModel
            )
            .navigationDestination(isPresented: $showTrips) {
                TripsView(viewModel: tripsViewModel, selectedCreatedRecap: $selectedCreatedRecap)
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView(selectedCreatedRecap: $selectedCreatedRecap)
                    .environmentObject(createdRecapStore)
            }
            .navigationDestination(isPresented: $showSeeAll) {
                MyBlogsProfileView(createdRecapStore: createdRecapStore, selectedCreatedRecap: $selectedCreatedRecap)
                    .environmentObject(createdRecapStore)
            }
            // Only push from Landing if we are staying on Landing (not showing Trips)
            .navigationDestination(isPresented: Binding(
                get: { selectedCreatedRecap != nil && !showTrips && !showProfile && !showSeeAll },
                set: { if !$0 { selectedCreatedRecap = nil } }
            )) {
                if let recap = selectedCreatedRecap {
                    RecapBlogPageView(
                        blogId: recap.sourceTripId,
                        initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
                    )
                }
            }
        }
        .environmentObject(createdRecapStore)
        .environment(\.dismissToLanding, {
            dismissToLandingRequested = true
        })
        .onChange(of: dismissToLandingRequested) { _, requested in
            if requested {
                dismissToLandingRequested = false
                // After blog creation, navigate to the new recap blog on top of TripsView
                // so back button returns to Trips page for creating more blogs
                if let latest = createdRecapStore.recents.first {
                    showTrips = true
                    selectedCreatedRecap = latest
                } else {
                    showTrips = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
