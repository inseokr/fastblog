import SwiftUI
import CoreLocation

@main
struct BloggoDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Pipeline — runs automatically on app launch. Based on real photos (EXIF).
@Observable
final class TripPipeline {
    var isRunning = true
    var photos: [PhotoItem] = []
    var clusters: [PlaceCluster] = []
    var funnel: [FunnelStage] = []
    var hero: PhotoItem?
    var stats: [TripStat] = []
    var moments: [HiddenMoment] = []
    var tripTitle = "My Trip"
    var tripSubtitle = ""

    // Captions + on-device RAG (reuses the caption path from Untitled Project 3)
    let ragStore = LocalRAGStore()
    var captionPairs: [UUID: CaptionService.Pair] = [:]
    var dna: TravelDNA?
    // Per-photo category (for Travel DNA category → photos filtering)
    var photoCategories: [UUID: TravelCategory] = [:]

    @MainActor
    func run() async {
        isRunning = true
        defer { isRunning = false }

        // 1. Load real photos + EXIF from the bundled TripPhotos folder
        let raw = TripPhotoLoader.load()
        guard !raw.isEmpty else { photos = []; return }

        // 2. Vision aesthetics + sharpness + saliency
        let scored = await AestheticScorer.score(raw)

        // 3. DBSCAN place clustering (falls back to time-based when no GPS)
        var built = Clustering.dbscan(scored)

        // 4. Reverse-geocode place names (network-dependent — keep "Stop N" on failure)
        let geocoder = CLGeocoder()
        for i in built.indices where built[i].photos.contains(where: \.hasGPS) {
            let c = built[i].center
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let pm = try? await geocoder.reverseGeocodeLocation(loc).first {
                built[i].name = pm.name ?? pm.subLocality ?? pm.locality ?? built[i].name
                if tripTitle == "My Trip", let city = pm.locality ?? pm.administrativeArea {
                    tripTitle = "\(city) Trip"
                }
            }
        }
        clusters = built

        // 5. Inject place names into photos (for hidden-moment pattern analysis)
        photos = scored.map { photo in
            var p = photo
            if let cluster = built.first(where: { $0.photos.contains(photo) }) {
                p.placeName = cluster.name
            }
            return p
        }

        // 6. 5-stage curation + hero
        funnel = CurationPipeline.run(photos)
        hero = CurationPipeline.heroPhoto(from: funnel)

        // 7. Stats + hidden moments
        stats = StatsEngine.compute(photos: photos, clusters: clusters,
                                    curated: funnel.last?.survivors.count ?? 0)
        moments = HiddenMoments.detect(photos: photos, clusters: clusters)

        // 8. RAG index tier 1: donate per-cluster Apple Maps POIs (real data, network — ignore failures)
        for cluster in clusters where cluster.photos.contains(where: \.hasGPS) {
            let c = cluster.center
            if let place = await AppleMapsContext.nearbyPlace(c) {
                ragStore.add(RAGDocument(
                    id: "poi-\(cluster.id.uuidString)", kind: .poi,
                    title: place.name ?? cluster.name,
                    text: place.describe(latitude: c.latitude, longitude: c.longitude,
                                         date: cluster.arrival),
                    latitude: c.latitude, longitude: c.longitude))
            }
        }

        // 9. Captions — final selected photos only (produce RAG OFF/ON, then donate the ON caption to the index)
        let finalPhotos = funnel.last?.survivors ?? []
        for photo in finalPhotos {
            var meta = PhotoMetadata()
            meta.captureDate = photo.timestamp
            if photo.hasGPS { meta.coordinate = photo.coordinate }
            meta.placeName = photo.placeName.isEmpty ? nil : photo.placeName

            let pair = await CaptionService.captionPair(image: photo.image, meta: meta,
                                                        store: ragStore)
            captionPairs[photo.id] = pair
            ragStore.add(RAGDocument(
                id: "caption-\(photo.id.uuidString)", kind: .caption,
                title: pair.placeNameRAG, text: pair.withRAG,
                latitude: photo.hasGPS ? photo.coordinate.latitude : nil,
                longitude: photo.hasGPS ? photo.coordinate.longitude : nil))

            // Classify each photo into a Travel-DNA category (keyword classifier — offline)
            let cls = await TravelDNAEngine.classify(pair.withRAG, useLLM: false)
            photoCategories[photo.id] = cls.major
        }

        // 10. Travel DNA — caption-based (reuses TravelDNAEngine from Untitled Project 3)
        let captions = captionPairs.values.map(\.withRAG)
        if !captions.isEmpty {
            dna = await TravelDNAEngine.buildDNA(captions: captions, useLLM: false)
        }

        // Subtitle: date range
        if let first = photos.first?.timestamp, let last = photos.last?.timestamp {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = "MMM d"
            tripSubtitle = first == last ? f.string(from: first)
                : "\(f.string(from: first)) – \(f.string(from: last))"
        }
    }

    /// Clusters grouped by day
    var days: [Date] {
        let cal = Calendar.current
        return Set(clusters.map { cal.startOfDay(for: $0.arrival) }).sorted()
    }

    func clusters(on day: Date) -> [PlaceCluster] {
        let cal = Calendar.current
        return clusters.filter { cal.startOfDay(for: $0.arrival) == day }
    }

    /// Photos taken on a given day, in time order (for the per-day record section)
    func photos(on day: Date) -> [PhotoItem] {
        let cal = Calendar.current
        return photos.filter { cal.startOfDay(for: $0.timestamp) == day }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// AI ranking of a day's clusters (top 3 by aesthetic score)
    func aiRanks(on day: Date) -> [UUID: Int] {
        let ranked = clusters(on: day)
            .map { ($0.id, $0.photos.map(\.aestheticScore).max() ?? 0) }
            .sorted { $0.1 > $1.1 }
        var result: [UUID: Int] = [:]
        for (i, entry) in ranked.prefix(3).enumerated() { result[entry.0] = i + 1 }
        return result
    }

    /// How many of a cluster's photos survived to the final selection
    func curatedCount(in cluster: PlaceCluster) -> Int {
        let finalIDs = Set((funnel.last?.survivors ?? []).map(\.id))
        return cluster.photos.filter { finalIDs.contains($0.id) }.count
    }

    /// A photo's final caption (the RAG-ON version) — used by highlight cards / blogging
    func caption(for photoID: UUID) -> String? {
        captionPairs[photoID]?.withRAG
    }

    /// Photos that have a caption pair (for the RAG comparison + search)
    var captionedPhotos: [PhotoItem] {
        (funnel.last?.survivors ?? []).filter { captionPairs[$0.id] != nil }
    }

    /// Photos whose caption contains the query (case-insensitive) — for the search screen
    func photosMatching(_ query: String) -> [PhotoItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return captionedPhotos.filter {
            (captionPairs[$0.id]?.withRAG.lowercased().contains(q)) ?? false
        }
    }

    /// Photos classified into a given Travel-DNA category — for the DNA category tap
    func photos(in category: TravelCategory) -> [PhotoItem] {
        captionedPhotos.filter { photoCategories[$0.id] == category }
    }
}
