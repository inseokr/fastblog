//
//  TravelDNAView.swift
//  Bloggo — Travel DNA screen (renders TravelDNAEngine output).
//
//  Feed it (photo, caption) pairs. It classifies each caption → aggregates personas → and, because
//  it now has the images, it can:
//    • show the top persona's photos as a backdrop behind the headline (dark, black overlay only),
//    • give every persona card its own representative photo background (dark overlay), and
//    • open a photo grid for a persona when its card is tapped.
//  Membership is gated by classification confidence so tapping a category shows the RIGHT photos.
//
//  Styling: dark navy throughout; text sits over a plain black-opacity overlay (no colored fills).
//  Card height follows its content, so the % number never clips on any phone aspect ratio.
//

import SwiftUI

/// One photo + the caption produced by the ③/④ caption paths.
struct DNAPhoto: Identifiable {
    let id = UUID()
    let image: UIImage?      // nil in previews / caption-only mode
    let caption: String
}

struct TravelDNAView: View {
    let items: [DNAPhoto]
    var useLLM: Bool = true

    @State private var dna: TravelDNA?
    @State private var byCategory: [TravelCategory: [DNAPhoto]] = [:]
    @State private var isLoading = true

    // Cache keyed by the input (captions + useLLM). Survives navigating away and back, so the DNA
    // shows instantly when the provided photos/captions haven't changed.
    private struct CacheEntry { let dna: TravelDNA; let byCategory: [TravelCategory: [DNAPhoto]] }
    private static var cache: [Int: CacheEntry] = [:]
    private var cacheKey: Int {
        var h = Hasher()
        for c in items.map(\.caption) { h.combine(c) }
        h.combine(items.count)
        h.combine(useLLM)
        return h.finalize()
    }

    // Dark palette (matches the "My Places" screen)
    private let bg = Color(red: 0.043, green: 0.06, blue: 0.15)
    private let cardFallback = Color.white.opacity(0.06)

