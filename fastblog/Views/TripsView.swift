//
//  TripsView.swift
//  Capper
//

import MapKit
import Photos
import SwiftUI

struct TripsView: View {
    @ObservedObject var viewModel: TripsViewModel
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
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

    init(
        viewModel: TripsViewModel,
        selectedCreatedRecap: Binding<CreatedRecapBlog?>,
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedCreatedRecap = selectedCreatedRecap
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
                    onCancel: {
                        viewModel.cancelDefaultScan()
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
        .navigationDestination(item: $selectedCreatedRecap) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: CreatedRecapBlogStore.shared.tripDraft(for: recap.sourceTripId)
            )
        }
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
        .onAppear { viewModel.onAppear() }
        .onChange(of: selectedCreatedRecap) { old, new in
            if new == nil && createdRecapStore.pendingRecapCreated {
                createdRecapStore.pendingRecapCreated = false
            }
        }
        .onChange(of: createdRecapStore.lastDiscardedTripId) { _, tripId in
            guard let tripId else { return }
            createdRecapStore.lastDiscardedTripId = nil
            // Scroll the carousel to the trip that just reappeared after the user discarded the blog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedTripID = tripId
                }
                if let center = allTrips.first(where: { $0.id == tripId })?.centerCoordinate {
                    let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                    mapPosition = .region(MKCoordinateRegion(center: center, span: span))
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
        // New moments detected overlay.
        .overlay(newlyScannedOverlay)
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
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            // Full-screen interactive map
            mapViewLayer

            VStack(spacing: 0) {
                // Only surface the Limited banner after a scan that produced weak results
                if photoAuth.status == .limited && showLimitedBannerAfterWeakScan {
                    limitedAccessHelper
                        .padding(.top, 60)
                }
                Spacer()
                // Carousel + CTA with integrated shadow backdrop
                bottomOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
                    viewModel.openFindMoreSheet()
                } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.body)
                        .foregroundColor(.white)
                }
                .opacity((showLoadMorePopup || viewModel.isLoadingOlderTrips) ? 0 : 1)
                .disabled(showLoadMorePopup || viewModel.isLoadingOlderTrips)
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
        // Surface the Limited banner only when scan finishes with weak results
        .onChange(of: viewModel.scanState) { oldState, newState in
            if oldState != .idle && newState == .idle {
                didCompleteInitialSelection = false
                if preserveScrollOnNextScan {
                    // Re-scan triggered by returning from blog flow — keep the user's scroll position.
                    preserveScrollOnNextScan = false
                } else {
                    // Normal scan (initial load, Find More, etc.) — restore last position or land on newest trip.
                    let trips = allTrips
                    if let target = preferredTrip(from: trips) {
                        selectedTripID = target.id
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
        // • Left-swipe on last card   → "Load older trips"
        // • Right-swipe on first card → "Load newer trips" (only when a newer window exists)
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
                       viewModel.canLoadNewerTrips,
                       !viewModel.isLoadingNewerTrips,
                       !showLoadNewerPopup {
                        withAnimation(.easeOut(duration: 0.3)) { showLoadNewerPopup = true }
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

            if photoAuth.status == .limited {
                HStack(spacing: 10) {
                    Button {
                        presentLimitedLibraryPicker()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add More Photos")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 0.18, green: 0.40, blue: 0.78),
                                             Color(red: 0.25, green: 0.35, blue: 0.72)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                        .clipShape(Capsule())
                    }

                    Button {
                        viewModel.openFindMoreSheet()
                    } label: {
                        Text("Change Range")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
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
                // Hide the banner and kick off a fresh scan to reflect newly added photos
                withAnimation { showLimitedBannerAfterWeakScan = false }
                viewModel.startDefaultScan()
            }
        }
    }

    // MARK: - Toast

    private var draftSavedToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
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
    // MARK: - Newly Scanned Overlay

    @ViewBuilder
    private var newlyScannedOverlay: some View {
        if viewModel.showNewlyScannedSheet {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.showNewlyScannedSheet = false
                        }
                        if viewModel.newMomentsSheetTriggeredByCreateButton {
                            viewModel.dismissNewMomentsAndOpenPendingCreateFlow()
                        } else {
                            viewModel.clearNewMomentsSignal()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(9)

                NewlyScannedPhotosSheet(
                    photos: viewModel.newlyScannedPhotos,
                    matchedTrip: viewModel.newMomentsInExistingTrip,
                    matchedBlog: viewModel.newMomentsMatchedBlog,
                    onGoToTrip: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.showNewlyScannedSheet = false
                        }
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
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.showNewlyScannedSheet = false
                        }
                        if let blog = viewModel.newMomentsMatchedBlog {
                            createdRecapStore.injectPhotos(
                                viewModel.newlyScannedPhotos,
                                intoSourceTripId: blog.sourceTripId
                            )
                            let recap = createdRecapStore.visibleRecents.first(where: { $0.id == blog.id })
                            if let recap { selectedCreatedRecap = recap }
                        }
                        viewModel.clearNewMomentsSignal()
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.showNewlyScannedSheet = false
                        }
                        if viewModel.newMomentsSheetTriggeredByCreateButton {
                            viewModel.dismissNewMomentsAndOpenPendingCreateFlow()
                        } else {
                            viewModel.clearNewMomentsSignal()
                        }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            }
        }
    }
}

// MARK: - Trip Carousel Card

struct TripCarouselCard: View {
    let trip: TripDraft
    var isSelected: Bool = false
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
                    // Trip title (base title only; episode on next row when split)
                    Text(trip.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Episode line when trip was split (e.g. "Episode 1 of 2")
                    if let episode = trip.displayEpisodeLabel, !episode.isEmpty {
                        Text(episode)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    // Subtitle: daysSeasonText (e.g. "7 days • Mar 2024") or date range + duration
                    Text(trip.daysSeasonText.isEmpty ? "\(trip.tripDateRangeDisplayText)  ·  \(durationText)" : trip.daysSeasonText)
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
    var targetSize: CGSize = CGSize(width: 600, height: 400)

    init(theme: String, coverAssetIdentifier: String? = nil, targetSize: CGSize = CGSize(width: 600, height: 400)) {
        self.theme = theme
        self.coverAssetIdentifier = coverAssetIdentifier
        self.targetSize = targetSize
    }

    /// Convenience init from a TripDraft.
    init(trip: TripDraft, targetSize: CGSize = CGSize(width: 600, height: 400)) {
        self.theme = trip.coverTheme
        self.coverAssetIdentifier = trip.coverAssetIdentifier
        self.targetSize = targetSize
    }

    var body: some View {
        ZStack {
            gradientForTheme(theme)
            if let id = coverAssetIdentifier {
                AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: targetSize)
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

// MARK: - Newly Scanned Photos Sheet

private let newMomentsSheetBg    = Color(red: 10/255, green: 14/255, blue: 52/255)
private let newMomentsCardBg     = Color(red: 28/255, green: 33/255, blue: 72/255)
private let newMomentsDivider    = Color.white.opacity(0.12)

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
        matchedBlog?.title ?? matchedTrip?.displayTitle ?? "Your Trip"
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

    private var newPhotoLabel: String {
        let n = photos.count
        return "\(n) new photo\(n == 1 ? "" : "s") found"
    }

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Sheet content
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        blogCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)

                        // New photo preview strip
                        photoStrip
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }

                // Action buttons pinned at bottom
                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.80)
            .background(newMomentsSheetBg)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .ignoresSafeArea()
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
                    // Badge: "N new photos"
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(newPhotoLabel)
                            .font(.system(size: 12, weight: .semibold))
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
            if matchedBlog != nil {
                Button(action: { onGoToBlog?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                        Text("Add to Blog")
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
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(newMomentsCardBg)
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
