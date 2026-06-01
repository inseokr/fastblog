//
//  PlaceSearchViewModel.swift
//  fastblog
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

/// A named POI returned for a map tap when several places are too close to pick automatically.
struct MapTapPOICandidate: Identifiable, Hashable {
    var id: String {
        if let kakaoPlaceId, !kakaoPlaceId.isEmpty { return "kakao|\(kakaoPlaceId)" }
        return "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
    }
    let name: String
    let category: String?
    let coordinate: CLLocationCoordinate2D
    /// Distance from the user's tap to this POI's placemark (meters).
    let distanceMeters: Double
    /// Kakao Local place id — used for `place.map.kakao.com` and `kakaomap://` links.
    let kakaoPlaceId: String?
    let kakaoPlaceURLString: String?
    let addressSubtitle: String?
    let categoryLabel: String?
    let phone: String?

    init(
        name: String,
        category: String?,
        coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        kakaoPlaceId: String? = nil,
        kakaoPlaceURLString: String? = nil,
        addressSubtitle: String? = nil,
        categoryLabel: String? = nil,
        phone: String? = nil
    ) {
        self.name = name
        self.category = category
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.kakaoPlaceId = kakaoPlaceId
        self.kakaoPlaceURLString = kakaoPlaceURLString
        self.addressSubtitle = addressSubtitle
        self.categoryLabel = categoryLabel
        self.phone = phone
    }

