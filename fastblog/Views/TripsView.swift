//
//  TripsView.swift
//  Capper
//

import AVFoundation
import CoreLocation
import MapKit
import Photos
import SwiftUI
import UIKit

struct TripsView: View {
    @ObservedObject var viewModel: TripsViewModel
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialDayIndexForRecap: Int?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)? = nil
    @StateObject private var photoAuth = PhotosAuthorizationManager()
    @AppStorage("blogify.skipSelectPhotosIntro") private var skipSelectPhotosIntro = false
    @State private var selectedTrip: TripDraft?
    @State private var createBlogFlowTrip: TripDraft?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var tripForPopup: TripDraft?
    @State private var selectedTripID: UUID?
    /// When true, skip the map-animate-to-trip in onChange (to avoid loop when map pan drives selection).
    @State private var suppressMapAnimation = false
    /// True after a scan completes with weak results while access is Limited — gates the top banner.
    @State private var showLimitedBannerAfterWeakScan = false
    #if DEBUG
    @State private var showDebugScanSheet = false
    #endif
    /// Show "Load more trips?" popup when user scrolls past the last trip.
    @State private var showLoadMorePopup = false
    /// Show "Load newer trips?" popup when user swipes past the first trip.
    @State private var showLoadNewerPopup = false
    /// Guards against the popup firing on the initial programmatic selection in onAppear.
    @State private var didCompleteInitialSelection = false
    /// True while the carousel is animating the map to a new trip — blocks onMapRegionChanged
    /// from firing back and jumping the scroll position mid-animation.
    @State private var isAnimatingMapFromCarousel = false
    /// Tracks the last known map region for zoom in/out controls.
    @State private var currentMapRegion: MKCoordinateRegion?
    /// (Unused after windowed paging — kept to avoid removing call sites; always 0 now.)
    @State private var tripCountBeforeOlderScan: Int = 0
    /// True when the blog creation flow was opened — tells the next scan completion to preserve scroll position.
    @State private var preserveScrollOnNextScan = false
    /// Fallback trip ID precomputed when blog creation starts (while the trip is still in allTrips).
    /// Used in the completion callback because createdRecapStore may have already filtered the trip
    /// out of allTrips by the time the callback fires, making removedTripIndex unreliable.
    @State private var nextTripIDAfterCreation: UUID? = nil
    /// Initial day index passed into TripDayPickerView — set to the latest day for new-moments
    /// navigation, 0 for all other navigation paths.
    @State private var tripInitialDayIndex: Int = 0
    /// Controls presentation of the in-app camera for on-the-go moments.
    @State private var showCameraCapture: Bool = false
    /// Set by scheduleScrollToLatestTripAfterPhotoSelection; onChange scrolls carousel to this trip when it appears.
    @State private var pendingScrollToTripID: UUID? = nil
    /// When true, after scan goes idle we select the latest trip (e.g. after user added photos via Limited picker).
    @State private var selectLatestTripWhenScanIdle = false
    /// Trip IDs that came from a photo-selection flow; show "new" badge on carousel until user interacts.
    @State private var newTripIDsFromPhotoSelection: Set<UUID> = []

    init(
        viewModel: TripsViewModel,
        selectedCreatedRecap: Binding<CreatedRecapBlog?>,
        initialDayIndexForRecap: Binding<Int?> = .constant(nil),
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedCreatedRecap = selectedCreatedRecap
        _initialDayIndexForRecap = initialDayIndexForRecap
        self.onDismiss = onDismiss
    }

    private var shouldShowSelectPhotosIntro: Bool {
        false
    }

    /// All visible trips sorted newest first — flat list for carousel.
    private var allTrips: [TripDraft] {
        viewModel.visibleDraftTripsNewestFirst
    }

    /// Restore the user's last visible selection when possible; otherwise fall back to the first trip.
    private func preferredTrip(from trips: [TripDraft]) -> TripDraft? {
        if let savedID = viewModel.lastSelectedVisibleTripID,
           let savedTrip = trips.first(where: { $0.id == savedID }) {
            return savedTrip
        }
        return trips.first
    }

    /// After photo selection, the list may not have updated when scanState goes idle. Schedule a delayed read of the list and set pendingScrollToTripID so we scroll once the list is populated.
    private func scheduleScrollToLatestTripAfterPhotoSelection() {
        let vm = viewModel
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000) // 0.45s for list to update
            let trips = vm.visibleDraftTripsNewestFirst
            guard let first = trips.first else { return }
            pendingScrollToTripID = first.id
        }
    }

    /// Find the trip whose coordinate is closest to a given map center point.
    private func closestTrip(to center: CLLocationCoordinate2D) -> TripDraft? {
        let tripsWithCoord = allTrips.compactMap { trip in
            trip.centerCoordinate.map { (trip, $0) }
        }
        guard !tripsWithCoord.isEmpty else { return nil }
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return tripsWithCoord.min(by: { a, b in
            let distA = centerLoc.distance(from: CLLocation(latitude: a.1.latitude, longitude: a.1.longitude))
            let distB = centerLoc.distance(from: CLLocation(latitude: b.1.latitude, longitude: b.1.longitude))
            return distA < distB
        })?.0
    }

    var body: some View {
        Group {
            if viewModel.scanState != .idle {
                LoadingScanView(
                    message: viewModel.loadingMessage,
                    isOverlay: false,
                    progress: nil,
                    onCancel: nil,
                    onUseCamera: {
                        viewModel.cancelDefaultScan()
                        showCameraCapture = true
                    },
                    onClose: {
                        viewModel.cancelDefaultScan()
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
                )
                .transition(.opacity)
            } else if shouldShowSelectPhotosIntro {
                SelectPhotosIntroView { dontShowAgain in
                    if dontShowAgain { skipSelectPhotosIntro = true }
                    viewModel.showSelectPhotosIntroAfterScan = false
                }
                .navigationTitle("Trips")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.scanState)
        .navigationDestination(item: $selectedTrip) { trip in
            TripDayPickerView(
                trip: viewModel.tripForPicker(trip),
                initialDayIndex: tripInitialDayIndex,
                onStartCreateBlog: { createBlogFlowTrip = $0 }
            )
        }
        .fullScreenCover(item: $createBlogFlowTrip) { trip in
            CreateBlogFlowView(trip: trip, startDirectlyCreating: true) { createdTripId in
                // Use the fallback precomputed when the flow opened. By the time this callback
                // fires, createdRecapStore has already added the blog so the trip is filtered
                // out of allTrips — making a live firstIndex lookup return nil and always
                // landing on index 0 (the newest trip).
                if selectedTripID == createdTripId {
                    let fallbackID = nextTripIDAfterCreation
                    let fallbackTrip = viewModel.visibleDraftTripsNewestFirst.first(where: { $0.id == fallbackID })
                                    ?? viewModel.tripDrafts.first(where: { $0.id == fallbackID })
                    selectedTripID = fallbackID
                    viewModel.lastSelectedVisibleTripID = fallbackID
                    if let center = fallbackTrip?.centerCoordinate {
                        let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                }
                viewModel.removeTrip(id: createdTripId)
                createBlogFlowTrip = nil
                selectedTrip = nil
            }
            .environmentObject(CreatedRecapBlogStore.shared)
        }
        .onChange(of: createBlogFlowTrip) { _, newTrip in
            if let trip = newTrip {
                preserveScrollOnNextScan = true
                // Snapshot the fallback position NOW while the trip is still in allTrips.
                let trips = allTrips
                if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
                    let remaining = trips.indices.filter { $0 != idx }.map { trips[$0] }
                    if !remaining.isEmpty {
                        nextTripIDAfterCreation = remaining[min(idx, remaining.count - 1)].id
                    } else {
                        nextTripIDAfterCreation = nil
                    }
                } else {
                    nextTripIDAfterCreation = nil
                }
            } else {
                nextTripIDAfterCreation = nil
            }
        }
        .sheet(isPresented: $viewModel.showFindMoreSheet) {
            FindMoreTripsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNewlyScannedSheet, onDismiss: {
            if viewModel.newMomentsSheetTriggeredByCreateButton {
                viewModel.dismissNewMomentsAndOpenPendingCreateFlow()
            } else {
                viewModel.clearNewMomentsSignal()
            }
        }) {
            NewlyScannedPhotosSheet(
                photos: viewModel.newlyScannedPhotos,
                matchedTrip: viewModel.newMomentsInExistingTrip,
                matchedBlog: viewModel.newMomentsMatchedBlog,
                onGoToTrip: {
                    viewModel.showNewlyScannedSheet = false
                    if let blog = viewModel.newMomentsMatchedBlog {
                        createdRecapStore.injectPhotos(
                            viewModel.newlyScannedPhotos,
                            intoSourceTripId: blog.sourceTripId
                        )
                    }
                    if let trip = viewModel.newMomentsInExistingTrip {
                        tripInitialDayIndex = viewModel.newMomentsLatestDayIndex
                        selectedTripID = trip.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedTrip = trip
                        }
                    }
                    viewModel.clearNewMomentsSignal()
                },
                onGoToBlog: {
                    viewModel.showNewlyScannedSheet = false
                    if let blog = viewModel.newMomentsMatchedBlog {
                        createdRecapStore.injectPhotos(
                            viewModel.newlyScannedPhotos,
                            intoSourceTripId: blog.sourceTripId
                        )
                        let newestPhoto = viewModel.newlyScannedPhotos.max(by: { $0.timestamp < $1.timestamp })
                        if let newestPhoto,
                           let detail = createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) {
                            let cal = Calendar.current
                            let dayStart = cal.startOfDay(for: newestPhoto.timestamp)
                            if let dayIdx = detail.days.firstIndex(where: { cal.startOfDay(for: $0.date) == dayStart }) {
                                initialDayIndexForRecap = dayIdx
                            }
                        }
                        let recap = createdRecapStore.visibleRecents.first(where: { $0.id == blog.id })
                        if let recap {
                            DispatchQueue.main.async {
                                selectedCreatedRecap = recap
                            }
                        }
                    }
                    viewModel.clearNewMomentsSignal()
                },
                onDismiss: {
                    viewModel.showNewlyScannedSheet = false
                    if viewModel.newMomentsSheetTriggeredByCreateButton {
                        viewModel.dismissNewMomentsAndOpenPendingCreateFlow()
                    } else {
                        viewModel.clearNewMomentsSignal()
                    }
                }
            )
            .presentationDetents([.fraction(0.72)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .onAppear { viewModel.onAppear() }
        .onChange(of: selectedCreatedRecap) { old, new in
            if new == nil && createdRecapStore.pendingRecapCreated {
                createdRecapStore.pendingRecapCreated = false
            }
        }
        .onChange(of: createdRecapStore.lastDiscardedTripId) { _, tripId in
            guard let tripId else { return }
            createdRecapStore.lastDiscardedTripId = nil
            // Scroll the carousel to the trip that just reappeared after the user discarded the blog.
            // Only set selectedTripID if the trip exists in allTrips to avoid crash when scrollPosition
            // references an ID not present in the list (e.g. camera-created blog, trip filtered out).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let tripExists = allTrips.contains(where: { $0.id == tripId })
                if tripExists {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedTripID = tripId
                    }
                    if let center = allTrips.first(where: { $0.id == tripId })?.centerCoordinate {
                        let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                }
            }
        }
        .overlay {
            if let trip = tripForPopup {
                blogCreationPopup(trip: trip)
            }
        }
        .overlay {
            if showLoadMorePopup && !viewModel.isLoadingOlderTrips {
                loadMoreTripsPopup
            }
        }
        .overlay {
            if showLoadNewerPopup && !viewModel.isLoadingNewerTrips {
                loadNewerTripsPopup
            }
        }
        .overlay {
            if viewModel.isLoadingOlderTrips {
                LoadingScanView(
                    message: "Finding older trips…",
                    isOverlay: true,
                    progress: viewModel.loadOlderProgress,
                    onCancel: {
                        viewModel.cancelLoadOlderTrips()
                        withAnimation(.easeOut(duration: 0.3)) { showLoadMorePopup = true }
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if viewModel.isLoadingNewerTrips {
                LoadingScanView(
                    message: "Finding newer trips…",
                    isOverlay: true,
                    progress: viewModel.loadNewerProgress,
                    onCancel: {
                        viewModel.cancelLoadNewerTrips()
                        withAnimation(.easeOut(duration: 0.3)) { showLoadNewerPopup = true }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.isLoadingOlderTrips)
        .animation(.easeInOut(duration: 0.4), value: viewModel.isLoadingNewerTrips)
        .navigationBarBackButtonHidden(true)
        // Older trips window loaded — dismiss popup and jump to newest of the older batch.
        .onChange(of: viewModel.olderTripsResult) { _, result in
            if case .success = result {
                withAnimation(.easeInOut(duration: 0.3)) { showLoadMorePopup = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let first = allTrips.first {
                        withAnimation(.easeInOut(duration: 0.45)) { selectedTripID = first.id }
                    }
                }
            } else if case .empty = result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.3)) { showLoadMorePopup = false }
                }
            }
        }
        // Newer trips window loaded — dismiss popup and jump to oldest (rightmost) of the newer batch,
        // which is chronologically closest to the older window the user came from.
        .onChange(of: viewModel.newerTripsResult) { _, result in
            if case .success = result {
                withAnimation(.easeInOut(duration: 0.3)) { showLoadNewerPopup = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let last = allTrips.last {
                        withAnimation(.easeInOut(duration: 0.45)) { selectedTripID = last.id }
                    }
                }
            } else if case .empty = result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.3)) { showLoadNewerPopup = false }
                }
            }
        }
        // When Create-blog check completes with no new photos (or user tapped "Later"), open the create flow.
        .onChange(of: viewModel.openCreateFlowForPendingTrip) { _, shouldOpen in
            guard shouldOpen, let trip = viewModel.pendingTripForCreateFlow else { return }
            createBlogFlowTrip = trip
            viewModel.clearPendingCreateFlow()
        }
        // Reset initial day index when trip detail view is dismissed normally.
        .onChange(of: selectedTrip) { _, newTrip in
            if newTrip == nil { tripInitialDayIndex = 0 }
        }
        // Find More scan completed — always land on the newest (latest-dated) trip.
        // Without this, the old selectedTripID is no longer valid in the refreshed trip list
        // and SwiftUI defaults the scroll position to the end of the carousel.
        .onChange(of: viewModel.findMoreScanResult) { _, result in
            if case .success = result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let newest = allTrips.first {
                        withAnimation(.easeInOut(duration: 0.45)) { selectedTripID = newest.id }
                        if let center = newest.centerCoordinate {
                            let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                        }
                    }
                }
            }
        }
        .onChange(of: viewModel.scanState) { oldState, newState in
            // #region agent log
            let _agentLog_payload_tv: [String: Any] = [
                "sessionId": "f5599d",
                "runId": "pre-fix",
                "hypothesisId": "H3",
                "location": "TripsView.swift:onChange(scanState)",
                "message": "TripsView scanState changed",
                "data": [
                    "oldState": String(describing: oldState),
                    "newState": String(describing: newState)
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if let _agentLog_data = try? JSONSerialization.data(withJSONObject: _agentLog_payload_tv) {
                // Write to local debug log file (may be no-op on device)
                let _agentLog_url = URL(fileURLWithPath: "/Users/justinseo/Desktop/fastblog/.cursor/debug-f5599d.log")
                if !FileManager.default.fileExists(atPath: _agentLog_url.path) {
                    FileManager.default.createFile(atPath: _agentLog_url.path, contents: nil, attributes: nil)
                }
                if let _agentLog_handle = try? FileHandle(forWritingTo: _agentLog_url) {
                    _agentLog_handle.seekToEndOfFile()
                    _agentLog_handle.write(_agentLog_data)
                    _agentLog_handle.write(Data([0x0a]))
                    try? _agentLog_handle.close()
                }
                // Also send to debug ingest endpoint so logs work from simulator/device
                if let url = URL(string: "http://127.0.0.1:7413/ingest/74888078-3f6a-4639-8372-d416f6cdf04c") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("f5599d", forHTTPHeaderField: "X-Debug-Session-Id")
                    request.httpBody = _agentLog_data
                    URLSession.shared.dataTask(with: request).resume()
                }
            }
            // #endregion agent log
        }
    }

    // MARK: - Main Content

    private var mainContentStack: some View {
        ZStack(alignment: .bottom) {
            mapViewLayer
            VStack(spacing: 0) {
                if photoAuth.status == .limited && showLimitedBannerAfterWeakScan {
                    limitedAccessHelper
                        .padding(.top, 60)
                }
                Spacer()
                bottomOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var mainContent: some View {
        mainContentStack
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                .opacity((showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips) ? 0 : 1)
                .disabled(showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showFindMoreSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .opacity((showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips) ? 0 : 1)
                .disabled(showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips)
            }
            // Scan Debug ladybug — hidden for now; set to DEBUG to show.
            #if false
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.runDebugScan()
                    showDebugScanSheet = true
                } label: {
                    Image(systemName: viewModel.isRunningDebugScan ? "arrow.clockwise.circle" : "ladybug")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                }
                .disabled(viewModel.isRunningDebugScan)
            }
            #endif
        }
        .overlay(alignment: .top) {
            if createdRecapStore.showDraftSavedToast {
                draftSavedToast
            }
        }
        // Scan Debug sheet — hidden for now; set to DEBUG to show.
        #if false
        .sheet(isPresented: $showDebugScanSheet) {
            ScanDebugSheet(info: viewModel.debugScanInfo, isLoading: viewModel.isRunningDebugScan)
                .onChange(of: viewModel.isRunningDebugScan) { _, loading in
                    // Sheet was opened immediately — keep it open and let it populate.
                    if !loading && viewModel.debugScanInfo == nil {
                        showDebugScanSheet = false
                    }
                }
        }
        #endif
        .onDisappear {
            createdRecapStore.showDraftSavedToast = false
        }
        .fullScreenCover(isPresented: $showCameraCapture) {
            NavigationStack {
                CameraCaptureView(
                    tripsViewModel: viewModel,
                    postDismissToast: nil,
                    onNavigateToBlog: { sourceTripId in
                        if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId }) {
                            selectedCreatedRecap = blog
                        }
                        showCameraCapture = false
                    }
                )
                .environmentObject(createdRecapStore)
            }
        }
        .onChange(of: showCameraCapture) { _, isShowing in
            // When camera dismisses, scroll to the trip with newly captured photos (if any).
            if !isShowing, let targetID = viewModel.pendingScrollToCameraTripID,
               allTrips.contains(where: { $0.id == targetID }) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    selectedTripID = targetID
                }
                viewModel.pendingScrollToCameraTripID = nil
                if let trip = allTrips.first(where: { $0.id == targetID }),
                   let center = trip.centerCoordinate {
                    let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                    mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
        .onChange(of: viewModel.pendingScrollToCameraTripID) { _, targetID in
            // Trip may be added async after user exits — scroll when it appears.
            guard let targetID, allTrips.contains(where: { $0.id == targetID }) else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedTripID = targetID
            }
            viewModel.pendingScrollToCameraTripID = nil
            if let trip = allTrips.first(where: { $0.id == targetID }),
               let center = trip.centerCoordinate {
                let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                mapPosition = .region(MKCoordinateRegion(center: center, span: span))
            }
        }
        // Surface the Limited banner only when scan finishes with weak results
        .onChange(of: viewModel.scanState) { oldState, newState in
            if oldState != .idle && newState == .idle {
                didCompleteInitialSelection = false
                if preserveScrollOnNextScan {
                    // Re-scan triggered by returning from blog flow — keep the user's scroll position.
                    preserveScrollOnNextScan = false
                } else {
                    let trips = allTrips
                    let afterPhotoSelection = selectLatestTripWhenScanIdle
                    if selectLatestTripWhenScanIdle {
                        selectLatestTripWhenScanIdle = false
                        // Scroll to the new trip after list has updated. Don't rely on onChange(list) — it can run before this handler, so we schedule a delayed scroll.
                        scheduleScrollToLatestTripAfterPhotoSelection()
                    }
                    let target: TripDraft? = afterPhotoSelection ? nil : preferredTrip(from: trips)
                    if let target = target {
                        withAnimation(.easeInOut(duration: 0.45)) { selectedTripID = target.id }
                        if let center = target.centerCoordinate {
                            let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                        }
                    }
                }
            }

            if newState == .idle && photoAuth.status == .limited && viewModel.scanResultIsWeak {
                withAnimation(.easeOut(duration: 0.4)) {
                    showLimitedBannerAfterWeakScan = true
                }
            } else if newState != .idle {
                // Hide banner while a new scan is running
                showLimitedBannerAfterWeakScan = false
            }
        }
        // Bi-directional sync: carousel scroll → map camera
        .onChange(of: selectedTripID) { _, newID in
            if newID != nil {
                viewModel.lastSelectedVisibleTripID = newID
            }
            // Skip popup on the initial programmatic selection that happens in onAppear.
            // Only real user carousel swipes (not map-pan or initial load) should trigger it.
            guard didCompleteInitialSelection else {
                didCompleteInitialSelection = true
                return
            }
            guard !suppressMapAnimation else {
                suppressMapAnimation = false
                return
            }
            guard let trip = allTrips.first(where: { $0.id == newID }),
                  let coord = trip.centerCoordinate else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Lock out map-region callbacks while we animate to prevent the intermediate
            // camera positions from bouncing the carousel back mid-swipe.
            isAnimatingMapFromCarousel = true
            withAnimation(.easeInOut(duration: 0.5)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                ))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                isAnimatingMapFromCarousel = false
            }
        }
    }

    // MARK: - Map Layer

    private var mapViewLayer: some View {
        TripsMapView(
            trips: allTrips,
            selectedTripID: $selectedTripID,
            mapPosition: $mapPosition,
            onTripTapped: { trip in
                if trip.id == selectedTripID {
                    viewModel.initiateCreateBlogFlow(trip: trip)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedTripID = trip.id
                    }
                }
            },
            onMapRegionChanged: { region in
                currentMapRegion = region
                // Don't interrupt a carousel-driven map animation — intermediate camera
                // positions would cause the scroll view to jump around.
                guard !isAnimatingMapFromCarousel else { return }
                // Don't let the map's initial auto-fit position override the programmatic selection.
                guard selectedTripID != nil else { return }
                // Find the trip closest to the map center
                let center = region.center
                guard let closest = closestTrip(to: center) else { return }
                guard closest.id != selectedTripID else { return }
                suppressMapAnimation = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedTripID = closest.id
                }
            }
        )
        .ignoresSafeArea()
        .onAppear {
            // Only set initial selection once — skip on re-appear (e.g. after fullScreenCover dismiss)
            guard selectedTripID == nil else { return }
            let trips = allTrips
            if let preferredTrip = preferredTrip(from: trips) {
                selectedTripID = preferredTrip.id

                // Restore the last visible trip when possible; otherwise use the newest trip.
                if let center = preferredTrip.centerCoordinate {
                    let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                    mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
        // Handle the case where trips arrive after onAppear (scan data published after scanState flips to idle)
        .onChange(of: viewModel.visibleDraftTripsNewestFirst) { _, newTrips in
            guard selectedTripID == nil, let preferredTrip = preferredTrip(from: newTrips) else { return }
            selectedTripID = preferredTrip.id
            if let center = preferredTrip.centerCoordinate {
                let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                mapPosition = .region(MKCoordinateRegion(center: center, span: span))
            }
        }
        // After photo selection: delayed scroll to latest trip (pendingScrollToTripID set by scheduleScrollToLatestTripAfterPhotoSelection)
        .onChange(of: pendingScrollToTripID) { (_: UUID?, id: UUID?) in
            guard let id else { return }
            let trips = viewModel.visibleDraftTripsNewestFirst
            guard let trip = trips.first(where: { $0.id == id }) else {
                pendingScrollToTripID = nil
                return
            }
            newTripIDsFromPhotoSelection = Set(trips.map(\.id))
            withAnimation(.easeInOut(duration: 0.45)) { selectedTripID = id }
            if let center = trip.centerCoordinate {
                mapPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)))
            }
            pendingScrollToTripID = nil
        }
    }


    // MARK: - Dynamic Month Title

    private var currentMonthTitle: String {
        guard let id = selectedTripID,
              let trip = allTrips.first(where: { $0.id == id }),
              let date = trip.earliestDate else {
            // Fallback to first trip
            if let first = allTrips.first, let date = first.earliestDate {
                return Self.monthYearFormatter.string(from: date)
            }
            return ""
        }
        return Self.monthYearFormatter.string(from: date)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale.current
        return f
    }()

    // MARK: - Bottom Overlay (Carousel + CTA)

    private var bottomOverlay: some View {
        VStack(spacing: 14) {
            if allTrips.isEmpty {
                emptyState
            } else {
                // Dynamic month header
                if !currentMonthTitle.isEmpty {
                    Text(currentMonthTitle.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: currentMonthTitle)
                }
                tripCarousel
            }
            findMoreTripsButton
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.45), Color.black.opacity(0.65), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -60) // extend shadow well above the month header
            .ignoresSafeArea(.container, edges: .bottom) // extend all the way to screen bottom
            .allowsHitTesting(false)
        )
    }

    // MARK: - Horizontal Trip Carousel

    private var tripCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(allTrips) { trip in
                    TripCarouselCard(
                        trip: trip,
                        isSelected: trip.id == selectedTripID,
                        showNewBadge: newTripIDsFromPhotoSelection.contains(trip.id),
                        onTap: {
                            if trip.id == selectedTripID {
                                // Already centered — check for new photos, then open blog creation
                                viewModel.initiateCreateBlogFlow(trip: trip)
                            } else {
                                // Not centered yet — just snap it into focus
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    selectedTripID = trip.id
                                }
                            }
                        }
                    )
                    .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 16)
                    .scrollTransition(.animated(.spring(response: 0.35, dampingFraction: 0.8))) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1.0 : 0.55)
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                            .offset(y: phase.isIdentity ? 0 : 8)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedTripID, anchor: .leading)
        .contentMargins(.horizontal, 24)
        .frame(height: 240)
        // Detect swipes past either end of the carousel.
        // • Left-swipe on last card   → "Load older trips" (or same popup when only one trip)
        // • Right-swipe on first card → "Load newer trips" when multiple trips; when only one trip, show load-more popup (Allow Full Access / Select More Photos / Cancel for limited)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let isLeftwardDrag  = value.translation.width < -40
                    let isRightwardDrag = value.translation.width >  40

                    if isLeftwardDrag,
                       selectedTripID == allTrips.last?.id,
                       allTrips.count > 1,
                       !viewModel.isLoadingOlderTrips,
                       !showLoadMorePopup {
                        withAnimation(.easeOut(duration: 0.3)) { showLoadMorePopup = true }
                    }

                    if isRightwardDrag,
                       selectedTripID == allTrips.first?.id,
                       !viewModel.isLoadingNewerTrips,
                       !showLoadNewerPopup {
                        if allTrips.count == 1 {
                            // Single trip: show load-more popup (limited users get Allow Full Access / Select More Photos / Cancel)
                            withAnimation(.easeOut(duration: 0.3)) { showLoadMorePopup = true }
                        } else if viewModel.canLoadNewerTrips {
                            withAnimation(.easeOut(duration: 0.3)) { showLoadNewerPopup = true }
                        }
                    }
                }
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(viewModel.hasPerformedCustomScan ? "No trips found in this range" : "No trips found in the last 90 days")
                    .font(.headline)
                    .foregroundColor(.white)
                if photoAuth.status == .limited {
                    Text("Limited photo access may be hiding some trips.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                } else {
                    Text("Try scanning a different date range")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Swipe hint
            HStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.caption)
                Text("Swipe to load more")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let isHorizontalSwipe = abs(value.translation.width) > 40
                    if isHorizontalSwipe, !showLoadMorePopup {
                        withAnimation(.easeOut(duration: 0.3)) { showLoadMorePopup = true }
                    }
                }
        )
    }

    // MARK: - Find More Trips CTA

    private var findMoreTripsButton: some View {
        Button {
            if photoAuth.status == .limited {
                presentLimitedLibraryPicker()
            } else {
                viewModel.openFindMoreSheet()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: photoAuth.status == .limited ? "photo.badge.plus" : "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                Text(photoAuth.status == .limited ? "Select More Photos" : "Find More New Blogs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.40, blue: 0.78),
                                Color(red: 0.25, green: 0.35, blue: 0.72)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
            .shadow(color: Color(red: 0.2, green: 0.35, blue: 0.7).opacity(0.15), radius: 10, y: 2)
        }
    }

    // MARK: - Limited Access Helper (top banner — Trigger 1, weak scan results)

    private var limitedAccessHelper: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .foregroundColor(.white)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Not finding your trip?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Limited access — add more photos to find more trips.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer()

            Button {
                presentLimitedLibraryPicker()
            } label: {
                Text("Add Photos")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController) { _ in
            DispatchQueue.main.async {
                photoAuth.refreshStatus()
                withAnimation { showLimitedBannerAfterWeakScan = false }
                selectLatestTripWhenScanIdle = true
            }
            // Give the Photos library a moment to expose newly selected assets before we scan
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                viewModel.startDefaultScan(forceFullScan: true)
            }
        }
    }

    // MARK: - Toast

    private var draftSavedToast: some View {
        HStack(spacing: 12) {
            Image("MyBlogsIcon")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.green)
                .frame(width: 28, height: 28)
            Text("Saved as draft")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation { createdRecapStore.showDraftSavedToast = false }
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
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .zIndex(100)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            withAnimation {
                createdRecapStore.showDraftSavedToast = false
            }
        }
    }

    // MARK: - Blog Creation Popup

    private func blogCreationPopup(trip: TripDraft) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { tripForPopup = nil }
                }

            VStack(spacing: 20) {
                Text("Create Recap Blog")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Would you like to turn \"\(trip.defaultBlogTitle)\" into a blog?")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    Button {
                        withAnimation { tripForPopup = nil }
                    } label: {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }

                    Button {
                        withAnimation { tripForPopup = nil }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            createBlogFlowTrip = trip
                        }
                    } label: {
                        Text("Create")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(200)
    }

    // MARK: - Load More Trips Popup

    private var loadMoreTripsPopup: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showLoadMorePopup = false }
                }

            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)

                Text("Load older trips?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Shown after a scan returns with no results
                if viewModel.olderTripsResult == .empty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text("No more trips found in this period.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }

                VStack(spacing: 10) {
                    if photoAuth.status == .limited {
                        // Limited access — offer to upgrade or select more photos
                        Button {
                            withAnimation { showLoadMorePopup = false }
                            openSettings()
                        } label: {
                            Text("Allow Full Access")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }

                        Button {
                            withAnimation { showLoadMorePopup = false }
                            presentLimitedLibraryPicker()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Select More Photos")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                        }
                    } else {
                        // Full access — one tap starts the scan automatically
                        Button {
                            withAnimation { showLoadMorePopup = false }
                            viewModel.loadOlderTrips()
                        } label: {
                            Text("Yes, load more")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        // Disable while a scan result is already displayed (user should dismiss first)
                        .disabled(viewModel.olderTripsResult == .empty)
                    }

                    Button {
                        withAnimation { showLoadMorePopup = false }
                    } label: {
                        Text("Not now")
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.25), value: viewModel.olderTripsResult)
            }
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(200)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Load Newer Trips Popup

    private var loadNewerTripsPopup: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showLoadNewerPopup = false }
                }

            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
                    .scaleEffect(x: -1) // mirror to face forward in time

                Text("Load newer trips?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Shown after a scan returns with no results
                if viewModel.newerTripsResult == .empty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text("No trips found in this period.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation { showLoadNewerPopup = false }
                        viewModel.loadNewerTrips()
                    } label: {
                        Text("Yes")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(viewModel.newerTripsResult == .empty)

                    Button {
                        withAnimation { showLoadNewerPopup = false }
                    } label: {
                        Text("Not now")
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.25), value: viewModel.newerTripsResult)
            }
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(200)
    }
}

