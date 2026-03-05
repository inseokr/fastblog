import MapKit
import SwiftUI

struct PlacesVisitedView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @State private var selectedYear: Int? = nil
    @State private var selectedCountry: String? = nil
    @State private var selectedCategory: String? = nil

    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false
    @FocusState private var isSearchFocused: Bool

    @State private var showPlacesMap: Bool = false

    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var selectedCreatedRecap: CreatedRecapBlog?

    private let searchBarHeight: CGFloat = 56
    private let mapButtonSize: CGFloat = 52
    private let horizontalPadding: CGFloat = 16

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
        let cats = createdRecapStore.visitedPlaces
            .compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private func categoryDisplayLabel(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let cat = MKPointOfInterestCategory(rawValue: trimmed)
        switch cat {
        case .restaurant:      return "Restaurant"
        case .cafe:            return "Café"
        case .bakery:          return "Bakery"
        case .winery:          return "Winery"
        case .brewery:         return "Brewery"
        case .nightlife:       return "Nightlife"
        case .hotel:           return "Hotel"
        case .campground:      return "Campground"
        case .museum:          return "Museum"
        case .movieTheater:    return "Movie Theater"
        case .theater:         return "Theater"
        case .amusementPark:   return "Amusement Park"
        case .zoo:             return "Zoo"
        case .aquarium:        return "Aquarium"
        case .park:            return "Park"
        case .beach:           return "Beach"
        case .nationalPark:    return "National Park"
        case .airport:         return "Airport"
        case .publicTransport: return "Transit"
        case .gasStation:      return "Gas Station"
        case .hospital:        return "Hospital"
        case .pharmacy:        return "Pharmacy"
        case .fitnessCenter:   return "Fitness"
        case .store:           return "Store"
        case .foodMarket:      return "Market"
        case .library:         return "Library"
        case .school:          return "School"
        case .university:      return "University"
        case .marina:          return "Marina"
        case .stadium:         return "Stadium"
        case .bank:            return "Bank"
        default:
            break
        }

        if trimmed.hasPrefix("MKPOICategory") {
            let remainder = String(trimmed.dropFirst("MKPOICategory".count))
            if remainder.isEmpty { return trimmed }
            let spaced = remainder
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return spaced
        }

        if trimmed.count <= 4 {
            return trimmed.uppercased()
        }

        return trimmed
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterBar

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

                            if createdRecapStore.visitedPlaces.isEmpty {
                                Button("Create Blog") { }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button("Clear filters") {
                                    selectedYear = nil
                                    selectedCountry = nil
                                    selectedCategory = nil
                                    searchText = ""
                                    isSearchFocused = false
                                    isSearchActive = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                    } else {
                        let indexedPlaces = Array(filteredPlaces.enumerated())
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                            ForEach(indexedPlaces, id: \.element.id) { index, place in
                                // Pair partner: even index pairs with the next, odd with the previous
                                let partnerIndex = index % 2 == 0 ? index + 1 : index - 1
                                let partnerHasCaption = partnerIndex < filteredPlaces.count && filteredPlaces[partnerIndex].captionPreview != nil
                                let showCaptionSpace = place.captionPreview != nil || partnerHasCaption
                                Button {
                                    selectedPlaceForModal = place
                                } label: {
                                    PlaceVisitedCard(place: place, showCaptionSpace: showCaptionSpace)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, searchBarHeight + mapButtonSize + 24)
            }

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    placesMapButton
                        .padding(.trailing, horizontalPadding)
                        .padding(.bottom, 16)
                }
                placesSearchBar
            }
            .allowsHitTesting(true)
        }
        .navigationTitle("Places Visited")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPlaceForModal) { place in
            placeModalSheet(place: place)
        }
        .navigationDestination(isPresented: $showPlacesMap) {
            PlacesVisitedMapView(
                selectedYear: $selectedYear,
                selectedCategory: $selectedCategory,
                searchText: $searchText
            )
            .environmentObject(createdRecapStore)
        }
        .navigationDestination(item: $selectedCreatedRecap) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All Countries") { selectedCountry = nil }
                    ForEach(availableCountries, id: \.self) { c in
                        Button(c) { selectedCountry = c }
                    }
                } label: {
                    Image(systemName: selectedCountry == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }

            if selectedYear != nil || selectedCountry != nil || selectedCategory != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        selectedYear = nil
                        selectedCountry = nil
                        selectedCategory = nil
                    }
                }
            }
        }
    }

    private var placesMapButton: some View {
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
    }

    private var placesSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search places", text: $searchText)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture { isSearchActive = true }

            if isSearchActive {
                Button {
                    searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: searchBarHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 12)
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
                                chip(label: categoryDisplayLabel(for: cat), isSelected: selectedCategory == cat) {
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

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color(uiColor: .systemBackground) : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.primary : Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func placeModalSheet(place: VisitedPlaceSummary) -> some View {
        PlaceVisitedPhotoModalWrapper(
            place: place,
            onDismiss: { selectedPlaceForModal = nil },
            onViewBlog: {
                guard let blogId = place.relatedBlogs.first?.blogId,
                      let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == blogId }) else { return }
                selectedPlaceForModal = nil
                selectedCreatedRecap = recap
            }
        )
        .environmentObject(createdRecapStore)
        .presentationDetents([.large])
    }
}


/// Stateful wrapper around PlacePhotoModalView for the Places Visited sheet.
/// Holds live per-photo caption state so the binding getter always reflects the latest value,
/// and calls updatePhotoCaption on the store whenever a caption is committed.
private struct PlaceVisitedPhotoModalWrapper: View {
    @EnvironmentObject private var store: CreatedRecapBlogStore

