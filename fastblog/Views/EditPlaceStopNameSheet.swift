//
//  EditPlaceStopNameSheet.swift
//  fastblog
//

import CoreLocation
import MapKit
import SwiftUI

struct EditPlaceStopNameSheet: View {
    @Binding var placeTitle: String
    /// City / country line under the title; editable even when there is no map or photos.
    var initialPlaceSubtitle: String? = nil
    /// Existing `PlaceStop.placeCategory` when opening the sheet. Kept on save only when the place name is unchanged; renames re-resolve or clear (see `saveAndDismissAsync`).
    var initialPlaceCategory: String? = nil
    var location: CLLocationCoordinate2D?
    /// All stop photos; the bottom thumbnail strip shows only `isIncluded` (blog-visible) shots.
    var photos: [RecapPhoto] = []
    /// Title, coordinate, POI category raw value, trimmed subtitle (empty clears subtitle).
    var onSave: (String, CLLocationCoordinate2D?, String?, String) -> Void
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
    /// True only when the map tap resolved via `MKLocalPointsOfInterestRequest` (a POI), not reverse-geocode fallback.
    @State private var mapTapResolvedAsPOI: Bool = false
    /// Set to true when the user picks a result from the autocomplete suggestions list.
    @State private var pickedFromAutocomplete: Bool = false
    @State private var initialTitle: String = ""
    @State private var editedSubtitle: String = ""
    @State private var initialSubtitle: String = ""
    @State private var initialCoordinate: CLLocationCoordinate2D? = nil
    @State private var initialCategory: String? = nil
    @State private var showSaveConfirmationAlert = false
    @State private var showMapTapPOIDisambiguation = false
    @State private var mapTapPOIDisambiguationCandidates: [MapTapPOICandidate] = []
    /// Incremented to request zoom on the embedded `MKMapView` (handled in `TappableMapView.updateUIView`).
    @State private var mapZoomInTrigger = 0
    @State private var mapZoomOutTrigger = 0
    @State private var isSavingName = false
    /// One-time coachmark for “tap the map to fill the place name” (shown until dismissed or the user taps the map).
    @AppStorage("blogify.editPlaceMapTapCoachmarkSeen") private var mapTapCoachmarkSeen = false
    @State private var showMapTapCoachmarkSheet = false
    /// Tapping a strip thumbnail opens a full-screen preview (swipe between included photos).
    @State private var enlargedStripPhoto: RecapPhoto? = nil
    /// Square cell size for the stacked map zoom control (compact, map-style).
    private let mapZoomControlSide: CGFloat = 34

    private var stripPhotos: [RecapPhoto] {
        photos.filter(\.isIncluded).filter(\.hasDisplayableLocalBacking)
    }

