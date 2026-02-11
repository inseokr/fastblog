//
//  PhotoSelectView.swift
//  Capper
//

import SwiftUI

/// When the selected day changes due to thumbnail-strip past-edge scroll, we scroll to first or last thumbnail of the new day.
enum DayChangeScrollEdge {
    case first
    case last
}

struct PhotoSelectView: View {
    let day: TripDay
    @ObservedObject var viewModel: TripCreationViewModel
    /// When true, used inside TripDayPickerView; Create/Update is in the nav bar.
    var embedded: Bool = false
    var onCreateBlog: (() -> Void)? = nil
    /// When true, show "Update" instead of "Create Blog" and call onUpdate when tapped.
    var isEditMode: Bool = false
    var onUpdate: (() -> Void)? = nil
    /// Called when user scrolls past last thumbnail (drag left); parent should switch to next day. Nil when not in day-picker context.
    var onRequestNextDay: (() -> Void)? = nil
    /// Called when user scrolls past first thumbnail (drag right); parent should switch to previous day.
    var onRequestPreviousDay: (() -> Void)? = nil
    /// When parent advances day, sets this to .first or .last; we scroll to that edge and clear. Nil when not used.
    @Binding var scrollToEdgeAfterDayChange: DayChangeScrollEdge?
    /// When embedded (e.g. in TripDayPickerView), optional content placed below the thumbnail strip (e.g. Create button).
    var embeddedBottomContent: (() -> AnyView)? = nil
    /// Stable ID of the photo shown in the main viewer. Single source of truth for "currently viewing".
    @State private var currentPhotoId: UUID?
    @Environment(\.dismiss) private var dismiss
    /// Cooldown after a day change to avoid rapid-fire advances.
    private static let dayChangeCooldown: TimeInterval = 0.6
    @State private var lastDayChangeTime: Date = .distantPast
    /// Minimum drag distance past edge to count as intentional day-change (avoids tap).
    private static let pastEdgeThreshold: CGFloat = 50

    private var dayIndex: Int? {
        viewModel.trip.days.firstIndex(where: { $0.id == day.id })
    }

    private var currentDayFromViewModel: TripDay? {
        guard let di = dayIndex else { return nil }
        return viewModel.trip.days[di]
    }

    /// Photos for this day, sorted oldest → newest (existing order).
    private var photos: [MockPhoto] {
        currentDayFromViewModel?.photos ?? day.photos
    }

