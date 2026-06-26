import MapKit
import Photos
import SwiftUI
import UIKit

enum PlacesVisitedPlaceGrid {
    static let columns: [GridItem] = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top)
    ]

    /// Toolbar row in select mode (56pt buttons + vertical padding).
    static let selectModeBottomBarHeight: CGFloat = 76

    /// Pairs places for a fixed 2-column eager layout (avoids LazyVGrid stale selection chrome).
    static func pairedRows<T>(_ items: [T]) -> [[T]] {
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: 2).map { index in
            if index + 1 < items.count {
                return [items[index], items[index + 1]]
            }
            return [items[index]]
        }
    }
}

/// Stable identity for a 2-column select-mode row.
private struct PlaceSelectRow: Identifiable {
    let id: String
    let places: [VisitedPlaceSummary]

    init(places: [VisitedPlaceSummary]) {
        self.places = places
        self.id = places.map(\.placeId).joined(separator: "|")
    }
}

/// Hides map + search inset while the place viewer or share studio is full-screen.
private struct PlacesVisitedBottomChromeInset<Chrome: View>: ViewModifier {
    let isHidden: Bool
    @ViewBuilder let chrome: () -> Chrome

    func body(content: Content) -> some View {
        if isHidden {
            content
        } else {
            content.homeTabFloatingSearchInset(chrome: chrome)
        }
    }
}

/// Dismisses the search field when active — only installed while focused so it cannot steal grid taps.
private struct PlacesVisitedSearchDismissTapModifier: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if isActive {
            content.onTapGesture(perform: onDismiss)
        } else {
            content
        }
    }
}

// MARK: - Agent debug logging (session 6af5cd)
private enum PlacesVisitedAgentDebug {
    private static let ingestURL = URL(string: "http://127.0.0.1:7720/ingest/6788f1c9-d047-4e46-82ba-585a06955b83")!

    static func log(hypothesisId: String, location: String, message: String, data: [String: String] = [:], runId: String = "pre-fix") {
        // #region agent log
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let dataPairs = data.map { "\"\(esc($0.key))\":\"\(esc($0.value))\"" }.joined(separator: ",")
        let line = "{\"sessionId\":\"6af5cd\",\"runId\":\"\(esc(runId))\",\"timestamp\":\(ts),\"location\":\"\(esc(location))\",\"message\":\"\(esc(message))\",\"hypothesisId\":\"\(hypothesisId)\",\"data\":{\(dataPairs)}}"
        guard let body = line.data(using: .utf8) else { return }
        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("6af5cd", forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
        #if DEBUG
        print("[AgentDebug6af5cd] \(line)")
        #endif
        // #endregion
    }
}

/// Select-mode checkmark overlay (drawn outside the card for reliable SwiftUI updates).
private struct PlacesSelectModeChrome: View {
    let isSelected: Bool

    var body: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                }
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Unselected filter chip fill: `systemGray5` blended ~15% toward white (lighter tone).
private func filterChipUnselectedFill() -> Color {
    Color(uiColor: UIColor { traits in
        let base = UIColor.systemGray5.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return base }
        let t: CGFloat = 0.15
        return UIColor(red: r * (1 - t) + t, green: g * (1 - t) + t, blue: b * (1 - t) + t, alpha: a)
    })
}

// MARK: - Standalone full-screen Places Visited (from home icon)
struct PlacesVisitedStandaloneView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    @Binding var suppressHomeBottomNav: Bool
    var onDismiss: () -> Void

    var onShowSettings: (() -> Void)? = nil

    @State private var searchText: String = ""
    @State private var showPlacesMap: Bool = false

    private let backgroundBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        PlacesVisitedView(
            searchText: $searchText,
            showPlacesMap: $showPlacesMap,
            selectedCreatedRecap: $selectedCreatedRecap,
            initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
            suppressHomeBottomNav: $suppressHomeBottomNav,
            standaloneOnDismiss: onDismiss,
            onShowSettings: onShowSettings
        )
        .background(backgroundBlue.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("My Places")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .homeSettingsToolbar(onShowSettings: onShowSettings)
    }
}

