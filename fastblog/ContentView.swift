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
    @State private var showCameraFromHome = false
    @State private var postCameraToastMessage: String?
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
                    showCameraFromHome: $showCameraFromHome,
                    selectedCreatedRecap: $selectedCreatedRecap,
                    postCameraToastMessage: $postCameraToastMessage,
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
                .onChange(of: selectedCreatedRecap) { _, new in
                    if new != nil { showPlacesVisited = false }
                }
            }
            .opacity(showSeeAll || showPlacesVisited || showTrips || showCameraFromHome || selectedCreatedRecap != nil ? 0 : 1)

            // Camera overlay (fade in/out).
            if showCameraFromHome {
                NavigationStack {
                    CameraCaptureView(
                        tripsViewModel: tripsViewModel,
                        postDismissToast: { msg in
                            postCameraToastMessage = msg
                        },
                        onDismissOverlay: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showCameraFromHome = false
                            }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .transition(.opacity)
                .zIndex(2)
            }

            // My Blogs overlay (fade in/out). preferredColorScheme on container avoids color flash during dismiss.
            if showSeeAll {
                NavigationStack {
                    MyBlogsProfileView(
                        createdRecapStore: createdRecapStore,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
                        tripsViewModel: tripsViewModel,
                        onDismissCover: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSeeAll = false
                            }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .preferredColorScheme(.dark)
                .transition(.opacity)
                .zIndex(3)
            }

            // Places Visited overlay (fade in/out).
            if showPlacesVisited {
                NavigationStack {
                    PlacesVisitedStandaloneView(
                        selectedCreatedRecap: $selectedCreatedRecap,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showPlacesVisited = false
                            }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .transition(.opacity)
                .zIndex(4)
            }

            // Trips overlay (fade in/out instead of navigation push/pop swipe).
            if showTrips {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
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
            
            // Blog overlay: fade in/out when user selects a blog from anywhere (Map, Country List, Recent List).
            if let recap = selectedCreatedRecap {
                NavigationStack {
                    RecapBlogPageView(
                        blogId: recap.sourceTripId,
                        initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId),
                        initialDayIndex: initialDayIndexForRecap,
                        onRequestDismiss: {
                            initialDayIndexForRecap = nil
                            selectedCreatedRecap = nil
                        }
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
        .animation(.easeInOut(duration: 0.18), value: showCameraFromHome)
        .animation(.easeInOut(duration: 0.25), value: showSeeAll)
        .animation(.easeInOut(duration: 0.18), value: showPlacesVisited)
        .animation(.easeInOut(duration: 0.22), value: showTrips)
        .animation(.easeInOut(duration: 0.25), value: selectedCreatedRecap != nil)
        .animation(.easeInOut(duration: 0.3), value: postCameraToastMessage != nil)
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
