//
//  VisitedCitiesSheet.swift
//  fastblog
//

import CoreLocation
import MapKit
import Photos
import SwiftUI
import UIKit

// MARK: - Sheet

struct VisitedCitiesSheet: View {
    @ObservedObject var viewModel: TripsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var yearTripsCache: [Int: [VisitedCityTrip]] = [:]
    @State private var selectedTripIds: Set<UUID> = []
    @State private var isCreatingBlog: Bool = false
    @State private var unavailableAlertMessage: String = ""
    @State private var showUnavailableAlert: Bool = false
    @State private var selectionAlertTitle: String = "Unavailable for Selection"
    @State private var showLongSingleStayWarning: Bool = false
    @State private var pendingLongStayTrips: [VisitedCityTrip] = []
    @State private var showCoverPreviewSheet: Bool = false
    @State private var coverPreviewTrip: VisitedCityTrip?
    @State private var coverPreviewMainImage: UIImage?
    @State private var coverPreviewExtraAssetIds: [String] = []
    @State private var coverPreviewCoordinate: CLLocationCoordinate2D?
    @State private var tripsListResetToken: UUID = UUID()

    private let currentYear = Calendar.current.component(.year, from: Date())
    private var availableYears: [Int] { [currentYear, currentYear - 1, currentYear - 2, currentYear - 3] }
    private var currentUserId: String { AuthStateManager.shared.currentUserId ?? "guest" }
    private let createdRecapStore = CreatedRecapBlogStore.shared

    // MARK: - Derived data

    private var selectedYearTrips: [VisitedCityTrip] {
        yearTripsCache[viewModel.visitedCitiesYear] ?? viewModel.visitedCityTrips
    }

    private var allLoadedTrips: [VisitedCityTrip] {
        yearTripsCache.values.flatMap { $0 }
            .sorted { $0.startDate > $1.startDate }
    }

    private var filteredTrips: [VisitedCityTrip] {
        let source = searchText.isEmpty ? selectedYearTrips : allLoadedTrips
        guard !searchText.isEmpty else { return source }
        let q = searchText.lowercased()
        return source.filter {
            $0.cityName.lowercased().contains(q) || $0.countryName.lowercased().contains(q)
        }
    }

