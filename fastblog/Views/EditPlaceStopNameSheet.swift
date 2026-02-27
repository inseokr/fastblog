//
//  EditPlaceStopNameSheet.swift
//  fastblog
//

import CoreLocation
import MapKit
import SwiftUI

struct EditPlaceStopNameSheet: View {
    @Binding var placeTitle: String
    var location: CLLocationCoordinate2D?
    var onSave: (String, CLLocationCoordinate2D?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchViewModel = PlaceSearchViewModel()
    @State private var editedTitle: String = ""
    @FocusState private var isFocused: Bool
    @State private var showSuggestions: Bool = true
    @State private var isResolvingPOI: Bool = false
    /// When user taps a POI on the map, we resolve the name and store the tapped coordinate to save as the place's location.
    @State private var selectedCoordinate: CLLocationCoordinate2D? = nil
    /// When user taps a POI (or picks from autocomplete), we resolve and store category (MKPointOfInterestCategory raw value).
    @State private var selectedCategory: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let coord = location {
                    TappableMapView(
                        center: coord,
                        onTap: { tappedCoordinate, mapRegion in
                            resolvePOI(at: tappedCoordinate, mapRegion: mapRegion)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay {
                        if isResolvingPOI {
                            Color.black.opacity(0.3)
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                                .allowsHitTesting(true)
                        }
                    }
                } else {
                    Color(white: 0.08)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    autocompleteBar
                    if isFocused, showSuggestions, !searchViewModel.suggestions.isEmpty {
                        suggestionsListContent
                    }
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "Stop" : trimmed, selectedCoordinate, selectedCategory)
                        dismiss()
                    }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(editedTitle != placeTitle || selectedCoordinate != nil || selectedCategory != nil ? .blue : .primary)
                }
            }
            .onAppear {
                editedTitle = placeTitle.hasPrefix("Near ") ? String(placeTitle.dropFirst(5)) : placeTitle
                selectedCoordinate = nil
                selectedCategory = nil
                searchViewModel.setBiasLocation(location)
            }
            .overlay(alignment: .bottom) {
                if location != nil, !isResolvingPOI {
                    Text("Tap a place on the map to use its name")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(.bottom, 16)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Autocomplete bar (compact, minimal top padding)
    private var autocompleteBar: some View {
        HStack {
            TextField("Place name", text: $editedTitle)
                .focused($isFocused)
                .autocorrectionDisabled()
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        showSuggestions = true
                        searchViewModel.query = editedTitle
                    }
                }
                .onChange(of: editedTitle) { oldValue, newValue in
                    if oldValue == placeTitle && newValue.hasPrefix(placeTitle) && newValue.count > oldValue.count {
                        editedTitle = String(newValue.dropFirst(placeTitle.count))
                    } else if showSuggestions {
                        searchViewModel.query = newValue
                    }
                }

            if !editedTitle.isEmpty {
                Button {
                    editedTitle = ""
                    searchViewModel.query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12))
    }

    // MARK: - Resolve POI at tapped coordinate (reverse geocode → place name + category)
    // Note: NSCocoaErrorDomain 4099 / PerfPowerTelemetryClientRegistrationService / "Maps SpringfieldUsage"
    // is a known iOS Simulator sandbox warning from MapKit telemetry. It does not affect POI resolution;
    // running on a real device usually avoids it. We guard against overlapping requests to reduce system load.
    private func resolvePOI(at coordinate: CLLocationCoordinate2D, mapRegion: MKCoordinateRegion? = nil) {
        if isResolvingPOI {
            debugPrint("[POI] resolvePOI skipped (already resolving)")
            return
        }
        debugPrint("[POI] resolvePOI started lat=\(coordinate.latitude) lon=\(coordinate.longitude)")
        isResolvingPOI = true
        isFocused = false
        showSuggestions = false
        Task { @MainActor in
            defer {
                isResolvingPOI = false
                debugPrint("[POI] resolvePOI finished")
            }
            // Prefer POI-at-tap (e.g. restaurant inside mall) over reverse geocode (which returns building/area).
            if let poi = await searchViewModel.resolvePOIAtCoordinate(coordinate, mapRegion: mapRegion) {
                debugPrint("[POI] POI-at-tap result: name=\(poi.name), category=\(poi.category ?? "nil")")
                editedTitle = poi.name
                selectedCoordinate = coordinate
                selectedCategory = poi.category
                debugPrint("[POI] updated: editedTitle=\(editedTitle), selectedCoordinate=\(coordinate.latitude),\(coordinate.longitude)")
                return
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            debugPrint("[POI] no POI at tap, falling back to reverse geocode...")
            let place = await GeocodingService.shared.place(for: location, precise: true)
            debugPrint("[POI] geocode result: title=\(place.title), bestPlaceLabel=\(place.bestPlaceLabel)")
            let name = !place.title.isEmpty ? place.title : place.bestPlaceLabel
            if !name.isEmpty, name != "Unknown Place" {
                editedTitle = name
                selectedCoordinate = coordinate
                debugPrint("[POI] set name=\(name), fetching category...")
                if let category = await searchViewModel.fetchCategory(at: coordinate, name: name) {
                    selectedCategory = category
                    debugPrint("[POI] category=\(category)")
                } else {
                    debugPrint("[POI] category=nil")
                }
                debugPrint("[POI] updated: editedTitle=\(editedTitle), selectedCoordinate=\(coordinate.latitude),\(coordinate.longitude)")
            } else {
                debugPrint("[POI] skipped update: name empty or Unknown Place")
            }
        }
    }

    // MARK: - Tappable map (tap → coordinate → resolve POI)
    private struct TappableMapView: UIViewRepresentable {
        let center: CLLocationCoordinate2D
        var onTap: (CLLocationCoordinate2D, MKCoordinateRegion) -> Void

        func makeUIView(context: Context) -> MKMapView {
            let map = MKMapView()
            map.delegate = context.coordinator
            map.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            )
            map.mapType = .standard
            map.showsUserLocation = false
            let ann = MKPointAnnotation()
            ann.coordinate = center
            map.addAnnotation(ann)
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            map.addGestureRecognizer(tap)
            debugPrint("[POI] TappableMapView makeUIView: tap recognizer added (cancelsTouchesInView=false)")
            return map
        }

        func updateUIView(_ mapView: MKMapView, context: Context) {
            // Do not reset region here — SwiftUI calls this on every state change (e.g. isResolvingPOI),
            // which was overriding the user's zoom/pan. Initial region is set in makeUIView only.
            if let pin = mapView.annotations.first(where: { $0 is MKPointAnnotation }) as? MKPointAnnotation {
                pin.coordinate = center
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, MKMapViewDelegate {
            let parent: TappableMapView

            init(_ parent: TappableMapView) {
                self.parent = parent
            }

            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                debugPrint("[POI] handleTap state=\(gesture.state.rawValue)")
                guard gesture.state == .ended else {
                    debugPrint("[POI] handleTap ignored (state != .ended)")
                    return
                }
                guard let mapView = gesture.view as? MKMapView else {
                    debugPrint("[POI] handleTap ignored (view is not MKMapView)")
                    return
                }
                let point = gesture.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                debugPrint("[POI] tap at point=\(point), coordinate=\(coordinate.latitude),\(coordinate.longitude) -> calling onTap")
                parent.onTap(coordinate, mapView.region)
            }

            func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
                guard annotation is MKPointAnnotation else { return nil }
                let id = "Pin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "mappin.circle.fill")
                view.canShowCallout = false
                return view
            }
        }
    }

    // MARK: - Nearby list (directly under place name bar, same background = connected)
    private var suggestionsListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(white: 0.25))
                .frame(height: 1)
            Text("Nearby Suggestions")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                        ForEach(Array(searchViewModel.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                showSuggestions = false
                                isFocused = false
                                editedTitle = suggestion.title
                                searchViewModel.suggestions = []
                                Task {
                                    selectedCategory = await searchViewModel.fetchCategory(for: suggestion)
                                }
                            } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .background(Color(white: 0.3))
                            .padding(.leading, 16)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .background(Color(white: 0.12))
    }
}

#Preview {
    EditPlaceStopNameSheet(
        placeTitle: .constant("Iceland Ring Road"),
        location: CLLocationCoordinate2D(latitude: 64.15, longitude: -21.95),
        onSave: { _, _, _ in }
    )
}
