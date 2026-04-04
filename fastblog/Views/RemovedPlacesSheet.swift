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

    /// The entry currently shown in the fullscreen place viewer.
    @State private var selectedEntry: RemovedPlaceEntry?

    var body: some View {
        ZStack {
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
            }

            // Full-screen place viewer — same overlay pattern as Places Visited.
            if let entry = selectedEntry {
                let stop = entry.stop
                let photos = stop.photos.filter(\.isIncluded).isEmpty ? stop.photos : stop.photos.filter(\.isIncluded)
                if let initialPhotoId = photos.first?.id {
                    PlacePhotoModalView(
                        placeTitle: Binding(
                            get: { stop.cleanedPlaceTitle },
                            set: { newTitle in
                                if let idx = draft.removedPlaceStops.firstIndex(where: { $0.stop.id == stop.id }) {
                                    draft.removedPlaceStops[idx].stop.placeTitle = newTitle
                                }
                            }
                        ),
                        placeSubtitle: stop.placeSubtitle,
                        photos: photos,
                        initialPhotoId: initialPhotoId,
                        stopDigitizedTime: stop.visitedTimeDigitized,
                        blogIsEditMode: false,
                        showAssetTimeMetadata: false,
                        presentation: .fullscreen(source: .placesVisited),
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
                        onDismiss: { selectedEntry = nil }
                    )
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .zIndex(200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }
        }
        .animation(.easeInOut(duration: 0.38), value: selectedEntry?.id)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entriesByDay) { group in
                    Text(group.header)
                        .textCase(nil)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    let pairs = stride(from: 0, to: group.entries.count, by: 2).map {
                        Array(group.entries[$0 ..< min($0 + 2, group.entries.count)])
                    }
                    ForEach(pairs, id: \.first?.id) { pair in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(pair.enumerated()), id: \.element.id) { _, entry in
                                removedCard(entry: entry)
                                    .frame(maxWidth: .infinity)
                            }
                            if pair.count == 1 {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func removedCard(entry: RemovedPlaceEntry) -> some View {
        let includedPhotos = entry.stop.photos.filter(\.isIncluded)
        let heroPhoto = includedPhotos.first ?? entry.stop.photos.first
        let previewThumbs = Array(includedPhotos.dropFirst().prefix(3))
        let visitDate = heroPhoto?.timestamp ?? entry.stop.photos.first?.timestamp

        let thumbSpacing: CGFloat = 8
        let stripPadding: CGFloat = 10
        let preferredThumbSize: CGFloat = 44

        return VStack(alignment: .leading, spacing: 10) {
            // Hero photo area
            GeometryReader { geo in
                let availableWidth = geo.size.width
                let thumbCount = previewThumbs.count
                let thumbSize: CGFloat = {
                    guard thumbCount > 0 else { return preferredThumbSize }
                    let gutters = stripPadding * 2 + CGFloat(thumbCount - 1) * thumbSpacing
                    let raw = (availableWidth - gutters) / CGFloat(thumbCount)
                    return min(preferredThumbSize, max(1, raw))
                }()
                let backingWidth = CGFloat(thumbCount) * thumbSize
                    + CGFloat(thumbCount - 1) * thumbSpacing
                    + stripPadding * 2

                ZStack(alignment: .bottom) {
                    // Hero image or placeholder
                    if let hero = heroPhoto {
                        RecapPhotoThumbnail(
                            photo: hero,
                            cornerRadius: 14,
                            showIcon: false,
                            targetSize: CGSize(width: 900, height: 600)
                        )
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.18))
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    // Date badge — top left
                    if let date = visitDate {
                        VStack {
                            HStack {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.55))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(10)
                    }

                    // Extra photo strip — bottom overlay
                    if !previewThumbs.isEmpty {
                        HStack(spacing: thumbSpacing) {
                            ForEach(Array(previewThumbs)) { photo in
                                RecapPhotoThumbnail(
                                    photo: photo,
                                    cornerRadius: 10,
                                    showIcon: false,
                                    targetSize: CGSize(width: 200, height: 200)
                                )
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(stripPadding)
                        .frame(width: min(backingWidth, availableWidth))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { openPlaceModal(for: entry) }
            }
            .frame(height: 150)

            // Text + restore button
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.stop.cleanedPlaceTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = entry.stop.placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button {
                    restore(entry: entry)
                } label: {
                    Text("Restore")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { openPlaceModal(for: entry) }
        }
        .padding(12)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func openPlaceModal(for entry: RemovedPlaceEntry) {
        guard entry.stop.photos.first(where: { $0.isIncluded }) != nil || !entry.stop.photos.isEmpty else { return }
        selectedEntry = entry
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
