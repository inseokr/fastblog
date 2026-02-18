//
//  SmartReminderService.swift
//  Capper
//

import Photos
import Foundation
import CoreLocation
import UserNotifications

struct SmartReminder: Identifiable {
    let id: UUID = UUID()
    let title: String
    let assets: [PHAsset]
    let cityName: String?
    let startDate: Date
    let endDate: Date
}

final class SmartReminderService {
    static let shared = SmartReminderService()
    
    private let calendar = Calendar.current
    private let dismissalKey = "blogify.smartReminder.lastDismissed"
    private let silenceDuration: TimeInterval = 3 * 24 * 3600 // 3 days
    
    private init() {}
    
    /// Checks for a high-value memory that hasn't been blogged yet.
    func checkReminders() async -> SmartReminder? {
        // 1. Check dismissal silence
        if let lastDismissed = UserDefaults.standard.object(forKey: dismissalKey) as? Date {
            if Date().timeIntervalSince(lastDismissed) < silenceDuration {
                return nil
            }
        }
        
        // 2. Fetch photos from last 30 days
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return nil }
        let assets = await fetchRecentAssets(start: start, end: end)
        
        // 3. Filter out photos already in blogs
        let usedIdentifiers = CreatedRecapBlogStore.shared.displayRecents.reduce(into: Set<String>()) { set, blog in
            // We need to fetch the detail to get all photo identifiers
            if let detail = CreatedRecapBlogStore.shared.getBlogDetail(blogId: blog.sourceTripId) {
                let ids = detail.days.flatMap { $0.placeStops.flatMap { $0.photos.compactMap(\.localIdentifier) } }
                set.formUnion(ids)
            }
        }
        
        let availableAssets = assets.filter { !usedIdentifiers.contains($0.localIdentifier) }
        
        // 4. Time Clustering (48h window)
        let timeClusters = clusterByTime(availableAssets, gapHours: 48)
        
        // 5. Location Sub-Clustering (1km radius) and Count Check (>= 20)
        var candidates: [SmartReminder] = []
        
        for cluster in timeClusters {
            let locationClusters = clusterByLocation(cluster, radius: 1000) // 1km
            
            for locCluster in locationClusters {
                guard locCluster.count >= 20 else { continue }
                
                // 7-day delay check
                guard let lastPhotoDate = locCluster.last?.creationDate,
                      Date().timeIntervalSince(lastPhotoDate) >= 7 * 24 * 3600 else { continue }
                
                if let reminder = await buildReminder(from: locCluster) {
                    candidates.append(reminder)
                    // Schedule notification if not already done for this cluster
                    schedulePushNotification(for: reminder)
                }
            }
        }
        
        // Return the most recent candidate
        return candidates.sorted { $0.endDate > $1.endDate }.first
    }
    
    func dismissReminder() {
        UserDefaults.standard.set(Date(), forKey: dismissalKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["SMART_REMINDER"])
    }
    
    // MARK: - Notifications
    
    private func schedulePushNotification(for reminder: SmartReminder) {
        let center = UNUserNotificationCenter.current()
        
        // Check if we already have a pending smart reminder notification
        center.getPendingNotificationRequests { requests in
            if requests.contains(where: { $0.identifier == "SMART_REMINDER" }) {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Don't forget your trip!"
            content.body = reminder.title
            content.sound = .default
            content.userInfo = ["type": "smart_reminder"]
            
            // Calculate trigger date: last photo date + 7 days, at 12 PM PST
            let lastPhotoDate = reminder.endDate
            var components = self.calendar.dateComponents([.year, .month, .day], from: self.calendar.date(byAdding: .day, value: 7, to: lastPhotoDate)!)
            
            // Set to 12 PM PST
            // Pacific Standard Time is UTC-8 (usually)
            components.hour = 12
            components.minute = 0
            components.second = 0
            components.timeZone = TimeZone(abbreviation: "PST")
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "SMART_REMINDER", content: content, trigger: trigger)
            
            center.add(request)
        }
    }
    
    // MARK: - Photo Logic
    
    private func fetchRecentAssets(start: Date, end: Date) async -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
    
    private func clusterByTime(_ assets: [PHAsset], gapHours: Double) -> [[PHAsset]] {
        guard !assets.isEmpty else { return [] }
        var result: [[PHAsset]] = []
        var current: [PHAsset] = [assets[0]]
        let gapSeconds = gapHours * 3600
        
        for i in 1..<assets.count {
            if let d1 = assets[i-1].creationDate, let d2 = assets[i].creationDate, d2.timeIntervalSince(d1) > gapSeconds {
                result.append(current)
                current = [assets[i]]
            } else {
                current.append(assets[i])
            }
        }
        result.append(current)
        return result
    }
    
    private func clusterByLocation(_ assets: [PHAsset], radius: Double) -> [[PHAsset]] {
        var clusters: [[PHAsset]] = []
        var remaining = assets
        
        while !remaining.isEmpty {
            guard let seed = remaining.first, let seedLoc = seed.location else {
                remaining.removeFirst()
                continue
            }
            
            let cluster = remaining.filter { asset in
                guard let loc = asset.location else { return false }
                return loc.distance(from: seedLoc) <= radius
            }
            
            clusters.append(cluster)
            remaining.removeAll { cluster.contains($0) }
        }
        
        return clusters
    }
    
    private func buildReminder(from assets: [PHAsset]) async -> SmartReminder? {
        guard let first = assets.first, let last = assets.last,
              let startDate = first.creationDate, let endDate = last.creationDate else { return nil }
        
        let location = assets.compactMap { $0.location }.first
        var cityName: String?
        if let location {
            let place = await GeocodingService.shared.place(for: location)
            cityName = place.cityName.isEmpty ? nil : place.cityName
        }
        
        let titleName = cityName ?? "your trip"
        let title = "You haven't turned your \(titleName) into a blog yet."
        
        return SmartReminder(
            title: title,
            assets: assets,
            cityName: cityName,
            startDate: startDate,
            endDate: endDate
        )
    }
}
