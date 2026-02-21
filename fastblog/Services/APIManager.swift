//
//  APIManager.swift
//  Capper
//
//  Centralized network manager that handles API requests, JSON encoding/decoding,
//  and automatically injects the JWT token into the Authorization header.
//

import Foundation
import UIKit

enum APIError: LocalizedError {
    case invalidURL
    case serializationFailed
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL configuration."
        case .serializationFailed: return "Failed to serialize the request body."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Received an invalid response from the server."
        case .httpError(let statusCode, let message): return "HTTP Error \(statusCode): \(message)"
        case .decodingFailed(let error): return "Failed to decode response: \(error.localizedDescription)"
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
            // Attempt to extract an error message from the response body
            var errorMessage = "Unknown server error."
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🚨 API Error Data JSON: \(json)")
                if let msg = json["message"] as? String {
                    errorMessage = msg
                } else if let err = json["error"] as? String {
                    errorMessage = err
                } else if let result = json["result"] as? String {
                    errorMessage = result
                }
            } else if let stringError = String(data: data, encoding: .utf8) {
                print("🚨 API Error Data String: \(stringError)")
                errorMessage = stringError
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

        // Compress to JPEG at 0.2 quality (matches LinkedSpaces compress: 0.2)
        guard let imageData = image.jpegData(compressionQuality: 0.2) else {
            throw APIError.serializationFailed
        }

        // Build multipart/form-data body — field name MUST be "photo"
        let boundary = UUID().uuidString
        var body = Data()
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
        let image = await ImageLoader.shared.loadImage(
            assetIdentifier: assetIdentifier,
            targetSize: CGSize(width: 1920, height: 1920)
        )
        guard let image else {
            throw APIError.serializationFailed
        }
        let filename = "IMG_\(assetIdentifier.prefix(8)).jpg"
        return try await uploadPhoto(image: image, filename: filename)
    }

    // MARK: - Blog Creation (Linkedspaces / Pocketverse)

    /// Creates a blog with places on the Pocketverse backend.
    /// Maps RecapBlogDetail → Linkedspaces payload format and POSTs to /placeVisitHistory/createBlogWithPlaces.
    /// - Returns: `CreateBlogResponse` containing the server-assigned `blogKey`.
    func createBlogWithPlaces(username: String, detail: RecapBlogDetail) async throws -> CreateBlogResponse {
        // Collect all timestamps to derive start/end
        let allPhotos = detail.days.flatMap(\.placeStops).flatMap { $0.photos.filter(\.isIncluded) }
        let timestamps = allPhotos.map { $0.timestamp }
        let startMs = timestamps.min().map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        let endMs = timestamps.max().map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0

        // Build placeList from all days/stops
        var placeList: [[String: Any]] = []
        for day in detail.days {
            for stop in day.placeStops {
                let includedPhotos = stop.photos.filter(\.isIncluded)
                guard !includedPhotos.isEmpty else { continue }

                let photoList: [[String: Any]] = includedPhotos.compactMap { photo in
                    guard let uri = photo.cloudURL else { return nil }
                    return [
                        "uri": uri,
                        "creationTime": Int64(photo.timestamp.timeIntervalSince1970 * 1000)
                    ]
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

                let visitedTime = Int64(includedPhotos[0].timestamp.timeIntervalSince1970 * 1000)

                let place: [String: Any] = [
                    "placeName": stop.placeTitle,
                    "coordinate": coord,
                    "visitedTime": visitedTime,
                    "photoList": photoList
                ]
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
        return try await request(
            endpoint: "/placeVisitHistory/createBlogWithPlaces",
            method: "POST",
            body: body,
            requiresAuth: true
        )
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
    func setBlogPrivacy(blogKey: Int, privacy: String = "public") async throws {
        let payload: [String: Any] = ["blogKey": blogKey, "privacy": privacy]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: GenericResponse = try await request(
            endpoint: "/placeVisitHistory/privacy-control",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

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
            let response = try await createBlogWithPlaces(username: username, detail: detail)
            print("✅ Blog created with blogKey: \(response.blogKey), placeIndices: \(response.placeIndices ?? [])")

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
}

struct CreateBlogResponse: Decodable {
    let blogKey: Int
    let placeIndices: [Int]?
}

private struct GenericResponse: Decodable {
    let result: String?
    let message: String?
}
