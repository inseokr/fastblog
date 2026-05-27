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

    // MARK: - Cloud URL Helpers

    /// Strips AWS signing query params from a URL, returning the permanent URL without expiry parameters.
    static func stripQueryParams(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return urlString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? urlString
    }

    /// Registers the APNs device token with the backend so the server can send push notifications.
    func registerDeviceToken(_ token: String) async {
        struct TokenBody: Encodable { let deviceToken: String }
        struct TokenResponse: Decodable { let result: String? }
        print("[Push] Sending device token to backend: \(token)")
        do {
            let response: TokenResponse = try await post(endpoint: "/bloggo/device-token", body: TokenBody(deviceToken: token))
            print("[Push] Backend registration succeeded — result: \(response.result ?? "nil")")
        } catch {
            print("[Push] Backend registration failed: \(error)")
        }
    }

    /// Fetches a fresh short-lived signed URL for the given permanent cloud URL.
    /// The permanent URL should have no query params (e.g., from `stripQueryParams`).
    func fetchSignedPhotoURL(permanentURL: String) async throws -> URL {
        guard let parsed = URL(string: permanentURL) else { throw APIError.invalidURL }
        // Extract the path component and strip the leading slash so the backend receives a relative path.
        let path = parsed.path.hasPrefix("/") ? String(parsed.path.dropFirst()) : parsed.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path

        struct SignedURLResponse: Decodable {
            let result: String?
            let url: String?
            let signedUrl: String?
            var resolvedURL: String? { url ?? signedUrl }
        }

        let response: SignedURLResponse = try await request(endpoint: "/media/signed-url?path=\(encoded)")
        guard let urlStr = response.resolvedURL, let signedURL = URL(string: urlStr) else {
            throw APIError.invalidResponse
        }
        return signedURL
    }

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
        AppAnalytics.shared.trackEvent(name: "upload_attempted")
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
            AppAnalytics.shared.trackEvent(name: "upload_failed")
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

        guard let rawURL = result.path, !rawURL.isEmpty else {
            AppAnalytics.shared.trackEvent(name: "upload_failed")
            throw APIError.invalidResponse
        }

        // Store the permanent URL (no signing query params) so it never expires locally.
        let cloudURL = APIManager.stripQueryParams(from: rawURL)
        print("   ✅ Uploaded → \(cloudURL)")
        AppAnalytics.shared.trackEvent(name: "upload_success")
        return cloudURL
    }

    /// Convenience: uploads a photo by asset identifier (PHAsset or app-capture).
    /// Loads the image at up to 2048×2048, compresses, and uploads.
    func uploadPhoto(assetIdentifier: String) async throws -> String {
        if assetIdentifier.hasPrefix(AppCapturePhotoService.prefix) {
            guard let image = AppCapturePhotoService.shared.loadImage(identifier: assetIdentifier) else {
                throw APIError.serializationFailed
            }
            let shortId = assetIdentifier.dropFirst(AppCapturePhotoService.prefix.count).prefix(8)
            let filename = "IMG_\(shortId).jpg"
            return try await uploadPhoto(image: image, filename: filename)
        }
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

    /// Uploads arbitrary `Data` to the file server as a named file.
    /// Uses the same multipart endpoint as `uploadPhoto`. Returns the cloud URL string on success.
    func uploadJSONData(_ data: Data, filename: String) async throws -> String {
        guard let url = URL(string: fileServerURL + "/place/file_upload") else {
            throw APIError.invalidURL
        }
        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = AuthService.shared.currentJwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        print("🌐 [POST] \(fileServerURL)/place/file_upload — json: \(filename) (\(data.count) bytes)")
        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            var msg = "Upload failed."
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                msg = (json["message"] as? String) ?? (json["error"] as? String) ?? msg
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: msg)
        }
        struct FileUploadResponse: Decodable { let path: String? }
        let result = try JSONDecoder().decode(FileUploadResponse.self, from: responseData)
        guard let rawURL = result.path, !rawURL.isEmpty else { throw APIError.invalidResponse }
        let cloudURL = APIManager.stripQueryParams(from: rawURL)
        print("   ✅ JSON uploaded → \(cloudURL)")
        return cloudURL
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

    /// Reads EXIF `OffsetTimeOriginal`, then `OffsetTimeDigitized`, from image data (capture offset, not device). Falls back to nil.
    /// - Parameter allowNetwork: When `false`, only on-device metadata is read (trip scans). Avoids stalling on iCloud-only assets.
    /// - Parameter timeoutSeconds: When set, returns nil if PhotoKit does not respond in time (guards hung `assetsd` callbacks).
    static func getLocalTimeZone(
        for asset: PHAsset,
        allowNetwork: Bool = true,
        timeoutSeconds: TimeInterval? = nil
    ) async -> TimeZone? {
        let timeout = timeoutSeconds ?? (allowNetwork ? 20 : 5)
        return await withTaskGroup(of: TimeZone?.self) { group in
            group.addTask {
                await Self.readLocalTimeZoneFromImageData(for: asset, allowNetwork: allowNetwork)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Max concurrent `PHImageManager` metadata reads (trip scan / visited cities). Unbounded parallelism stalls `assetsd`.
    static let captureTimeZoneMapMaxConcurrent = 6

    /// Reads EXIF capture offset per asset with bounded concurrency. Use `allowNetwork: false` for library scans.
    static func buildCaptureTimeZoneMap(
        for assets: [PHAsset],
        allowNetwork: Bool = false,
        maxConcurrent: Int = captureTimeZoneMapMaxConcurrent
    ) async -> [String: TimeZone] {
        var tzMap: [String: TimeZone] = [:]
        guard !assets.isEmpty else { return tzMap }

        var iterator = assets.makeIterator()
        await withTaskGroup(of: (String, TimeZone?).self) { group in
            for _ in 0..<min(maxConcurrent, assets.count) {
                guard let asset = iterator.next() else { break }
                let id = asset.localIdentifier
                group.addTask {
                    let tz = await Self.getLocalTimeZone(for: asset, allowNetwork: allowNetwork)
                    return (id, tz)
                }
            }
            for await (id, tz) in group {
                if let tz { tzMap[id] = tz }
                guard let asset = iterator.next() else { continue }
                let nextId = asset.localIdentifier
                group.addTask {
                    let tz = await Self.getLocalTimeZone(for: asset, allowNetwork: allowNetwork)
                    return (nextId, tz)
                }
            }
        }
        return tzMap
    }

    private static func readLocalTimeZoneFromImageData(for asset: PHAsset, allowNetwork: Bool) async -> TimeZone? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = allowNetwork

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data = data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                      let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }
                let raw = (exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String)
                    ?? (exif[kCGImagePropertyExifOffsetTimeDigitized as String] as? String)
                let offsetString = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !offsetString.isEmpty, let tz = Self.timeZone(fromEXIFOffset: offsetString) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: tz)
            }
        }
    }

    /// Timezone **when the photo was taken**: EXIF offset first, else `CLPlacemark.timeZone` at the asset’s GPS (capture location). Not `TimeZone.current`.
    static func captureTimeZone(for asset: PHAsset) async -> TimeZone? {
        if let tz = await getLocalTimeZone(for: asset) {
            return tz
        }
        guard let location = asset.location else { return nil }
        return await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.timeZone)
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

        // Debug: summarize story coverage before building payload
        let totalDays = detail.days.count
        let daysWithStory = detail.days.filter { $0.dayCaption != nil && !($0.dayCaption?.isEmpty ?? true) }.count
        let allStops = detail.days.flatMap(\.placeStops)
        let stopsWithStory = allStops.filter { $0.noteText != nil && !($0.noteText?.isEmpty ?? true) }.count
        let allIncludedPhotos = allStops.flatMap { $0.photos.filter(\.isIncluded) }
        let photosWithStory = allIncludedPhotos.filter { $0.caption != nil && !($0.caption?.isEmpty ?? true) }.count
        print("📝 [createBlogWithPlaces] Story coverage — days: \(daysWithStory)/\(totalDays) have dayStory, stops: \(stopsWithStory)/\(allStops.count) have placeStory, photos: \(photosWithStory)/\(allIncludedPhotos.count) have photoStory")

        // Build placeList from all days/stops, tracking which (dayIdx, stopIdx) each entry maps to.
        var placeList: [[String: Any]] = []
        var placeStopMapping: [PlaceStopBuildInfo] = []
        for (dayIdx, day) in detail.days.enumerated() {
            let dayStoryPreview = day.dayCaption.map { "\"\($0.prefix(40))\"" } ?? "nil"
            print("📅 [createBlogWithPlaces] Day[\(dayIdx)] dayStory=\(dayStoryPreview), stops=\(day.placeStops.count)")
            for (stopIdx, stop) in day.placeStops.enumerated() {
                let includedPhotos = stop.photos.filter(\.isIncluded)
                guard !includedPhotos.isEmpty else {
                    print("   ↳ Stop[\(stopIdx)] '\(stop.placeTitle)' — skipped (no included photos)")
                    continue
                }

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
                var earliestCreationTimeMs: Int64 = 0
                var earliestDigitizedTime: String?
                // localIdentifier → digitizedTime for every photo in this stop (written back to RecapPhoto after publish)
                var photoDigitizedTimes: [String: String] = [:]
                for photo in includedPhotos {
                    guard let uri = photo.cloudURL else { continue }
                    let asset = photo.localIdentifier.flatMap { assetMap[$0] }
                    let creationDate = asset?.creationDate ?? photo.timestamp
                    let creationTimeMs = Int64(creationDate.timeIntervalSince1970 * 1000)
                    let tz = photo.localIdentifier.flatMap { assetTimeZoneMap[$0] }
                    let digitizedTime = Self.digitizedTimeString(from: creationDate, timeZone: tz ?? utc)
                    if let lid = photo.localIdentifier {
                        photoDigitizedTimes[lid] = digitizedTime
                    }
                    if earliestCreationTimeMs == 0 || creationTimeMs < earliestCreationTimeMs {
                        earliestCreationTimeMs = creationTimeMs
                        earliestDigitizedTime = digitizedTime
                    }
                    let location = asset?.location ?? photo.location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
                    let photoLocation: [String: Double] = location.map { ["latitude": $0.coordinate.latitude, "longitude": $0.coordinate.longitude] } ?? coord
                    var photoEntry: [String: Any] = [
                        "uri": uri,
                        "digitizedTime": digitizedTime,
                        "creationTime": creationTimeMs,
                        "location": photoLocation,
                        "selected": true,
                        "coverPhotoScore": (photo.qualityScore?.totalScore).map { $0 as Any } ?? NSNull(),
                        "localUri": NSNull(),
                        "inAppPhoto": true
                    ]
                    if let caption = photo.caption, !caption.isEmpty {
                        photoEntry["story"] = caption
                        print("      📷 photo story set: \"\(caption.prefix(40))\"")
                    }
                    photoList.append(photoEntry)
                }

                let visitedTime = earliestCreationTimeMs != 0 ? earliestCreationTimeMs : Int64(Date().timeIntervalSince1970 * 1000)
                let placeVisitedTimeDigitized = earliestDigitizedTime ?? (photoList.first?["digitizedTime"] as? String) ?? defaultDigitizedTime

                let categories: [String] = stop.placeCategory.map { [$0] } ?? ["unknown"]
                var place: [String: Any] = [
                    "visitedTimeDigitized": placeVisitedTimeDigitized,
                    "visitedTime": visitedTime,
                    "visitedCity": stop.placeSubtitle ?? "",
                    "placeName": stop.placeTitle,
                    "placeFormattedAddress": (stop.placeSubtitle).map { $0 as Any } ?? NSNull(),
                    "coordinate": coord,
                    "status": "active",
                    "abstract": true,
                    "categories": categories,
                    "photoList": photoList,
                    "sentiment": stop.sentiment
                ]
                let placeStoryNote = stop.noteText.map { "\"\($0.prefix(40))\"" } ?? "nil"
                let dayStoryNote = day.dayCaption.map { "\"\($0.prefix(40))\"" } ?? "nil"
                print("   ↳ Stop[\(stopIdx)] '\(stop.placeTitle)' — \(photoList.count) photos, placeStory=\(placeStoryNote), dayStory=\(dayStoryNote)")
                let storyText = (stop.noteText?.isEmpty == false ? stop.noteText : stop.overallStory)
                if let storyText = storyText, !storyText.isEmpty {
                    place["story"] = storyText
                }
                placeStopMapping.append(PlaceStopBuildInfo(
                    dayIdx: dayIdx,
                    stopIdx: stopIdx,
                    visitedTimeDigitized: placeVisitedTimeDigitized,
                    photoDigitizedTimes: photoDigitizedTimes
                ))
                placeList.append(place)
            }
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayStoriesArray: [[String: Any]] = detail.days.compactMap { day in
            guard let caption = day.dayCaption, !caption.isEmpty else { return nil }
            return ["date": dayFormatter.string(from: day.date), "story": caption]
        }

        var blogMetaData: [String: Any] = [
            "title": detail.title,
            "startTimestamp": startMs,
            "endTimestamp": endMs,
            "destinationName": detail.countryName ?? ""
        ]
        if !dayStoriesArray.isEmpty {
            blogMetaData["dayStories"] = dayStoriesArray
        }

        let payload: [String: Any] = [
            "username": username,
            "blogMetaData": blogMetaData,
            "placeList": placeList
        ]

        let placesWithDayStory = dayStoriesArray.count
        let placesWithPlaceStory = placeList.filter { $0["story"] != nil }.count
        let totalPhotosInPayload = placeList.compactMap { $0["photoList"] as? [[String: Any]] }.flatMap { $0 }
        let photosWithStoryInPayload = totalPhotosInPayload.filter { $0["story"] != nil }.count
        print("📦 [createBlogWithPlaces] Payload summary — \(placeList.count) places, dayStories: \(placesWithDayStory), placeStory: \(placesWithPlaceStory), photoStory: \(photosWithStoryInPayload)/\(totalPhotosInPayload.count)")

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

    /// Uploads a photo asset and sets it as the blog's cover photo. Returns the permanent cloud URL (also applied to matching draft photos by callers when needed).
    @discardableResult
    func uploadAndUpdateCoverPhoto(blogKey: Int, assetIdentifier: String) async throws -> String {
        let cloudURL = try await uploadPhoto(assetIdentifier: assetIdentifier)
        try await updateCoverPhoto(blogKey: blogKey, photoUri: cloudURL)
        print("✅ Cover photo updated for blogKey=\(blogKey)")
        return cloudURL
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

    /// Updates the sentiment value for a place visit on the backend.
    /// - Parameters:
    ///   - placeKey: The `visitedTimeDigitized` key for the place.
    ///   - sentiment: 1 = bad, 2 = neutral, 3 = good.
    func updateSentiment(placeKey: String, sentiment: Int) async throws {
        let payload: [String: Any] = [
            "visitedTimeDigitized": placeKey,
            "sentiment": sentiment
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/updateSentiment",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        print("✅ Sentiment updated: \(sentiment) for key=\(placeKey)")
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

    /// Updates the day-level story for an already-published blog.
    /// - Parameters:
    ///   - blogKey: The server-assigned blog key.
    ///   - dateKey: Zero-based index of the day within the trip.
    ///   - story: Story text. Pass "" to clear.
    func updateDayStory(blogKey: Int, dateKey: Int, story: String) async throws {
        print("🟡 [updateDayStory] blogKey=\(blogKey) dateKey=\(dateKey) text=\"\(story.prefix(60))\"")
        let payload: [String: Any] = [
            "blogKey": blogKey,
            "dateKey": dateKey,
            "story": story
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/trips/day-story",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        print("✅ [updateDayStory] done — blogKey=\(blogKey) dateKey=\(dateKey)")
    }

    /// Updates place-level or photo-level story on the backend (placeVisitHistory).
    /// - Parameters:
    ///   - placeKey: visitedTimeDigitized for the place.
    ///   - storyText: The story/caption text.
    ///   - photoIndex: If nil, updates place-level story; if set, updates that photo's story (index in filtered/included list).
    ///   - photoIndexType: "filtered" when photoIndex is index in included photos; "all" for full photoList index. Default "filtered".
    func updateStory(placeKey: String, storyText: String, photoIndex: Int? = nil, photoIndexType: String = "filtered") async throws {
        let level = photoIndex == nil ? "place" : "photo[\(photoIndex!)]"
        print("🟡 [updateStory] START — level:\(level) placeKey:\(placeKey) text:\"\(storyText)\"")
        var payload: [String: Any] = [
            "placeKey": placeKey,
            "storyText": storyText
        ]
        if let idx = photoIndex {
            payload["photoIndex"] = idx
            payload["photoIndexType"] = photoIndexType
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        do {
            let _: GenericResponse = try await request(
                endpoint: "/placeVisitHistory/story",
                method: "POST",
                body: body,
                requiresAuth: true
            )
            print("✅ [updateStory] SUCCESS — level:\(level) placeKey:\(placeKey)")
        } catch {
            print("❌ [updateStory] FAILED — level:\(level) placeKey:\(placeKey) error:\(error)")
            throw error
        }
    }

    /// Updates a single photo's inclusion state on the backend.
    /// - Parameters:
    ///   - placeKey: The `visitedTimeDigitized` of the containing place in placeVisitHistory.
    ///   - photo: The photo to add or delete (must have a cloudURL).
    ///   - operation: `"add"` to re-include, `"delete"` to exclude.
    /// - Returns: The `digitizedTime` string used in the request (store on `RecapPhoto.digitizedTime`
    ///   when adding a new photo so subsequent delete/re-add calls send the same value).
    @discardableResult
    func updatePhoto(placeKey: String, photo: RecapPhoto, operation: String, digitizedTimeZoneFallback: TimeZone? = nil) async throws -> String {
        guard let cloudURL = photo.cloudURL else {
            print("⚠️ [updatePhoto] photo has no cloudURL — skipping (op=\(operation) placeKey=\(placeKey))")
            return ""
        }

        // Use the digitizedTime stored on the photo at publish/upload time so the backend can match
        // the exact entry it recorded. Only re-compute if it was never stored (legacy data).
        let utc = TimeZone(identifier: "UTC")!
        let digitizedTime: String
        if let stored = photo.digitizedTime {
            digitizedTime = stored
            print("🔍 [updatePhoto] using stored digitizedTime=\(digitizedTime)")
        } else {
            // Legacy path: photo was published before digitizedTime field was introduced.
            // Re-compute using EXIF timezone only (same as createBlogWithPlaces — no geocoding fallback)
            // to minimise divergence.
            var tzSource = "utc"
            if let assetId = photo.localIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject {
                let tzFromAsset = await Self.getLocalTimeZone(for: asset)
                let tz = tzFromAsset ?? digitizedTimeZoneFallback ?? utc
                tzSource = tzFromAsset != nil ? "EXIF" : (digitizedTimeZoneFallback != nil ? "fallbackArg" : "utc")
                let creationDate = asset.creationDate ?? photo.timestamp
                digitizedTime = Self.digitizedTimeString(from: creationDate, timeZone: tz)
                print("🔍 [updatePhoto] legacy re-compute localId=\(assetId.prefix(20)) digitizedTime=\(digitizedTime) tzSource=\(tzSource)")
            } else {
                digitizedTime = Self.digitizedTimeString(from: photo.timestamp, timeZone: digitizedTimeZoneFallback ?? utc)
                print("🔍 [updatePhoto] legacy re-compute (no PHAsset) digitizedTime=\(digitizedTime) tzSource=\(tzSource)")
            }
        }

        var photoDict: [String: Any] = [
            "uri": cloudURL,
            "digitizedTime": digitizedTime,
            "inAppPhoto": true
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

        print("📤 [updatePhoto] op=\(operation) placeKey=\(placeKey) digitizedTime=\(digitizedTime) uri=\(cloudURL)")
        if let prettyJSON = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let prettyStr = String(data: prettyJSON, encoding: .utf8) {
            print("📤 [updatePhoto] payload:\n\(prettyStr)")
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/updatePhoto",
            method: "POST",
            body: body,
            requiresAuth: true
        )
        print("✅ [updatePhoto] SUCCESS op=\(operation) placeKey=\(placeKey) digitizedTime=\(digitizedTime)")
        return digitizedTime
    }

    // MARK: - Admin Analytics
    
    /// Fetches global dashboard analytics (admin only).
    /// Uses a direct request so we can log the raw JSON for debugging decode mismatches.
    func fetchDashboardAnalytics() async throws -> BackendDashboardAnalytics {
        guard let url = URL(string: baseURL + "/admin/dashboard/analytics/bloggo") else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthService.shared.currentJwtToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("🌐 [GET] \(url.absoluteString)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Log full raw response for debugging
        let rawJSON = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        print("📥 Admin Analytics \(httpResponse.statusCode): \(rawJSON)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: msg)
        }

        // Try decoding as { result, data: { ... } } wrapper first
        struct WrappedResponse: Decodable {
            let result: String?
            let data: BackendDashboardAnalytics?
            let message: String?
        }

        if let wrapped = try? JSONDecoder().decode(WrappedResponse.self, from: data),
           let analytics = wrapped.data {
            return analytics
        }

        // Fallback: try decoding analytics directly from root
        do {
            return try JSONDecoder().decode(BackendDashboardAnalytics.self, from: data)
        } catch {
            print("🚨 Analytics decode error: \(error)")
            throw APIError.decodingFailed(error)
        }
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

        let initialIncluded = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let initialWithURL = initialIncluded.filter { $0.cloudURL != nil }
        print("🔍 publishBlog — photos: \(initialIncluded.count) included, \(initialWithURL.count) have cloudURL (before upload pass)")

        do {
            // Upload any included photo that still lacks a cloud URI. createBlogWithPlaces omits photos without `uri`, which caused missing places/photos after publish.
            var workingDetail = detail
            var uploadedMissing = false
            for dIdx in workingDetail.days.indices {
                for sIdx in workingDetail.days[dIdx].placeStops.indices {
                    for pIdx in workingDetail.days[dIdx].placeStops[sIdx].photos.indices {
                        guard workingDetail.days[dIdx].placeStops[sIdx].photos[pIdx].isIncluded else { continue }
                        guard workingDetail.days[dIdx].placeStops[sIdx].photos[pIdx].cloudURL == nil else { continue }
                        let rawId = workingDetail.days[dIdx].placeStops[sIdx].photos[pIdx].localIdentifier?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !rawId.isEmpty else { continue }
                        let cloudURL = try await uploadPhoto(assetIdentifier: rawId)
                        workingDetail.days[dIdx].placeStops[sIdx].photos[pIdx].cloudURL = cloudURL
                        uploadedMissing = true
                    }
                }
            }
            if uploadedMissing {
                CreatedRecapBlogStore.shared.saveBlogDetail(workingDetail)
            }

            let allIncluded = workingDetail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
            print("🔍 publishBlog — after upload pass: \(allIncluded.count) included, \(allIncluded.filter { $0.cloudURL != nil }.count) have cloudURL")

            print("🔍 Step 1/3: Calling createBlogWithPlaces...")
            let (response, placeStopMapping) = try await createBlogWithPlaces(username: username, detail: workingDetail)
            print("✅ Blog created with blogKey: \(response.blogKey), placeIndices: \(response.placeIndices ?? [])")

            // Write the per-photo digitizedTime computed during publish back into workingDetail so that
            // future updatePhoto calls reuse the exact same value the backend recorded.
            var digitizedTimesWritten = 0
            for info in placeStopMapping {
                guard info.dayIdx < workingDetail.days.count,
                      info.stopIdx < workingDetail.days[info.dayIdx].placeStops.count else { continue }
                for pIdx in workingDetail.days[info.dayIdx].placeStops[info.stopIdx].photos.indices {
                    let photo = workingDetail.days[info.dayIdx].placeStops[info.stopIdx].photos[pIdx]
                    if let lid = photo.localIdentifier, let dt = info.photoDigitizedTimes[lid] {
                        workingDetail.days[info.dayIdx].placeStops[info.stopIdx].photos[pIdx].digitizedTime = dt
                        digitizedTimesWritten += 1
                    }
                }
            }
            if digitizedTimesWritten > 0 {
                print("📸 [publishBlog] stored digitizedTime on \(digitizedTimesWritten) photo(s)")
                CreatedRecapBlogStore.shared.saveBlogDetail(workingDetail)
            }

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
                CreatedRecapBlogStore.shared.applyCloudKeys(blogId: workingDetail.id, blogKey: response.blogKey, detail: workingDetail, placeMapping: placeMapping)
            } else if let indices = response.placeIndices, !indices.isEmpty {
                // Fall back to positional matching (zip truncates if server skipped some as duplicates)
                let placeMapping: [(dayIdx: Int, stopIdx: Int, placeIndex: Int, visitedTimeDigitized: String)] =
                    zip(placeStopMapping, indices).map { info, idx in
                        (dayIdx: info.dayIdx, stopIdx: info.stopIdx, placeIndex: idx, visitedTimeDigitized: info.visitedTimeDigitized)
                    }
                CreatedRecapBlogStore.shared.applyCloudKeys(blogId: workingDetail.id, blogKey: response.blogKey, detail: workingDetail, placeMapping: placeMapping)
            } else {
                // No place-level info — at least store the blogKey
                CreatedRecapBlogStore.shared.setBlogKey(blogId: workingDetail.id, blogKey: response.blogKey)
            }

            print("🔍 Step 2/3: Cover photo…")
            if let rawCoverId = workingDetail.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawCoverId.isEmpty {
                let coverMatch = allIncluded.first {
                    ($0.localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == rawCoverId
                }
                if let existingURL = coverMatch?.cloudURL {
                    try await updateCoverPhoto(blogKey: response.blogKey, photoUri: existingURL)
                    print("✅ Cover photo set (existing uploaded URI)")
                } else {
                    let cloudURL = try await uploadPhoto(assetIdentifier: rawCoverId)
                    try await updateCoverPhoto(blogKey: response.blogKey, photoUri: cloudURL)
                    CreatedRecapBlogStore.shared.applyCloudURLToLocalPhoto(
                        blogId: workingDetail.id,
                        localIdentifier: rawCoverId,
                        cloudURL: cloudURL
                    )
                    print("✅ Cover photo uploaded and set on blog; draft cloudURL updated")
                }
            } else {
                print("   (no cover selected)")
            }

            print("🔍 Step 3/3: Setting privacy to public...")
            try await setBlogPrivacy(blogKey: response.blogKey)
            print("✅ Privacy set to public for blogKey: \(response.blogKey)")

            print("🎉 publishBlog complete — all 3 steps succeeded")
            AppAnalytics.shared.trackEvent(name: "blog_published")
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

    // MARK: - Waitlist Registration

    struct WaitlistResponse: Decodable {
        let result: String?
        let message: String?
        let registeredAt: String?
    }

    /// Registers a user on the early-access waitlist.
    /// POST /waitlist — public endpoint (no auth required).
    /// Throws on network/server errors; silently succeeds on 409 (already registered).
    func registerWaitlist(userName: String, email: String) async throws {
        struct WaitlistPayload: Encodable {
            let userName: String
            let email: String
        }
        let payload = WaitlistPayload(userName: userName, email: email)
        do {
            let _: WaitlistResponse = try await post(endpoint: "/waitlist", body: payload, requiresAuth: false)
        } catch APIError.httpError(let statusCode, _) where statusCode == 409 {
            // Already on the waitlist — treat as success
            print("ℹ️ APIManager.registerWaitlist: already registered (409)")
        }
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
    /// localIdentifier → digitizedTime for each photo in this stop, as computed during publish.
    /// Used to write the exact digitizedTime back into RecapPhoto so future updatePhoto calls
    /// send the same value the backend recorded.
    let photoDigitizedTimes: [String: String]
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
    /// Day-level captions sent by the app as {"date":"yyyy-MM-dd","story":"..."}.
    let dayStories: [ServerDayStory]?
}

struct ServerTripPlace: Decodable {
    let placeIndex: Int
}

struct ServerDayStory: Decodable {
    /// "yyyy-MM-dd" formatted date string matching the day.
    let date: String?
    let story: String?
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
