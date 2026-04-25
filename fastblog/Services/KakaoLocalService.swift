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

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(y), let lon = Double(x) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Road address preferred over lot address for display.
    var displaySubtitle: String {
        road_address_name.isEmpty ? address_name : road_address_name
    }

    /// Partial mapping from Kakao category_group_code to MKPointOfInterestCategory raw value.
    /// Used to show the right icon in PlaceStopRowView.
    var poiCategoryRaw: String? {
        switch category_group_code {
        case "FD6": return MKPointOfInterestCategory.restaurant.rawValue
        case "CE7": return MKPointOfInterestCategory.cafe.rawValue
        case "HP8": return MKPointOfInterestCategory.hospital.rawValue
        case "PM9": return MKPointOfInterestCategory.pharmacy.rawValue
        case "BK9": return MKPointOfInterestCategory.bank.rawValue
        case "OL7": return MKPointOfInterestCategory.gasStation.rawValue
        case "PK6": return MKPointOfInterestCategory.parking.rawValue
        case "AT4": return MKPointOfInterestCategory.amusementPark.rawValue
        case "AD5": return MKPointOfInterestCategory.hotel.rawValue
        case "CT1": return MKPointOfInterestCategory.museum.rawValue
        case "SC4": return MKPointOfInterestCategory.school.rawValue
        default: return nil
        }
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
        return response.documents
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