    static func from(
        kakaoPlace place: KakaoPlace,
        distanceMeters: Double,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> MapTapPOICandidate {
        let trimmedName = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryLabel = place.category_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = place.displaySubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return MapTapPOICandidate(
            name: trimmedName,
            category: place.poiCategoryRaw,
            coordinate: place.coordinate ?? fallbackCoordinate,
            distanceMeters: distanceMeters,
            kakaoPlaceId: place.id,
            kakaoPlaceURLString: place.place_url,
            addressSubtitle: address.isEmpty ? nil : address,
            categoryLabel: categoryLabel.isEmpty ? nil : categoryLabel,
            phone: place.phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    /// In-app Kakao Map place page when this row came from Kakao Local (not used for MapKit-only candidates).
    var kakaoDetailWebURL: URL? {
        if let raw = kakaoPlaceURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let normalized = raw.hasPrefix("http://")
                ? "https://" + raw.dropFirst("http://".count)
                : raw
            if let url = URL(string: normalized) { return url }
        }
        if let placeId = kakaoPlaceId?.trimmingCharacters(in: .whitespacesAndNewlines), !placeId.isEmpty,
           let url = URL(string: "https://place.map.kakao.com/\(placeId)") {
            return url
        }
        return nil
    }

    /// Google search for MapKit nearby-picker rows (matches ``POIInfoSheet`` / ``StoryPlaceGoogleSearch``).
    var googleDetailWebURL: URL? {
        StoryPlaceGoogleSearch.url(placeName: name, placeSubtitle: addressSubtitle)
    }

    var kakaoMapAppURL: URL? {
        guard let placeId = kakaoPlaceId?.trimmingCharacters(in: .whitespacesAndNewlines), !placeId.isEmpty else {
            return nil
        }
        return URL(string: "kakaomap://place?id=\(placeId)")
    }

    static func == (lhs: MapTapPOICandidate, rhs: MapTapPOICandidate) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Result of resolving a bare map tap (no `MKMapFeatureAnnotation`) to a place.
enum MapTapPOIResult {
    case none
    case single(name: String, category: String?, coordinate: CLLocationCoordinate2D)
    case ambiguous(candidates: [MapTapPOICandidate])
}

/// One row in the debug POI panel — all candidates returned by a Kakao tap-resolve attempt.
struct DebugPOIEntry: Identifiable {
    let id = UUID()
    let name: String
    let categoryCode: String
    let rawDistanceMeters: Double
    let effectiveDistanceMeters: Double
}

/// Which backend serves autocomplete suggestions and coordinate resolution.
enum PlaceSearchProvider {
    case mapKit
    case kakao
}

/// Wraps MKLocalSearchCompleter (MapKit) and Kakao Local API for place suggestions,
/// automatically routing to the right provider based on the place's country.
final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [PlaceSuggestion] = []
    @Published var isSearching = false

    // MARK: - Debug (tap-resolve diagnostics)
    @Published var debugLastTapCoordinate: CLLocationCoordinate2D? = nil
    @Published var debugPOICandidates: [DebugPOIEntry] = []

    var onPlaceSelected: ((String) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()
    private let debounceInterval: TimeInterval = 0.3

    private var activeProvider: PlaceSearchProvider = .mapKit
    private var kakaoSearchTask: Task<Void, Never>?

    /// Stored for Kakao distance-biased search.
    private var biasCoordinate: CLLocationCoordinate2D?

    /// If set, MapKit search results are biased towards this region.
    var biasRegion: MKCoordinateRegion? {
        didSet {
            if let region = biasRegion {
                completer.region = region
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]

        $query
            .debounce(for: .seconds(debounceInterval), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                self?.updateSearch(query: newQuery)
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider selection

    /// Call this once the place's country is known. Switches to Kakao for KR when the API key is configured.
    func setProvider(isoCountryCode: String) {
        if isoCountryCode == "KR", KakaoLocalService.shared.isAvailable {
            activeProvider = .kakao
            completer.queryFragment = ""
            suggestions = []
            debugPrint("[PlaceSearch] provider → Kakao (KR)")
        } else {
            activeProvider = .mapKit
            kakaoSearchTask?.cancel()
            kakaoSearchTask = nil
            suggestions = []
            debugPrint("[PlaceSearch] provider → MapKit (\(isoCountryCode))")
        }
    }

    // MARK: - Bias location

    func setBiasLocation(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        biasCoordinate = coordinate
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        self.biasRegion = region
    }

    // MARK: - Search routing

    private func updateSearch(query: String) {
        switch activeProvider {
        case .mapKit:
            if query.isEmpty { suggestions = []; return }
            completer.queryFragment = query
        case .kakao:
            kakaoSearchTask?.cancel()
            if query.isEmpty { suggestions = []; return }
            let coord = biasCoordinate
            let q = query
            kakaoSearchTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                let places = await KakaoLocalService.shared.searchPlaces(query: q, near: coord)
                guard !Task.isCancelled else { return }
                self.suggestions = places.compactMap { place in
                    guard let coord = place.coordinate else { return nil }
                    return PlaceSuggestion(
                        id: place.id,
                        title: place.place_name,
                        subtitle: place.displaySubtitle,
                        source: .kakao(coordinate: coord, categoryRaw: place.poiCategoryRaw)
                    )
                }
            }
        }
    }

    func clearQuery() {
        query = ""
        suggestions = []
        kakaoSearchTask?.cancel()
        kakaoSearchTask = nil
    }

    // MARK: - Suggestion resolution

    /// Resolves a picked suggestion to its coordinate and POI category.
    /// For Kakao suggestions this returns immediately; for MapKit it does a network round-trip.
    func resolveDetails(for suggestion: PlaceSuggestion) async -> (coordinate: CLLocationCoordinate2D?, categoryRaw: String?) {
        switch suggestion.source {
        case .mapKit(let completion):
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            guard let response = try? await search.start(),
                  let mapItem = response.mapItems.first else {
                debugPrint("[PlaceSearch] resolveDetails(mapKit) '\(suggestion.title)' → no result")
                return (nil, nil)
            }
            let cat = mapItem.pointOfInterestCategory?.rawValue
            debugPrint("[PlaceSearch] resolveDetails(mapKit) '\(suggestion.title)' → category=\(cat ?? "nil")")
            return (mapItem.placemark.coordinate, cat)
        case .kakao(let coordinate, let categoryRaw):
            debugPrint("[PlaceSearch] resolveDetails(kakao) '\(suggestion.title)' → category=\(categoryRaw ?? "nil")")
            return (coordinate, categoryRaw)
        }
    }

    // MARK: - Coordinate → place name

    /// Returns the best human-readable place name for a coordinate.
    /// Uses Kakao reverse geocode when the active provider is Kakao; otherwise `GeocodingService` (Apple geocoder).
    func resolveCoordinateName(at coordinate: CLLocationCoordinate2D) async -> String {
        if activeProvider == .kakao {
            if let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coordinate) {
                let name = doc.bestPlaceName
                if !name.isEmpty {
                    debugPrint("[PlaceSearch] resolveCoordinateName(kakao) → '\(name)'")
                    return name
                }
            }
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let place = await GeocodingService.shared.place(for: location, precise: true)
        // Prefer `bestPlaceLabel`: it filters street-suffix names (" st", " ave", …) and falls
        // through to subLocality/locality. Taps that miss every nearby POI surface a neighborhood
        // or city name instead of "1234 Main St", which is what users actually want.
        let preferred = place.bestPlaceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let usePreferred = !preferred.isEmpty && preferred != "Unknown Place"
        let name = usePreferred ? preferred : place.title
        debugPrint("[PlaceSearch] resolveCoordinateName(geocoder) → '\(name)' (best='\(place.bestPlaceLabel)' title='\(place.title)')")
        return name
    }

    // MARK: - MapKit POI tap resolution

    /// Search radius for POIs around a map tap (meters). Scales with zoom.
    private static func tapSearchRadiusMeters(mapRegion: MKCoordinateRegion?) -> Double {
        if let region = mapRegion {
            let metersPerPoint = region.span.latitudeDelta * 111_000.0 / 500.0
            return max(25.0, min(80.0, metersPerPoint * 22.0))
        }
        return 80.0
    }

    /// Wide fallback radius (meters) when the strict tap radius returns no POI. Apple's POI registration
    /// coordinate is often offset 30–80 m (sometimes more, e.g. hotel entrance vs. building footprint),
    /// so a strict-only search misses POIs the user clearly tapped on. Picked to match the upper Kakao tier.
    private static let widePOIFallbackRadiusMeters: Double = 250

    /// Routes a map tap to Kakao (when activeProvider == .kakao) or MapKit, from a single call site.
    /// `EditPlaceStopNameSheet` always calls this so Korean map taps go through Kakao automatically.
    func resolveMapTapForCurrentProvider(
        near coordinate: CLLocationCoordinate2D,
        mapRegion: MKCoordinateRegion? = nil
    ) async -> MapTapPOIResult {
        if activeProvider == .kakao, KakaoLocalService.shared.isAvailable {
            let zoom = Self.kakaoZoomLevelFromRegion(mapRegion)
            return await resolveKakaoMapTapPOI(near: coordinate, kakaoZoomLevel: zoom)
        }
        return await resolveMapTapPOI(near: coordinate, mapRegion: mapRegion)
    }

    /// Converts an MKCoordinateRegion latitude delta to an approximate Kakao zoom level (13–20).
    private static func kakaoZoomLevelFromRegion(_ region: MKCoordinateRegion?) -> Int {
        guard let latDelta = region?.span.latitudeDelta else { return 16 }
        switch latDelta {
        case ..<0.002: return 20
        case ..<0.004: return 18
        case ..<0.008: return 16
        case ..<0.02:  return 14
        default:       return 13
        }
    }

    /// Resolves a bare map tap to a POI using MKLocalPointsOfInterestRequest.
    /// Strategy: strict zoom-scaled radius first (best when the tap landed on a label), then a generous
    /// fallback radius so registration offsets don't silently degrade to a street-name reverse geocode.
    /// If two or more POIs are almost equally close, returns `.ambiguous` so the UI can let the user choose.
    func resolveMapTapPOI(near coordinate: CLLocationCoordinate2D, mapRegion: MKCoordinateRegion? = nil) async -> MapTapPOIResult {
        let strictRadius = Self.tapSearchRadiusMeters(mapRegion: mapRegion)
        debugPrint("[POI] resolveMapTapPOI strictRadius=\(Int(strictRadius))m latDelta=\(mapRegion?.span.latitudeDelta ?? -1)")

        let strict = await searchPOINearTap(coordinate: coordinate, radius: strictRadius)
        if case .none = strict {
            let wide = Self.widePOIFallbackRadiusMeters
            debugPrint("[POI] resolveMapTapPOI strict empty → retrying wideRadius=\(Int(wide))m")
            return await searchPOINearTap(coordinate: coordinate, radius: wide)
        }
        return strict
    }

    /// Single-radius POI search around a tap. Returns `.single` for a dominant nearest POI,
    /// `.ambiguous` when two or more POIs are within `ambiguousGapMeters` of the closest, else `.none`.
    private func searchPOINearTap(coordinate: CLLocationCoordinate2D, radius: Double) async -> MapTapPOIResult {
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !response.mapItems.isEmpty else { return .none }

        let withName = response.mapItems.filter { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let scored: [(item: MKMapItem, distance: Double)] = withName.compactMap { item in
            let loc = item.placemark.location
                ?? CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let d = tapLocation.distance(from: loc)
            guard d <= radius else { return nil }
            return (item, d)
        }
        .sorted { $0.distance < $1.distance }

        guard let first = scored.first else {
            debugPrint("[POI] no named POI within radius=\(Int(radius))m")
            return .none
        }

        let gapToSecond = scored.count >= 2 ? scored[1].distance - first.distance : Double.greatestFiniteMagnitude
        let ambiguousGapMeters: Double = 22

        if scored.count >= 2, gapToSecond < ambiguousGapMeters {
            let capped = scored.prefix(8).map { pair in
                MapTapPOICandidate(
                    name: (pair.item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    category: pair.item.pointOfInterestCategory?.rawValue,
                    coordinate: pair.item.placemark.coordinate,
                    distanceMeters: pair.distance
                )
            }
            debugPrint("[POI] ambiguous tap: \(capped.count) candidates (gap \(Int(gapToSecond))m, radius=\(Int(radius))m)")
            return .ambiguous(candidates: Array(capped))
        }

        let name = (first.item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .none }
        debugPrint("[POI] single POI '\(name)' dist=\(Int(first.distance))m radius=\(Int(radius))m")
        return .single(
            name: name,
            category: first.item.pointOfInterestCategory?.rawValue,
            coordinate: first.item.placemark.coordinate
        )
    }

    // MARK: - Kakao category priority

    /// Multiplier applied to raw distance before ranking Kakao nearby results.
    /// Values < 1.0 boost a category (effectively closer); > 1.0 deprioritize it.
    /// Attractions and cultural venues are strongly preferred; restaurants/cafes are deprioritized
    /// so a café 30 m away doesn't shadow a landmark 60 m away.
    private static func categoryPriorityMultiplier(for code: String) -> Double {
        switch code {
        case "AT4": return 0.50  // tourist attractions — highest priority
        case "CT1": return 0.55  // cultural facilities (museums, galleries)
        case "AD5": return 0.70  // accommodations / hotels
        case "SW8": return 0.75  // subway / transit hubs
        case "PO3": return 0.85  // public institutions — often travel-relevant in KR
        case "PK6": return 1.05  // parking
        case "OL7": return 1.10  // gas / charging
        case "BK9": return 1.15  // banks
        case "HP8": return 1.10  // hospitals
        case "PM9": return 1.20  // pharmacies
        case "CS2": return 1.30  // convenience stores
        case "MT1": return 1.30  // marts / supermarkets
        case "FD6": return 1.40  // restaurants
        case "CE7": return 1.50  // cafes — lowest priority
        default:    return 1.00
        }
    }

    /// Kakao category groups omitted from map-tap nearby lists and auto-pick (infrastructure, not destinations).
    private static let kakaoExcludedMapTapCategoryCodes: Set<String> = [
        "PK6",  // parking
        "OL7",  // gas / EV charging only
    ]

    /// Boarding gates, ticket booths, etc. — not the main destination when the user taps a map label
    /// (e.g. "돌산 탑승장" vs "여수해상케이블카" at the same site).
    private static func kakaoMapTapPOINameIsSubFacility(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        let markers = [
            "탑승장", "승강장", "하차장", "승하차", "매표소", "매표실", "발권",
            "입구", "출구", "정문", "후문", "동문", "서문", "남문", "북문",
            "안내소", "안내센터", "관광안내", "주차타워",
        ]
        return markers.contains { n.localizedCaseInsensitiveContains($0) }
    }

    /// Restrooms, parking, transit stops, etc. — excluded from nearby picker and auto-resolve.
    private static func kakaoMapTapPOINameIsExcluded(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return true }
        let blocked = [
            "화장실", "공중화장실", "변기", "장애인화장실",
            "주차장", "주차타워", "주차빌딩", "기계식주차", "코인주차", "발렛",
            "지하주차", "옥외주차",
            "승하차장", "버스정류", "정류장", "택시승강",
            "ATM", "에이티엠", "무인민원", "경비실", "관리사무소",
            "쓰레기", "분리수거", "택배함", "우편함",
            "전기차충전", "충전소", "주유소", "LPG",
        ]
        return blocked.contains { n.localizedCaseInsensitiveContains($0) }
    }

    private static func kakaoMapTapPlaceIsExcluded(_ place: KakaoPlace) -> Bool {
        if kakaoExcludedMapTapCategoryCodes.contains(place.category_group_code) {
            return true
        }
        return kakaoMapTapPOINameIsExcluded(place.place_name)
    }

    private struct KakaoMapTapScoredPlace {
        let place: KakaoPlace
        let rawDistanceMeters: Double
        let effectiveDistanceMeters: Double
    }

    private static func kakaoMapTapScoreMultiplier(for place: KakaoPlace) -> Double {
        var m = categoryPriorityMultiplier(for: place.category_group_code)
        if kakaoMapTapPOINameIsSubFacility(place.place_name) { m *= 1.45 }
        return m
    }

    private static func kakaoMapTapLandmarkSortDistance(rawMeters: Double, placeName: String) -> Double {
        rawMeters * (kakaoMapTapPOINameIsSubFacility(placeName) ? 1.45 : 1.0)
    }

    /// Extra diagnostic output (console filter: `[POI-debug] mapTap-score`).
    /// Keep `false` for normal use; flip on when debugging missing candidates.
    private static let kakaoMapTapExplainScoreDebug = true

    private static func kakaoMaxAcceptDistanceMeters(
        for place: KakaoPlace,
        searchRadius: Int,
        isDirectPOITap: Bool
    ) -> Double {
        switch place.category_group_code {
        case "AT4": return Double(max(searchRadius, isDirectPOITap ? 1200 : 900))
        case "CT1": return Double(max(searchRadius, isDirectPOITap ? 900 : 650))
        case "PO3": return Double(max(searchRadius, isDirectPOITap ? 650 : 450))
        default:    return Double(searchRadius)
        }
    }

    private func kakaoScorePlacesForMapTap(
        places: [KakaoPlace],
        coordinate: CLLocationCoordinate2D,
        searchRadius: Int,
        isDirectPOITap: Bool
    ) -> [KakaoMapTapScoredPlace] {
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        enum DropReason: String {
            case excluded = "excluded(name/category)"
            case missingCoordinate = "missing coordinate"
            case emptyName = "empty name"
            case beyondMaxAccept = "beyond maxAccept"
        }

        var kept: [KakaoMapTapScoredPlace] = []
        var dropCounts: [DropReason: Int] = [:]
        var dropSamples: [String] = []
        var keepSamples: [String] = []

        func recordDrop(_ reason: DropReason, place: KakaoPlace, detail: String) {
            dropCounts[reason, default: 0] += 1
            guard Self.kakaoMapTapExplainScoreDebug, dropSamples.count < 14 else { return }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            dropSamples.append("drop=\(reason.rawValue) '\(name)' [\(place.category_group_code)] \(detail)")
        }

        for place in places {
            if Self.kakaoMapTapPlaceIsExcluded(place) {
                recordDrop(.excluded, place: place, detail: "")
                continue
            }
            guard let coord = place.coordinate else {
                recordDrop(.missingCoordinate, place: place, detail: "")
                continue
            }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                recordDrop(.emptyName, place: place, detail: "")
                continue
            }

            let rawDist = place.distanceMetersFromAPI
                ?? tapLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            let maxAccept = Self.kakaoMaxAcceptDistanceMeters(
                for: place,
                searchRadius: searchRadius,
                isDirectPOITap: isDirectPOITap
            )
            if rawDist > maxAccept {
                recordDrop(.beyondMaxAccept, place: place, detail: "raw=\(Int(rawDist))m max=\(Int(maxAccept))m")
                continue
            }

            let categoryMult = Self.categoryPriorityMultiplier(for: place.category_group_code)
            let subFacilityMult: Double = Self.kakaoMapTapPOINameIsSubFacility(name) ? 1.45 : 1.0
            let mult = categoryMult * subFacilityMult
            let effective = rawDist * mult

            if Self.kakaoMapTapExplainScoreDebug, keepSamples.count < 14 {
                let catStr = String(format: "%.2f", categoryMult)
                let subStr = String(format: "%.2f", subFacilityMult)
                keepSamples.append(
                    "keep '\(name)' [\(place.category_group_code)] raw=\(Int(rawDist))m max=\(Int(maxAccept))m ×cat=\(catStr) ×sub=\(subStr) → eff=\(Int(effective))m"
                )
            }

            kept.append(
                KakaoMapTapScoredPlace(
                    place: place,
                    rawDistanceMeters: rawDist,
                    effectiveDistanceMeters: effective
                )
            )
        }

        if Self.kakaoMapTapExplainScoreDebug {
            let keptCount = kept.count
            let droppedCount = places.count - keptCount
            let dropSummary = dropCounts
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: " · ")
            Self.poiDebugTrace(
                "mapTap-score R=\(searchRadius)m directPOI=\(isDirectPOITap) in=\(places.count) kept=\(keptCount) dropped=\(droppedCount) (\(dropSummary))"
            )
            for line in keepSamples { Self.poiDebugTrace("mapTap-score \(line)") }
            for line in dropSamples { Self.poiDebugTrace("mapTap-score \(line)") }
        }

        return kept.sorted { $0.effectiveDistanceMeters < $1.effectiveDistanceMeters }
    }

    private func mapTapCandidates(
        from scored: [KakaoMapTapScoredPlace],
        fallbackCoordinate: CLLocationCoordinate2D,
        limit: Int
    ) -> [MapTapPOICandidate] {
        let slice = Array(scored.prefix(limit))
        if Self.kakaoMapTapExplainScoreDebug {
            let keptTotal = scored.count
            let returned = slice.count
            let cutoffEff = slice.last?.effectiveDistanceMeters ?? -1
            Self.poiDebugTrace(
                "mapTap-candidates limit=\(limit) returned=\(returned)/kept=\(keptTotal) cutoffEff=\(Int(cutoffEff))m"
            )
            for (i, row) in slice.enumerated() {
                let name = row.place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
                let code = row.place.category_group_code.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.poiDebugTrace(
                    "mapTap-candidates #\(i + 1) eff=\(Int(row.effectiveDistanceMeters))m raw=\(Int(row.rawDistanceMeters))m · \(name) [\(code)]"
                )
            }
        }

        return slice.map { row in
            MapTapPOICandidate.from(
                kakaoPlace: row.place,
                distanceMeters: row.rawDistanceMeters,
                fallbackCoordinate: fallbackCoordinate
            )
        }
    }

    /// Ranked nearby places for a Kakao map tap — shared by auto-resolve and the "what's around" picker.
    func fetchKakaoMapTapNearbyCandidates(
        near coordinate: CLLocationCoordinate2D,
        kakaoZoomLevel: Int,
        isDirectPOITap: Bool = false
    ) async -> [MapTapPOICandidate] {
        guard activeProvider == .kakao, KakaoLocalService.shared.isAvailable else { return [] }
        let strictRadius = Self.kakaoTapRadiusMeters(zoomLevel: kakaoZoomLevel)
        let searchRadius = isDirectPOITap
            ? max(strictRadius, Self.kakaoWidePOIFallbackRadiusMeters)
            : strictRadius
        let places = await KakaoLocalService.shared.searchNearbyPlacesForMapTap(
            coordinate: coordinate,
            radius: searchRadius,
            isDirectPOITap: isDirectPOITap
        )
        let scored = kakaoScorePlacesForMapTap(
            places: places,
            coordinate: coordinate,
            searchRadius: searchRadius,
            isDirectPOITap: isDirectPOITap
        )
        let candidates = mapTapCandidates(from: scored, fallbackCoordinate: coordinate, limit: 20)
        await MainActor.run {
            debugLastTapCoordinate = coordinate
            debugPOICandidates = scored.prefix(50).map { row in
                DebugPOIEntry(
                    name: row.place.place_name,
                    categoryCode: row.place.category_group_code,
                    rawDistanceMeters: row.rawDistanceMeters,
                    effectiveDistanceMeters: row.effectiveDistanceMeters
                )
            }
        }
        return candidates
    }

    /// Direct tile POI taps: show the nearby list when several places share the tap (SDK has no label).
    func kakaoNearbyPickerCandidatesIfNeeded(
        for result: MapTapPOIResult,
        near coordinate: CLLocationCoordinate2D,
        kakaoZoomLevel: Int,
        isDirectPOITap: Bool
    ) async -> [MapTapPOICandidate]? {
        guard isDirectPOITap else { return nil }
        if case .ambiguous = result { return nil }

        var nearby = await fetchKakaoMapTapNearbyCandidates(
            near: coordinate,
            kakaoZoomLevel: kakaoZoomLevel,
            isDirectPOITap: true
        )

        if case .single(let name, _, _) = result, Self.kakaoMapTapPOINameIsSubFacility(name) {
            let widened = await fetchKakaoDirectTapLandmarkAlternatives(near: coordinate)
            nearby = mergeMapTapCandidates(nearby, widened)
            Self.poiDebugTrace(
                "nearbyPicker sub-facility single '\(name)' → merged \(nearby.count) choices (landmark widen)"
            )
            if nearby.count >= 2 { return nearby }
            if let parent = nearby.first(where: { !Self.kakaoMapTapPOINameIsSubFacility($0.name) }) {
                return [parent]
            }
            return nil
        }

        guard nearby.count >= 2 else { return nil }
        if case .single(let name, _, _) = result, Self.kakaoMapTapPOINameIsExcluded(name) {
            return nearby
        }
        // Always offer the picker on direct POI taps when multiple Kakao Local rows are in range.
        return nearby
    }

    /// Wider AT4/CT1 pull when coord2address or ranking surfaced a sub-facility (탑승장, 매표소, …).
    private func fetchKakaoDirectTapLandmarkAlternatives(
        near coordinate: CLLocationCoordinate2D
    ) async -> [MapTapPOICandidate] {
        guard activeProvider == .kakao, KakaoLocalService.shared.isAvailable else { return [] }
        let places = await KakaoLocalService.shared.searchLandmarkPlacesNear(
            coordinate: coordinate,
            radius: Self.kakaoLandmarkIdentitySearchRadiusMeters(isDirectPOITap: true)
        )
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let scored: [(place: KakaoPlace, rawMeters: Double, sortMeters: Double)] = places.compactMap { place in
            guard !Self.kakaoMapTapPlaceIsExcluded(place) else { return nil }
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let raw = place.distanceMetersFromAPI
                ?? tapLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard raw <= 900 else { return nil }
            let sortDist = Self.kakaoMapTapLandmarkSortDistance(rawMeters: raw, placeName: name)
            return (place, raw, sortDist)
        }
        .sorted { $0.sortMeters < $1.sortMeters }
        return scored.prefix(12).map { row in
            MapTapPOICandidate.from(
                kakaoPlace: row.place,
                distanceMeters: row.rawMeters,
                fallbackCoordinate: coordinate
            )
        }
    }

    private func mergeMapTapCandidates(
        _ a: [MapTapPOICandidate],
        _ b: [MapTapPOICandidate]
    ) -> [MapTapPOICandidate] {
        var seen = Set<String>()
        var merged: [MapTapPOICandidate] = []
        for c in a + b {
            if seen.insert(c.id).inserted { merged.append(c) }
        }
        return merged
    }

    // MARK: - Kakao Local POI tap resolution

    /// Search radius (meters) around a tap from Kakao map zoom level (1 = far out … 21 = close in).
    /// Generous radii account for the user tapping on nearby terrain instead of directly on the POI icon,
    /// which can offset the registered coordinate by 30–80 m depending on zoom.
    private static func kakaoTapRadiusMeters(zoomLevel: Int) -> Int {
        switch zoomLevel {
        case 19...21: return 70
        case 17..<19: return 100
        case 15..<17: return 140
        case 13..<15: return 200
        default: return 280
        }
    }

    /// Kakao tiles and label hit-testing can be offset from Kakao Local results by tens of meters,
    /// especially when the user taps a POI icon at high zoom. Mirror the MapKit fallback strategy
    /// with a wider retry radius to avoid silently degrading to reverse geocode.
    private static let kakaoWidePOIFallbackRadiusMeters: Int = 250

    // MARK: - Kakao map tap debug (console: filter `[POI-debug]`)

    /// Famous-site substrings to call out explicitly in logs (e.g. 첨성대 taps mis-resolving).
    private static let kakaoTapDebugWatchSubstrings: [String] = ["첨성대", "Cheomseongdae"]

    private static func poiDebugTrace(_ message: String) {
        debugPrint("[POI-debug] \(message)")
    }

    private static func poiDebugTapHeader(
        coordinate: CLLocationCoordinate2D,
        kakaoZoomLevel: Int,
        isDirectPOITap: Bool
    ) {
        poiDebugTrace(
            String(
                format: "tap lat=%.6f lon=%.6f zoom=%d directPOI=%@",
                coordinate.latitude,
                coordinate.longitude,
                kakaoZoomLevel,
                isDirectPOITap ? "YES" : "NO")
        )
    }

    private static func poiDebugTapDistance(place: KakaoPlace, tapLoc: CLLocation) -> Double? {
        guard let coord = place.coordinate else { return nil }
        return place.distanceMetersFromAPI
            ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
    }

    /// Whether `needle` occurs in any place name (Korean name search).
    private static func poiDebugWatchHits(places: [KakaoPlace], tapLoc: CLLocation) -> String {
        var segments: [String] = []
        for needle in kakaoTapDebugWatchSubstrings {
            let rows = places.compactMap { p -> String? in
                guard p.place_name.contains(needle) else { return nil }
                guard let d = poiDebugTapDistance(place: p, tapLoc: tapLoc) else { return nil }
                return "'\(p.place_name)' [\(p.category_group_code)] ~\(Int(d))m"
            }
            if rows.isEmpty {
                segments.append("watch '\(needle)': (none among \(places.count) places)")
            } else {
                segments.append("watch '\(needle)': \(rows.joined(separator: " | "))")
            }
        }
        return segments.joined(separator: " · ")
    }

    private static func poiDebugDumpPlaces(prefix: String, places: [KakaoPlace], tapLoc: CLLocation, limit: Int = 12) {
        poiDebugTrace("\(prefix) n=\(places.count) — \(poiDebugWatchHits(places: places, tapLoc: tapLoc))")
        for (i, p) in places.prefix(limit).enumerated() {
            let d = poiDebugTapDistance(place: p, tapLoc: tapLoc).map { Int($0) } ?? -1
            let distAPI = p.distance ?? "—"
            poiDebugTrace("  \(i + 1). \(p.place_name) [\(p.category_group_code)] dist~\(d)m API.distance=\(distAPI)")
        }
        if places.count > limit {
            poiDebugTrace("  … \(places.count - limit) more")
        }
    }

    private static func poiDebugDescribeResult(_ result: MapTapPOIResult) -> String {
        switch result {
        case .none: return "none"
        case .single(let name, let cat, _):
            return "single '\(name)' cat=\(cat ?? "nil")"
        case .ambiguous(let c):
            let names = c.prefix(4).map(\.name).joined(separator: ", ")
            return "ambiguous(\(c.count)) [\(names)\(c.count > 4 ? ", …" : "")]"
        }
    }

    /// When AT4/CT1 results are this much closer than nearby dining (FD6/CE7), resolve from landmarks only.
    /// Avoids picking a famous temple when the user clearly tapped a nearer restaurant; still favors the
    /// landmark when food is farther away (large-site / tap-on-ground cases).
    private static let landmarkOverDiningProximityGapMeters: Double = 35

    /// Kakao Local category radius for AT4 ∪ CT1 before the broad map-tap fan-out. Tile POI taps often
    /// land 100–250 m from Kakao’s registered landmark coordinate; large outdoor AT4 blobs (계림 등) may
    /// Direct taps use a moderately wide AT4 ∪ CT1 search; overly large radii snag unrelated regional POIs.
    private static func kakaoLandmarkIdentitySearchRadiusMeters(isDirectPOITap: Bool) -> Int {
        isDirectPOITap ? 380 : 320
    }

    /// Historic-site keyword-recover: reject hits farther than this from the tap — avoids snapping to unrelated AT4 far away.
    private static let keywordHistoricRecoverMaxMetersFromTap: Double = 380

    /// If Kakao’s registered centroid is farther than this from the tap, keep the tap as the resolved coordinate (same as keyword path).
    private static let landmarkBiasPreferTapIfRegistrationBeyondMeters: Double = 280

    /// 상권 이름에 섞인 “〇〇첨성대점” 등 — 키워드 검색 결과에서 명승 우선 순위 배제용.
    private static func kakaoNameLooksCommercialLandmarkMisuse(_ name: String) -> Bool {
        let n = name
        let junk = ["카페", "커피", "MGC", "스타벅스", "바나프레소", "GS25", "CU ", "미니스톱", "빵", "베이커리",
                    "제과", "매점", "매표", "점", "스테이", "펜션", "게스트", "모텔", "호텔", "한옥", "숙박", "편의점", "마트", "슈퍼"]
        return junk.contains { n.contains($0) }
    }

    /// Landmark keyword recover: 같은 반경 안에서 **거리만** 고르면 “스튜디오 초”가 “첨성대”(문화재, 빈 group)보다 가깝게 이기므로 순위 필요.
    private static func kakaoKeywordRecoverRank(place: KakaoPlace, query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n == q || n == "경주 \(q)" { return 0 }
        switch place.category_group_code {
        case "AT4": return 1
        case "CT1": return 2
        case "PO3": return 3
        case "":
            return n.hasPrefix(q) ? 4 : 6
        default: return 6
        }
    }

    /// Very small core bbox around 첨성대 itself — 브로더 “첨성로” 카페/식당 타일까지 키워드 복구가 가로채지 않도록.
    private static func kakaoDirectTapHistoricKeywordQuery(
        coordinate: CLLocationCoordinate2D,
        addressDoc: KakaoCoord2AddressDoc
    ) -> String? {
        _ = addressDoc
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let cheomseongdaeCoreBBox = (35.83448...35.83512).contains(lat)
            && (129.21845...129.21935).contains(lon)
        return cheomseongdaeCoreBBox ? "첨성대" : nil
    }

    /// 타일 POI 직탭 + 주소/좌표가 첨성대 권역이면 키워드+AT4(→CT1)로 본디 명승 한 건을 복구.
    private func tryDirectTapKeywordHistoricRecover(near coordinate: CLLocationCoordinate2D, isDirectPOITap: Bool) async -> MapTapPOIResult? {
        guard isDirectPOITap, activeProvider == .kakao, KakaoLocalService.shared.isAvailable else { return nil }
        guard let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coordinate) else {
            Self.poiDebugTrace("keywordRecover SKIP: coord2address nil")
            return nil
        }
        guard let query = Self.kakaoDirectTapHistoricKeywordQuery(coordinate: coordinate, addressDoc: doc) else {
            Self.poiDebugTrace("keywordRecover SKIP: no regional hint (첨성로 / Cheomseongdae bbox)")
            return nil
        }

        // Request window for Kakao keyword API (sort=distance); we only *accept* within `keywordHistoricRecoverMaxMetersFromTap`.
        let apiRadius = 1200
        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Self.poiDebugTrace(
            "keywordRecover TRY query='\(query)' apiR=\(apiRadius)m acceptMax=\(Int(Self.keywordHistoricRecoverMaxMetersFromTap))m (AT4→CT1→경주+q→plain)"
        )

        var pool: [KakaoPlace] = await KakaoLocalService.shared.searchPlaces(
            query: query, near: coordinate, radius: apiRadius, categoryGroupCode: "AT4")
        if pool.isEmpty {
            pool = await KakaoLocalService.shared.searchPlaces(
                query: query, near: coordinate, radius: apiRadius, categoryGroupCode: "CT1")
        }
        if pool.isEmpty {
            let altQuery = "경주 " + query
            pool = await KakaoLocalService.shared.searchPlaces(
                query: altQuery, near: coordinate, radius: apiRadius, categoryGroupCode: "AT4")
            Self.poiDebugTrace("keywordRecover: AT4 '\(altQuery)' n=\(pool.count)")
        }
        if pool.isEmpty {
            pool = await KakaoLocalService.shared.searchPlaces(query: query, near: coordinate, radius: apiRadius)
            Self.poiDebugTrace("keywordRecover: unfiltered keyword n=\(pool.count)")
        }

        Self.poiDebugDumpPlaces(prefix: "keywordRecover raw", places: pool, tapLoc: tapLoc, limit: 15)

        let cleaned = pool.filter { !Self.kakaoNameLooksCommercialLandmarkMisuse($0.place_name) }
        Self.poiDebugTrace("keywordRecover after drop commercial-like: \(cleaned.count)")

        let scored: [(place: KakaoPlace, distance: Double)] = cleaned.compactMap { place in
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let d = place.distanceMetersFromAPI
                ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard d <= Self.keywordHistoricRecoverMaxMetersFromTap else { return nil }
            return (place, d)
        }
        .sorted {
            let r0 = Self.kakaoKeywordRecoverRank(place: $0.place, query: query)
            let r1 = Self.kakaoKeywordRecoverRank(place: $1.place, query: query)
            if r0 != r1 { return r0 < r1 }
            return $0.distance < $1.distance
        }

        for (idx, pair) in scored.prefix(6).enumerated() {
            let r = Self.kakaoKeywordRecoverRank(place: pair.place, query: query)
            Self.poiDebugTrace(
                "  keywordRecover ranked#\(idx + 1) tier=\(r) dist=\(Int(pair.distance))m · \(pair.place.place_name) [\(pair.place.category_group_code)]"
            )
        }

        guard let first = scored.first else {
            Self.poiDebugTrace(
                "keywordRecover OUT none (nothing within \(Int(Self.keywordHistoricRecoverMaxMetersFromTap))m after filters)"
            )
            return nil
        }

        // Pin stays on the user's tap — Kakao's registered centroid often sits far from where they touched.
        let pinCoordinate = coordinate

        if scored.count >= 2 {
            let capped = scored.prefix(12).map { pair in
                MapTapPOICandidate.from(
                    kakaoPlace: pair.place,
                    distanceMeters: pair.distance,
                    fallbackCoordinate: pinCoordinate
                )
            }
            let result = MapTapPOIResult.ambiguous(candidates: Array(capped))
            Self.poiDebugTrace(
                "keywordRecover OUT \(Self.poiDebugDescribeResult(result)) (always list when 2+ candidates; pin=tap)"
            )
            return result
        }

        let name = first.place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = MapTapPOIResult.single(
            name: name,
            category: first.place.poiCategoryRaw,
            coordinate: pinCoordinate
        )
        Self.poiDebugTrace(
            "keywordRecover OUT \(Self.poiDebugDescribeResult(result)) nearestDoc=\(Int(first.distance))m pin=tap(not Kakao centroid)"
        )
        return result
    }

    // MARK: - Direct POI building-name resolution

    /// For direct tile POI taps, resolves the POI by using Kakao coord2address `building_name` as a keyword.
    /// When the user taps a basemap POI icon the coordinate lands on (or very near) the POI itself, so
    /// `road_address.building_name` is the canonical name — uncategorized heritage sites (category_group_code "")
    /// that are invisible to category search are found reliably this way.
    private func tryDirectPOIBuildingNameSearch(near coordinate: CLLocationCoordinate2D) async -> MapTapPOIResult? {
        guard activeProvider == .kakao, KakaoLocalService.shared.isAvailable else { return nil }
        guard let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coordinate) else {
            Self.poiDebugTrace("buildingName SKIP: coord2address returned nil")
            return nil
        }
        // Use building_name directly — bestPlaceName can fall back to road/lot address strings.
        let buildingName = doc.road_address?.building_name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !buildingName.isEmpty else {
            Self.poiDebugTrace("buildingName SKIP: building_name empty")
            return nil
        }
        if Self.kakaoMapTapPOINameIsExcluded(buildingName) {
            Self.poiDebugTrace("buildingName SKIP: excluded building_name '\(buildingName)' → use nearby list")
            return nil
        }
        if Self.kakaoMapTapPOINameIsSubFacility(buildingName) {
            Self.poiDebugTrace("buildingName SKIP: sub-facility building_name '\(buildingName)' → landmark/nearby list")
            return nil
        }
        Self.poiDebugTrace("buildingName TRY '\(buildingName)'")

        let radius = 600
        // Prefer AT4 (attractions) and CT1 (cultural) to avoid name-collision with nearby commercial POIs.
        async let at4 = KakaoLocalService.shared.searchPlaces(
            query: buildingName, near: coordinate, radius: radius, categoryGroupCode: "AT4")
        async let ct1 = KakaoLocalService.shared.searchPlaces(
            query: buildingName, near: coordinate, radius: radius, categoryGroupCode: "CT1")
        var byId: [String: KakaoPlace] = [:]
        for p in await at4 + (await ct1) { if byId[p.id] == nil { byId[p.id] = p } }
        var places = Array(byId.values)
        if places.isEmpty {
            // Uncategorized POIs (category_group_code == "") need an unfiltered keyword search.
            places = await KakaoLocalService.shared.searchPlaces(query: buildingName, near: coordinate, radius: radius)
            Self.poiDebugTrace("buildingName unfiltered fallback n=\(places.count)")
        }

        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Self.poiDebugDumpPlaces(prefix: "buildingName '\(buildingName)'", places: places, tapLoc: tapLoc, limit: 8)

        let nearby: [(KakaoPlace, Double)] = places.compactMap { place in
            guard !Self.kakaoMapTapPlaceIsExcluded(place) else { return nil }
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let d = place.distanceMetersFromAPI
                ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard d <= Double(radius) else { return nil }
            return (place, d)
        }.sorted { $0.1 < $1.1 }

        guard let (place, dist) = nearby.first else {
            // No Kakao Local keyword match nearby — use building_name directly.
            // coord2address building_name is Kakao's canonical structure name (not an address string),
            // so it is a reliable POI name even without a corroborating keyword-search hit.
            Self.poiDebugTrace("buildingName OUT direct '\(buildingName)' (no keyword match within \(radius)m)")
            return .single(name: buildingName, category: nil, coordinate: coordinate)
        }
        let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.kakaoMapTapPOINameIsExcluded(name) {
            Self.poiDebugTrace("buildingName SKIP: nearest keyword hit is excluded '\(name)'")
            return nil
        }
        if Self.kakaoMapTapPOINameIsSubFacility(name) {
            Self.poiDebugTrace("buildingName SKIP: nearest keyword hit is sub-facility '\(name)'")
            return nil
        }
        if nearby.count >= 2 {
            let candidates = nearby.prefix(8).map { place, d in
                MapTapPOICandidate.from(
                    kakaoPlace: place,
                    distanceMeters: d,
                    fallbackCoordinate: coordinate
                )
            }
            Self.poiDebugTrace("buildingName OUT ambiguous(\(candidates.count)) for '\(buildingName)'")
            return .ambiguous(candidates: Array(candidates))
        }
        Self.poiDebugTrace("buildingName OUT single '\(name)' dist=\(Int(dist))m cat=\(place.category_group_code)")
        return .single(name: name, category: place.poiCategoryRaw, coordinate: coordinate)
    }

    /// FD6 ∪ CE7 search radius vs landmarks (meters); 80m missed many 카페/식당 Kakao centroid offsets from the tile tap.
    private static let kakaoDiningProximityCompareRadiusMeters: Int = 240

    /// AT4/CT1-only resolution when landmarks beat nearby dining on raw distance; otherwise `nil` so the
    /// usual multi-category ranking runs (cafés, transit, etc.).
    private func tryLandmarkProximityBiasedKakaoTap(
        coordinate: CLLocationCoordinate2D,
        isDirectPOITap: Bool
    ) async -> MapTapPOIResult? {
        guard activeProvider == .kakao, KakaoLocalService.shared.isAvailable else { return nil }

        // tryDirectPOIBuildingNameSearch already handled the clear building-name case.
        // Run landmark bias for both direct and terrain taps; the dining proximity guard below
        // prevents a distant AT4 from stealing a restaurant tile POI tap.

        let landmarkRadius = Self.kakaoLandmarkIdentitySearchRadiusMeters(isDirectPOITap: isDirectPOITap)
        let landmarks = await KakaoLocalService.shared.searchLandmarkPlacesNear(
            coordinate: coordinate,
            radius: landmarkRadius
        )
        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Self.poiDebugTrace("landmark-bias START radius=\(landmarkRadius)m (AT4 ∪ CT1)")
        Self.poiDebugDumpPlaces(prefix: "landmark-bias candidates", places: landmarks, tapLoc: tapLoc, limit: 15)

        guard !landmarks.isEmpty else {
            debugPrint("[POI] landmark bias: no AT4/CT1 within \(landmarkRadius)m")
            Self.poiDebugTrace("landmark-bias SKIP: zero API results → fall through to multi-category")
            return nil
        }

        let foods = await KakaoLocalService.shared.searchDiningPlacesNear(
            coordinate: coordinate,
            radius: Self.kakaoDiningProximityCompareRadiusMeters
        )
        Self.poiDebugDumpPlaces(prefix: "landmark-bias dining (FD6 ∪ CE7) compare r=\(Self.kakaoDiningProximityCompareRadiusMeters)m", places: foods, tapLoc: tapLoc, limit: 8)

        func rawLandmarkDistance(to place: KakaoPlace) -> Double? {
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let d = place.distanceMetersFromAPI
                ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard d <= Double(landmarkRadius) else { return nil }
            return d
        }

        let scoredLandmarks: [(place: KakaoPlace, rawMeters: Double, sortMeters: Double)] = landmarks.compactMap { place in
            guard let d = rawLandmarkDistance(to: place) else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sortDist = Self.kakaoMapTapLandmarkSortDistance(rawMeters: d, placeName: name)
            return (place, d, sortDist)
        }
        .sorted { $0.sortMeters < $1.sortMeters }

        if !landmarks.isEmpty && scoredLandmarks.isEmpty {
            Self.poiDebugTrace(
                "landmark-bias WARNING: \(landmarks.count) API rows but NONE pass distance≤\(landmarkRadius)m — POI/registry offset or distance calc mismatch"
            )
            Self.poiDebugDumpPlaces(prefix: "landmark-bias unscored snapshot", places: landmarks, tapLoc: tapLoc, limit: 20)
        }

        guard let nearestRawLandmarkDist = scoredLandmarks.first?.rawMeters else {
            Self.poiDebugTrace("landmark-bias SKIP: no scored landmarks → fall through")
            return nil
        }

        let minFoodDist: Double = foods.compactMap { rawFoodDistanceForLandmarkBias(to: $0, tapLoc: tapLoc) }.min() ?? .infinity

        let foodLabel = minFoodDist.isInfinite ? "none" : "\(Int(minFoodDist))"
        let threshold = nearestRawLandmarkDist + Self.landmarkOverDiningProximityGapMeters
        Self.poiDebugTrace(
            "landmark-bias compare nearestLandmark=\(Int(nearestRawLandmarkDist))m + gap\(Int(Self.landmarkOverDiningProximityGapMeters))m=\(Int(threshold))m vs nearestFood=\(foodLabel) → \(threshold < minFoodDist ? "TAKE landmark-only" : "SKIP (dining wins proximity)")"
        )

        guard nearestRawLandmarkDist + Self.landmarkOverDiningProximityGapMeters < minFoodDist else {
            debugPrint("[POI] landmark bias skipped (dining as close or closer: food=\(foodLabel)m landmark=\(Int(nearestRawLandmarkDist))m)")
            Self.poiDebugTrace("landmark-bias SKIP: dining too close · \(Self.poiDebugWatchHits(places: landmarks, tapLoc: tapLoc))")
            return nil
        }

        debugPrint("[POI] landmark bias: resolving from AT4/CT1 only (landmark=\(Int(nearestRawLandmarkDist))m vs food=\(minFoodDist.isInfinite ? "∞" : "\(Int(minFoodDist))")m)")

        let allDebug: [DebugPOIEntry] = (scoredLandmarks.map { pair in
            DebugPOIEntry(name: pair.place.place_name, categoryCode: pair.place.category_group_code,
                          rawDistanceMeters: pair.rawMeters, effectiveDistanceMeters: pair.sortMeters)
        } + foods.compactMap { place -> DebugPOIEntry? in
            guard let d = rawFoodDistanceForLandmarkBias(to: place, tapLoc: tapLoc) else { return nil }
            return DebugPOIEntry(name: place.place_name, categoryCode: place.category_group_code,
                                 rawDistanceMeters: d, effectiveDistanceMeters: d)
        })
        .sorted { $0.rawDistanceMeters < $1.rawDistanceMeters }

        await MainActor.run {
            debugLastTapCoordinate = coordinate
            debugPOICandidates = Array(allDebug.prefix(50))
        }

        let rawScored = scoredLandmarks.map { ($0.place, $0.rawMeters) }
        return mapTapResultFromScoredKakaoPlacesRawDistance(scored: rawScored, fallbackCoordinate: coordinate)
    }

    private func rawFoodDistanceForLandmarkBias(to place: KakaoPlace, tapLoc: CLLocation) -> Double? {
        guard let coord = place.coordinate else { return nil }
        let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let d = place.distanceMetersFromAPI
            ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        guard d <= Double(Self.kakaoDiningProximityCompareRadiusMeters) else { return nil }
        return d
    }

    /// Single vs ambiguous tap using **raw** distances (for landmark-only cohorts).
    private func mapTapResultFromScoredKakaoPlacesRawDistance(
        scored: [(place: KakaoPlace, distance: Double)],
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> MapTapPOIResult {
        guard let first = scored.first else {
            Self.poiDebugTrace("landmark-bias OUT none (empty scored list)")
            return .none
        }
        // Wider than map-tap: terrain landmark cohort is smaller; clearer disambiguation without hiding choices.
        let ambiguousGapMeters: Double = 36
        let gapToSecond = scored.count >= 2 ? scored[1].distance - first.distance : .greatestFiniteMagnitude

        if scored.count >= 2, gapToSecond < ambiguousGapMeters {
            let capped = scored.prefix(8).map { pair in
                MapTapPOICandidate.from(
                    kakaoPlace: pair.place,
                    distanceMeters: pair.distance,
                    fallbackCoordinate: fallbackCoordinate
                )
            }
            debugPrint("[POI] landmark bias ambiguous: \(capped.count) candidates (gap \(Int(gapToSecond))m)")
            let result = MapTapPOIResult.ambiguous(candidates: Array(capped))
            Self.poiDebugTrace("landmark-bias OUT \(Self.poiDebugDescribeResult(result)) gap=\(Int(gapToSecond))m")
            return result
        }

        let name = first.place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            Self.poiDebugTrace("landmark-bias OUT none (empty name)")
            return .none
        }
        debugPrint("[POI] landmark bias single '\(name)' dist=\(Int(first.distance))m")
        let registrationFar = first.distance > Self.landmarkBiasPreferTapIfRegistrationBeyondMeters
        let pinCoordinate = registrationFar ? fallbackCoordinate : (first.place.coordinate ?? fallbackCoordinate)
        let result = MapTapPOIResult.single(
            name: name,
            category: first.place.poiCategoryRaw,
            coordinate: pinCoordinate
        )
        Self.poiDebugTrace(
            "landmark-bias OUT \(Self.poiDebugDescribeResult(result)) rawDist=\(Int(first.distance))m pin=\(registrationFar ? "tap" : "Kakao")"
        )
        return result
    }

    /// Resolves a map tap in Korea to a named place using Kakao category search (parallel category queries),
    /// mirroring `resolveMapTapPOI` semantics: single hit, ambiguous list, or `.none` for address fallback.
    func resolveKakaoMapTapPOI(
        near coordinate: CLLocationCoordinate2D,
        kakaoZoomLevel: Int,
        isDirectPOITap: Bool = false
    ) async -> MapTapPOIResult {
        guard activeProvider == .kakao, KakaoLocalService.shared.isAvailable else {
            debugPrint("[POI] resolveKakaoMapTapPOI skipped (not Kakao or REST key missing)")
            return .none
        }
        Self.poiDebugTapHeader(coordinate: coordinate, kakaoZoomLevel: kakaoZoomLevel, isDirectPOITap: isDirectPOITap)

        // Direct tile POI taps: the tap coordinate lands on the POI itself, so coord2address building_name
        // is the fastest and most accurate identifier — catches heritage sites and uncategorized POIs
        // (category_group_code "") that are invisible to the category fan-out below.
        if isDirectPOITap {
            if let buildingResult = await tryDirectPOIBuildingNameSearch(near: coordinate) {
                Self.poiDebugTrace("resolution FINAL path=buildingName \(Self.poiDebugDescribeResult(buildingResult))")
                return buildingResult
            }
            Self.poiDebugTrace("resolution buildingName skipped → continuing")
        }

        if let landmarkResult = await tryLandmarkProximityBiasedKakaoTap(
            coordinate: coordinate,
            isDirectPOITap: isDirectPOITap
        ) {
            Self.poiDebugTrace(
                "resolution FINAL path=landmarkBias \(Self.poiDebugDescribeResult(landmarkResult))"
            )
            return landmarkResult
        }

        Self.poiDebugTrace("resolution landmarkBias skipped · continuing multi-category tier")

        if let kwRecover = await tryDirectTapKeywordHistoricRecover(near: coordinate, isDirectPOITap: isDirectPOITap) {
            Self.poiDebugTrace(
                "resolution FINAL path=keywordHistoricRecover \(Self.poiDebugDescribeResult(kwRecover))"
            )
            return kwRecover
        }
        Self.poiDebugTrace("resolution keywordHistoricRecover skipped")

        let strictRadius = Self.kakaoTapRadiusMeters(zoomLevel: kakaoZoomLevel)
        debugPrint("[POI] resolveKakaoMapTapPOI radius=\(strictRadius)m zoom=\(kakaoZoomLevel) directPOI=\(isDirectPOITap)")

        func attempt(radius: Int) async -> MapTapPOIResult {
            let places = await KakaoLocalService.shared.searchNearbyPlacesForMapTap(
                coordinate: coordinate,
                radius: radius,
                isDirectPOITap: isDirectPOITap
            )
            let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

            Self.poiDebugTrace(
                "multiCategory attempt R=\(radius)m merged=\(places.count) \(Self.poiDebugWatchHits(places: places, tapLoc: tapLocation))"
            )
            Self.poiDebugDumpPlaces(
                prefix: "multiCategory R=\(radius)m sample",
                places: places,
                tapLoc: tapLocation,
                limit: 10
            )

            let scored = kakaoScorePlacesForMapTap(
                places: places,
                coordinate: coordinate,
                searchRadius: radius,
                isDirectPOITap: isDirectPOITap
            )

            await MainActor.run {
                self.debugLastTapCoordinate = coordinate
                self.debugPOICandidates = scored.prefix(50).map { row in
                    DebugPOIEntry(
                        name: row.place.place_name,
                        categoryCode: row.place.category_group_code,
                        rawDistanceMeters: row.rawDistanceMeters,
                        effectiveDistanceMeters: row.effectiveDistanceMeters
                    )
                }
            }

            for (i, row) in scored.prefix(12).enumerated() {
                Self.poiDebugTrace(
                    "  rank#\(i + 1) eff=\(Int(row.effectiveDistanceMeters))m raw=\(Int(row.rawDistanceMeters))m · \(row.place.place_name) [\(row.place.category_group_code)]"
                )
            }

            guard let first = scored.first else {
                debugPrint("[POI] resolveKakaoMapTapPOI: no named place within radius=\(radius)m")
                Self.poiDebugTrace("multiCategory R=\(radius)m OUT none (no scored within radius)")
                return .none
            }

            // On effective-distance scale, cafés/restaurants separated by tens of metres often want a chooser —
            // 12 would auto-pick a single café too aggressively.
            let ambiguousGapMeters: Double = 38
            let gapToSecond = scored.count >= 2
                ? scored[1].effectiveDistanceMeters - first.effectiveDistanceMeters
                : Double.greatestFiniteMagnitude

            if scored.count >= 2, gapToSecond < ambiguousGapMeters {
                let capped = mapTapCandidates(from: scored, fallbackCoordinate: coordinate, limit: 20)
                debugPrint("[POI] Kakao ambiguous tap: \(capped.count) candidates (gap \(Int(gapToSecond))m)")
                let result = MapTapPOIResult.ambiguous(candidates: capped)
                Self.poiDebugTrace("multiCategory R=\(radius)m OUT \(Self.poiDebugDescribeResult(result)) gap=\(Int(gapToSecond))m")
                return result
            }

            let name = first.place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                Self.poiDebugTrace("multiCategory R=\(radius)m OUT none (winner name empty)")
                return .none
            }
            debugPrint("[POI] Kakao single place '\(name)' dist=\(Int(first.rawDistanceMeters))m radius=\(radius)m")
            let result = MapTapPOIResult.single(
                name: name,
                category: first.place.poiCategoryRaw,
                coordinate: first.place.coordinate ?? coordinate
            )
            Self.poiDebugTrace("multiCategory R=\(radius)m OUT \(Self.poiDebugDescribeResult(result)) winnerEffDist=\(Int(first.effectiveDistanceMeters))m")
            return result
        }

        let strict = await attempt(radius: strictRadius)
        Self.poiDebugTrace(
            "resolution strict R=\(strictRadius)m → \(Self.poiDebugDescribeResult(strict))"
        )
        if case .none = strict {
            let wide = max(Self.kakaoWidePOIFallbackRadiusMeters, strictRadius)
            debugPrint("[POI] resolveKakaoMapTapPOI strict empty → retrying wideRadius=\(wide)m")
            let wideResult = await attempt(radius: wide)
            Self.poiDebugTrace(
                "resolution wide R=\(wide)m → \(Self.poiDebugDescribeResult(wideResult))"
            )
            if case .none = wideResult {
                // Third tier: when category-group coverage fails, try a keyword search using Kakao's
                // own coord2address "bestPlaceName". For many landmarks this is the actual POI name
                // (not a street address). This catches famous sites that are misgrouped or missing
                // from our category fan-out.
                if let coordNameResult = await coord2AddressNameKeywordSearch(near: coordinate, radius: wide) {
                    Self.poiDebugTrace(
                        "resolution FINAL path=coord2addressKeyword \(Self.poiDebugDescribeResult(coordNameResult))"
                    )
                    return coordNameResult
                }

                // Fourth tier: places with empty category_group_code (e.g. 동궁과월지) are invisible to
                // category search. Use coord2regioncode to get the statutory neighbourhood name, then
                // keyword-search for it — Kakao keyword search matches address fields.
                debugPrint("[POI] resolveKakaoMapTapPOI wide empty → trying neighbourhood keyword search")
                let neighbourhood = await neighbourhoodKeywordSearch(near: coordinate, radius: wide)
                Self.poiDebugTrace(
                    "resolution FINAL path=neighbourhoodKeyword \(Self.poiDebugDescribeResult(neighbourhood))"
                )
                return neighbourhood
            }
            Self.poiDebugTrace(
                "resolution FINAL path=multiCategory-wide \(Self.poiDebugDescribeResult(wideResult))"
            )
            return wideResult
        }
        Self.poiDebugTrace(
            "resolution FINAL path=multiCategory-strict \(Self.poiDebugDescribeResult(strict))"
        )
        return strict
    }

    /// Attempts to recover a POI name when Kakao category searches return nothing by using Kakao's
    /// coord2address bestPlaceName as a keyword query near the tap coordinate.
    private func coord2AddressNameKeywordSearch(near coordinate: CLLocationCoordinate2D, radius: Int) async -> MapTapPOIResult? {
        guard let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coordinate) else { return nil }
        let raw = doc.bestPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !Self.kakaoNameLooksLikeAddress(raw) else {
            debugPrint("[POI] coord2AddressNameKeywordSearch skipped (name looks like address): '\(raw)'")
            Self.poiDebugTrace("coord2address-keyword SKIP (address-like or empty) bestPlaceName='\(raw)'")
            return nil
        }

        let searchRadius = min(max(150, radius), 1200)
        debugPrint("[POI] coord2AddressNameKeywordSearch '\(raw)' radius=\(searchRadius)m")

        // Keyword + category_group_code prefers tourist/cultural IDs (AT4/CT1) when the coord2address
        // string is ambiguous; Kakao keyword search still requires a non-empty query.
        let at4 = await KakaoLocalService.shared.searchPlaces(
            query: raw, near: coordinate, radius: searchRadius, categoryGroupCode: "AT4")
        let ct1 = await KakaoLocalService.shared.searchPlaces(
            query: raw, near: coordinate, radius: searchRadius, categoryGroupCode: "CT1")
        var byId: [String: KakaoPlace] = [:]
        for place in at4 + ct1 { if byId[place.id] == nil { byId[place.id] = place } }
        var places = Array(byId.values)
        if places.isEmpty {
            places = await KakaoLocalService.shared.searchPlaces(query: raw, near: coordinate, radius: searchRadius)
        }
        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Self.poiDebugTrace(
            "coord2address-keyword query='\(raw)' radius=\(searchRadius)m merged=\(places.count) \(Self.poiDebugWatchHits(places: places, tapLoc: tapLoc))"
        )
        Self.poiDebugDumpPlaces(
            prefix: "coord2address-keyword picks",
            places: places,
            tapLoc: tapLoc,
            limit: 12
        )

        let nearby: [(KakaoPlace, Double)] = places.compactMap { place in
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let dist = place.distanceMetersFromAPI
                ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard dist <= Double(searchRadius) else { return nil }
            return (place, dist)
        }
        .sorted { $0.1 < $1.1 }

        guard let (place, dist) = nearby.first else {
            debugPrint("[POI] coord2AddressNameKeywordSearch '\(raw)': no result within \(searchRadius)m")
            Self.poiDebugTrace("coord2address-keyword no hit within radius (watch: \(Self.poiDebugWatchHits(places: places, tapLoc: tapLoc)))")
            return nil
        }
        let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        debugPrint("[POI] coord2AddressNameKeywordSearch '\(raw)' → '\(name)' dist=\(Int(dist))m")
        return .single(name: name, category: place.poiCategoryRaw, coordinate: place.coordinate ?? coordinate)
    }

