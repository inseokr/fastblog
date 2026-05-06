//
//  MapDayView.swift
//  Capper
//

import MapKit
import SwiftUI
import UIKit

/// Unselected category chip on map: `systemGray5` blended ~15% toward white.
private func mapDayFilterChipUnselectedFill() -> Color {
    Color(uiColor: UIColor { traits in
        let base = UIColor.systemGray5.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return base }
        let t: CGFloat = 0.15
        return UIColor(red: r * (1 - t) + t, green: g * (1 - t) + t, blue: b * (1 - t) + t, alpha: a)
    })
}

/// One marker per place: coordinate, first photo (for image), place title. Order preserved for route.
struct PlaceMapMarker: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let firstPhoto: RecapPhoto
    let placeTitle: String
    var placeCategory: String?
}

/// Map for one day: one marker per place (first photo as marker image), place name below, route line in visit order. Tap to open full-screen map when onTap provided.
struct MapDayView: View {
    let placeStops: [PlaceStop]
    var height: CGFloat = 220
    var onTap: (() -> Void)?
    /// When set, map region centers on this place's coordinate (e.g. for full-screen card sync).
    var focusedPlaceId: UUID? = nil
    /// Called when the user taps a place annotation on the map. Receives the stop's UUID.
    var onAnnotationTap: ((UUID) -> Void)? = nil
    /// If true, suppress any green/orange "Start" or "End" visual styling on markers.
    var hideStartEndMarkers: Bool = false

    @State private var cameraPosition: MapCameraPosition = .automatic

    init(placeStops: [PlaceStop], height: CGFloat = 220, onTap: (() -> Void)? = nil, focusedPlaceId: UUID? = nil, onAnnotationTap: ((UUID) -> Void)? = nil, hideStartEndMarkers: Bool = false) {
        self.placeStops = placeStops
        self.height = height
        self.onTap = onTap
        self.focusedPlaceId = focusedPlaceId
        self.onAnnotationTap = onAnnotationTap
        self.hideStartEndMarkers = hideStartEndMarkers
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color(red: 0, green: 122/255, blue: 1), lineWidth: 4)
            }
            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                let placeNumber = index + 1
                let isFirst = !hideStartEndMarkers && index == 0
                let isLast = !hideStartEndMarkers && index == markers.count - 1
                Annotation("", coordinate: marker.coordinate) {
                    PlaceMarkerView(
                        photo: marker.firstPhoto,
                        title: marker.placeTitle,
                        placeNumber: placeNumber,
                        isFirst: isFirst,
                        isLast: isLast,
                        placeCategory: marker.placeCategory
                    )
                    .onTapGesture {
                        onAnnotationTap?(marker.id)
                    }
                }
            }
            
            // Mileage markers between points (guard: 0..<-1 would crash)
            ForEach(0..<max(0, markers.count - 1), id: \.self) { i in
                let start = markers[i]
                let end = markers[i+1]
                if let dist = distanceString(from: start.coordinate, to: end.coordinate) {
                    Annotation("", coordinate: midPoint(from: start.coordinate, to: end.coordinate)) {
                        Text(dist)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .shadow(radius: 1)
                    }
                }
            }
        }
        // Match onboarding's native Apple Maps look (less 3D terrain-heavy than realistic elevation).
        .mapStyle(.standard(elevation: .flat))
        .frame(height: height)
        .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            updateCameraPosition(animated: false)
        }
        .onChange(of: placeStops) { _, _ in
            // Day filter changed — reset map to the "Start" POI of the new day.
            updateCameraPosition(animated: true)
        }
        .onChange(of: focusedPlaceId) { _, _ in
            updateCameraPosition(animated: true)
        }
    }

    private func updateCameraPosition(animated: Bool) {
        let newPosition = MapCameraPosition.region(region)
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                cameraPosition = newPosition
            }
        } else {
            cameraPosition = newPosition
        }
    }

    private var markers: [PlaceMapMarker] {
        placeStops.compactMap { stop in
            let included = stop.includedPhotos
            guard !included.isEmpty else { return nil }
            let coord = stop.representativeLocation?.clCoordinate
                ?? included.first(where: { $0.location != nil })?.location?.clCoordinate
            guard let coordinate = coord, let first = included.first else { return nil }
            return PlaceMapMarker(
                id: stop.id,
                coordinate: coordinate,
                firstPhoto: first,
                placeTitle: stop.placeTitle,
                placeCategory: stop.placeCategory
            )
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        markers.map(\.coordinate)
    }

    private var region: MKCoordinateRegion {
        let coords = routeCoordinates
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        
        // If a specific place is focused, center on it.
        if let focusId = focusedPlaceId, let marker = markers.first(where: { $0.id == focusId }) {
            return MKCoordinateRegion(
                center: marker.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.0035, longitudeDelta: 0.0035)
            )
        }
        
        // Otherwise, center on the "Start" (first place) of the day.
        if let startMarker = markers.first {
            return MKCoordinateRegion(
                center: startMarker.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        
        // Fallback
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        let padding = 0.002
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.003, (maxLat - minLat) + padding * 2),
            longitudeDelta: max(0.003, (maxLon - minLon) + padding * 2)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func distanceString(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String? {
         let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
         let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
         let distanceInMeters = loc2.distance(from: loc1)
         let distanceInMiles = distanceInMeters / 1609.34
         if distanceInMiles < 0.1 { return nil }
         return String(format: "%.1f mi", distanceInMiles)
    }

    private func midPoint(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (from.latitude + to.latitude) / 2,
            longitude: (from.longitude + to.longitude) / 2
        )
    }
}

/// Marker: first photo (rounded), place order badge, START/END labels, place name below.
private struct PlaceMarkerView: View {
    let photo: RecapPhoto
    let title: String
    let placeNumber: Int
    let isFirst: Bool
    let isLast: Bool
    var placeCategory: String? = nil

    private var orderLabel: String {
        switch placeNumber {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(placeNumber)th"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if isFirst && isLast {
                startEndBadge(text: "START & END", color: Color.green)
            } else if isFirst {
                startEndBadge(text: "START", color: Color.green)
            } else if isLast {
                startEndBadge(text: "END", color: Color.orange)
            }

            ZStack(alignment: .topLeading) {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 80, height: 80))
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isFirst ? Color.green : (isLast ? Color.orange : Color.white),
                                lineWidth: isFirst || isLast ? 3 : 2
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 2)

                // Middle stops only: order badge on the photo. Start/end use the pills above.
                if !isFirst && !isLast {
                    Text("\(placeNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.blue.opacity(0.9)))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .offset(x: -4, y: -4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let raw = placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                    let presentation = PlacePOICategoryPresentation.presentation(forRaw: raw)
                    Image(systemName: presentation.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(presentation.color))
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                        .offset(x: 4, y: -2)
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                }
            }

            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.75))
                .appChromeCornerRadius(6)
                .frame(maxWidth: 90)

            Text(orderLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
    }

    private func startEndBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.95)))
            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 1)
    }
}

