//
//  KakaoLocalService.swift
//  fastblog
//
//  Wraps the Kakao Local REST API for place keyword search and reverse geocoding.
//  Used as a replacement for MKLocalSearchCompleter / CLGeocoder when the place
//  coordinate is in South Korea (isoCountryCode == "KR").
//
//  Setup:
//    1. Register at https://developers.kakao.com and create an app.
//    2. Add KAKAO_REST_API_KEY = <your key> to Secrets.xcconfig (not committed).
//    3. Info.plist already exposes it as KakaoRestApiKey via $(KAKAO_REST_API_KEY).
//

import CoreLocation
import Foundation
import MapKit

// MARK: - Response models

struct KakaoSearchResponse: Decodable {
    let documents: [KakaoPlace]
}

struct KakaoPlace: Decodable {
    let id: String
    let place_name: String
    let category_name: String
    let category_group_code: String
    let address_name: String
    let road_address_name: String
    /// Longitude string (Kakao uses x = longitude, y = latitude)
    let x: String
    /// Latitude string
    let y: String
    /// Meters from search center when `x`/`y`/`radius` (or category search center) are used; may be absent.
    let distance: String?

    enum CodingKeys: String, CodingKey {
        case id, place_name, category_name, category_group_code, address_name, road_address_name, x, y, distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        place_name = try c.decode(String.self, forKey: .place_name)
        category_name = try c.decodeIfPresent(String.self, forKey: .category_name) ?? ""
        category_group_code = try c.decodeIfPresent(String.self, forKey: .category_group_code) ?? ""
        address_name = try c.decodeIfPresent(String.self, forKey: .address_name) ?? ""
        road_address_name = try c.decodeIfPresent(String.self, forKey: .road_address_name) ?? ""
        x = try c.decode(String.self, forKey: .x)
        y = try c.decode(String.self, forKey: .y)
        if let s = try c.decodeIfPresent(String.self, forKey: .distance) {
            distance = s
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .distance) {
            distance = String(i)
        } else if let d = try c.decodeIfPresent(Double.self, forKey: .distance) {
            distance = String(format: "%.0f", d)
        } else {
            distance = nil
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(y), let lon = Double(x) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Distance to the reference point when Kakao returned `distance` (meters).
    var distanceMetersFromAPI: Double? {
        guard let distance, let m = Double(distance) else { return nil }
        return m
    }

    /// Road address preferred over lot address for display.
    var displaySubtitle: String {
        road_address_name.isEmpty ? address_name : road_address_name
    }

    /// Maps Kakao category fields to an MKPointOfInterestCategory raw value.
    /// Uses category_group_code for the coarse type, then narrows AT4 (tourist attractions)
    /// via the hierarchical category_name string (e.g. "관광명소 > 해변" → beach).
    var poiCategoryRaw: String? {
        switch category_group_code {
        case "FD6": return MKPointOfInterestCategory.restaurant.rawValue
        case "CE7": return MKPointOfInterestCategory.cafe.rawValue
        case "HP8": return MKPointOfInterestCategory.hospital.rawValue
        case "PM9": return MKPointOfInterestCategory.pharmacy.rawValue
        case "BK9": return MKPointOfInterestCategory.bank.rawValue
        case "OL7": return MKPointOfInterestCategory.gasStation.rawValue
        case "PK6": return MKPointOfInterestCategory.parking.rawValue
        case "AD5": return MKPointOfInterestCategory.hotel.rawValue
        case "CT1": return MKPointOfInterestCategory.museum.rawValue
        case "SC4": return MKPointOfInterestCategory.school.rawValue
        case "CS2": return MKPointOfInterestCategory.store.rawValue
        case "MT1": return MKPointOfInterestCategory.foodMarket.rawValue
        case "SW8": return MKPointOfInterestCategory.publicTransport.rawValue
        case "AT4": return Self.refinedAttractionCategory(from: category_name)
        default: return nil
        }
    }

    /// Narrows Kakao AT4 (관광명소) to a more specific MKPointOfInterestCategory
    /// by inspecting the Korean subcategory tokens in category_name.
    private static func refinedAttractionCategory(from categoryName: String) -> String {
        let name = categoryName
        if name.contains("해변") || name.contains("해수욕장") {
            return MKPointOfInterestCategory.beach.rawValue
        }
        if name.contains("국립공원") {
            return MKPointOfInterestCategory.nationalPark.rawValue
        }
        if name.contains("공원") || name.contains("자연") {
            return MKPointOfInterestCategory.park.rawValue
        }
        if name.contains("수족관") {
            return MKPointOfInterestCategory.aquarium.rawValue
        }
        if name.contains("동물원") {
            return MKPointOfInterestCategory.zoo.rawValue
        }
        if name.contains("경기장") || name.contains("스타디움") {
            return MKPointOfInterestCategory.stadium.rawValue
        }
        if name.contains("문화유적") || name.contains("유적") || name.contains("랜드마크") {
            return "MKPOICategoryLandmark"
        }
        return MKPointOfInterestCategory.amusementPark.rawValue
    }
}

struct KakaoCoord2AddressResponse: Decodable {
    let documents: [KakaoCoord2AddressDoc]
}

struct KakaoCoord2AddressDoc: Decodable {
    let road_address: KakaoRoadAddress?
    let address: KakaoLotAddress?