// MARK: - CameraCaptureView & Camera Preview

/// One captured photo in the current camera session.
struct CapturedMoment: Identifiable {
    let id: UUID
    let localIdentifier: String?
    let timestamp: Date
    var caption: String?
    /// In-memory preview image used only for the in-app camera session.
    var previewImage: UIImage?
    /// When this moment was injected into a blog or draft, the injected photo's UUID (for removal if user trashes from modal).
    var injectedPhotoId: UUID?
    /// Capture location (for grouping by place when counting moments).
    var location: PhotoCoordinate?

    init(
        id: UUID = UUID(),
        localIdentifier: String?,
        timestamp: Date = Date(),
        caption: String? = nil,
        previewImage: UIImage? = nil,
        injectedPhotoId: UUID? = nil,
        location: PhotoCoordinate? = nil
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.timestamp = timestamp
        self.caption = caption
        self.previewImage = previewImage
        self.injectedPhotoId = injectedPhotoId
        self.location = location
    }
}

/// Simple AVFoundation camera controller that owns the capture session.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "bloggo.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let locationManager = CLLocationManager()
    private var videoDevice: AVCaptureDevice?

    private var captureCompletion: ((UIImage?, String?) -> Void)?

    @Published var isConfigured = false
    @Published var authorizationDenied = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    /// Current location for embedding in captured photos. Updated when camera runs.
    @Published private(set) var currentLocation: CLLocation?
    /// Current camera position (back or front).
    @Published private(set) var position: AVCaptureDevice.Position = .back
    /// Flash mode for next capture.
    @Published var flashMode: AVCaptureDevice.FlashMode = .off

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        configureSession()
    }

    /// Handles permission flow and kicks off session configuration on a dedicated queue.
    private func configureSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupSession(position: .back)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.setupSession(position: .back)
                } else {
                    DispatchQueue.main.async {
                        self.authorizationDenied = true
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.authorizationDenied = true
            }
        }
    }

    /// Performs all session configuration on the session queue.
    private func setupSession(position: AVCaptureDevice.Position) {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                    DispatchQueue.main.async { self.authorizationDenied = true }
                    self.session.commitConfiguration()
                    return
                }
                self.videoDevice = device
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                DispatchQueue.main.async {
                    self.position = position
                }
            } catch {
                DispatchQueue.main.async { self.authorizationDenied = true }
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.isConfigured = true
            }
        }
    }

    /// Switch between front and back camera.
    func flipCamera() {
        let nextPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async {
            self.session.beginConfiguration()
            if let currentInput = self.session.inputs.first as? AVCaptureDeviceInput {
                self.session.removeInput(currentInput)
            }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: nextPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.session.commitConfiguration()
            self.videoDevice = device
            DispatchQueue.main.async {
                self.position = nextPosition
                self.isConfigured = true
            }
        }
    }

    /// Cycle flash: off → on → auto (back camera only; front has no flash).
    func cycleFlashMode() {
        guard position == .back else { return }
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }

    /// Capture a single still photo. The completion is called on the main queue.
    func capturePhoto(completion: @escaping (UIImage?, String?) -> Void) {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let settings = AVCapturePhotoSettings()
            if self.videoDevice?.hasFlash == true {
                settings.flashMode = self.flashMode
            }
            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Clamps and applies a zoom factor to the active camera device.
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            let clamped = max(1.0, min(factor, device.maxAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async {
                self.zoomFactor = clamped
            }
        }
    }

    func startRunning() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        startLocationUpdatesIfAuthorized()
    }

    func stopRunning() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        locationManager.stopUpdatingLocation()
    }

    private func startLocationUpdatesIfAuthorized() {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let completion = captureCompletion
        captureCompletion = nil

        guard error == nil else {
            DispatchQueue.main.async {
                completion?(nil, nil)
            }
            return
        }

        let data = photo.fileDataRepresentation()
        let image = data.flatMap { UIImage(data: $0) }

        DispatchQueue.main.async {
            completion?(image, nil)
        }
    }
}

