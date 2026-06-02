//
//  ContentView.swift
//  Capper
//

import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @StateObject private var createdRecapStore = CreatedRecapBlogStore.shared
    @EnvironmentObject private var nearbyShare: TripNearbyShareSessionController
    @StateObject private var tripsViewModel: TripsViewModel
    @State private var showTrips = false
    /// When true, show Trips overlay when scan reaches .idle (so it fades in when ready).
    @State private var pendingShowTripsWhenIdle = false
    /// Keeps the TripsView (and its MapKit Metal layer) in the tree for ~0.5 s after dismissal
    /// so the GPU can drain any in-flight command buffers before the CAMetalLayer is deallocated.
    /// Without this, .transition(.identity) removes the view immediately and Metal fires
    /// MTLDebugDevice notifyExternalReferencesNonZeroOnDealloc.
    @State private var tripsViewKeepMounted = false
    @State private var showSeeAll = false
    @State private var showPlacesVisited = false
    @State private var postCameraToastMessage: String?
    @State private var selectedCreatedRecap: CreatedRecapBlog?
    @State private var initialDayIndexForRecap: Int?
    @State private var initialScrollToStopIdForRecap: UUID?
    /// Set from My Blogs country list "Edit Blog" so `RecapBlogPageView` opens in edit mode.
    @State private var openRecapInEditMode = false
    /// Set from My Blogs country list "Share Blog" so the Share Your Blog sheet opens on the recap.
    @State private var openRecapPresentShareYourBlogSheet = false
    @State private var dismissToLandingRequested = false
    @State private var showNoPhotosAlert = false
    /// User dismissed the limited library picker without changing which photos are shared (e.g. tapped away).
    @State private var showLimitedPickerDismissedWithoutChangeAlert = false
    /// Enables the unchanged-selection prompt only after a prior limited scan found no trips.
    @State private var didSeeWeakResultOnLimitedScan = false
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    /// Day index to open when navigating to a blog via the new-moments popup.
    @AppStorage("blogify.justFinishedOnboarding") private var justFinishedOnboarding = false
    @State private var showSettingsFromNav = false

    init() {
        _tripsViewModel = StateObject(wrappedValue: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        rootContent
            .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
            .animation(.easeInOut(duration: 0.25), value: showSeeAll)
            .animation(.easeInOut(duration: 0.18), value: showPlacesVisited)
            .animation(.easeInOut(duration: 0.35), value: showTrips)
            .animation(.easeInOut(duration: 0.25), value: selectedCreatedRecap != nil)
            .animation(.easeInOut(duration: 0.3), value: postCameraToastMessage != nil)
            .alert("No Photos Selected", isPresented: $showNoPhotosAlert) {
                Button("Select Photos") {
                    presentLimitedLibraryPickerFromLanding()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please select at least one photo to create a travel blog.")
            }
            .alert("No additional photos selected for trip scanning", isPresented: $showLimitedPickerDismissedWithoutChangeAlert) {
                Button("Select More") {
                    presentLimitedLibraryPickerFromLanding()
                }
                Button("Cancel", role: .cancel) { }
                Button("Proceed", role: .cancel) {
                    pendingShowTripsWhenIdle = true
                    tripsViewModel.startDefaultScan(forceFullScan: true)
                }
            } message: {
                Text("Your shared photos did not change. Add more location photos, or proceed with the current selection.")
            }
            .environmentObject(createdRecapStore)
            .sheet(isPresented: $showSettingsFromNav) {
                SettingsView()
                    .environmentObject(AuthService.shared)
                    .environmentObject(photoAuth)
                    .environmentObject(createdRecapStore)
            }
            .sheet(isPresented: Binding(
                get: { nearbyShare.presentReceiveFromDeepLink },
                set: { new in
                    if !new { nearbyShare.dismissReceiveDeepLinkPresentation() }
                }
            )) {
                TripNearbyShareReceiveSheet(controller: nearbyShare)
            }
            .environment(\.dismissToLanding, {
                dismissToLandingRequested = true
            })
            .onChange(of: tripsViewModel.openTripsWhenCurrentDefaultScanFinishes) { _, shouldPrepare in
                if shouldPrepare {
                    pendingShowTripsWhenIdle = true
                }
            }
            .onChange(of: tripsViewModel.scanState) { _, newState in
                if newState == .idle && pendingShowTripsWhenIdle {
                    pendingShowTripsWhenIdle = false
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showTrips = true
                    }
                }
                if newState == .idle {
                    didSeeWeakResultOnLimitedScan = photoAuth.status == .limited && tripsViewModel.scanResultIsWeak
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
                        dismissTripsOverlay()
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

    private var rootContent: some View {
        ZStack {
            // Camera is the base layer (always mounted).
            NavigationStack {
                CameraCaptureView(
                    tripsViewModel: tripsViewModel,
                    postDismissToast: { msg in
                        postCameraToastMessage = msg
                    },
                    onDismissOverlay: nil,
                    onNavigateToBlog: { sourceTripId in
                        if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId }) {
                            selectedCreatedRecap = blog
                        }
                    },
                    onNavMyBlogs: {
                        withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = true }
                    },
                    onNavMyPlaces: {
                        withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = true }
                    }
                )
                .environmentObject(createdRecapStore)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .zIndex(1)

            // My Blogs overlay (fade in/out). preferredColorScheme on container avoids color flash during dismiss.
            if showSeeAll {
                NavigationStack {
                    MyBlogsProfileView(
                        createdRecapStore: createdRecapStore,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
                        openRecapInEditMode: $openRecapInEditMode,
                        openRecapPresentShareYourBlogSheet: $openRecapPresentShareYourBlogSheet,
                        tripsViewModel: tripsViewModel,
                        onDismissCover: nil,
                        onShowSettings: {
                            showSettingsFromNav = true
                        },
                        onNavCamera: {
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = false }
                        },
                        onNavMyPlaces: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSeeAll = false
                                showPlacesVisited = true
                            }
                        },
                        onTapToBlog: handleTapToBlog
                    )
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.primary)
                .preferredColorScheme(.dark)
                .transition(.opacity)
                .zIndex(3)
            }

            // Places Visited overlay (fade in/out).
            if showPlacesVisited {
                NavigationStack {
                    PlacesVisitedStandaloneView(
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
                        onDismiss: { withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = false } },
                        onShowSettings: { showSettingsFromNav = true },
                        onNavMyBlogs: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showPlacesVisited = false
                                showSeeAll = true
                            }
                        },
                        onNavCamera: {
                            withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = false }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.primary)
                .transition(.opacity)
                .zIndex(4)
            }

            // Trips overlay — added when user taps "Tap to Blog"; opacity-only fade (no slide).
            // tripsViewKeepMounted extends the lifetime after dismissal so MapKit's CAMetalLayer
            // can finish in-flight GPU work before the view is torn down.
            if showTrips || pendingShowTripsWhenIdle || tripsViewKeepMounted {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
                        onDismiss: dismissTripsOverlay
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
                        initialScrollToStopId: initialScrollToStopIdForRecap,
                        forceEditMode: openRecapInEditMode,
                        forcePresentShareYourBlogSheet: openRecapPresentShareYourBlogSheet,
                        onRequestDismiss: {
                            initialDayIndexForRecap = nil
                            initialScrollToStopIdForRecap = nil
                            openRecapInEditMode = false
                            openRecapPresentShareYourBlogSheet = false
                            selectedCreatedRecap = nil
                        }
                    )
                    // Fresh scroll/deep-link state per open; include stop id so repeat opens to another place work.
                    .id("\(recap.sourceTripId.uuidString)-\(initialScrollToStopIdForRecap?.uuidString ?? "none")")
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(10)
            }

            if tripsViewModel.scanState != .idle {
                LoadingScanView(
                    message: tripsViewModel.loadingMessage,
                    progress: tripsViewModel.defaultScanProgress,
                    onCancel: {
                        tripsViewModel.cancelDefaultScan()
                        pendingShowTripsWhenIdle = false
                        dismissTripsOverlay()
                    },
                    progressStepLabelOverride: { p in
                        p >= 0.9 ? "Almost done..." : "Please wait..."
                    },
                    useCenteredLayout: true
                )
                .transition(.identity)
                .zIndex(20)
            }

            // Post-camera toast banner (shown over camera base layer).
            if let toastMsg = postCameraToastMessage {
                postCameraToastBanner(message: toastMsg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(15)
            }
        }
    }

    // MARK: - Trips overlay lifecycle

    /// Fades out the Trips overlay and delays view removal so MapKit's Metal layer can drain
    /// in-flight GPU command buffers before the CAMetalLayer drawable is deallocated.
    private func dismissTripsOverlay() {
        tripsViewKeepMounted = true
        withAnimation(.easeInOut(duration: 0.3)) {
            showTrips = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !showTrips, !pendingShowTripsWhenIdle else { return }
            tripsViewKeepMounted = false
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

    private func presentLimitedLibraryPickerFromLanding() {
        DispatchQueue.main.async {
            guard let topVC = topViewControllerForPresentation() else { return }
            let photoCountBeforePicker = photoAuth.selectedPhotoCount
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    photoAuth.refreshStatus()
                    let countAfter = photoAuth.selectedPhotoCount
                    guard countAfter > 0 else {
                        showNoPhotosAlert = true
                        return
                    }
                    // Only show the unchanged-selection prompt after a weak limited scan; otherwise run the first scan attempt.
                    guard countAfter != photoCountBeforePicker else {
                        if didSeeWeakResultOnLimitedScan {
                            showLimitedPickerDismissedWithoutChangeAlert = true
                            return
                        }
                        pendingShowTripsWhenIdle = true
                        tripsViewModel.startDefaultScan(forceFullScan: true)
                        return
                    }
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

    private func postCameraToastBanner(message toastMsg: String) -> some View {
        VStack {
            HStack(spacing: 12) {
                Group {
                    if toastMsg.contains("added to") {
                        Image("MyBlogsIcon")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(.green)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
                Text(toastMsg)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation { postCameraToastMessage = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(appChromeBaseRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            Spacer()
        }
        .onChange(of: postCameraToastMessage) { _, msg in
            if msg != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        postCameraToastMessage = nil
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TripNearbyShareSessionController.shared)
}
