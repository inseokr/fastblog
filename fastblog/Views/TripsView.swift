//
//  TripsView.swift
//  Capper
//

import MapKit
import SwiftUI

struct TripsView: View {
    @ObservedObject var viewModel: TripsViewModel
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @AppStorage("blogify.skipSelectPhotosIntro") private var skipSelectPhotosIntro = false
    @State private var selectedTrip: TripDraft?
    @State private var createBlogFlowTrip: TripDraft?
    /// Sheet offset from top: 0 = expanded (list full), positive = pulled down (map revealed).
    @State private var sheetOffset: CGFloat = 0
    @State private var dragStartSheetOffset: CGFloat = 0
    @State private var mapPosition: MapCameraPosition = .automatic
    /// Top of scroll content in sheet coordinate space. At top when >= -10.
    @State private var scrollContentMinY: CGFloat = 0
    /// Latch state for the drag gesture: true = we are pulling the sheet; false = we are scrolling the list; nil = undetermined (start of gesture).
    @State private var isSheetGestureValid: Bool? = nil

    init(viewModel: TripsViewModel, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedCreatedRecap = selectedCreatedRecap
    }

    @State private var tripForPopup: TripDraft?

    private var shouldShowSelectPhotosIntro: Bool {
        viewModel.scanState == .idle
            && !viewModel.tripDrafts.isEmpty
            && !skipSelectPhotosIntro
            && viewModel.showSelectPhotosIntroAfterScan
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
                TripDraftStore.clearSelection(tripId: createdTripId)
                viewModel.removeTrip(id: createdTripId)
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
                // Banner removed — shown in RecapBlogPageView on first save
            }
        }
        .overlay {
            if let trip = tripForPopup {
                blogCreationPopup(trip: trip)
            }
        }
    }

    // ... (rest of the file until myDraftsSection) ...
    // Note: I cannot replace the whole file easily. I will execute multiple replacements or chunks.
    // Wait, the instruction said "1. Add tripForPopup... 2. Implementation... 3. Update TripDraftRow... 4. Update sections...".
    // I should probably use `multi_replace_file_content` for better precision if I can't comfortably replace a large chunk.
    // However, `TripsView` is 731 lines.
    // I will use `multi_replace_file_content`.
    
    // Changing strategy to `multi_replace_file_content` in the actual tool call below.
    // This block is just for the tool call construction logic.


    private static let listHorizontalPadding: CGFloat = 20
    /// Once sheet is pulled down (offset > this), list scroll is locked. Use small value so lock engages immediately.
    private static let scrollLockThreshold: CGFloat = 0
    /// Scroll content minY >= this (in sheet space) means user is at top; then pull-down closes the sheet.
    private static let scrollAtTopTolerance: CGFloat = 1
    /// Collapsed snap = this fraction of screen height (map revealed).
    private static let collapsedFraction: CGFloat = 0.85

    private struct ScrollContentMinYKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    /// Returns a region that fits all coordinates with padding. Places the latest trip (first in newest-first order) in the center-top area of the map.
    private static func regionFittingCoordinates(
        _ coords: [CLLocationCoordinate2D],
        latestCoord: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let padding = 0.15
        let lonDelta = max(0.02, (maxLon - minLon) + padding)
        let centerLon: CLLocationDegrees
        let centerLat: CLLocationDegrees
        if let latest = latestCoord {
            // Position the latest trip at roughly the top 25% of the visible map.
            // To do this, set the center south of the latest trip so it appears near the top.
            let allSpanLat = max(0.02, (maxLat - minLat) + padding)
            // Ensure the span is large enough to also show trips below the center
            let distBelow = latest.latitude - minLat + padding / 2
            // The latest trip should be at ~25% from the top → 75% of the span is below it
            let neededSpan = max(allSpanLat, distBelow / 0.75)
            let latDelta = neededSpan
            centerLat = latest.latitude - (latDelta * 0.25)
            centerLon = latest.longitude
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        } else {
            let latDelta = max(0.02, (maxLat - minLat) + padding)
            centerLat = (minLat + maxLat) / 2
            centerLon = (minLon + maxLon) / 2
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        }
    }

    private var mainContent: some View {
        GeometryReader { geometry in
            buildMainContentBody(geometry: geometry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
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
        .onChange(of: selectedCreatedRecap) { old, new in
            if new == nil && createdRecapStore.pendingRecapCreated {
                createdRecapStore.pendingRecapCreated = false
                // Banner removed — shown in RecapBlogPageView on first save
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
    }

    private func buildMainContentBody(geometry: GeometryProxy) -> some View {
        let collapsedSnap = geometry.size.height * Self.collapsedFraction
        let isScrollLocked = sheetOffset > Self.scrollLockThreshold

        return ZStack(alignment: .top) {
            mapViewLayer
            
            sheetLayer(collapsedSnap: collapsedSnap, isScrollLocked: isScrollLocked)
        }
        .onAppear {
            dragStartSheetOffset = sheetOffset
        }
        .onChange(of: geometry.size) { _, _ in
            // Keep sheet at valid offset when size changes (e.g. rotation)
            let newCollapsed = geometry.size.height * Self.collapsedFraction
            if sheetOffset > 0 && sheetOffset >= newCollapsed - 1 {
                sheetOffset = newCollapsed
                dragStartSheetOffset = newCollapsed
            }
        }
    }

    private var mapViewLayer: some View {
        TripsMapView(
            trips: viewModel.visibleDraftTrips,
            mapPosition: $mapPosition,
            onTripTapped: { trip in
                createBlogFlowTrip = trip
            }
        )
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if mapPosition == .automatic, !viewModel.visibleDraftTrips.isEmpty {
                let coords = viewModel.visibleDraftTrips.compactMap(\.centerCoordinate)
                let latestCoord = viewModel.visibleDraftTripsNewestFirst.first.flatMap(\.centerCoordinate)
                if !coords.isEmpty, let region = Self.regionFittingCoordinates(coords, latestCoord: latestCoord) {
                    mapPosition = .region(region)
                }
            }
        }
    }

    private func sheetLayer(collapsedSnap: CGFloat, isScrollLocked: Bool) -> some View {
        VStack(spacing: 0) {
            // Grabber handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    myDraftsSection
                    readyToStartSection
                    Spacer(minLength: 100)
                }
                .background(
                    GeometryReader { g in
                        Color.clear.preference(
                            key: ScrollContentMinYKey.self,
                            value: g.frame(in: .named("sheetScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "sheetScroll")
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(isScrollLocked)
            .onPreferenceChange(ScrollContentMinYKey.self) { scrollContentMinY = $0 }

            findMoreTripsButton
        }
        .padding(.horizontal, Self.listHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .ignoresSafeArea()
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .offset(y: sheetOffset)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: sheetOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    // Latching logic: decide intent at the start of the gesture
                    if isSheetGestureValid == nil {
                        let atTop = scrollContentMinY >= -Self.scrollAtTopTolerance
                        // Valid if already pulled down OR at the top of the list
                        isSheetGestureValid = (sheetOffset > 0) || atTop
                    }
                    
                    guard isSheetGestureValid == true else { return }

                    // If we started at top but drag UP (scroll down), clamp to 0. 
                    // If we started at top and drag DOWN (pull release), move sheet.
                    // If we started with sheet open, move sheet.
                    
                    let proposed = dragStartSheetOffset + value.translation.height
                    // Only allow pulling down (positive offset)
                    sheetOffset = min(collapsedSnap, max(0, proposed))
                }
                .onEnded { value in
                    defer {
                        isSheetGestureValid = nil
                        dragStartSheetOffset = sheetOffset
                    }
                    
                    guard isSheetGestureValid == true else { return }
                    
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let mid = collapsedSnap / 2
                    
                    if velocity < -50 || (sheetOffset < mid && velocity <= 0) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            sheetOffset = 0
                        }
                    } else if velocity > 50 || sheetOffset >= mid {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            sheetOffset = collapsedSnap
                        }
                    }
                }
        )
        .onChange(of: sheetOffset) { _, newValue in
            if newValue == 0 {
                dragStartSheetOffset = 0
            } else if abs(newValue - collapsedSnap) < 1 {
                dragStartSheetOffset = collapsedSnap
            }
        }
    }


    
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

    /// Success notification card: icon, title, "Tap to view", optional dismiss. Auto-dismisses after 6s; tap opens latest blog.
    private var recapCreatedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.7, blue: 1), Color(red: 0.3, green: 0.5, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Your recap blog is ready!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Available in your Profile")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createdRecapStore.dismissRecapCreatedBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
                .symbolRenderingMode(.hierarchical)
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
        .onTapGesture {
            if let latest = createdRecapStore.recents.first {
                selectedCreatedRecap = latest
            }
            createdRecapStore.dismissRecapCreatedBanner()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                createdRecapStore.dismissRecapCreatedBanner()
            }
        }
    }

    @ViewBuilder
    private var myDraftsSection: some View {
        if !viewModel.myDraftsNewestFirst.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
            Text("My Drafts")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Continue where you left off")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 16)

        VStack(alignment: .leading, spacing: 16) {
            ForEach(viewModel.myDraftsGroupedByMonth, id: \.monthKey) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.85))
                        ForEach(group.trips) { trip in
                            TripDraftRow(
                                trip: trip,
                                onCoverTapped: { createBlogFlowTrip = trip },
                                onTextTapped: { withAnimation { tripForPopup = trip } }
                            )
                        }
                }
            }
        }
        .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var readyToStartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Trips")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Turn photos into recap blogs")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)

        if viewModel.readyToStartNewestFirst.isEmpty && viewModel.myDraftsNewestFirst.isEmpty {
            emptyScanState
        } else if viewModel.readyToStartNewestFirst.isEmpty {
            Text("No new trips. Tap Find More Trips to scan.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.readyToStartGroupedByMonth, id: \.monthKey) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.85))
                        ForEach(group.trips) { trip in
                            TripDraftRow(
                                trip: trip,
                                onCoverTapped: { createBlogFlowTrip = trip },
                                onTextTapped: { withAnimation { tripForPopup = trip } }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyScanState: some View {
        VStack(spacing: 12) {
            Text("No trips found in the last 90 days")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Try changing the date range or scan older months")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }

    private var findMoreTripsButton: some View {
        Button("Find More Trips") {
            viewModel.openFindMoreSheet()
        }
        .font(.headline)
        .foregroundColor(Color(white: 0.45))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(12)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

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
                        // Allow animation to finish slightly before opening the cover
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
            .background(Color(red: 0.15, green: 0.15, blue: 0.15))
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(200)
    }
}

struct TripDraftRow: View {
    let trip: TripDraft
    var onCoverTapped: () -> Void = {}
    var onTextTapped: () -> Void = {}

    private static let cardCornerRadius: CGFloat = 12
    private static let contentPadding: CGFloat = 16
    private static let draftBadgePadding: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverSection
            textSection
        }
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
    }

    private var coverSection: some View {
        ZStack(alignment: .topLeading) {
            TripCoverImage(theme: trip.coverTheme, coverAssetIdentifier: trip.coverAssetIdentifier)
                .aspectRatio(16/10, contentMode: .fill)
                .frame(height: 180)
                .clipped()

            Text("\(trip.totalPhotoCount) Photos")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55))
                .cornerRadius(6)
                .padding(Self.draftBadgePadding)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCoverTapped)
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tripCardTitleLine)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(trip.tripDateRangeDisplayText)
                .font(.subheadline)
                .foregroundColor(Color(white: 0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.contentPadding)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTextTapped)
    }

    /// "Trip to [City Name] in [Season]" (e.g. "Trip to Daegu in Winter"). Season empty when unknown. Matches defaultBlogTitle used when editing the blog title.
    private var tripCardTitleLine: String {
        trip.defaultBlogTitle
    }
}

/// Photo-like cover gradients keyed by theme (Iceland = aurora, Morocco = lanterns, etc.). When coverAssetIdentifier is set, shows that photo from the library.
struct TripCoverImage: View {
    let theme: String
    var coverAssetIdentifier: String? = nil
    var targetSize: CGSize = CGSize(width: 600, height: 400)

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

    /// If you add images to Assets (e.g. IcelandCover, MoroccoCover), they'll show here
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