    /// Currently viewing photo (by stable ID). Falls back to first photo if id missing.
    private var currentPhoto: MockPhoto? {
        if let id = currentPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    /// Selected photo IDs for this day (from viewModel). Single source of truth for selection.
    private var selectedPhotoIds: Set<UUID> {
        Set(photos.filter(\.isSelected).map(\.id))
    }

    /// Dim thumbnail unless it is the current photo or a selected photo.
    private func shouldDimThumbnail(photoId: UUID) -> Bool {
        if photoId == currentPhotoId { return false }
        if selectedPhotoIds.contains(photoId) { return false }
        return true
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Full-screen photo: fills remaining space (shrinks when embedded bottom content is present)
                mainPhotoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom: count label, horizontal strip, then optional Create button when embedded
                VStack(spacing: 12) {
                    selectedCountLabel
                    thumbnailStrip
                }
                .padding(.vertical, 12)
                .background(Color.black)

                if embedded, let content = embeddedBottomContent {
                    content()
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
            .background(Color.black)
        }
        .navigationTitle(embedded ? "" : "Select Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "Update" : "Create") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .preferredColorScheme(.dark)
        .onAppear {
            if currentPhotoId == nil {
                currentPhotoId = photos.first?.id
            }
        }
        .onChange(of: day.id) { _, _ in
            if let edge = scrollToEdgeAfterDayChange {
                if edge == .first {
                    currentPhotoId = photos.first?.id
                } else {
                    currentPhotoId = photos.last?.id
                }
                lastDayChangeTime = Date()
                scrollToEdgeAfterDayChange = nil
            } else {
                currentPhotoId = photos.first?.id
            }
        }
    }

    private var mainPhotoArea: some View {
        ZStack {
            if let photo = currentPhoto {
                ZStack {
                    mainPhotoImage(photo: photo)
                    if photo.isSelected {
                        selectionCheckOverlay
                    }
                }
                .id(photo.id)
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection() }
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let idx = photos.firstIndex(where: { $0.id == currentPhotoId }) ?? 0
                            let dx = value.translation.width
                            if dx < -40, idx + 1 < photos.count {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentPhotoId = photos[idx + 1].id
                                }
                            } else if dx > 40, idx > 0 {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentPhotoId = photos[idx - 1].id
                                }
                            }
                        }
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: currentPhotoId)
    }

    private func mainPhotoImage(photo: MockPhoto) -> some View {
        MockPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionCheckOverlay: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 6)
            .transition(.scale.combined(with: .opacity))
    }

    private func toggleSelection() {
        guard let di = dayIndex else { return }
        let photoIdx = photos.firstIndex(where: { $0.id == currentPhoto?.id }) ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.selectCurrentPhoto(dayIndex: di, photoIndex: photoIdx)
        }
    }

    private var selectedCountLabel: some View {
        Text(viewModel.selectedCountLabel)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
    }

    /// Bottom horizontal strip: tap a thumbnail to show it full-screen. Scrolls to keep current photo in view. Supports past-edge drag to advance to next/previous day.
    private var thumbnailStrip: some View {
        let currentPhotoIndex = photos.firstIndex(where: { $0.id == currentPhotoId }) ?? 0
        let atFirst = currentPhotoIndex == 0
        let atLast = currentPhotoIndex == photos.count - 1

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        ThumbnailCell(
                            photo: photo,
                            isCurrent: photo.id == currentPhotoId,
                            shouldDim: shouldDimThumbnail(photoId: photo.id)
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                currentPhotoId = photo.id
                            }
                        }
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 72)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let dx = value.translation.width
                        let pastEdgeLeft = atLast && dx < -Self.pastEdgeThreshold
                        let pastEdgeRight = atFirst && dx > Self.pastEdgeThreshold
                        let inCooldown = Date().timeIntervalSince(lastDayChangeTime) < Self.dayChangeCooldown

                        let direction: String = dx < 0 ? "left" : "right"
                        let edgeReached: String = atLast ? "last" : (atFirst ? "first" : "none")
                        var didAdvanceDay = false

                        if pastEdgeLeft && !inCooldown {
                            onRequestNextDay?()
                            didAdvanceDay = true
                        } else if pastEdgeRight && !inCooldown {
                            onRequestPreviousDay?()
                            didAdvanceDay = true
                        }

                        #if DEBUG
                        print("[PhotoSelect] currentDayIndex=\(dayIndex ?? -1) currentPhotoIndex=\(currentPhotoIndex) direction=\(direction) edgeReached=\(edgeReached) didAdvanceDay=\(didAdvanceDay)")
                        #endif
                    }
            )
            .onAppear {
                if let id = currentPhotoId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: currentPhotoId) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailCell: View {
    let photo: MockPhoto
    let isCurrent: Bool
    /// When true, apply black 20% overlay so thumbnail is dimmed (not current and not selected).
    let shouldDim: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                MockPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                    .frame(width: 56, height: 56)
                if photo.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(4)
                }
                if shouldDim {
                    Color.black.opacity(0.2)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let day = TripDay(dayIndex: 1, dateText: "Jan 1", photos: [
        MockPhoto(imageName: "photo", timestamp: Date()),
        MockPhoto(imageName: "camera", timestamp: Date()),
        MockPhoto(imageName: "mountain.2", timestamp: Date())
    ])
    let trip = TripDraft(
        title: "Test",
        dateRangeText: "Jan 1",
        days: [day],
        coverImageName: "photo",
        isScannedFromDefaultRange: true
    )
    return NavigationStack {
        PhotoSelectView(
            day: day,
            viewModel: TripCreationViewModel(trip: trip),
            scrollToEdgeAfterDayChange: .constant(nil)
        )
    }
}