    /// Best human-readable name: building name > road address > lot address.
    var bestPlaceName: String {
        if let road = road_address {
            if !road.building_name.isEmpty { return road.building_name }
            if !road.address_name.isEmpty { return road.address_name }
        }
        return address?.address_name ?? ""
    }
}

struct KakaoRoadAddress: Decodable {
    let address_name: String
    let building_name: String
}

struct KakaoLotAddress: Decodable {
    let address_name: String
}

struct KakaoRegionResponse: Decodable {
    let documents: [KakaoRegionDoc]
}

/// One administrative-area document from `/v2/local/geo/coord2regioncode.json`.
/// `region_type` is "B" (법정동 — statutory, used in addresses) or "H" (행정동 — administrative).
struct KakaoRegionDoc: Decodable {
    let region_type: String
    let address_name: String
    let region_1depth_name: String
    let region_2depth_name: String
    let region_3depth_name: String
    let x: Double
    let y: Double
}

// MARK: - Service

actor KakaoLocalService {
    static let shared = KakaoLocalService()

    /// The REST API key read from Info.plist (injected via Secrets.xcconfig).
    nonisolated let apiKey: String

    /// Returns false when the API key is absent or is the unexpanded xcconfig placeholder.
    nonisolated var isAvailable: Bool {
        !apiKey.isEmpty && apiKey != "$(KAKAO_REST_API_KEY)"
    }

    private let session = URLSession.shared

    private init() {
        apiKey = Bundle.main.object(forInfoDictionaryKey: "KakaoRestApiKey") as? String ?? ""
    }

    // MARK: - Keyword search

    /// Returns up to 15 places matching `query`, sorted by `sort` from `coordinate` when provided.
    /// When `categoryGroupCode` is set, Kakao restricts keyword matches to that group (e.g. AT4 landmarks).
    /// `sort` must be `"distance"` (default, requires coordinate) or `"accuracy"` (text-relevance, ignores radius).
    func searchPlaces(
        query: String,
        near coordinate: CLLocationCoordinate2D?,
        radius: Int = 5000,
        categoryGroupCode: String? = nil,
        sort: String = "distance"
    ) async -> [KakaoPlace] {
        guard isAvailable, !query.isEmpty else { return [] }

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            // Kakao caps keyword page size at 15; nearer POIs can push the true landmark out when size=10.
            URLQueryItem(name: "size", value: coordinate != nil ? "15" : "10")
        ]
        if let code = categoryGroupCode, !code.isEmpty {
            items.append(URLQueryItem(name: "category_group_code", value: code))
        }
        if let coord = coordinate {
            items += [
                URLQueryItem(name: "x", value: String(coord.longitude)),
                URLQueryItem(name: "y", value: String(coord.latitude)),
                URLQueryItem(name: "radius", value: String(radius)),
                URLQueryItem(name: "sort", value: sort)
            ]
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await session.data(for: request),
              let response = try? JSONDecoder().decode(KakaoSearchResponse.self, from: data) else {
            debugPrint("[Kakao] searchPlaces('\(query)') failed or no results")
            return []
        }
        debugPrint("[Kakao] searchPlaces('\(query)') → \(response.documents.count) results")
        for place in response.documents {
            debugPrint("[Kakao] category  '\(place.place_name)'  group=\(place.category_group_code)  name='\(place.category_name)'  → poi=\(place.poiCategoryRaw ?? "nil")")
        }
        return response.documents
    }

    // MARK: - Category search (nearby POIs for map taps)

    /// Kakao Local `/v2/local/search/category.json` codes: MT1, CS2, PK6, OL7, SW8, BK9, CT1, PO3, AT4, AD5, FD6, CE7, HP8, PM9, …
    ///
    /// Map taps use **two tiers** merged into one candidate pool:
    /// 1. **Landmark tier** — large / “popular” POIs (AT4, CT1, PO3) with **wider radii** so registry offset does not drop 첨성대-class sites.
    /// 2. **Amenity tier** — small venue categories **tied to map zoom radius** (food, café, stay, transit, etc.).
    static let mapTapLandmarkCategoryCodes: [String] = [
        "AT4",  // tourist attractions
        "CT1",  // cultural facilities
        "PO3",  // public institutions (palaces, offices, some heritage-adjacent rows)
    ]
    static let mapTapAmenityCategoryCodes: [String] = [
        "FD6",  // restaurants
        "CE7",  // cafes
        "AD5",  // accommodations
        "CS2",  // convenience stores
        "MT1",  // supermarkets
        "SW8",  // subway stations
        "PK6",  // parking
        "OL7",  // gas / charging
        "BK9",  // banks
        "HP8",  // hospitals
        "PM9",  // pharmacies
    ]
    /// All codes queried across both tiers (deduped merge); preserved for tooling / clarity.
    static var categoryGroupCodesForMapTap: [String] {
        mapTapLandmarkCategoryCodes + mapTapAmenityCategoryCodes
    }

    /// Places of one category within `radius` meters of `coordinate` (sorted by distance when supported).
    func searchPlacesByCategory(
        categoryGroupCode: String,
        coordinate: CLLocationCoordinate2D,
        radius: Int,
        size: Int = 15
    ) async -> [KakaoPlace] {
        guard isAvailable else { return [] }

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/category.json")!
        components.queryItems = [
            URLQueryItem(name: "category_group_code", value: categoryGroupCode),
            URLQueryItem(name: "x", value: String(coordinate.longitude)),
            URLQueryItem(name: "y", value: String(coordinate.latitude)),
            URLQueryItem(name: "radius", value: String(min(20_000, max(1, radius)))),
            URLQueryItem(name: "size", value: String(min(15, max(1, size)))),
            URLQueryItem(name: "sort", value: "distance")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await session.data(for: request),
              let response = try? JSONDecoder().decode(KakaoSearchResponse.self, from: data) else {
            debugPrint("[Kakao] searchPlacesByCategory(\(categoryGroupCode)) failed")
            return []
        }
        return response.documents
    }

    /// Parallel category queries; dedupes by place `id`.
    func searchPlacesUnionCategories(
        categoryGroupCodes: [String],
        coordinate: CLLocationCoordinate2D,
        radius: Int,
        size: Int = 15
    ) async -> [KakaoPlace] {
        guard isAvailable, !categoryGroupCodes.isEmpty else { return [] }
        let r = min(20_000, max(1, radius))
        return await withTaskGroup(of: [KakaoPlace].self) { group in
            for code in categoryGroupCodes {
                group.addTask {
                    await self.searchPlacesByCategory(
                        categoryGroupCode: code,
                        coordinate: coordinate,
                        radius: r,
                        size: size
                    )
                }
            }
            var byId: [String: KakaoPlace] = [:]
            for await chunk in group {
                for place in chunk {
                    if byId[place.id] == nil { byId[place.id] = place }
                }
            }
            return Array(byId.values)
        }
    }

    /// Tourist attractions (AT4) and cultural venues (CT1) within `radius`.
    func searchLandmarkPlacesNear(coordinate: CLLocationCoordinate2D, radius: Int) async -> [KakaoPlace] {
        await searchPlacesUnionCategories(
            categoryGroupCodes: ["AT4", "CT1"],
            coordinate: coordinate,
            radius: radius
        )
    }

    /// Restaurants and cafés within `radius`, for comparing proximity against landmarks.
    func searchDiningPlacesNear(coordinate: CLLocationCoordinate2D, radius: Int) async -> [KakaoPlace] {
        await searchPlacesUnionCategories(
            categoryGroupCodes: ["FD6", "CE7"],
            coordinate: coordinate,
            radius: radius
        )
    }

    /// Landmark tier — stretch radius/size so big sites survive coordinate skew vs the map icon.
    private static func landmarkTierSearchParams(for code: String, baseRadius: Int, isDirectPOITap: Bool) -> (radius: Int, size: Int) {
        switch code {
        case "AT4":
            return (max(baseRadius, isDirectPOITap ? 900 : 520), 15)
        case "CT1":
            return (max(baseRadius, isDirectPOITap ? 720 : 450), 12)
        case "PO3":
            return (max(baseRadius, isDirectPOITap ? 520 : 360), 10)
        default:
            return (baseRadius, 10)
        }
    }

    /// Amenity tier — honour zoom-scaled search radius so cafés/restaurants stay distance-faithful.
    private static func amenityTierSearchParams(for code: String, baseRadius: Int, isDirectPOITap: Bool) -> (radius: Int, size: Int) {
        _ = isDirectPOITap
        switch code {
        case "FD6", "CE7":
            return (baseRadius, 12)
        case "AD5":
            return (baseRadius, 10)
        default:
            return (baseRadius, 8)
        }
    }

    private func searchMapTapCategoryTier(
        codes: [String],
        coordinate: CLLocationCoordinate2D,
        baseRadius: Int,
        isDirectPOITap: Bool,
        tier: MapTapCategoryTier
    ) async -> [KakaoPlace] {
        guard !codes.isEmpty else { return [] }
        return await withTaskGroup(of: [KakaoPlace].self) { group in
            for code in codes {
                group.addTask {
                    let (r, size): (Int, Int) = switch tier {
                    case .landmark:
                        Self.landmarkTierSearchParams(for: code, baseRadius: baseRadius, isDirectPOITap: isDirectPOITap)
                    case .amenity:
                        Self.amenityTierSearchParams(for: code, baseRadius: baseRadius, isDirectPOITap: isDirectPOITap)
                    }
                    return await self.searchPlacesByCategory(
                        categoryGroupCode: code,
                        coordinate: coordinate,
                        radius: r,
                        size: size
                    )
                }
            }
            var byId: [String: KakaoPlace] = [:]
            for await chunk in group {
                for place in chunk {
                    if byId[place.id] == nil { byId[place.id] = place }
                }
            }
            return Array(byId.values)
        }
    }

    private enum MapTapCategoryTier {
        case landmark
        case amenity
    }

    /// Dedupes by Kakao `id`. If a place appears in both tiers, keep the **landmark-tier** document (wider search may carry the canonical row).
    private static func mergeMapTapLandmarkAndAmenityTiers(landmarks: [KakaoPlace], amenities: [KakaoPlace]) -> [KakaoPlace] {
        var byId: [String: KakaoPlace] = [:]
        for p in amenities { byId[p.id] = p }
        for p in landmarks { byId[p.id] = p }
        return Array(byId.values)
    }

    /// Parallel **landmark** + **amenity** category fan-out, merged for `PlaceSearchViewModel` ranking / disambiguation.
    func searchNearbyPlacesForMapTap(
        coordinate: CLLocationCoordinate2D,
        radius: Int,
        isDirectPOITap: Bool = false
    ) async -> [KakaoPlace] {
        guard isAvailable else { return [] }

        let baseRadius = min(20_000, max(1, radius))
        async let landmarkRows = searchMapTapCategoryTier(
            codes: Self.mapTapLandmarkCategoryCodes,
            coordinate: coordinate,
            baseRadius: baseRadius,
            isDirectPOITap: isDirectPOITap,
            tier: .landmark
        )
        async let amenityRows = searchMapTapCategoryTier(
            codes: Self.mapTapAmenityCategoryCodes,
            coordinate: coordinate,
            baseRadius: baseRadius,
            isDirectPOITap: isDirectPOITap,
            tier: .amenity
        )
        let (landmarks, amenities) = await (landmarkRows, amenityRows)
        let results = Self.mergeMapTapLandmarkAndAmenityTiers(landmarks: landmarks, amenities: amenities)
        debugPrint("[Kakao] mapTap landmark-tier → \(landmarks.count) (deduped within tier)")
        debugPrint("[Kakao] mapTap amenity-tier → \(amenities.count) (deduped within tier)")
        debugPrint("[Kakao] mapTap merged → \(results.count) nearby places (deduped across tiers)")
        for place in results {
            debugPrint("[Kakao] category  '\(place.place_name)'  group=\(place.category_group_code)  name='\(place.category_name)'  → poi=\(place.poiCategoryRaw ?? "nil")")
        }
        return results
    }

    // MARK: - Reverse geocode

    /// Returns the best place name for a coordinate: building name, road address, or lot address.
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> KakaoCoord2AddressDoc? {
        guard isAvailable else { return nil }

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/geo/coord2address.json")!
        components.queryItems = [
            URLQueryItem(name: "x", value: String(coordinate.longitude)),
            URLQueryItem(name: "y", value: String(coordinate.latitude))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await session.data(for: request),
              let response = try? JSONDecoder().decode(KakaoCoord2AddressResponse.self, from: data) else {
            debugPrint("[Kakao] reverseGeocode(\(coordinate.latitude),\(coordinate.longitude)) failed")
            return nil
        }
        debugPrint("[Kakao] reverseGeocode → \(response.documents.first?.bestPlaceName ?? "nil")")
        return response.documents.first
    }

    // MARK: - Region code (neighborhood fallback for uncategorized POIs)

    /// Returns the smallest administrative area containing `coordinate`.
    /// Prefers the B-type (법정동) document because Kakao Local `address_name` fields use statutory names.
    func reverseGeocodeToRegionCode(coordinate: CLLocationCoordinate2D) async -> KakaoRegionDoc? {
        guard isAvailable else { return nil }

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/geo/coord2regioncode.json")!
        components.queryItems = [
            URLQueryItem(name: "x", value: String(coordinate.longitude)),
            URLQueryItem(name: "y", value: String(coordinate.latitude))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await session.data(for: request),
              let response = try? JSONDecoder().decode(KakaoRegionResponse.self, from: data) else {
            debugPrint("[Kakao] reverseGeocodeToRegionCode(\(coordinate.latitude),\(coordinate.longitude)) failed")
            return nil
        }
        let result = response.documents.first(where: { $0.region_type == "B" }) ?? response.documents.first
        debugPrint("[Kakao] reverseGeocodeToRegionCode → \(result?.address_name ?? "nil") type=\(result?.region_type ?? "nil")")
        return result
    }
}
