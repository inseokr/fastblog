import SwiftUI
import MapKit

// MARK: - Design tokens (dark theme ported from day1_hero_comparison.html)

enum BloggoTheme {
    static let bg = Color(red: 0.043, green: 0.055, blue: 0.078)   // #0b0e14
    static let card = Color.white.opacity(0.06)
    static let blue = Color(red: 0.039, green: 0.518, blue: 1.0)   // #0A84FF
    static let inkDim = Color.white.opacity(0.72)
    static let inkFaint = Color.white.opacity(0.5)
    static let amber = LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.42),
                                               Color(red: 1, green: 0.62, blue: 0.26)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct ContentView: View {
    @State private var pipeline = TripPipeline()

    var body: some View {
        ZStack {
            BloggoTheme.bg.ignoresSafeArea()
            if pipeline.isRunning {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Analyzing on-device — Vision · DBSCAN · EXIF")
                        .font(.footnote).foregroundStyle(BloggoTheme.inkDim)
                }
            } else if pipeline.photos.isEmpty {
                EmptyStateView()
            } else {
                TabView {
                    BlogView(pipeline: pipeline)
                        .tabItem { Label("Blog", systemImage: "book.pages") }
                    DNAView(pipeline: pipeline)
                        .tabItem { Label("Trip DNA", systemImage: "dna") }
                    SearchView(pipeline: pipeline)
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    RAGCompareView(pipeline: pipeline)
                        .tabItem { Label("RAG", systemImage: "square.split.2x1") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await pipeline.run() }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44)).foregroundStyle(BloggoTheme.inkFaint)
            Text("No photos").font(.headline).foregroundStyle(.white)
            Text("Drag a \"TripPhotos\" folder of original photos (HEIC/JPEG)\ninto the Xcode project. Their EXIF capture time & GPS are used as-is.")
                .font(.footnote).foregroundStyle(BloggoTheme.inkDim)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Atmosphere helpers (meaningful blogging info: place · time · mood)

enum Atmosphere {
    static func daypartEmoji(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return "🌅"; case 11..<17: return "☀️"; case 17..<21: return "🌆"
        default: return "🌙"
        }
    }
    static func moodLabel(_ date: Date, goldenHour: Bool) -> String {
        if goldenHour { return "Golden hour" }
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return "Fresh morning"
        case 11..<17: return "Bright midday"
        case 17..<21: return "Warm evening"
        default: return "City at night"
        }
    }
    static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
    static func goldenHour(_ p: PhotoItem) -> Bool {
        p.hasGPS && StatsEngine.isGoldenHour(date: p.timestamp, gps: p.coordinate)
    }
}

// MARK: - Blog (Variant B: the hero itself is a swipeable IG-style highlight carousel)

struct BlogView: View {
    let pipeline: TripPipeline

    /// Highlight photos = top curated survivors by aesthetic score (multiple images for the carousel)
    private var highlights: [PhotoItem] {
        pipeline.captionedPhotos
            .sorted { $0.aestheticScore > $1.aestheticScore }
            .prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HeroHighlightCarousel(pipeline: pipeline, highlights: highlights)

                // Per-day sections stacked below (Day 1, 2, 3 …)
                ForEach(Array(pipeline.days.enumerated()), id: \.offset) { i, day in
                    DaySection(pipeline: pipeline, day: day, dayNumber: i + 1)
                }

                sectionHeader("Trip Data Report", sub: "generated on-device")
                StatsSection(stats: pipeline.stats)

                if !pipeline.moments.isEmpty {
                    sectionHeader("Hidden Moments the AI Found", sub: "EXIF pattern analysis")
                    MomentsSection(moments: pipeline.moments)
                        .padding(.bottom, 24)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func sectionHeader(_ title: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Spacer()
            Text(sub).font(.system(size: 11.5)).foregroundStyle(BloggoTheme.inkFaint)
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
    }
}

// MARK: - Hero: swipeable highlight carousel (Instagram-style) + Share button

struct HeroHighlightCarousel: View {
    let pipeline: TripPipeline
    let highlights: [PhotoItem]
    @State private var index = 0
    @State private var showShareSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            // Swipeable full-bleed photos (swipe right like an IG post)
            TabView(selection: $index) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { i, photo in
                    HeroSlide(pipeline: pipeline, photo: photo).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 540)

            // Progress bar (story style)
            HStack(spacing: 4) {
                ForEach(highlights.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.white : Color.white.opacity(0.3))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 14).padding(.top, 52)

            // Fixed overlay: title + stats + DNA badge + Share
            VStack(spacing: 9) {
                Text(pipeline.tripTitle)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                Text(pipeline.tripSubtitle)
                    .font(.system(size: 12)).foregroundStyle(BloggoTheme.inkDim)
                HStack(spacing: 8) {
                    Text("\(pipeline.days.count) Days"); Text("·")
                    Text("\(pipeline.clusters.count) Moments"); Text("·")
                    Text("\(pipeline.photos.count) Photos")
                }
                .font(.system(size: 12)).foregroundStyle(BloggoTheme.inkDim)
                if let dna = pipeline.dna, let top = dna.personas.first {
                    Text("\(top.emoji) \(dna.headline)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                Button { showShareSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text("Share to Instagram").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .background(BloggoTheme.amber, in: Capsule())
                    .foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0))
                    .shadow(color: .black.opacity(0.3), radius: 7, y: 3)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.top, 74)
            .allowsHitTesting(true)
        }
        .frame(height: 540)
        .sheet(isPresented: $showShareSheet) {
            ShareMockSheet(images: highlights.map(\.image), title: pipeline.tripTitle)
        }
    }
}

