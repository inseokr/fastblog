import SwiftUI

/// On-device RAG OFF/ON comparison — same input yields two outputs shown side by side.
/// ① Photo caption (incl. place-name grounding change) ② Day blog draft ③ Natural-language photo search
struct RAGCompareView: View {
    let pipeline: TripPipeline
    @State private var selectedID: UUID?
    @State private var draftPair: BlogDraftService.Pair?
    @State private var isDrafting = false
    @State private var searchText = ""

    private var selectedPhoto: PhotoItem? {
        pipeline.captionedPhotos.first { $0.id == selectedID } ?? pipeline.captionedPhotos.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    captionSection
                    draftSection
                    searchSection
                    Text("Retrieve: NLEmbedding cosine + Core Spotlight index · the iOS 27 SpotlightSearchTool path is enabled via the ENABLE_IOS27_RAG flag")
                        .font(.system(size: 10)).foregroundStyle(BloggoTheme.inkFaint)
                        .padding(.horizontal, 16).padding(.bottom, 20)
                }
                .padding(.top, 8)
            }
            .background(BloggoTheme.bg)
            .navigationTitle("RAG Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - ① Caption comparison

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("① Photo caption — place-name grounding", sub: "select a photo")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pipeline.captionedPhotos) { photo in
                        Image(uiImage: photo.image)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedPhoto?.id == photo.id ? BloggoTheme.blue : .clear,
                                        lineWidth: 2))
                            .onTapGesture { selectedID = photo.id }
                    }
                }
                .padding(.horizontal, 16)
            }

            if let photo = selectedPhoto, let pair = pipeline.captionPairs[photo.id] {
                VStack(spacing: 10) {
                    // place-name change summary
                    HStack(spacing: 6) {
                        Text("Place:").font(.system(size: 12)).foregroundStyle(BloggoTheme.inkFaint)
                        Text(pair.placeNameNoRAG)
                            .font(.system(size: 12)).foregroundStyle(BloggoTheme.inkDim)
                            .strikethrough(pair.placeNameChanged, color: .red.opacity(0.7))
                        if pair.placeNameChanged {
                            Image(systemName: "arrow.right").font(.system(size: 10))
                                .foregroundStyle(BloggoTheme.inkFaint)
                            Text(pair.placeNameRAG)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                        } else {
                            Text("(no change)").font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    outputCard(tag: "RAG OFF", tint: .gray, body: pair.noRAG,
                               footer: String(format: "%@ · geocoded name as-is · %.0f ms",
                                              pair.basePathLabel, pair.noRAGMs))
                    outputCard(tag: "RAG ON", tint: BloggoTheme.blue, body: pair.withRAG,
                               footer: String(format: "%d docs injected · %.0f ms",
                                              pair.retrieved.count, pair.ragMs))

                    if !pair.retrieved.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Retrieved evidence").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BloggoTheme.inkFaint)
                            ForEach(pair.retrieved) { hit in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(kindLabel(hit.doc.kind))
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(BloggoTheme.card, in: Capsule())
                                    Text("\(hit.doc.title) — \(hit.doc.text)")
                                        .font(.system(size: 11)).foregroundStyle(BloggoTheme.inkDim)
                                        .lineLimit(2)
                                    Spacer()
                                    Text(String(format: "%.2f", hit.score))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(BloggoTheme.inkFaint)
                                }
                            }
                        }
                        .padding(12).background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    } else {
                        Text("No retrieval → knowledge sentence omitted (③-b hard rule in action)")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - ② Blog draft comparison

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("② Day blog draft", sub: "grounded by your own captions")

            Button {
                Task {
                    isDrafting = true
                    let day = pipeline.days.first ?? .now
                    draftPair = await BlogDraftService.draftPair(
                        clusters: pipeline.clusters(on: day), store: pipeline.ragStore)
                    isDrafting = false
                }
            } label: {
                Label(isDrafting ? "Generating…" : "Generate Day 1 draft (OFF vs ON)",
                      systemImage: "square.split.2x1")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(BloggoTheme.blue, in: Capsule()).foregroundStyle(.white)
            }
            .disabled(isDrafting)
            .padding(.horizontal, 16)

            if let pair = draftPair {
                outputCard(tag: "RAG OFF", tint: .gray, body: pair.noRAG,
                           footer: "Template — place + time only")
                outputCard(tag: "RAG ON", tint: BloggoTheme.blue, body: pair.withRAG,
                           footer: "\(pair.cited.filter { $0.doc.kind == .caption }.count) quotes · \(pair.cited.filter { $0.doc.kind == .placeFact }.count) facts grounded")
            }
        }
    }

    // MARK: - ③ Natural-language photo search comparison

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("③ Natural-language search", sub: "e.g. \"the bridge at sunset\"")

            TextField("Query (matched against English captions)", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

            if !searchText.isEmpty {
                let keyword = keywordMatches(searchText)
                let rag = pipeline.ragStore.retrieve(query: searchText, k: 3, kinds: [.caption])
                outputCard(tag: "RAG OFF (keyword contains)", tint: .gray,
                           body: keyword.isEmpty ? "No matches"
                                : keyword.map { "· \($0)" }.joined(separator: "\n"),
                           footer: "\(keyword.count) — string contains")
                outputCard(tag: "RAG ON (embedding search)", tint: BloggoTheme.blue,
                           body: rag.isEmpty ? "No matches"
                                : rag.map { String(format: "· (%.2f) %@", $0.score, $0.doc.text) }
                                     .joined(separator: "\n"),
                           footer: "\(rag.count) — NLEmbedding cosine")
            }
        }
    }

    private func keywordMatches(_ query: String) -> [String] {
        let q = query.lowercased()
        return pipeline.captionPairs.values.map(\.withRAG).filter { $0.lowercased().contains(q) }
    }

    // MARK: - Shared components

    private func header(_ title: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Spacer()
            Text(sub).font(.system(size: 11)).foregroundStyle(BloggoTheme.inkFaint)
        }
        .padding(.horizontal, 16)
    }

    private func outputCard(tag: String, tint: Color, body text: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tag).font(.system(size: 10, weight: .heavy))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(tint.opacity(0.25), in: Capsule())
                .foregroundStyle(tint == .gray ? BloggoTheme.inkDim : Color(red: 0.5, green: 0.75, blue: 1))
            Text(text.isEmpty ? "(no output — check the detail log)" : text)
                .font(.system(size: 12.5)).foregroundStyle(.white).lineSpacing(2)
            Text(footer).font(.system(size: 10)).foregroundStyle(BloggoTheme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13).background(BloggoTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func kindLabel(_ kind: RAGDocument.Kind) -> String {
        switch kind {
        case .placeFact: return "FACT"
        case .poi: return "POI"
        case .caption: return "MY CAPTION"
        }
    }
}
