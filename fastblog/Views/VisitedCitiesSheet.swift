//
//  VisitedCitiesSheet.swift
//  fastblog
//

import Photos
import SwiftUI

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
    @State private var previewImage: UIImage?
    @State private var showImagePreview: Bool = false
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
        guard let start = trips.map(\.startDate).min(),
              let end = trips.map(\.endDate).max() else { return "" }
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: end)
    }

    private var groupedFilteredTrips: [(monthStart: Date, title: String, trips: [VisitedCityTrip])] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
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
            .navigationTitle("Your memories")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.loadVisitedCities(year: viewModel.visitedCitiesYear)
                seedCurrentYearCache()
                if !searchText.isEmpty { warmAllYearsForSearch() }
            }
            .onReceive(viewModel.$visitedCityTrips) { trips in
                yearTripsCache[viewModel.visitedCitiesYear] = trips
            }
            .onChange(of: searchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    warmAllYearsForSearch()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .done = viewModel.visitedCitiesBuildState {
                        Button { viewModel.refreshVisitedCities() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !selectedTripIds.isEmpty {
                    selectionBottomOverlay
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .alert("Unavailable for Selection", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(unavailableAlertMessage)
        }
        .sheet(isPresented: $showImagePreview, onDismiss: {
            previewImage = nil
        }) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Controls header (always visible)

    private var controlsHeader: some View {
        VStack(spacing: 8) {
            searchBarView

            Picker("Year", selection: $viewModel.visitedCitiesYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.visitedCitiesYear) { _, newYear in
                viewModel.loadVisitedCities(year: newYear)
                tripsListResetToken = UUID()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var selectionBottomOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedTripIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear") { selectedTripIds.removeAll() }
                    .font(.subheadline)
            }
            HStack {
                Label(selectedDateRangeText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    createBlogFromSelection()
                } label: {
                    if isCreatingBlog {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(width: 120)
                    } else {
                        Text("Create Blog")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(minWidth: 120)
                    }
                }
                .disabled(isCreatingBlog)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(UIColor.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Trip list

    private var tripsListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text(searchText.isEmpty ? String(viewModel.visitedCitiesYear) : "All Years")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text("\(filteredTrips.count) \(filteredTrips.count == 1 ? "place" : "places")")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                VStack(spacing: 12) {
                    ForEach(groupedFilteredTrips, id: \.monthStart) { group in
                        VStack(spacing: 0) {
                            HStack {
                                Text(group.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)

                            VStack(spacing: 0) {
                                ForEach(Array(group.trips.enumerated()), id: \.element.id) { index, trip in
                                    CityTripRow(
                                        trip: trip,
                                        isSelected: selectedTripIds.contains(trip.id),
                                        isUnavailable: isUnavailableForSelection(trip),
                                        onToggleSelection: { handleToggle(trip) },
                                        onTapCover: { assetId in openCoverPreview(assetId: assetId) }
                                    )
                                    if index < group.trips.count - 1 {
                                        Divider().padding(.leading, 82)
                                    }
                                }
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .id(tripsListResetToken)
    }

    // MARK: - Scanning banner (shown above existing results while scanning)

    private func scanningBanner(progress: Double) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("Scanning \(String(viewModel.visitedCitiesYear))…")
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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Scanning Photo Library")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Finding places you visited in \(String(viewModel.visitedCitiesYear))…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 8) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                    .tint(.blue)
                if progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
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

    private func handleToggle(_ trip: VisitedCityTrip) {
        if isUnavailableForSelection(trip) {
            unavailableAlertMessage = "\"\(trip.displayTitle)\" is already part of a created/saved blog, so it cannot be selected."
            showUnavailableAlert = true
            return
        }
        if selectedTripIds.contains(trip.id) {
            selectedTripIds.remove(trip.id)
        } else {
            selectedTripIds.insert(trip.id)
        }
    }

    private func createBlogFromSelection() {
        var seen = Set<UUID>()
        let trips = (allLoadedTrips + selectedYearTrips).filter {
            guard selectedTripIds.contains($0.id), seen.insert($0.id).inserted else { return false }
            return true
        }
        guard !trips.isEmpty else { return }
        isCreatingBlog = true
        Task {
            let success = await viewModel.createTripFromVisitedCitiesSelection(trips)
            await MainActor.run {
                isCreatingBlog = false
                if success {
                    dismiss()
                } else {
                    unavailableAlertMessage = "Could not build a trip from the selected places. Try selecting a wider date span."
                    showUnavailableAlert = true
                }
            }
        }
    }

    // MARK: - Cover preview

    private func openCoverPreview(assetId: String?) {
        guard let assetId else { return }
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
            previewImage = image
            showImagePreview = true
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

// MARK: - Row

private struct CityTripRow: View {
    let trip: VisitedCityTrip
    let isSelected: Bool
    let isUnavailable: Bool
    let onToggleSelection: () -> Void
    let onTapCover: (String?) -> Void

    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                onTapCover(trip.coverAssetIdentifier)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 54, height: 54)

                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(3)
                }
            }
            .buttonStyle(.plain)

            Button {
                onToggleSelection()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.displayTitle)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(trip.displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if isUnavailable {
                            Text("Already in a created/saved blog")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        } else {
                            Text(isSelected ? "Selected" : "Tap to select")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(isSelected ? .blue : .secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(
                            isUnavailable
                                ? Color.gray.opacity(0.45)
                                : (isSelected ? Color.blue : Color.secondary)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isUnavailable)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        )
        .onAppear { loadThumbnail() }
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
