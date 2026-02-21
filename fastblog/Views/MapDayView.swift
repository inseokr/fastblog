//
//  MapDayView.swift
//  Capper
//

import MapKit
import SwiftUI

/// One marker per place: coordinate, first photo (for image), place title. Order preserved for route.
struct PlaceMapMarker: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let firstPhoto: RecapPhoto
    let placeTitle: String
}

/// Map for one day: one marker per place (first photo as marker image), place name below, route line in visit order. Tap to open full-screen map when onTap provided.
struct MapDayView: View {
    let placeStops: [PlaceStop]
    var height: CGFloat = 220
    var onTap: (() -> Void)?
    /// When set, map region centers on this place's coordinate (e.g. for full-screen card sync).
    var focusedPlaceId: UUID? = nil
    
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(placeStops: [PlaceStop], height: CGFloat = 220, onTap: (() -> Void)? = nil, focusedPlaceId: UUID? = nil) {
        self.placeStops = placeStops
        self.height = height
        self.onTap = onTap
        self.focusedPlaceId = focusedPlaceId
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color(red: 0, green: 122/255, blue: 1), lineWidth: 4)
            }
            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                let placeNumber = index + 1
                let isFirst = index == 0
                let isLast = index == markers.count - 1
                Annotation("", coordinate: marker.coordinate) {
                    PlaceMarkerView(
                        photo: marker.firstPhoto,
                        title: marker.placeTitle,
                        placeNumber: placeNumber,
                        isFirst: isFirst,
                        isLast: isLast
                    )
                }
            }
            
            // Mileage markers between points
            ForEach(0..<markers.count - 1, id: \.self) { i in
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
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            updateCameraPosition(animated: false)
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
            let coord = stop.representativeLocation?.clCoordinate
                ?? stop.photos.first(where: { $0.location != nil })?.location?.clCoordinate
            guard let coordinate = coord, let first = stop.photos.first else { return nil }
            return PlaceMapMarker(
                id: stop.id,
                coordinate: coordinate,
                firstPhoto: first,
                placeTitle: stop.placeTitle
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

    private var orderLabel: String {
        switch placeNumber {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(placeNumber)th"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            if isFirst && isLast {
                startEndBadge(text: "START & END", color: Color.green)
            } else if isFirst {
                startEndBadge(text: "START", color: Color.green)
            } else if isLast {
                startEndBadge(text: "END", color: Color.orange)
            }

            ZStack(alignment: .bottomTrailing) {
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

                Text("\(placeNumber)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.blue.opacity(0.9)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .offset(x: 4, y: 4)
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
                .cornerRadius(6)
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
    }
}

// MARK: - Full-screen map (tap day map to open)

/// Full-screen map for one day: same markers, route, labels; bottom place cards scroll one-by-one and drive map center.
struct FullScreenMapView: View {
    let day: RecapBlogDay
    var onDismiss: () -> Void

    @State private var selectedPlaceIndex: Int = 0

    private var focusedPlaceId: UUID? {
        guard day.placeStops.indices.contains(selectedPlaceIndex) else { return nil }
        return day.placeStops[selectedPlaceIndex].id
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                MapDayView(
                    placeStops: day.placeStops,
                    height: geo.size.height,
                    onTap: nil,
                    focusedPlaceId: focusedPlaceId
                )
                .ignoresSafeArea(edges: .all)

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.top, 56)
                .padding(.trailing, 20)

                if !day.placeStops.isEmpty {
                    VStack {
                        Spacer()
                        placeCardsStrip(in: geo)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
        .preferredColorScheme(.dark)
    }

    @State private var scrolledPlaceID: UUID?

    private func placeCardsStrip(in geo: GeometryProxy) -> some View {
        let cardWidth = min(geo.size.width * 0.80, 340)
        let cardHeight: CGFloat = 130

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                    PlaceMapCardView(stop: stop, stopNumber: index + 1, isSelected: selectedPlaceIndex == index)
                        .frame(width: cardWidth, height: cardHeight)
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
        .onChange(of: scrolledPlaceID) { _, newID in
            // Card snapped — update index and recenter map
            if let newID,
               let newIndex = day.placeStops.firstIndex(where: { $0.id == newID }),
               newIndex != selectedPlaceIndex {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    selectedPlaceIndex = newIndex
                }
            }
        }
        .onChange(of: selectedPlaceIndex) { _, newIndex in
            // Annotation/button tap drives scroll position
            if let id = day.placeStops[safe: newIndex]?.id, scrolledPlaceID != id {
                scrolledPlaceID = id
            }
        }
        .onAppear {
            // Seed initial scroll position to first card
            scrolledPlaceID = day.placeStops.first?.id
        }
        .frame(height: cardHeight + 20)
    }
}

/// Single place card for full-screen map bottom strip: number + title, description, photo on right; blue border when selected.
    /// Single place card for full-screen map bottom strip: Premium layout with image left, badge, and text right.
    private struct PlaceMapCardView: View {
        let stop: PlaceStop
        let stopNumber: Int
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 16) {
                // Left: Photo + Badge
                ZStack(alignment: .topLeading) {
                    if let photo = stop.photos.first {
                        RecapPhotoThumbnail(photo: photo, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                            .frame(width: 96, height: 96)
                            .clipped()
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 96, height: 96)
                            .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)))
                    }

                    // Order Badge
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
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
        }

        private var descriptionText: String? {
            if let note = stop.noteText, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return note
            }
            if let photoCaption = stop.photos.first?.caption, !photoCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
