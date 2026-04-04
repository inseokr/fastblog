//
//  RemovedPlacesSheet.swift
//  fastblog
//

import SwiftUI

/// Sheet that lists all place stops the user has removed from a blog,
/// with a one-tap "Restore" button that brings each place back
/// — including its note caption and any per-photo captions.
struct RemovedPlacesSheet: View {
    /// Live binding to the blog draft so changes persist immediately.
    @Binding var draft: RecapBlogDetail
    /// Live binding to the selected day index in the parent view.
    @Binding var selectedDayIndex: Int
    /// Called after a restore so the parent can persist the draft.
    var onRestore: () -> Void

    @Environment(\.dismiss) private var dismiss
    
    /// The currently selected item to show in the place pull-up modal.
    @State private var placeModalItem: PlacePhotoModalItem?

    var body: some View {
        NavigationStack {
            Group {
                if draft.removedPlaceStops.isEmpty {
                    emptyState
                } else {
                    removedList
                }
            }
            .navigationTitle("Restore Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
            .sheet(item: $placeModalItem) { item in
                placePhotoModalSheet(item: item)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Removed Places")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Places you remove from your blog will appear here so you can bring them back anytime.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Grouped List

    private struct DayGroup: Identifiable {
        let id: UUID          // dayId
        let dayIndex: Int
        let header: String
        let entries: [RemovedPlaceEntry]
    }

    /// Removed entries grouped by original day, sorted chronologically.
    private var entriesByDay: [DayGroup] {
        var seen = Set<UUID>()
        var ordered: [DayGroup] = []
        for entry in draft.removedPlaceStops {
            guard !seen.contains(entry.dayId) else { continue }
            seen.insert(entry.dayId)
            let header: String
            if let day = draft.days.first(where: { $0.id == entry.dayId }) {
                header = "Day \(day.dayIndex) · \(day.shortDateText)"
            } else {
                header = "Day \(entry.dayIndex)"
            }
            let groupEntries = draft.removedPlaceStops.filter { $0.dayId == entry.dayId }
            ordered.append(DayGroup(id: entry.dayId, dayIndex: entry.dayIndex, header: header, entries: groupEntries))
        }
        return ordered.sorted { $0.dayIndex < $1.dayIndex }
    }

    private var removedList: some View {
        List {
            ForEach(entriesByDay) { group in
                Section {
                    ForEach(group.entries) { entry in
                        removedRow(entry: entry)
                    }
                } header: {
                    Text(group.header)
                        .textCase(nil)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func removedRow(entry: RemovedPlaceEntry) -> some View {
        HStack(spacing: 12) {
            // Cover photo thumbnail (or placeholder)
            Group {
                if let coverPhoto = entry.stop.photos.first(where: { $0.isIncluded }) ?? entry.stop.photos.first {
                    RecapPhotoThumbnail(
                        photo: coverPhoto,
                        cornerRadius: 10,
                        showIcon: false,
                        targetSize: CGSize(width: 128, height: 128)
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
                    .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.22))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openPlaceModal(for: entry)
            }

            // Place info
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.stop.placeTitle)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let subtitle = entry.stop.placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if hasCaptions(entry: entry) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.caption2)
                        Text("Captions preserved")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue.opacity(0.8))
                    .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openPlaceModal(for: entry)
            }

            Spacer()

            // Restore button
            Button {
                restore(entry: entry)
            } label: {
                Text("Restore")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func openPlaceModal(for entry: RemovedPlaceEntry) {
        let photos = entry.stop.photos.filter(\.isIncluded)
        let initialPhotoId = photos.first?.id ?? entry.stop.photos.first?.id
        
        if let initialPhotoId = initialPhotoId {
            placeModalItem = PlacePhotoModalItem(
                dayId: entry.dayId,
                stopId: entry.stop.id,
                initialPhotoId: initialPhotoId
            )
        }
    }

    @ViewBuilder
    private func placePhotoModalSheet(item: PlacePhotoModalItem) -> some View {
        if let entry = draft.removedPlaceStops.first(where: { $0.stop.id == item.stopId && $0.dayId == item.dayId }) {
            let stop = entry.stop
            let includedPhotos = stop.photos.filter(\.isIncluded)
            if !includedPhotos.isEmpty {
                PlacePhotoModalView(
                    placeTitle: Binding(
                        get: { stop.placeTitle },
                        set: { newTitle in
                            if let idx = draft.removedPlaceStops.firstIndex(where: { $0.stop.id == stop.id }) {
                                draft.removedPlaceStops[idx].stop.placeTitle = newTitle
                            }
                        }
                    ),
                    placeSubtitle: stop.placeSubtitle,
                    photos: includedPhotos,
                    initialPhotoId: includedPhotos.contains(where: { $0.id == item.initialPhotoId }) ? item.initialPhotoId : includedPhotos[0].id,
                    stopDigitizedTime: stop.visitedTimeDigitized,
                    blogIsEditMode: true,
                    presentation: .sheet,
                    photoCaption: { photoId in
                        Binding(
                            get: { stop.photos.first(where: { $0.id == photoId })?.caption ?? "" },
                            set: { newCaption in
                                if let idx = draft.removedPlaceStops.firstIndex(where: { $0.stop.id == stop.id }),
                                   let photoIdx = draft.removedPlaceStops[idx].stop.photos.firstIndex(where: { $0.id == photoId }) {
                                    draft.removedPlaceStops[idx].stop.photos[photoIdx].caption = newCaption
                                }
                            }
                        )
                    },
                    onDismiss: { placeModalItem = nil }
                )
                .presentationDetents([.large])
                .presentationBackground(.clear)
            } else {
                Color.white.onAppear { placeModalItem = nil }
            }
        } else {
            Color.white.onAppear { placeModalItem = nil }
        }
    }

    private func hasCaptions(entry: RemovedPlaceEntry) -> Bool {
        let hasNote = !(entry.stop.noteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhotoCaption = entry.stop.photos.contains { !($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasNote || hasPhotoCaption
    }

    /// Inserts a place stop into the day's placeStops array at the correct
    /// position based on its original orderIndex.
    private func insertByOrderIndex(_ stop: PlaceStop, into placeStops: inout [PlaceStop]) {
        if let insertIndex = placeStops.firstIndex(where: { $0.orderIndex > stop.orderIndex }) {
            placeStops.insert(stop, at: insertIndex)
        } else {
            placeStops.append(stop)
        }
    }

    private func restore(entry: RemovedPlaceEntry) {
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        // Preserve the current cover photo so restoration doesn't change it
        let currentCover = draft.selectedCoverPhotoIdentifier

        // Remove from the removed list
        draft.removedPlaceStops.removeAll { $0.stop.id == entry.stop.id }

        // Find the original day and insert at its original order position
        if let dayIdx = draft.days.firstIndex(where: { $0.id == entry.dayId }) {
            insertByOrderIndex(entry.stop, into: &draft.days[dayIdx].placeStops)
            selectedDayIndex = dayIdx
        } else if let dayIdx = draft.days.firstIndex(where: { $0.dayIndex == entry.dayIndex }) {
            insertByOrderIndex(entry.stop, into: &draft.days[dayIdx].placeStops)
            selectedDayIndex = dayIdx
        } else {
            // Day was completely removed, we must recreate it.
            let fallbackDate = entry.stop.photos.first?.timestamp ?? Date()
            let resurrectedDay = RecapBlogDay(
                id: entry.dayId,
                dayIndex: entry.dayIndex,
                date: entry.dayDate ?? fallbackDate,
                placeStops: [entry.stop]
            )
            
            // Insert the recreated day at the correct sequential dayIndex
            if let insertIdx = draft.days.firstIndex(where: { $0.dayIndex > entry.dayIndex }) {
                draft.days.insert(resurrectedDay, at: insertIdx)
                selectedDayIndex = insertIdx
            } else {
                draft.days.append(resurrectedDay)
                selectedDayIndex = draft.days.count - 1
            }
        }

        // If the blog was empty (no cover photo) before this restore, auto-assign the best photo
        // from the newly restored place as the cover photo.
        if currentCover == nil && draft.selectedCoverPhotoIdentifier == nil {
            let includedPhotos = entry.stop.photos.filter(\.isIncluded)
            // Pick highest quality score, falling back to the first included photo
            let bestPhoto = includedPhotos.max(by: { ($0.qualityScore?.totalScore ?? 0) < ($1.qualityScore?.totalScore ?? 0) })
                ?? includedPhotos.first
            if let identifier = bestPhoto?.localIdentifier {
                draft.selectedCoverPhotoIdentifier = identifier
            }
        } else {
            // Restore cover photo to what it was before
            draft.selectedCoverPhotoIdentifier = currentCover
        }

        onRestore()
    }
}

#Preview {
    let stop1 = PlaceStop(
        orderIndex: 0,
        placeTitle: "Golden Gate Bridge",
        placeSubtitle: "San Francisco, CA",
        photos: [
            RecapPhoto(timestamp: Date(), imageName: "photo", caption: "Foggy morning view 🌁")
        ],
        noteText: "Walked across at sunrise — absolutely worth it."
    )
    let stop2 = PlaceStop(
        orderIndex: 1,
        placeTitle: "Fisherman's Wharf",
        placeSubtitle: "San Francisco, CA",
        photos: []
    )
    let day = RecapBlogDay(dayIndex: 1, date: Date(), placeStops: [])
    let detail = RecapBlogDetail(
        title: "SF Trip",
        days: [day],
        removedPlaceStops: [
            RemovedPlaceEntry(dayId: day.id, dayIndex: 1, stop: stop1),
            RemovedPlaceEntry(dayId: day.id, dayIndex: 1, stop: stop2)
        ]
    )
    return RemovedPlacesSheet(draft: .constant(detail), selectedDayIndex: .constant(0), onRestore: {})
}