extension CameraController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last, location.horizontalAccuracy >= 0 {
            DispatchQueue.main.async {
                self.currentLocation = location
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.currentLocation = nil
        }
    }
}


/// UIKit-backed preview layer for the capture session.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        return CameraPreviewContainer(session: session)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let container = uiView as? CameraPreviewContainer else { return }
        container.updateSession(session)
    }
}

/// UIView that owns an AVCaptureVideoPreviewLayer and keeps it sized to its bounds.
private final class CameraPreviewContainer: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    func updateSession(_ session: AVCaptureSession) {
        previewLayer.session = session
    }
}

/// Camera UI that shows a live preview and session counter. Moment plumbing is added separately.
struct CameraCaptureView: View {
    @ObservedObject var tripsViewModel: TripsViewModel
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss
    /// When set, receives the summary message (e.g. "3 moments added to Trip") when user leaves with attached photos.
    var postDismissToast: ((String) -> Void)? = nil
    /// When set (ZStack overlay presentation), called instead of dismiss().
    var onDismissOverlay: (() -> Void)? = nil
    /// When set, "View" in the blog-started modal will call this with the blog's sourceTripId so the parent can open that blog and dismiss the camera.
    var onNavigateToBlog: ((UUID) -> Void)? = nil

    @StateObject private var cameraController = CameraController()

