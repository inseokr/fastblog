//
//  NeighborhoodMapRefinementView.swift
//  Capper
//
//  Created by Capper AI
//

import MapKit
import SwiftUI

struct NeighborhoodMapRefinementView: View {
    var initialRegion: MKCoordinateRegion
    var onDismiss: () -> Void
    
    @State private var mapRegion: MKCoordinateRegion
    @State private var currentCenter: CLLocationCoordinate2D
    @State private var currentSpan: MKCoordinateSpan
    @State private var isResolvingPlace = false
    @State private var showSuccess = false
    @State private var savedName: String?
    
    // Dependencies
    @StateObject private var onboardingState = OnboardingState()
    
    init(initialRegion: MKCoordinateRegion, onDismiss: @escaping () -> Void) {
        self.initialRegion = initialRegion
        self.onDismiss = onDismiss
        _mapRegion = State(initialValue: initialRegion)
        _currentCenter = State(initialValue: initialRegion.center)
        _currentSpan = State(initialValue: initialRegion.span)
    }
    
    var body: some View {
        ZStack {
            // Map
            MapWithRegionBinding(
                region: $mapRegion,
                center: $currentCenter,
                span: $currentSpan
            )
            .ignoresSafeArea()
            
            // Map Overlay (Circle)
            ZStack {
                // Glow
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                
                // Pulsing Core
                RefinementPulsingCircle()
            }
            .allowsHitTesting(false) // Let touches pass to map
            
            // UI Overlay
            VStack {
                // Header
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
                .padding(.top, 60) // Space for status bar/safe area
                
                Spacer()
                
                // Footer Buttons
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
                        // Pop back to search (SwiftUI NavigationStack handles this via dismiss?)
                        // "Search Again" implies going back.
                        // Since we are pushed, we can just use Environment dismiss, 
                        // but here we are presumably at top of stack inside navigation?
                        // No, Intro -> Search -> Refinement.
                        // So we want to go back to Search.
                        // We can use @Environment(\.dismiss)
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
            
            // Success Overlay
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
    
    @Environment(\.dismiss) var dismiss
    
    private func confirmArea() {
        isResolvingPlace = true
        
        // Reverse Geocode to get name (or use what we had if we passed it? But map moved)
        let location = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
        
        Task { @MainActor in
            let place = await GeocodingService.shared.place(for: location)
            let cityName = place.areaName
            
            // Save logic
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
            
            // Delay dismissal
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

// Reuse MapWithRegionBinding (private copy since original is private)
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