// MARK: - Legacy initializer (photos only) for preview / backward compatibility

extension MapDayView {
    /// Builds place markers from a flat list of photos (one “place” per photo). Use placeStops initializer when you have structured places.
    init(photos: [RecapPhoto], height: CGFloat = 220, onTap: (() -> Void)? = nil, focusedPlaceId: UUID? = nil) {
        self.placeStops = photos.enumerated().compactMap { index, photo in
            guard let loc = photo.location else { return nil }
            return PlaceStop(
                orderIndex: index,
                placeTitle: "Photo \(index + 1)",
                representativeLocation: PhotoCoordinate(latitude: loc.latitude, longitude: loc.longitude),
                photos: [photo]
            )
        }
        self.height = height
        self.onTap = onTap
        self.focusedPlaceId = focusedPlaceId
        self.onAnnotationTap = nil
    }
}

// MARK: - Full-screen map (tap day map to open)

/// Full-screen map for one day: same markers, route, labels; bottom place cards scroll one-by-one and drive map center.
struct FullScreenMapView: View {
    let day: RecapBlogDay
    var onDismiss: () -> Void
    /// Called when a photo caption is saved inside the modal. Receives (stopId, photoId, newCaption).
    var onCaptionSaved: ((UUID, UUID, String) -> Void)? = nil
    /// Called when a place name is saved from the modal kebab menu.
    /// Receives (stopId, newName, category, coordinate, subtitleLine).
    var onPlaceNameSaved: ((UUID, String, String?, CLLocationCoordinate2D?, String) -> Void)? = nil
    /// When set, opens focused on this place marker.
    var initialFocusedPlaceId: UUID? = nil

    @State private var selectedPlaceIndex: Int = 0
    @State private var didApplyInitialFocus = false
    // Photo modal
    @State private var photoModalStop: PlaceStop?
    @State private var photoModalInitialPhotoId: UUID?
    @State private var photoModalCaptions: [UUID: String] = [:]
    /// Captions at the moment the modal was opened — used to diff on dismiss.
    @State private var photoModalCaptionsSnapshot: [UUID: String] = [:]
    
