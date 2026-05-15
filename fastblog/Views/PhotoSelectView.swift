//
//  PhotoSelectView.swift
//  Capper
//

import SwiftUI
import UIKit

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
    @State private var thumbnailFrames: [UUID: CGRect] = [:]
    @State private var dragSelectionStartIndex: Int?
    @State private var dragSelectionTargetIsSelected: Bool?
    @State private var dragInitialSelectionById: [UUID: Bool] = [:]
    @State private var didPerformRangeSelection: Bool = false

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

#if DEBUG
    private func debugDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter.string(from: date)
    }

    private func debugLogVisiblePhotoOrder(context: String) {
        guard !photos.isEmpty else {
            print("[PhotoSelectOrder] \(context) photos=0")
            return
        }
        print("[PhotoSelectOrder] \(context) photos=\(photos.count)")
        for (idx, photo) in photos.enumerated() {
            let suffix = photo.localIdentifier.map { String($0.suffix(8)) } ?? "nil"
            print(
                "[PhotoSelectOrder] #\(idx + 1) id=\(photo.id.uuidString.prefix(8)) " +
                "assetSuffix=\(suffix) timestamp=\(debugDateString(photo.timestamp))"
            )
        }
    }
#endif

    var body: some View {
        VStack(spacing: 0) {
            // Full-screen photo: fills remaining space (shrinks when embedded bottom content is present)
            // ignoresSafeArea(.container, .top) lets the photo draw behind the nav bar without expanding
            // the VStack's layout frame — keeping sibling overlays (day tabs) properly below the nav bar.
            mainPhotoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)

            // Bottom: count label, horizontal strip, then optional Create button when embedded
            VStack(spacing: 24) {
                selectedCountLabel
                thumbnailStrip
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color.black)

            if embedded, let content = embeddedBottomContent {
                content()
                    .padding(.top, 4)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .background(PopGestureDisabler())
        .navigationTitle(embedded ? "Photo Selection" : "Select Photos")
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
#if DEBUG
            debugLogVisiblePhotoOrder(context: "onAppear dayIndex=\(day.dayIndex) dateText=\(day.dateText)")
#endif
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
#if DEBUG
            debugLogVisiblePhotoOrder(context: "onChangeDay dayIndex=\(day.dayIndex) dateText=\(day.dateText)")
#endif
        }
    }

    private var mainPhotoArea: some View {
        ZStack {
            if let photo = currentPhoto {
                mainPhotoImage(photo: photo)
                    .opacity(photo.isSelected ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 0.2), value: photo.isSelected)
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
            .clipped()
    }

    private func toggleSelection() {
        guard let di = dayIndex else { return }
        let photoIdx = photos.firstIndex(where: { $0.id == currentPhoto?.id }) ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.selectCurrentPhoto(dayIndex: di, photoIndex: photoIdx)
        }
    }

    private func photoIndex(at location: CGPoint) -> Int? {
        for (idx, photo) in photos.enumerated() {
            if let frame = thumbnailFrames[photo.id], frame.contains(location) {
                return idx
            }
        }
        return nil
    }

    private func beginRangeSelection(at index: Int) {
        guard photos.indices.contains(index) else { return }
        dragSelectionStartIndex = index
        dragInitialSelectionById = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.isSelected) })
        dragSelectionTargetIsSelected = !photos[index].isSelected
        didPerformRangeSelection = true
        applyRangeSelection(currentIndex: index)
    }

    private func applyRangeSelection(currentIndex: Int) {
        guard let start = dragSelectionStartIndex,
              let targetIsSelected = dragSelectionTargetIsSelected,
              let di = dayIndex,
              photos.indices.contains(currentIndex) else { return }
        let lower = min(start, currentIndex)
        let upper = max(start, currentIndex)
        for idx in photos.indices {
            let id = photos[idx].id
            let initial = dragInitialSelectionById[id] ?? photos[idx].isSelected
            let shouldSelect = (lower...upper).contains(idx) ? targetIsSelected : initial
            viewModel.setPhotoSelection(dayIndex: di, photoIndex: idx, isSelected: shouldSelect)
        }
    }

    private func endRangeSelection() {
        dragSelectionStartIndex = nil
        dragSelectionTargetIsSelected = nil
        dragInitialSelectionById = [:]
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
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ThumbnailFramePreferenceKey.self,
                                    value: [photo.id: geo.frame(in: .named("thumbnailStripArea"))]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .coordinateSpace(name: "thumbnailStripArea")
            .frame(height: 72)
            .onPreferenceChange(ThumbnailFramePreferenceKey.self) { frames in
                thumbnailFrames = frames
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard !didPerformRangeSelection else {
                            didPerformRangeSelection = false
                            return
                        }
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("thumbnailStripArea"))
                    .onChanged { value in
                        if dragSelectionStartIndex == nil {
                            let dragDistance = hypot(value.translation.width, value.translation.height)
                            guard dragDistance > 8 else { return }
                            guard let startIdx = photoIndex(at: value.startLocation) else { return }
                            beginRangeSelection(at: startIdx)
                        }
                        guard let currentIdx = photoIndex(at: value.location) else { return }
                        applyRangeSelection(currentIndex: currentIdx)
                    }
                    .onEnded { _ in
                        endRangeSelection()
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

private struct ThumbnailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
                    .clipped()
                if photo.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(4)
                }
                if shouldDim {
                    Color.black.opacity(0.2)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 8)
                    .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

// Disables the NavigationStack's edge-swipe-back gesture while the photo viewer
// is visible, preventing it from competing with the left/right photo-navigation swipe.
private struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> VC { .init() }
    func updateUIViewController(_: VC, context: Context) {}

    final class VC: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
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