    /// Photos captured in this camera session only (for "new trip" flow; used for gallery).
    @State private var sessionMoments: [CapturedMoment] = []
    /// All captures this session with preview images — for the pull-up when photos went to blog/draft (same style as session gallery).
    @State private var sessionCapturesForDisplay: [CapturedMoment] = []
    /// Total photos captured this session (all routes) — used for bottom-right counter.
    @State private var photosCapturedThisSession: Int = 0
    @State private var isShowingSessionGallery = false
    @State private var flashOpacity: Double = 0
    @State private var toastMessage: String?
    @State private var isShowingToast: Bool = false
    @State private var attachedCountThisSession: Int = 0
    /// Trip/blog name that received photos this session, for the exit toast.
    @State private var sessionTripTitle: String? = nil
    /// When adding to an existing blog, the blog's sourceTripId (so we can remove photo if user trashes from modal).
    @State private var sessionSourceTripId: UUID? = nil
    /// When adding to a camera draft, the draft's tripId (so we can remove photo if user trashes from modal).
    @State private var sessionDraftTripId: UUID? = nil
    @State private var hasOfferedStartBlogThisSession: Bool = false
    @State private var hasReportedDismissToast: Bool = false
    /// When true, show the "Blog has started, your moments will be saved to [name]" modal with Ok / View.
    @State private var showBlogStartedPrompt: Bool = false
    /// When capture is near home, show confirmation before adding. Pending (image, timestamp) to add if user taps Keep.
    @State private var showNearHomeConfirmation: Bool = false
    @State private var pendingNearHomeCapture: (image: UIImage, timestamp: Date)?
    @State private var nearHomeDoNotShowAgain: Bool = false
    /// When true, show the In-app Photo Gallery (all photos taken with in-app camera).
    @State private var isShowingInAppGallery = false
    @AppStorage("bloggo.hasSeenCameraTooltip") private var hasSeenCameraTooltip = false
    @State private var showCameraTooltip = false
    // Zoom
    @State private var zoomBaseScale: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    @State private var zoomIndicatorTask: Task<Void, Never>? = nil

    private static let nearHomeAlertSuppressedKey = "bloggo.nearHomeAlertSuppressed"
    private static let nearHomeSuppressedPreferKeepKey = "bloggo.nearHomeSuppressedPreferKeep"

    var body: some View {
        ZStack {
            // Full-screen camera preview as the base layer
            Group {
                if cameraController.authorizationDenied {
                    Color.black
                        .ignoresSafeArea()
                } else if cameraController.isConfigured {
                    CameraPreviewView(session: cameraController.session)
                        .ignoresSafeArea()
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newZoom = max(1.0, min(zoomBaseScale * value, 10.0))
                                    cameraController.setZoomFactor(newZoom)
                                    showZoomIndicator = true
                                    zoomIndicatorTask?.cancel()
                                }
                                .onEnded { value in
                                    zoomBaseScale = max(1.0, min(zoomBaseScale * value, 10.0))
                                    zoomIndicatorTask = Task {
                                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                                        guard !Task.isCancelled else { return }
                                        await MainActor.run { showZoomIndicator = false }
                                    }
                                }
                        )
                } else {
                    Color.black
                        .ignoresSafeArea()
                }
            }

