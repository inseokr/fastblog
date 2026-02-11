//
//  RecapBlogPageView.swift
//  Capper
//

import SwiftUI
import MapKit

struct RecapBlogPageView: View {
    let blogId: UUID
    let initialTrip: TripDraft?

    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecapBlogDetail
    @State private var selectedDayIndex: Int = 0  // 0 = Day 1, 1 = Day 2, ...
    @State private var overflowStop: OverflowItem?
    @State private var showEditNameForStop: PlaceStop?
    @State private var showManagePhotosForStop: ManagePhotosItem?
    @State private var isEditMode = true
    @State private var savedToast = false
    @State private var showBlogSettings = false
    @State private var showShareSheet = false
    @State private var showEditPhotoFlow = false
    @State private var fullScreenMapDay: RecapBlogDay?
    @State private var showTitleChange = false
    @State private var placePhotoModalItem: PlacePhotoModalItem?
    @State private var showUnsavedAlert = false
    @State private var hasShownUnsavedAlert = false
    @State private var showCoverPhotoPicker = false

    init(blogId: UUID, initialTrip: TripDraft?) {
        self.blogId = blogId
        self.initialTrip = initialTrip
        _draft = State(initialValue: RecapBlogDetail(id: blogId, title: "", days: [], coverTheme: "default"))
    }

