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
    }
}

/// Selection-aware map marker with glow and pulse when selected.
private struct TripDraftMapAnnotationView: View {
    let trip: TripDraft
    let isSelected: Bool

    @State private var isPulsing = false

    private static let thumbSize: CGFloat = 64
    private static let titleMaxWidth: CGFloat = 100

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Glow ring behind selected marker
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: Self.thumbSize + 12, height: Self.thumbSize + 12)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }

                TripCoverImage(
                    theme: trip.coverTheme,
                    coverAssetIdentifier: trip.coverAssetIdentifier,
                    targetSize: CGSize(width: 200, height: 200)
                )
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Color.white.opacity(isSelected ? 1.0 : 0.4),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
                .shadow(
                    color: isSelected ? Color.white.opacity(0.35) : Color.black.opacity(0.3),
                    radius: isSelected ? 10 : 3,
                    x: 0,
                    y: isSelected ? 0 : 2
                )
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
        .scaleEffect(isSelected ? 1.2 : 0.8)
        .opacity(isSelected ? 1.0 : 0.5)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .onChange(of: isSelected) { _, selected in
            if selected {
                isPulsing = false
                // Reset then start pulse
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

#Preview {
    TripsMapView(trips: [], selectedTripID: .constant(nil), mapPosition: .constant(.automatic))
}