            // Overlay UI (shutter + status) on top of preview
            VStack {
                Spacer()
                if cameraController.authorizationDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 34, weight: .semibold))
                        Text("Enable camera access in Settings to capture moments.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 24)
                } else if !cameraController.isConfigured {
                    ProgressView("Preparing camera…")
                        .tint(.white)
                        .foregroundColor(.white)
                        .padding(.bottom, 24)
                }
                shutterBar
                    .padding(.bottom, 24)
            }

            // Zoom level indicator — appears while pinching, fades out
            if showZoomIndicator {
                VStack {
                    Text(String(format: "%.1f×", cameraController.zoomFactor))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .transition(.opacity)
                    Spacer()
                }
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.2), value: showZoomIndicator)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height < -50 {
                        isShowingInAppGallery = true
                    }
                }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    closeCamera()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        cameraController.cycleFlashMode()
                    } label: {
                        Image(systemName: flashIconName)
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(flashAccessibilityLabel)
                    .disabled(cameraController.position == .front)
                    Button {
                        cameraController.flipCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Flip camera")
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .overlay(
            Rectangle()
                .fill(Color.white)
                .opacity(flashOpacity)
                .ignoresSafeArea()
        )
        .overlay(alignment: .bottomLeading) {
            Button {
                isShowingInAppGallery = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Bloggo Photos")
            .padding(.leading, 16)
            .padding(.bottom, 33)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isShowingSessionGallery = true
            } label: {
                let previewSize: CGFloat = 56
                let effectiveList = sessionMoments.isEmpty ? sessionCapturesForDisplay : sessionMoments
                let displayCount = effectiveList.count
                let latestImage = effectiveList.last?.previewImage
                ZStack {
                    if let image = latestImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: previewSize, height: previewSize)
                            .clipped()
                            .cornerRadius(10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: previewSize, height: previewSize)
                    }
                    // Camera icon and count (only when there are photos)
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                        if displayCount > 0 {
                            Text("\(displayCount)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .frame(width: previewSize, height: previewSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                )
            }
            .padding(.trailing, 16)
            .padding(.bottom, 33)
        }
        .overlay(alignment: .top) {
            if let message = toastMessage, isShowingToast {
                HStack(spacing: 12) {
                    Group {
                        if message == "Blog has started" || message.contains("added to") {
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
                    Text(message)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                .padding(.top, 72)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            // Fresh session each time camera is opened.
            sessionMoments = []
            sessionCapturesForDisplay = []
            photosCapturedThisSession = 0
            attachedCountThisSession = 0
            sessionTripTitle = nil
            sessionSourceTripId = nil
            sessionDraftTripId = nil
            if !hasSeenCameraTooltip {
                showCameraTooltip = true
            }
            if cameraController.isConfigured {
                cameraController.startRunning()
            }
        }
        .onChange(of: cameraController.isConfigured) { _, configured in
            if configured {
                cameraController.startRunning()
            }
        }
        .onDisappear {
            cameraController.stopRunning()
            // Sync any captions typed in the gallery into the blog for real-time injected photos.
            syncSessionCaptionsToBlog()
            // If user swipes away with unsaved session moments (e.g. closed before blog creation completed), save as draft.
            if !sessionMoments.isEmpty && attachedCountThisSession == 0 {
                saveSessionAsTripDraftOnly()
            }
            // Exit toast: when adding to a blog, show "X moment(s) saved for [Blog Name]".
            if !hasReportedDismissToast {
                let title = sessionTripTitle ?? OnTheGoTripStore.activeBlogTitle ?? "your trip"
                let countToBlog = sessionSourceTripId != nil
                    ? momentCount(from: sessionCapturesForDisplay)
                    : max(attachedCountThisSession, photosCapturedThisSession)
                if sessionSourceTripId != nil && countToBlog > 0 {
                    hasReportedDismissToast = true
                    let count = countToBlog
                    let msg = "\(count) moment\(count == 1 ? "" : "s") saved for \(title)"
                    postDismissToast?(msg)
                } else if attachedCountThisSession > 0 {
                    hasReportedDismissToast = true
                    let msg = "\(attachedCountThisSession) moment\(attachedCountThisSession == 1 ? "" : "s") added to \(title)"
                    postDismissToast?(msg)
                }
            }
        }
        .sheet(isPresented: $showCameraTooltip, onDismiss: {
            hasSeenCameraTooltip = true
        }) {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("Capture moments for your trip")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        Text("Photos taken here will appear in your blog.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    showCameraTooltip = false
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 24)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingInAppGallery) {
            InAppPhotoGalleryView()
        }
        .sheet(isPresented: $isShowingSessionGallery) {
            Group {
                if !sessionMoments.isEmpty {
                    SessionGalleryView(
                        moments: $sessionMoments,
                        allowRemove: true,
                        onRemoveAttachedMoment: { moment in
                            // Also remove from sessionCapturesForDisplay so the photo
                            // won't reappear after blog creation (when gallery switches lists).
                            sessionCapturesForDisplay.removeAll { $0.id == moment.id }
                        },
                        onClear: {
                            sessionCapturesForDisplay = []
                            photosCapturedThisSession = 0
                        }
                    )
                } else {
                    SessionGalleryView(
                        moments: $sessionCapturesForDisplay,
                        allowRemove: false,
                        savedToTitle: sessionTripTitle ?? OnTheGoTripStore.activeBlogTitle ?? "your trip",
                        onRemoveAttachedMoment: { moment in
                            if let photoId = moment.injectedPhotoId {
                                if sessionSourceTripId != nil {
                                    createdRecapStore.removePhotoFromBlog(photoId: photoId)
                                } else if let draftId = sessionDraftTripId {
                                    tripsViewModel.removePhotoFromCameraDraft(tripId: draftId, photoId: photoId)
                                }
                                // Recompute moment count after removal (list will update after this)
                                let afterRemoval = sessionCapturesForDisplay.filter { $0.id != moment.id }
                                attachedCountThisSession = momentCount(from: afterRemoval)
                            }
                        }
                    )
                }
            }
        }
        .overlay {
            if showBlogStartedPrompt {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }
                let blogName = sessionTripTitle ?? OnTheGoTripStore.activeBlogTitle ?? "your blog"
                VStack(spacing: 0) {
                    Text("Blog has started, your moments will be saved to \"\(blogName)\"")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                    HStack(spacing: 16) {
                        Button("Ok") {
                            showBlogStartedPrompt = false
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        Button("View") {
                            showBlogStartedPrompt = false
                            if let id = sessionSourceTripId {
                                onNavigateToBlog?(id)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 300)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 36)
            }
        }
        .overlay {
            if showNearHomeConfirmation {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }
                VStack(spacing: 0) {
                    Text("This moment appears to be near your home. Do you want to keep it anyway?")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    Toggle(isOn: $nearHomeDoNotShowAgain) {
                        Text("Do not show again")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            if nearHomeDoNotShowAgain {
                                UserDefaults.standard.set(true, forKey: Self.nearHomeAlertSuppressedKey)
                                UserDefaults.standard.set(false, forKey: Self.nearHomeSuppressedPreferKeepKey)
                            }
                            pendingNearHomeCapture = nil
                            showNearHomeConfirmation = false
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        Button("Keep") {
                            if nearHomeDoNotShowAgain {
                                UserDefaults.standard.set(true, forKey: Self.nearHomeAlertSuppressedKey)
                                UserDefaults.standard.set(true, forKey: Self.nearHomeSuppressedPreferKeepKey)
                            }
                            if let pending = pendingNearHomeCapture {
                                applyCapturedPhoto(image: pending.image, timestamp: pending.timestamp)
                                pendingNearHomeCapture = nil
                            }
                            showNearHomeConfirmation = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 300)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 36)
            }
        }
        .onChange(of: showNearHomeConfirmation) { _, show in
            if show { nearHomeDoNotShowAgain = false }
        }
    }

    private var flashIconName: String {
        switch cameraController.flashMode {
        case .off: return "bolt.slash"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic"
        @unknown default: return "bolt.slash"
        }
    }

    private var flashAccessibilityLabel: String {
        switch cameraController.flashMode {
        case .off: return "Flash off"
        case .on: return "Flash on"
        case .auto: return "Flash auto"
        @unknown default: return "Flash"
        }
    }

    private var shutterBar: some View {
        HStack {
            Spacer()
            Button {
                // Visual capture flash
                flashOpacity = 1
                withAnimation(.easeOut(duration: 0.2)) {
                    flashOpacity = 0
                }

                // Capture a real photo
                cameraController.capturePhoto { image, _ in
                    let timestamp = Date()
                    // Lightweight near-home check: same threshold as trip exclusion (Set home region).
                    if let home = NeighborhoodStore.getNeighborhoodCenter(),
                       let location = cameraController.currentLocation,
                       !TripPhotoFilter.shouldIncludeInTrips(
                           assetLocation: location,
                           home: home,
                           minMiles: NeighborhoodStore.localExclusionMiles
                       ) {
                        let suppressed = UserDefaults.standard.bool(forKey: Self.nearHomeAlertSuppressedKey)
                        if suppressed {
                            let preferKeep = UserDefaults.standard.bool(forKey: Self.nearHomeSuppressedPreferKeepKey)
                            if preferKeep {
                                applyCapturedPhoto(image: image, timestamp: timestamp)
                            }
                            return
                        }
                        pendingNearHomeCapture = (image ?? UIImage(), timestamp)
                        showNearHomeConfirmation = true
                        return
                    }
                    applyCapturedPhoto(image: image, timestamp: timestamp)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 62, height: 62)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Moment count by place (same place = one moment)

private let samePlaceDistanceMeters: CLLocationDistance = 50

/// Returns the number of distinct "places" (groups of photos within 50m) for display as "moment" count.
private func momentCount(from moments: [CapturedMoment]) -> Int {
    let sorted = moments.sorted { $0.timestamp < $1.timestamp }
    guard !sorted.isEmpty else { return 0 }
    var groups: [[CapturedMoment]] = []
    for moment in sorted {
        if groups.isEmpty {
            groups.append([moment])
            continue
        }
        let lastGroup = groups[groups.count - 1]
        let withinPlace: Bool
        if let loc = moment.location {
            if let lastWithLoc = lastGroup.last(where: { $0.location != nil }),
               let lastLoc = lastWithLoc.location {
                let from = CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude)
                let to = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                withinPlace = from.distance(from: to) <= samePlaceDistanceMeters
            } else {
                withinPlace = false
            }
        } else {
            // No location: treat as its own place (don't merge with others)
            withinPlace = false
        }
        if withinPlace {
            groups[groups.count - 1].append(moment)
        } else {
            groups.append([moment])
        }
    }
    return groups.count
}

// MARK: - CameraCaptureView helpers

extension CameraCaptureView {
    /// Adds the captured photo to the session and routes it (active blog, matching blog, camera draft, or start-blog prompt).
    /// Used after capture when not near home, and when user taps "Keep" on the near-home confirmation.
    /// Only adds to sessionMoments and shows "You are capturing a moment" when it's truly a new trip (no existing blog or draft for this capture).
    private func applyCapturedPhoto(image: UIImage?, timestamp: Date) {
        if let image = image {
            InAppCameraPhotoStore.shared.addPhoto(id: UUID(), image: image, timestamp: timestamp)
        }
        let location = cameraController.currentLocation.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let displayMoment = CapturedMoment(
            localIdentifier: nil,
            timestamp: timestamp,
            caption: nil,
            previewImage: image,
            location: location
        )
        if let activeSourceTripId = activeBlogIdIfCapturedImageHandled(image, at: timestamp) {
            sessionSourceTripId = activeSourceTripId
            sessionCapturesForDisplay.append(displayMoment)
            photosCapturedThisSession += 1
            injectCapturedImageIntoBlog(image, at: timestamp, sourceTripId: activeSourceTripId, momentId: displayMoment.id)
        } else if let matchedBlog = blogMatchingCaptureDate(timestamp) {
            sessionSourceTripId = matchedBlog.sourceTripId
            sessionCapturesForDisplay.append(displayMoment)
            photosCapturedThisSession += 1
            injectCapturedImageIntoBlog(image, at: timestamp, sourceTripId: matchedBlog.sourceTripId, momentId: displayMoment.id)
            if let endDate = matchedBlog.tripEndDate,
               (Calendar.current.dateComponents([.day], from: endDate, to: Date()).day ?? Int.max) <= 14 {
                OnTheGoTripStore.markTripAsActive(blogId: matchedBlog.sourceTripId, title: matchedBlog.title, tripEndDate: endDate, country: matchedBlog.countryName)
            }
        } else if let matchedDraft = tripsViewModel.cameraTripDraftMatching(captureDate: timestamp) {
            sessionDraftTripId = matchedDraft.id
            sessionCapturesForDisplay.append(displayMoment)
            photosCapturedThisSession += 1
            injectCapturedPhotoIntoCameraDraft(image, at: timestamp, tripId: matchedDraft.id, momentId: displayMoment.id)
        } else {
            let moment = displayMoment
            sessionMoments.append(moment)
            sessionCapturesForDisplay.append(displayMoment)
            photosCapturedThisSession += 1
            if !hasOfferedStartBlogThisSession {
                hasOfferedStartBlogThisSession = true
                startNewOnTheGoBlogFromSession()
            }
        }
    }

    /// Returns the active blog's sourceTripId if capture should be routed there; nil otherwise.
    /// If the user removed that blog, we clear on-the-go state and return nil so the next capture starts a new blog (and shows "Blog has started" prompt).
    private func activeBlogIdIfCapturedImageHandled(_ image: UIImage?, at timestamp: Date) -> UUID? {
        guard image != nil else { return nil }
        guard let activeSourceTripId = OnTheGoTripStore.activeBlogId,
              OnTheGoTripStore.isTripStillOngoing() else {
            return nil
        }
        if !createdRecapStore.hasCreatedBlog(sourceTripId: activeSourceTripId) {
            OnTheGoTripStore.markTripAsEnded()
            return nil
        }
        return activeSourceTripId
    }

    /// Finds a created blog whose date range includes the capture date (same day or within 7 days after).
    private func blogMatchingCaptureDate(_ captureTimestamp: Date) -> CreatedRecapBlog? {
        let cal = Calendar.current
        let captureDay = cal.startOfDay(for: captureTimestamp)
        for blog in createdRecapStore.visibleRecents {
            guard let blogStart = blog.tripStartDate, let blogEnd = blog.tripEndDate else { continue }
            let blogStartDay = cal.startOfDay(for: blogStart)
            let blogEndDay = cal.startOfDay(for: blogEnd)
            let overlaps = captureDay >= blogStartDay && captureDay <= blogEndDay
            let dayDiff = cal.dateComponents([.day], from: blogEndDay, to: captureDay).day ?? Int.max
            let continues = dayDiff >= 0 && dayDiff <= 7
            if overlaps || continues { return blog }
        }
        return nil
    }

    /// Saves the image to the photo library and injects it into the given blog. Updates the moment's injectedPhotoId when done so removal from modal can remove from blog.
    private func injectCapturedImageIntoBlog(_ image: UIImage?, at timestamp: Date, sourceTripId: UUID, momentId: UUID) {
        guard let image = image else { return }
        let location = cameraController.currentLocation
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.location = location
            let placeholder = request.placeholderForCreatedAsset
            let id = placeholder?.localIdentifier
            if let id { UserDefaults.standard.set(id, forKey: "bloggo.lastCapturedLocalId") }
        }, completionHandler: { success, error in
            guard success,
                  let localId = UserDefaults.standard.string(forKey: "bloggo.lastCapturedLocalId") else {
                return
            }
            UserDefaults.standard.removeObject(forKey: "bloggo.lastCapturedLocalId")
            let photoLocation = location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            Task { @MainActor in
                await Task.yield()
                try? await Task.sleep(nanoseconds: 300_000_000)
                var locationName: String? = nil
                var countryName: String? = nil
                if let location {
                    let place = await GeocodingService.shared.place(for: location)
                    locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                    countryName = place.countryName != "Unknown" ? place.countryName : nil
                }
                let photoId = UUID()
                let photo = MockPhoto(
                    id: photoId,
                    imageName: "camera.fill",
                    timestamp: timestamp,
                    locationName: locationName ?? "Captured Moment",
                    countryName: countryName,
                    isSelected: true,
                    localIdentifier: localId,
                    location: photoLocation
                )
                createdRecapStore.injectPhotos([photo], intoSourceTripId: sourceTripId)
                sessionTripTitle = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == sourceTripId })?.title
                attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
                if let idx = sessionCapturesForDisplay.firstIndex(where: { $0.id == momentId }) {
                    var m = sessionCapturesForDisplay[idx]
                    m.injectedPhotoId = photoId
                    sessionCapturesForDisplay[idx] = m
                }
            }
        })
    }

    /// Saves the image to the photo library and appends it to the given camera trip draft. Updates the moment's injectedPhotoId when done so removal from modal can remove from draft.
    private func injectCapturedPhotoIntoCameraDraft(_ image: UIImage?, at timestamp: Date, tripId: UUID, momentId: UUID) {
        guard let image = image else { return }
        let location = cameraController.currentLocation
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.location = location
            let placeholder = request.placeholderForCreatedAsset
            let id = placeholder?.localIdentifier
            if let id { UserDefaults.standard.set(id, forKey: "bloggo.lastCapturedLocalId") }
        }, completionHandler: { success, error in
            guard success,
                  let localId = UserDefaults.standard.string(forKey: "bloggo.lastCapturedLocalId") else {
                return
            }
            UserDefaults.standard.removeObject(forKey: "bloggo.lastCapturedLocalId")
            let photoLocation = location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            Task { @MainActor in
                await Task.yield()
                try? await Task.sleep(nanoseconds: 300_000_000)
                var locationName = "Captured Moment"
                var countryName: String? = nil
                if let location {
                    let place = await GeocodingService.shared.place(for: location)
                    locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                    countryName = place.countryName != "Unknown" ? place.countryName : nil
                }
                let photoId = UUID()
                let photo = MockPhoto(
                    id: photoId,
                    imageName: "camera.fill",
                    timestamp: timestamp,
                    locationName: locationName,
                    countryName: countryName,
                    isSelected: true,
                    localIdentifier: localId,
                    location: photoLocation
                )
                tripsViewModel.appendPhotosToCameraDraft(tripId: tripId, newPhotos: [photo])
                let draftTitle = tripsViewModel.tripDrafts.first(where: { $0.id == tripId })?.title
                if let t = draftTitle, !t.isEmpty { sessionTripTitle = t }
                attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
                if let idx = sessionCapturesForDisplay.firstIndex(where: { $0.id == momentId }) {
                    var m = sessionCapturesForDisplay[idx]
                    m.injectedPhotoId = photoId
                    sessionCapturesForDisplay[idx] = m
                }
            }
        })
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingToast = false
            }
        }
    }

    /// Handles closing the camera. Summary toast is shown by parent after dismiss.
    private func closeCamera() {
        // Sync any captions typed in the gallery into the blog for real-time injected photos.
        syncSessionCaptionsToBlog()
        // If user has unsaved session moments (e.g. closed before blog creation completed), save as draft.
        if !sessionMoments.isEmpty && attachedCountThisSession == 0 {
            saveSessionAsTripDraftOnly()
        }
        // Exit toast: when adding to a blog, show "X moment(s) saved for [Blog Name]".
        if !hasReportedDismissToast {
            let title = sessionTripTitle ?? OnTheGoTripStore.activeBlogTitle ?? "your trip"
            let countToBlog = sessionSourceTripId != nil
                ? momentCount(from: sessionCapturesForDisplay)
                : max(attachedCountThisSession, photosCapturedThisSession)
            if sessionSourceTripId != nil && countToBlog > 0 {
                hasReportedDismissToast = true
                let count = countToBlog
                let msg = "\(count) moment\(count == 1 ? "" : "s") saved for \(title)"
                postDismissToast?(msg)
            } else if attachedCountThisSession > 0 {
                hasReportedDismissToast = true
                let msg = "\(attachedCountThisSession) moment\(attachedCountThisSession == 1 ? "" : "s") added to \(title)"
                postDismissToast?(msg)
            }
        }
        if let onDismissOverlay {
            onDismissOverlay()
        } else {
            dismiss()
        }
    }

    /// Creates a new on-the-go blog for the current trip (if any) and injects
    /// all photos captured so far in this camera session. If there is no existing trip,
    /// creates a trip + blog from the current session moments.
    private func startNewOnTheGoBlogFromSession() {
        let allTrips = tripsViewModel.visibleDraftTripsNewestFirst
        let currentTrip: TripDraft?
        if let savedID = tripsViewModel.lastSelectedVisibleTripID,
           let match = allTrips.first(where: { $0.id == savedID }) {
            currentTrip = match
        } else {
            currentTrip = allTrips.first
        }

        let momentsWithImages = sessionMoments.filter { $0.previewImage != nil }

        // Validate that the selected trip is related to the camera session's timestamps.
        // If the session moments don't overlap with the trip's date range, ignore the trip
        // and create from session moments only (avoid pulling photos from unrelated trips).
        let validatedTrip: TripDraft? = {
            guard let trip = currentTrip,
                  let tripStart = trip.earliestDate,
                  let tripEnd = trip.latestDate else { return currentTrip }
            let cal = Calendar.current
            let sessionTimestamps = momentsWithImages.map(\.timestamp)
            guard let earliestCapture = sessionTimestamps.min() else { return currentTrip }
            let captureDay = cal.startOfDay(for: earliestCapture)
            let tripStartDay = cal.startOfDay(for: tripStart)
            let tripEndDay = cal.startOfDay(for: tripEnd)
            // Trip covers the capture date, or capture is within 7 days after trip end
            let overlaps = captureDay >= tripStartDay && captureDay <= tripEndDay
            let dayDiff = cal.dateComponents([.day], from: tripEndDay, to: captureDay).day ?? Int.max
            let continues = dayDiff >= 0 && dayDiff <= 7
            return (overlaps || continues) ? trip : nil
        }()

        // No existing trip: create a new trip + blog from session moments (save to library first).
        guard let trip = validatedTrip else {
            guard !momentsWithImages.isEmpty else { return }
            createBlogFromSessionMomentsOnly(momentsWithImages: momentsWithImages)
            return
        }

        // Blog already exists for this trip: just mark it active.
        if createdRecapStore.hasCreatedBlog(sourceTripId: trip.id),
           let existing = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == trip.id }),
           let endDate = existing.tripEndDate {
            OnTheGoTripStore.markTripAsActive(blogId: trip.id, title: existing.title, tripEndDate: endDate, country: existing.countryName)
            sessionSourceTripId = trip.id
            sessionTripTitle = existing.title
        } else {
            createdRecapStore.addCreatedBlog(trip: trip)
            if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == trip.id }),
               let endDate = blog.tripEndDate {
                OnTheGoTripStore.markTripAsActive(blogId: trip.id, title: blog.title, tripEndDate: endDate, country: blog.countryName)
                sessionSourceTripId = trip.id
                sessionTripTitle = blog.title
            }
        }
        showBlogStartedPrompt = true
        // So exit toast shows "X moments added to [Blog Name]" even if user exits before injection completes.
        attachedCountThisSession = momentCount(from: sessionMoments)
        // Clear sessionMoments so the counter and gallery switch to sessionCapturesForDisplay,
        // which receives all subsequent camera captures after blog creation.
        sessionMoments = []

        // Inject session photos into the trip/blog (save to library first for localIdentifiers).
        guard !momentsWithImages.isEmpty else { return }

        var placeholderIds: [String] = []
        let tripIdToUse = trip.id
        let location = cameraController.currentLocation
        let photoLocation = location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }

        PHPhotoLibrary.shared().performChanges {
            for moment in momentsWithImages {
                guard let image = moment.previewImage else { continue }
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.location = location
                if let id = request.placeholderForCreatedAsset?.localIdentifier {
                    placeholderIds.append(id)
                }
            }
        } completionHandler: { success, error in
            guard success, placeholderIds.count == momentsWithImages.count else {
                #if DEBUG
                if let err = error { print("[Camera] Failed to save session photos: \(err)") }
                #endif
                return
            }
            Task { @MainActor in
                await Task.yield()
                try? await Task.sleep(nanoseconds: 400_000_000)
                var locationName = "Captured Moment"
                var countryName: String? = nil
                if let location {
                    let place = await GeocodingService.shared.place(for: location)
                    locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                    countryName = place.countryName != "Unknown" ? place.countryName : nil
                }
                let photos: [MockPhoto] = zip(momentsWithImages, placeholderIds).map { moment, localId in
                    MockPhoto(
                        id: moment.id,
                        imageName: "camera.fill",
                        timestamp: moment.timestamp,
                        locationName: locationName,
                        countryName: countryName,
                        isSelected: true,
                        localIdentifier: localId,
                        location: moment.location ?? photoLocation,
                        caption: moment.caption
                    )
                }
                createdRecapStore.injectPhotos(photos, intoSourceTripId: tripIdToUse)
                // Set cover to first camera-captured photo (not the scanned trip's cover)
                if let firstLocalId = photos.first?.localIdentifier {
                    createdRecapStore.updateCoverAsset(sourceTripId: tripIdToUse, localIdentifier: firstLocalId)
                }
                sessionTripTitle = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == tripIdToUse })?.title
                attachedCountThisSession = momentCount(from: sessionCapturesForDisplay)
            }
        }
    }

    /// Creates a new trip draft from session moments, adds it as a blog, and shows "Blog has started, you can continue to add moments".
    /// Used when the first capture is a new trip (no existing blog or draft) — blog is created automatically.
    private func createBlogFromSessionMomentsOnly(momentsWithImages: [CapturedMoment]) {
        // Switch UI to blog flow immediately so counter and gallery use sessionCapturesForDisplay.
        attachedCountThisSession = momentCount(from: sessionMoments)
        sessionMoments = []
        let location = cameraController.currentLocation
        var placeholderIds: [String] = []
        PHPhotoLibrary.shared().performChanges {
            for moment in momentsWithImages {
                guard let image = moment.previewImage else { continue }
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.location = location
                if let id = request.placeholderForCreatedAsset?.localIdentifier {
                    placeholderIds.append(id)
                }
            }
        } completionHandler: { success, _ in
            guard success, placeholderIds.count == momentsWithImages.count else { return }
            Task { @MainActor in
                let photoLocation = location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                var locationName = "Captured Moment"
                var countryName: String? = nil
                if let location {
                    let place = await GeocodingService.shared.place(for: location)
                    locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                    countryName = place.countryName != "Unknown" ? place.countryName : nil
                }
                let photos: [MockPhoto] = zip(momentsWithImages, placeholderIds).map { moment, localId in
                    MockPhoto(
                        id: moment.id,
                        imageName: "camera.fill",
                        timestamp: moment.timestamp,
                        locationName: locationName,
                        countryName: countryName,
                        isSelected: true,
                        localIdentifier: localId,
                        location: moment.location ?? photoLocation,
                        caption: moment.caption
                    )
                }
                let cal = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale.current
                dateFormatter.dateStyle = .medium
                let byDay = Dictionary(grouping: photos) { cal.startOfDay(for: $0.timestamp) }
                let sortedDays = byDay.sorted { $0.key < $1.key }
                let days: [TripDay] = sortedDays.enumerated().map { index, pair in
                    let dayStart = pair.key
                    let dayPhotos = pair.value.sorted { $0.timestamp < $1.timestamp }
                    return TripDay(
                        dayIndex: index,
                        dateText: dateFormatter.string(from: dayStart),
                        photos: dayPhotos
                    )
                }
                let tripId = UUID()
                let title = cameraBlogTitleFromPhotos(photos: photos, locationName: locationName, countryName: countryName)
                let dateRangeStr: String
                if let first = sortedDays.first?.key, let last = sortedDays.last?.key {
                    dateRangeStr = first == last
                        ? dateFormatter.string(from: first)
                        : "\(dateFormatter.string(from: first)) – \(dateFormatter.string(from: last))"
                } else {
                    dateRangeStr = dateFormatter.string(from: Date())
                }
                let trip = TripDraft(
                    id: tripId,
                    title: title,
                    dateRangeText: dateRangeStr,
                    days: days,
                    coverImageName: "camera.fill",
                    isScannedFromDefaultRange: false,
                    draftCreatedAgoText: "Draft created recently",
                    daysSeasonText: "",
                    coverTheme: "default",
                    coverAssetIdentifier: photos.first?.localIdentifier
                )
                tripsViewModel.addCameraTripDraft(trip)
                createdRecapStore.addCreatedBlog(trip: trip)
                if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == tripId }),
                   let endDate = blog.tripEndDate {
                    OnTheGoTripStore.markTripAsActive(blogId: tripId, title: blog.title, tripEndDate: endDate, country: blog.countryName)
                }
                sessionSourceTripId = tripId
                sessionTripTitle = title
                attachedCountThisSession = photos.count
                showBlogStartedPrompt = true
            }
        }
    }

    /// Pushes captions from sessionCapturesForDisplay into the blog detail for any
    /// photos that were real-time injected (have injectedPhotoId) and have a caption.
    private func syncSessionCaptionsToBlog() {
        let captions: [(photoId: UUID, caption: String)] = sessionCapturesForDisplay.compactMap { moment in
            guard let photoId = moment.injectedPhotoId,
                  let caption = moment.caption, !caption.isEmpty else { return nil }
            return (photoId: photoId, caption: caption)
        }
        createdRecapStore.syncCaptions(captions)
    }

    /// Saves session photos to the library and creates or updates a trip draft (no blog).
    /// Called when user closes the camera with unsaved session moments (e.g. before blog creation completed).
    /// Uses the same grouping as the trip scanner: merge only when within maxGapDaysToBridge of an existing draft; otherwise group days by gap into one or more trips to avoid duplicates.
    private func saveSessionAsTripDraftOnly() {
        let momentsWithImages = sessionMoments.filter { $0.previewImage != nil }
        guard !momentsWithImages.isEmpty else { return }

        let earliestTimestamp = momentsWithImages.map(\.timestamp).min() ?? Date()
        let existingDraft = tripsViewModel.cameraTripDraftMatching(captureDate: earliestTimestamp)

        var placeholderIds: [String] = []
        let location = cameraController.currentLocation
        PHPhotoLibrary.shared().performChanges {
            for moment in momentsWithImages {
                guard let image = moment.previewImage else { continue }
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.location = location
                if let id = request.placeholderForCreatedAsset?.localIdentifier {
                    placeholderIds.append(id)
                }
            }
        } completionHandler: { success, _ in
            guard success, placeholderIds.count == momentsWithImages.count else { return }
            Task { @MainActor in
                let photoLocation = location.map { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                var locationName = "Captured Moment"
                var countryName: String? = nil
                if let location {
                    let place = await GeocodingService.shared.place(for: location)
                    locationName = place.cityName != "Unknown Place" ? place.cityName : place.bestPlaceLabel
                    countryName = place.countryName != "Unknown" ? place.countryName : nil
                }
                let photos: [MockPhoto] = zip(momentsWithImages, placeholderIds).map { moment, localId in
                    MockPhoto(
                        id: moment.id,
                        imageName: "camera.fill",
                        timestamp: moment.timestamp,
                        locationName: locationName,
                        countryName: countryName,
                        isSelected: true,
                        localIdentifier: localId,
                        location: photoLocation,
                        caption: moment.caption
                    )
                }

                let cal = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale.current
                dateFormatter.dateStyle = .medium

                if let draft = existingDraft,
                   let draftStart = draft.earliestDate,
                   let draftEnd = draft.latestDate {
                    let draftStartDay = cal.startOfDay(for: draftStart)
                    let draftEndDay = cal.startOfDay(for: draftEnd)
                    let cutoff = cal.date(byAdding: .day, value: ScanConfig.maxGapDaysToBridge, to: draftEndDay)!
                    let photosToAppend = photos.filter { photo in
                        let day = cal.startOfDay(for: photo.timestamp)
                        return day >= draftStartDay && day <= cutoff
                    }
                    let remainingPhotos = photos.filter { p in !photosToAppend.contains(where: { $0.id == p.id }) }

                    if !photosToAppend.isEmpty {
                        tripsViewModel.appendPhotosToCameraDraft(tripId: draft.id, newPhotos: photosToAppend)
                    }
                    if !remainingPhotos.isEmpty {
                        for trip in cameraTripsFromPhotos(remainingPhotos, cal: cal, dateFormatter: dateFormatter, locationName: locationName, countryName: countryName) {
                            tripsViewModel.addCameraTripDraft(trip)
                        }
                    }
                } else {
                    let tripDayGroups = cameraTripDayGroupsFromPhotos(photos, cal: cal)
                    for group in tripDayGroups {
                        let days: [TripDay] = group.enumerated().map { index, pair in
                            let dayStart = pair.0
                            let dayPhotos = pair.1.sorted { $0.timestamp < $1.timestamp }
                            return TripDay(
                                dayIndex: index,
                                dateText: dateFormatter.string(from: dayStart),
                                photos: dayPhotos
                            )
                        }
                        let groupPhotos = group.flatMap(\.1)
                        let tripId = UUID()
                        let title = cameraBlogTitleFromPhotos(photos: groupPhotos, locationName: locationName, countryName: countryName)
                        let dateRangeStr: String
                        if let first = group.first?.0, let last = group.last?.0 {
                            dateRangeStr = first == last
                                ? dateFormatter.string(from: first)
                                : "\(dateFormatter.string(from: first)) – \(dateFormatter.string(from: last))"
                        } else {
                            dateRangeStr = dateFormatter.string(from: Date())
                        }
                        let trip = TripDraft(
                            id: tripId,
                            title: title,
                            dateRangeText: dateRangeStr,
                            days: days,
                            coverImageName: "camera.fill",
                            isScannedFromDefaultRange: false,
                            draftCreatedAgoText: "Draft created recently",
                            daysSeasonText: "",
                            coverTheme: "default",
                            coverAssetIdentifier: groupPhotos.first?.localIdentifier
                        )
                        tripsViewModel.addCameraTripDraft(trip)
                    }
                }
            }
        }
    }

    /// Groups photos by calendar day, then splits into trip day groups using the same gap rule as the trip scanner (maxGapDaysToBridge).
    /// Returns one array of (dayDate, photos) per trip so we avoid duplicate trips when session spans a large gap.
    private func cameraTripDayGroupsFromPhotos(_ photos: [MockPhoto], cal: Calendar) -> [[(Date, [MockPhoto])]] {
        let byDay = Dictionary(grouping: photos) { cal.startOfDay(for: $0.timestamp) }
        let sortedDays = byDay.sorted { $0.key < $1.key }
        var tripDayGroups: [[(Date, [MockPhoto])]] = []
        var current: [(Date, [MockPhoto])] = []
        for pair in sortedDays {
            let dayDate = pair.key
            if current.isEmpty {
                current = [pair]
            } else {
                let lastDay = current.last!.0
                let gap = cal.dateComponents([.day], from: lastDay, to: dayDate).day ?? 0
                if gap <= ScanConfig.maxGapDaysToBridge {
                    current.append(pair)
                } else {
                    tripDayGroups.append(current)
                    current = [pair]
                }
            }
        }
        if !current.isEmpty { tripDayGroups.append(current) }
        return tripDayGroups
    }

    /// Builds one TripDraft per trip group from the given photos using scanner gap logic.
    private func cameraTripsFromPhotos(
        _ photos: [MockPhoto],
        cal: Calendar,
        dateFormatter: DateFormatter,
        locationName: String,
        countryName: String?
    ) -> [TripDraft] {
        let groups = cameraTripDayGroupsFromPhotos(photos, cal: cal)
        return groups.map { group in
            let days: [TripDay] = group.enumerated().map { index, pair in
                let dayStart = pair.0
                let dayPhotos = pair.1.sorted { $0.timestamp < $1.timestamp }
                return TripDay(
                    dayIndex: index,
                    dateText: dateFormatter.string(from: dayStart),
                    photos: dayPhotos
                )
            }
            let groupPhotos = group.flatMap(\.1)
            let title = cameraBlogTitleFromPhotos(photos: groupPhotos, locationName: locationName, countryName: countryName)
            let dateRangeStr: String
            if let first = group.first?.0, let last = group.last?.0 {
                dateRangeStr = first == last
                    ? dateFormatter.string(from: first)
                    : "\(dateFormatter.string(from: first)) – \(dateFormatter.string(from: last))"
            } else {
                dateRangeStr = dateFormatter.string(from: Date())
            }
            return TripDraft(
                id: UUID(),
                title: title,
                dateRangeText: dateRangeStr,
                days: days,
                coverImageName: "camera.fill",
                isScannedFromDefaultRange: false,
                draftCreatedAgoText: "Draft created recently",
                daysSeasonText: "",
                coverTheme: "default",
                coverAssetIdentifier: groupPhotos.first?.localIdentifier
            )
        }
    }

    /// Builds a location-based default blog title from camera photos (e.g. "San Francisco, United States").
    private func cameraBlogTitleFromPhotos(photos: [MockPhoto], locationName: String, countryName: String?) -> String {
        let country = countryName ?? "Unknown"
        let city = locationName.isEmpty || locationName == "Unknown Place" || locationName == "Captured Moment" ? "" : locationName
        let geo: String
        if city.isEmpty {
            geo = country != "Unknown" ? "\(country) Trip" : "Captured Moments"
        } else if country == "Unknown" {
            geo = "Captured Moments"
        } else {
            let uniqueCities = Set(photos.compactMap { $0.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "Captured Moment" })
            geo = uniqueCities.count > 1 ? "\(city) Area, \(country)" : "\(city), \(country)"
        }
        if geo == "Captured Moments" { return geo }
        guard let firstDate = photos.first?.timestamp else { return geo }
        let month = Calendar.current.component(.month, from: firstDate)
        let season: String
        switch month {
        case 12, 1, 2: season = "Winter"
        case 3, 4, 5: season = "Spring"
        case 6, 7, 8: season = "Summer"
        case 9, 10, 11: season = "Fall"
        default: season = "Winter"
        }
        if geo.hasSuffix(" Trip") { return geo }
        return "\(geo) in \(season)"
    }
}

