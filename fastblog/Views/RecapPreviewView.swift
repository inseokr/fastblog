//
//  RecapPreviewView.swift
//  Capper
//

import SwiftUI

struct RecapPreviewView: View {
    let draft: RecapDraft
    var imageLoader: ImageLoader
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(draft.clusters) { cluster in
                    sectionView(cluster: cluster)
                }
            }
            .padding()
        }
        .navigationTitle("Recap Preview")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await prepareShareContent()
                        showShare = true
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
    }

    private func sectionView(cluster: PlaceCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cluster.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
            if !cluster.subtitle.isEmpty {
                Text(cluster.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(cluster.dateRange)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cluster.assetIdentifiers.prefix(9), id: \.self) { id in
                    ClusterPreviewThumb(id: id, imageLoader: imageLoader)
                }
            }
        }
    }

    private func prepareShareContent() async {
        var items: [Any] = []
        items.append(draftSummaryText())
        for cluster in draft.clusters.prefix(5) {
            if let img = await imageLoader.loadThumbnail(assetIdentifier: cluster.coverAssetIdentifier, targetSize: CGSize(width: 600, height: 600)) {
                items.append(img)
            }
        }
        shareItems = items
    }

    private func draftSummaryText() -> String {
        var lines: [String] = ["My Recap"]
        for c in draft.clusters {
            lines.append("• \(c.displayTitle)\(c.subtitle.isEmpty ? "" : " — \(c.subtitle)") (\(c.photoCount) photos)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct ClusterPreviewThumb: View {
    let id: String
    var imageLoader: ImageLoader
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(ProgressView())
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .cornerRadius(4)
        .task {
            image = await imageLoader.loadThumbnail(assetIdentifier: id, targetSize: CGSize(width: 200, height: 200))
        }
    }
}

#Preview {
    NavigationStack {
        RecapPreviewView(
            draft: RecapDraft(clusters: [
                PlaceCluster(
                    resolvedTitle: "Central Park",
                    subtitle: "New York, USA",
                    dateRange: "Jan 15 – Jan 18",
                    photoCount: 3,
                    coverAssetIdentifier: "",
                    assetIdentifiers: ["", "", ""]
                )
            ]),
            imageLoader: ImageLoader()
        )
    }
}
