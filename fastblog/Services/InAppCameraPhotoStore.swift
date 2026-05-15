//
//  InAppCameraPhotoStore.swift
//  fastblog
//
//  Persists all photos taken with the in-app camera for the In-app Photo Gallery.
//

import Foundation
import SwiftUI
import UIKit

struct InAppCameraPhotoEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    /// Relative path under the store's photo directory (e.g. "abc123.jpg").
    let relativePath: String

    var fileURL: URL {
        InAppCameraPhotoStore.photoDirectory.appendingPathComponent(relativePath)
    }
}

/// Persists in-app camera photos to disk and exposes them for the In-app Photo Gallery (latest first).
final class InAppCameraPhotoStore: ObservableObject {
    static let shared = InAppCameraPhotoStore()

    /// All entries, sorted latest first for display.
    @Published private(set) var entries: [InAppCameraPhotoEntry] = []

    private static let listKey = "bloggo.inAppCameraPhotoList"
    private static let photoSubdir = "InAppCameraPhotos"

    static var photoDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(photoSubdir, isDirectory: true)
    }

    private let queue = DispatchQueue(label: "bloggo.inAppCameraPhotoStore")
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    /// In-memory cache to avoid repeated disk reads and flicker in the gallery.
    private var imageCache: [UUID: UIImage] = [:]

    private init() {
        ensureDirectoryExists()
        loadEntries()
    }

    private func ensureDirectoryExists() {
        let url = Self.photoDirectory
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func loadEntries() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let data = UserDefaults.standard.data(forKey: Self.listKey),
                  let decoded = try? self.jsonDecoder.decode([CodableEntry].self, from: data) else {
                DispatchQueue.main.async { self.entries = [] }
                return
            }
            let list = decoded.map { InAppCameraPhotoEntry(id: $0.id, timestamp: $0.timestamp, relativePath: $0.relativePath) }
                .sorted { $0.timestamp > $1.timestamp }
            DispatchQueue.main.async {
                self.entries = list
            }
        }
    }

    private func persistEntries(_ list: [InAppCameraPhotoEntry]) {
        let codable = list.map { CodableEntry(id: $0.id, timestamp: $0.timestamp, relativePath: $0.relativePath) }
        if let data = try? jsonEncoder.encode(codable) {
            UserDefaults.standard.set(data, forKey: Self.listKey)
        }
        DispatchQueue.main.async { [weak self] in
            self?.entries = list.sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Add a photo (call from main queue; image is written on background).
    func addPhoto(id: UUID = UUID(), image: UIImage, timestamp: Date = Date()) {
        ensureDirectoryExists()
        let relativePath = "\(id.uuidString).jpg"
        let url = Self.photoDirectory.appendingPathComponent(relativePath)
        let entry = InAppCameraPhotoEntry(id: id, timestamp: timestamp, relativePath: relativePath)
        let currentList = entries
        var newList = currentList
        newList.append(entry)

        queue.async { [weak self] in
            guard let self else { return }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url)
            DispatchQueue.main.async {
                self.persistEntries(newList)
            }
        }
        // Update UI immediately so session gallery feels responsive
        entries = newList.sorted { $0.timestamp > $1.timestamp }
    }

    /// Remove photos by id (deletes files and updates list). Call from main queue.
    func removePhotos(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let toRemove = entries.filter { ids.contains($0.id) }
        let listAfterRemoval = entries.filter { !ids.contains($0.id) }
        for id in ids { imageCache.removeValue(forKey: id) }
        queue.async { [weak self] in
            guard let self else { return }
            for entry in toRemove {
                try? FileManager.default.removeItem(at: entry.fileURL)
            }
            DispatchQueue.main.async {
                self.persistEntries(listAfterRemoval)
            }
        }
        entries = listAfterRemoval.sorted { $0.timestamp > $1.timestamp }
    }

    /// Load image for an entry (cached to prevent flicker). Call from main.
    func image(for entry: InAppCameraPhotoEntry) -> UIImage? {
        if let cached = imageCache[entry.id] { return cached }
        guard FileManager.default.fileExists(atPath: entry.fileURL.path),
              let data = try? Data(contentsOf: entry.fileURL),
              let image = UIImage(data: data) else { return nil }
        imageCache[entry.id] = image
        return image
    }

    private struct CodableEntry: Codable {
        let id: UUID
        let timestamp: Date
        let relativePath: String
    }
}