struct PlacesVisitedView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @ObservedObject private var everydayStore = EverydayMomentsStore.shared
    @ObservedObject private var hiddenMyPlacesStore = HiddenMyPlacesStore.shared

    @Binding var searchText: String
    @Binding var showPlacesMap: Bool
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    @Binding var suppressHomeBottomNav: Bool
    /// When set (standalone presentation), shows a leading dismiss control in the navigation bar.
    var standaloneOnDismiss: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil

    @State private var selectedYear: Int? = nil
    @State private var selectedCountry: String? = nil
    @State private var selectedCategory: String? = nil

    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var openCategoryPickerWhenPlaceModalOpens: Bool = false
    @State private var revealNavDuringModalDismiss: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchActive: Bool = false
    @State private var scrollRestorationPlaceId: String?

    @State private var isSelectMode = false
    @State private var selectedPlaceKeys: Set<String> = []
    @State private var showHidePlacesConfirmation = false
    @State private var showCreateBlogFromSelectionAlert = false
    @State private var showHiddenPlacesSheet = false
    @State private var placesDownloadToast: String?

    @State private var showShareYourPlacesSheet = false
    @State private var showPlacesShareTooManyAlert = false
    @State private var placesShareBlockedPlaceCount = 0
    @State private var placesShareDraft: RecapBlogDetail?
    @State private var showPlacesSocialStudio = false
    @State private var showPlacesVideoExport = false
    @State private var placesVideoShareURL: URL?
    @State private var showPlacesVideoShareSheet = false
    @State private var showPromoteToBlogConfirmation = false
    @State private var placePendingPromote: VisitedPlaceSummary?

    private let horizontalPadding: CGFloat = 16

    private var visiblePlaces: [VisitedPlaceSummary] {
        createdRecapStore.visitedPlaces.filter { !hiddenMyPlacesStore.isHidden($0.placeId) }
    }

    private var selectedPlaces: [VisitedPlaceSummary] {
        visiblePlaces.filter { selectedPlaceKeys.contains(placeSelectionKey(for: $0)) }
    }

    /// Stable across `placeId` churn (everyday cluster rebuilds, blog `local_` → `cloud_` migration).
    private func placeSelectionKey(for place: VisitedPlaceSummary) -> String {
        let photoIds = place.photos.map(\.id.uuidString).sorted()
        guard !photoIds.isEmpty else { return "place:\(place.placeId)" }
        return "photos:\(photoIds.joined(separator: ","))"
    }

    private var availableYears: [Int] {
        Array(Set(visiblePlaces.map(\.year))).sorted(by: >)
    }

    private var availableCountries: [String] {
        Array(Set(visiblePlaces.map(\.country))).sorted()
    }

    private var availableCategories: [String] {
        let placesForYear = visiblePlaces.filter { place in
            guard let y = selectedYear else { return true }
            return place.year == y
        }

        let allRaws = placesForYear.compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let dataRaws = Set(allRaws.filter { !$0.isEmpty })
        let includeOthers = placesForYear.contains {
            ($0.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var frequencies: [String: Int] = [:]
        for raw in allRaws where !raw.isEmpty { frequencies[raw, default: 0] += 1 }

        let cats = PlacePOICategoryCatalog.categoryRawsAppearingInDataForFilters(dataRaws: dataRaws, includeOthers: false)
        let sorted = cats.sorted { a, b in
            let fa = frequencies[a] ?? 0
            let fb = frequencies[b] ?? 0
            if fa != fb { return fa > fb }
            return PlacePOICategoryPresentation.displayLabel(forRaw: a)
                .localizedStandardCompare(PlacePOICategoryPresentation.displayLabel(forRaw: b)) == .orderedAscending
        }
        return includeOthers ? sorted + ["Others"] : sorted
    }

    private var filteredPlaces: [VisitedPlaceSummary] {
        visiblePlaces
            .filter { place in
                if let y = selectedYear, place.year != y { return false }
                if let c = selectedCountry {
                    let lhs = place.country.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }
                if let cat = selectedCategory {
                    let rhs = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lhsRaw = (place.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if rhs.caseInsensitiveCompare("Others") == .orderedSame {
                        if !lhsRaw.isEmpty { return false }
                    } else if lhsRaw.caseInsensitiveCompare(rhs) != .orderedSame {
                        return false
                    }
                }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let q = query.lowercased()
                    let name = place.displayName.lowercased()
                    let city = (place.cityDisplay ?? "").lowercased()
                    let country = place.country.lowercased()
                    if !(name.contains(q) || city.contains(q) || country.contains(q)) { return false }
                }

                return true
            }
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    private var hasActivePlaceFilters: Bool {
        selectedYear != nil || selectedCountry != nil || selectedCategory != nil
    }

    @ViewBuilder
    private var placesScrollEmptyState: some View {
        VStack(spacing: 10) {
            Text(visiblePlaces.isEmpty ? "No places yet" : "No matches")
                .font(.title3)
                .fontWeight(.semibold)

            Text(visiblePlaces.isEmpty
                 ? (createdRecapStore.visitedPlaces.isEmpty
                    ? "Capture everyday moments with the camera — they appear here automatically."
                    : "All places are hidden. Tap Manage to restore them.")
                 : "Try clearing filters.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            if hiddenMyPlacesStore.hiddenCount > 0 && visiblePlaces.isEmpty {
                Button("Show hidden places") {
                    showHiddenPlacesSheet = true
                }
                .buttonStyle(.borderedProminent)
            }

            if !visiblePlaces.isEmpty && hasActivePlaceFilters {
                Button("Clear filters") {
                    selectedYear = nil
                    selectedCountry = nil
                    selectedCategory = nil
                    searchText = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func togglePlaceSelection(selectionKey: String, place: VisitedPlaceSummary, wasSelected: Bool) {
        if wasSelected {
            selectedPlaceKeys = selectedPlaceKeys.subtracting([selectionKey])
        } else {
            selectedPlaceKeys = selectedPlaceKeys.union([selectionKey])
        }
        let nowSelected = selectedPlaceKeys.contains(selectionKey)
        // #region agent log
        PlacesVisitedAgentDebug.log(
            hypothesisId: "H",
            location: "PlacesVisitedView:togglePlaceSelection",
            message: "place_tapped",
            data: [
                "selectionKey": selectionKey,
                "placeId": place.placeId,
                "selectionKeyInSet": "\(nowSelected)",
                "displayName": place.displayName,
                "isEverydayOnly": "\(place.isEverydayOnly)",
                "wasSelected": "\(wasSelected)",
                "nowSelected": "\(nowSelected)",
                "selectedCount": "\(selectedPlaceKeys.count)"
            ],
            runId: "post-fix-v4"
        )
        // #endregion
    }

    @ViewBuilder
    private func placesSelectModeGrid(for places: [VisitedPlaceSummary]) -> some View {
        let rowModels = PlacesVisitedPlaceGrid.pairedRows(places).map { row in
            PlaceSelectRow(places: row)
        }
        // #region agent log
        let _ = {
            let rowIds = rowModels.map(\.id)
            let dupeRowIds = Dictionary(grouping: rowIds, by: { $0 }).filter { $1.count > 1 }.map(\.key)
            if !dupeRowIds.isEmpty {
                PlacesVisitedAgentDebug.log(
                    hypothesisId: "E",
                    location: "placesSelectModeGrid",
                    message: "duplicate_row_ids",
                    data: ["dupeRowIds": dupeRowIds.joined(separator: ";"), "placeCount": "\(places.count)"]
                )
            }
        }()
        // #endregion
        VStack(spacing: 12) {
            ForEach(rowModels) { rowModel in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rowModel.places) { place in
                        let selectionKey = placeSelectionKey(for: place)
                        let isSelected = selectedPlaceKeys.contains(selectionKey)
                        ZStack(alignment: .bottomTrailing) {
                            PlaceVisitedCard(
                                place: place,
                                isSelectMode: true,
                                isSelected: isSelected
                            )
                            PlacesSelectModeChrome(isSelected: isSelected)
                                .padding(10)
                        }
                        .overlay {
                            RoundedRectangle(appChromeBaseRadius: 18, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.blue : Color.primary.opacity(0.06),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            togglePlaceSelection(
                                selectionKey: selectionKey,
                                place: place,
                                wasSelected: isSelected
                            )
                        }
                        .accessibilityLabel(place.displayName)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .frame(maxWidth: .infinity)
                    }
                    if rowModel.places.count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func placesYearMonthList(for places: [VisitedPlaceSummary]) -> some View {
        let yearGroups = groupedByYearThenMonth(places)
        // Eager VStack avoids LazyVStack + LazyVGrid hit-testing glitches on edge rows in select mode.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(yearGroups, id: \.year) { yearGroup in
                Text(String(yearGroup.year))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(yearGroup.months, id: \.month) { monthGroup in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(monthGroup.monthName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 6)

                        if isSelectMode {
                            placesSelectModeGrid(for: monthGroup.places)
                        } else {
                            LazyVGrid(columns: PlacesVisitedPlaceGrid.columns, spacing: 12) {
                                ForEach(monthGroup.places) { place in
                                    PlaceVisitedCard(
                                        place: place,
                                        onTap: {
                                            scrollRestorationPlaceId = place.id
                                            openCategoryPickerWhenPlaceModalOpens = false
                                            selectedPlaceForModal = place
                                        },
                                        onAddCategoryTap: {
                                            scrollRestorationPlaceId = place.id
                                            openCategoryPickerWhenPlaceModalOpens = true
                                            selectedPlaceForModal = place
                                        }
                                    )
                                    .id(place.id)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var placesScrollContent: some View {
        if filteredPlaces.isEmpty {
            placesScrollEmptyState
        } else {
            placesYearMonthList(for: filteredPlaces)
        }
    }

    @ViewBuilder
    private var placesMainZStack: some View {
        ZStack(alignment: .bottom) {
            placesListColumn
            placesSelectedPlaceOverlay
            if let toast = placesDownloadToast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, isSelectMode
                        ? PlacesVisitedPlaceGrid.selectModeBottomBarHeight + 12
                        : 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placesListColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isSelectMode {
                filterBar
                    .padding(.horizontal, horizontalPadding)
            }
            placesScrollReader
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(.large)
    }

    private var placesScrollReader: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    placesScrollContent
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, isSelectMode ? 16 : 0)
                .padding(.bottom, isSelectMode ? PlacesVisitedPlaceGrid.selectModeBottomBarHeight + 24 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollClipDisabled(isSelectMode)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectMode && !filteredPlaces.isEmpty {
                    placesSelectModeBottomBar
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: selectedPlaceForModal) { _, newValue in
                restoreScrollAfterPlaceModalDismiss(newValue: newValue, scrollProxy: scrollProxy)
            }
        }
    }

    private func restoreScrollAfterPlaceModalDismiss(
        newValue: VisitedPlaceSummary?,
        scrollProxy: ScrollViewProxy
    ) {
        guard newValue == nil, let id = scrollRestorationPlaceId else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            scrollProxy.scrollTo(id, anchor: .center)
        }
    }

    @ViewBuilder
    private var placesSelectedPlaceOverlay: some View {
        if let place = selectedPlaceForModal {
            placeModalView(for: place)
        }
    }

    @ViewBuilder
    private func placeModalView(for place: VisitedPlaceSummary) -> some View {
        PlaceVisitedPhotoModalWrapper(
            place: place,
            presentCategoryPickerInitially: openCategoryPickerWhenPlaceModalOpens,
            onDismiss: {
                selectedPlaceForModal = nil
                openCategoryPickerWhenPlaceModalOpens = false
                revealNavDuringModalDismiss = false
            },
            onDismissSlideBegan: { revealNavDuringModalDismiss = true },
            onViewBlog: { openRelatedBlog(for: place) },
            onCreateTripBlog: place.isEverydayOnly ? {
                placePendingPromote = place
                showPromoteToBlogConfirmation = true
            } : nil
        )
        .environmentObject(createdRecapStore)
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .zIndex(200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
    }

    private func openRelatedBlog(for place: VisitedPlaceSummary) {
        guard let ref = place.relatedBlogs.first,
              let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == ref.blogId }) else { return }
        openCategoryPickerWhenPlaceModalOpens = false
        initialScrollToStopIdForRecap = ref.placeStopId
        selectedCreatedRecap = recap
    }

    private var placesChromeLayer: some View {
        placesMainZStack
            .modifier(PlacesVisitedBottomChromeInset(isHidden: shouldHidePlacesVisitedNavigationBar || isSelectMode) {
                placesBottomChrome
            })
            .alert("Create trip blog?", isPresented: $showCreateBlogFromSelectionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Create Blog") {
                    createTripBlogFromSelectedPlaces()
                }
            } message: {
                Text("Selected places will become a trip blog in My Blogs.")
            }
            .alert("Hide selected places?", isPresented: $showHidePlacesConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Hide", role: .destructive) {
                    hideSelectedPlaces()
                }
            } message: {
                Text(selectedPlaceKeys.count == 1
                     ? "This place will be hidden from My Places. You can restore it anytime from Manage."
                     : "These places will be hidden from My Places. You can restore them anytime from Manage.")
            }
            .alert("Create trip blog?", isPresented: $showPromoteToBlogConfirmation) {
                Button("Cancel", role: .cancel) { placePendingPromote = nil }
                Button("Create Blog") {
                    if let place = placePendingPromote {
                        _ = createdRecapStore.createTripBlogFromEverydayPhotos(
                            place.photos,
                            preferredTitle: place.displayName
                        )
                    }
                    placePendingPromote = nil
                    selectedPlaceForModal = nil
                }
            } message: {
                Text("These everyday moments will become a trip blog in My Blogs.")
            }
            .modifier(PlacesVisitedSearchDismissTapModifier(isActive: isSearchFocused) {
                isSearchFocused = false
                isSearchActive = false
            })
            .animation(.easeInOut(duration: 0.38), value: selectedPlaceForModal?.id)
    }

    private var placesShareSheetsLayer: some View {
        placesChromeLayer
            .sheet(isPresented: $showHiddenPlacesSheet) {
                HiddenMyPlacesSheet()
                    .environmentObject(createdRecapStore)
            }
            .sheet(isPresented: $showShareYourPlacesSheet) {
                ShareYourPlacesSheet(
                    onPickDestination: { destination in
                        showShareYourPlacesSheet = false
                        let placeCount = selectedPlaces.count
                        let cap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
                        if placeCount > cap {
                            placesShareBlockedPlaceCount = placeCount
                            showPlacesShareTooManyAlert = true
                            return
                        }
                        beginPlacesShare(destination: destination)
                    },
                    onDismiss: { showShareYourPlacesSheet = false }
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
            .alert("Too many places to share", isPresented: $showPlacesShareTooManyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(placesShareTooManyAlertMessage)
            }
            .sheet(isPresented: $showPlacesVideoExport) {
                if let draft = placesShareDraft {
                    BlogVideoExportOptionsSheet(
                        draft: draft,
                        isPlacesCollectionExport: true,
                        onShare: { url in
                            placesVideoShareURL = url
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                showPlacesVideoShareSheet = true
                            }
                        },
                        onRequestReelCapture: {}
                    )
                }
            }
            .sheet(isPresented: $showPlacesVideoShareSheet) {
                if let url = placesVideoShareURL {
                    ShareSheet(items: [url])
                }
            }
            .overlay {
                if showPlacesSocialStudio, let draft = placesShareDraft {
                    SocialPostStudioSheet(
                        blog: draft,
                        opensInEditMode: true,
                        placesOnlyMode: true,
                        onDismissFromParent: {
                            showPlacesSocialStudio = false
                            placesShareDraft = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(300)
                }
            }
    }

    var body: some View {
        placesShareSheetsLayer
        .navigationDestination(isPresented: $showPlacesMap) {
            PlacesVisitedMapView(
                selectedYear: $selectedYear,
                selectedCountry: $selectedCountry,
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                selectedCreatedRecap: $selectedCreatedRecap,
                initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
                suppressHomeBottomNav: $suppressHomeBottomNav
            )
            .environmentObject(createdRecapStore)
        }
        .toolbar { placesToolbarContent }
        .toolbar(shouldHidePlacesVisitedNavigationBar ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground(shouldHidePlacesVisitedNavigationBar ? .hidden : .automatic, for: .navigationBar)
        .onChange(of: selectedYear) { _, _ in
            if let selectedCategory,
               !availableCategories.contains(where: { $0.caseInsensitiveCompare(selectedCategory) == .orderedSame }) {
                self.selectedCategory = nil
            }
        }
        .onChange(of: selectedPlaceForModal?.id) { _, _ in syncHomeBottomNavSuppression() }
        .onChange(of: revealNavDuringModalDismiss) { _, _ in syncHomeBottomNavSuppression() }
        .onChange(of: showPlacesSocialStudio) { _, _ in syncHomeBottomNavSuppression() }
        .onChange(of: isSelectMode) { _, active in
            if active {
                isSearchFocused = false
                isSearchActive = false
                // #region agent log
                let ids = filteredPlaces.map(\.placeId)
                let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.map(\.key)
                let keys = filteredPlaces.map { placeSelectionKey(for: $0) }
                let dupeKeys = Dictionary(grouping: keys, by: { $0 }).filter { $1.count > 1 }.map(\.key)
                PlacesVisitedAgentDebug.log(
                    hypothesisId: "A",
                    location: "PlacesVisitedView:isSelectMode",
                    message: "select_mode_entered",
                    data: [
                        "placeCount": "\(ids.count)",
                        "uniqueCount": "\(Set(ids).count)",
                        "duplicateIds": dupes.isEmpty ? "none" : dupes.joined(separator: ";"),
                        "duplicateSelectionKeys": dupeKeys.isEmpty ? "none" : dupeKeys.joined(separator: ";")
                    ],
                    runId: "post-fix-v4"
                )
                // #endregion
            }
            syncHomeBottomNavSuppression()
        }
        .onAppear { syncHomeBottomNavSuppression() }
        .onDisappear { suppressHomeBottomNav = false }
    }

    @ToolbarContentBuilder
    private var placesToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if selectedYear != nil || selectedCountry != nil || selectedCategory != nil {
                Button("Reset") {
                    selectedYear = nil
                    selectedCountry = nil
                    selectedCategory = nil
                }
                .foregroundStyle(.primary)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isSearchActive, !filteredPlaces.isEmpty {
                if isSelectMode {
                    Button("Done") {
                        exitPlacesSelectMode()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                } else {
                    if hiddenMyPlacesStore.hiddenCount > 0 {
                        Menu {
                            Button {
                                isSelectMode = true
                            } label: {
                                Label("Select Places", systemImage: "checkmark.circle")
                            }
                            Button {
                                showHiddenPlacesSheet = true
                            } label: {
                                Label("Hidden Places (\(hiddenMyPlacesStore.hiddenCount))", systemImage: "eye.slash")
                            }
                        } label: {
                            Image(systemName: "checklist")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Manage places")
                    } else {
                        Button {
                            isSelectMode = true
                        } label: {
                            Image(systemName: "checklist")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Manage places")
                    }
                }
            }
            if isSearchActive {
                Button("Done") {
                    searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            } else {
                Menu {
                    Button("All Countries") { selectedCountry = nil }
                    ForEach(availableCountries, id: \.self) { c in
                        Button(c) { selectedCountry = c }
                    }
                } label: {
                    Image(systemName: selectedCountry == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    /// Hide My Places chrome while place viewer or Carousel Studio is full-screen (matches blog recap during share).
    private var shouldHidePlacesVisitedNavigationBar: Bool {
        (selectedPlaceForModal != nil && !revealNavDuringModalDismiss) || showPlacesSocialStudio
    }

    private func syncHomeBottomNavSuppression() {
        suppressHomeBottomNav = shouldHidePlacesVisitedNavigationBar || isSelectMode
    }

    private var placesShareTooManyAlertMessage: String {
        let cap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        return "You have \(placesShareBlockedPlaceCount) places in your current view. Sharing supports up to \(cap) places at a time.\n\nUse the year, country, category, or search filters to narrow your list, then try sharing again."
    }

    /// Matches blog share: pick a format, then open the export UI directly. Uses current My Places filters as the place set; trim slides in Social Post Studio.

    private func beginPlacesShare(destination: PlacesShareDestination) {
        let places = isSelectMode ? selectedPlaces : filteredPlaces
        guard !places.isEmpty else { return }
        guard let draft = PlacesShareDraftBuilder.makeShareDraft(selectedPlaces: places) else { return }
        placesShareDraft = draft
        switch destination {
        case .socialCarousel, .pdf:
            showPlacesSocialStudio = true
        case .video:
            showPlacesVideoExport = true
        }
        if isSelectMode {
            exitPlacesSelectMode()
        }
    }

    private var placesSelectModeBottomBar: some View {
        HStack {
            Button {
                saveSelectedPlacesToPhotoLibrary()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedPlaceKeys.isEmpty ? .gray : .primary)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            }
            .disabled(selectedPlaceKeys.isEmpty)
            .accessibilityLabel("Save selected photos to Photos")

            Button {
                showCreateBlogFromSelectionAlert = true
            } label: {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selectedPlaceKeys.isEmpty ? .gray : .primary)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            }
            .disabled(selectedPlaceKeys.isEmpty)
            .accessibilityLabel("Create trip blog from selection")

            Menu {
                Button {
                    showShareYourPlacesSheet = true
                } label: {
                    Label("Share Places", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedPlaceKeys.isEmpty)
                if hiddenMyPlacesStore.hiddenCount > 0 {
                    Divider()
                    Button {
                        showHiddenPlacesSheet = true
                    } label: {
                        Label("Hidden Places (\(hiddenMyPlacesStore.hiddenCount))", systemImage: "eye.slash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            }
            .accessibilityLabel("More actions")

            Spacer()

            Text("\(selectedPlaceKeys.count) Selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showHidePlacesConfirmation = true
            } label: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedPlaceKeys.isEmpty ? .gray : .orange)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            }
            .disabled(selectedPlaceKeys.isEmpty)
            .accessibilityLabel("Hide selected places")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 4)
    }

    private func exitPlacesSelectMode() {
        isSelectMode = false
        selectedPlaceKeys = []
    }

    private func hideSelectedPlaces() {
        hiddenMyPlacesStore.hide(placeIds: Set(selectedPlaces.map(\.placeId)))
        exitPlacesSelectMode()
    }

    private func createTripBlogFromSelectedPlaces() {
        let photos = selectedPlaces.flatMap(\.photos)
        guard !photos.isEmpty else { return }
        let title = selectedPlaces.count == 1 ? selectedPlaces[0].displayName : nil
        _ = createdRecapStore.createTripBlogFromEverydayPhotos(photos, preferredTitle: title)
        exitPlacesSelectMode()
    }

    private func saveSelectedPlacesToPhotoLibrary() {
        let captureIds: [UUID] = selectedPlaces.flatMap(\.photos).compactMap { photo in
            guard let lid = photo.localIdentifier else { return nil }
            return AppCapturePhotoService.uuid(from: lid)
        }
        guard !captureIds.isEmpty else {
            placesDownloadToast = "No downloadable photos in selection"
            schedulePlacesDownloadToastDismiss()
            return
        }

        Task {
            var auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if auth == .notDetermined {
                auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
            guard auth == .authorized || auth == .limited else {
                await MainActor.run {
                    placesDownloadToast = "Allow Photos access to save"
                    schedulePlacesDownloadToastDismiss()
                }
                return
            }

            AppCapturePhotoService.shared.saveCapturesToPhotoLibrary(captureIds: captureIds) { count, success in
                if success, count > 0 {
                    placesDownloadToast = "\(count) photo\(count == 1 ? "" : "s") saved to Photos"
                } else {
                    placesDownloadToast = "Couldn't save to Photos"
                }
                schedulePlacesDownloadToastDismiss()
            }
        }
    }

    private func schedulePlacesDownloadToastDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            placesDownloadToast = nil
        }
    }

    // MARK: - Year / Month grouping helpers

    private struct MonthGroup {
        let month: Int          // 1–12
        let monthName: String   // e.g. "March"
        let places: [VisitedPlaceSummary]
    }

    private struct YearGroup {
        let year: Int
        let months: [MonthGroup]
    }

    private func groupedByYearThenMonth(_ places: [VisitedPlaceSummary]) -> [YearGroup] {
        let cal = Calendar.current
        // Group by year
        let byYear = Dictionary(grouping: places) { cal.component(.year, from: $0.latestVisitDate) }
        return byYear.keys.sorted(by: >).map { year in
            let yearPlaces = byYear[year]!
            // Group by month within the year
            let byMonth = Dictionary(grouping: yearPlaces) { cal.component(.month, from: $0.latestVisitDate) }
            let monthGroups = byMonth.keys.sorted(by: >).map { month -> MonthGroup in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                let name: String = {
                    var comps = DateComponents(); comps.month = month; comps.year = year
                    let date = cal.date(from: comps) ?? Date()
                    return formatter.string(from: date)
                }()
                return MonthGroup(
                    month: month,
                    monthName: name,
                    places: byMonth[month]!.sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
                )
            }
            return YearGroup(year: year, months: monthGroups)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Year")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(label: "All", isSelected: selectedYear == nil) {
                            selectedYear = nil
                        }
                        ForEach(availableYears, id: \.self) { y in
                            chip(label: String(y), isSelected: selectedYear == y) {
                                selectedYear = (selectedYear == y) ? nil : y
                            }
                        }
                    }
                }
            }

            if !availableCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(label: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(availableCategories, id: \.self) { cat in
                                placesVisitedCategoryChip(raw: cat, isSelected: selectedCategory == cat) {
                                    selectedCategory = (selectedCategory == cat) ? nil : cat
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var placesBottomChrome: some View {
        HomeTabFloatingSearchChrome(
            onMapTap: {
                isSearchFocused = false
                showPlacesMap = true
            },
            searchContent: { placesSearchField }
        )
    }

    private var placesSearchField: some View {
        HomeTabSearchFieldRow(
            placeholder: "Search place, city, or country",
            text: $searchText,
            focus: $isSearchFocused
        ) {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(HomeChromeMetrics.homeSearchFieldFont)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .onTapGesture { isSearchActive = true }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : filterChipUnselectedFill())
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func placesVisitedCategoryChip(raw: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        let label = PlacePOICategoryPresentation.displayLabel(forRaw: raw)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.white : p.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? p.color : p.color.opacity(0.14))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(p.color.opacity(isSelected ? 0.25 : 0.45), lineWidth: isSelected ? 0 : 1)
            )
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

}


/// Stateful wrapper around PlacePhotoModalView for the Places Visited full-screen overlay.
/// Holds live per-photo caption state so the binding getter always reflects the latest value,
/// and calls updatePhotoCaption on the store whenever a caption is committed.
struct PlaceVisitedPhotoModalWrapper: View {
    @EnvironmentObject private var store: CreatedRecapBlogStore

    let place: VisitedPlaceSummary
    var presentCategoryPickerInitially: Bool = false
    var onDismiss: () -> Void
    var onDismissSlideBegan: (() -> Void)? = nil
    var onViewBlog: (() -> Void)?
    var onCreateTripBlog: (() -> Void)? = nil

    /// Live caption state keyed by photo ID. Seeded from place.photos on appear.
    @State private var liveCaptions: [UUID: String] = [:]
    /// Live place name — updated when user edits via the kebab 'Edit Place Name' menu item.
    @State private var livePlaceTitle: String = ""

    var body: some View {
        // Look up live photos from the store so we always reflect the current included-photo state,
        // even if isIncluded flags changed after this sheet was first presented.
        let photos = store.visitedPlaces.first { $0.placeId == place.placeId }?.photos ?? place.photos
        if let initialPhotoId = photos.first?.id {
            ZStack(alignment: .topTrailing) {
            PlacePhotoModalView(
                placeTitle: Binding(
                    get: { livePlaceTitle.isEmpty ? place.displayName : livePlaceTitle },
                    set: { newName in
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        livePlaceTitle = trimmed
                        // Name-only fallback; full update (with category/coord/subtitle) handled by onSavePlaceName.
                        store.updatePlaceStopName(photoId: initialPhotoId, newName: trimmed)
                    }
                ),
                placeSubtitle: place.cityDisplay ?? place.country,
                initialPlaceCategory: place.categoryRawValue,
                photos: photos,
                initialPhotoId: initialPhotoId,
                stopDigitizedTime: nil,
                blogIsEditMode: false,
                showAssetTimeMetadata: false,
                presentation: .fullscreen(source: .placesVisited),
                presentPlaceCategoryPickerOnAppear: presentCategoryPickerInitially,
                photoCaption: { photoId in
                    Binding(
                        get: { liveCaptions[photoId] ?? photos.first(where: { $0.id == photoId })?.caption ?? "" },
                        set: { newValue in
                            liveCaptions[photoId] = newValue
                            store.updatePhotoCaption(photoId: photoId, newCaption: newValue)
                        }
                    )
                },
                onDismiss: onDismiss,
                onDismissSlideBegan: onDismissSlideBegan,
                onViewBlog: place.relatedBlogs.isEmpty ? nil : onViewBlog,
                onPhotoCaptionManuallyEdited: { photoId in
                    // updatePhotoCaption already called via the binding setter
                },
                onRemovePhoto: { photoId in
                    store.removePhotoFromBlog(photoId: photoId)
                    if photos.count <= 1 {
                        onDismiss()
                    }
                },
                onSavePlaceName: { newName, category, coord, subtitleLine in
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    livePlaceTitle = trimmed
                    store.updatePlaceStopFromPlacesVisited(
                        photoId: initialPhotoId,
                        newName: trimmed,
                        category: category,
                        coordinate: coord,
                        subtitle: subtitleLine
                    )
                },
                onSavePlaceCategory: { newCategory in
                    store.updatePlaceStopCategoryFromPlacesVisited(photoId: initialPhotoId, category: newCategory)
                }
            )
            if let onCreateTripBlog {
                Button(action: onCreateTripBlog) {
                    Label("Create Trip Blog", systemImage: "book.closed.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.9), in: Capsule())
                }
                .padding(.top, 56)
                .padding(.trailing, 16)
            }
            }
        } else {
            Color.clear.onAppear { onDismiss() }
        }
    }
}

struct PlaceVisitedCard: View {
    let place: VisitedPlaceSummary
    var isSelectMode: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    var onAddCategoryTap: (() -> Void)? = nil

    private static let heroHeight: CGFloat = 108
    private static let titleBlockHeight: CGFloat = 44
    private static let categoryRowHeight: CGFloat = 28
    private static let cardPadding: CGFloat = 12
    /// Same on every card so 2-column rows stay aligned (hero + text + category are fixed).
    private static var layoutHeight: CGFloat {
        cardPadding * 2 + heroHeight + 10 + titleBlockHeight + 4 + categoryRowHeight
    }

    @ViewBuilder
    private var addCategoryPillLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.caption2)
            Text("Add category")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary.opacity(0.72))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if isSelectMode {
                selectModeCardContent
            } else {
                interactiveCardContent
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: Self.layoutHeight, alignment: .topLeading)
        .padding(Self.cardPadding)
        .background {
            if isSelectMode && isSelected {
                RoundedRectangle(appChromeBaseRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.28))
            }
        }
        .clipShape(RoundedRectangle(appChromeBaseRadius: 18, style: .continuous))
        .overlay {
            if !isSelectMode {
                RoundedRectangle(appChromeBaseRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var selectModeCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroThumbnail
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: Self.heroHeight)
                .clipShape(RoundedRectangle(appChromeBaseRadius: 14))
                .overlay(alignment: .topLeading) {
                    heroDateBadge
                }

            VStack(alignment: .leading, spacing: 4) {
                titleLabels
                    .frame(height: Self.titleBlockHeight, alignment: .topLeading)

                categoryRow
                    .frame(height: Self.categoryRowHeight, alignment: .leading)
                    .clipped()
            }
        }
    }

    private var interactiveCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { onTap?() } label: {
                heroThumbnail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .buttonStyle(.plain)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: Self.heroHeight)
            .clipShape(RoundedRectangle(appChromeBaseRadius: 14))
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                heroDateBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                titleBlock
                    .frame(height: Self.titleBlockHeight, alignment: .topLeading)

                categoryRow
                    .frame(height: Self.categoryRowHeight, alignment: .leading)
                    .clipped()
            }
        }
    }

    private var heroDateBadge: some View {
        Text(place.latestVisitDate.formatted(.dateTime.month(.abbreviated).day()))
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(10)
            .allowsHitTesting(false)
    }

    private var titleLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(place.cityDisplay ?? place.country)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let onTap {
            Button(action: onTap) {
                titleLabels
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            titleLabels
        }
    }

    @ViewBuilder
    private var categoryRow: some View {
        if let raw = place.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            PlacePOICategoryBadge(rawCategory: raw)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        } else if isSelectMode {
            addCategoryPillLabel
                .allowsHitTesting(false)
        } else if let onAddCategoryTap {
            Button(action: onAddCategoryTap) {
                addCategoryPillLabel
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            addCategoryPillLabel
        }
    }

    @ViewBuilder
    private var heroThumbnail: some View {
        if let hero = place.heroPhoto {
            RecapPhotoThumbnail(photo: hero, cornerRadius: 14, showIcon: false, targetSize: CGSize(width: 900, height: 600))
        } else {
            RoundedRectangle(appChromeBaseRadius: 14)
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }
}


private struct PlacesVisitedMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    @Binding var selectedYear: Int?
    @Binding var selectedCountry: String?
    @Binding var selectedCategory: String?
    @Binding var searchText: String
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    @Binding var suppressHomeBottomNav: Bool

    @State private var mapPosition: MapCameraPosition = .automatic
    /// Kept in sync via `onMapCameraChange` for screen-space overlap detection when zooming stacked markers.
    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
    )
    @State private var mapViewSize: CGSize = CGSize(width: 400, height: 800)
    @State private var selectedPlaceForModal: VisitedPlaceSummary?
    @State private var openCategoryPickerWhenPlaceModalOpens: Bool = false
    @State private var revealNavDuringModalDismiss: Bool = false
    @State private var isSearchActive: Bool = false
    @State private var hasTappedLocationButton: Bool = false
    @State private var selectedMapFeature: MapFeature?
    @State private var activePOIFeature: MapFeature?
    @State private var showPOISheet: Bool = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var locationHelper = PlacesVisitedMapLocationHelper()

    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
    )

    private var availableYears: [Int] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.year))).sorted(by: >)
    }

    private var availableCountries: [String] {
        Array(Set(createdRecapStore.visitedPlaces.map(\.country))).sorted()
    }

    private var availableCategories: [String] {
        let placesForYear = createdRecapStore.visitedPlaces.filter { place in
            guard let y = selectedYear else { return true }
            return place.year == y
        }

        let allRaws = placesForYear.compactMap { $0.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let dataRaws = Set(allRaws.filter { !$0.isEmpty })
        let includeOthers = placesForYear.contains {
            ($0.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var frequencies: [String: Int] = [:]
        for raw in allRaws where !raw.isEmpty { frequencies[raw, default: 0] += 1 }

        let cats = PlacePOICategoryCatalog.categoryRawsAppearingInDataForFilters(dataRaws: dataRaws, includeOthers: false)
        let sorted = cats.sorted { a, b in
            let fa = frequencies[a] ?? 0
            let fb = frequencies[b] ?? 0
            if fa != fb { return fa > fb }
            return PlacePOICategoryPresentation.displayLabel(forRaw: a)
                .localizedStandardCompare(PlacePOICategoryPresentation.displayLabel(forRaw: b)) == .orderedAscending
        }
        return includeOthers ? sorted + ["Others"] : sorted
    }

    private func coordinate(for place: VisitedPlaceSummary) -> CLLocationCoordinate2D? {
        if let loc = place.heroPhoto?.location?.clCoordinate { return loc }
        if let loc = place.photos.compactMap({ $0.location?.clCoordinate }).first { return loc }
        return nil
    }

    private var filteredPlaces: [VisitedPlaceSummary] {
        createdRecapStore.visitedPlaces
            .filter { place in
                if let y = selectedYear, place.year != y { return false }
                if let c = selectedCountry {
                    let lhs = place.country.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lhs.caseInsensitiveCompare(rhs) != .orderedSame { return false }
                }
                if let cat = selectedCategory {
                    let rhs = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lhsRaw = (place.categoryRawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if rhs.caseInsensitiveCompare("Others") == .orderedSame {
                        if !lhsRaw.isEmpty { return false }
                    } else if lhsRaw.caseInsensitiveCompare(rhs) != .orderedSame {
                        return false
                    }
                }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let q = query.lowercased()
                    let name = place.displayName.lowercased()
                    let city = (place.cityDisplay ?? "").lowercased()
                    let country = place.country.lowercased()
                    if !(name.contains(q) || city.contains(q) || country.contains(q)) { return false }
                }
                return true
            }
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    private var placesWithCoordinates: [(place: VisitedPlaceSummary, coordinate: CLLocationCoordinate2D)] {
        filteredPlaces.compactMap { place in
            guard let coord = coordinate(for: place) else { return nil }
            return (place, coord)
        }
    }

    private var clusteredPlaceItems: [VisitedPlaceCluster] {
        clusterVisitedPlaces(placesWithCoordinates, span: mapRegion.span)
    }

    private func recenterToLatestPlace() {
        if let latest = placesWithCoordinates.first?.coordinate {
            let region = MKCoordinateRegion(
                center: latest,
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
            )
            mapRegion = region
            withAnimation {
                mapPosition = .region(region)
            }
        } else {
            mapRegion = defaultRegion
            withAnimation {
                mapPosition = .region(defaultRegion)
            }
        }
    }

    // MARK: - Overlapping markers → zoom in until separable (My Places map)

    /// How close (pt) two marker centers can be on screen and still count as “stacked.”
    private static let clusterRadiusPixels: CGFloat = 68
    /// Minimum center-to-center distance (pt) before we open the place sheet instead of zooming again.
    private static let separationThresholdPixels: CGFloat = 58
    /// ~street-level floor — beyond this, identical coordinates cannot be separated by zoom.
    private static let minZoomSpanLat: CLLocationDegrees = 0.00014
    private static let minZoomSpanLon: CLLocationDegrees = 0.00014

    private func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        let r = mapRegion
        let size = mapViewSize
        guard size.width > 1, size.height > 1, r.span.latitudeDelta > 0, r.span.longitudeDelta > 0 else {
            return .zero
        }
        let minLon = r.center.longitude - r.span.longitudeDelta / 2
        let maxLat = r.center.latitude + r.span.latitudeDelta / 2
        let x = (coordinate.longitude - minLon) / r.span.longitudeDelta * size.width
        let y = (maxLat - coordinate.latitude) / r.span.latitudeDelta * size.height
        return CGPoint(x: x, y: y)
    }

    private func placesInScreenCluster(near place: VisitedPlaceSummary) -> [VisitedPlaceSummary] {
        guard let refCoord = coordinate(for: place) else { return [place] }
        let refPt = screenPoint(for: refCoord)
        return placesWithCoordinates.compactMap { item -> VisitedPlaceSummary? in
            guard let c = coordinate(for: item.place) else { return nil }
            let p = screenPoint(for: c)
            let d = hypot(p.x - refPt.x, p.y - refPt.y)
            return d <= Self.clusterRadiusPixels ? item.place : nil
        }
    }

    private func minPairwiseScreenDistance(_ places: [VisitedPlaceSummary]) -> CGFloat {
        let coords = places.compactMap { coordinate(for: $0) }
        guard coords.count >= 2 else { return .greatestFiniteMagnitude }
        var minD: CGFloat = .greatestFiniteMagnitude
        for i in 0..<coords.count {
            for j in (i + 1)..<coords.count {
                let p = screenPoint(for: coords[i])
                let q = screenPoint(for: coords[j])
                minD = min(minD, hypot(p.x - q.x, p.y - q.y))
            }
        }
        return minD
    }

    private var isAtMinZoomForOverlapResolution: Bool {
        mapRegion.span.latitudeDelta <= Self.minZoomSpanLat * 1.08
            && mapRegion.span.longitudeDelta <= Self.minZoomSpanLon * 1.08
    }

    private func zoomToSeparateCluster(_ cluster: [VisitedPlaceSummary]) {
        let coords = cluster.compactMap { coordinate(for: $0) }
        guard !coords.isEmpty else { return }
        let center = CLLocationCoordinate2D(
            latitude: coords.map(\.latitude).reduce(0, +) / Double(coords.count),
            longitude: coords.map(\.longitude).reduce(0, +) / Double(coords.count)
        )
        let newLat = max(mapRegion.span.latitudeDelta * 0.48, Self.minZoomSpanLat)
        let newLon = max(mapRegion.span.longitudeDelta * 0.48, Self.minZoomSpanLon)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: newLat, longitudeDelta: newLon)
        )
        mapRegion = region
        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            mapPosition = .region(region)
        }
    }

    private func handleMarkerTap(_ place: VisitedPlaceSummary) {
        let cluster = placesInScreenCluster(near: place)
        guard cluster.count >= 2 else {
            openCategoryPickerWhenPlaceModalOpens = false
            selectedPlaceForModal = place
            return
        }
        let minDist = minPairwiseScreenDistance(cluster)
        if minDist >= Self.separationThresholdPixels {
            openCategoryPickerWhenPlaceModalOpens = false
            selectedPlaceForModal = place
            return
        }
        if isAtMinZoomForOverlapResolution {
            openCategoryPickerWhenPlaceModalOpens = false
            selectedPlaceForModal = place
            return
        }
        zoomToSeparateCluster(cluster)
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func centerOnCurrentLocation() {
        if !CLLocationManager.locationServicesEnabled() {
            openLocationSettings()
            return
        }

        switch locationHelper.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationHelper.requestCurrentLocation { coordinate in
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                mapRegion = region
                withAnimation {
                    mapPosition = .region(region)
                }
            }
        case .notDetermined:
            locationHelper.requestAuthorizationAndCenter { coordinate in
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                mapRegion = region
                withAnimation {
                    mapPosition = .region(region)
                }
            }
        case .restricted, .denied:
            openLocationSettings()
        @unknown default:
            openLocationSettings()
        }
    }

    // MARK: - Year / Month grouping helpers (mirrors PlacesVisitedView)

    private struct MonthGroup {
        let month: Int          // 1–12
        let monthName: String   // e.g. "March"
        let places: [VisitedPlaceSummary]
    }

    private struct YearGroup {
        let year: Int
        let months: [MonthGroup]
    }

    private func groupedByYearThenMonth(_ places: [VisitedPlaceSummary]) -> [YearGroup] {
        let cal = Calendar.current
        let byYear = Dictionary(grouping: places) { cal.component(.year, from: $0.latestVisitDate) }
        return byYear.keys.sorted(by: >).map { year in
            let yearPlaces = byYear[year]!
            let byMonth = Dictionary(grouping: yearPlaces) { cal.component(.month, from: $0.latestVisitDate) }
            let monthGroups = byMonth.keys.sorted(by: >).map { month -> MonthGroup in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                let name: String = {
                    var comps = DateComponents(); comps.month = month; comps.year = year
                    let date = cal.date(from: comps) ?? Date()
                    return formatter.string(from: date)
                }()
                return MonthGroup(month: month, monthName: name, places: byMonth[month]!)
            }
            return YearGroup(year: year, months: monthGroups)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                Map(position: $mapPosition, selection: $selectedMapFeature) {
                    ForEach(clusteredPlaceItems) { cluster in
                        Annotation("", coordinate: cluster.coordinate) {
                            if cluster.isCluster {
                                PlacesVisitedClusterMarker(cluster: cluster)
                                    .onTapGesture {
                                        let newLat = max(Self.minZoomSpanLat, mapRegion.span.latitudeDelta / 3)
                                        let newLon = max(Self.minZoomSpanLon, mapRegion.span.longitudeDelta / 3)
                                        let region = MKCoordinateRegion(
                                            center: cluster.coordinate,
                                            span: MKCoordinateSpan(latitudeDelta: newLat, longitudeDelta: newLon)
                                        )
                                        mapRegion = region
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                            mapPosition = .region(region)
                                        }
                                    }
                            } else {
                                PlacesVisitedMapMarker(place: cluster.representative)
                                    .onTapGesture {
                                        handleMarkerTap(cluster.representative)
                                    }
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onChange(of: selectedMapFeature) { _, newFeature in
                    guard let newFeature else { return }
                    activePOIFeature = newFeature
                    showPOISheet = true
                    selectedMapFeature = nil
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapRegion = context.region
                }
                .onAppear {
                    mapViewSize = geo.size
                    recenterToLatestPlace()
                }
                .onChange(of: geo.size) { _, new in
                    mapViewSize = new
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedYear) { _, _ in
                // If the user switches years, drop any category that doesn't exist for the new year.
                if let selectedCategory,
                   !availableCategories.contains(where: { $0.caseInsensitiveCompare(selectedCategory) == .orderedSame }) {
                    self.selectedCategory = nil
                }
                recenterToLatestPlace()
            }
            .onChange(of: selectedCountry) { _, _ in
                recenterToLatestPlace()
            }
            .onChange(of: selectedCategory) { _, _ in
                recenterToLatestPlace()
            }

            // Top filter chips
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Year")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(label: "All", isSelected: selectedYear == nil, unselectedBackground: Color(red: 0.25, green: 0.31, blue: 0.40)) {
                                selectedYear = nil
                            }
                            ForEach(availableYears, id: \.self) { y in
                                chip(label: String(y), isSelected: selectedYear == y, unselectedBackground: Color(red: 0.25, green: 0.31, blue: 0.40)) {
                                    selectedYear = (selectedYear == y) ? nil : y
                                }
                            }
                        }
                    }
                }

                if !availableCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(label: "All", isSelected: selectedCategory == nil) {
                                    selectedCategory = nil
                                }
                                ForEach(availableCategories, id: \.self) { cat in
                                    placesVisitedMapCategoryChip(raw: cat, isSelected: selectedCategory == cat) {
                                        selectedCategory = (selectedCategory == cat) ? nil : cat
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Search overlay (dark navy, similar to My Blogs map search)
            if isSearchActive {
                Color(red: 5/255, green: 10/255, blue: 48/255)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // Search bar under header
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(HomeChromeMetrics.homeSearchFieldFont)
                            .foregroundColor(.white.opacity(0.7))
                        ZStack(alignment: .leading) {
                            if searchText.isEmpty {
                                Text("Search place, city, or country")
                                    .font(HomeChromeMetrics.homeSearchFieldFont)
                                    .foregroundStyle(HomeChromeMetrics.homeSearchPlaceholderColor)
                                    .lineLimit(1)
                                    .allowsHitTesting(false)
                            }
                            TextField("", text: $searchText)
                                .font(HomeChromeMetrics.homeSearchFieldFont)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .focused($isSearchFocused)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .fill(Color.white.opacity(0.12))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    // List of matching places (same grouping source as main list)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            if filteredPlaces.isEmpty {
                                VStack(spacing: 10) {
                                    Text("No matches")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)

                                    Text("Try a different place, city, or country.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 44)
                            } else {
                                let yearGroups = groupedByYearThenMonth(filteredPlaces)
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(yearGroups, id: \.year) { yearGroup in
                                        Text(String(yearGroup.year))
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)

                                        ForEach(yearGroup.months, id: \.month) { monthGroup in
                                            Text(monthGroup.monthName)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(.top, 10)
                                                .padding(.bottom, 6)

                                            LazyVGrid(columns: PlacesVisitedPlaceGrid.columns, spacing: 12) {
                                                ForEach(monthGroup.places) { place in
                                                    PlaceVisitedCard(
                                                        place: place,
                                                        onTap: {
                                                            openCategoryPickerWhenPlaceModalOpens = false
                                                            selectedPlaceForModal = place
                                                        },
                                                        onAddCategoryTap: {
                                                            openCategoryPickerWhenPlaceModalOpens = true
                                                            selectedPlaceForModal = place
                                                        }
                                                    )
                                                }
                                            }
                                            .padding(.bottom, 12)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
                .transition(.opacity)
            }

            // Full-screen place viewer (matches blog overlay, not a sheet).
            if let place = selectedPlaceForModal {
                PlaceVisitedPhotoModalWrapper(
                    place: place,
                    presentCategoryPickerInitially: openCategoryPickerWhenPlaceModalOpens,
                    onDismiss: {
                        selectedPlaceForModal = nil
                        openCategoryPickerWhenPlaceModalOpens = false
                        revealNavDuringModalDismiss = false
                    },
                    onDismissSlideBegan: { revealNavDuringModalDismiss = true },
                    onViewBlog: {
                        guard let ref = place.relatedBlogs.first,
                              let recap = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == ref.blogId }) else { return }
                        // Keep the place modal presented under the global recap overlay so dismissing
                        // the blog returns here instead of leaving only the list/map underneath.
                        openCategoryPickerWhenPlaceModalOpens = false
                        initialScrollToStopIdForRecap = ref.placeStopId
                        selectedCreatedRecap = recap
                    }
                )
                .environmentObject(createdRecapStore)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container)
            }

            if !isSearchActive {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            hasTappedLocationButton = true
                            centerOnCurrentLocation()
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(hasTappedLocationButton ? Color.blue.opacity(0.92) : Color.white.opacity(0.23))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 22)
                    }
                }
                .zIndex(90)
            }
        }
        .onTapGesture {
            if isSearchFocused {
                isSearchFocused = false
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.38), value: selectedPlaceForModal?.id)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSearchActive {
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSearchActive = false
                        }
                        searchText = ""
                        isSearchFocused = false
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                } else {
                    // Search icon (left)
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSearchActive = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSearchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.primary)
                    }

                    // Existing filter menu (right)
                    Menu {
                        Button("All Countries") { selectedCountry = nil }
                        ForEach(availableCountries, id: \.self) { c in
                            Button(c) { selectedCountry = c }
                        }
                    } label: {
                        Image(systemName: selectedCountry == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .toolbar((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground((selectedPlaceForModal != nil && !revealNavDuringModalDismiss) ? .hidden : .automatic, for: .navigationBar)
        .dynamicTypeSize(.large)
        .sheet(isPresented: $showPOISheet, onDismiss: {
            activePOIFeature = nil
        }) {
            if let feature = activePOIFeature {
                POIInfoSheet(feature: feature)
            }
        }
        .onChange(of: selectedPlaceForModal?.id) { _, _ in syncMapHomeBottomNavSuppression() }
        .onChange(of: revealNavDuringModalDismiss) { _, _ in syncMapHomeBottomNavSuppression() }
        .onDisappear { suppressHomeBottomNav = false }
    }

    private func syncMapHomeBottomNavSuppression() {
        suppressHomeBottomNav = selectedPlaceForModal != nil && !revealNavDuringModalDismiss
    }

    private func placesVisitedMapCategoryChip(raw: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let p = PlacePOICategoryPresentation.presentation(forRaw: raw)
        let label = PlacePOICategoryPresentation.displayLabel(forRaw: raw)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.white : p.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? p.color : p.color.opacity(0.35))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(p.color.opacity(isSelected ? 0.25 : 0.45), lineWidth: isSelected ? 0 : 1)
            )
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func chip(label: String, isSelected: Bool, unselectedBackground: Color = Color.white.opacity(0.23), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : unselectedBackground)
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}

private final class PlacesVisitedMapLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var pendingCenterRequest = false
    private var onCoordinateResolved: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation(onResolved: @escaping (CLLocationCoordinate2D) -> Void) {
        onCoordinateResolved = onResolved
        manager.requestLocation()
    }

    func requestAuthorizationAndCenter(onResolved: @escaping (CLLocationCoordinate2D) -> Void) {
        onCoordinateResolved = onResolved
        pendingCenterRequest = true
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard pendingCenterRequest else { return }
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            pendingCenterRequest = false
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            pendingCenterRequest = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        onCoordinateResolved?(coordinate)
        onCoordinateResolved = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onCoordinateResolved = nil
    }
}

private struct PlacesVisitedMapMarker: View {
    let place: VisitedPlaceSummary

    var body: some View {
        let rawCategory = place.categoryRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let categoryKey = rawCategory.isEmpty ? "Others" : rawCategory
        let categoryPresentation = PlacePOICategoryPresentation.presentation(forRaw: categoryKey)

        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)

                    if let hero = place.heroPhoto {
                        RecapPhotoThumbnail(photo: hero, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                            }
                    } else {
                        Image(systemName: "photo")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }

                Image(systemName: categoryPresentation.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(categoryPresentation.color))
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                    .offset(x: 4, y: -2)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }

            Text(place.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
                .frame(maxWidth: 110)
        }
    }
}

/// Cluster marker for 2+ visited places grouped at one map position.
/// Ghost ring behind + count badge distinguish it from the individual PlacesVisitedMapMarker.
private struct PlacesVisitedClusterMarker: View {
    let cluster: VisitedPlaceCluster

    var body: some View {
        VStack(spacing: 4) {
            // Count pill above the marker
            Text("\(cluster.count) Places")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.blue))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2)

            // Representative photo circle
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)

                if let hero = cluster.representative.heroPhoto {
                    RecapPhotoThumbnail(photo: hero, cornerRadius: 12, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                        }
                } else {
                    Image(systemName: "photo")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
        }
    }
}