    private var selectedDateRangeText: String {
        var seen = Set<UUID>()
        let trips = (allLoadedTrips + selectedYearTrips).filter {
            guard selectedTripIds.contains($0.id), seen.insert($0.id).inserted else { return false }
            return true
        }
        guard !trips.isEmpty,
              let start = trips.map(\.startDate).min(),
              let end = trips.map(\.endDate).max() else { return "No selection" }
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: end)
    }

    /// Places not already in a blog, oldest → newest (used for continuous selection).
    private var availableTripsChronological: [VisitedCityTrip] {
        filteredTrips.filter { !isUnavailableForSelection($0) }.sorted { $0.startDate < $1.startDate }
    }

    private func pruneSelectionToVisibleTrips() {
        let visible = Set(filteredTrips.map(\.id))
        selectedTripIds = selectedTripIds.filter { visible.contains($0) }
    }

    private var groupedFilteredTrips: [(monthStart: Date, title: String, trips: [VisitedCityTrip])] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM"
        let cal = Calendar.current

        let grouped = Dictionary(grouping: filteredTrips) { trip in
            let c = cal.dateComponents([.year, .month], from: trip.startDate)
            return cal.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? trip.startDate
        }

        return grouped
            .map { monthStart, trips in
                let title: String
                title = formatter.string(from: monthStart)
                return (monthStart: monthStart, title: title, trips: trips.sorted { $0.startDate < $1.startDate })
            }
            .sorted { $0.monthStart < $1.monthStart }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlsHeader

                ZStack {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                    switch viewModel.visitedCitiesBuildState {
                    case .building(let p):
                        if viewModel.visitedCityTrips.isEmpty {
                            buildingView(progress: p)
                        } else {
                            VStack(spacing: 0) {
                                scanningBanner(progress: p)
                                if filteredTrips.isEmpty { emptyView } else { tripsListView }
                            }
                        }
                    case .idle:
                        buildingView(progress: 0)
                    case .done:
                        if filteredTrips.isEmpty { emptyView } else { tripsListView }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.loadVisitedCities(year: viewModel.visitedCitiesYear)
                seedCurrentYearCache()
                if !searchText.isEmpty { warmAllYearsForSearch() }
            }
            .onReceive(viewModel.$visitedCityTrips) { trips in
                yearTripsCache[viewModel.visitedCitiesYear] = trips
            }
            .onChange(of: searchText) { _, newValue in
                pruneSelectionToVisibleTrips()
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    warmAllYearsForSearch()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if case .done = viewModel.visitedCitiesBuildState,
                   !filteredTrips.isEmpty {
                    selectionBottomOverlay
                        .background(alignment: .bottom) {
                            Color.black
                                .ignoresSafeArea(.keyboard, edges: .bottom)
                        }
                }
            }
        }
        .alert(selectionAlertTitle, isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(unavailableAlertMessage)
        }
        .alert("Long stay", isPresented: $showLongSingleStayWarning) {
            Button("Cancel", role: .cancel) { pendingLongStayTrips = [] }
            Button("Continue") {
                let trips = pendingLongStayTrips
                pendingLongStayTrips = []
                startCreateBlogTask(with: trips)
            }
        } message: {
            Text("This place spans more than 7 days. Building the blog may take longer. Continue?")
        }
        .sheet(isPresented: $showCoverPreviewSheet, onDismiss: {
            resetCoverPreviewState()
        }) {
            if let trip = coverPreviewTrip, let main = coverPreviewMainImage {
                VisitedCityMomentPreviewSheet(
                    trip: trip,
                    mainImage: main,
                    coverAssetId: trip.coverAssetIdentifier,
                    extraAssetIds: coverPreviewExtraAssetIds,
                    fallbackCoordinate: coverPreviewCoordinate
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Controls header (always visible)

    private var controlsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            topNavigationHeader
                .padding(.bottom, 20)

            searchBarView
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            guard viewModel.visitedCitiesYear != year else { return }
                            viewModel.visitedCitiesYear = year
                            selectedTripIds.removeAll()
                            viewModel.loadVisitedCities(year: year)
                            tripsListResetToken = UUID()
                        } label: {
                            Text(String(year))
                                .font(.system(size: 14, weight: viewModel.visitedCitiesYear == year ? .semibold : .medium))
                                .foregroundStyle(viewModel.visitedCitiesYear == year ? Color.white : Color.primary.opacity(0.75))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.visitedCitiesYear == year ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            viewModel.visitedCitiesYear == year
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.25),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(.bottom, 16)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(filteredTrips.count) \(filteredTrips.count == 1 ? "trip" : "trips")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Select memories to create a blog")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .done = viewModel.visitedCitiesBuildState {
                    Button("Rescan memories") {
                        viewModel.refreshVisitedCities()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var topNavigationHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")

            Spacer()

            Text("Your Memories")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Keeps title optically centered against the leading close button.
            Color.clear
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
        }
    }

    private var selectionBottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selecting multiple memories will be merged into one blog.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .center) {
                Text("\(selectedTripIds.count) selected")
                    .font(.system(size: 15, weight: .semibold))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()

                Button {
                    beginCreateBlogFromSelection()
                } label: {
                    if isCreatingBlog {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(width: 120)
                    } else {
                        Text(selectedTripIds.isEmpty ? "Select memories" : "Create Blog")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(minWidth: 120)
                    }
                }
                .disabled(isCreatingBlog || selectedTripIds.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Search bar

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Search city or country", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(UIColor.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    // MARK: - Trip list

    private var tripsListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(groupedFilteredTrips, id: \.monthStart) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(Array(group.trips.enumerated()), id: \.element.id) { index, trip in
                                CityTripRow(
                                    trip: trip,
                                    isSelected: selectedTripIds.contains(trip.id),
                                    isUnavailable: isUnavailableForSelection(trip),
                                    interactionLabel: interactionLabel(for: trip),
                                    onToggleSelection: { handleToggle(trip) },
                                    onTapCover: { openCoverPreview(for: trip) }
                                )
                                if index < group.trips.count - 1 {
                                    Divider().padding(.leading, 92)
                                }
                            }
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .padding(.top, 10)
            }
        }
        .id(tripsListResetToken)
    }

    // MARK: - Scanning banner (shown above existing results while scanning)

    private func scanningBanner(progress: Double) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("Loading trips from \(String(viewModel.visitedCitiesYear))...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress > 0 ? progress : nil)
                .progressViewStyle(.linear)
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Building (full-screen, no results yet)

    @ViewBuilder
    private func buildingView(progress: Double) -> some View {
        LoadingScanView(
            message: "Loading Trips from \(String(viewModel.visitedCitiesYear))",
            isOverlay: false,
            progress: progress > 0 ? progress : 0,
            onCancel: nil,
            onUseCamera: nil,
            onClose: nil,
            progressStepLabelOverride: { p in
                p >= 0.9 ? "Almost done..." : "Please wait..."
            },
            backgroundColorOverride: Color(UIColor.systemGroupedBackground),
            useCenteredLayout: true
        )
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No Places in \(String(viewModel.visitedCitiesYear))" : "No Results Across Years")
                .font(.title3)
                .fontWeight(.semibold)
            Text(searchText.isEmpty
                 ? "No location-tagged photos from \(String(viewModel.visitedCitiesYear)) were found outside your home area."
                 : "No places matching \"\(searchText)\" in the last four years.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Selection / availability

    private func isUnavailableForSelection(_ trip: VisitedCityTrip) -> Bool {
        createdRecapStore.visibleRecents.contains { blog in
            guard let start = blog.tripStartDate, let end = blog.tripEndDate else { return false }
            return trip.endDate >= start && trip.startDate <= end
        }
    }

    private func interactionLabel(for trip: VisitedCityTrip) -> String {
        if isUnavailableForSelection(trip) { return "Already added to a blog" }
        if selectedTripIds.contains(trip.id) { return "Selected" }
        return "Available to select"
    }

    /// Fills every available place between the earliest and latest selected (chronological).
    private func expandSelectionToContinuousRange() {
        let avail = availableTripsChronological
        let indices = avail.indices.filter { selectedTripIds.contains(avail[$0].id) }
        guard let minI = indices.min(), let maxI = indices.max() else { return }
        selectedTripIds = Set(avail[minI...maxI].map(\.id))
    }

    private func handleToggle(_ trip: VisitedCityTrip) {
        if isUnavailableForSelection(trip) {
            selectionAlertTitle = "Unavailable for Selection"
            unavailableAlertMessage = "\"\(trip.displayTitle)\" is already part of a created/saved blog. Remove overlapping blogs or pick other places."
            showUnavailableAlert = true
            return
        }
        if selectedTripIds.contains(trip.id) {
            let selInOrder = availableTripsChronological.filter { selectedTripIds.contains($0.id) }
            if selInOrder.count <= 1 {
                selectedTripIds.remove(trip.id)
                return
            }
            if trip.id != selInOrder.first?.id && trip.id != selInOrder.last?.id {
                selectionAlertTitle = "Unavailable for Selection"
                unavailableAlertMessage = "To narrow your selection, remove a place at the start or end of the range, or tap Clear."
                showUnavailableAlert = true
                return
            }
            selectedTripIds.remove(trip.id)
        } else {
            let before = selectedTripIds
            selectedTripIds.insert(trip.id)
            expandSelectionToContinuousRange()
            let built = selectedTripsForBuild()
            let span = calendarSpanDays(of: built)
            if span > 7, built.count >= 2 {
                selectedTripIds = before
                selectionAlertTitle = "Too many days"
                unavailableAlertMessage = "You can select up to 7 days across multiple places. Remove places from the start or end of the range, or choose a shorter stretch."
                showUnavailableAlert = true
            }
        }
    }

    private func selectedTripsForBuild() -> [VisitedCityTrip] {
        var seen = Set<UUID>()
        return (allLoadedTrips + selectedYearTrips).filter {
            guard selectedTripIds.contains($0.id), seen.insert($0.id).inserted else { return false }
            return true
        }
    }

    private func calendarSpanDays(of trips: [VisitedCityTrip]) -> Int {
        guard let start = trips.map(\.startDate).min(),
              let end = trips.map(\.endDate).max() else { return 0 }
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: start)
        let d1 = cal.startOfDay(for: end)
        return (cal.dateComponents([.day], from: d0, to: d1).day ?? 0) + 1
    }

    private func beginCreateBlogFromSelection() {
        let trips = selectedTripsForBuild()
        guard !trips.isEmpty else {
            selectionAlertTitle = "Nothing selected"
            unavailableAlertMessage = "Select at least one place to create a blog."
            showUnavailableAlert = true
            return
        }
        for trip in trips where isUnavailableForSelection(trip) {
            selectionAlertTitle = "Unavailable for Selection"
            unavailableAlertMessage = "Your selection includes \"\(trip.displayTitle)\", which overlaps a blog you already created. Adjust your selection."
            showUnavailableAlert = true
            return
        }
        let span = calendarSpanDays(of: trips)
        if span > 7 {
            if trips.count == 1 {
                pendingLongStayTrips = trips
                showLongSingleStayWarning = true
                return
            }
            selectionAlertTitle = "Too many days"
            unavailableAlertMessage = "You can select up to 7 days across multiple places. Narrow your selection with Clear or by removing places from the start or end of the range."
            showUnavailableAlert = true
            return
        }
        startCreateBlogTask(with: trips)
    }

    private func startCreateBlogTask(with trips: [VisitedCityTrip]) {
        isCreatingBlog = true
        Task {
            let success = await viewModel.createTripFromVisitedCitiesSelection(trips)
            await MainActor.run {
                isCreatingBlog = false
                if success {
                    dismiss()
                } else {
                    selectionAlertTitle = "Unavailable for Selection"
                    unavailableAlertMessage = "Could not build a trip from the selected places. Try selecting a wider date span."
                    showUnavailableAlert = true
                }
            }
        }
    }

    // MARK: - Cover preview

    private func resetCoverPreviewState() {
        coverPreviewTrip = nil
        coverPreviewMainImage = nil
        coverPreviewExtraAssetIds = []
        coverPreviewCoordinate = nil
    }

    /// Up to three other located photos from the same trip date span (cover excluded).
    private func fetchAdditionalAssetLocalIdentifiers(for trip: VisitedCityTrip, excluding coverId: String?) -> [String] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        guard let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: trip.endDate) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var ids: [String] = []
        result.enumerateObjects { asset, _, stop in
            guard !asset.mediaSubtypes.contains(.photoScreenshot), asset.location != nil else { return }
            if asset.localIdentifier == coverId { return }
            ids.append(asset.localIdentifier)
            if ids.count >= 3 { stop.pointee = true }
        }
        return ids
    }

    /// Cover may lack `location` while other trip-day assets have GPS; fall back to any located asset in the trip window.
    private func resolveCoordinateForPreview(trip: VisitedCityTrip, coverAssetId: String?) -> CLLocationCoordinate2D? {
        if let coverId = coverAssetId,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [coverId], options: nil).firstObject,
           let loc = asset.location {
            return loc.coordinate
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        guard let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: trip.endDate) else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var found: CLLocationCoordinate2D?
        result.enumerateObjects { asset, _, stop in
            guard !asset.mediaSubtypes.contains(.photoScreenshot), let loc = asset.location else { return }
            found = loc.coordinate
            stop.pointee = true
        }
        return found
    }

    private func openCoverPreview(for trip: VisitedCityTrip) {
        guard let assetId = trip.coverAssetIdentifier else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: opts
        ) { image, _ in
            guard let image else { return }
            coverPreviewTrip = trip
            coverPreviewMainImage = image
            coverPreviewExtraAssetIds = fetchAdditionalAssetLocalIdentifiers(for: trip, excluding: assetId)
            coverPreviewCoordinate = resolveCoordinateForPreview(trip: trip, coverAssetId: assetId)
            showCoverPreviewSheet = true
        }
    }

    // MARK: - Search across years

    private func seedCurrentYearCache() {
        if yearTripsCache[viewModel.visitedCitiesYear] == nil {
            yearTripsCache[viewModel.visitedCitiesYear] = viewModel.visitedCityTrips
        }
    }

    private func warmAllYearsForSearch() {
        Task {
            for year in availableYears where yearTripsCache[year] == nil {
                if let cached = VisitedCitiesService.shared.loadCached(userId: currentUserId, year: year) {
                    await MainActor.run { yearTripsCache[year] = cached }
                } else {
                    let built = await VisitedCitiesService.shared.buildVisitedCities(year: year) { _ in }
                    VisitedCitiesService.shared.saveCache(built, userId: currentUserId, year: year)
                    await MainActor.run { yearTripsCache[year] = built }
                }
            }
        }
    }
}