struct HeroSlide: View {
    let pipeline: TripPipeline
    let photo: PhotoItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: photo.image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity).frame(height: 540).clipped()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .clear, location: 0.35),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.8), location: 1)
            ], startPoint: .top, endPoint: .bottom)

            // Per-slide caption: place · time · mood + AI caption
            VStack(alignment: .leading, spacing: 6) {
                if !photo.placeName.isEmpty {
                    Text(photo.placeName)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }
                HStack(spacing: 5) {
                    chip("\(Atmosphere.daypartEmoji(photo.timestamp)) \(Atmosphere.timeLabel(photo.timestamp))")
                    chip(Atmosphere.moodLabel(photo.timestamp, goldenHour: Atmosphere.goldenHour(photo)))
                }
                if let caption = pipeline.caption(for: photo.id) {
                    Text(caption)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(16).padding(.bottom, 8)
        }
        .frame(height: 540).clipped()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
    }
}

/// Non-functional Instagram share mock (preview of the shareable images)
struct ShareMockSheet: View {
    let images: [UIImage]
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Preview — \(images.count) images will be shared as a carousel post")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.top, 8)
                    ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable().aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity).frame(height: 300).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("(Demo — actual Instagram sharing is not wired up)")
                        .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 20)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Per-day section: that day's photos + simple blogging info

struct DaySection: View {
    let pipeline: TripPipeline
    let day: Date
    let dayNumber: Int

    private var dayPhotos: [PhotoItem] { pipeline.photos(on: day) }
    private var dayClusters: [PlaceCluster] { pipeline.clusters(on: day) }

    private var trail: [CLLocationCoordinate2D] {
        dayPhotos.filter(\.hasGPS).map(\.coordinate)
    }
    private var dateLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE, MMM d"
        return f.string(from: day)
    }
    private var placesLabel: String {
        Set(dayClusters.map(\.name)).sorted().joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(dayNumber)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(dateLabel) · \(dayPhotos.count) photos")
                    .font(.system(size: 11.5)).foregroundStyle(BloggoTheme.inkFaint)
            }
            if !placesLabel.isEmpty {
                Text(placesLabel).font(.system(size: 12)).foregroundStyle(BloggoTheme.inkDim)
            }

            // that day's route
            if trail.count > 1 {
                Map {
                    MapPolyline(coordinates: trail).stroke(BloggoTheme.blue, lineWidth: 2.5)
                    if let s = trail.first {
                        Annotation("START", coordinate: s) {
                            Circle().fill(.green).frame(width: 9, height: 9)
                        }
                    }
                }
                .allowsHitTesting(false)
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // that day's photos with per-photo info
            ForEach(dayPhotos) { photo in
                DayPhotoRow(pipeline: pipeline, photo: photo)
            }
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }
}

struct DayPhotoRow: View {
    let pipeline: TripPipeline
    let photo: PhotoItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(uiImage: photo.image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.placeName.isEmpty ? "Untitled spot" : photo.placeName)
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 5) {
                    infoChip("\(Atmosphere.daypartEmoji(photo.timestamp)) \(Atmosphere.timeLabel(photo.timestamp))")
                    infoChip(Atmosphere.moodLabel(photo.timestamp, goldenHour: Atmosphere.goldenHour(photo)))
                }
                if let caption = pipeline.caption(for: photo.id) {
                    Text(caption).font(.system(size: 11.5)).foregroundStyle(BloggoTheme.inkDim)
                        .lineLimit(3)
                } else {
                    Text("Not selected in final curation")
                        .font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(0.14), in: Capsule())
    }
}