    @State private var selectedCategory: String? = nil
    @State private var scrolledPlaceID: UUID?
    @State private var editablePlaceStops: [PlaceStop]

    init(
        day: RecapBlogDay,
        onDismiss: @escaping () -> Void,
        onCaptionSaved: ((UUID, UUID, String) -> Void)? = nil,
        onPlaceNameSaved: ((UUID, String, String?, CLLocationCoordinate2D?, String) -> Void)? = nil,
        initialFocusedPlaceId: UUID? = nil
    ) {
        self.day = day
        self.onDismiss = onDismiss
        self.onCaptionSaved = onCaptionSaved
        self.onPlaceNameSaved = onPlaceNameSaved
        self.initialFocusedPlaceId = initialFocusedPlaceId
        _editablePlaceStops = State(initialValue: day.placeStops)
    }

    private var availableCategories: [String] {
        let dataRaws = Set(editablePlaceStops.compactMap { stop -> String? in
            let cat = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cat.isEmpty else { return nil }
            return cat
        })
        let includeOthers = editablePlaceStops.contains {
            ($0.placeCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return PlacePOICategoryCatalog.categoryRawsAppearingInDataForFilters(dataRaws: dataRaws, includeOthers: includeOthers)
    }

    private var filteredStops: [PlaceStop] {
        guard let cat = selectedCategory else { return editablePlaceStops }
        return editablePlaceStops.filter { stop in
            let rawCat = (stop.placeCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let actualCat = rawCat.isEmpty ? "Others" : rawCat
            return actualCat.caseInsensitiveCompare(cat) == .orderedSame
        }
    }

    private var focusedPlaceId: UUID? {
        guard filteredStops.indices.contains(selectedPlaceIndex) else { return nil }
        return filteredStops[selectedPlaceIndex].id
    }

    private func openPhotoModal(for stop: PlaceStop) {
        let included = stop.includedPhotos
        guard !included.isEmpty else { return }
        let captions = Dictionary(uniqueKeysWithValues: included.map { ($0.id, $0.caption ?? "") })
        photoModalCaptions = captions
        photoModalCaptionsSnapshot = captions
        photoModalInitialPhotoId = included.first?.id
        photoModalStop = stop
    }

    private func flushCaptionChanges(stop: PlaceStop) {
        for (photoId, newCaption) in photoModalCaptions {
            let original = photoModalCaptionsSnapshot[photoId] ?? ""
            if newCaption != original {
                onCaptionSaved?(stop.id, photoId, newCaption)
            }
        }
    }

    private func fullScreenMapHeaderGradientOverlay(safeTop: CGFloat) -> some View {
        let chromeHeight: CGFloat = 152
        let fadeTail: CGFloat = 110
        let totalHeight = safeTop + chromeHeight + fadeTail

        return VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .black.opacity(0.32), location: 0.24),
                    .init(color: .black.opacity(0.16), location: 0.5),
                    .init(color: .black.opacity(0.06), location: 0.76),
                    .init(color: .black.opacity(0.015), location: 0.92),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    MapDayView(
                        placeStops: filteredStops,
                        height: geo.size.height,
                        onTap: nil,
                        focusedPlaceId: focusedPlaceId,
                        onAnnotationTap: { stopId in
                            guard let stop = filteredStops.first(where: { $0.id == stopId }) else { return }
                            openPhotoModal(for: stop)
                        },
                        hideStartEndMarkers: selectedCategory != nil
                    )
                    .ignoresSafeArea(edges: .all)

                    if photoModalStop == nil {
                        // Soft top scrim so back button, day title, and category chips stay readable on any map.
                        fullScreenMapHeaderGradientOverlay(safeTop: geo.safeAreaInsets.top)
                            .allowsHitTesting(false)
                            .zIndex(0.5)

                        // Top bar: Back button on left, Day info centered
                        HStack(alignment: .top) {
                            Button(action: onDismiss) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            VStack(spacing: 2) {
                                Text("Day \(day.dayIndex)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 2)

                                Text(day.shortDateText)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.8), radius: 2)
                            }
                            .padding(.top, 4) // Slight visual tweak to center with the 40 height button

                            Spacer()

                            // Invisible spacer for symmetry so the title is perfectly centered
                            Color.clear.frame(width: 40, height: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 44) // Moved up closer to the top edge
                        .zIndex(2)

                        VStack(spacing: 8) {
                            if !availableCategories.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        chip(label: "All", isSelected: selectedCategory == nil) {
                                            withAnimation { selectedCategory = nil; selectedPlaceIndex = 0 }
                                        }
                                        ForEach(availableCategories, id: \.self) { cat in
                                            mapCategoryFilterChip(categoryKey: cat, isSelected: selectedCategory == cat) {
                                                withAnimation { selectedCategory = (selectedCategory == cat) ? nil : cat; selectedPlaceIndex = 0 }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.top, 112) // Extra gap so chips don't crowd the date label
                        .frame(maxWidth: .infinity, alignment: .top)
                        .zIndex(1)

                        if !filteredStops.isEmpty {
                            VStack {
                                Spacer()
                                placeCardsStrip(in: geo)
                                    .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                            }
                        }
                    }
                }
            }

            // Same full-screen fade overlay as RecapBlogPageView place viewer (not a pull-up sheet).
            if let stop = photoModalStop, let initialId = photoModalInitialPhotoId {
                PlacePhotoModalView(
                    placeTitle: Binding(
                        get: { photoModalStop?.placeTitle ?? stop.placeTitle },
                        set: { newValue in
                            guard var updated = photoModalStop else { return }
                            updated.placeTitle = newValue
                            photoModalStop = updated
                        }
                    ),
                    placeSubtitle: stop.placeSubtitle,
                    initialPlaceCategory: stop.placeCategory,
                    photos: stop.includedPhotos,
                    initialPhotoId: initialId,
                    stopDigitizedTime: stop.visitedTimeDigitized,
                    blogIsEditMode: false,
                    showAssetTimeMetadata: false,
                    presentation: .fullscreen(source: .blogMap),
                    photoCaption: { id in
                        Binding(
                            get: { photoModalCaptions[id] ?? "" },
                            set: { photoModalCaptions[id] = $0 }
                        )
                    },
                    onDismiss: {
                        flushCaptionChanges(stop: stop)
                        photoModalStop = nil
                        photoModalInitialPhotoId = nil
                    },
                    onSavePlaceName: { name, category, coord, subtitleLine in
                        guard var updated = photoModalStop else { return }
                        updated.placeTitle = name
                        // `EditPlaceStopNameSheet` passes the resolved category (including nil to clear after a rename).
                        updated.placeCategory = category
                        if let coord {
                            updated.representativeLocation = PhotoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
                        }
                        let trimmedSubtitle = subtitleLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.placeSubtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
                        photoModalStop = updated
                        if let idx = editablePlaceStops.firstIndex(where: { $0.id == updated.id }) {
                            editablePlaceStops[idx] = updated
                        }
                        onPlaceNameSaved?(updated.id, name, category, coord, subtitleLine)
                    },
                    onSavePlaceCategory: { newCategory in
                        guard var updated = photoModalStop else { return }
                        updated.placeCategory = newCategory
                        photoModalStop = updated
                        if let idx = editablePlaceStops.firstIndex(where: { $0.id == updated.id }) {
                            editablePlaceStops[idx] = updated
                        }
                        let subtitleLine = (updated.placeSubtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let coord = updated.representativeLocation?.clCoordinate
                        onPlaceNameSaved?(updated.id, updated.placeTitle, newCategory, coord, subtitleLine)
                    }
                )
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(20)
            }
        }
        .background(Color.black)
        // Keep fullscreen map under system bars, but preserve keyboard safe-area
        // so PlacePhotoModalView's caption editor inset stays above the keyboard.
        .ignoresSafeArea(.container, edges: .all)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.38), value: photoModalStop?.id)
        .onAppear {
            applyInitialFocusIfNeeded()
        }
    }

