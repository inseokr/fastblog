//
//  TripsView.swift
//  Capper
//

import MapKit
import SwiftUI

struct TripsView: View {
    @ObservedObject var viewModel: TripsViewModel
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

    init(viewModel: TripsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

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
    }

    private static let listHorizontalPadding: CGFloat = 20
    /// Once sheet is pulled down (offset > this), list scroll is locked. Use small value so lock engages immediately.
    private static let scrollLockThreshold: CGFloat = 0
    /// Scroll content minY >= this (in sheet space) means user is at top; then pull-down closes the sheet.
    private static let scrollAtTopTolerance: CGFloat = 10
    /// Collapsed snap = this fraction of screen height (map revealed).
    private static let collapsedFraction: CGFloat = 0.42

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
            let collapsedSnap = geometry.size.height * Self.collapsedFraction
            let isScrollLocked = sheetOffset > Self.scrollLockThreshold

            ZStack(alignment: .top) {
                // Map behind the list (full screen)
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

                // List sheet: grabber + scroll list + Find More button
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
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .ignoresSafeArea()
                )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
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
                        TripDraftRow(trip: trip)
                            .onTapGesture { createBlogFlowTrip = trip }
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
                            TripDraftRow(trip: trip)
                                .onTapGesture { createBlogFlowTrip = trip }
                        }
                    }
                }
            }
        }
    }

    private var emptyScanState: some View {
        VStack(spacing: 12) {
            Text("No trips found in the selected range")
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
}

struct TripDraftRow: View {
    let trip: TripDraft

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

    var body: some View {
        ZStack {
            gradientForTheme(theme)
            if let id = coverAssetIdentifier {
                AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 600, height: 400))
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
        TripsView(viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
    }
}
