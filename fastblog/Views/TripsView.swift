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
    /// Show "Load more trips?" popup when user scrolls to the last trip.
    @State private var showLoadMorePopup = false
    /// Guards against the popup firing on the initial programmatic selection in onAppear.
    @State private var didCompleteInitialSelection = false
    /// True while the carousel is animating the map to a new trip — blocks onMapRegionChanged
    /// from firing back and jumping the scroll position mid-animation.
    @State private var isAnimatingMapFromCarousel = false
    /// Snapshot of allTrips.count taken just before a load-older scan starts, so we know
    /// which index the first new trip lands at after the scan completes.
    @State private var tripCountBeforeOlderScan: Int = 0

    init(viewModel: TripsViewModel, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedCreatedRecap = selectedCreatedRecap
    }

    private var shouldShowSelectPhotosIntro: Bool {
        viewModel.scanState == .idle
            && !viewModel.tripDrafts.isEmpty
            && !skipSelectPhotosIntro
            && viewModel.showSelectPhotosIntroAfterScan
    }

    /// All visible trips sorted newest first — flat list for carousel.
    private var allTrips: [TripDraft] {
        viewModel.visibleDraftTripsNewestFirst
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
                LoadingScanView(message: viewModel.loadingMessage)
            } else if shouldShowSelectPhotosIntro {
                SelectPhotosIntroView { dontShowAgain in
                    if dontShowAgain { skipSelectPhotosIntro = true }
                    viewModel.showSelectPhotosIntroAfterScan = false
                }
                .navigationTitle("Trips")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                mainContent
            }
        }
        .navigationDestination(item: $selectedCreatedRecap) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: CreatedRecapBlogStore.shared.tripDraft(for: recap.sourceTripId)
            )
        }
        .navigationDestination(item: $selectedTrip) { trip in
            TripDayPickerView(
                trip: viewModel.tripForPicker(trip),
                onStartCreateBlog: { createBlogFlowTrip = $0 }
            )
        }
        .fullScreenCover(item: $createBlogFlowTrip) { trip in
            CreateBlogFlowView(trip: trip, startDirectlyCreating: true) { createdTripId in
                createBlogFlowTrip = nil
                selectedTrip = nil
            }
            .environmentObject(CreatedRecapBlogStore.shared)
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
            if viewModel.isLoadingOlderTrips {
                LoadingScanView(
                    message: "Scanning older photos…",
                    isOverlay: true,
                    progress: viewModel.loadOlderProgress,
                    onCancel: {
                        viewModel.cancelLoadOlderTrips()
                        // Restore the popup so the user isn't stranded on the last card
                        withAnimation(.easeOut(duration: 0.3)) { showLoadMorePopup = true }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.isLoadingOlderTrips)
        // Always disable default back button to unconditionally prevent the swipe-to-go-back gesture, 
        // which users can accidentally trigger when swiping the carousel from left to right.
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.olderTripsResult) { _, result in
            if case .success = result {
                // New trips appended — dismiss popup and scroll to the first new trip.
                withAnimation(.easeInOut(duration: 0.3)) { showLoadMorePopup = false }
                // allTrips is sorted newest→oldest, so the first newly loaded trip sits
                // at index tripCountBeforeOlderScan (right after the old last card).
                let trips = allTrips
                if tripCountBeforeOlderScan < trips.count {
                    let firstNewTrip = trips[tripCountBeforeOlderScan]
                    // Brief delay lets SwiftUI finish inserting the new rows before scrolling.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            selectedTripID = firstNewTrip.id
                        }
                    }
                }
            } else if case .empty = result {
                // No older trips found — keep popup open so user sees the message,
                // then auto-dismiss after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.3)) { showLoadMorePopup = false }
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
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Back")
                    }
                }
                .opacity((showLoadMorePopup || viewModel.isLoadingOlderTrips) ? 0 : 1)
                .disabled(showLoadMorePopup || viewModel.isLoadingOlderTrips)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.openFindMoreSheet()
                } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.body)
                        .foregroundColor(.white)
                }
            }
        }
        .overlay(alignment: .top) {
            if createdRecapStore.showDraftSavedToast {
                draftSavedToast
            }
        }
        .onDisappear {
            createdRecapStore.showDraftSavedToast = false
        }
        // Surface the Limited banner only when scan finishes with weak results
        .onChange(of: viewModel.scanState) { _, newState in
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
            trips: viewModel.visibleDraftTrips,
            selectedTripID: $selectedTripID,
            mapPosition: $mapPosition,
            onTripTapped: { trip in
                if trip.id == selectedTripID {
                    createBlogFlowTrip = trip
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedTripID = trip.id
                    }
                }
            },
            onMapRegionChanged: { center in
                // Don't interrupt a carousel-driven map animation — intermediate camera
                // positions would cause the scroll view to jump around.
                guard !isAnimatingMapFromCarousel else { return }
                // Find the trip closest to the map center
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
            let trips = allTrips
            if !trips.isEmpty {
                // Set initial selection to newest trip
                let firstTrip = trips.first
                selectedTripID = firstTrip?.id
                
                // Center the map on the newest trip's coordinates
                if let center = firstTrip?.centerCoordinate {
                    let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                    mapPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
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
                                // Already centered — open blog creation
                                createBlogFlowTrip = trip
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
        .scrollPosition(id: $selectedTripID)
        .contentMargins(.horizontal, 24)
        .frame(height: 240)
        // Detect an attempt to swipe past the last card (leftward drag while already on it).
        // The ScrollView rubber-bands naturally; we also pop the "Load older trips" sheet.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let isLeftwardDrag = value.translation.width < -40
                    guard isLeftwardDrag,
                          selectedTripID == allTrips.last?.id,
                          allTrips.count > 1,
                          !viewModel.isLoadingOlderTrips,
                          !showLoadMorePopup else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        showLoadMorePopup = true
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
                Text(photoAuth.status == .limited ? "Select More Photos" : "Scan Photos for More Trips")
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

                Text("Scan photos from the previous 3 months to find more trips.")
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
                            // Snapshot the current count so we can scroll to the first new
                            // trip after the scan completes.
                            tripCountBeforeOlderScan = allTrips.count
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
                    // Trip title
                    Text(trip.defaultBlogTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Date range + duration
                    Text("\(trip.tripDateRangeDisplayText)  ·  \(durationText)")
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

#Preview {
    NavigationStack {
        TripsView(
            viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            selectedCreatedRecap: .constant(nil)
        )
    }
}
