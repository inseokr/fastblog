//
//  TripsMapView.swift
//  Capper
//

import MapKit
import SwiftUI

/// Full-screen map showing draft trips with selection-aware markers.
struct TripsMapView: View {
    let trips: [TripDraft]
    @Binding var selectedTripID: UUID?
    @Binding var mapPosition: MapCameraPosition
    var onTripTapped: ((TripDraft) -> Void)?
    var onMapRegionChanged: ((MKCoordinateRegion) -> Void)?

    /// Trips that have a center coordinate for map display.
    private var tripsWithCoordinate: [(trip: TripDraft, coordinate: CLLocationCoordinate2D)] {
        trips.compactMap { trip in
            trip.centerCoordinate.map { (trip, $0) }
        }
    }

    var body: some View {
        Map(position: $mapPosition) {
            ForEach(tripsWithCoordinate, id: \.trip.id) { item in
                Annotation("", coordinate: item.coordinate) {
                    TripDraftMapAnnotationView(
                        trip: item.trip,
                        isSelected: item.trip.id == selectedTripID
                    )
                    .onTapGesture {
                        onTripTapped?(item.trip)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            onMapRegionChanged?(context.region)
        }
    }
}

/// Selection-aware map marker with glow and pulse when selected.
/// Unselected trips render as a compact dot to avoid overlap when many trips share a region.
private struct TripDraftMapAnnotationView: View {
    let trip: TripDraft
    let isSelected: Bool

    @State private var isPulsing = false

    private static let thumbSize: CGFloat = 64
    private static let titleMaxWidth: CGFloat = 100
    private static let dotSize: CGFloat = 14

    var body: some View {
        ZStack {
            if isSelected {
                selectedMarker
            } else {
                unselectedDot
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .onChange(of: isSelected) { _, selected in
            if selected {
                isPulsing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }

    // MARK: Selected — full thumbnail card with title and pulse ring

    private var selectedMarker: some View {
        VStack(spacing: 5) {
            ZStack {
                // Glow ring behind selected marker
                RoundedRectangle(appChromeBaseRadius: 10)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: Self.thumbSize + 12, height: Self.thumbSize + 12)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: isPulsing
                    )

                TripCoverImage(
                    theme: trip.coverTheme,
                    coverAssetIdentifier: trip.coverAssetIdentifier,
                    targetSize: CGSize(width: 200, height: 200)
                )
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(appChromeBaseRadius: 10))
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 10)
                        .stroke(Color.white, lineWidth: 2.5)
                )
                .shadow(color: Color.white.opacity(0.35), radius: 10)
            }

            Text(trip.defaultBlogTitle)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Self.titleMaxWidth)
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Unselected — small dot so nearby markers don't pile up

    private var unselectedDot: some View {
        Circle()
            .fill(Color.white.opacity(0.9))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    TripsMapView(trips: [], selectedTripID: .constant(nil), mapPosition: .constant(.automatic))
}