// MARK: - Full-screen cover / moment preview

private struct VisitedCityMomentPreviewSheet: View {
    let trip: VisitedCityTrip
    let mainImage: UIImage
    let coverAssetId: String?
    let extraAssetIds: [String]
    let fallbackCoordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [UIImage]
    /// Parallel to `photos`; empty string means no asset id for that slot.
    @State private var photoAssetIds: [String]
    @State private var selectedIndex: Int = 0
    @State private var isLoadingMorePhotos = false
    @State private var mapPosition: MapCameraPosition
    @State private var digitizedTimeDisplay: String?

    init(
        trip: VisitedCityTrip,
        mainImage: UIImage,
        coverAssetId: String?,
        extraAssetIds: [String],
        fallbackCoordinate: CLLocationCoordinate2D?
    ) {
        self.trip = trip
        self.mainImage = mainImage
        self.coverAssetId = coverAssetId
        self.extraAssetIds = extraAssetIds
        self.fallbackCoordinate = fallbackCoordinate
        _photos = State(initialValue: [mainImage])
        if let c = coverAssetId {
            _photoAssetIds = State(initialValue: [c])
        } else {
            _photoAssetIds = State(initialValue: [""])
        }
        if let c = fallbackCoordinate {
            _mapPosition = State(
                initialValue: .region(
                    MKCoordinateRegion(
                        center: c,
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )
                )
            )
        } else {
            _mapPosition = State(initialValue: .automatic)
        }
    }

