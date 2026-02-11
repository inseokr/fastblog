//
//  TripPhotoSelectionService.swift
//  Capper
//
//  Created for deterministic "Best 3 Photos" selection per place cluster.
//

import Foundation
import Photos
import CoreLocation

actor TripPhotoSelectionService {
    static let shared = TripPhotoSelectionService()
    
    private let placeClusteringService = PlaceClusteringService()
    
    /// Main entry point: Given a TripDraft, fetch its assets, cluster them, select top 3 per cluster,
    /// and return a new TripDraft with those photos marked isSelected=true.
    func selectTopPhotosPerCluster(trip: TripDraft) async -> TripDraft {
        // 1. Collect all local identifiers from the trip
        let allPhotoIds = trip.days.flatMap { $0.photos }.compactMap { $0.localIdentifier }
        guard !allPhotoIds.isEmpty else {
            print("[TripPhotoSelectionService] No local identifiers found in trip.")
            return trip
        }
        
        // 2. Fetch PHAssets
        let assets = fetchAssets(with: allPhotoIds)
        guard !assets.isEmpty else {
            print("[TripPhotoSelectionService] No matching PHAssets found.")
            return trip
        }
        
        // 3. Cluster using PlaceClusteringService
        // Note: PlaceClusteringService.cluster expects strict time/location sorting usually, 
        // but we'll trust it handles the list we give. 
        // We probably should sort assets by creationDate first just in case.
        let sortedAssets = assets.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
        
        let clusters = placeClusteringService.cluster(assets: sortedAssets)
        print("[TripPhotoSelectionService] Found \(clusters.count) place clusters.")
        
        var selectedAssetIds: Set<String> = []
        
        // 4. For each cluster, select top 3
        for (index, cluster) in clusters.enumerated() {
            let clusterAssets = sortedAssets.filter { cluster.assetIdentifiers.contains($0.localIdentifier) }
            let best3 = selectBestPhotos(from: clusterAssets, maxCount: 3)
            
            print("[TripPhotoSelectionService] Cluster \(index): \(clusterAssets.count) photos -> selected \(best3.count)")
            best3.forEach { selectedAssetIds.insert($0.localIdentifier) }
        }
        
        // 5. Update TripDraft
        var updatedTrip = trip
        for dayIdx in updatedTrip.days.indices {
            for photoIdx in updatedTrip.days[dayIdx].photos.indices {
                if let localId = updatedTrip.days[dayIdx].photos[photoIdx].localIdentifier {
                    if selectedAssetIds.contains(localId) {
                        updatedTrip.days[dayIdx].photos[photoIdx].isSelected = true
                    } else {
                        updatedTrip.days[dayIdx].photos[photoIdx].isSelected = false
                    }
                }
            }
        }
        
        return updatedTrip
    }
    
    private func fetchAssets(with localIdentifiers: [String]) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        // We can fetch all at once
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: fetchOptions)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
    
    /// Deterministic selection logic
    /// 1. Higher resolution (pixel count)
    /// 2. Closest to centroid
    /// 3. Diversity of timestamps (not implemented yet, but implicitly handled by "best" if we want)
    ///    The prompt asks for "Prefer a diversity of timestamps within the cluster". 
    ///    We can achieve this by penalizing photos that are too close in time to already selected ones? 
    ///    Or pre-filtering duplicates/bursts.
    ///    Let's stick to the prompt's scoring order.
    private func selectBestPhotos(from assets: [PHAsset], maxCount: Int) -> [PHAsset] {
        if assets.count <= maxCount { return assets }
        
        // Calculate centroid for this cluster
        let locations = assets.compactMap { $0.location }
        let centroid: CLLocation?
        if !locations.isEmpty {
            let avgLat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
            let avgLon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
            centroid = CLLocation(latitude: avgLat, longitude: avgLon)
        } else {
            centroid = nil
        }
        
        // Score each asset
        let scoredAssets = assets.map { asset -> (asset: PHAsset, score: Double) in
            var score: Double = 0
            
            // 1. Resolution (pixel count) - Normalized roughly. 
            // 12MP = 12,000,000. Let's say max score component is 1000.
            let pixels = Double(asset.pixelWidth * asset.pixelHeight)
            let resScore = min(pixels / 10000.0, 1000.0) // Cap to avoid overflow dominance? No, just use raw.
            // Actually, simply sorting by tuple is easier for strict priority.
            
            // Let's implement a comparator instead of a single scalar score, for strict priority.
            return (asset, 0) 
        }
        
        // Sort using the prompt's priority list
        let sorted = assets.sorted { a, b in
            // 1. Photo quality proxy (Resolution)
            let resA = a.pixelWidth * a.pixelHeight
            let resB = b.pixelWidth * b.pixelHeight
            if resA != resB {
                return resA > resB // Higher is better
            }
            
            // 2. Closest to centroid
            if let c = centroid {
                let distA = a.location?.distance(from: c) ?? Double.infinity
                let distB = b.location?.distance(from: c) ?? Double.infinity
                if abs(distA - distB) > 1.0 { // 1 meter tolerance
                    return distA < distB // Closer is better
                }
            }
            
            // 3. Diversity of timestamps (This is hard to do in a simple sort. 
            //    Usually "Diversity" means "pick one, then pick next that is far away".
            //    The prompt says "Prefer a diversity...".
            //    If we just sort, we pick the top 3 best quality.
            //    If we want diversity, we should pick iteratively.
            //    Let's implement iterative selection below.
            
            // 4. Stable tie-breaker
            if let da = a.creationDate, let db = b.creationDate, da != db {
                return da < db 
            }
            return a.localIdentifier < b.localIdentifier
        }
        
        // If simply sorting is enough:
        // return Array(sorted.prefix(maxCount))
        
        // Implementation of Diversity (Iterative Selection)
        // We want to pick `maxCount` photos.
        // We pick the absolute best one first.
        // Then we pick the next best one that is "sufficiently different" in time from the selected ones?
        // Or we just penalize temporal proximity in the scoring of subsequent picks.
        
        var candidates = sorted // Already sorted by Quality -> Centroid -> Date
        var selected: [PHAsset] = []
        
        while selected.count < maxCount && !candidates.isEmpty {
            // Pick the first one (highest quality static score)
            // But wait, the "Diversity" rule is priority #3. 
            // If "Resolution" (#1) is much better, we take it regardless of diversity?
             
            // PROMPT: "Use this deterministic scoring order (highest priority first): 1) Quality, 2) Centroid, 3) Diversity"
            // This implies: Quality trumps Diversity.
            // So if I have 3 photos:
            // A: High Res, 12:00
            // B: High Res, 12:00:01 (Duplicate)
            // C: Low Res, 15:00
            
            // If strict priority: 
            // 1. A vs B vs C -> A and B are top because High Res.
            // So we pick A and B. C is ignored.
            // But then we have duplicates.
            
            // Use "Diversity" usually implies we filter out near-duplicates *before* or *during* selection.
            // "Prefer a diversity... (avoid near-duplicates back-to-back)"
            
            // Interpretation:
            // "Photo quality" is the primary sort key. 
            // BUT "Diversity" is a rule to "avoid near-duplicates".
            // A common approach: Greedy selection with penalty.
            
            // Let's stick to a simpler interpretation for "Execution-Only":
            // Strict sort by Quality then Centroid.
            // Then, take the top N.
            // BUT, filter out "duplicates" first?
            
            // Let's refine the sort to just be:
            // 1. Filter out bursts (keep best 1 of burst).
            // 2. Sort remaining by Quality + Centroid.
            // 3. Take top 3.
            
            // Burst logic: timestamps within < 1.0s?
            break // Handled below
        }
        
        // Refined Strategy:
        // 1. Group by "Time Buckets" or detect Bursts. 
        //    (Photos within 1s of each other).
        //    Keep only the BEST photo from each burst.
        // 2. From the surviving unique moments, sort by (Resolution, Centroid).
        // 3. Take top 3.
        
        // deduplicate bursts
        var uniqueMoments: [PHAsset] = []
        if !sorted.isEmpty {
            uniqueMoments.append(sorted[0])
            for i in 1..<sorted.count {
                let prev = uniqueMoments.last!
                let curr = sorted[i]
                
                let t1 = prev.creationDate?.timeIntervalSince1970 ?? 0
                let t2 = curr.creationDate?.timeIntervalSince1970 ?? 0
                
                if abs(t2 - t1) < 1.0 {
                    // It's a burst/duplicate.
                    // Since 'sorted' is already sorted by Quality, 'prev' is better or equal to 'curr' 
                    // (because we sorted descending logic? Wait, my sort above was quality descending? 
                    // Let's check sort implementation).
                    
                    // My sort above:
                    // resA > resB -> true. So Higher Res comes first.
                    // So sorted[0] is the highest resolution.
                    
                    // If we process in order of Quality, we implicitly keep the best logic?
                    // No, 'sorted' list is by quality. Timestamps are mixed.
                    
                    // We need to deduplicate based on time.
                    // Let's sort by TIME first to find bursts easily.
                }
            }
        }
        
        // Correct approach for Diversity + Quality:
        // 1. Sort by Time to identify bursts.
        let timeSorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        
        var distinctCandidates: [PHAsset] = []
        var currentBurst: [PHAsset] = []
        
        for asset in timeSorted {
            if let last = currentBurst.last,
               let t1 = last.creationDate?.timeIntervalSince1970,
               let t2 = asset.creationDate?.timeIntervalSince1970,
               abs(t2 - t1) < 2.0 { // 2 seconds threshold for "duplicate/burst"
                currentBurst.append(asset)
            } else {
                // Flush previous burst
                if !currentBurst.isEmpty {
                    distinctCandidates.append(bestInBurst(currentBurst, centroid: centroid))
                }
                currentBurst = [asset]
            }
        }
        // Flush last
        if !currentBurst.isEmpty {
            distinctCandidates.append(bestInBurst(currentBurst, centroid: centroid))
        }
        
        // now we have distinct moments (best of each burst).
        // Sort these by Quality (Res) then Centroid.
        let finalSorted = distinctCandidates.sorted { a, b in
            // 1. Resolution
            let resA = a.pixelWidth * a.pixelHeight
            let resB = b.pixelWidth * b.pixelHeight
            if resA != resB {
                return resA > resB
            }
            // 2. Centroid
            if let c = centroid {
                let distA = a.location?.distance(from: c) ?? Double.infinity
                let distB = b.location?.distance(from: c) ?? Double.infinity
                return distA < distB
            }
            // 4. Stable
            return a.localIdentifier < b.localIdentifier
        }
        
        return Array(finalSorted.prefix(maxCount))
    }
    
    private func bestInBurst(_ assets: [PHAsset], centroid: CLLocation?) -> PHAsset {
        if assets.count == 1 { return assets[0] }
        return assets.max { a, b in
            // Return true if A < B (so max returns B). We want "Best" so we want A < B means B is better.
            
            // 1. Resolution
            let resA = a.pixelWidth * a.pixelHeight
            let resB = b.pixelWidth * b.pixelHeight
            if resA != resB {
                return resA < resB // Higher is better
            }
            // 2. Centroid
            if let c = centroid {
                let distA = a.location?.distance(from: c) ?? Double.infinity
                let distB = b.location?.distance(from: c) ?? Double.infinity
                return distA > distB // Smaller distance is better
            }
            return false
        } ?? assets[0]
    }
}
