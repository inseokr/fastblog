//
//  RecapBuilderView.swift
//  Capper
//

import SwiftUI
import PhotosUI

@MainActor
struct RecapBuilderView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var draft: RecapDraft = RecapDraft()
    @State private var isOrganizing = false
    @State private var permissionDenied = false
    @State private var showRename: PlaceCluster?
    @State private var navigateToPreview = false
    @State private var imageLoader = ImageLoader()

    private let clusteringService = PlaceClusteringService()
    private let photoService = PhotoAssetService.shared
    private let geocodingService = GeocodingService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isOrganizing {
                    organizingView
                } else if draft.clusters.isEmpty {
                    emptyStateView
                } else {
                    clusterListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Capper")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 500,
                        matching: .images
                    ) {
                        Label("Pick Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedItems) { _, new in
                        guard !new.isEmpty else { return }
                        startClustering(items: new)
                    }
                }
            }
            .sheet(item: $showRename) { cluster in
                RenamePlaceView(
                    placeTitle: cluster.displayTitle,
                    onSave: { newTitle in
                        if let idx = draft.clusters.firstIndex(where: { $0.id == cluster.id }) {
                            draft.clusters[idx].customTitle = newTitle.isEmpty ? nil : newTitle
                        }
                        showRename = nil
                    },
                    onCancel: { showRename = nil }
                )
            }
            .navigationDestination(isPresented: $navigateToPreview) {
                RecapPreviewView(draft: draft, imageLoader: imageLoader)
            }
            .alert("Photo Access", isPresented: $permissionDenied) {
                Button("Open Settings", role: .none) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Capper needs photo library access to build your recap. Enable it in Settings.")
            }
        }
    }

    private var organizingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Organizing photos…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Select photos to build your recap")
                .font(.title2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Tap Pick Photos to choose images from your library. We'll group them by place and time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 500,
                matching: .images
            ) {
                Label("Pick Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
            }
            .onChange(of: selectedItems) { _, new in
                guard !new.isEmpty else { return }
                startClustering(items: new)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clusterListView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(draft.clusters) { cluster in
                    ClusterRowView(cluster: cluster, imageLoader: imageLoader)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showRename = cluster
                        }
                }
            }

            Button {
                navigateToPreview = true
            } label: {
                Text("Create Recap")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func startClustering(items: [PhotosPickerItem]) {
        isOrganizing = true
        Task {
            let identifiers = items.compactMap(\.itemIdentifier)
            guard !identifiers.isEmpty else {
                await MainActor.run { isOrganizing = false }
                return
            }
            let assets = photoService.fetchAssets(identifiers: identifiers)
            guard !assets.isEmpty else {
                await MainActor.run {
                    isOrganizing = false
                    permissionDenied = true
                }
                return
            }
            var clusters = clusteringService.cluster(assets: assets)
            for i in clusters.indices {
                if let loc = clusters[i].representativeLocation {
                    let place = await geocodingService.place(for: loc)
                    clusters[i].resolvedTitle = place.title
                    clusters[i].subtitle = place.subtitle
                } else {
                    clusters[i].resolvedTitle = "Unknown Place"
                }
            }
            await MainActor.run {
                draft = RecapDraft(clusters: clusters, createdDate: Date())
                selectedItems = []
                isOrganizing = false
            }
        }
    }
}

#Preview {
    RecapBuilderView()
}
