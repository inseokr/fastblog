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
    @State private var initialDayIndexForRecap: Int?
    @State private var dismissToLandingRequested = false
    /// Day index to open when navigating to a blog via the new-moments popup.
    @AppStorage("blogify.justFinishedOnboarding") private var justFinishedOnboarding = false

    init() {
        _tripsViewModel = StateObject(wrappedValue: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                LandingView(
                    showTrips: $showTrips,
                    showProfile: $showProfile,
                    showSeeAll: $showSeeAll,
                    selectedCreatedRecap: $selectedCreatedRecap,
                    tripsViewModel: tripsViewModel
                )
                .navigationDestination(isPresented: $showProfile) {
                    ProfileView(selectedCreatedRecap: $selectedCreatedRecap)
                        .environmentObject(createdRecapStore)
                }
                .fullScreenCover(isPresented: $showSeeAll) {
                    NavigationStack {
                        MyBlogsProfileView(
                            createdRecapStore: createdRecapStore,
                            selectedCreatedRecap: $selectedCreatedRecap,
                            initialDayIndexForRecap: $initialDayIndexForRecap,
                            tripsViewModel: tripsViewModel,
                            onDismissCover: { showSeeAll = false }
                        )
                        .environmentObject(createdRecapStore)
                    }
                }
                // Only push from Landing if we are staying on Landing (not showing Trips)
                .navigationDestination(isPresented: Binding(
                    get: { selectedCreatedRecap != nil && !showTrips && !showProfile && !showSeeAll },
                    set: { if !$0 { selectedCreatedRecap = nil } }
                )) {
                    if let recap = selectedCreatedRecap {
                        RecapBlogPageView(
                            blogId: recap.sourceTripId,
                            initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId),
                        )
                    }
                }
            }

            // Trips overlay (fade in/out instead of navigation push/pop swipe).
            if showTrips {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showTrips = false
                            }
                        }
                    )
                }
                .transition(.opacity)
                .zIndex(5)
            }
            
            if tripsViewModel.scanState != .idle {
                LoadingScanView(
                    message: tripsViewModel.loadingMessage,
                    progress: tripsViewModel.defaultScanProgress > 0 ? tripsViewModel.defaultScanProgress : nil,
                    onCancel: {
                        tripsViewModel.cancelDefaultScan()
                        showTrips = false
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .animation(.easeInOut(duration: 0.22), value: showTrips)
        .environmentObject(createdRecapStore)
        .environment(\.dismissToLanding, {
            dismissToLandingRequested = true
        })
        .onChange(of: dismissToLandingRequested) { _, requested in
            if requested {
                dismissToLandingRequested = false
                // After blog creation, navigate to the new recap blog on top of TripsView
                // so back button returns to Trips page for creating more blogs.
                // Use a non-animated transaction so the blog appears instantly behind
                // the fullScreenCover instead of sliding in from the right.
                if let latest = createdRecapStore.displayRecents.first {
                    showTrips = true
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedCreatedRecap = latest
                    }
                } else {
                    showTrips = false
                }
            }
        }
        .onAppear {
            if justFinishedOnboarding {
                justFinishedOnboarding = false
                if tripsViewModel.tripDrafts.isEmpty {
                    tripsViewModel.startDefaultScan()
                }
                showTrips = true
            }
        }
    }
}

#Preview {
    ContentView()
}
