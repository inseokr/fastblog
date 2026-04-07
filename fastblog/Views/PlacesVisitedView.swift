import MapKit
import SwiftUI
import UIKit

/// Unselected filter chip fill: `systemGray5` blended ~15% toward white (lighter tone).
private func filterChipUnselectedFill() -> Color {
    Color(uiColor: UIColor { traits in
        let base = UIColor.systemGray5.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return base }
        let t: CGFloat = 0.15
        return UIColor(red: r * (1 - t) + t, green: g * (1 - t) + t, blue: b * (1 - t) + t, alpha: a)
    })
}

// MARK: - Standalone full-screen Places Visited (from home icon)
struct PlacesVisitedStandaloneView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    var onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var showPlacesMap: Bool = false

    private let backgroundBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        PlacesVisitedView(
            searchText: $searchText,
            showPlacesMap: $showPlacesMap,
            selectedCreatedRecap: $selectedCreatedRecap,
            initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
            standaloneOnDismiss: onDismiss
        )
        .background(backgroundBlue.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Places Visited")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
    }
}

struct PlacesVisitedView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @Binding var searchText: String
    @Binding var showPlacesMap: Bool
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    /// When set (standalone presentation), shows a leading dismiss control in the navigation bar.
    var standaloneOnDismiss: (() -> Void)? = nil

    @State private var selectedYear: Int? = nil
    @State private var selectedCountry: String? = nil
    @State private var selectedCategory: String? = nil

    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var revealNavDuringModalDismiss: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchActive: Bool = false

    private let searchBarHeight: CGFloat = 56
    private let mapButtonSize: CGFloat = 52
    private let horizontalPadding: CGFloat = 16
    /// Bottom bar padding (match My Blogs layout).
    private let bottomBarHorizontalPadding: CGFloat = 20

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    private var availableYears: [Int] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.year))).sorted(by: >)
    }

    private var availableCountries: [String] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.country))).sorted()
    }

    private var availableCategories: [String] {
        let placesForYear = createdRecapStore.visitedPlaces.filter { place in
            guard let y = selectedYear else { return true }
            return place.year == y
        }

        let cats = placesForYear
            .compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private var filteredPlaces: [VisitedPlaceSummary] {
        createdRecapStore.visitedPlaces
            .filter { place in
                if let y = selectedYear, place.year != y { return false }
                if let c = selectedCountry {
                    let lhs = place.country.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }
                if let cat = selectedCategory {
                    let lhs = (place.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let q = query.lowercased()
                    let name = place.displayName.lowercased()
                    let city = (place.cityDisplay ?? "").lowercased()
                    let country = place.country.lowercased()
                    if !(name.contains(q) || city.contains(q) || country.contains(q)) { return false }
                }

                return true
            }
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                filterBar
                    .padding(.horizontal, horizontalPadding)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if filteredPlaces.isEmpty {
                            VStack(spacing: 10) {
                                Text(createdRecapStore.visitedPlaces.isEmpty ? "No places yet" : "No matches")
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text(createdRecapStore.visitedPlaces.isEmpty
                                     ? "Create a blog to start building your Places."
                                     : "Try clearing filters.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                                // Only treat year / country / category as "filters" for this button.
                                // Plain text search alone should NOT surface the Clear filters button.
                                let hasActiveFilters =
                                    selectedYear != nil ||
                                    selectedCountry != nil ||
                                    selectedCategory != nil

                                if !createdRecapStore.visitedPlaces.isEmpty && hasActiveFilters {
                                    Button("Clear filters") {
                                        selectedYear = nil
                                        selectedCountry = nil
                                        selectedCategory = nil
                                        searchText = ""
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        } else {
                            // Group by year, then by month
                            let yearGroups = groupedByYearThenMonth(filteredPlaces)
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(yearGroups, id: \.year) { yearGroup in
                                    // Year header — large
                                    Text(String(yearGroup.year))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)

                                    ForEach(yearGroup.months, id: \.month) { monthGroup in
                                        // Month header — smaller
                                        Text(monthGroup.monthName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 10)
                                            .padding(.bottom, 6)

                                        // 2-column grid for places in this month
                                        let pairs = stride(from: 0, to: monthGroup.places.count, by: 2).map {
                                            Array(monthGroup.places[$0 ..< min($0 + 2, monthGroup.places.count)])
                                        }
                                        ForEach(pairs, id: \.first?.id) { pair in
                                            HStack(alignment: .top, spacing: 12) {
                                                ForEach(Array(pair.enumerated()), id: \.element.id) { _, place in
                                                    Button {
                                                        selectedPlaceForModal = place
                                                    } label: {
                                                        PlaceVisitedCard(place: place)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .frame(maxWidth: .infinity)
                                                }
                                                // If odd number in this row, fill the gap
                                                if pair.count == 1 {
                                                    Color.clear.frame(maxWidth: .infinity)
                                                }
                                            }
                                            .padding(.bottom, 12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 140)
                }
            }

            // Persistent bottom bar (search + map), same design as My Blogs
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        isSearchFocused = false
                        showPlacesMap = true
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: mapButtonSize, height: mapButtonSize)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, bottomBarHorizontalPadding)
                    .padding(.bottom, 16)
                }
                placesSearchBar
            }
            .allowsHitTesting(true)

            // Full-screen place viewer (matches blog overlay, not a sheet).
            if let place = selectedPlaceForModal {
                PlaceVisitedPhotoModalWrapper(
                    place: place,
                    onDismiss: {
                        selectedPlaceForModal = nil
                        revealNavDuringModalDismiss = false
                    },
                    onDismissSlideBegan: { revealNavDuringModalDismiss = true },
                    onViewBlog: {
                        guard let ref = place.relatedBlogs.first,
                              let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == ref.blogId }) else { return }
                        selectedPlaceForModal = nil
                        revealNavDuringModalDismiss = false
                        initialScrollToStopIdForRecap = ref.placeStopId
                        selectedCreatedRecap = recap
                    }
                )
                .environmentObject(createdRecapStore)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.38), value: selectedPlaceForModal?.id)
        .navigationDestination(isPresented: $showPlacesMap) {
            PlacesVisitedMapView(
                selectedYear: $selectedYear,
                selectedCountry: $selectedCountry,
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                selectedCreatedRecap: $selectedCreatedRecap,
                initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap
            )
            .environmentObject(createdRecapStore)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if let standaloneOnDismiss {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            standaloneOnDismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                if selectedYear != nil || selectedCountry != nil || selectedCategory != nil {
                    Button("Reset") {
                        selectedYear = nil
                        selectedCountry = nil
                        selectedCategory = nil
                    }
                    .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSearchActive {
                    Button("Done") {
                        searchText = ""
                        isSearchFocused = false
                        isSearchActive = false
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                } else {
                    Menu {
                        Button("All Countries") { selectedCountry = nil }
                        ForEach(availableCountries, id: \.self) { c in
                            Button(c) { selectedCountry = c }
                        }
                    } label: {
                        Image(systemName: selectedCountry == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .toolbar((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
        .onChange(of: selectedYear) { _, _ in
            // If the user switches years, drop any category that doesn't exist for the new year.
            if let selectedCategory,
               !availableCategories.contains(where: { $0.caseInsensitiveCompare(selectedCategory) == .orderedSame }) {
                self.selectedCategory = nil
            }
        }
    }

    // MARK: - Year / Month grouping helpers

    private struct MonthGroup {
        let month: Int          // 1–12
        let monthName: String   // e.g. "March"
        let places: [VisitedPlaceSummary]
    }

    private struct YearGroup {
        let year: Int
        let months: [MonthGroup]
    }

    private func groupedByYearThenMonth(_ places: [VisitedPlaceSummary]) -> [YearGroup] {
        let cal = Calendar.current
        // Group by year
        let byYear = Dictionary(grouping: places) { cal.component(.year, from: $0.latestVisitDate) }
        return byYear.keys.sorted(by: >).map { year in
            let yearPlaces = byYear[year]!
            // Group by month within the year
            let byMonth = Dictionary(grouping: yearPlaces) { cal.component(.month, from: $0.latestVisitDate) }
            let monthGroups = byMonth.keys.sorted(by: >).map { month -> MonthGroup in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                let name: String = {
                    var comps = DateComponents(); comps.month = month; comps.year = year
                    let date = cal.date(from: comps) ?? Date()
                    return formatter.string(from: date)
                }()
                return MonthGroup(month: month, monthName: name, places: byMonth[month]!)
            }
            return YearGroup(year: year, months: monthGroups)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Year")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(label: "All", isSelected: selectedYear == nil) {
                            selectedYear = nil
                        }
                        ForEach(availableYears, id: \.self) { y in
                            chip(label: String(y), isSelected: selectedYear == y) {
                                selectedYear = (selectedYear == y) ? nil : y
                            }
                        }
                    }
                }
            }

            if !availableCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(label: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(availableCategories, id: \.self) { cat in
                                placesVisitedCategoryChip(raw: cat, isSelected: selectedCategory == cat) {
                                    selectedCategory = (selectedCategory == cat) ? nil : cat
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var placesSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("Search place, city, or country", text: $searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture { isSearchActive = true }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: searchBarHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
        .padding(.horizontal, bottomBarHorizontalPadding)
        .padding(.bottom, 12)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : filterChipUnselectedFill())
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func placesVisitedCategoryChip(raw: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        let label = PlacePOICategoryPresentation.displayLabel(forRaw: raw)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.white : p.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? p.color : p.color.opacity(0.14))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(p.color.opacity(isSelected ? 0.25 : 0.45), lineWidth: isSelected ? 0 : 1)
            )
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

}


/// Stateful wrapper around PlacePhotoModalView for the Places Visited full-screen overlay.
/// Holds live per-photo caption state so the binding getter always reflects the latest value,
/// and calls updatePhotoCaption on the store whenever a caption is committed.
private struct PlaceVisitedPhotoModalWrapper: View {
    @EnvironmentObject private var store: CreatedRecapBlogStore

    let place: VisitedPlaceSummary
    var onDismiss: () -> Void
    var onDismissSlideBegan: (() -> Void)? = nil
    var onViewBlog: (() -> Void)?

    /// Live caption state keyed by photo ID. Seeded from place.photos on appear.
    @State private var liveCaptions: [UUID: String] = [:]
    /// Live place name — updated when user edits via the kebab 'Edit Place Name' menu item.
    @State private var livePlaceTitle: String = ""

    var body: some View {
        // Look up live photos from the store so we always reflect the current included-photo state,
        // even if isIncluded flags changed after this sheet was first presented.
        let photos = store.visitedPlaces.first { $0.placeId == place.placeId }?.photos ?? place.photos
        if let initialPhotoId = photos.first?.id {
            PlacePhotoModalView(
                placeTitle: Binding(
                    get: { livePlaceTitle.isEmpty ? place.displayName : livePlaceTitle },
                    set: { newName in
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        livePlaceTitle = trimmed
                        store.updatePlaceStopName(photoId: initialPhotoId, newName: trimmed)
                    }
                ),
                placeSubtitle: place.cityDisplay ?? place.country,
                photos: photos,
                initialPhotoId: initialPhotoId,
                stopDigitizedTime: nil,
                blogIsEditMode: false,
                showAssetTimeMetadata: false,
                presentation: .fullscreen(source: .placesVisited),
                photoCaption: { photoId in
                    Binding(
                        get: { liveCaptions[photoId] ?? photos.first(where: { $0.id == photoId })?.caption ?? "" },
                        set: { newValue in
                            liveCaptions[photoId] = newValue
                            store.updatePhotoCaption(photoId: photoId, newCaption: newValue)
                        }
                    )
                },
                onDismiss: onDismiss,
                onDismissSlideBegan: onDismissSlideBegan,
                onViewBlog: place.relatedBlogs.isEmpty ? nil : onViewBlog,
                onPhotoCaptionManuallyEdited: { photoId in
                    // updatePhotoCaption already called via the binding setter
                },
                onRemovePhoto: { photoId in
                    store.removePhotoFromBlog(photoId: photoId)
                    onDismiss()
                }
            )
        } else {
            Color.clear.onAppear { onDismiss() }
        }
    }
}

private struct PlaceVisitedCard: View {
    let place: VisitedPlaceSummary

    private let maxThumbs: Int = 3
    private let thumbSpacing: CGFloat = 8
    private let stripPadding: CGFloat = 10
    /// Preferred thumb size on wide cards; scales down when the grid column is narrower (non‑Max iPhones).
    private let preferredThumbSize: CGFloat = 44

    var body: some View {
        let heroId = place.heroPhoto?.id
        let previewThumbs = place.photos
            .filter { $0.id != heroId }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(maxThumbs)

        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let availableWidth = geo.size.width
                let thumbCount = previewThumbs.count
                let thumbSize: CGFloat = {
                    guard thumbCount > 0 else { return preferredThumbSize }
                    let gutters = stripPadding * 2 + CGFloat(thumbCount - 1) * thumbSpacing
                    let raw = (availableWidth - gutters) / CGFloat(thumbCount)
                    // No minimum clamp — a floor can make the strip wider than the column on narrow phones.
                    return min(preferredThumbSize, max(1, raw))
                }()
                let backingWidth = CGFloat(thumbCount) * thumbSize
                    + CGFloat(thumbCount - 1) * thumbSpacing
                    + stripPadding * 2

                ZStack(alignment: .bottom) {
                    if let hero = place.heroPhoto {
                        RecapPhotoThumbnail(photo: hero, cornerRadius: 14, showIcon: false, targetSize: CGSize(width: 900, height: 600))
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 14))
                    } else {
                        Color.clear
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 14))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack {
                        HStack {
                            Text(place.latestVisitDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)

                    if !previewThumbs.isEmpty {
                        HStack(spacing: thumbSpacing) {
                            ForEach(Array(previewThumbs)) { photo in
                                RecapPhotoThumbnail(photo: photo, cornerRadius: 10, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                                    .frame(width: thumbSize, height: thumbSize)
                                    .clipShape(RoundedRectangle(appChromeBaseRadius: 10))
                                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(stripPadding)
                        .frame(width: min(backingWidth, availableWidth))
                        .background(
                            RoundedRectangle(appChromeBaseRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                        )
                    }
                }
            }
            .frame(height: 150)

            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(place.cityDisplay ?? place.country)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let raw = place.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                    PlacePOICategoryBadge(rawCategory: raw)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color.clear)
        .clipShape(RoundedRectangle(appChromeBaseRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(appChromeBaseRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}


private struct PlacesVisitedMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @Binding var selectedYear: Int?
    @Binding var selectedCountry: String?
    @Binding var selectedCategory: String?
    @Binding var searchText: String
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var revealNavDuringModalDismiss: Bool = false
    @State private var isSearchActive: Bool = false
    @FocusState private var isSearchFocused: Bool

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
    )

    private var availableYears: [Int] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.year))).sorted(by: >)
    }

    private var availableCountries: [String] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.country))).sorted()
    }

    private var availableCategories: [String] {
        let placesForYear = createdRecapStore.visitedPlaces.filter { place in
            guard let y = selectedYear else { return true }
            return place.year == y
        }

        let cats = placesForYear
            .compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private func coordinate(for place: VisitedPlaceSummary) -> CLLocationCoordinate2D? {
        if let loc = place.heroPhoto?.location?.clCoordinate { return loc }
        if let loc = place.photos.compactMap({ $0.location?.clCoordinate }).first { return loc }
        return nil
    }

    private var filteredPlaces: [VisitedPlaceSummary] {
        createdRecapStore.visitedPlaces
            .filter { place in
                if let y = selectedYear, place.year != y { return false }
                if let c = selectedCountry {
                    let lhs = place.country.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }
                if let cat = selectedCategory {
                    let lhs = (place.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let q = query.lowercased()
                    let name = place.displayName.lowercased()
                    let city = (place.cityDisplay ?? "").lowercased()
                    let country = place.country.lowercased()
                    if !(name.contains(q) || city.contains(q) || country.contains(q)) { return false }
                }
                return true
            }
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    private var placesWithCoordinates: [(place: VisitedPlaceSummary, coordinate: CLLocationCoordinate2D)] {
        filteredPlaces.compactMap { place in
            guard let coord = coordinate(for: place) else { return nil }
            return (place, coord)
        }
    }

    private func recenterToLatestPlace() {
        if let latest = placesWithCoordinates.first?.coordinate {
            withAnimation {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: latest,
                        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                    )
                )
            }
        } else {
            withAnimation {
                mapPosition = .region(defaultRegion)
            }
        }
    }

    // MARK: - Year / Month grouping helpers (mirrors PlacesVisitedView)

    private struct MonthGroup {
        let month: Int          // 1–12
        let monthName: String   // e.g. "March"
        let places: [VisitedPlaceSummary]
    }

    private struct YearGroup {
        let year: Int
        let months: [MonthGroup]
    }

    private func groupedByYearThenMonth(_ places: [VisitedPlaceSummary]) -> [YearGroup] {
        let cal = Calendar.current
        let byYear = Dictionary(grouping: places) { cal.component(.year, from: $0.latestVisitDate) }
        return byYear.keys.sorted(by: >).map { year in
            let yearPlaces = byYear[year]!
            let byMonth = Dictionary(grouping: yearPlaces) { cal.component(.month, from: $0.latestVisitDate) }
            let monthGroups = byMonth.keys.sorted(by: >).map { month -> MonthGroup in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                let name: String = {
                    var comps = DateComponents(); comps.month = month; comps.year = year
                    let date = cal.date(from: comps) ?? Date()
                    return formatter.string(from: date)
                }()
                return MonthGroup(month: month, monthName: name, places: byMonth[month]!)
            }
            return YearGroup(year: year, months: monthGroups)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $mapPosition) {
                ForEach(placesWithCoordinates, id: \.place.id) { item in
                    Annotation("", coordinate: item.coordinate) {
                        PlacesVisitedMapMarker(place: item.place)
                            .onTapGesture {
                                selectedPlaceForModal = item.place
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(.container, edges: .bottom)
            .onAppear {
                recenterToLatestPlace()
            }
            .onChange(of: selectedYear) { _, _ in
                // If the user switches years, drop any category that doesn't exist for the new year.
                if let selectedCategory,
                   !availableCategories.contains(where: { $0.caseInsensitiveCompare(selectedCategory) == .orderedSame }) {
                    self.selectedCategory = nil
                }
                recenterToLatestPlace()
            }
            .onChange(of: selectedCountry) { _, _ in
                recenterToLatestPlace()
            }
            .onChange(of: selectedCategory) { _, _ in
                recenterToLatestPlace()
            }

            // Top filter chips
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Year")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(label: "All", isSelected: selectedYear == nil) {
                                selectedYear = nil
                            }
                            ForEach(availableYears, id: \.self) { y in
                                chip(label: String(y), isSelected: selectedYear == y) {
                                    selectedYear = (selectedYear == y) ? nil : y
                                }
                            }
                        }
                    }
                }

                if !availableCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(label: "All", isSelected: selectedCategory == nil) {
                                    selectedCategory = nil
                                }
                                ForEach(availableCategories, id: \.self) { cat in
                                    placesVisitedMapCategoryChip(raw: cat, isSelected: selectedCategory == cat) {
                                        selectedCategory = (selectedCategory == cat) ? nil : cat
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Search overlay (dark navy, similar to My Blogs map search)
            if isSearchActive {
                Color(red: 5/255, green: 10/255, blue: 48/255)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // Search bar under header
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        TextField("Search place, city, or country", text: $searchText)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)

                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .fill(Color.white.opacity(0.12))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    // List of matching places (same grouping source as main list)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            if filteredPlaces.isEmpty {
                                VStack(spacing: 10) {
                                    Text("No matches")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)

                                    Text("Try a different place, city, or country.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 44)
                            } else {
                                let yearGroups = groupedByYearThenMonth(filteredPlaces)
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(yearGroups, id: \.year) { yearGroup in
                                        Text(String(yearGroup.year))
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)

                                        ForEach(yearGroup.months, id: \.month) { monthGroup in
                                            Text(monthGroup.monthName)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(.top, 10)
                                                .padding(.bottom, 6)

                                            let pairs = stride(from: 0, to: monthGroup.places.count, by: 2).map {
                                                Array(monthGroup.places[$0 ..< min($0 + 2, monthGroup.places.count)])
                                            }
                                            ForEach(pairs, id: \.first?.id) { pair in
                                                HStack(alignment: .top, spacing: 12) {
                                                    ForEach(Array(pair.enumerated()), id: \.element.id) { _, place in
                                                        Button {
                                                            selectedPlaceForModal = place
                                                        } label: {
                                                            PlaceVisitedCard(place: place)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .frame(maxWidth: .infinity)
                                                    }
                                                    if pair.count == 1 {
                                                        Color.clear.frame(maxWidth: .infinity)
                                                    }
                                                }
                                                .padding(.bottom, 12)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
                .transition(.opacity)
            }

            // Full-screen place viewer (matches blog overlay, not a sheet).
            if let place = selectedPlaceForModal {
                PlaceVisitedPhotoModalWrapper(
                    place: place,
                    onDismiss: {
                        selectedPlaceForModal = nil
                        revealNavDuringModalDismiss = false
                    },
                    onDismissSlideBegan: { revealNavDuringModalDismiss = true },
                    onViewBlog: {
                        guard let ref = place.relatedBlogs.first,
                              let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == ref.blogId }) else { return }
                        selectedPlaceForModal = nil
                        revealNavDuringModalDismiss = false
                        initialScrollToStopIdForRecap = ref.placeStopId
                        selectedCreatedRecap = recap
                    }
                )
                .environmentObject(createdRecapStore)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.38), value: selectedPlaceForModal?.id)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSearchActive {
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSearchActive = false
                        }
                        searchText = ""
                        isSearchFocused = false
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                } else {
                    // Search icon (left)
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSearchActive = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSearchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.primary)
                    }

                    // Existing filter menu (right)
                    Menu {
                        Button("All Countries") { selectedCountry = nil }
                        ForEach(availableCountries, id: \.self) { c in
                            Button(c) { selectedCountry = c }
                        }
                    } label: {
                        Image(systemName: selectedCountry == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .toolbar((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
    }

    private func placesVisitedMapCategoryChip(raw: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        let label = PlacePOICategoryPresentation.displayLabel(forRaw: raw)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? p.color : p.color.opacity(0.35))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(isSelected ? 0.4 : 0.2), lineWidth: 1))
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.white.opacity(0.23))
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}

private struct PlacesVisitedMapMarker: View {
    let place: VisitedPlaceSummary

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)

            if let hero = place.heroPhoto {
                RecapPhotoThumbnail(photo: hero, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                    }
            } else {
                Image(systemName: "photo")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
    }
}