    var body: some View {
        Group {
            if draft.days.isEmpty && initialTrip != nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
            }
        }
        .navigationBarBackButtonHidden(isEditMode && !hasShownUnsavedAlert)
        .navigationTitle("Recap Blog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isEditMode && !hasShownUnsavedAlert {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showUnsavedAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isEditMode {
                    Button {
                        showCoverPhotoPicker = true
                    } label: {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 16) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        Button {
                            showBlogSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .sheet(isPresented: $showBlogSettings) {
            BlogSettingsSheet(draft: $draft, onSave: { saveDraft() }, onEditMode: {
                showBlogSettings = false
                isEditMode = true
            })
        }
        .sheet(isPresented: $showTitleChange) {
            BlogTitleChangeSheet(title: $draft.title) {
                showTitleChange = false
            }
        }
        .alert("Blog Not Saved", isPresented: $showUnsavedAlert) {
            Button("Got it") {
                hasShownUnsavedAlert = true
                dismiss()
            }
        } message: {
            Text("You haven't saved your blog yet. Save it to unlock your map routes and keep your edits.")
        }
        .sheet(isPresented: $showCoverPhotoPicker) {
            BlogCoverPhotoPickerView(
                photos: allIncludedPhotos,
                selectedIdentifier: $draft.selectedCoverPhotoIdentifier,
                onSave: {
                    showCoverPhotoPicker = false
                    saveDraft()
                    isEditMode = false
                }
            )
        }
        .onAppear {
            loadDraftIfNeeded()
        }
        .sheet(item: $overflowStop) { item in
            PlaceStopActionSheet(
                placeTitle: item.stop.placeTitle,
                onEditName: { showEditNameForStop = item.stop },
                onManagePhotos: { showManagePhotosForStop = ManagePhotosItem(dayId: item.dayId, stopId: item.stop.id) },
                onRemoveFromBlog: { removePlaceStop(dayId: item.dayId, stopId: item.stop.id) }
            )
        }
        .sheet(item: $showEditNameForStop) { stop in
            EditPlaceStopNameSheet(placeTitle: bindingForPlaceTitle(stopId: stop.id), onSave: { newTitle in
                updatePlaceTitle(stopId: stop.id, to: newTitle)
            })
        }
        .sheet(item: $showManagePhotosForStop) { pair in
            ManagePhotosView(
                placeTitle: placeStop(dayId: pair.dayId, stopId: pair.stopId)?.placeTitle ?? "Photos",
                photos: bindingForPhotos(dayId: pair.dayId, stopId: pair.stopId)
            )
        }
        .fullScreenCover(isPresented: $showEditPhotoFlow) {
            EditBlogPhotoFlowView(blogId: blogId, onDismiss: { showEditPhotoFlow = false })
                .environmentObject(createdRecapStore)
        }
        .fullScreenCover(item: $fullScreenMapDay) { day in
            FullScreenMapView(day: day) {
                fullScreenMapDay = nil
            }
        }
        .sheet(item: $placePhotoModalItem) { item in
            Group {
                if let stop = placeStop(dayId: item.dayId, stopId: item.stopId), !stop.photos.isEmpty {
                    PlacePhotoModalView(
                        placeTitle: stop.placeTitle,
                        placeSubtitle: stop.placeSubtitle,
                        photos: stop.photos,
                        initialPhotoId: stop.photos.contains(where: { $0.id == item.initialPhotoId }) ? item.initialPhotoId : stop.photos[0].id,
                        photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
                        onDismiss: { placePhotoModalItem = nil }
                    )
                } else {
                    Color.white
                        .onAppear { placePhotoModalItem = nil }
                }
            }
            .presentationDetents([.fraction(0.45), .fraction(0.65), .fraction(0.92)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
            .presentationBackground(Color.white)
        }
        .overlay {
            if savedToast {
                Text("Saved")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: savedToast)
        .preferredColorScheme(.dark)
    }

    @State private var scrollToStopId: UUID?

    private static let dayFilterApproxHeight: CGFloat = 52

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: Self.dayFilterApproxHeight)
                        blogTitleView
                        if !isEditMode {
                            mapOrPreviewCard
                        }
                        timelineContent
                    }
                    .background(Color.black)
                }
                .background(Color.black)
                .onChange(of: scrollToStopId) { _, newId in
                    guard let id = newId else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    scrollToStopId = nil
                }
                dayFilterSection
            }
        }
        .background(Color.black)
    }

    /// Blog title placed between day filter and map; scrolls with content. Tappable to rename.
    private var blogTitleView: some View {
        Button {
            showTitleChange = true
        } label: {
            HStack(spacing: 6) {
                Text(draft.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    /// Day filter fixed at top; scrollable content (map + timeline) sits below it.
    private var dayFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(draft.days.enumerated()), id: \.element.id) { index, day in
                    dayPill(title: "Day \(day.dayIndex)", index: index)
                        .id(day.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func dayPill(title: String, index: Int) -> some View {
        let isSelected = selectedDayIndex == index
        return Button {
            selectedDayIndex = index
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color(white: 0.2))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mapOrPreviewCard: some View {
        if let day = day(at: selectedDayIndex) {
            ZStack(alignment: .bottomTrailing) {
                MapDayView(placeStops: day.placeStops, onTap: { fullScreenMapDay = day })
                Button {
                    fullScreenMapDay = day
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let day = day(at: selectedDayIndex) {
                daySection(day: day)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func daySection(day: RecapBlogDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(day.shortDateText)
                    .font(.headline)
                    .foregroundColor(.white)
                Image(systemName: "sun.max")
                    .foregroundColor(.secondary)
                Image(systemName: "mappin")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                PlaceStopRowView(
                    day: day,
                    stop: stop,
                    stopNumber: index + 1,
                    isEditMode: isEditMode,
                    placeNote: bindingForPlaceNote(dayId: day.id, stopId: stop.id),
                    photoCaption: { bindingForPhotoCaption(dayId: day.id, stopId: stop.id, photoId: $0) },
                    onDelete: {
                        removePlaceStop(dayId: day.id, stopId: stop.id)
                    },
                    onKebab: {
                        overflowStop = OverflowItem(dayId: day.id, stop: stop)
                    },
                    onManagePhotos: {
                        showManagePhotosForStop = ManagePhotosItem(dayId: day.id, stopId: stop.id)
                    },
                    onRemovePhoto: { photoId in
                        removePhoto(dayId: day.id, stopId: stop.id, photoId: photoId)
                    },
                    onPhotoTapped: { photo in
                        placePhotoModalItem = PlacePhotoModalItem(dayId: day.id, stopId: stop.id, initialPhotoId: photo.id)
                    },
                    onCaptionFocus: { scrollToStopId = stop.id }
                )
                .id(stop.id)
            }
        }
    }

    private func loadDraftIfNeeded() {
        if let saved = createdRecapStore.getBlogDetail(blogId: blogId) {
            draft = saved
            return
        }
        guard let trip = initialTrip ?? createdRecapStore.tripDraft(for: blogId) else { return }
        Task { @MainActor in
            draft = await createdRecapStore.buildBlogDetailAsync(from: trip)
        }
    }

    /// All included photos across all days/stops, for cover photo selection.
    private var allIncludedPhotos: [RecapPhoto] {
        draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
    }

    private var shareText: String {
        let placeCount = draft.days.flatMap(\.placeStops).count
        if placeCount > 0 {
            return "\(draft.title) – My Recap Blog (\(placeCount) places)"
        }
        return "\(draft.title) – My Recap Blog"
    }

    private func saveDraft() {
        createdRecapStore.saveBlogDetail(draft)
        savedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedToast = false
        }
    }

    private func day(at index: Int) -> RecapBlogDay? {
        guard draft.days.indices.contains(index) else { return nil }
        return draft.days[index]
    }

    private func removePlaceStop(dayId: UUID, stopId: UUID) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayId }) else { return }
        var day = draft.days[dayIndex]
        day.placeStops.removeAll { $0.id == stopId }
        draft.days[dayIndex] = day
    }

    private func removePhoto(dayId: UUID, stopId: UUID, photoId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        var day = draft.days[dayIdx]
        var stop = day.placeStops[stopIdx]
        stop.photos.removeAll { $0.id == photoId }
        day.placeStops[stopIdx] = stop
        draft.days[dayIdx] = day
    }

    private func updatePlaceTitle(stopId: UUID, to title: String) {
        for i in draft.days.indices {
            if let j = draft.days[i].placeStops.firstIndex(where: { $0.id == stopId }) {
                var day = draft.days[i]
                var stop = day.placeStops[j]
                stop.placeTitle = title
                day.placeStops[j] = stop
                draft.days[i] = day
                break
            }
        }
        showEditNameForStop = nil
    }

    private func bindingForPlaceTitle(stopId: UUID) -> Binding<String> {
        Binding(
            get: {
                for day in draft.days {
                    if let stop = day.placeStops.first(where: { $0.id == stopId }) {
                        return stop.placeTitle
                    }
                }
                return ""
            },
            set: { _ in }
        )
    }

    private func bindingForPhotos(dayId: UUID, stopId: UUID) -> Binding<[RecapPhoto]> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }) else {
                    return []
                }
                return stop.photos
            },
            set: { newPhotos in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                var day = draft.days[dayIdx]
                var stop = day.placeStops[stopIdx]
                stop.photos = newPhotos
                day.placeStops[stopIdx] = stop
                draft.days[dayIdx] = day
            }
        )
    }

    private func placeStop(dayId: UUID, stopId: UUID) -> PlaceStop? {
        draft.days.first(where: { $0.id == dayId })?.placeStops.first(where: { $0.id == stopId })
    }

    /// Place note is stored per Place in PlaceStop.noteText; persisted when user taps Save.
    private func bindingForPlaceNote(dayId: UUID, stopId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }) else { return "" }
                return stop.noteText ?? ""
            },
            set: { newValue in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                var day = draft.days[dayIdx]
                var stop = day.placeStops[stopIdx]
                stop.noteText = newValue.isEmpty ? nil : newValue
                day.placeStops[stopIdx] = stop
                draft.days[dayIdx] = day
            }
        )
    }

    /// Photo caption is stored per photo (photoID-based); persisted when user taps Save.
    private func bindingForPhotoCaption(dayId: UUID, stopId: UUID, photoId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }),
                      let photo = stop.photos.first(where: { $0.id == photoId }) else { return "" }
                return photo.caption ?? ""
            },
            set: { newValue in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
                      let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
                var day = draft.days[dayIdx]
                var stop = day.placeStops[stopIdx]
                var photo = stop.photos[photoIdx]
                photo.caption = newValue.isEmpty ? nil : newValue
                stop.photos[photoIdx] = photo
                day.placeStops[stopIdx] = stop
                draft.days[dayIdx] = day
            }
        )
    }
}

