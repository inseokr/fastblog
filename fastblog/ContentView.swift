//
//  ContentView.swift
//  Capper
//

import SwiftUI
import Photos
import UIKit

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
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @State private var showCaptureIntroSheet = false
    /// Day index to open when navigating to a blog via the new-moments popup.
    @AppStorage("blogify.justFinishedOnboarding") private var justFinishedOnboarding = false

    /// Per-identity flag for whether the Capture intro has been seen.
    private var captureIntroSeenForCurrentIdentity: Bool {
        let key: String
        if let userId = AuthService.shared.currentUser?.id {
            key = "blogify.captureIntroSeen.user.\(userId)"
        } else {
            key = "blogify.captureIntroSeen.guest"
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func markCaptureIntroSeenForCurrentIdentity() {
        let key: String
        if let userId = AuthService.shared.currentUser?.id {
            key = "blogify.captureIntroSeen.user.\(userId)"
        } else {
            key = "blogify.captureIntroSeen.guest"
        }
        UserDefaults.standard.set(true, forKey: key)
    }

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
                    onTapToBlog: handleTapToBlog
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
                        },
                        onNavigateToBlog: { sourceTripId in
                            if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId }) {
                                selectedCreatedRecap = blog
                            }
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

            // Trips overlay — added when user taps "Tap to Blog"; opacity-only fade (no slide).
            if showTrips || pendingShowTripsWhenIdle {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
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
        .animation(.easeInOut(duration: 0.35), value: showTrips)
        .animation(.easeInOut(duration: 0.25), value: selectedCreatedRecap != nil)
        .animation(.easeInOut(duration: 0.3), value: postCameraToastMessage != nil)
        .environmentObject(createdRecapStore)
        .environment(\.dismissToLanding, {
            dismissToLandingRequested = true
        })
        .sheet(isPresented: $showCaptureIntroSheet, onDismiss: {
            // Any dismissal (swipe down, tap outside, or Continue) counts as seen for this identity.
            markCaptureIntroSeenForCurrentIdentity()
        }) {
            captureIntroModalContent
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
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
        .onChange(of: showCameraFromHome) { _, isShowing in
            // Show first-time Capture intro when camera opens from home, once per identity.
            if isShowing, !captureIntroSeenForCurrentIdentity {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showCaptureIntroSheet = true
                }
            }
        }
    }

    // MARK: - Landing CTA handling

    private func handleTapToBlog() {
        // Limited access: first open the iOS photo picker, then run a full scan and show loading → Trips.
        if photoAuth.status == .limited {
            presentLimitedLibraryPickerFromLanding()
        } else {
            // Full access or not determined: keep existing flow.
            tripsViewModel.startDefaultScan()
            pendingShowTripsWhenIdle = true
        }
    }

    // MARK: - Capture Intro Pull-Up

    private var captureIntroModalContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                // Match the capture button icon used on the home page
                Image("SplashIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundColor(.white)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Capture Trip Moments")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Photos will be organized into your blogs.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showCaptureIntroSheet = false
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .preferredColorScheme(.dark)
    }

    private func presentLimitedLibraryPickerFromLanding() {
        DispatchQueue.main.async {
            guard let topVC = topViewControllerForPresentation() else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    photoAuth.refreshStatus()
                    // Trigger loading → Trips flow after the user confirms with the blue checkmark.
                    pendingShowTripsWhenIdle = true
                    tripsViewModel.startDefaultScan(forceFullScan: true)
                }
            }
        }
    }

    private func topViewControllerForPresentation() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}

#Preview {
    ContentView()
}