    private static func kakaoNameLooksLikeAddress(_ name: String) -> Bool {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        // Street addresses always include digits (e.g. "테헤란로 152")
        if s.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        // Road-name suffixes at the END of a short string (e.g. "강남대로", "삼성로", "인왕동로")
        // A POI name that merely contains "로" mid-word (e.g. "로마네 카페", "동궁과월지") must NOT be blocked.
        let roadSuffixes = ["대로", "번길", "로", "길"]
        for suffix in roadSuffixes where s.hasSuffix(suffix) && s.count <= 12 { return true }
        // Short administrative unit names ending in admin suffixes (e.g. "황남동", "안동면")
        let adminSuffixes = ["동", "리", "읍", "면", "번지"]
        for suffix in adminSuffixes where s.hasSuffix(suffix) && s.count <= 6 { return true }
        return false
    }

    /// Resolves a coordinate to a named place by using the statutory neighbourhood name (법정동) as a
    /// keyword query. Kakao keyword search matches address fields, so uncategorized places (group code "")
    /// whose lot address contains the neighbourhood name will appear even though category search misses them.
    private func neighbourhoodKeywordSearch(near coordinate: CLLocationCoordinate2D, radius: Int) async -> MapTapPOIResult {
        guard let region = await KakaoLocalService.shared.reverseGeocodeToRegionCode(coordinate: coordinate) else {
            debugPrint("[POI] neighbourhoodKeywordSearch: no region code")
            return .none
        }
        // Use the most specific non-empty level: 3rd depth (dong) > 2nd depth (city/gu)
        let keyword = [region.region_3depth_name, region.region_2depth_name]
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        guard !keyword.isEmpty else { return .none }

        let searchRadius = min(radius, 300)
        debugPrint("[POI] neighbourhoodKeywordSearch '\(keyword)' radius=\(searchRadius)m")

        let places = await KakaoLocalService.shared.searchPlaces(query: keyword, near: coordinate, radius: searchRadius)
        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Self.poiDebugTrace(
            "neighbourhood-keyword '\(keyword)' r=\(searchRadius)m n=\(places.count) \(Self.poiDebugWatchHits(places: places, tapLoc: tapLoc))"
        )
        Self.poiDebugDumpPlaces(prefix: "neighbourhood-keyword", places: places, tapLoc: tapLoc, limit: 12)

        let nearby: [(KakaoPlace, Double)] = places.compactMap { place in
            guard let coord = place.coordinate else { return nil }
            let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let dist = place.distanceMetersFromAPI
                ?? tapLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            guard dist <= Double(searchRadius) else { return nil }
            return (place, dist)
        }
        .sorted { $0.1 < $1.1 }

        guard let (place, dist) = nearby.first else {
            debugPrint("[POI] neighbourhoodKeywordSearch '\(keyword)': no result within \(searchRadius)m")
            return .none
        }
        let name = place.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
        debugPrint("[POI] neighbourhoodKeywordSearch '\(keyword)' → '\(name)' dist=\(Int(dist))m")
        return .single(name: name, category: place.poiCategoryRaw, coordinate: place.coordinate ?? coordinate)
    }

    // MARK: - Category helpers (MapKit)

    /// Resolves POI category at a coordinate by searching for the place name in a small region.
    func fetchCategory(at coordinate: CLLocationCoordinate2D, name: String) async -> String? {
        guard !name.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let mapItem = response.mapItems.first else {
            debugPrint("[Category] fetchCategory '\(name)' → nil")
            return nil
        }
        let raw = mapItem.pointOfInterestCategory?.rawValue
        debugPrint("[Category] fetchCategory '\(name)' → \(raw ?? "nil")")
        return raw
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard activeProvider == .mapKit else { return }
        suggestions = completer.results.map { completion in
            PlaceSuggestion(
                id: "\(completion.title)|\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle,
                source: .mapKit(completion)
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