private struct OverflowItem: Identifiable {
    let dayId: UUID
    let stop: PlaceStop
    var id: UUID { stop.id }
}

private struct ManagePhotosItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    var id: UUID { stopId }
}

/// Presents the photo selection flow (TripDayPickerView) in edit mode, then Title → Cover with "Update". Used when user taps Edit on the Recap Blog page.
private struct EditBlogPhotoFlowView: View {
    let blogId: UUID
    var onDismiss: () -> Void
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var trip: TripDraft?
    @State private var tripToUpdate: TripDraft?

    var body: some View {
        NavigationStack {
            Group {
                if let t = trip {
                    TripDayPickerView(
                        trip: t,
                        onStartCreateBlog: { _ in },
                        isEditMode: true,
                        onUpdate: { updated in
                            tripToUpdate = updated
                        }
                    )
                    .fullScreenCover(item: $tripToUpdate) { updatedTrip in
                    CreateBlogFlowView(
                        trip: updatedTrip,
                        existingBlogId: blogId,
                        onUpdateComplete: {
                            tripToUpdate = nil
                            onDismiss()
                        },
                        onClose: { _ in }
                    )
                    .environmentObject(createdRecapStore)
                    }
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .onAppear {
            trip = createdRecapStore.tripDraftApplyingBlogSelection(blogId: blogId)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        RecapBlogPageView(blogId: UUID(), initialTrip: nil)
            .environmentObject(CreatedRecapBlogStore.shared)
    }
}