    /// Convenience: caption-only (no photos) — used by previews / older callers.
    init(captions: [String], useLLM: Bool = true) {
        self.items = captions.map { DNAPhoto(image: nil, caption: $0) }
        self.useLLM = useLLM
    }
    init(items: [DNAPhoto], useLLM: Bool = true) {
        self.items = items
        self.useLLM = useLLM
    }

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    if isLoading {
                        ProgressView("Analyzing your photos…").padding(.top, 60)
                    } else if let dna {
                        VStack(alignment: .leading, spacing: 18) {
                            hero(dna)

                            let discovered = dna.personas.filter { $0.category != .other && $0.count > 0 }
                            Text("YOUR MIX · \(discovered.count) OF \(TravelCategory.allCases.count - 1) DISCOVERED")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.white.opacity(0.55)).tracking(1)

                            LazyVGrid(columns: grid, spacing: 12) {
                                ForEach(discovered) { p in
                                    NavigationLink { categoryPhotos(p.category) } label: { personaCard(p) }
                                        .buttonStyle(.plain)
                                }
                                ForEach(undiscovered(dna), id: \.self) { cat in
                                    undiscoveredCard(cat)
                                }
                            }

                            Text("From \(dna.total) photos · analyzed on-device")
                                .font(.caption).foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Travel DNA")
            .toolbarBackground(bg, for: .navigationBar)
        }
        .task { await build() }
    }

    // MARK: - Hero (headline over the top persona's photos; dark, black overlay only)

    private func hero(_ dna: TravelDNA) -> some View {
        let top = dna.personas.first?.category ?? .other
        let backdrop = byCategory[top] ?? []
        return VStack(spacing: 6) {
            Text("YOU ARE A").font(.caption).tracking(2).foregroundStyle(.white.opacity(0.8))
            Text("\(dna.personas.first?.emoji ?? "🧭") \(dna.headline)")
                .font(.title).bold().multilineTextAlignment(.center).foregroundStyle(.white)
            Text(dna.summary).font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            ZStack {
                cardFallback
                PhotoCollage(photos: backdrop)
                // Slight black opacity only — no colored gradient.
                LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Persona card (photo background + black overlay; height follows content → no clipping)

    private func personaCard(_ p: Persona) -> some View {
        let rep = byCategory[p.category]?.first?.image
        return VStack(alignment: .leading, spacing: 4) {
            Text(p.emoji).font(.system(size: 24))
            Spacer(minLength: 20)
            Text(p.title).font(.headline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            Text("\(Int(p.percent))%").font(.title3).bold().foregroundStyle(.white)
            if !p.topSubcategories.isEmpty {
                Text(p.topSubcategories.prefix(2).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(
            ZStack {
                if let rep {
                    Image(uiImage: rep).resizable().scaledToFill()
                } else {
                    cardFallback
                }
                // Black overlay only (≈50–75%), keeps text readable, no colored tint.
                LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func undiscoveredCard(_ cat: TravelCategory) -> some View {
        let info = travelTaxonomy[cat]!
        return VStack(alignment: .leading, spacing: 4) {
            Text(info.emoji).font(.system(size: 22)).opacity(0.5)
            Spacer(minLength: 20)
            Text(info.title).font(.subheadline).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("undiscovered").font(.caption2).foregroundStyle(.white.opacity(0.35))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(cardFallback)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            .foregroundStyle(.white.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Tapped category → its photos

    private func categoryPhotos(_ cat: TravelCategory) -> some View {
        let photos = byCategory[cat] ?? []
        let info = travelTaxonomy[cat]!
        return ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: grid, spacing: 10) {
                    ForEach(photos) { photo in
                        VStack(alignment: .leading, spacing: 4) {
                            if let img = photo.image {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(height: 150).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Text(photo.caption).font(.caption2)
                                .foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                        }
                    }
                }
                .padding(16)
                if photos.isEmpty {
                    Text("No photos confidently matched this category.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.5)).padding(.top, 40)
                }
            }
        }
        .navigationTitle("\(info.emoji) \(info.title) · \(photos.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(bg, for: .navigationBar)
    }

    // MARK: - Build

    private func build() async {
        // Cache hit: same photos/captions as before → show instantly, skip recompute.
        if let cached = Self.cache[cacheKey] {
            dna = cached.dna
            byCategory = cached.byCategory
            isLoading = false
            return
        }

        isLoading = true
        let captions = items.map(\.caption)

        // Per-photo classification → group photos by category (confidence-gated).
        let classes = await TravelDNAEngine.classifyBatch(captions, useLLM: useLLM)
        var grouped: [TravelCategory: [(DNAPhoto, Double)]] = [:]
        for (item, cls) in zip(items, classes) where
            cls.major != .other && cls.confidence >= TravelDNAEngine.categoryMembershipThreshold {
            grouped[cls.major, default: []].append((item, cls.confidence))
        }
        let groupedByCategory = grouped.mapValues { $0.sorted { $0.1 > $1.1 }.map(\.0) }
        byCategory = groupedByCategory

        // Personas / headline / summary from the aggregate.
        var result = TravelDNAEngine.aggregate(classes)
        result.summary = await TravelDNAEngine.lifestyleSummary(result)
        dna = result
        isLoading = false

        // Store for next time this view appears with the same input.
        Self.cache[cacheKey] = CacheEntry(dna: result, byCategory: groupedByCategory)
    }

    private func undiscovered(_ dna: TravelDNA) -> [TravelCategory] {
        let shown = Set(dna.personas.filter { $0.count > 0 }.map(\.category))
        return TravelCategory.allCases.filter { $0 != .other && !shown.contains($0) }
    }
}

/// A simple 2×2 (or fewer) collage used as the faded hero backdrop.
private struct PhotoCollage: View {
    let photos: [DNAPhoto]
    var body: some View {
        let imgs = Array(photos.compactMap(\.image).prefix(4))
        GeometryReader { geo in
            if imgs.isEmpty {
                Color.clear
            } else if imgs.count == 1 {
                Image(uiImage: imgs[0]).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                let cols = 2
                let rows = Int(ceil(Double(imgs.count) / Double(cols)))
                let w = geo.size.width / CGFloat(cols)
                let h = geo.size.height / CGFloat(rows)
                ZStack {
                    ForEach(Array(imgs.enumerated()), id: \.offset) { i, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: w, height: h).clipped()
                            .position(x: w * (CGFloat(i % cols) + 0.5),
                                      y: h * (CGFloat(i / cols) + 0.5))
                    }
                }
            }
        }
    }
}

#Preview("Travel DNA — Vancouver sample") {
    TravelDNAView(captions: [
        "Two lattes with intricate latte art on a wooden table at a cozy café in Victory Square.",
        "A grilled meat platter with a poached egg on a pink ceramic dish at a downtown izakaya.",
        "A round plate of sushi with shrimp and fish, a teapot and chopsticks, at a sushi bar.",
        "The busy entrance to the Capilano Suspension Bridge, people under a wooden canopy.",
        "A person dispensing orange gelato into a cup at a café near Capilano.",
        "A serene afternoon at Capilano where towering pines frame a calm river under a blue sky.",
        "A woman in a gray jacket gently holds a falcon at the Raptor Experience.",
        "Waves crash on the sandy beach at English Bay as the sun sets over the ocean."
    ], useLLM: false)
}
