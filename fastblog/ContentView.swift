//
//  ContentView.swift
//  Capper
//

import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    @State private var homeTab: BottomNavTab = .camera
    /// Immersive home camera hides the tab bar until the user taps the back chevron.
    @State private var isHomeBottomNavRevealed = false
    @State private var homeBottomNavAutoHideTask: Task<Void, Never>?
    private static let homeBottomNavAutoHideSeconds: UInt64 = 4
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
    /// My Places place viewer / share studio — hides the shared home tab bar.
    @State private var suppressHomeBottomNav = false

    // On-the-go new-moments banner (camera home)
    @State private var showNewMomentsBanner = false
    @State private var newMomentsBannerBlogTitle = ""
    @State private var newMomentsBannerBlogId: UUID?
    @State private var newMomentsBannerDayIndex: Int?
    @State private var newMomentsBannerDragOffset: CGFloat = 0
    @State private var postCameraToastDragOffset: CGFloat = 0

    /// Post-camera toast: sits just above the camera shutter controls (tab bar is outside `homeTabsLayer`).
    private var cameraHomeBannerBottomInset: CGFloat {
        HomeChromeMetrics.cameraCaptureControlsBottomInset(isCompactHeight: verticalSizeClass == .compact)
    }
    /// New moments banner: small lift from the bottom of the tab content area.
    private var newMomentsBannerBottomInset: CGFloat { 32 }

    init() {
        _tripsViewModel = StateObject(wrappedValue: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }

    var body: some View {
        rootContent
            .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
            .animation(.easeInOut(duration: 0.35), value: showTrips)
            .animation(.easeInOut(duration: 0.25), value: selectedCreatedRecap != nil)
            .animation(.easeInOut(duration: 0.3), value: postCameraToastMessage != nil)
            .animation(.easeInOut(duration: 0.3), value: showNewMomentsBanner)
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
                    considerPresentingNewMomentsBannerOnCamera()
                }
            }
            .onChange(of: selectedCreatedRecap?.sourceTripId) { _, sourceTripId in
                BlogMenuIndicatorStore.shared.focusedBlogSourceTripId = sourceTripId
                if let sourceTripId {
                    BlogMenuIndicatorStore.shared.clear(sourceTripId: sourceTripId)
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
                considerPresentingNewMomentsBannerOnCamera()
            }
            .onChange(of: isCameraHomeVisible) { _, visible in
                if visible {
                    considerPresentingNewMomentsBannerOnCamera()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showNewMomentsBanner = false
                        newMomentsBannerDragOffset = 0
                    }
                }
            }
    }

    private var rootContent: some View {
        VStack(spacing: 0) {
            homeTabsLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isHomeBottomNavVisible {
                BottomNavBar(
                    activeTab: homeTab,
                    onMyBlogs: { selectHomeTab(.myBlogs) },
                    onCamera: { selectHomeTab(.camera) },
                    onMyPlaces: { selectHomeTab(.myPlaces) }
                )
            }
        }
        .onChange(of: homeTab) { _, newTab in
            if newTab == .camera {
                isHomeBottomNavRevealed = false
            } else {
                cancelHomeBottomNavAutoHide()
            }
            if newTab != .myPlaces {
                suppressHomeBottomNav = false
            }
        }
        .onChange(of: isHomeBottomNavRevealed) { _, revealed in
            if revealed {
                scheduleHomeBottomNavAutoHide()
            } else {
                cancelHomeBottomNavAutoHide()
            }
        }
    }

    /// Tab stacks and overlays — lives in the area above the shared bottom navigation bar.
    private var homeTabsLayer: some View {
        ZStack {
            // Home tabs stay mounted (opacity) so the shared bottom nav never tears down / re-renders.
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
                    homeBottomNavRevealed: $isHomeBottomNavRevealed
                )
                .environmentObject(createdRecapStore)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .opacity(homeTab == .camera ? 1 : 0)
            .allowsHitTesting(homeTab == .camera)
            .zIndex(homeTab == .camera ? 1 : 0)

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
                        selectHomeTab(.camera)
                    },
                    onNavMyPlaces: {
                        selectHomeTab(.myPlaces)
                    },
                    onTapToBlog: handleTapToBlog
                )
                .environmentObject(createdRecapStore)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(.primary)
            .preferredColorScheme(.dark)
            .opacity(homeTab == .myBlogs ? 1 : 0)
            .allowsHitTesting(homeTab == .myBlogs)
            .zIndex(homeTab == .myBlogs ? 3 : 0)

            NavigationStack {
                PlacesVisitedStandaloneView(
                    selectedCreatedRecap: $selectedCreatedRecap,
                    initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
                    suppressHomeBottomNav: $suppressHomeBottomNav,
                    onDismiss: { selectHomeTab(.camera) },
                    onShowSettings: { showSettingsFromNav = true }
                )
                .environmentObject(createdRecapStore)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(.primary)
            .preferredColorScheme(.dark)
            .opacity(homeTab == .myPlaces ? 1 : 0)
            .allowsHitTesting(homeTab == .myPlaces)
            .zIndex(homeTab == .myPlaces ? 4 : 0)

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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(15)
            }

            // New moments from library scan — bottom banner on camera home.
            if showNewMomentsBanner {
                newMomentsCameraBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(14)
            }
        }
    }

    private var showsHomeChrome: Bool {
        !showTrips && !pendingShowTripsWhenIdle && selectedCreatedRecap == nil && tripsViewModel.scanState == .idle
    }

    /// Tab bar: hidden on default camera, My Places place viewer, and share studio; optional on camera after back chevron.
    private var isHomeBottomNavVisible: Bool {
        showsHomeChrome && !suppressHomeBottomNav && (homeTab != .camera || isHomeBottomNavRevealed)
    }

    private var isCameraHomeVisible: Bool {
        homeTab == .camera && showsHomeChrome
    }

    private func selectHomeTab(_ tab: BottomNavTab) {
        cancelHomeBottomNavAutoHide()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if tab == .camera {
                isHomeBottomNavRevealed = false
            }
            homeTab = tab
        }
    }

    private func scheduleHomeBottomNavAutoHide() {
        cancelHomeBottomNavAutoHide()
        homeBottomNavAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.homeBottomNavAutoHideSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard homeTab == .camera, isHomeBottomNavRevealed else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isHomeBottomNavRevealed = false
            }
        }
    }

    private func cancelHomeBottomNavAutoHide() {
        homeBottomNavAutoHideTask?.cancel()
        homeBottomNavAutoHideTask = nil
    }

    private func considerPresentingNewMomentsBannerOnCamera() {
        guard isCameraHomeVisible else { return }
        guard OnTheGoTripStore.hasNewMoments,
              let blogId = OnTheGoTripStore.activeBlogId,
              let title = OnTheGoTripStore.activeBlogTitle,
              createdRecapStore.visibleRecents.contains(where: { $0.sourceTripId == blogId }) else { return }
        newMomentsBannerBlogId = blogId
        newMomentsBannerBlogTitle = title
        newMomentsBannerDayIndex = OnTheGoTripStore.newMomentsDayIndex
        newMomentsBannerDragOffset = 0
        withAnimation(.easeInOut(duration: 0.3)) {
            showNewMomentsBanner = true
        }
    }

    private func dismissNewMomentsBannerLater() {
        OnTheGoTripStore.clearNewMoments()
        withAnimation(.easeOut(duration: 0.25)) {
            showNewMomentsBanner = false
            newMomentsBannerDragOffset = 0
        }
    }

    private func openNewMomentsBannerBlog() {
        let blogId = newMomentsBannerBlogId
        let photos = tripsViewModel.newlyScannedPhotos
        let fallbackDay = newMomentsBannerDayIndex
        withAnimation(.easeOut(duration: 0.25)) {
            showNewMomentsBanner = false
            newMomentsBannerDragOffset = 0
        }
        tripsViewModel.clearNewMomentsSignal()
        OnTheGoTripStore.clearNewMoments()
        guard let blogId,
              let recap = createdRecapStore.displayRecents.first(where: { $0.sourceTripId == blogId }) else { return }
        Task { @MainActor in
            await createdRecapStore.injectPhotosAndWait(
                photos,
                intoSourceTripId: blogId,
                notifyMenuIndicator: false
            )
            let detail = createdRecapStore.getBlogDetail(blogId: blogId)
            initialDayIndexForRecap = detail?.preferredDayIndexForNewMoments(
                from: photos,
                fallbackDayIndex: fallbackDay
            ) ?? fallbackDay
            selectedCreatedRecap = recap
        }
    }

    private var newMomentsCameraBanner: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.25))
                    Text("New moments found")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                Text("Photos in \"\(newMomentsBannerBlogTitle)\" since your last visit.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: openNewMomentsBannerBlog) {
                        Text("View")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button(action: dismissNewMomentsBannerLater) {
                        Text("Later")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(appChromeBaseRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, newMomentsBannerBottomInset)
            .shadow(color: .black.opacity(0.35), radius: 12, y: -4)
            .offset(y: newMomentsBannerDragOffset)
            .gesture(newMomentsBannerDismissDragGesture)
        }
        .allowsHitTesting(true)
    }

    private var newMomentsBannerDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                newMomentsBannerDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 72 || value.predictedEndTranslation.height > 120 {
                    dismissNewMomentsBannerLater()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        newMomentsBannerDragOffset = 0
                    }
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
        VStack(spacing: 0) {
            Spacer()
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
                    withAnimation {
                        postCameraToastMessage = nil
                        postCameraToastDragOffset = 0
                    }
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
            .padding(.bottom, cameraHomeBannerBottomInset)
            .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
            .offset(y: postCameraToastDragOffset)
            .gesture(postCameraToastDismissDragGesture)
        }
        .onChange(of: postCameraToastMessage) { _, msg in
            if msg != nil {
                postCameraToastDragOffset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        postCameraToastMessage = nil
                        postCameraToastDragOffset = 0
                    }
                }
            }
        }
    }

    private var postCameraToastDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                postCameraToastDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 72 || value.predictedEndTranslation.height > 120 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        postCameraToastMessage = nil
                        postCameraToastDragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        postCameraToastDragOffset = 0
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(TripNearbyShareSessionController.shared)
}