    private func applyInitialFocusIfNeeded() {
        guard !didApplyInitialFocus else { return }
        didApplyInitialFocus = true
        guard let placeId = initialFocusedPlaceId,
              let index = filteredStops.firstIndex(where: { $0.id == placeId }) else { return }
        selectedPlaceIndex = index
    }

    private func mapCategoryFilterChip(categoryKey: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = PlacePOICategoryPresentation.displayLabel(forRaw: categoryKey)
        let p = PlacePOICategoryPresentation.presentation(forRaw: categoryKey)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? p.color : p.color.opacity(0.35))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(isSelected ? 0.4 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : mapDayFilterChipUnselectedFill().opacity(0.88))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func placeCardsStrip(in geo: GeometryProxy) -> some View {
        let cardWidth = min(geo.size.width * 0.80, 340)
        let cardHeight: CGFloat = 130

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(filteredStops.enumerated()), id: \.element.id) { index, stop in
                    Button {
                        openPhotoModal(for: stop)
                    } label: {
                        PlaceMapCardView(
                            stop: stop,
                            stopNumber: index + 1,
                            isFirst: selectedCategory == nil && index == 0,
                            isLast: selectedCategory == nil && index == filteredStops.count - 1,
                            isSelected: selectedPlaceIndex == index
                        )
                        .frame(width: cardWidth, height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .id(stop.id)
                    .scaleEffect(selectedPlaceIndex == index ? 1.02 : 0.95)
                    .opacity(selectedPlaceIndex == index ? 1.0 : 0.6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPlaceIndex)
                }
            }
            .scrollTargetLayout()
        }
        .safeAreaPadding(.horizontal, (geo.size.width - cardWidth) / 2)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledPlaceID)
        .scrollClipDisabled(true)
        .onChange(of: scrolledPlaceID) { _, newID in
            // Card snapped — update index and recenter map
            if let newID,
               let newIndex = filteredStops.firstIndex(where: { $0.id == newID }),
               newIndex != selectedPlaceIndex {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    selectedPlaceIndex = newIndex
                }
            }
        }
        .onChange(of: selectedPlaceIndex) { _, newIndex in
            // Annotation/button tap drives scroll position
            if let id = filteredStops[safe: newIndex]?.id, scrolledPlaceID != id {
                scrolledPlaceID = id
            }
        }
        .onAppear {
            // Seed initial scroll position to first card
            scrolledPlaceID = filteredStops.first?.id
        }
        .frame(height: cardHeight + 20)
    }
}