    private var headingLine: String {
        if trip.cityName.isEmpty {
            return trip.countryName.isEmpty ? trip.displayTitle : trip.countryName
        }
        if trip.countryName.isEmpty || trip.cityName == trip.countryName {
            return trip.cityName
        }
        return "\(trip.cityName), \(trip.countryName)"
    }

    private var mapCoordinateForSelection: CLLocationCoordinate2D? {
        guard photos.indices.contains(selectedIndex),
              photoAssetIds.indices.contains(selectedIndex) else { return fallbackCoordinate }
        let id = photoAssetIds[selectedIndex]
        if !id.isEmpty,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
           let loc = asset.location {
            return loc.coordinate
        }
        return fallbackCoordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        photoHeroWithThumbnailStrip

                        if mapCoordinateForSelection != nil {
                            mapSection
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(headingLine)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(trip.displaySubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedIndex) { _, _ in
            syncMapToSelection()
        }
        .onAppear {
            syncMapToSelection()
        }
        .task {
            await loadAdditionalPhotosIfNeeded()
        }
        .task(id: "\(selectedIndex)-\(photoAssetIds.count)") {
            await refreshDigitizedTime()
        }
    }

    /// e.g. "2025 Mar 5, 02:03 AM PST" — wall clock and zone label from capture timezone (EXIF or photo GPS), not device.
    private func refreshDigitizedTime() async {
        guard photoAssetIds.indices.contains(selectedIndex) else {
            await MainActor.run { digitizedTimeDisplay = nil }
            return
        }
        let id = photoAssetIds[selectedIndex]
        guard !id.isEmpty,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              let date = asset.creationDate else {
            await MainActor.run { digitizedTimeDisplay = nil }
            return
        }
        let resolved = await APIManager.captureTimeZone(for: asset) ?? TimeZone(identifier: "UTC")!
        let str = Self.formattedCaptureDate(creationDate: date, timeZone: resolved)
        await MainActor.run { digitizedTimeDisplay = str }
    }

    private static func formattedCaptureDate(creationDate: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy MMM d, hh:mm a"
        let formatted = f.string(from: creationDate)
        let zoneLabel =
            timeZone.abbreviation(for: creationDate)
            ?? timeZone.localizedName(for: .shortStandard, locale: Locale(identifier: "en_US_POSIX"))
            ?? timeZone.identifier
        return "\(formatted) \(zoneLabel)"
    }

    private var photoHeroWithThumbnailStrip: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: photos[selectedIndex])
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                if isLoadingMorePhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading more photos…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                }

                if let digitized = digitizedTimeDisplay {
                    Text(digitized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos.indices, id: \.self) { i in
                            Button {
                                selectedIndex = i
                            } label: {
                                Image(uiImage: photos[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedIndex == i ? Color.white : Color.white.opacity(0.25), lineWidth: selectedIndex == i ? 3 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(height: UIScreen.main.bounds.height * 0.8)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Scroll for map", systemImage: "map")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let c = mapCoordinateForSelection {
                Map(position: $mapPosition) {
                    Annotation("Photo", coordinate: c) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .colorScheme(.light)
                .id("\(c.latitude)-\(c.longitude)-\(selectedIndex)")
            }
        }
        .padding(.horizontal, 16)
    }

    private func syncMapToSelection() {
        guard let c = mapCoordinateForSelection else { return }
        mapPosition = .region(
            MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
    }

    private func loadAdditionalPhotosIfNeeded() async {
        guard !extraAssetIds.isEmpty else { return }
        await MainActor.run { isLoadingMorePhotos = true }
        var loaded: [UIImage] = []
        for id in extraAssetIds {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { continue }
            if let img = await Self.requestImage(for: asset) {
                loaded.append(img)
            }
        }
        await MainActor.run {
            isLoadingMorePhotos = false
            guard !loaded.isEmpty else { return }
            photos = [mainImage] + loaded
            var ids: [String] = []
            if let c = coverAssetId {
                ids.append(c)
            } else {
                ids.append("")
            }
            ids.append(contentsOf: extraAssetIds.prefix(loaded.count))
            photoAssetIds = ids
        }
    }

    private static func requestImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.resizeMode = .fast
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: opts
            ) { image, _ in
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: image)
            }
        }
    }
}

