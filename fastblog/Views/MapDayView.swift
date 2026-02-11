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

    init(placeStops: [PlaceStop], height: CGFloat = 220, onTap: (() -> Void)? = nil, focusedPlaceId: UUID? = nil) {
        self.placeStops = placeStops
        self.height = height
        self.onTap = onTap
        self.focusedPlaceId = focusedPlaceId
    }

    var body: some View {
        Map(position: .constant(.region(region))) {
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
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
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
        if let focusId = focusedPlaceId, let marker = markers.first(where: { $0.id == focusId }) {
            return MKCoordinateRegion(
                center: marker.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.0035, longitudeDelta: 0.0035)
            )
        }
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
                .shadow(color: .black.opacity(0.6), radius: 1)
                .frame(maxWidth: 76)

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

    private func placeCardsStrip(in geo: GeometryProxy) -> some View {
        let cardWidth = min(geo.size.width * 0.88, 340)
        let cardHeight: CGFloat = 120

        return TabView(selection: $selectedPlaceIndex) {
            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                PlaceMapCardView(stop: stop, stopNumber: index + 1, isSelected: selectedPlaceIndex == index)
                    .frame(width: cardWidth, height: cardHeight)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: cardHeight)
    }
}

/// Single place card for full-screen map bottom strip: number + title, description, photo on right; blue border when selected.
private struct PlaceMapCardView: View {
    let stop: PlaceStop
    let stopNumber: Int
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(stopNumber) \(stop.placeTitle)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let photo = stop.photos.first {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                    .frame(width: 72, height: 72)
                    .clipped()
                    .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
    }

    private var descriptionText: String {
        if let note = stop.noteText, !note.isEmpty {
            return note
        }
        if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
            return subtitle
        }
        return "\(stop.photos.count) photo\(stop.photos.count == 1 ? "" : "s")"
    }
}

#Preview {
    MapDayView(photos: [
        RecapPhoto(timestamp: Date(), location: PhotoCoordinate(latitude: 35.6762, longitude: 139.6503), imageName: "photo"),
        RecapPhoto(timestamp: Date(), location: PhotoCoordinate(latitude: 35.678, longitude: 139.652), imageName: "camera")
    ])
    .padding()
}
