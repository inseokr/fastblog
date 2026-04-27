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

    /// Returns up to 10 places matching `query`, sorted by distance from `coordinate` when provided.
    func searchPlaces(query: String, near coordinate: CLLocationCoordinate2D?, radius: Int = 5000) async -> [KakaoPlace] {
        guard isAvailable, !query.isEmpty else { return [] }

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "size", value: "10")
        ]
        if let coord = coordinate {
            items += [
                URLQueryItem(name: "x", value: String(coord.longitude)),
                URLQueryItem(name: "y", value: String(coord.latitude)),
                URLQueryItem(name: "radius", value: String(radius)),
                URLQueryItem(name: "sort", value: "distance")
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

    /// Travel-relevant Kakao category group codes used for map-tap POI resolution.
    /// Ordered roughly by likelihood of appearing in a travel blog; excludes low-value
    /// categories (schools, nurseries, academies, real estate, public offices) to keep
    /// the parallel-request fan-out to 10 instead of 18.
    static let categoryGroupCodesForMapTap: [String] = [
        "FD6",  // restaurants
        "CE7",  // cafes
        "AT4",  // tourist attractions
        "AD5",  // accommodations / hotels
        "CT1",  // cultural facilities (museums, galleries)
        "CS2",  // convenience stores
        "MT1",  // large marts / supermarkets
        "SW8",  // subway stations
        "HP8",  // hospitals
        "PM9",  // pharmacies
    ]

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

    /// Merges category searches in parallel; dedupes by `id`. Caller sorts by distance.
    func searchNearbyPlacesForMapTap(coordinate: CLLocationCoordinate2D, radius: Int) async -> [KakaoPlace] {
        guard isAvailable else { return [] }

        let codes = Self.categoryGroupCodesForMapTap
        let r = min(20_000, max(1, radius))
        return await withTaskGroup(of: [KakaoPlace].self) { group in
            for code in codes {
                group.addTask {
                    await self.searchPlacesByCategory(
                        categoryGroupCode: code,
                        coordinate: coordinate,
                        radius: r,
                        size: 5   // we only need the nearest result per category
                    )
                }
            }
            var byId: [String: KakaoPlace] = [:]
            for await chunk in group {
                for place in chunk {
                    if byId[place.id] == nil { byId[place.id] = place }
                }
            }
            let results = Array(byId.values)
            debugPrint("[Kakao] mapTap → \(results.count) nearby places (deduped)")
            for place in results {
                debugPrint("[Kakao] category  '\(place.place_name)'  group=\(place.category_group_code)  name='\(place.category_name)'  → poi=\(place.poiCategoryRaw ?? "nil")")
            }
            return results
        }
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
}