// MARK: - In-app Photo Gallery

/// Dedicated gallery of all photos taken with the in-app camera (latest first). 3×3 grid; Select mode: Done in toolbar, trash (bottom right) and download (bottom left) in modal.
private struct InAppPhotoGalleryView: View {
    @ObservedObject private var store = InAppCameraPhotoStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSelectMode = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showRemoveConfirmation = false
    @State private var downloadToast: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    private static let darkNavy = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Self.darkNavy
                    .ignoresSafeArea()
                Group {
                    if store.entries.isEmpty {
                        ContentUnavailableView(
                            "No Bloggo photos yet",
                            systemImage: "camera",
                            description: Text("Photos you take with the camera will appear here.")
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(store.entries) { entry in
                                    galleryCell(entry)
                                }
                            }
                            .padding(4)
                            .padding(.bottom, isSelectMode ? 72 : 0)
                        }
                    }
                }
                .navigationTitle("Bloggo Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if store.entries.isEmpty {
                            EmptyView()
                        } else if isSelectMode {
                            Button("Done") {
                                isSelectMode = false
                                selectedIds = []
                            }
                        } else {
                            Button("Select") {
                                isSelectMode = true
                            }
                        }
                    }
                }

                // Bottom bar: download (left), "# Photos Selected" (center), trash (right) — only in select mode
                if isSelectMode && !store.entries.isEmpty {
                    HStack {
                        Button {
                            saveSelectedToPhotoLibrary()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(selectedIds.isEmpty ? .gray : .white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedIds.isEmpty)
                        .accessibilityLabel("Save selected to Photos")

                        Spacer()

                        Text("\(selectedIds.count) Photos Selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            showRemoveConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(selectedIds.isEmpty ? .gray : .red)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedIds.isEmpty)
                        .accessibilityLabel("Remove selected from gallery")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                if let toast = downloadToast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(.bottom, 100)
                }
            }
            .alert("Remove selected photos?", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    store.removePhotos(ids: selectedIds)
                    selectedIds = []
                    isSelectMode = false
                }
            } message: {
                Text("\(selectedIds.count) photo\(selectedIds.count == 1 ? "" : "s") will be deleted from this gallery. They will not be removed from your device photo library or any blog.")
            }
        }
        .presentationDetents([.fraction(1)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func saveSelectedToPhotoLibrary() {
        let entriesToSave = store.entries.filter { selectedIds.contains($0.id) }
        let images = entriesToSave.compactMap { store.image(for: $0) }
        guard !images.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    downloadToast = "\(images.count) photo\(images.count == 1 ? "" : "s") saved to Photos"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                }
            }
        }
    }

    private func galleryCell(_ entry: InAppCameraPhotoEntry) -> some View {
        let isSelected = selectedIds.contains(entry.id)
        return Button {
            if isSelectMode {
                if isSelected {
                    selectedIds.remove(entry.id)
                } else {
                    selectedIds.insert(entry.id)
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                if let image = store.image(for: entry) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .opacity(isSelectMode && isSelected ? 0.5 : 1)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                    Image(systemName: "photo")
                        .foregroundColor(.white.opacity(0.6))
                }
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isSelectMode)
    }
}