    /// Extra space above the bottom hint so the photo strip does not cover it.
    /// Scales with Dynamic Type so the hint capsule never overlaps photos at large text sizes.
    @ScaledMetric(relativeTo: .caption) private var mapBottomHintClearance: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
            Group {
                if let coord = location {
                    TappableMapView(
                        center: selectedCoordinate ?? coord,
                        title: selectedCoordinate != nil ? editedTitle : nil,
                        zoomInTrigger: mapZoomInTrigger,
                        zoomOutTrigger: mapZoomOutTrigger,
                        onTap: { tappedCoordinate, mapRegion in
                            resolvePOI(at: tappedCoordinate, mapRegion: mapRegion)
                        },
                        onMapFeatureTap: { feature, mapRegion, endMapSelection in
                            resolvePOIFromMapFeature(feature, mapRegion: mapRegion, endMapSelection: endMapSelection)
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
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    autocompleteBar
                    // Only when there is no map: subtitle is the second line of place context (not a second “place name” row).
                    if location == nil {
                        subtitleField
                    }
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
                        if hasChanges {
                            showSaveConfirmationAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    let canSave = !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button("Save") {
                        Task { await saveAndDismissAsync() }
                    }
                    .disabled(!canSave || isSavingName)
                    .foregroundStyle(canSave && !isSavingName ? Color(uiColor: .systemBlue) : Color.white.opacity(0.35))
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .alert("Save changes?", isPresented: $showSaveConfirmationAlert) {
                Button("Save") {
                    Task { await saveAndDismissAsync() }
                }
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text(
                    location == nil
                        ? "You have unsaved changes to the place name, city or country, or location. Would you like to save them before leaving?"
                        : "You have unsaved changes to the place name or location. Would you like to save them before leaving?"
                )
            }
            .sheet(isPresented: $showMapTapPOIDisambiguation) {
                mapTapPOIDisambiguationSheet
            }
            .onAppear {
                let initialValue = placeTitle.hasPrefix("Near ") ? String(placeTitle.dropFirst(5)) : placeTitle
                editedTitle = initialValue
                initialTitle = initialValue
                let subSeed = initialPlaceSubtitle ?? ""
                editedSubtitle = subSeed
                initialSubtitle = subSeed
                selectedCoordinate = nil
                initialCoordinate = nil
                selectedCategory = initialPlaceCategory
                initialCategory = initialPlaceCategory
                mapTapResolvedAsPOI = false
                pickedFromAutocomplete = false
                searchViewModel.setBiasLocation(location)
                if location != nil, !mapTapCoachmarkSeen {
                    showMapTapCoachmarkSheet = true
                }
            }
            .onChange(of: isResolvingPOI) { _, resolving in
                if resolving { mapTapCoachmarkSeen = true }
            }
            .sheet(isPresented: $showMapTapCoachmarkSheet, onDismiss: {
                mapTapCoachmarkSeen = true
            }) {
                mapTapCoachmarkSheetContent
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
            .preferredColorScheme(.dark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            editPlaceBottomPhotoStripOverlay
            editPlaceBottomMapChromeOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(item: $enlargedStripPhoto) { photo in
            EditPlaceStripPhotoFullScreenViewer(photos: stripPhotos, initialPhoto: photo)
        }
    }

    /// Sibling of `NavigationStack` so bottom alignment uses the sheet’s full bounds, not the nav stack’s safe-area-inset overlay region.
    @ViewBuilder
    private var editPlaceBottomPhotoStripOverlay: some View {
        if !stripPhotos.isEmpty && !isFocused {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    mapZoomControlsColumn
                        .padding(.leading, 16)
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(stripPhotos) { photo in
                            Button {
                                enlargedStripPhoto = photo
                            } label: {
                                RecapPhotoThumbnail(photo: photo, cornerRadius: 10, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                                    .frame(width: 90, height: 90)
                                    .clipped()
                                    .appChromeCornerRadius(10)
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View photo larger")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                Spacer()
                    .frame(height: mapBottomHintClearance)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var editPlaceBottomMapChromeOverlay: some View {
        if location != nil, !isResolvingPOI {
            Group {
                if selectedCoordinate != nil, mapTapResolvedAsPOI {
                    Button {
                        let query = editedTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let urlString = "https://www.google.com/maps/search/?api=1&query=\(query)"
                        if let url = URL(string: urlString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.88, blue: 0.72),
                                            Color(red: 0.28, green: 0.72, blue: 0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("View on Google Maps")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .background {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(Color.black.opacity(0.38))
                                }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        }
                        .appChromeCornerRadius(24)
                        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
                    }
                } else if selectedCoordinate == nil {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        mapTapPlaceNameHint
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .allowsHitTesting(false)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var mapTapPlaceNameHint: some View {
        HStack {
            Spacer(minLength: 0)
            mapTapPlaceNameCompactHint
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// First visit: pull-up modal explaining map interaction for editing the place name.
    private var mapTapCoachmarkSheetContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "mappin.and.ellipse")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.cyan)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Edit your place name")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("Tap any place on the map to set it as this moment's location. You can also zoom in and out to discover more place names, or type a name directly in the search bar.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                showMapTapCoachmarkSheet = false
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .appChromeCornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }

    /// Returning users: small reminder aligned with the map chrome.
    private var mapTapPlaceNameCompactHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(.cyan)
            Text("Tap the map to use a place name")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func applyMapTapPOIChoice(_ candidate: MapTapPOICandidate) {
        editedTitle = candidate.name
        selectedCoordinate = candidate.coordinate
        selectedCategory = candidate.category
        mapTapResolvedAsPOI = true
        showMapTapPOIDisambiguation = false
        mapTapPOIDisambiguationCandidates = []
    }

    private var mapTapPOIDisambiguationSheet: some View {
        NavigationStack {
            List(mapTapPOIDisambiguationCandidates) { candidate in
                Button {
                    applyMapTapPOIChoice(candidate)
                } label: {
                    let p = PlacePOICategoryPresentation.presentation(forRaw: candidate.category)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(p.color)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(p.color.opacity(0.18))
                            )
                            .overlay(
                                Circle()
                                    .stroke(p.color.opacity(0.35), lineWidth: 1)
                            )
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(
                                candidate.distanceMeters < 8
                                    ? "Very near your tap"
                                    : String(format: "About %.0f m from your tap", candidate.distanceMeters)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Which place is this?")
                            .font(.headline)
                        Text("Choose the correct place name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var hasChanges: Bool {
        let trimmedCurrent = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInitial = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subCurrent = editedSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subInitial = initialSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitleDiffers = (location == nil) && (subCurrent != subInitial)

        return trimmedCurrent != trimmedInitial ||
               subtitleDiffers ||
               selectedCoordinate?.latitude != initialCoordinate?.latitude ||
               selectedCoordinate?.longitude != initialCoordinate?.longitude ||
               selectedCategory != initialCategory
    }

    private var mapZoomControlsColumn: some View {
        VStack(spacing: 0) {
            Button {
                mapZoomInTrigger += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: mapZoomControlSide, height: mapZoomControlSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .accessibilityLabel("Zoom in")

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: mapZoomControlSide, height: 1)

            Button {
                mapZoomOutTrigger += 1
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: mapZoomControlSide, height: mapZoomControlSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .accessibilityLabel("Zoom out")
        }
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(appChromeBaseRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(appChromeBaseRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    @MainActor
    private func saveAndDismissAsync() async {
        isSavingName = true
        defer { isSavingName = false }

        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Stop" : trimmed

        let trimmedInitial = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleChanged = finalName != trimmedInitial
        let inferred = PlacePOICategoryPresentation.inferredCategoryRaw(fromPlaceTitle: finalName)

        var category: String?
        if !titleChanged {
            category = selectedCategory
        }
        if category == nil {
            let searchCoord = selectedCoordinate ?? location
            if let searchCoord {
                category = await searchViewModel.fetchCategory(at: searchCoord, name: finalName)
            }
        }
        if category == nil {
            category = inferred
        }
        if titleChanged, inferred == nil, PlacePOICategoryPresentation.titleLooksLikeAddressOrGenericPlaceholder(finalName) {
            category = nil
        }

        debugPrint("[Category] EditPlaceStopNameSheet save: name='\(finalName)' category=\(category ?? "nil") coord=\(selectedCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "nil")")
        if mapTapResolvedAsPOI {
            AppAnalytics.trackEvent(name: "Blog-Place-ChangeName-ClickPoi")
        } else if pickedFromAutocomplete {
            AppAnalytics.trackEvent(name: "Blog-Place-ChangeName-AutoComplete")
        } else {
            AppAnalytics.trackEvent(name: "Blog-Place-ChangeName-Custom")
        }
        let subTrimmed: String = {
            if location == nil {
                return editedSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return initialSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        onSave(finalName, selectedCoordinate, category, subTrimmed)
        dismiss()
    }

    /// City / country (or any subtitle); always available so users can fix metadata without photos or map.
    private var subtitleField: some View {
        HStack {
            TextField("City, country", text: $editedSubtitle)
                .autocorrectionDisabled()
                .foregroundColor(.primary)
            if !editedSubtitle.isEmpty {
                Button {
                    editedSubtitle = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.18))
        .appChromeCornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(white: 0.12))
    }

    // MARK: - Autocomplete bar (compact, minimal top padding)
    private var autocompleteBar: some View {
        HStack {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.18))
            .appChromeCornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            switch await searchViewModel.resolveMapTapPOI(near: coordinate, mapRegion: mapRegion) {
            case .single(let name, let category, let coord):
                debugPrint("[POI] map-tap single: name=\(name), category=\(category ?? "nil")")
                editedTitle = name
                selectedCoordinate = coord
                selectedCategory = category
                mapTapResolvedAsPOI = true
                debugPrint("[POI] updated: editedTitle=\(editedTitle), coord=\(coord.latitude),\(coord.longitude)")
                return
            case .ambiguous(let candidates):
                debugPrint("[POI] map-tap ambiguous: \(candidates.count) choices")
                mapTapPOIDisambiguationCandidates = candidates
                showMapTapPOIDisambiguation = true
                return
            case .none:
                break
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            debugPrint("[POI] no POI at tap, falling back to reverse geocode...")
            let place = await GeocodingService.shared.place(for: location, precise: true)
            debugPrint("[POI] geocode result: title=\(place.title), bestPlaceLabel=\(place.bestPlaceLabel)")
            let name = !place.title.isEmpty ? place.title : place.bestPlaceLabel
            if !name.isEmpty, name != "Unknown Place" {
                editedTitle = name
                selectedCoordinate = coordinate
                mapTapResolvedAsPOI = false
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

    /// Uses the map feature Apple associated with the tap (same hit-testing as the Maps UI), then `MKMapItemRequest`
    /// for the canonical name. `endMapSelection` clears MapKit’s selection **after** we finish so the user doesn’t
    /// get a lingering “dot only” state with no label while we load.
    private func resolvePOIFromMapFeature(
        _ annotation: MKMapFeatureAnnotation,
        mapRegion: MKCoordinateRegion,
        endMapSelection: @escaping () -> Void
    ) {
        if isResolvingPOI {
            debugPrint("[POI] resolvePOIFromMapFeature skipped (already resolving)")
            endMapSelection()
            return
        }
        debugPrint("[POI] resolvePOIFromMapFeature started")
        isResolvingPOI = true
        isFocused = false
        showSuggestions = false
        Task { @MainActor in
            defer { endMapSelection() }
            let request = MKMapItemRequest(mapFeatureAnnotation: annotation)
            var mapItem: MKMapItem?
            do {
                mapItem = try await request.mapItem
            } catch {
                debugPrint("[POI] MKMapItemRequest.mapItem error: \(error)")
            }
            if let mapItem,
               let raw = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                debugPrint("[POI] map feature → mapItem name=\(raw)")
                editedTitle = raw
                selectedCoordinate = mapItem.placemark.coordinate
                selectedCategory = mapItem.pointOfInterestCategory?.rawValue
                mapTapResolvedAsPOI = true
                isResolvingPOI = false
                debugPrint("[POI] resolvePOIFromMapFeature finished (mapItem)")
                return
            }
            let titlePart = annotation.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitlePart = annotation.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = [titlePart, subtitlePart].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            if !combined.isEmpty {
                debugPrint("[POI] map feature fallback annotation title/subtitle=\(combined)")
                editedTitle = combined
                selectedCoordinate = annotation.coordinate
                selectedCategory = annotation.pointOfInterestCategory?.rawValue
                mapTapResolvedAsPOI = true
                isResolvingPOI = false
                debugPrint("[POI] resolvePOIFromMapFeature finished (annotation text)")
                return
            }
            debugPrint("[POI] map feature had no resolvable name, falling back to coordinate POI search")
            isResolvingPOI = false
            resolvePOI(at: annotation.coordinate, mapRegion: mapRegion)
        }
    }

    // MARK: - Tappable map (tap → coordinate → resolve POI)
    private struct TappableMapView: UIViewRepresentable {
        let center: CLLocationCoordinate2D
        let title: String?
        var zoomInTrigger: Int = 0
        var zoomOutTrigger: Int = 0
        var onTap: (CLLocationCoordinate2D, MKCoordinateRegion) -> Void
        var onMapFeatureTap: (MKMapFeatureAnnotation, MKCoordinateRegion, @escaping () -> Void) -> Void

        /// `spanScale` multiplies span: smaller than 1 zooms in, larger than 1 zooms out.
        private static func applyZoom(_ mapView: MKMapView, spanScale: CGFloat) {
            var region = mapView.region
            let lat = region.span.latitudeDelta * spanScale
            let lon = region.span.longitudeDelta * spanScale
            let minDelta: CLLocationDegrees = 0.0003
            let maxDelta: CLLocationDegrees = 120
            region.span.latitudeDelta = min(max(lat, minDelta), maxDelta)
            region.span.longitudeDelta = min(max(lon, minDelta), maxDelta)
            mapView.setRegion(region, animated: true)
        }

        func makeUIView(context: Context) -> MKMapView {
            let map = MKMapView()
            map.delegate = context.coordinator
            map.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 350,
                longitudinalMeters: 350
            )
            map.mapType = .standard
            map.showsUserLocation = false
            map.selectableMapFeatures = [.pointsOfInterest]
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
                if pin.coordinate.latitude != center.latitude || pin.coordinate.longitude != center.longitude {
                    UIView.animate(withDuration: 0.25) {
                        pin.coordinate = center
                    }
                }
                pin.title = title
                if let title = title, !title.isEmpty {
                    mapView.selectAnnotation(pin, animated: true)
                } else {
                    mapView.deselectAnnotation(pin, animated: true)
                }
            }

            if zoomInTrigger != context.coordinator.lastZoomInTrigger {
                context.coordinator.lastZoomInTrigger = zoomInTrigger
                Self.applyZoom(mapView, spanScale: 0.5)
            }
            if zoomOutTrigger != context.coordinator.lastZoomOutTrigger {
                context.coordinator.lastZoomOutTrigger = zoomOutTrigger
                Self.applyZoom(mapView, spanScale: 2.0)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, MKMapViewDelegate {
            let parent: TappableMapView
            var lastZoomInTrigger: Int = 0
            var lastZoomOutTrigger: Int = 0
            /// When the user taps a rendered POI, `didSelect(MKMapFeatureAnnotation)` runs; we cancel this so we do not
            /// also run proximity-based `MKLocalPointsOfInterestRequest` (which can pick a different sub-POI).
            private var pendingBareMapTap: DispatchWorkItem?

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
                debugPrint("[POI] tap at point=\(point), coordinate=\(coordinate.latitude),\(coordinate.longitude) -> scheduling deferred onTap")
                pendingBareMapTap?.cancel()
                let region = mapView.region
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    debugPrint("[POI] deferred bare-map tap → onTap")
                    self.parent.onTap(coordinate, region)
                }
                pendingBareMapTap = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            }

            func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
                if let feature = annotation as? MKMapFeatureAnnotation {
                    guard feature.featureType == .pointOfInterest else {
                        mapView.deselectAnnotation(annotation, animated: false)
                        debugPrint("[POI] didSelect non-POI map feature, ignored")
                        return
                    }
                    pendingBareMapTap?.cancel()
                    pendingBareMapTap = nil
                    debugPrint("[POI] didSelect MKMapFeatureAnnotation → onMapFeatureTap (selection cleared after resolve)")
                    let endSelection = { [weak mapView] in
                        guard let mapView else { return }
                        mapView.deselectAnnotation(feature, animated: false)
                    }
                    parent.onMapFeatureTap(feature, mapView.region, endSelection)
                    return
                }
                if annotation is MKPointAnnotation {
                    pendingBareMapTap?.cancel()
                    pendingBareMapTap = nil
                }
            }

            func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
                guard annotation is MKPointAnnotation else { return nil }
                let id = "Pin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "mappin.circle.fill")
                view.canShowCallout = true
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
                                pickedFromAutocomplete = true
                                searchViewModel.suggestions = []
                                Task {
                                    let cat = await searchViewModel.fetchCategory(for: suggestion)
                                    debugPrint("[Category] autocomplete picked '\(suggestion.title)' → category=\(cat ?? "nil")")
                                    selectedCategory = cat
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

// MARK: - Strip photo full-screen preview

private struct EditPlaceStripPhotoFullScreenViewer: View {
    let photos: [RecapPhoto]
    let initialPhoto: RecapPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var selection: RecapPhoto.ID

    init(photos: [RecapPhoto], initialPhoto: RecapPhoto) {
        self.photos = photos
        self.initialPhoto = initialPhoto
        _selection = State(initialValue: initialPhoto.id)
    }

    private static let previewPixelSize = CGSize(width: 1400, height: 1400)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    RecapPhotoThumbnail(
                        photo: photo,
                        cornerRadius: 0,
                        showIcon: false,
                        targetSize: Self.previewPixelSize
                    )
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            // Done button — top-trailing, floating above the photo
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.trailing, 16)
            }
            .padding(.top, 56) // below status bar / Dynamic Island
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    EditPlaceStopNameSheet(
        placeTitle: .constant("Iceland Ring Road"),
        initialPlaceSubtitle: "Reykjavík, Iceland",
        initialPlaceCategory: nil,
        location: CLLocationCoordinate2D(latitude: 64.15, longitude: -21.95),
        onSave: { _, _, _, _ in }
    )
}
