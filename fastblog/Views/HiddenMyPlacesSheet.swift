//
//  HiddenMyPlacesSheet.swift
//  fastblog
//
//  Lists places hidden from My Places with one-tap restore.
//

import SwiftUI

struct HiddenMyPlacesSheet: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @ObservedObject private var hiddenStore = HiddenMyPlacesStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlace: VisitedPlaceSummary?

    private var hiddenPlaces: [VisitedPlaceSummary] {
        createdRecapStore.visitedPlaces
            .filter { hiddenStore.isHidden($0.placeId) }
            .sorted(by: { $0.latestVisitDate > $1.latestVisitDate })
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if hiddenPlaces.isEmpty {
                        emptyState
                    } else {
                        hiddenList
                    }
                }
                .navigationTitle("Hidden Places")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .preferredColorScheme(.dark)
            }

            if let place = selectedPlace {
                PlaceVisitedPhotoModalWrapper(
                    place: place,
                    presentCategoryPickerInitially: false,
                    onDismiss: { selectedPlace = nil }
                )
                .environmentObject(createdRecapStore)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: selectedPlace?.id)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No hidden places")
                .font(.headline)
            Text("Places you hide from My Places appear here so you can bring them back anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hiddenList: some View {
        ScrollView {
            LazyVGrid(columns: PlacesVisitedPlaceGrid.columns, spacing: 12) {
                ForEach(hiddenPlaces) { place in
                    PlaceVisitedCard(
                        place: place,
                        onTap: { selectedPlace = place }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            restore(place)
                        } label: {
                            Text("Restore")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func restore(_ place: VisitedPlaceSummary) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        hiddenStore.unhide(placeId: place.placeId)
        if selectedPlace?.placeId == place.placeId {
            selectedPlace = nil
        }
    }
}