// MARK: - Session Gallery

/// Session photos pull-up: list of captured photos with thumbnails and caption field.
/// Used for both "new trip" (allowRemove: true) and "added to blog/trip" (allowRemove: false, savedToTitle: "…").
private struct SessionGalleryView: View {
    @Binding var moments: [CapturedMoment]
    var allowRemove: Bool = true
    var savedToTitle: String? = nil
    /// When user removes a moment from the "Saved to" list, call this so the parent can remove from blog/draft and update count.
    var onRemoveAttachedMoment: ((CapturedMoment) -> Void)? = nil
    /// When user taps "Clear" and confirms, call this so the parent can sync sessionCapturesForDisplay and photosCapturedThisSession.
    var onClear: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false
    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if moments.isEmpty {
                    if let title = savedToTitle {
                        Section {
                            Text("Saved to \"\(title)\"")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                        }
                    }
                    Text("No photos captured yet.")
                        .foregroundColor(.secondary)
                } else if let title = savedToTitle {
                    Section {
                        Text("Saved to \"\(title)\"")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                        ForEach(moments.indices, id: \.self) { index in
                        let moment = moments[index]
                        let rowHeight: CGFloat = 100
                        HStack(alignment: .top, spacing: 12) {
                            // Photo preview — same height as timestamp + caption block
                            if let image = moment.previewImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: rowHeight)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                    Image(systemName: "photo")
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(width: 64, height: rowHeight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                // Timestamp row with Trash on the right (above caption box)
                                HStack {
                                    Text(moment.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 8)
                                    Button {
                                        let moment = moments[index]
                                        onRemoveAttachedMoment?(moment)
                                        moments.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }

                                TextField("Add a caption…", text: Binding(
                                    get: { moments[index].caption ?? "" },
                                    set: { moments[index].caption = $0.isEmpty ? nil : $0 }
                                ), axis: .vertical)
                                .focused($isCaptionFocused)
                                .font(.subheadline)
                                .lineLimit(3...6)
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
                                .background(Color(uiColor: .secondarySystemFill))
                                .cornerRadius(8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: rowHeight)
                        }
                        .padding(.vertical, 4)
                    }
                    }
                } else {
                    ForEach(moments.indices, id: \.self) { index in
                        let moment = moments[index]
                        let rowHeight: CGFloat = 100
                        HStack(alignment: .top, spacing: 12) {
                            // Photo preview — same height as timestamp + caption block
                            if let image = moment.previewImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: rowHeight)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                    Image(systemName: "photo")
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(width: 64, height: rowHeight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                // Timestamp row with Trash on the right (above caption box)
                                HStack {
                                    Text(moment.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 8)
                                    Button {
                                        let moment = moments[index]
                                        onRemoveAttachedMoment?(moment)
                                        moments.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }

                                TextField("Add a caption…", text: Binding(
                                    get: { moments[index].caption ?? "" },
                                    set: { moments[index].caption = $0.isEmpty ? nil : $0 }
                                ), axis: .vertical)
                                .focused($isCaptionFocused)
                                .font(.subheadline)
                                .lineLimit(3...6)
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
                                .background(Color(uiColor: .secondarySystemFill))
                                .cornerRadius(8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: rowHeight)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Current Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isCaptionFocused {
                        Button("Done") {
                            isCaptionFocused = false
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    } else if allowRemove {
                        Button("Clear") {
                            showClearConfirmation = true
                        }
                    }
                }
            }
            .alert("Start fresh?", isPresented: $showClearConfirmation) {
                Button("No", role: .cancel) { }
                Button("Yes", role: .destructive) {
                    onClear?()
                    moments = []
                }
            } message: {
                Text("Do you want to start fresh? All session photos will be removed.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Camera Overlay

extension TripsView {
    private var cameraOverlayButton: some View {
        HStack(spacing: 8) {
            Button {
                showCameraCapture = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.16))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
        .opacity((showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips) ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: showLoadMorePopup || showLoadNewerPopup || viewModel.isLoadingOlderTrips || viewModel.isLoadingNewerTrips)
    }
}

// MARK: - Trip Carousel Card

struct TripCarouselCard: View {
    let trip: TripDraft
    var isSelected: Bool = false
    var showNewBadge: Bool = false
    var onTap: () -> Void = {}

    private static let cornerRadius: CGFloat = 18

    private var durationText: String {
        let count = trip.days.count
        return count == 1 ? "1 day" : "\(count) days"
    }

    var body: some View {
        // Cover image as the base
        TripCoverImage(trip: trip)
            .frame(height: 220)
            .scaleEffect(1.05)
            .clipped()
            // Dark gradient at bottom for text contrast
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
            // Trip info — bottom left
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    // Trip title
                    Text(trip.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Subtitle: Date range + duration
                    Text("\(trip.tripDateRangeDisplayText)  •  \(durationText)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))

                    // Photo count glass pill
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(trip.totalPhotoCount) Photos")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .padding(14)
            }
            // "New" badge — top left (trips from this session's photo selection)
            .overlay(alignment: .topLeading) {
                if showNewBadge {
                    Text("New")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green))
                        .padding(10)
                }
            }
            // Subtle "tap to create" hint only on the selected card
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Color.blue)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Selection ring
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .onTapGesture(perform: onTap)
    }
}

// MARK: - TripCoverImage

/// Photo-like cover gradients keyed by theme (Iceland = aurora, Morocco = lanterns, etc.). When coverAssetIdentifier is set, shows that photo from the library.
struct TripCoverImage: View {
    let theme: String
    var coverAssetIdentifier: String? = nil
    var coverCloudURL: String? = nil
    var targetSize: CGSize = CGSize(width: 600, height: 400)

    init(theme: String, coverAssetIdentifier: String? = nil, coverCloudURL: String? = nil, targetSize: CGSize = CGSize(width: 600, height: 400)) {
        self.theme = theme
        self.coverAssetIdentifier = coverAssetIdentifier
        self.coverCloudURL = coverCloudURL
        self.targetSize = targetSize
    }

    /// Convenience init from a TripDraft.
    init(trip: TripDraft, targetSize: CGSize = CGSize(width: 600, height: 400)) {
        self.theme = trip.coverTheme
        self.coverAssetIdentifier = trip.coverAssetIdentifier
        self.coverCloudURL = nil // Drafts are local only
        self.targetSize = targetSize
    }

    var body: some View {
        ZStack {
            gradientForTheme(theme)
            if let id = coverAssetIdentifier {
                AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: targetSize)
            } else if let cloudURL = coverCloudURL, let url = URL(string: cloudURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            }
            optionalAssetOverlay
        }
    }

    private func gradientForTheme(_ theme: String) -> some View {
        switch theme {
        case "iceland":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.15, blue: 0.35),
                        Color(red: 0.05, green: 0.35, blue: 0.25),
                        Color(red: 0.15, green: 0.5, blue: 0.4),
                        Color(red: 0.08, green: 0.2, blue: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case "morocco":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.2, blue: 0.15),
                        Color(red: 0.6, green: 0.35, blue: 0.2),
                        Color(red: 0.55, green: 0.25, blue: 0.2),
                        Color(red: 0.35, green: 0.18, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case "tokyo":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.15, blue: 0.25),
                        Color(red: 0.6, green: 0.2, blue: 0.35),
                        Color(red: 0.25, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case "paris":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.25, green: 0.22, blue: 0.35),
                        Color(red: 0.35, green: 0.3, blue: 0.45),
                        Color(red: 0.2, green: 0.18, blue: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case "california":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.7, blue: 0.4),
                        Color(red: 0.85, green: 0.5, blue: 0.35),
                        Color(red: 0.4, green: 0.5, blue: 0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case "alps":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.6, green: 0.75, blue: 0.9),
                        Color(red: 0.4, green: 0.6, blue: 0.75),
                        Color(red: 0.25, green: 0.4, blue: 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case "barcelona":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.9, green: 0.4, blue: 0.2),
                        Color(red: 0.7, green: 0.35, blue: 0.4),
                        Color(red: 0.3, green: 0.2, blue: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case "london":
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.22, blue: 0.3),
                        Color(red: 0.35, green: 0.35, blue: 0.45),
                        Color(red: 0.15, green: 0.15, blue: 0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        default:
            return AnyView(
                LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder
    private var optionalAssetOverlay: some View {
        let capName = "\(theme.prefix(1).uppercased())\(theme.dropFirst())Cover"
        if UIImage(named: capName) != nil {
            Image(capName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if UIImage(named: theme) != nil {
            Image(theme)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

// MARK: - On-the-go sheet slide-up wrapper

/// Wraps the on-the-go modal content so it slides up from the bottom on appear (offset animation).
/// Content is rasterized with drawingGroup() so the panel and all its components move as one fixed unit.
/// Sheet height is limited so part of the map remains visible at the top (pull-up affordance).
private struct OnTheGoSheetWithSlideUp<Content: View>: View {
    let sheetContent: Content
    @State private var offsetY: CGFloat = 600
    /// Fraction of screen height for the sheet so the map peeks at the top (~28% visible).
    private let sheetHeightFraction: CGFloat = 0.72

    init(@ViewBuilder sheetContent: () -> Content) {
        self.sheetContent = sheetContent()
    }

    var body: some View {
        GeometryReader { geo in
            let sheetHeight = max(400, geo.size.height * sheetHeightFraction)
            sheetContent
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: offsetY)
        }
        .onAppear {
            // One layout pass so the panel is fully composed, then slide up as one unit.
            // Short delay ensures overlay/GeometryReader have valid size (fixes modal not appearing when shown from overlay).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    offsetY = 0
                }
            }
        }
        .transition(.asymmetric(
            insertion: .identity,
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

// MARK: - Newly Scanned Photos Sheet

/// Card/secondary surfaces inside the on-the-go sheet.
private let newMomentsCardBg     = Color(uiColor: .tertiarySystemGroupedBackground)
private let newMomentsDivider    = Color.primary.opacity(0.12)

struct NewlyScannedPhotosSheet: View {
    let photos: [MockPhoto]
    let matchedTrip: TripDraft?
    let matchedBlog: CreatedRecapBlog?
    var onGoToTrip: (() -> Void)?
    var onGoToBlog: (() -> Void)?
    var onDismiss: () -> Void

    // Up to 4 thumbnails in the preview strip.
    private var previewPhotos: [MockPhoto] { Array(photos.prefix(4)) }

    private var coverAssetId: String? {
        matchedBlog?.coverAssetIdentifier
            ?? matchedTrip?.coverAssetIdentifier
            ?? photos.first?.localIdentifier
    }

    private var entityTitle: String {
        matchedBlog?.title ?? matchedTrip?.title ?? "Your Trip"
    }

    private var entityDateRange: String {
        matchedBlog?.tripDateRangeText
            ?? matchedTrip?.tripDateRangeDisplayText
            ?? ""
    }

    private var entityDuration: String {
        if let blog = matchedBlog {
            let d = blog.tripDurationDays
            return "\(d) day\(d == 1 ? "" : "s")"
        }
        if let trip = matchedTrip {
            let d = trip.days.count
            return "\(d) day\(d == 1 ? "" : "s")"
        }
        return ""
    }

    /// Main notification label: "# Moments – Add to [Blog Name]" when matched to a saved blog, else "N moment(s) found".
    private var newPhotoLabel: String {
        let n = photos.count
        let momentText = "\(n) moment\(n == 1 ? "" : "s")"
        if let blog = matchedBlog {
            return "\(momentText) – Add to \"\(blog.title)\""
        }
        return "\(momentText) found"
    }

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Sheet content: blog card + photo strip + CTAs (not scrollable)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    blogCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    photoStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)

                // CTA buttons at bottom of pull-up modal
                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous))
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
    }

    // MARK: - Blog Card

    @ViewBuilder
    private var blogCard: some View {
        let themeName = matchedBlog?.coverImageName ?? matchedTrip?.coverTheme ?? "blue"
        VStack(alignment: .leading, spacing: 12) {
            TripCoverImage(theme: themeName, coverAssetIdentifier: coverAssetId)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    // Badge: "# Moments – Add to [Blog Name]" or "N moment(s) found"
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(newPhotoLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(entityDateRange)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                Text(entityTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    if !entityDuration.isEmpty {
                        Text(entityDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Photo strip (up to 4 thumbnails)

    @ViewBuilder
    private var photoStrip: some View {
        if !previewPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEW MOMENTS FOUND")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                HStack(spacing: 6) {
                    ForEach(previewPhotos) { photo in
                        Group {
                            if let id = photo.localIdentifier {
                                AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 160, height: 160))
                            } else {
                                MockPhotoView(seed: photo.id.hashValue, cornerRadius: 0, showIcon: false, iconName: photo.imageName)
                            }
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    // "+N more" pill when there are extra photos
                    if photos.count > 4 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(newMomentsCardBg)
                                .frame(width: 70, height: 70)
                            Text("+\(photos.count - 4)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let blog = matchedBlog {
                Button(action: { onGoToBlog?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                        Text("Add to \"\(blog.title)\"")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            } else if matchedTrip != nil {
                Button(action: { onGoToTrip?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "map.fill")
                        Text("View Trip")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            }

            Button(action: onDismiss) {
                Text("Later")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
        }
    }
}

// MARK: - Debug Scan Sheet

#if DEBUG
private struct ScanDebugSheet: View {
    let info: ScanDebugInfo?
    let isLoading: Bool

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy  HH:mm:ss"
        return f
    }()

    private func ts(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return Self.tsFormatter.string(from: d)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && info == nil {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Scanning photos…").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let info {
                    List {
                        summarySection(info)
                        if info.entries.isEmpty {
                            Section("Photo Groups") {
                                Text("No trips found in this window.")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                        } else {
                            ForEach(info.entries) { entry in
                                entrySection(entry, lastScanned: info.lastScannedDate)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    Text("No scan data yet.").foregroundColor(.secondary)
                }
            }
            .navigationTitle("Scan Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func summarySection(_ info: ScanDebugInfo) -> some View {
        Section("Summary") {
            LabeledContent("Scanned at", value: ts(info.scannedAt))
            LabeledContent("Last scan", value: ts(info.lastScannedDate))
            LabeledContent("Fetch window start", value: ts(info.fetchStart))
            LabeledContent("Trip groups found", value: "\(info.entries.count)")
            let totalNew = info.entries.reduce(0) { $0 + $1.newPhotoCount }
            let totalAll = info.entries.reduce(0) { $0 + $1.totalPhotos }
            LabeledContent("Photos (total / new)", value: "\(totalAll) / \(totalNew)")
        }
    }

    @ViewBuilder
    private func entrySection(_ entry: ScanDebugInfo.TripEntry, lastScanned: Date?) -> some View {
        Section {
            // Match badge row
            HStack(spacing: 6) {
                matchBadge(entry.match)
                if entry.within24hOfExisting {
                    Text("≤24 h")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                Spacer()
            }

            LabeledContent("Date range", value: entry.dateRange)
            LabeledContent("Photos total", value: "\(entry.totalPhotos)")

            let newLabel = lastScanned == nil ? "Photos (no prior scan)" : "New (after last scan)"
            LabeledContent(newLabel, value: "\(entry.newPhotoCount)")
                .foregroundColor(entry.newPhotoCount > 0 ? .green : .primary)

            if case .savedBlog(_, let cutoff) = entry.match {
                LabeledContent("Blog cutoff", value: ts(cutoff))
                LabeledContent("After cutoff", value: "\(entry.photosAfterCutoff)")
                    .foregroundColor(entry.photosAfterCutoff > 0 ? .green : .secondary)
            }

            if entry.within24hOfExisting {
                Text("This trip's start is within 24 h of an existing draft or blog boundary — likely the same ongoing trip.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(entry.title)
                .textCase(nil)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func matchBadge(_ match: ScanDebugInfo.TripMatch) -> some View {
        let (label, color): (String, Color) = {
            switch match {
            case .newTrip:             return ("New Trip", .blue)
            case .existingDraft(let t): return ("Draft: \(t)", .purple)
            case .savedBlog(let t, _):  return ("Blog: \(t)", .green)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
#endif

#Preview {
    NavigationStack {
        TripsView(
            viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            selectedCreatedRecap: .constant(nil)
        )
    }
}