/// Category icon + label on map place cards (matches `PlacePOICategoryPresentation`).
    private struct MapPlaceCategoryCaptionLine: View {
        let categoryRaw: String

        var body: some View {
            let p = PlacePOICategoryPresentation.presentation(forRaw: categoryRaw)
            HStack(spacing: 5) {
                Image(systemName: p.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(p.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(p.color)
        }
    }

/// Single place card for full-screen map bottom strip: Premium layout with image left, badge, and text right.
    private struct PlaceMapCardView: View {
        let stop: PlaceStop
        let stopNumber: Int
        let isFirst: Bool
        let isLast: Bool
        let isSelected: Bool

        private var borderColor: Color {
            if isFirst && isLast { return .green }
            if isFirst { return .green }
            if isLast  { return .orange }
            return .white.opacity(0.5)
        }

        var body: some View {
            HStack(spacing: 16) {
                // Left: Photo + start/end badge overlay + order badge
                ZStack(alignment: .topLeading) {
                    // Photo with coloured border
                    Group {
                        if let photo = stop.includedPhotos.first {
                            RecapPhotoThumbnail(photo: photo, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                                .frame(width: 96, height: 96)
                                .clipped()
                                .appChromeCornerRadius(12)
                        } else {
                            RoundedRectangle(appChromeBaseRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 96, height: 96)
                                .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)))
                        }
                    }
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 12)
                            .stroke(borderColor, lineWidth: (isFirst || isLast) ? 3 : 1.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                    // Order badge (top-leading)
                    Text("\(stopNumber)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: -8, y: -8)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

                    // START / END pill in bottom-leading corner of photo
                    if isFirst || isLast {
                        VStack {
                            Spacer()
                            HStack {
                                startEndLabel
                                    .padding(.leading, 4)
                                    .padding(.bottom, 4)
                                Spacer()
                            }
                        }
                        .frame(width: 96, height: 96)
                    }
                }
                .padding(.leading, 8)

                // Right: Text Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(stop.placeTitle)
                        .font(.system(.headline, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let raw = stop.placeCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                        MapPlaceCategoryCaptionLine(categoryRaw: raw)
                    }

                    if let desc = descriptionText, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.trailing, 4)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .appChromeCornerRadius(20)
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 20)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
        }

        @ViewBuilder
        private var startEndLabel: some View {
            if isFirst && isLast {
                startEndPill(text: "START & END", color: .green)
            } else if isFirst {
                startEndPill(text: "START", color: .green)
            } else if isLast {
                startEndPill(text: "END", color: .orange)
            }
        }

        private func startEndPill(text: String, color: Color) -> some View {
            Text(text)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.9)))
                .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 1)
        }

        private var descriptionText: String? {
            if let note = stop.noteText, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return note
            }
            if let photoCaption = stop.includedPhotos.first?.caption, !photoCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return photoCaption
            }
            if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                return subtitle
            }
            return nil
        }
    }

#Preview {
    MapDayView(photos: [
        RecapPhoto(timestamp: Date(), location: PhotoCoordinate(latitude: 35.6762, longitude: 139.6503), imageName: "photo"),
        RecapPhoto(timestamp: Date(), location: PhotoCoordinate(latitude: 35.678, longitude: 139.652), imageName: "camera")
    ])
    .padding()
}