// MARK: - Row

private struct CityTripRow: View {
    let trip: VisitedCityTrip
    let isSelected: Bool
    let isUnavailable: Bool
    let interactionLabel: String
    let onToggleSelection: () -> Void
    let onTapCover: () -> Void

    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onTapCover()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 60, height: 60)

                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                onToggleSelection()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trip.displayTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(trip.displaySubtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if isUnavailable {
                            Text("Already added")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.88, green: 0.52, blue: 0.56))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(Color(red: 0.88, green: 0.52, blue: 0.56).opacity(0.16))
                                )
                        } else {
                            Text(interactionLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: checkboxIconName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(
                            isUnavailable
                                ? Color.gray.opacity(0.45)
                                : (isSelected ? Color.accentColor : Color.secondary.opacity(0.8))
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isUnavailable)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .opacity(isUnavailable ? 0.75 : 1)
        .onAppear { loadThumbnail() }
    }

    private var checkboxIconName: String {
        if isUnavailable { return "square" }
        return isSelected ? "checkmark.square.fill" : "square"
    }

    private func loadThumbnail() {
        guard let id = trip.coverAssetIdentifier else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.isNetworkAccessAllowed = false
        opts.isSynchronous = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 108, height: 108),
            contentMode: .aspectFill,
            options: opts
        ) { img, _ in
            if let img { coverImage = img }
        }
    }
}
