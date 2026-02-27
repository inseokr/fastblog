//
//  APIManager.swift
//  Capper
//
//  Centralized network manager that handles API requests, JSON encoding/decoding,
//  and automatically injects the JWT token into the Authorization header.
//

import CoreLocation
import Foundation
import ImageIO
import Photos
import UIKit

enum APIError: LocalizedError {
    case invalidURL
    case serializationFailed
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed(Error)
    case limitReached(errorCode: String, message: String, details: [String: Any])
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL configuration."
        case .serializationFailed: return "Failed to serialize the request body."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Received an invalid response from the server."
        case .httpError(let statusCode, let message): return "HTTP Error \(statusCode): \(message)"
        case .decodingFailed(let error): return "Failed to decode response: \(error.localizedDescription)"
        case .limitReached(_, let message, _): return message
        }
    }
}

@MainActor
final class APIManager {
    static let shared = APIManager()
    
    // Actual API server URLs
    let baseURL = "https://pocketverse.herokuapp.com/LS_API"
    let fileServerURL = "https://ls-file-server-4312402ca23f.herokuapp.com/LS_FS_API"    
    private init() {}
    
    // MARK: - Generic Request Method
    
    /// Performs an authenticated or unauthenticated HTTP request
    /// - Parameters:
    ///   - endpoint: The API endpoint (e.g., "/jwt_login").
    ///   - method: HTTP method ("GET", "POST", etc.).
    ///   - body: Optional body data. Recommended to use `post<T, U>` for typed requests.
    ///   - requiresAuth: If true, injects the Bearer token. If true and no token is found, standard failure applies.
    /// - Returns: Decoded object of type `T`.
    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Inject JWT Token (matching Axios Interceptor logic)
        if requiresAuth, let token = AuthService.shared.currentJwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        // 🔍 DEBUG: Log outgoing request
        print("🌐 [\(method)] \(baseURL + endpoint)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            let preview = bodyString.prefix(500)
            print("   📤 Body (\(body.count) bytes): \(preview)\(bodyString.count > 500 ? "…" : "")")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("   ❌ Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // 🔍 DEBUG: Log response
        print("   📥 \(httpResponse.statusCode) (\(data.count) bytes)")
        if let responseString = String(data: data, encoding: .utf8) {
            let preview = responseString.prefix(300)
            print("   📥 Response: \(preview)\(responseString.count > 300 ? "…" : "")")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Attempt to extract a human-readable error message from the response body
            var errorMessage: String
            
            // Friendly messages for common HTTP error codes
            switch httpResponse.statusCode {
            case 503: errorMessage = "The server is temporarily unavailable. Please try again in a moment."
            case 502: errorMessage = "The server is unreachable. Please check your connection and try again."
            case 401: errorMessage = "Incorrect username or password."
            case 403: errorMessage = "You don't have permission to do that."
            case 404: errorMessage = "The requested resource was not found."
            case 409: errorMessage = "An account with this username or email already exists."
            case 429: errorMessage = "Too many requests. Please wait a moment and try again."
            default:  errorMessage = "Something went wrong (error \(httpResponse.statusCode)). Please try again."
            }
            
            // Try to get a more specific message from the JSON body (if not HTML)
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let isHTML = contentType.contains("text/html")
            if !isHTML, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🚨 API Error Data JSON: \(json)")
                
                // Optimized enforcement check: Look for structured errorCode
                if let errorCode = json["errorCode"] as? String {
                    let msg = json["message"] as? String ?? errorMessage
                    let details = json["details"] as? [String: Any] ?? [:]
                    throw APIError.limitReached(errorCode: errorCode, message: msg, details: details)
                }

                if let msg = json["message"] as? String, !msg.isEmpty { errorMessage = msg }
                else if let err = json["error"] as? String, !err.isEmpty { errorMessage = err }
                else if let result = json["result"] as? String, !result.isEmpty { errorMessage = result }
            }
            
            print("🚨 HTTP Error \(httpResponse.statusCode): \(errorMessage)")
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Performs a POST request with an Encodable body
    func post<T: Decodable, U: Encodable>(endpoint: String, body: U, requiresAuth: Bool = true) async throws -> T {
        let requestData = try JSONEncoder().encode(body)
        return try await request(endpoint: endpoint, method: "POST", body: requestData, requiresAuth: requiresAuth)
    }
    
    /// Performs a GET request
    func get<T: Decodable>(endpoint: String, requiresAuth: Bool = true) async throws -> T {
        return try await request(endpoint: endpoint, method: "GET", body: nil, requiresAuth: requiresAuth)
    }

    // MARK: - User Cloud Storage

    /// Response from GET /user/cloudStorage (authenticated user's cloud storage usage).
    struct CloudStorageUsageResponse: Decodable {
        let result: String
        let cloudStorageUsage: CloudStorageUsageItem?
    }

    /// Current cloud storage usage for the authenticated user.
    struct CloudStorageUsageItem: Decodable {
        let totalBytes: Int64
        let totalMB: Double
        let photoCount: Int
        /// ISO date string or null from server.
        let lastUpdated: String?
    }

    /// Fetches the authenticated user's cloud storage usage.
    func fetchCloudStorageUsage() async throws -> CloudStorageUsageItem {
        let response: CloudStorageUsageResponse = try await get(endpoint: "/user/cloudStorage")
        guard response.result == "OK", let usage = response.cloudStorageUsage else {
            throw APIError.invalidResponse
        }
        return usage
    }

    // MARK: - File Server Upload

    /// Uploads a UIImage to the file server as a compressed JPEG.
    /// - Parameters:
    ///   - image: The UIImage to upload.
    ///   - filename: Filename for the upload (default: "photo.jpg").
    /// - Returns: The cloud URL string from the server response.
    func uploadPhoto(image: UIImage, filename: String = "photo.jpg") async throws -> String {
        guard let url = URL(string: fileServerURL + "/place/file_upload") else {
            throw APIError.invalidURL
        }

        // JPEG Quality: 0.92 for high-quality web/large-screen display
        guard let imageData = image.jpegData(compressionQuality: 0.92) else {
            throw APIError.serializationFailed
        }

        // Build multipart/form-data body — field name MUST be "photo"; backend accepts quality (1–100)
        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"quality\"\r\n\r\n".utf8))
        body.append(Data("50\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Let the boundary be set explicitly — do NOT set a bare "multipart/form-data"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Inject JWT token
        if let token = AuthService.shared.currentJwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        // 🔍 DEBUG: Log photo upload
        print("🌐 [POST] \(fileServerURL)/place/file_upload — photo: \(filename) (\(imageData.count) bytes)")
        
        // 📊 Storage Tracking: Assume success for tracking. Actual failure handling can be refined.
        print("Storage Tracking: Uploading \(imageData.count) bytes")
        AuthService.shared.incrementStorageUsed(by: Int64(imageData.count))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorMessage = "Upload failed."
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🚨 Upload Error JSON: \(json)")
                errorMessage = (json["message"] as? String)
                    ?? (json["error"] as? String)
                    ?? errorMessage
            }
            print("🚨 Upload HTTP Error \(httpResponse.statusCode): \(errorMessage)")
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Server returns { "path": "https://...cloud-url..." }
        struct FileUploadResponse: Decodable {
            let path: String?
        }

        let result: FileUploadResponse
        do {
            result = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }

        guard let cloudURL = result.path, !cloudURL.isEmpty else {
            throw APIError.invalidResponse
        }

        print("   ✅ Uploaded → \(cloudURL)")
        return cloudURL
    }

    /// Convenience: uploads a photo from the iOS Photos library by asset identifier.
    /// Loads the image at up to 1920×1920, compresses, and uploads.
    func uploadPhoto(assetIdentifier: String) async throws -> String {
        // Target dimension 2048px on longest edge as per new Free Tier rules
        let image = await ImageLoader.shared.loadImage(
            assetIdentifier: assetIdentifier,
            targetSize: CGSize(width: 2048, height: 2048)
        )
        guard let image else {
            throw APIError.serializationFailed
        }
        let filename = "IMG_\(assetIdentifier.prefix(8)).jpg"
        return try await uploadPhoto(image: image, filename: filename)
    }

    /// Uploads the user's profile picture (POST /profile/:user_id/file_upload on LS_API).
    /// Backend expects multipart field name "file_name". Returns the server path on success.
    func uploadProfilePicture(userId: String, image: UIImage) async throws -> String {
        guard let url = URL(string: baseURL + "/profile/\(userId)/file_upload") else {
            throw APIError.invalidURL
        }

        guard let imageData = image.jpegData(compressionQuality: 0.92) else {
            throw APIError.serializationFailed
        }

        let filename = "profile_\(userId).jpg"
        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file_name\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = AuthService.shared.currentJwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        print("🌐 [POST] \(baseURL)/profile/\(userId)/file_upload — profile picture (\(imageData.count) bytes)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorMessage = "Profile picture upload failed."
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                errorMessage = (json["message"] as? String) ?? (json["error"] as? String) ?? errorMessage
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        struct ProfileUploadResponse: Decodable {
            let path: String?
            let result: String?
        }

        let decoded: ProfileUploadResponse
        do {
            decoded = try JSONDecoder().decode(ProfileUploadResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }

        guard decoded.result == "OK", let path = decoded.path, !path.isEmpty else {
            throw APIError.invalidResponse
        }

        print("   ✅ Profile picture uploaded → \(path)")
        return path
    }

    // MARK: - Blog Creation (Linkedspaces / Pocketverse)

    /// Digitized time format for API: "2026:01:06 18:57:13" (yyyy:MM:dd HH:mm:ss). Timezone is the photo's capture location so the time reflects where it was taken.
    static func digitizedTimeString(from date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f.string(from: date)
    }

    /// Parses EXIF OffsetTimeOriginal (e.g. "+09:00", "-05:30") into a TimeZone. Returns nil if invalid.
    private static func timeZone(fromEXIFOffset offsetString: String) -> TimeZone? {
        let s = offsetString.trimmingCharacters(in: .whitespaces)
        guard let first = s.first else { return nil }
        let sign: Int = (first == "-") ? -1 : (first == "+" ? 1 : 0)
        guard sign != 0 else { return nil }
        let rest = String(s.dropFirst())
        let parts = rest.split(separator: ":")
        guard parts.count >= 1,
              let hours = Int(parts[0]),
              hours >= 0, hours <= 23 else { return nil }
        let minutes = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
        let secondsFromGMT = sign * (hours * 3600 + minutes * 60)
        return TimeZone(secondsFromGMT: secondsFromGMT)
    }

    /// Reads EXIF OffsetTimeOriginal from the asset's image data to get the capture timezone (no geocoding). Falls back to nil so caller can use UTC.
    static func getLocalTimeZone(for asset: PHAsset) async -> TimeZone? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data = data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                      let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
                      let offsetString = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String,
                      let tz = Self.timeZone(fromEXIFOffset: offsetString) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: tz)
            }
        }
    }

    /// Creates a blog with places on the Pocketverse backend.
    /// Maps RecapBlogDetail → Linkedspaces payload format and POSTs to /placeVisitHistory/createBlogWithPlaces.
    /// - Returns: A tuple of the server response and a per-stop mapping (dayIdx, stopIdx, visitedTimeDigitized)
    ///   in the same order as the placeList payload, used to write cloud keys back to local storage.
    fileprivate func createBlogWithPlaces(username: String, detail: RecapBlogDetail) async throws -> (CreateBlogResponse, [PlaceStopBuildInfo]) {
        // Collect all timestamps to derive start/end
        let allPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let timestamps = allPhotos.map { $0.timestamp }
        let startMs = timestamps.min().map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        let endMs = timestamps.max().map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0

        // Fetch PHAssets for all included photos so we use creationDate and location from the asset
        let includedIds = allPhotos.compactMap(\.localIdentifier)
        var assetMap: [String: PHAsset] = [:]
        if !includedIds.isEmpty {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: includedIds, options: nil)
            fetchResult.enumerateObjects { asset, _, _ in
                assetMap[asset.localIdentifier] = asset
            }
        }

        // Batch timezone from EXIF (no geocoding). One async read per asset in parallel.
        var assetTimeZoneMap: [String: TimeZone] = [:]
        await withTaskGroup(of: (String, TimeZone?).self) { group in
            for (id, asset) in assetMap {
                group.addTask {
                    let tz = await Self.getLocalTimeZone(for: asset)
                    return (id, tz)
                }
            }
            for await (id, tz) in group {
                if let tz = tz { assetTimeZoneMap[id] = tz }
            }
        }

        let utc = TimeZone(identifier: "UTC")!
        let defaultDigitizedTime = "1970:01:01 00:00:00"

        // Build placeList from all days/stops, tracking which (dayIdx, stopIdx) each entry maps to.
        var placeList: [[String: Any]] = []
        var placeStopMapping: [PlaceStopBuildInfo] = []
        for (dayIdx, day) in detail.days.enumerated() {
            for (stopIdx, stop) in day.placeStops.enumerated() {
                let includedPhotos = stop.photos.filter(\.isIncluded)
                guard !includedPhotos.isEmpty else { continue }

                let coord: [String: Double] = {
                    if let loc = stop.representativeLocation {
                        return ["latitude": loc.latitude, "longitude": loc.longitude]
                    }
                    if let loc = includedPhotos.first?.location {
                        return ["latitude": loc.latitude, "longitude": loc.longitude]
                    }
                    return ["latitude": 0, "longitude": 0]
                }()

                var photoList: [[String: Any]] = []
                var firstPhotoVisitedTimeMs: Int64 = 0
                for photo in includedPhotos {
                    guard let uri = photo.cloudURL else { continue }
                    let asset = photo.localIdentifier.flatMap { assetMap[$0] }
                    let creationDate = asset?.creationDate ?? photo.timestamp
                    let creationTimeMs = Int64(creationDate.timeIntervalSince1970 * 1000)
                    if firstPhotoVisitedTimeMs == 0 { firstPhotoVisitedTimeMs = creationTimeMs }
                    let tz = photo.localIdentifier.flatMap { assetTimeZoneMap[$0] }
                    let digitizedTime = Self.digitizedTimeString(from: creationDate, timeZone: tz ?? utc)
                    let location = asset?.location ?? photo.location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
                    let photoLocation: [String: Double] = location.map { ["latitude": $0.coordinate.latitude, "longitude": $0.coordinate.longitude] } ?? coord
                    photoList.append([
                        "uri": uri,
                        "digitizedTime": digitizedTime,
                        "creationTime": creationTimeMs,
                        "location": photoLocation,
                        "selected": true,
                        "coverPhotoScore": (photo.qualityScore?.totalScore).map { $0 as Any } ?? NSNull(),
                        "localUri": NSNull()
                    ])
                }

                let visitedTime = firstPhotoVisitedTimeMs != 0 ? firstPhotoVisitedTimeMs : Int64(Date().timeIntervalSince1970 * 1000)
                let placeVisitedTimeDigitized = (photoList.first?["digitizedTime"] as? String) ?? defaultDigitizedTime

                let categories: [String] = stop.placeCategory.map { [$0] } ?? ["unknown"]
                let place: [String: Any] = [
                    "visitedTimeDigitized": placeVisitedTimeDigitized,
                    "visitedTime": visitedTime,
                    "visitedCity": stop.placeSubtitle ?? "",
                    "placeName": stop.placeTitle,
                    "placeFormattedAddress": (stop.placeSubtitle).map { $0 as Any } ?? NSNull(),
                    "coordinate": coord,
                    "status": "active",
                    "abstract": true,
                    "categories": categories,
                    "photoList": photoList
                ]
                placeStopMapping.append(PlaceStopBuildInfo(
                    dayIdx: dayIdx,
                    stopIdx: stopIdx,
                    visitedTimeDigitized: placeVisitedTimeDigitized
                ))
                placeList.append(place)
            }
        }

        let payload: [String: Any] = [
            "username": username,
            "blogMetaData": [
                "title": detail.title,
                "startTimestamp": startMs,
                "endTimestamp": endMs,
                "destinationName": detail.countryName ?? ""
            ],
            "placeList": placeList
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let response: CreateBlogResponse = try await request(
            endpoint: "/placeVisitHistory/createBlogWithPlaces",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        return (response, placeStopMapping)
    }

    /// Uploads a cover photo for a blog, then notifies the server.
    /// - Parameters:
    ///   - blogKey: The server-assigned blog key from createBlogWithPlaces.
    ///   - assetIdentifier: The PHAsset local identifier for the cover photo.
    func uploadCoverPhoto(blogKey: Int, assetIdentifier: String) async throws {
        let cloudURL = try await uploadPhoto(assetIdentifier: assetIdentifier)
        let payload: [String: Any] = ["coverPhotoUrl": cloudURL]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/listing/event/\(blogKey)/cover-photo",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    /// Sets the privacy of a blog on the Pocketverse backend.
    func updateBlogTitle(blogKey: Int, title: String) async throws {
        struct Payload: Encodable { let blogKey: Int; let title: String }
        let _: GenericResponse = try await post(endpoint: "/trips/update-title", body: Payload(blogKey: blogKey, title: title))
    }

    func deleteBlogFromCloud(blogKey: Int) async throws {
        struct Payload: Encodable { let blogKey: Int }
        let _: GenericResponse = try await post(endpoint: "/trips/delete", body: Payload(blogKey: blogKey))
    }

    /// Updates the cover photo URI for a blog on the backend.
    func updateCoverPhoto(blogKey: Int, photoUri: String) async throws {
        struct Payload: Encodable { let blogKey: Int; let photoUri: String }
        let _: GenericResponse = try await post(endpoint: "/trips/update-cover-photo", body: Payload(blogKey: blogKey, photoUri: photoUri))
    }

    /// Uploads a photo asset and sets it as the blog's cover photo.
    func uploadAndUpdateCoverPhoto(blogKey: Int, assetIdentifier: String) async throws {
        let cloudURL = try await uploadPhoto(assetIdentifier: assetIdentifier)
        try await updateCoverPhoto(blogKey: blogKey, photoUri: cloudURL)
        print("✅ Cover photo updated for blogKey=\(blogKey)")
    }

    /// Updates the place name (and optionally category) on the backend for DB sync.
    func updatePlaceName(visitedTimeDigitized: String, placeName: String, categories: [String]? = nil) async throws {
        var payload: [String: Any] = [
            "visitedTimeDigitized": visitedTimeDigitized,
            "placeName": placeName
        ]
        if let categories = categories, !categories.isEmpty {
            payload["categories"] = categories
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/updatePlaceName",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        print("✅ Place name updated: '\(placeName)' for key=\(visitedTimeDigitized)")
    }

    func setBlogPrivacy(blogKey: Int, level: String = "public") async throws {
        let payload: [String: Any] = ["blogKey": blogKey, "level": level]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/trips/privacy-control",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    /// Updates place-level or photo-level story on the backend (placeVisitHistory).
    /// - Parameters:
    ///   - placeKey: visitedTimeDigitized for the place.
    ///   - storyText: The story/caption text.
    ///   - photoIndex: If nil, updates place-level story; if set, updates that photo's story (index in filtered/included list).
    ///   - photoIndexType: "filtered" when photoIndex is index in included photos; "all" for full photoList index. Default "filtered".
    func updateStory(placeKey: String, storyText: String, photoIndex: Int? = nil, photoIndexType: String = "filtered") async throws {
        var payload: [String: Any] = [
            "placeKey": placeKey,
            "storyText": storyText
        ]
        if let idx = photoIndex {
            payload["photoIndex"] = idx
            payload["photoIndexType"] = photoIndexType
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/story",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    /// Updates a single photo's inclusion state on the backend.
    /// - Parameters:
    ///   - placeKey: The `visitedTimeDigitized` of the containing place in placeVisitHistory.
    ///   - photo: The photo to add or delete (must have a cloudURL).
    ///   - operation: `"add"` to re-include, `"delete"` to exclude.
    func updatePhoto(placeKey: String, photo: RecapPhoto, operation: String) async throws {
        guard let cloudURL = photo.cloudURL else {
            print("⚠️ updatePhoto: photo has no cloudURL — skipping")
            return
        }

        // Recompute digitizedTime the same way createBlogWithPlaces does so the
        // backend can locate the correct entry in the place's photoList.
        let digitizedTime: String
        if let assetId = photo.localIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject {
            let tz = await Self.getLocalTimeZone(for: asset)
            let creationDate = asset.creationDate ?? photo.timestamp
            digitizedTime = Self.digitizedTimeString(from: creationDate, timeZone: tz ?? TimeZone(identifier: "UTC")!)
        } else {
            digitizedTime = Self.digitizedTimeString(from: photo.timestamp, timeZone: TimeZone(identifier: "UTC")!)
        }

        var photoDict: [String: Any] = [
            "uri": cloudURL,
            "digitizedTime": digitizedTime,
        ]
        // Include caption/story so the backend preserves it alongside the photo state change.
        if let caption = photo.caption {
            photoDict["story"] = caption
        }

        let payload: [String: Any] = [
            "placeKey": placeKey,
            "photo": photoDict,
            "operation": operation
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/updatePhoto",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        print("✅ updatePhoto: \(operation) — placeKey=\(placeKey), digitizedTime=\(digitizedTime)")
    }

    // MARK: - Cloud Sync Fetch

    /// Fetches all trips (blogs) for the given username from the backend.
    func fetchTrips(username: String) async throws -> TripsResponse {
        return try await request(endpoint: "/trips?username=\(username)", method: "GET", requiresAuth: true)
    }

    /// Fetches the full placeVisitHistory for the given username.
    /// Uses showAll=true so the owner sees all statuses.
    func fetchPlaceVisitHistory(username: String) async throws -> PlaceVisitHistoryResponse {
        return try await request(endpoint: "/placeVisitHistory?username=\(username)&showAll=true", method: "GET", requiresAuth: true)
    }

    // MARK: - Blog publish flow

    /// Full post-upload publish sequence: create blog → cover photo → privacy.
    /// Returns the server-assigned blogKey on success, nil on failure.
    @discardableResult
    func publishBlog(detail: RecapBlogDetail) async -> Int? {
        let user = AuthService.shared.currentUser
        print("🔍 publishBlog — user: id=\(user?.id ?? "nil"), username=\(user?.username ?? "nil"), displayName=\(user?.displayName ?? "nil"), email=\(user?.email ?? "nil")")

        guard let username = user?.username ?? user?.displayName ?? user?.email else {
            print("⚠️ No username available — skipping createBlogWithPlaces")
            return nil
        }

        print("🔍 publishBlog — resolved username: \(username)")
        print("🔍 publishBlog — blog title: \(detail.title), days: \(detail.days.count), country: \(detail.countryName ?? "nil")")

        let allPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let withCloudURL = allPhotos.filter { $0.cloudURL != nil }
        print("🔍 publishBlog — photos: \(allPhotos.count) included, \(withCloudURL.count) have cloudURL")

        do {
            print("🔍 Step 1/3: Calling createBlogWithPlaces...")
            let (response, placeStopMapping) = try await createBlogWithPlaces(username: username, detail: detail)
            print("✅ Blog created with blogKey: \(response.blogKey), placeIndices: \(response.placeIndices ?? [])")

            // Build the per-stop cloud key mapping and persist it to local storage.
            // Prefer placeMemories (has visitedTimeDigitized for robust matching) over positional placeIndices.
            if let memories = response.placeMemories, !memories.isEmpty {
                // Build a lookup from visitedTimeDigitized → (dayIdx, stopIdx)
                let digestMap: [String: (dayIdx: Int, stopIdx: Int)] = Dictionary(
                    uniqueKeysWithValues: placeStopMapping.map { ($0.visitedTimeDigitized, ($0.dayIdx, $0.stopIdx)) }
                )
                var placeMapping: [(dayIdx: Int, stopIdx: Int, placeIndex: Int, visitedTimeDigitized: String)] = []
                for memory in memories {
                    if let loc = digestMap[memory.visitedTimeDigitized] {
                        placeMapping.append((dayIdx: loc.dayIdx, stopIdx: loc.stopIdx, placeIndex: memory.placeIndex, visitedTimeDigitized: memory.visitedTimeDigitized))
                    }
                }
                CreatedRecapBlogStore.shared.applyCloudKeys(blogId: detail.id, blogKey: response.blogKey, detail: detail, placeMapping: placeMapping)
            } else if let indices = response.placeIndices, !indices.isEmpty {
                // Fall back to positional matching (zip truncates if server skipped some as duplicates)
                let placeMapping: [(dayIdx: Int, stopIdx: Int, placeIndex: Int, visitedTimeDigitized: String)] =
                    zip(placeStopMapping, indices).map { info, idx in
                        (dayIdx: info.dayIdx, stopIdx: info.stopIdx, placeIndex: idx, visitedTimeDigitized: info.visitedTimeDigitized)
                    }
                CreatedRecapBlogStore.shared.applyCloudKeys(blogId: detail.id, blogKey: response.blogKey, detail: detail, placeMapping: placeMapping)
            } else {
                // No place-level info — at least store the blogKey
                CreatedRecapBlogStore.shared.setBlogKey(blogId: detail.id, blogKey: response.blogKey)
            }

            // TODO: Cover photo upload — endpoint not yet available on server
            // if let coverAssetId = detail.selectedCoverPhotoIdentifier {
            //     try await uploadCoverPhoto(blogKey: response.blogKey, assetIdentifier: coverAssetId)
            // }
            print("🔍 Step 2/3: Cover photo — skipped (endpoint not ready)")

            print("🔍 Step 3/3: Setting privacy to public...")
            try await setBlogPrivacy(blogKey: response.blogKey)
            print("✅ Privacy set to public for blogKey: \(response.blogKey)")

            print("🎉 publishBlog complete — all 3 steps succeeded")
            return response.blogKey
        } catch {
            print("🚨 publishBlog failed: \(error)")
            return nil
        }
    }

    // MARK: - Two-Phase Publish Flow (Free Tier Limits)

    struct InitiatePublishPayload: Encodable {
        let title: String
        let photoCount: Int
        let destinationName: String
        // Add approx size if available (optional)
        var estimatedBytes: Int64?
    }

    struct InitiatePublishResponse: Decodable {
        let publishSessionId: String
    }

    /// Phase 1: Inform server of intent to publish and check limits.
    func initiatePublish(detail: RecapBlogDetail) async throws -> String {
        let allPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let payload = InitiatePublishPayload(
            title: detail.title,
            photoCount: allPhotos.count,
            destinationName: detail.countryName ?? "",
            estimatedBytes: nil // Client-side estimation could be added here
        )
        
        let response: InitiatePublishResponse = try await post(endpoint: "/blog/initiatePublish", body: payload)
        return response.publishSessionId
    }


    struct FinalizePublishPayload: Encodable {
        let publishSessionId: String
        let uploadedKeys: [String]
        let title: String
        let countryName: String
    }

    /// Phase 2: Confirm all photos are uploaded and atomicity commit.
    func finalizePublish(publishSessionId: String, detail: RecapBlogDetail) async throws -> Int {
        // Collect all cloud URLs to send as uploaded keys/verification
        let allPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let uploadedKeys = allPhotos.compactMap { $0.cloudURL }
        
        let payload = FinalizePublishPayload(
            publishSessionId: publishSessionId,
            uploadedKeys: uploadedKeys,
            title: detail.title,
            countryName: detail.countryName ?? ""
        )
        
        struct FinalizeResponse: Decodable {
            let blogKey: Int
        }
        
        let response: FinalizeResponse = try await post(endpoint: "/blog/finalizePublish", body: payload)
        return response.blogKey
    }
}

/// Helper for Any Codable if needed, but let's stick to concrete types for now.
struct AnyCodable: Codable {}

struct CreateBlogResponse: Decodable {
    let blogKey: Int
    let placeIndices: [Int]?
    /// Richer per-place info returned by the server (includes visitedTimeDigitized for robust matching).
    let placeMemories: [PlaceMemory]?

    struct PlaceMemory: Decodable {
        let placeIndex: Int
        let visitedTimeDigitized: String
    }
}

/// Tracks which (dayIdx, stopIdx) in the local RecapBlogDetail contributed each entry to the
/// placeList payload, along with the visitedTimeDigitized used as a cloud dedup key.
private struct PlaceStopBuildInfo {
    let dayIdx: Int
    let stopIdx: Int
    let visitedTimeDigitized: String
}

private struct GenericResponse: Decodable {
    let result: String?
    let message: String?
}

// MARK: - Cloud Sync Response Models

struct TripsResponse: Decodable {
    let result: String
    let trips: [ServerTrip]?
}

struct ServerTrip: Decodable {
    let blogKey: Int
    let title: String?
    /// Unix milliseconds stored as a Number in MongoDB (not a Date), so decoded as Double.
    let startTimestamp: Double?
    let endTimestamp: Double?
    let country: String?
    let countryCode: String?
    let coverPhotoUri: String?
    let placeList: [ServerTripPlace]?
    let status: String?
    let visitedPlaceName: [String]?
    let startTimeString: String?
    let endTimeString: String?
}

struct ServerTripPlace: Decodable {
    let placeIndex: Int
}

struct PlaceVisitHistoryResponse: Decodable {
    let result: String
    let visitedHistory: [ServerPlaceRecord]?
}

struct ServerPlaceRecord: Decodable {
    let placeIndex: Int
    let visitedTimeDigitized: String?
    /// blogKey of the trip this place belongs to. -1 or nil if not in a trip.
    let blogKey: Int?
    let placeName: String?
    let visitedCity: String?
    let country: String?
    let coordinate: ServerCoordinate?
    /// User-written story/note for this place.
    let story: String?
    /// POI categories (e.g. MKPOICategoryRestaurant). We send this on create; server may echo it back.
    let categories: [String]?
    let photoList: [ServerPhotoRecord]?
}

struct ServerCoordinate: Decodable {
    let latitude: Double
    let longitude: Double
}

struct ServerPhotoRecord: Decodable {
    let uri: String?
    /// EXIF digitized time: "yyyy:MM:dd HH:mm:ss"
    let digitizedTime: String?
    let coordinate: ServerCoordinate?
    /// Whether this photo was selected/included in the blog.
    let selected: Bool?
    /// User-written caption/story for this individual photo.
    let story: String?
}