// MARK: - Stats / Moments sections

struct StatsSection: View {
    let stats: [TripStat]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(stats) { stat in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: stat.icon).font(.system(size: 15))
                        .foregroundStyle(BloggoTheme.blue).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stat.label).font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
                        Text(stat.value).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                        Text(stat.note).font(.system(size: 11)).foregroundStyle(BloggoTheme.inkDim)
                    }
                    Spacer()
                }
                .padding(12).background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
    }
}

struct MomentsSection: View {
    let moments: [HiddenMoment]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(moments) { moment in
                VStack(alignment: .leading, spacing: 5) {
                    Text(moment.title).font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text(moment.body).font(.system(size: 12.5)).foregroundStyle(BloggoTheme.inkDim)
                        .lineSpacing(2)
                    Text("Source: \(moment.source)").font(.system(size: 10.5))
                        .foregroundStyle(BloggoTheme.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13).background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Trip DNA (tap a category → its photos)

struct DNAView: View {
    let pipeline: TripPipeline
    @State private var selectedCategory: TravelCategory?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let dna = pipeline.dna {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You are a").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                            Text(dna.headline).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            Text(dna.summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [Color(red: 0.48, green: 0.36, blue: 1),
                                                            Color(red: 1, green: 0.37, blue: 0.62)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 18))

                        Text("Tap a category to see its photos")
                            .font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)

                        ForEach(dna.personas) { persona in
                            Button { selectedCategory = persona.category } label: {
                                PersonaRow(persona: persona,
                                           photoCount: pipeline.photos(in: persona.category).count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                } else {
                    Text("Not enough captions to build Travel DNA yet.")
                        .font(.footnote).foregroundStyle(BloggoTheme.inkDim).padding(40)
                }
            }
            .background(BloggoTheme.bg)
            .navigationTitle("Trip DNA")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedCategory) { cat in
                CategoryPhotosView(pipeline: pipeline, category: cat)
            }
        }
    }
}

struct PersonaRow: View {
    let persona: Persona
    let photoCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(persona.emoji).font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(persona.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(photoCount) photos · \(Int(persona.percent))%")
                        .font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(BloggoTheme.blue)
                            .frame(width: geo.size.width * CGFloat(persona.percent / 100))
                    }
                }
                .frame(height: 7)
            }
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(BloggoTheme.inkFaint)
        }
        .padding(12).background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CategoryPhotosView: View {
    let pipeline: TripPipeline
    let category: TravelCategory

    private var photos: [PhotoItem] { pipeline.photos(in: category) }
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: photo.image)
                            .resizable().aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity).frame(height: 150).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        if let caption = pipeline.caption(for: photo.id) {
                            Text(caption).font(.system(size: 10)).foregroundStyle(BloggoTheme.inkDim)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(BloggoTheme.bg)
        .navigationTitle("\(travelTaxonomy[category]?.title ?? "Photos") · \(photos.count)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Search (shows photos whose caption contains the query)

struct SearchView: View {
    let pipeline: TripPipeline
    @State private var query = ""
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var results: [PhotoItem] { pipeline.photosMatching(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search your photos by what's in them — e.g. \"bridge\", \"coffee\", \"sunset\"")
                        .font(.system(size: 12)).foregroundStyle(BloggoTheme.inkFaint)

                    // quick chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["bridge", "food", "coffee", "sunset", "night"], id: \.self) { term in
                                Button { query = term } label: {
                                    Text(term).font(.system(size: 12))
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(.white.opacity(0.1), in: Capsule())
                                        .foregroundStyle(BloggoTheme.inkDim)
                                }
                            }
                        }
                    }

                    if !query.isEmpty {
                        Text("\(results.count) photos match \"\(query)\"")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(results) { photo in
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(uiImage: photo.image)
                                        .resizable().aspectRatio(1, contentMode: .fill)
                                        .frame(maxWidth: .infinity).frame(height: 150).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    if let caption = pipeline.caption(for: photo.id) {
                                        Text(caption).font(.system(size: 10))
                                            .foregroundStyle(BloggoTheme.inkDim).lineLimit(2)
                                    }
                                }
                            }
                        }
                        if results.isEmpty {
                            Text("No matches. Captions are generated on-device — try a broader word.")
                                .font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
                        }
                    }
                }
                .padding(16)
            }
            .background(BloggoTheme.bg)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search photos by content")
        }
    }
}

#Preview { ContentView() }
