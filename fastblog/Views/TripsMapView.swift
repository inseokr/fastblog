//
//  TripsMapView.swift
//  Capper
//

import MapKit
import SwiftUI

/// Full-screen map showing draft trips that have a center coordinate. Custom annotation: cover thumbnail + title.
struct TripsMapView: View {
    let trips: [TripDraft]
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
                    TripDraftMapAnnotationView(trip: item.trip)
                        .onTapGesture {
                            onTripTapped?(item.trip)
                        }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}

/// Small card-style marker: cover thumbnail + trip default title.
private struct TripDraftMapAnnotationView: View {
    let trip: TripDraft

    private static let thumbSize: CGFloat = 48
    private static let titleMaxWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 4) {
            TripCoverImage(theme: trip.coverTheme, coverAssetIdentifier: trip.coverAssetIdentifier)
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)

            Text(trip.defaultBlogTitle)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Self.titleMaxWidth)
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
    }
}

#Preview {
    TripsMapView(trips: [], mapPosition: .constant(.automatic))
}