    let place: VisitedPlaceSummary
    var onDismiss: () -> Void
    var onViewBlog: (() -> Void)?

    /// Live caption state keyed by photo ID. Seeded from place.photos on appear.
    @State private var liveCaptions: [UUID: String] = [:]

    var body: some View {
        let photos = place.photos
        if let initialPhotoId = photos.first?.id {
            PlacePhotoModalView(
                placeTitle: Binding(
                    get: { place.displayName },
                    set: { _ in }
                ),
                placeSubtitle: place.cityDisplay ?? place.country,
                photos: photos,
                initialPhotoId: initialPhotoId,
                stopDigitizedTime: nil,
                blogIsEditMode: false,
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
                onViewBlog: onViewBlog,
                onPhotoCaptionManuallyEdited: { photoId in
                    // updatePhotoCaption already called via the binding setter
                }
            )
        } else {
            Color.clear.onAppear { onDismiss() }
        }
    }
}

private struct PlaceVisitedCard: View {
    let place: VisitedPlaceSummary
    var showCaptionSpace: Bool = true

    var body: some View {
        let thumbSize: CGFloat = 44
        let thumbSpacing: CGFloat = 8
        let stripPadding: CGFloat = 10
        let maxThumbs: Int = 3
        let backingWidth: CGFloat = (CGFloat(maxThumbs) * thumbSize) + (CGFloat(maxThumbs - 1) * thumbSpacing) + (stripPadding * 2)

        let heroId = place.heroPhoto?.id
        let previewThumbs = place.photos
            .filter { $0.id != heroId }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(maxThumbs)

        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                if let hero = place.heroPhoto {
                    RecapPhotoThumbnail(photo: hero, cornerRadius: 14, showIcon: false, targetSize: CGSize(width: 900, height: 600))
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Color(uiColor: .secondarySystemBackground)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }

                VStack {
                    HStack {
                        Text(place.latestVisitDate.formatted(date: .abbreviated, time: .omitted))
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
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(stripPadding)
                    .frame(width: backingWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                    )
                }
            }

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

                if showCaptionSpace {
                    ZStack(alignment: .topLeading) {
                        // Invisible 2-line spacer — reserves height only when row partner also has/needs caption
                        Text(" \n ")
                            .font(.subheadline)
                            .lineLimit(2)
                            .opacity(0)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Real caption on top
                        if let preview = place.captionPreview {
                            Text(preview)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.9))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct PlacesVisitedMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @Binding var selectedYear: Int?
    @Binding var selectedCategory: String?
    @Binding var searchText: String

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedPlaceForModal: VisitedPlaceSummary?

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
    )

    private var availableYears: [Int] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.year))).sorted(by: >)
    }

    private var availableCategories: [String] {
        let cats = createdRecapStore.visitedPlaces
            .compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private func categoryDisplayLabel(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let cat = MKPointOfInterestCategory(rawValue: trimmed)
        switch cat {
        case .restaurant:      return "Restaurant"
        case .cafe:            return "Café"
        case .bakery:          return "Bakery"
        case .winery:          return "Winery"
        case .brewery:         return "Brewery"
        case .nightlife:       return "Nightlife"
        case .hotel:           return "Hotel"
        case .campground:      return "Campground"
        case .museum:          return "Museum"
        case .movieTheater:    return "Movie Theater"
        case .theater:         return "Theater"
        case .amusementPark:   return "Amusement Park"
        case .zoo:             return "Zoo"
        case .aquarium:        return "Aquarium"
        case .park:            return "Park"
        case .beach:           return "Beach"
        case .nationalPark:    return "National Park"
        case .airport:         return "Airport"
        case .publicTransport: return "Transit"
        case .gasStation:      return "Gas Station"
        case .hospital:        return "Hospital"
        case .pharmacy:        return "Pharmacy"
        case .fitnessCenter:   return "Fitness"
        case .store:           return "Store"
        case .foodMarket:      return "Market"
        case .library:         return "Library"
        case .school:          return "School"
        case .university:      return "University"
        case .marina:          return "Marina"
        case .stadium:         return "Stadium"
        case .bank:            return "Bank"
        default:
            break
        }

        if trimmed.hasPrefix("MKPOICategory") {
            let remainder = String(trimmed.dropFirst("MKPOICategory".count))
            if remainder.isEmpty { return trimmed }
            let spaced = remainder
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return spaced
        }

        if trimmed.count <= 4 {
            return trimmed.uppercased()
        }

        return trimmed
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
                if let first = placesWithCoordinates.first?.coordinate {
                    mapPosition = .region(
                        MKCoordinateRegion(
                            center: first,
                            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                        )
                    )
                } else {
                    mapPosition = .region(defaultRegion)
                }
            }

            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Year")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

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
                            .foregroundStyle(.white.opacity(0.7))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(label: "All", isSelected: selectedCategory == nil) {
                                    selectedCategory = nil
                                }
                                ForEach(availableCategories, id: \.self) { cat in
                                    chip(label: categoryDisplayLabel(for: cat), isSelected: selectedCategory == cat) {
                                        selectedCategory = (selectedCategory == cat) ? nil : cat
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedPlaceForModal) { place in
            PlaceVisitedPhotoModalWrapper(
                place: place,
                onDismiss: { selectedPlaceForModal = nil },
                onViewBlog: nil
            )
            .environmentObject(createdRecapStore)
            .presentationDetents([.large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.white.opacity(0.2))
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
