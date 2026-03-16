//
//  ContentView.swift
//  Capper
//

import SwiftUI

struct ContentView: View {
    @StateObject private var createdRecapStore = CreatedRecapBlogStore.shared
    @StateObject private var tripsViewModel: TripsViewModel
    @State private var showTrips = false
    /// When true, show Trips overlay when scan reaches .idle (so it fades in when ready).
    @State private var pendingShowTripsWhenIdle = false
    @State private var showProfile = false
    @State private var showSeeAll = false
    @State private var showPlacesVisited = false
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
                    showPlacesVisited: $showPlacesVisited,
                    selectedCreatedRecap: $selectedCreatedRecap,
                    tripsViewModel: tripsViewModel,
                    onTapToBlog: {
                        tripsViewModel.startDefaultScan()
                        pendingShowTripsWhenIdle = true
                    }
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
                .navigationDestination(isPresented: $showPlacesVisited) {
                    PlacesVisitedStandaloneView(
                        selectedCreatedRecap: $selectedCreatedRecap,
                        onDismiss: { showPlacesVisited = false }
                    )
                    .environmentObject(createdRecapStore)
                    .onDisappear { showPlacesVisited = false }
                    .onChange(of: selectedCreatedRecap) { _, new in
                        if new != nil { showPlacesVisited = false }
                    }
                }
            }

            // Trips overlay — added when user taps "Tap to Blog"; opacity-only fade (no slide).
            if showTrips || pendingShowTripsWhenIdle {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showTrips = false
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showTrips ? 1 : 0)
                .allowsHitTesting(showTrips)
                .animation(.easeInOut(duration: 0.35), value: showTrips)
                .zIndex(5)
                .transition(.identity)
            }
            
            // Blog overlay: fade in/out when user selects a blog from anywhere (Map, Country List, Recent List).
            if let recap = selectedCreatedRecap {
                NavigationStack {
                    RecapBlogPageView(
                        blogId: recap.sourceTripId,
                        initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId),
                        onRequestDismiss: { selectedCreatedRecap = nil }
                    )
                    .environmentObject(createdRecapStore)
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if tripsViewModel.scanState != .idle {
                LoadingScanView(
                    message: tripsViewModel.loadingMessage,
                    progress: tripsViewModel.defaultScanProgress > 0 ? tripsViewModel.defaultScanProgress : nil,
                    onCancel: {
                        tripsViewModel.cancelDefaultScan()
                        showTrips = false
                        pendingShowTripsWhenIdle = false
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .animation(.easeInOut(duration: 0.35), value: showTrips)
        .animation(.easeInOut(duration: 0.25), value: selectedCreatedRecap != nil)
        .environmentObject(createdRecapStore)
        .environment(\.dismissToLanding, {
            dismissToLandingRequested = true
        })
        .onChange(of: tripsViewModel.scanState) { _, newState in
            if newState == .idle && pendingShowTripsWhenIdle {
                pendingShowTripsWhenIdle = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    showTrips = true
                }
            }
        }
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
                    pendingShowTripsWhenIdle = true
                } else {
                    showTrips = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
