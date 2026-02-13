//
//  NeighborhoodMapRefinementView.swift
//  fastblog
//

import MapKit
import SwiftUI
import UIKit

struct NeighborhoodMapRefinementView: View {
    var initialRegion: MKCoordinateRegion
    var onDismiss: () -> Void

    @State private var mapRegion: MKCoordinateRegion
    @State private var currentCenter: CLLocationCoordinate2D
    @State private var currentSpan: MKCoordinateSpan
    @State private var isResolvingPlace = false
    @State private var showSuccess = false
    @State private var savedName: String?

    @StateObject private var onboardingState = OnboardingState()
    @Environment(\.dismiss) var dismiss

    init(initialRegion: MKCoordinateRegion, onDismiss: @escaping () -> Void) {
        self.initialRegion = initialRegion
        self.onDismiss = onDismiss
        _mapRegion = State(initialValue: initialRegion)
        _currentCenter = State(initialValue: initialRegion.center)
        _currentSpan = State(initialValue: initialRegion.span)
    }

    var body: some View {
        ZStack {
            MapWithRegionBinding(
                region: $mapRegion,
                center: $currentCenter,
                span: $currentSpan
            )
            .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                RefinementPulsingCircle()
            }
            .allowsHitTesting(false)

            VStack {
                VStack(spacing: 8) {
                    Text("Refine Your Neighborhood")
                        .font(.headline)
                        .foregroundColor(.black)
                    Text("Move the map to position your neighborhood.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.top, 60)

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        confirmArea()
                    } label: {
                        HStack {
                            if isResolvingPlace {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Confirm Area")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                    }
                    .disabled(isResolvingPlace)

                    Button("Search Again") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .padding(.bottom, 8)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(20, corners: [.topLeft, .topRight])
            }
            .ignoresSafeArea(edges: .bottom)

            if showSuccess {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .symbolEffect(.bounce, value: showSuccess)
                    Text("Neighborhood Saved")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(40)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
    }

    private func confirmArea() {
        isResolvingPlace = true
        let location = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)

        Task { @MainActor in
            let place = await GeocodingService.shared.place(for: location)
            let cityName = place.areaName

            let selection = NeighborhoodSelection(
                cityName: cityName,
                centerLatitude: currentCenter.latitude,
                centerLongitude: currentCenter.longitude,
                spanLatitudeDelta: currentSpan.latitudeDelta,
                spanLongitudeDelta: currentSpan.longitudeDelta
            )
            onboardingState.saveSelection(selection)
            NeighborhoodStore.saveCenter(currentCenter)

            isResolvingPlace = false
            savedName = cityName

            withAnimation {
                showSuccess = true
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onDismiss()
        }
    }
}

// MARK: - Components

private struct RefinementPulsingCircle: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(Color.orange.opacity(0.75))
            .frame(width: 80, height: 80)
            .scaleEffect(isExpanded ? 1.1 : 0.95)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isExpanded
            )
            .onAppear {
                isExpanded = true
            }
    }
}

private struct MapWithRegionBinding: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var center: CLLocationCoordinate2D
    @Binding var span: MKCoordinateSpan

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.region = region
        map.delegate = context.coordinator
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let desired = MKCoordinateRegion(center: region.center, span: region.span)
        if regionsAreClose(mapView.region, desired) { return }

        context.coordinator.isProgrammaticChange = true
        mapView.setRegion(desired, animated: true)

        DispatchQueue.main.async {
            context.coordinator.isProgrammaticChange = false
        }
    }

    private func regionsAreClose(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 0.000_001 &&
        abs(a.center.longitude - b.center.longitude) < 0.000_001 &&
        abs(a.span.latitudeDelta - b.span.latitudeDelta) < 0.000_001 &&
        abs(a.span.longitudeDelta - b.span.longitudeDelta) < 0.000_001
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithRegionBinding
        var isProgrammaticChange = false

        init(_ parent: MapWithRegionBinding) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isProgrammaticChange else { return }
            let newCenter = mapView.region.center
            let newSpan = mapView.region.span

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.center = newCenter
                self.parent.span = newSpan
            }
        }
    }
}

extension View {
    fileprivate func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
