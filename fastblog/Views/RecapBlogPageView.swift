//
//  RecapBlogPageView.swift
//  Capper
//

import SwiftUI
import MapKit
import Combine

struct RecapBlogPageView: View {
    let blogId: UUID
    let initialTrip: TripDraft?

    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecapBlogDetail
    @State private var selectedDayIndex: Int = 0  // 0 = Day 1, 1 = Day 2, ...
    @State private var overflowStop: OverflowItem?
    @State private var showEditNameForStop: PlaceStop?
    @State private var showManagePhotosForStop: ManagePhotosItem?
    /// Snapshot taken when ManagePhotosView opens, used to diff on dismiss for targeted cloud sync.
    @State private var managePhotosEditInfo: ManagePhotosEditInfo?
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
    @State private var showNewBlogExitConfirmation = false

    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoOverlay = false
    @State private var isUndoMinimized = false
    @State private var isKeyboardVisible = false
    @State private var cancellables = Set<AnyCancellable>()

    // Cloud Upload State
    @State private var isUploading = false
    @State private var uploadProgress: (current: Int, total: Int) = (0, 0)
    @State private var showUploadingFullScreen = false
    @State private var showUploadSuccessBanner = false
    @State private var showUploadErrorAlert = false
    @State private var uploadErrorMessage = ""
    @State private var showRemoveFromCloudAlert = false
    @State private var showAuth = false
    @State private var showRestorePlaces = false

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
            bodyContent(screenHeight: screenGeo.size.height)
        }
    }

    private func bodyContent(screenHeight: CGFloat) -> some View {
        coreContent(screenHeight: screenHeight)
            .overlay(alignment: .top) { firstSaveBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFirstSaveBanner)
            .overlay(alignment: .top) { uploadSuccessBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showUploadSuccessBanner)
            .fullScreenCover(isPresented: $showUploadingFullScreen) {
                UploadingBlogView(uploadProgress: $uploadProgress)
            }
            .alert("Upload Failed", isPresented: $showUploadErrorAlert) {
                if uploadErrorMessage == "Please sign in to upload photos." {
                    Button("Sign In") {
                        showAuth = true
                    }
                    Button("Close", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(uploadErrorMessage)
            }
            .alert("Remove from Cloud?", isPresented: $showRemoveFromCloudAlert) {
                Button("Yes", role: .destructive) {
                    removeCloudURLsFromDraft()
                }
                Button("No", role: .cancel) { }
            } message: {
                Text("This will remove your blog from the cloud. Your local blog and photos will not be affected.")
            }
            .fullScreenCover(isPresented: $showAuth) {
                AuthView(onAuthenticated: {
                    showAuth = false
                })
                .environmentObject(authService)
            }
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func coreContentRoot(screenHeight: CGFloat) -> some View {
        if draft.days.isEmpty && initialTrip != nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            mainContent(screenHeight: screenHeight)
        }
    }

    private func coreContent(screenHeight: CGFloat) -> some View {
        coreContentWithSheets(screenHeight: screenHeight)
    }

    private func coreContentWithSheets(screenHeight: CGFloat) -> some View {
        coreContentRoot(screenHeight: screenHeight)
            .navigationBarBackButtonHidden(true)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showBlogSettings) {
                BlogSettingsSheet(
                    draft: $draft,
                    blogKey: currentBlogKey,
                    onSave: { saveDraft() },
                    onEditMode: {
                        showBlogSettings = false
                        isEditMode = true
                    },
                    onDelete: {
                        createdRecapStore.deleteBlog(sourceTripId: blogId)
                        dismiss()
                    },
                    onRemoveFromCloud: {
                        createdRecapStore.removeFromCloud(blogId: blogId)
                    },
                    onRestore: {
                        // Persist after a place is restored from the Restore Places sheet
                        createdRecapStore.saveBlogDetail(draft)
                        syncWithCloudIfNeeded()
                    }
                )
            }
            .sheet(isPresented: $showTitleChange, onDismiss: {
                if !isEditMode { createdRecapStore.saveBlogDetail(draft); syncWithCloudIfNeeded() }
            }) {
                BlogTitleChangeSheet(title: $draft.title, blogKey: currentBlogKey) {
                    showTitleChange = false
                }
            }
            .sheet(isPresented: $showCoverPhotoPicker, onDismiss: {
                if !isEditMode { createdRecapStore.saveBlogDetail(draft); syncWithCloudIfNeeded() }
            }) {
                BlogCoverPhotoPickerView(
                    photos: allIncludedPhotos,
                    selectedIdentifier: $draft.selectedCoverPhotoIdentifier,
                    onSave: {
                        showCoverPhotoPicker = false
                    }
                )
            }
            .sheet(item: $overflowStop) { item in
                PlaceStopActionSheet(
                    placeTitle: item.stop.placeTitle,
                    placeSubtitle: item.stop.placeSubtitle,
                    onEditName: { showEditNameForStop = item.stop },
                    onManagePhotos: { openManagePhotos(dayId: item.dayId, stopId: item.stop.id) },
                    onEditMode: { isEditMode = true },
                    onRemoveFromBlog: { removePlaceStop(dayId: item.dayId, stopId: item.stop.id) }
                )
            }
            .sheet(item: $showEditNameForStop) { stop in
                EditPlaceStopNameSheet(placeTitle: bindingForPlaceTitle(stopId: stop.id), location: stop.representativeLocation?.clCoordinate ?? stop.photos.first?.location?.clCoordinate, onSave: { newTitle in
                    updatePlaceTitle(stopId: stop.id, to: newTitle)
                })
            }
            .sheet(item: $showManagePhotosForStop, onDismiss: {
                if !isEditMode { createdRecapStore.saveBlogDetail(draft); syncPhotoChangesWithCloud() }
            }) { pair in
                ManagePhotosView(
                    placeTitle: placeStop(dayId: pair.dayId, stopId: pair.stopId)?.placeTitle ?? "Photos",
                    photos: bindingForPhotos(dayId: pair.dayId, stopId: pair.stopId)
                )
            }
            .fullScreenCover(isPresented: $showEditPhotoFlow, onDismiss: {
                if !isEditMode { createdRecapStore.saveBlogDetail(draft); syncWithCloudIfNeeded() }
            }) {
                EditBlogPhotoFlowView(blogId: blogId, onDismiss: { showEditPhotoFlow = false })
                    .environmentObject(createdRecapStore)
            }
            .fullScreenCover(item: $fullScreenMapDay) { day in
                FullScreenMapView(day: day) {
                    fullScreenMapDay = nil
                }
            }
            .sheet(item: $placePhotoModalItem, onDismiss: {
                if !isEditMode { createdRecapStore.saveBlogDetail(draft); syncWithCloudIfNeeded() }
            }) { item in
                placePhotoModalSheet(item: item)
            }
            .sheet(isPresented: $showRestorePlaces) {
                RemovedPlacesSheet(draft: $draft) {
                    createdRecapStore.saveBlogDetail(draft)
                    syncWithCloudIfNeeded()
                }
            }
            .modifier(coreContentAlertsAndLifecycleModifier())
    }

    private func coreContentAlertsAndLifecycleModifier() -> some ViewModifier {
        CoreContentAlertsAndLifecycleModifier(
            showSaveTipAlert: $showSaveTipAlert,
            showFirstTimeSaveTip: $showFirstTimeSaveTip,
            showUnsavedChangesAlert: $showUnsavedChangesAlert,
            showNewBlogExitConfirmation: $showNewBlogExitConfirmation,
            draftSnapshot: $draftSnapshot,
            cancellables: $cancellables,
            isKeyboardVisible: $isKeyboardVisible,
            isEditMode: isEditMode,
            draft: draft,
            blogId: blogId,
            saveDraft: saveDraft,
            loadDraftIfNeeded: loadDraftIfNeeded,
            checkFirstTimeTip: checkFirstTimeTip,
            createdRecapStore: createdRecapStore,
            dismiss: dismiss
        )
    }

    @State private var scrollToStopId: UUID?
    /// When the user focuses a story/caption field we store the row id here and scroll when the keyboard actually appears (no fixed delay).
    @State private var pendingScrollToStopId: UUID?

    private static let dayFilterApproxHeight: CGFloat = 52

    private func mainContent(screenHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        if draft.selectedCoverPhotoIdentifier != nil {
                            coverPhotoHero(screenHeight: screenHeight)
                        } else {
                            blogTitleView
                        }
                        // Restore card sits right under the cover photo/title in edit mode
                        if isEditMode && !draft.removedPlaceStops.isEmpty {
                            restoreRemovedPlacesCard
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                        }
                        if !isEditMode {
                            mapOrPreviewCard
                                .id("map-anchor")
                        }
                        timelineContent
                        
                        // Spacer for bottom filter + Undo button
                        Color.clear
                            .frame(height: Self.dayFilterApproxHeight + 80)
                    }
                    .background(Color.black)
                }
                .background(Color.black)
                .ignoresSafeArea(edges: isKeyboardVisible ? [] : .bottom)
                .onChange(of: scrollToStopId) { _, newId in
                    guard let id = newId else { return }
                    scrollToStopId = nil
                    if isKeyboardVisible {
                        // Keyboard already up (e.g. switched to another field); scroll immediately.
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    } else {
                        pendingScrollToStopId = id
                    }
                }
                .onChange(of: isKeyboardVisible) { _, visible in
                    if visible, let id = pendingScrollToStopId {
                        pendingScrollToStopId = nil
                        withAnimation(.easeOut(duration: 0.25)) {
                            // Anchor .top so the row sits at the top of the visible area and the text field stays well above the keyboard.
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                .onChange(of: selectedDayIndex) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("map-anchor", anchor: .top)
                    }
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
    }

    private func coverPhotoHero(screenHeight: CGFloat) -> some View {
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

                if !isEditMode && blogIsInCloud {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                showShareSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                        }
                        .padding(.bottom, 20)
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
                .fill(.ultraThinMaterial.opacity(0.75))
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

    /// Inline card that shows how many places have been removed and lets the user jump to the restore sheet.
    private var restoreRemovedPlacesCard: some View {
        Button {
            showRestorePlaces = true
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore Removed Places")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(draft.removedPlaceStops.count == 1
                         ? "1 place was removed — tap to bring it back"
                         : "\(draft.removedPlaceStops.count) places were removed — tap to bring them back")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.14))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                        openManagePhotos(dayId: day.id, stopId: stop.id)
                    },
                    onRemovePhoto: { photoId in
                        removePhoto(dayId: day.id, stopId: stop.id, photoId: photoId)
                    },
                    onPhotoTapped: { photo in
                        placePhotoModalItem = PlacePhotoModalItem(dayId: day.id, stopId: stop.id, initialPhotoId: photo.id)
                    },
                    onCaptionFocus: { scrollToStopId = stop.id },
                    onNavigate: { openNavigation(for: stop) },
                    onEditName: { showEditNameForStop = stop },
                    onDoneEditingStory: { stopId, isPlaceNote, photoId in
                        syncStoryToCloudIfNeeded(stopId: stopId, isPlaceNote: isPlaceNote, photoId: photoId)
                    }
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
            if let stop = placeStop(dayId: item.dayId, stopId: item.stopId) {
                let includedPhotos = stop.photos.filter(\.isIncluded)
                if !includedPhotos.isEmpty {
                    PlacePhotoModalView(
                        placeTitle: bindingForPlaceTitle(stopId: item.stopId),
                        placeSubtitle: stop.placeSubtitle,
                        photos: includedPhotos,
                        initialPhotoId: includedPhotos.contains(where: { $0.id == item.initialPhotoId }) ? item.initialPhotoId : includedPhotos[0].id,
                        photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
                        onDismiss: { placePhotoModalItem = nil }
                    )
                } else {
                    Color.white
                        .onAppear { placePhotoModalItem = nil }
                }
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

    private var shareItems: [Any] {
        // Put the URL first so iOS "Copy" action copies the link, not the text.
        if blogIsInCloud,
           let blog = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }),
           let key = blog.blogKey {
            let user = AuthService.shared.currentUser
            let username = user?.username ?? user?.displayName ?? user?.email ?? "user"
            let safeUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "user"
            if let url = URL(string: "https://ls-beta-84213e85e326.herokuapp.com/trip/\(safeUsername)/\(key)") {
                return [url, shareText]
            }
        }
        return [shareText]
    }

    private func saveDraft() {
        // Check if this is the first save before saving
        let isFirstSave = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil

        // Clear undo state
        withAnimation {
            showUndoOverlay = false
            lastUndoAction = nil
        }

// AutosaveManager.shared.cancelPending() — removed
        createdRecapStore.saveBlogDetail(draft)
        syncWithCloudIfNeeded()

        if isFirstSave {
            withAnimation {
                showFirstSaveBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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
        
        // Soft-delete: preserve stop in removedPlaceStops so it can be restored later
        let removedEntry = RemovedPlaceEntry(dayId: dayId, dayIndex: day.dayIndex, stop: stop)
        draft.removedPlaceStops.append(removedEntry)
        
        // Perform Deletion
        var updatedDay = day
        updatedDay.placeStops.remove(at: stopIndex)

        if updatedDay.placeStops.isEmpty {
            // No places left in this day — remove the whole day
            draft.days.remove(at: dayIndex)
            // Clamp selectedDayIndex if it's now out of bounds
            if selectedDayIndex >= draft.days.count {
                selectedDayIndex = max(0, draft.days.count - 1)
            }
        } else {
            draft.days[dayIndex] = updatedDay
        }
        
        if !isEditMode {
            createdRecapStore.saveBlogDetail(draft)
            syncWithCloudIfNeeded()
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
        updatedStop.photos[photoIdx].isIncluded = false
        updatedDay.placeStops[stopIdx] = updatedStop
        draft.days[dayIdx] = updatedDay

        if !isEditMode {
            createdRecapStore.saveBlogDetail(draft)
            if let placeKey = stop.visitedTimeDigitized, photo.cloudURL != nil {
                Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "delete") }
            }
        }
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
                // Remove from the soft-deleted list since user chose to undo (not just restore later)
                draft.removedPlaceStops.removeAll { $0.stop.id == stop.id }
                
            case .deletePhoto(let dayId, let stopId, let photo, _):
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                   let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) {
                    var day = draft.days[dayIdx]
                    var stop = day.placeStops[stopIdx]
                    if let pIdx = stop.photos.firstIndex(where: { $0.id == photo.id }) {
                        stop.photos[pIdx].isIncluded = true
                        day.placeStops[stopIdx] = stop
                        draft.days[dayIdx] = day
                        if !isEditMode, let placeKey = stop.visitedTimeDigitized, photo.cloudURL != nil {
                            Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "add") }
                        }
                    }
                }
            }

            showUndoOverlay = false
            lastUndoAction = nil

            if !isEditMode {
                createdRecapStore.saveBlogDetail(draft)
            }
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
                
                if !isEditMode {
                    createdRecapStore.saveBlogDetail(draft)
                    syncWithCloudIfNeeded()
                }
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

    /// Pushes the current place note or photo caption to the backend when the blog is in the cloud. Call when user taps Done on the keyboard toolbar.
    private func syncStoryToCloudIfNeeded(stopId: UUID, isPlaceNote: Bool, photoId: UUID?) {
        guard blogIsInCloud else { return }
        guard let day = draft.days.first(where: { $0.placeStops.contains(where: { $0.id == stopId }) }),
              let stop = day.placeStops.first(where: { $0.id == stopId }),
              let placeKey = stop.visitedTimeDigitized else { return }
        Task {
            if isPlaceNote {
                let storyText = stop.noteText ?? ""
                try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: storyText, photoIndex: nil)
            } else if let pid = photoId,
                      let photo = stop.photos.first(where: { $0.id == pid }) {
                let included = stop.photos.filter(\.isIncluded)
                guard let filteredIndex = included.firstIndex(where: { $0.id == pid }) else { return }
                let storyText = photo.caption ?? ""
                try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: storyText, photoIndex: filteredIndex, photoIndexType: "filtered")
            }
        }
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

    private func checkFirstTimeTip() {
        // If the blog has been saved before, start in View Mode.
        if let existing = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }), existing.lastEditedAt != nil {
            isEditMode = false
        } else if showFirstTimeSaveTip {
            showSaveTipAlert = true
        }
        
        // Snapshot for change detection (after a brief delay so draft is loaded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.draftSnapshot == nil {
                self.draftSnapshot = self.draft
            }
        }
    }

    // MARK: - Extracted Body Helpers

    private var navTitle: String {
        let hasBeenSaved = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt != nil
        if !hasBeenSaved {
            return "Draft"
        } else {
            return isEditMode ? "Edit Mode" : "Recap Blog"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if isEditMode {
                    let isFirstCreation = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil
                    
                    if isFirstCreation {
                        showNewBlogExitConfirmation = true
                    } else {
                        showUnsavedChangesAlert = true
                    }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
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
                        if blogIsInCloud {
                            showRemoveFromCloudAlert = true
                        } else {
                            uploadBlogPhotos()
                        }
                    } label: {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: blogIsInCloud ? "checkmark.icloud.fill" : "icloud.and.arrow.up")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .foregroundColor(blogIsInCloud ? .green : .white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                    .padding(.leading, 12)

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

    @ViewBuilder
    private var firstSaveBannerOverlay: some View {
        if showFirstSaveBanner {
            ZStack(alignment: .top) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { showFirstSaveBanner = false }
                    }
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
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var uploadSuccessBannerOverlay: some View {
        if showUploadSuccessBanner {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploaded to cloud")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("All photos are now in the cloud.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer()
                Button {
                    withAnimation { showUploadSuccessBanner = false }
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
            .transition(.opacity)
        }
    }

    private func removeCloudURLsFromDraft() {
        // 1. Update backend to hide the blog if we have a blogKey
        if let existing = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }),
           let key = existing.blogKey {
            Task {
                do {
                    try await APIManager.shared.setBlogPrivacy(blogKey: key, level: "hidden")
                    print("✅ Successfully hid blog (key: \(key)) from cloud on backend.")
                } catch {
                    print("🚨 Failed to hide blog on backend: \(error)")
                }
            }
        }

        // 2. Clear local cloudURLs
        for dayIdx in draft.days.indices {
            for stopIdx in draft.days[dayIdx].placeStops.indices {
                for photoIdx in draft.days[dayIdx].placeStops[stopIdx].photos.indices {
                    draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = nil
                }
            }
        }
// AutosaveManager.shared.cancelPending() — removed
        createdRecapStore.saveBlogDetail(draft)
    }

    private func syncWithCloudIfNeeded() {
        guard blogIsInCloud else { return }
        
        let snapshot = draft
        let currentBlogId = blogId
        
        // Hide existing cloud blog if we have its key
        if let existingKey = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.blogKey {
            Task {
                try? await APIManager.shared.setBlogPrivacy(blogKey: existingKey, level: "hidden")
            }
        }
        
        // Publish new snapshot
        Task {
            if let newKey = await APIManager.shared.publishBlog(detail: snapshot) {
                await MainActor.run {
                    createdRecapStore.setBlogKey(blogId: currentBlogId, blogKey: newKey)
                }
            }
        }
    }

    /// Captures photo inclusion state for a stop before ManagePhotosView opens so we can diff on dismiss.
    private func openManagePhotos(dayId: UUID, stopId: UUID) {
        if let stop = placeStop(dayId: dayId, stopId: stopId) {
            managePhotosEditInfo = ManagePhotosEditInfo(
                dayId: dayId, stopId: stopId,
                photoInclusionBefore: Dictionary(uniqueKeysWithValues: stop.photos.map { ($0.id, $0.isIncluded) })
            )
        }
        showManagePhotosForStop = ManagePhotosItem(dayId: dayId, stopId: stopId)
    }

    /// Diffs photo inclusion changes made in ManagePhotosView and fires targeted updatePhoto calls.
    /// For newly included photos that have never been uploaded, uploads first then adds.
    private func syncPhotoChangesWithCloud() {
        guard let info = managePhotosEditInfo,
              let stop = placeStop(dayId: info.dayId, stopId: info.stopId),
              let placeKey = stop.visitedTimeDigitized else {
            managePhotosEditInfo = nil
            return
        }

        for photo in stop.photos {
            guard let wasIncluded = info.photoInclusionBefore[photo.id] else { continue }
            if wasIncluded && !photo.isIncluded {
                // Removed — only relevant if the photo was already in the cloud
                guard photo.cloudURL != nil else { continue }
                Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "delete") }
            } else if !wasIncluded && photo.isIncluded {
                if photo.cloudURL != nil {
                    // Already uploaded — just re-include it
                    Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "add") }
                } else {
                    // New photo — upload to file server first, then add to the place
                    Task { await uploadAndAddPhotoToCloud(photo: photo, placeKey: placeKey, stopId: stop.id) }
                }
            }
        }
        managePhotosEditInfo = nil
    }

    /// Uploads a photo that has no cloudURL yet, persists the URL locally, then calls updatePhoto(add).
    private func uploadAndAddPhotoToCloud(photo: RecapPhoto, placeKey: String, stopId: UUID) async {
        guard let assetId = photo.localIdentifier else { return }
        do {
            let cloudURL = try await APIManager.shared.uploadPhoto(assetIdentifier: assetId)

            // Persist the new cloudURL in the draft so it survives future syncs
            for dayIdx in draft.days.indices {
                for stopIdx in draft.days[dayIdx].placeStops.indices
                    where draft.days[dayIdx].placeStops[stopIdx].id == stopId {
                    if let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos
                        .firstIndex(where: { $0.id == photo.id }) {
                        draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = cloudURL
                        createdRecapStore.saveBlogDetail(draft)
                    }
                }
            }

            var uploaded = photo
            uploaded.cloudURL = cloudURL
            try await APIManager.shared.updatePhoto(placeKey: placeKey, photo: uploaded, operation: "add")
        } catch {
            print("🚨 uploadAndAddPhotoToCloud failed: \(error)")
        }
    }

    /// True if every included photo already has a cloud URL.
    private var blogIsInCloud: Bool {
        let included = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        return !included.isEmpty && included.allSatisfy { $0.cloudURL != nil }
    }

    private var currentBlogKey: Int? {
        createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.blogKey
    }

    private func uploadBlogPhotos() {
        guard !isUploading else { return }
        guard AuthService.shared.currentJwtToken != nil else {
            uploadErrorMessage = "Please sign in to upload photos."
            showUploadErrorAlert = true
            return
        }

        // Collect all included photos that still need uploading
        var photosToUpload: [(dayIdx: Int, stopIdx: Int, photoIdx: Int, assetId: String)] = []
        for (dIdx, day) in draft.days.enumerated() {
            for (sIdx, stop) in day.placeStops.enumerated() {
                for (pIdx, photo) in stop.photos.enumerated() {
                    if photo.isIncluded && photo.cloudURL == nil,
                       let assetId = photo.localIdentifier {
                        photosToUpload.append((dIdx, sIdx, pIdx, assetId))
                    }
                }
            }
        }

        if photosToUpload.isEmpty {
            // Already fully uploaded
            withAnimation { showUploadSuccessBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showUploadSuccessBanner = false }
            }
            return
        }

        isUploading = true
        uploadProgress = (0, photosToUpload.count)
        showUploadingFullScreen = true

        Task {
            var failCount = 0
            for item in photosToUpload {
                do {
                    let cloudURL = try await APIManager.shared.uploadPhoto(assetIdentifier: item.assetId)
                    // Write the cloud URL back into the draft
                    draft.days[item.dayIdx].placeStops[item.stopIdx].photos[item.photoIdx].cloudURL = cloudURL
                } catch {
                    failCount += 1
                    print("🚨 Upload failed for asset \(item.assetId): \(error.localizedDescription)")
                }
                uploadProgress.current += 1
            }

            // Save updated draft with cloud URLs
    // AutosaveManager.shared.cancelPending() — removed
            createdRecapStore.saveBlogDetail(draft)

            // Create blog on server (fire-and-forget)
            if failCount == 0 {
                let snapshot = draft
                let currentBlogId = blogId
                Task {
                    if let blogKey = await APIManager.shared.publishBlog(detail: snapshot) {
                        await MainActor.run {
                            createdRecapStore.setBlogKey(blogId: currentBlogId, blogKey: blogKey)
                        }
                    }
                }
            }

            isUploading = false
            showUploadingFullScreen = false

            if failCount > 0 {
                uploadErrorMessage = "\(failCount) photo\(failCount == 1 ? "" : "s") failed to upload. Tap the cloud button to retry."
                showUploadErrorAlert = true
            } else {
                withAnimation { showUploadSuccessBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { showUploadSuccessBanner = false }
                }
            }
        }
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

