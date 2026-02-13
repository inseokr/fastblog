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
    @State private var showBlogSettings = false
    @State private var showShareSheet = false
    @State private var showEditPhotoFlow = false
    @State private var fullScreenMapDay: RecapBlogDay?
    @State private var showTitleChange = false
    @State private var placePhotoModalItem: PlacePhotoModalItem?
    @State private var showUnsavedChangesAlert = false
    @State private var showCoverPhotoPicker = false
    /// Snapshot of the draft when edit mode was entered; compared to detect changes.
    @State private var draftSnapshot: RecapBlogDetail?
    @AppStorage("blogify.showFirstTimeSaveTip") private var showFirstTimeSaveTip = true
    @State private var showSaveTipAlert = false
    @State private var showFirstSaveBanner = false

    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoOverlay = false
    @State private var isUndoMinimized = false
    @State private var isKeyboardVisible = false
    
    // Sticky Title State
    @State private var showStickyTitle = false

    private enum UndoAction {
        case deletePlace(dayId: UUID, stop: PlaceStop, index: Int)
        case deletePhoto(dayId: UUID, stopId: UUID, photo: RecapPhoto, index: Int)

        var text: String {
            switch self {
            case .deletePlace: return "Place deleted"
            case .deletePhoto: return "Photo removed"
            }
        }
    }

    init(blogId: UUID, initialTrip: TripDraft?) {
        self.blogId = blogId
        self.initialTrip = initialTrip
        _draft = State(initialValue: RecapBlogDetail(id: blogId, title: "", days: [], coverTheme: "default"))
    }

    var body: some View {
        GeometryReader { screenGeo in
            Group {
                if draft.days.isEmpty && initialTrip != nil {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mainContent(screenHeight: screenGeo.size.height)
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationTitle(showStickyTitle ? draft.title : (createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil ? "Draft" : "Recap Blog"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(showStickyTitle ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if isEditMode {
                            showUnsavedChangesAlert = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditMode {
                        Button {
                            saveDraft()
                            isEditMode = false
                        } label: {
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .clipShape(Capsule())
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
                BlogSettingsSheet(
                    draft: $draft,
                    onSave: { saveDraft() },
                    onEditMode: {
                        showBlogSettings = false
                        isEditMode = true
                    },
                    onDelete: {
                        createdRecapStore.deleteBlog(sourceTripId: blogId)
                        dismiss()
                    }
                )
            }
            .sheet(isPresented: $showTitleChange) {
                BlogTitleChangeSheet(title: $draft.title) {
                    showTitleChange = false
                }
            }
            .alert("Welcome to Your Blog!", isPresented: $showSaveTipAlert) {
                Button("Don't Show Again") {
                    showFirstTimeSaveTip = false
                }
                Button("Okay", role: .cancel) { }
            } message: {
                Text("Tap Save when you're done editing to keep your changes and unlock your map routes.")
            }
            .alert("Save before leaving?", isPresented: $showUnsavedChangesAlert) {
                if isAlreadySaved {
                    Button("Save") {
                        saveDraft()
                        // If we are leaving, we should dismiss?
                        // Or just exit edit mode?
                        // Usually "Save before leaving" implies leaving.
                        isEditMode = false
                        dismiss()
                    }
                    Button("Discard Changes", role: .destructive) {
                        isEditMode = false
                        dismiss()
                    }
                } else {
                    Button("Save As Draft") {
                        if draftSnapshot != nil && draft != draftSnapshot {
                            DraftReminderNotificationManager.scheduleDraftReminder(blogTitle: draft.title)
                        }
                        isEditMode = false
                        dismiss()
                    }
                    Button("Delete Blog", role: .destructive) {
                        createdRecapStore.deleteBlog(sourceTripId: blogId)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if isAlreadySaved {
                    Text("You have unsaved changes. Would you like to save them before leaving?")
                } else {
                    Text("Would you like to save your blog before leaving?")
                }
            }
            .sheet(isPresented: $showCoverPhotoPicker) {
                BlogCoverPhotoPickerView(
                    photos: allIncludedPhotos,
                    selectedIdentifier: $draft.selectedCoverPhotoIdentifier,
                    saveButtonTitle: "Done",
                    onSave: {
                        showCoverPhotoPicker = false
                    }
                )
            }
            .onAppear {
                loadDraftIfNeeded()
                // If the blog has been saved before, start in View Mode.
                if let existing = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }), existing.lastEditedAt != nil {
                    isEditMode = false
                } else if showFirstTimeSaveTip {
                    showSaveTipAlert = true
                }
                // Snapshot for change detection (after a brief delay so draft is loaded)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if draftSnapshot == nil {
                        draftSnapshot = draft
                    }
                }
            }
            .onChange(of: isEditMode) { _, editing in
                if editing {
                    // When entering edit mode, snapshot the *current* draft state.
                    // If we came from Settings (where we might have changed title/cover),
                    // we want to ensure we capture that as the "starting point" for THIS edit session?
                    // Actually, if we changed checks in Settings, we probably want those to count as changes.
                    // But standard flow:
                    // 1. View Mode -> Settings -> Change Title -> Done (updates draft, but not saved to store yet if we want "Cancel" to revert?)
                    // The BlogSettingsSheet updates the `draft` binding directly.
                    // So if we enter Edit Mode, we should probably snapshot what is currently in the store if we want "Revert to Last Saved".
                    
                    // However, for "Leave without saving", we simply compare current `draft` to `draftSnapshot`.
                    // If we want "Cancel" to revert to *Last Saved*, we should snapshot the *Last Saved* state.
                    
                    // Let's grab the latest saved state from store if available, or use current draft if new.
                    if let saved = createdRecapStore.getBlogDetail(blogId: blogId) {
                        draftSnapshot = saved
                        // If local draft has changes from settings (e.g. title), they will differ from saved, so "Unsaved Changes" will trigger. Correct.
                    } else {
                        draftSnapshot = draft
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation { isKeyboardVisible = false }
            }
            .sheet(item: $overflowStop) { item in
                PlaceStopActionSheet(
                    placeTitle: item.stop.placeTitle,
                    onEditName: { showEditNameForStop = item.stop },
                    onEditPlace: { isEditMode = true },
                    onRemoveFromBlog: { removePlaceStop(dayId: item.dayId, stopId: item.stop.id) }
                )
            }
            .sheet(item: $showEditNameForStop) { stop in
                EditPlaceStopNameSheet(placeTitle: bindingForPlaceTitle(stopId: stop.id), location: stop.representativeLocation?.clCoordinate ?? stop.photos.first?.location?.clCoordinate, onSave: { newTitle in
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
                placePhotoModalSheet(item: item)
            }

            .overlay(alignment: .top) {
                if showFirstSaveBanner {
                    ZStack(alignment: .top) {
                        // Dimmed background
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation { showFirstSaveBanner = false }
                            }
                        
                        // Notification Banner
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Draft has been saved")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Your recap blog is ready.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            Spacer()
                            Button {
                                withAnimation { showFirstSaveBanner = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                    }
                    .transition(.opacity) // Fade in/out for the whole ZStack (dimming + banner)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFirstSaveBanner)
            .preferredColorScheme(.dark)
        }
    }

    @State private var scrollToStopId: UUID?

    private static let dayFilterApproxHeight: CGFloat = 52

    private func mainContent(screenHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        if draft.selectedCoverPhotoIdentifier != nil {
                            coverPhotoHero(screenHeight: screenHeight) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    proxy.scrollTo("RecapMapSection", anchor: .top)
                                }
                            }
                        } else {
                            blogTitleView
                        }
                        if !isEditMode {
                            mapOrPreviewCard
                                .id("RecapMapSection")
                        }
                        timelineContent
                        
                        // Spacer for bottom filter + Undo button
                        Color.clear
                            .frame(height: Self.dayFilterApproxHeight + 80)
                    }
                    .background(Color.black)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { minY in
                    // If the title (or cover) goes off screen (minY < -someThreshold), show sticky title.
                    // We'll track the bottom of the title view? Or just the top.
                    // Let's say simpler: if the top of the content is scrolled up past the safe area?
                    // But we want it to trigger when the *Big Title* disappears.
                    // So we expect the GeometryReader on the title view to report its frame.
                    // When (frame.maxY < safeAreaTop), show sticky title.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showStickyTitle = minY < 0 
                    }
                }
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .onChange(of: scrollToStopId) { _, newId in
                    guard let id = newId else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    scrollToStopId = nil
                }
                
                if !isKeyboardVisible {
                    // Day Filter fixed at bottom
                    dayFilterSection
                        .ignoresSafeArea(.keyboard)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Undo Overlay (Banner or Button)
                if showUndoOverlay {
                    UndoOverlayView(
                        text: lastUndoAction?.text ?? "Item deleted",
                        isMinimized: $isUndoMinimized,
                        onUndo: {
                            performUndo()
                        },
                        onDismiss: {
                            withAnimation {
                                showUndoOverlay = false
                                lastUndoAction = nil
                            }
                        }
                    )
                    // When expanded, push it up above the day filter
                    // When minimized, it sits in bottom right (UndoOverlayView handles its own bottom alignment to safe area, 
                    // but we might want to offset it slightly to not cover the last day chip if list is long, 
                    // though typically FABs overlay content).
                    // The Day Filter is ~52pt high.
                    .padding(.bottom, isUndoMinimized ? 52 : 72) 
                    .ignoresSafeArea(.keyboard)
                }
            }
        }
        .background(Color.black)
    }

    private var blogTitleView: some View {
        Group {
            if isEditMode {
                Button {
                    showTitleChange = true
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Text(draft.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.trailing, 32)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            } else {
                Text(draft.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.trailing, 32)
                    .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named("scroll")).maxY
                )
            }
        )
    }

    private func coverPhotoHero(screenHeight: CGFloat, scrollToMap: @escaping () -> Void = {}) -> some View {
        GeometryReader { geo in
            ZStack {
                // Cover photo — tap to change
                if let coverId = draft.selectedCoverPhotoIdentifier {
                    AssetPhotoView(assetIdentifier: coverId, cornerRadius: 0, targetSize: CGSize(width: 1200, height: 1200))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showCoverPhotoPicker = true
                        }
                }

                // Dimmed overlay — stronger in edit mode for readability
                Color.black.opacity(isEditMode ? 0.45 : 0.0)

                // Gradient overlay for text legibility (view mode)
                if !isEditMode {
                    LinearGradient(
                        colors: [Color.black.opacity(0.5), Color.clear, Color.black.opacity(0.3)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }

                // Title + duration overlay at center
                VStack(spacing: 6) {
                    if isEditMode {
                        Button { showTitleChange = true } label: {
                            HStack(spacing: 6) {
                                Text(draft.title)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                    } else {
                        Text(draft.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

                        Text(tripDurationText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    }
                }
                .padding(.horizontal, 24)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("scroll")).maxY
                        )
                    }
                )

                // Edit mode: change cover button (top right)
                if isEditMode {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showCoverPhotoPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo")
                                        .font(.caption)
                                    Text("Change Cover")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                }

                // Scroll hint arrow
                if !isEditMode {
                    VStack {
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.bottom, 16)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120),
                        alignment: .bottom
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        scrollToMap()
                    }
                }
            }
        }
        .frame(height: screenHeight * 0.55)
        .padding(.bottom, 16)
    }


    private var tripDurationText: String {
        guard let firstDate = draft.days.first?.date,
              let lastDate = draft.days.last?.date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dayCount = draft.days.count
        if Calendar.current.isDate(firstDate, equalTo: lastDate, toGranularity: .year) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate)), \(yearFormatter.string(from: lastDate)) · \(dayCount) day\(dayCount == 1 ? "" : "s")"
        }
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate)) · \(dayCount) day\(dayCount == 1 ? "" : "s")"
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
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .fixedSize(horizontal: false, vertical: true)
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
                    .font(.title3) // Bigger than previous .headline, smaller than Blog Title (.largeTitle/34)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Image(systemName: "sun.max")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                let badgeColor: Color = (index == 0) ? .green : (index == day.placeStops.count - 1 ? .orange : .blue)
                PlaceStopRowView(
                    day: day,
                    stop: stop,
                    stopNumber: index + 1,
                    isEditMode: isEditMode,
                    badgeColor: badgeColor,
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
                    onCaptionFocus: { scrollToStopId = stop.id },
                    onNavigate: { openNavigation(for: stop) },
                    onEditName: { showEditNameForStop = stop }
                )
                .id(stop.id)
                
                if !isEditMode && index < day.placeStops.count - 1 {
                    let nextStop = day.placeStops[index + 1]
                    if let dist = distanceString(from: stop, to: nextStop) {
                        HStack {
                            Spacer()
                            Text(dist)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 32) // Aligned roughly with content
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func placePhotoModalSheet(item: PlacePhotoModalItem) -> some View {
        Group {
            if let stop = placeStop(dayId: item.dayId, stopId: item.stopId), !stop.photos.isEmpty {
                PlacePhotoModalView(
                    placeTitle: bindingForPlaceTitle(stopId: item.stopId),
                    placeSubtitle: stop.placeSubtitle,
                    photos: stop.photos,
                    initialPhotoId: stop.photos.contains(where: { $0.id == item.initialPhotoId }) ? item.initialPhotoId : stop.photos[0].id,
                    blogIsEditMode: isEditMode,
                    photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
                    onDismiss: { placePhotoModalItem = nil }
                )
            } else {
                Color.white
                    .onAppear { placePhotoModalItem = nil }
            }
        }
        .presentationDetents(isEditMode ? [.fraction(1.0)] : [.fraction(0.99)])
        .presentationDragIndicator(isEditMode ? .hidden : .hidden)
        .presentationCornerRadius(isEditMode ? 0 : 24)
        .presentationBackground(Color.white)
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

    private var isAlreadySaved: Bool {
        createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt != nil
    }

    private var shareText: String {
        let placeCount = draft.days.flatMap(\.placeStops).count
        if placeCount > 0 {
            return "\(draft.title) – My Recap Blog (\(placeCount) places)"
        }
        return "\(draft.title) – My Recap Blog"
    }

    private func saveDraft() {
        // Check if this is the first save before saving
        let isFirstSave = !isAlreadySaved

        // Clear undo state
        withAnimation {
            showUndoOverlay = false
            lastUndoAction = nil
        }

        createdRecapStore.saveBlogDetail(draft)
        DraftReminderNotificationManager.cancelPendingReminder()

        if isFirstSave {
            withAnimation {
                showFirstSaveBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showFirstSaveBanner = false
                }
            }
        } else {
            // savedToast removed — user requested only the "Saved as draft" notification in TripsView
        }
    }

    private func day(at index: Int) -> RecapBlogDay? {
        guard draft.days.indices.contains(index) else { return nil }
        return draft.days[index]
    }

    private func removePlaceStop(dayId: UUID, stopId: UUID) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIndex = draft.days[dayIndex].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        
        // Prepare Undo
        let day = draft.days[dayIndex]
        let stop = day.placeStops[stopIndex]
        withAnimation {
            lastUndoAction = .deletePlace(dayId: dayId, stop: stop, index: stopIndex)
            showUndoOverlay = true
            isUndoMinimized = false
        }
        
        // Perform Deletion
        var updatedDay = day
        updatedDay.placeStops.remove(at: stopIndex)
        draft.days[dayIndex] = updatedDay
    }

    fileprivate struct ScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }


    private func removePhoto(dayId: UUID, stopId: UUID, photoId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
              let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
        
        // Prepare Undo
        let day = draft.days[dayIdx]
        let stop = day.placeStops[stopIdx]
        let photo = stop.photos[photoIdx]
        
        withAnimation {
            lastUndoAction = .deletePhoto(dayId: dayId, stopId: stopId, photo: photo, index: photoIdx)
            showUndoOverlay = true
            isUndoMinimized = false
        }
        
        // Perform Deletion
        var updatedDay = day
        var updatedStop = stop
        updatedStop.photos.remove(at: photoIdx)
        updatedDay.placeStops[stopIdx] = updatedStop
        draft.days[dayIdx] = updatedDay
    }
    
    private func performUndo() {
        guard let action = lastUndoAction else { return }
        
        withAnimation {
            switch action {
            case .deletePlace(let dayId, let stop, let index):
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }) {
                    var day = draft.days[dayIdx]
                    if index <= day.placeStops.count {
                        day.placeStops.insert(stop, at: index)
                        draft.days[dayIdx] = day
                    }
                }
                
            case .deletePhoto(let dayId, let stopId, let photo, let index):
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                   let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) {
                    var day = draft.days[dayIdx]
                    var stop = day.placeStops[stopIdx]
                    if index <= stop.photos.count {
                        stop.photos.insert(photo, at: index)
                        day.placeStops[stopIdx] = stop
                        draft.days[dayIdx] = day
                    }
                }
            }
            
            showUndoOverlay = false
            lastUndoAction = nil
        }
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
            set: { newValue in
                for i in draft.days.indices {
                    if let j = draft.days[i].placeStops.firstIndex(where: { $0.id == stopId }) {
                        var day = draft.days[i]
                        var stop = day.placeStops[j]
                        stop.placeTitle = newValue
                        day.placeStops[j] = stop
                        draft.days[i] = day
                        return
                    }
                }
            }
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
    private func distanceString(from: PlaceStop, to: PlaceStop) -> String? {
        guard let loc1 = from.representativeLocation?.clCoordinate ?? from.photos.first?.location?.clCoordinate,
              let loc2 = to.representativeLocation?.clCoordinate ?? to.photos.first?.location?.clCoordinate else {
            return nil
        }
        let start = CLLocation(latitude: loc1.latitude, longitude: loc1.longitude)
        let end = CLLocation(latitude: loc2.latitude, longitude: loc2.longitude)
        let distanceInMeters = end.distance(from: start)
        let distanceInMiles = distanceInMeters / 1609.34
        
        // If really close, maybe don't show? Or show 0.1 mi.
        if distanceInMiles < 0.1 { return nil }
        
        return String(format: "%.1f mi", distanceInMiles)
    }

    private func openNavigation(for stop: PlaceStop) {
        guard let location = stop.representativeLocation?.clCoordinate ?? stop.photos.first?.location?.clCoordinate else { return }
        let lat = location.latitude
        let lon = location.longitude
        if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)") {
            UIApplication.shared.open(url)
        }
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
