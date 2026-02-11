//
//  ClusterRowView.swift
//  Capper
//

import SwiftUI

struct ClusterRowView: View {
    let cluster: PlaceCluster
    var imageLoader: ImageLoader
    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            coverView
            VStack(alignment: .leading, spacing: 4) {
                Text(cluster.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if !cluster.subtitle.isEmpty {
                    Text(cluster.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(cluster.dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(cluster.photoCount) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .task {
            coverImage = await imageLoader.loadThumbnail(assetIdentifier: cluster.coverAssetIdentifier, targetSize: CGSize(width: 80, height: 80))
        }
    }

    private var coverView: some View {
        Group {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(ProgressView())
            }
        }
        .frame(width: 64, height: 64)
        .clipped()
        .cornerRadius(8)
    }
}

#Preview {
    List {
        ClusterRowView(
            cluster: PlaceCluster(
                resolvedTitle: "Central Park",
                subtitle: "New York, USA",
                dateRange: "Jan 15 – Jan 18, 2026",
                photoCount: 12,
                coverAssetIdentifier: "",
                assetIdentifiers: []
            ),
            imageLoader: ImageLoader()
        )
    }
}