// MARK: - Core content alerts & lifecycle (split out to help type-checker)
private struct CoreContentAlertsAndLifecycleModifier: ViewModifier {
    @Binding var showSaveTipAlert: Bool
    @Binding var showFirstTimeSaveTip: Bool
    @Binding var showUnsavedChangesAlert: Bool
    @Binding var showNewBlogExitConfirmation: Bool
    @Binding var draftSnapshot: RecapBlogDetail?
    @Binding var cancellables: Set<AnyCancellable>
    @Binding var isKeyboardVisible: Bool
    var isEditMode: Bool
    var draft: RecapBlogDetail
    var blogId: UUID
    var saveDraft: () -> Void
    var loadDraftIfNeeded: () -> Void
    var checkFirstTimeTip: () -> Void
    var createdRecapStore: CreatedRecapBlogStore
    var dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .alert("Welcome to Your Blog!", isPresented: $showSaveTipAlert) {
                Button("Don't Show Again") { showFirstTimeSaveTip = false }
                Button("Okay", role: .cancel) { }
            } message: {
                Text("Tap Save when you're done editing to keep your changes and unlock your map routes.")
            }
            .alert("Save Before Leaving?", isPresented: $showUnsavedChangesAlert) {
                Button("Yes") { saveDraft(); dismiss() }
                Button("No", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Would you like to save before leaving?")
            }
            .alert("Save Before Leaving?", isPresented: $showNewBlogExitConfirmation) {
                Button("Save Draft") {
                    createdRecapStore.saveBlogDetail(draft, asDraft: true)
                    createdRecapStore.showDraftSavedToast = true
                    dismiss()
                }
                Button("Don't Save", role: .destructive) {
                    createdRecapStore.deleteBlog(sourceTripId: blogId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to save this blog as a draft before leaving?")
            }
            .onAppear {
                if createdRecapStore.isLoading {
                    createdRecapStore.$isLoading
                        .filter { !$0 }
                        .first()
                        .receive(on: RunLoop.main)
                        .sink { _ in
                            loadDraftIfNeeded()
                            checkFirstTimeTip()
                        }
                        .store(in: &cancellables)
                } else {
                    loadDraftIfNeeded()
                    checkFirstTimeTip()
                }
            }
            .onChange(of: isEditMode) { _, editing in
                if editing { draftSnapshot = draft }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation { isKeyboardVisible = false }
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

private struct ManagePhotosEditInfo {
    let dayId: UUID
    let stopId: UUID
    /// Inclusion state of each photo at the moment ManagePhotosView was opened.
    let photoInclusionBefore: [UUID: Bool]
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
