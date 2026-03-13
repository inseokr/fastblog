//
//  RecapBlogPageView.swift
//  Capper
//

import SwiftUI
import MapKit
import Combine

private struct TitleMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// MARK: - Caption Edit Sheet Item Types

/// Carries the day identity + mutable caption for the pull-up day caption editor.
struct DayCaptionEditItem: Identifiable {
    let dayId: UUID
    let dayLabel: String
    var id: UUID { dayId }
}

/// Carries the stop identity for the pull-up place caption editor.
struct PlaceCaptionEditItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    var id: UUID { stopId }
}

struct RecapBlogPageView: View {
    let blogId: UUID
    let initialTrip: TripDraft?
    let forceEditMode: Bool
    /// When set (e.g. when presented as overlay), called instead of environment dismiss to close the blog.
    var onRequestDismiss: (() -> Void)? = nil

    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecapBlogDetail
    @State private var selectedDayIndex: Int = 0  // 0 = Day 1, 1 = Day 2, ...
    @State private var overflowStop: OverflowItem?
    @State private var showEditNameForStop: PlaceStop?
    @State private var showManagePhotosForStop: ManagePhotosItem?
    /// The stop currently having its place caption generated (triggered by place name pick).
    @State private var generatingCaptionStopId: UUID?
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
    /// The cover photo asset identifier captured just before the cover picker opens, used to detect changes on dismiss.
    @State private var coverPhotoIdentifierBeforeEdit: String? = nil
    /// Snapshot of the draft when edit mode was entered; compared to detect changes.
    @State private var draftSnapshot: RecapBlogDetail?
    @AppStorage("blogify.showFirstTimeSaveTip") private var showFirstTimeSaveTip = true
    @AppStorage("hasUploadedFirstBlog") private var hasUploadedFirstBlog = false
    @State private var showCloudOnboardingModal = false
    @State private var newlyUploadedBlogKey: Int? = nil
    @State private var showSaveTipAlert = false
    @State private var showFirstSaveBanner = false
    @State private var showNewBlogExitConfirmation = false
    @State private var showUploadPromptAlert = false
    @State private var showNavBarTitle = false
    @State private var hasFinishedInitialLoad = false

    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoOverlay = false
    @State private var isUndoMinimized = false
    @State private var isKeyboardVisible = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visitedDayIndices: Set<Int> = [0]

    // Cloud Upload State
    @State private var isUploading = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadProgress: (current: Int, total: Int) = (0, 0)
    @State private var showUploadingFullScreen = false
    @State private var showUploadSuccessBanner = false
    @State private var showUploadErrorAlert = false
    @State private var uploadErrorMessage = ""
    @State private var showRemoveFromCloudAlert = false
    @State private var showAuth = false
    @State private var pendingEarlyAccessAfterAuth = false
    @State private var pendingCloudUploadAfterAuth = false
    @State private var pendingExportAfterAuth = false
    /// Single pull-up modal: shown when non-nil; content is "You're on the list" when true, else "Join Early Access" prompt.
    @State private var earlyAccessSheetPresented: Bool = false
    @State private var earlyAccessShowOnListConfirm: Bool = false
    @AppStorage("hasJoinedEarlyAccess") private var hasJoinedEarlyAccess = false
    @State private var isExportingPDF = false
    @State private var pdfExportURL: URL?
    @State private var showPDFPreview = false
    @State private var showProfileManagement = false
    @State private var showRestorePlaces = false
    /// Tracks whether AI auto-fill is running so we don't show the blog as empty during generation.
    @State private var isAutoFillingCaptions = false
    /// The day ID currently having its caption AI-generated (nil when idle).
    @State private var isGeneratingDayCaptionForDayId: UUID?
    /// Day caption pull-up sheet trigger.
    @State private var dayCaptionEditItem: DayCaptionEditItem?
    /// Place caption pull-up sheet trigger.
    @State private var placeCaptionEditItem: PlaceCaptionEditItem?
    /// Alert when user taps a day that is not yet processed (geocoding still in progress).
    @State private var showUnprocessedDayAlert = false
    
    // MARK: - New Moments
    @State private var newMomentPhotos: [MockPhoto] = []
    @State private var showNewMomentsReviewSheet = false
    @State private var isCheckingNewMoments = false
    @State private var hasCheckedNewMoments = false

    // MARK: - Split Blog Properties
    @State private var showSplitActionSheet = false
    @State private var dayIndexToSplit: Int?
    @State private var unsavedSplitPromptIndex: Int?
    @State private var showSplitUndoBanner = false

    private enum UndoAction {
        case deletePlace(dayId: UUID, stop: PlaceStop, index: Int)
        case deletePhoto(dayId: UUID, stopId: UUID, photo: RecapPhoto, index: Int)

        var text: String {
            switch self {
            case .deletePlace: return "Place hidden"
            case .deletePhoto: return "Photo removed"
            }
        }
    }

    init(blogId: UUID, initialTrip: TripDraft?, forceEditMode: Bool = false, onRequestDismiss: (() -> Void)? = nil) {
        self.blogId = blogId
        self.initialTrip = initialTrip
        self.forceEditMode = forceEditMode
        self.onRequestDismiss = onRequestDismiss
        _draft = State(initialValue: RecapBlogDetail(id: blogId, title: "", days: [], coverTheme: "default"))
    }

    private func performDismiss() {
        if let onRequestDismiss {
            onRequestDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                bodyContent(screenHeight: screenGeo.size.height)
            }

            if isExportingPDF {
                ExportingPDFView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isExportingPDF)
    }

    private func bodyContent(screenHeight: CGFloat) -> some View {
        bodyContentBase(screenHeight: screenHeight)
            .fullScreenCover(isPresented: $showAuth) {
                AuthView(
                    onAuthenticated: {
                        if pendingEarlyAccessAfterAuth {
                            // Immediately return to the blog with the confirmation pull-up; register via API in the background.
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            pendingEarlyAccessAfterAuth = false
                            hasJoinedEarlyAccess = true
                            earlyAccessShowOnListConfirm = true
                            showAuth = false
                            Task {
                                await EarlyAccessManager.shared.registerWaitlist()
                            }
                        } else if pendingCloudUploadAfterAuth {
                            pendingCloudUploadAfterAuth = false
                            showAuth = false
                            handleCloudUploadTap()
                        } else if pendingExportAfterAuth {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                showAuth = false
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                pendingExportAfterAuth = false
                                exportBlogToPDF()
                            }
                        } else {
                            showAuth = false
                        }
                    },
                    onDismiss: {
                        if pendingEarlyAccessAfterAuth {
                            earlyAccessSheetPresented = false
                        }
                        showAuth = false
                    },
                    hostControlsDismiss: true
                )
                .environmentObject(authService)
            }
            .sheet(isPresented: $earlyAccessSheetPresented) {
                earlyAccessModalContent(isOnList: earlyAccessShowOnListConfirm)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPDFPreview) {
                if let url = pdfExportURL {
                    PDFPreviewSheet(pdfURL: url)
                }
            }
            .sheet(isPresented: $showProfileManagement, onDismiss: {
                if let updatedDetail = createdRecapStore.getBlogDetail(blogId: blogId) {
                    draft = updatedDetail
                }
            }) {
                ProfileManagementView()
                    .environmentObject(createdRecapStore)
            }
    }

    private func bodyContentBase(screenHeight: CGFloat) -> some View {
        coreContent(screenHeight: screenHeight)
            .overlay(alignment: .top) { firstSaveBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFirstSaveBanner)
            .overlay(alignment: .top) { uploadSuccessBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showUploadSuccessBanner)
            .fullScreenCover(isPresented: $showUploadingFullScreen) {
                UploadingBlogView(uploadProgress: $uploadProgress, onCancel: cancelUpload)
            }
            .alert("Upload Failed", isPresented: $showUploadErrorAlert) {
                if uploadErrorMessage == "Cloud storage limit reached.\nRemove a published blog to continue." {
                    Button("Manage") {
                        showProfileManagement = true
                    }
                    Button("OK", role: .cancel) { }
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
            .alert("Upload to Cloud?", isPresented: $showUploadPromptAlert) {
                Button("Yes") {
                    uploadBlogPhotos()
                }
                Button("No", role: .cancel) { }
            } message: {
                Text("This blog needs to be uploaded to the cloud before you can share a link. Would you like to upload it now?")
            }
            .overlay {
                if showUnprocessedDayAlert {
                    ProcessingDayPopup {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showUnprocessedDayAlert = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showUnprocessedDayAlert)
                    .zIndex(999)
                }
            }
            .onReceive(createdRecapStore.objectWillChange) {
                if let updated = createdRecapStore.getBlogDetail(blogId: blogId),
                   updated.days.count == draft.days.count, !updated.days.isEmpty {
                    draft = updated
                }
                if showUnprocessedDayAlert {
                    let stillProcessing = createdRecapStore.processingDayIndexByBlogId[blogId] != nil
                    let allResolved = draft.days.allSatisfy { $0.isPlaceNamesResolved }
                    if !stillProcessing && allResolved {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showUnprocessedDayAlert = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func coreContentRoot(screenHeight: CGFloat) -> some View {
        if draft.days.isEmpty && initialTrip != nil && !hasFinishedInitialLoad {
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
            .toolbarBackground(!isEditMode && showNavBarTitle ? .visible : .hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showBlogSettings) {
                BlogSettingsSheet(
                    draft: $draft,
                    selectedDayIndex: $selectedDayIndex,
                    blogKey: currentBlogKey,
                    onSave: { saveDraft() },
                    onEditMode: {
                        showBlogSettings = false
                        isEditMode = true
                    },
                    onAddNewMoments: newMomentPhotos.isEmpty ? nil : {
                        showBlogSettings = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showNewMomentsReviewSheet = true
                        }
                    },
                    onDelete: {
                        createdRecapStore.deleteBlog(sourceTripId: blogId)
                        performDismiss()
                    },
                    onRemoveLocalOnly: {
                        createdRecapStore.removeLocalCopy(sourceTripId: blogId)
                        performDismiss()
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
                createdRecapStore.saveBlogDetail(draft)
            }) {
                BlogTitleChangeSheet(title: $draft.title, blogKey: currentBlogKey) {
                    showTitleChange = false
                }
            }
            .sheet(isPresented: $showCoverPhotoPicker, onDismiss: {
                createdRecapStore.saveBlogDetail(draft)
                // Only push to cloud if the selection actually changed and the blog is published
                if let blogKey = currentBlogKey,
                   let newId = draft.selectedCoverPhotoIdentifier,
                   newId != coverPhotoIdentifierBeforeEdit {
                    Task { try? await APIManager.shared.uploadAndUpdateCoverPhoto(blogKey: blogKey, assetIdentifier: newId) }
                }
                coverPhotoIdentifierBeforeEdit = nil
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
                EditPlaceStopNameSheet(
                    placeTitle: bindingForPlaceTitle(stopId: stop.id),
                    location: stop.representativeLocation?.clCoordinate ?? stop.photos.first?.location?.clCoordinate,
                    photos: stop.includedPhotos,
                    onSave: { newTitle, newCoordinate, newCategory in
                        updatePlaceTitle(stopId: stop.id, to: newTitle, category: newCategory, coordinate: newCoordinate)
                    }
                )
            }
            // Day caption pull-up modal
            .sheet(item: $dayCaptionEditItem) { item in
                DayCaptionEditSheet(
                    dayLabel: item.dayLabel,
                    caption: bindingForDayCaption(dayId: item.dayId),
                    onSave: {
                        dayCaptionEditItem = nil
                        createdRecapStore.saveBlogDetail(draft)
                    },
                    onCancel: {
                        dayCaptionEditItem = nil
                    }
                )
            }
            // Place caption pull-up modal
            .sheet(item: $placeCaptionEditItem) { item in
                if let stop = placeStop(dayId: item.dayId, stopId: item.stopId) {
                    PlaceCaptionEditSheet(
                        placeTitle: stop.placeTitle,
                        placeSubtitle: stop.placeSubtitle,
                        photos: stop.includedPhotos,
                        caption: bindingForOverallStory(dayId: item.dayId, stopId: item.stopId),
                        onSave: {
                            placeCaptionEditItem = nil
                            markOverallStoryManual(dayId: item.dayId, stopId: item.stopId)
                            createdRecapStore.saveBlogDetail(draft)
                        },
                        onCancel: {
                            placeCaptionEditItem = nil
                        }
                    )
                }
            }
            .sheet(item: $showManagePhotosForStop, onDismiss: {
                // Capture dayId/stopId before syncPhotoChangesWithCloud clears managePhotosEditInfo.
                let _ = managePhotosEditInfo
                createdRecapStore.saveBlogDetail(draft)
                syncPhotoChangesWithCloud()
            }) { pair in
                ManagePhotosView(
                    placeTitle: placeStop(dayId: pair.dayId, stopId: pair.stopId)?.placeTitle ?? "Photos",
                    photos: bindingForPhotos(dayId: pair.dayId, stopId: pair.stopId)
                )
            }
            .fullScreenCover(isPresented: $showEditPhotoFlow, onDismiss: {
                createdRecapStore.saveBlogDetail(draft)
            }) {
                EditBlogPhotoFlowView(blogId: blogId, onDismiss: { showEditPhotoFlow = false })
                    .environmentObject(createdRecapStore)
            }
            .fullScreenCover(item: $fullScreenMapDay) { day in
                FullScreenMapView(day: day, onDismiss: {
                    fullScreenMapDay = nil
                }, onCaptionSaved: { stopId, photoId, newCaption in
                    // Write the edited caption back into the draft and persist it
                    bindingForPhotoCaption(dayId: day.id, stopId: stopId, photoId: photoId).wrappedValue = newCaption
                    createdRecapStore.saveBlogDetail(draft)
                })
            }
            .sheet(item: $placePhotoModalItem, onDismiss: {
                createdRecapStore.saveBlogDetail(draft)
            }) { item in
                placePhotoModalSheet(item: item)
            }
            .sheet(isPresented: $showRestorePlaces) {
                RemovedPlacesSheet(draft: $draft, selectedDayIndex: $selectedDayIndex) {
                    createdRecapStore.saveBlogDetail(draft)
                    syncWithCloudIfNeeded()
                }
            }
            .sheet(isPresented: $showCloudOnboardingModal) {
                cloudOnboardingModalContent()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: Binding(
                get: { unsavedSplitPromptIndex != nil },
                set: { if !$0 { unsavedSplitPromptIndex = nil } }
            )) {
                if let splitIdx = unsavedSplitPromptIndex {
                    unsavedSplitModal(splitIdx: splitIdx)
                }
            }
            .overlay {
                if showNewMomentsReviewSheet {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showNewMomentsReviewSheet = false
                            }
                        }
                        .transition(.opacity)
                        .zIndex(9)
                }
            }
            .overlay {
                if showNewMomentsReviewSheet {
                    NewMomentsReviewSheet(
                        photos: newMomentPhotos,
                        blogTitle: draft.title,
                        onAdd: { selected in addNewMomentsToBlog(selected) },
                        onLater: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showNewMomentsReviewSheet = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
                }
            }
            .modifier(coreContentAlertsAndLifecycleModifier())
            .alert("Save or Exit?", isPresented: $showNewBlogExitConfirmation) {
                Button("Continue Later") {
                    createdRecapStore.saveBlogDetail(draft, asDraft: true)
                    createdRecapStore.showDraftSavedToast = true
                    performDismiss()
                }
                Button("Exit", role: .destructive) {
                    createdRecapStore.deleteBlog(sourceTripId: blogId)
                    performDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"Continue Later\" saves your blog as a draft. \"Exit\" will discard all changes.")
            }
    }

    private func coreContentAlertsAndLifecycleModifier() -> some ViewModifier {
        CoreContentAlertsAndLifecycleModifier(
            showSaveTipAlert: $showSaveTipAlert,
            showFirstTimeSaveTip: $showFirstTimeSaveTip,
            showUnsavedChangesAlert: $showUnsavedChangesAlert,
            draftSnapshot: $draftSnapshot,
            cancellables: $cancellables,
            isKeyboardVisible: $isKeyboardVisible,
            isEditMode: $isEditMode,
            draft: $draft,
            saveDraft: { saveDraft() },
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
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0)
                            .id("page-top")

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
                        // New moments card — shown when lightweight scan found new photos
                        if !newMomentPhotos.isEmpty {
                            newMomentsCard
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                        }
                        if !isEditMode {
                            mapOrPreviewCard
                                .id("map-anchor")
                        }
                        timelineContent

                        if draft.days.isEmpty && hasFinishedInitialLoad {
                            Text("All places are hidden.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                                .padding(.bottom, 60)
                        }

                        // Spacer for bottom filter + Undo button
                        Color.clear
                            .frame(height: Self.dayFilterApproxHeight + 80)
                    }
                    .background(Color.black)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(TitleMinYPreferenceKey.self) { minY in
                    let shouldShow = minY < 0
                    if shouldShow != showNavBarTitle {
                        showNavBarTitle = shouldShow
                    }
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
                .onChange(of: selectedDayIndex) { _, newIndex in
                    if isEditMode {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("page-top", anchor: .top)
                        }
                        visitedDayIndices.insert(newIndex)
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("map-anchor", anchor: .top)
                        }
                    }
                }
                .onChange(of: hasFinishedInitialLoad) { _, finished in
                    if finished && isEditMode {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("page-top", anchor: .top)
                        }
                    }
                }
                .onChange(of: isEditMode) { _, editing in
                    if editing {
                        visitedDayIndices = [selectedDayIndex]
                    }
                }
                
                // Undo Overlay (Banner or Button)
                if showUndoOverlay {
                    UndoOverlayView(
                        text: lastUndoAction?.text ?? "Item hidden",
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
                    .padding(.bottom, Self.dayFilterApproxHeight + 10)
                    .zIndex(20)
                } else if showSplitUndoBanner {
                        // Special banner for "Undo Split" in edit mode
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Text("Blog split into two parts")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)

                                Spacer()

                                Button("Undo") {
                                    createdRecapStore.undoSplit()
                                    withAnimation {
                                        showSplitUndoBanner = false
                                    }
                                    // Optionally re-fetch draft since we merged back
                                    if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
                                        draft = updated
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(uiColor: .label).opacity(0.88))
                            )
                            .padding(.horizontal, 20)
                    }
                }

                if !isKeyboardVisible {
                    // Day Filter fixed at bottom
                    dayFilterSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.keyboard)
            .background(Color.black)
        }
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
                    .background(
                        GeometryReader { titleGeo in
                            Color.clear.preference(
                                key: TitleMinYPreferenceKey.self,
                                value: titleGeo.frame(in: .named("scroll")).maxY
                            )
                        }
                    )
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
                        .brightness(-0.05)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
                            showCoverPhotoPicker = true
                        }
                }

                // Dimmed overlay — stronger in edit mode for readability
                Color.black.opacity(isEditMode ? 0.45 : 0.25)

                // Gradient overlay for text legibility (view mode)
                if !isEditMode {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.1), Color.black.opacity(0.35)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }

                // Title + duration overlay at center
                VStack(spacing: 12) {
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
                        
                        Button {
                            coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
                            showCoverPhotoPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.subheadline)
                                Text("Change Cover")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    } else {
                        VStack(spacing: 6) {
                            Text(draft.title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                                .background(
                                    GeometryReader { titleGeo in
                                        Color.clear.preference(
                                            key: TitleMinYPreferenceKey.self,
                                            value: titleGeo.frame(in: .named("scroll")).maxY
                                        )
                                    }
                                )

                            Text(tripDurationText)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.92))
                                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                            let placeCount = draft.days.flatMap(\.placeStops).count
                            if placeCount > 0 {
                                Text("\(placeCount) moment\(placeCount == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.92))
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            }

                            Button {
                                if authService.isSignedIn {
                                    exportBlogToPDF()
                                } else {
                                    pendingExportAfterAuth = true
                                    showAuth = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Export")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.15).background(.ultraThinMaterial))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 24)

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
        let processingIndex = createdRecapStore.processingDayIndexByBlogId[blogId]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(draft.days.enumerated()), id: \.element.id) { index, day in
                    dayPill(title: "Day \(day.dayIndex)", index: index, day: day, processingIndex: processingIndex)
                        .id(day.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.75))
                .ignoresSafeArea(edges: .bottom)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dayPill(title: String, index: Int, day: RecapBlogDay, processingIndex: Int?) -> some View {
        let isSelected = selectedDayIndex == index
        let isProcessed = day.isPlaceNamesResolved
        let isProcessing = processingIndex == index
        let isUnprocessed = !isProcessed && !isProcessing
        let isBlocked = isUnprocessed || isProcessing
        return Button {
            if isBlocked {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showUnprocessedDayAlert = true
                }
            } else {
                selectedDayIndex = index
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : (isUnprocessed ? .secondary.opacity(0.6) : .secondary))
                    .opacity(isUnprocessed ? 0.7 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue : Color(white: 0.2))
            .clipShape(Capsule())
            .opacity(isUnprocessed ? 0.85 : 1)
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
                    .id("day-section-\(day.id)")
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
                        .foregroundColor(.white)
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

    /// Inline card shown when new photos were detected for this recent blog.
    private var newMomentsCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                showNewMomentsReviewSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(newMomentPhotos.count) new photo\(newMomentPhotos.count == 1 ? "" : "s") found")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Tap to review and add to your blog")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.14))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private func daySection(day: RecapBlogDay) -> some View {
        let isDayLoading = !day.isPlaceNamesResolved
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(day.shortDateText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                if isDayLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.secondary)
                } else {
                    Image(systemName: "sun.max")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Only show split icon if there are at least 2 days and this isn't the *first* day
                if isEditMode, draft.days.count >= 2, let dayIdx = draft.days.firstIndex(where: { $0.id == day.id }), dayIdx > 0 {
                    Button {
                        let isJustCreated = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil
                        if isJustCreated {
                            unsavedSplitPromptIndex = dayIdx
                        } else {
                            dayIndexToSplit = dayIdx
                            showSplitActionSheet = true
                        }
                    } label: {
                        Image(systemName: "scissors")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Split Blog Here?",
                        isPresented: $showSplitActionSheet,
                        titleVisibility: .visible
                    ) {
                        if let splitIdx = dayIndexToSplit {
                            Button("Split Blog Here") {
                                splitSavedBlog(afterDayIndex: splitIdx - 1)
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            dayIndexToSplit = nil
                        }
                    } message: {
                        if let splitIdx = dayIndexToSplit {
                            let part1Count = splitIdx
                            let part2Count = draft.days.count - part1Count
                            Text("This will create two separate blogs:\n\nPart 1: Day 1–\(part1Count) (\(part1Count) day\(part1Count == 1 ? "" : "s"))\nPart 2: Day \(part1Count + 1)–\(draft.days.count) (\(part2Count) day\(part2Count == 1 ? "" : "s"))")
                        } else {
                            Text("Split this blog into two separate blogs.")
                        }
                    }
                }
            }
            .padding(.top, 4)

            // Day-level caption — right below the date header
            dayCaptionRow(day: day)

            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                let badgeColor: Color = (index == 0) ? .green : (index == day.placeStops.count - 1 ? .orange : .blue)
                PlaceStopRowView(
                    day: day,
                    stop: stop,
                    stopNumber: index + 1,
                    isEditMode: isEditMode,
                    badgeColor: badgeColor,
                    placeNote: bindingForPlaceNote(dayId: day.id, stopId: stop.id),
                    overallStory: bindingForOverallStory(dayId: day.id, stopId: stop.id),
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
                    onCaptionFocus: { focusId in scrollToStopId = focusId },
                    onNavigate: { openNavigation(for: stop) },
                    onEditName: { showEditNameForStop = stop },
                    onDoneEditingStory: { stopId, isPlaceNote, photoId in
                        syncStoryToCloudIfNeeded(stopId: stopId, isPlaceNote: isPlaceNote, photoId: photoId)
                    },
                    onGeneratePlaceStory: {
                        await StoryCaptionService.shared.generatePlaceStory(stop: stop, dayDate: day.date)
                    },
                    onGenerateOverallStory: {
                        guard let currentStop = placeStop(dayId: day.id, stopId: stop.id) else { return "" }
                        let captions = currentStop.photos.filter(\.isIncluded).map { $0.caption ?? "" }
                        return await StoryCaptionService.shared.generateOverallPlaceStory(stop: currentStop, dayDate: day.date, photoCaptions: captions)
                    },
                    onGeneratePhotoCaption: { photo in
                        await StoryCaptionService.shared.generateCaption(photo: photo, placeName: stop.placeTitle, placeSubtitle: stop.placeSubtitle)
                    },
                    onPhotoUserEdited: { photoId in
                        markPhotoCaptionManual(dayId: day.id, stopId: stop.id, photoId: photoId)
                    },
                    onCaptionTapped: { photoId in
                        placePhotoModalItem = PlacePhotoModalItem(dayId: day.id, stopId: stop.id, initialPhotoId: photoId, autoFocusCaption: true)
                    },
                    onOverallStoryUserEdited: {
                        markOverallStoryManual(dayId: day.id, stopId: stop.id)
                    },
                    onAICaptionApplied: { photoId in
                        markPhotoCaptionAI(dayId: day.id, stopId: stop.id, photoId: photoId)
                        Task { await cascadeOverallStory(dayId: day.id, stopId: stop.id) }
                    },
                    onAIOverallStoryApplied: {
                        markOverallStoryAI(dayId: day.id, stopId: stop.id)
                    },
                    onEditPlaceCaption: {
                        placeCaptionEditItem = PlaceCaptionEditItem(dayId: day.id, stopId: stop.id)
                    },
                    isGeneratingCaption: generatingCaptionStopId == stop.id
                )
                .id(stop.id)
                
                if !isEditMode && index < day.placeStops.count - 1 {
                    let nextStop = day.placeStops[index + 1]
                    if let dist = distanceString(from: stop, to: nextStop) {
                        HStack {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(dist)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.leading, 16) // Aligned with the numbered circle badge
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .id("day-section-\(day.id)")
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
                        stopDigitizedTime: stop.visitedTimeDigitized,
                        blogIsEditMode: isEditMode,
                        showAssetTimeMetadata: isEditMode,
                        autoFocusCaption: item.autoFocusCaption,
                        photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
                        onDismiss: { placePhotoModalItem = nil },
                        onGenerateCaption: { photo, placeName, placeSubtitle in
                            await StoryCaptionService.shared.generateCaption(photo: photo, placeName: placeName, placeSubtitle: placeSubtitle)
                        },
                        onAICaptionApplied: { photoId in
                            markPhotoCaptionAI(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                            Task { await cascadeOverallStory(dayId: item.dayId, stopId: item.stopId) }
                        },
                        onPhotoCaptionManuallyEdited: { photoId in
                            markPhotoCaptionManual(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                        },
                        onRemovePhoto: { photoId in
                            removePhoto(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                        }
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
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
        .presentationBackground(.black)
    }

    @ViewBuilder
    private func unsavedSplitModal(splitIdx: Int) -> some View {
        let part1Count = splitIdx
        
        let part1StartDate = draft.days[0..<splitIdx].first?.date
        let part1EndDate = draft.days[0..<splitIdx].last?.date
        let part1DateStr = CreatedRecapBlogStore.formatDateRange(start: part1StartDate, end: part1EndDate) ?? "Unknown Date"
        
        let part2StartDate = draft.days[splitIdx...].first?.date
        let part2EndDate = draft.days[splitIdx...].last?.date
        let part2DateStr = CreatedRecapBlogStore.formatDateRange(start: part2StartDate, end: part2EndDate) ?? "Unknown Date"
        
        let part1Cities = draft.days[0..<splitIdx]
            .flatMap(\.placeStops)
            .compactMap { $0.placeSubtitle }
            .filter { !$0.isEmpty }
        
        // Remove duplicates while preserving order
        var seen1 = Set<String>()
        let part1UniqueCities = part1Cities.filter { seen1.insert($0).inserted }
        let part1CityString = part1UniqueCities.joined(separator: ", ")
        
        let part2Cities = draft.days[splitIdx...]
            .flatMap(\.placeStops)
            .compactMap { $0.placeSubtitle }
            .filter { !$0.isEmpty }
        
        var seen2 = Set<String>()
        let part2UniqueCities = part2Cities.filter { seen2.insert($0).inserted }
        let part2CityString = part2UniqueCities.joined(separator: ", ")
        
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Choose which part to keep")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 24)
                
                Text("The other part will be saved as a separate trip.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            VStack(spacing: 16) {
                Button {
                    unsavedSplitPromptIndex = nil
                    // delay slightly to allow sheet dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitUnsavedBlog(afterDayIndex: splitIdx - 1, keepPart: 1)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep Part 1")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Days 1–\(part1Count) (\(part1DateStr))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !part1CityString.isEmpty {
                            Text(part1CityString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    unsavedSplitPromptIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitUnsavedBlog(afterDayIndex: splitIdx - 1, keepPart: 2)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep Part 2")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Days \(part1Count + 1)–\(draft.days.count) (\(part2DateStr))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !part2CityString.isEmpty {
                            Text(part2CityString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    unsavedSplitPromptIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitUnsavedBlog(afterDayIndex: splitIdx - 1, keepPart: 1)
                    }
                } label: {
                    Text("Keep Both")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .presentationDetents([.fraction(0.50), .large])
        .presentationDragIndicator(.visible)
        .ignoresSafeArea(edges: .bottom)
    }

    private func loadDraftIfNeeded() {
        if let saved = createdRecapStore.getBlogDetail(blogId: blogId) {
            draft = saved
            hasFinishedInitialLoad = true
            // Process any remaining days in background (rate-limited geocoding).
            Task { @MainActor in await createdRecapStore.continueGeocodingDays(blogId: blogId) }
            // Check for new moments if this is a recent blog.
            checkForNewMomentsIfRecent()
            return
        }
        guard let trip = initialTrip ?? createdRecapStore.tripDraft(for: blogId) else {
            hasFinishedInitialLoad = true
            return
        }
        Task { @MainActor in
            let detail = await createdRecapStore.buildBlogDetailFirstDayOnly(from: trip)
            createdRecapStore.saveBlogDetail(detail, asDraft: true)
            draft = detail
            hasFinishedInitialLoad = true
            // Process remaining days in background (rate limit: 50 geocode/min).
            await createdRecapStore.continueGeocodingDays(blogId: blogId)
        }
    }

    // MARK: - New Moments Scan

    private func checkForNewMomentsIfRecent() {
        guard !hasCheckedNewMoments else { return }
        hasCheckedNewMoments = true
        Task { @MainActor in
            isCheckingNewMoments = true
            let photos = await createdRecapStore.scanForNewMoments(blogId: blogId)
            newMomentPhotos = photos
            isCheckingNewMoments = false
        }
    }

    private func addNewMomentsToBlog(_ selected: [MockPhoto]) {
        guard !selected.isEmpty else { return }
        createdRecapStore.injectPhotos(selected, intoSourceTripId: blogId)
        // Save cutoff so these photos don't resurface.
        if let maxDate = newMomentPhotos.map(\.timestamp).max() {
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blogId)
        }
        // Reload the draft with injected photos.
        if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
            draft = updated
            draftSnapshot = updated
        }
        newMomentPhotos = []
        withAnimation(.easeInOut(duration: 0.3)) {
            showNewMomentsReviewSheet = false
        }
    }

    private func dismissNewMoments() {
        newMomentPhotos = []
    }

    private func dismissAndSuppressNewMoments() {
        // Save cutoff so these photos don't resurface until genuinely new ones appear.
        if let maxDate = newMomentPhotos.map(\.timestamp).max() {
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blogId)
        }
        newMomentPhotos = []
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
            if let url = SecureShareToken.shareURL(username: username, blogKey: key) {
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
        let removedEntry = RemovedPlaceEntry(dayId: dayId, dayIndex: day.dayIndex, dayDate: day.date, stop: stop)
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
        
        // Fallback for cover photo if the place containing it was removed
        let allIncludedPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        if let currentCover = draft.selectedCoverPhotoIdentifier, !allIncludedPhotos.contains(where: { $0.localIdentifier == currentCover }) {
            draft.selectedCoverPhotoIdentifier = allIncludedPhotos.compactMap(\.localIdentifier).first
        }
        
        createdRecapStore.saveBlogDetail(draft)
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

        // Fallback for cover photo if the specific photo was removed
        let allIncludedPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        if let currentCover = draft.selectedCoverPhotoIdentifier, !allIncludedPhotos.contains(where: { $0.localIdentifier == currentCover }) {
            draft.selectedCoverPhotoIdentifier = allIncludedPhotos.compactMap(\.localIdentifier).first
        }

        createdRecapStore.saveBlogDetail(draft)
        if let placeKey = stop.visitedTimeDigitized, photo.cloudURL != nil {
            Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "delete") }
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
                        if let placeKey = stop.visitedTimeDigitized {
                            if photo.cloudURL != nil {
                                Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "add") }
                            } else {
                                // Photo was never uploaded — upload first, then add to cloud
                                Task { await uploadAndAddPhotoToCloud(photo: photo, placeKey: placeKey, stopId: stopId) }
                            }
                        }
                    }
                }
            }

            showUndoOverlay = false
            lastUndoAction = nil

            createdRecapStore.saveBlogDetail(draft)
        }
    }

    private func updatePlaceTitle(stopId: UUID, to title: String, category: String? = nil, coordinate: CLLocationCoordinate2D? = nil) {
        for i in draft.days.indices {
            if let j = draft.days[i].placeStops.firstIndex(where: { $0.id == stopId }) {
                var day = draft.days[i]
                var stop = day.placeStops[j]
                stop.placeTitle = title
                if let category { stop.placeCategory = category }
                if let coordinate {
                    stop.representativeLocation = PhotoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                day.placeStops[j] = stop
                draft.days[i] = day

                createdRecapStore.saveBlogDetail(draft)
                if let placeKey = stop.visitedTimeDigitized {
                    let categories = stop.placeCategory.map { [$0] }
                    Task { try? await APIManager.shared.updatePlaceName(visitedTimeDigitized: placeKey, placeName: title, categories: categories) }
                }
                // Generate place caption when user picks a name — only when on-device LLM is available.
                if LocalLLMStoryCaptionGenerator.isCapable {
                    let capturedDayId = day.id
                    Task { @MainActor in await generatePlaceCaption(dayId: capturedDayId, stopId: stopId) }
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

    /// Overall place story (quick summary from photo captions); shown above/below place and time.
    private func bindingForOverallStory(dayId: UUID, stopId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }) else { return "" }
                return stop.overallStory ?? ""
            },
            set: { newValue in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                var day = draft.days[dayIdx]
                var stop = day.placeStops[stopIdx]
                stop.overallStory = newValue.isEmpty ? nil : newValue
                day.placeStops[stopIdx] = stop
                draft.days[dayIdx] = day
            }
        )
    }

    private func bindingForDayCaption(dayId: UUID) -> Binding<String> {
        Binding(
            get: {
                draft.days.first(where: { $0.id == dayId })?.dayCaption ?? ""
            },
            set: { newValue in
                guard let idx = draft.days.firstIndex(where: { $0.id == dayId }) else { return }
                draft.days[idx].dayCaption = newValue.isEmpty ? nil : newValue
            }
        )
    }

    @ViewBuilder
    private func dayCaptionRow(day: RecapBlogDay) -> some View {
        let captionBinding = bindingForDayCaption(dayId: day.id)
        let isGenerating = isGeneratingDayCaptionForDayId == day.id
        if isEditMode {
            HStack(alignment: .top, spacing: 8) {
                // Tappable display — opens DayCaptionEditSheet
                Button {
                    dayCaptionEditItem = DayCaptionEditItem(
                        dayId: day.id,
                        dayLabel: "Day \(day.dayIndex) · \(day.shortDateText)"
                    )
                } label: {
                    let trimmed = captionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(trimmed.isEmpty ? "Describe your day in a sentence…" : trimmed)
                        .font(.subheadline)
                        .foregroundColor(trimmed.isEmpty ? .secondary.opacity(0.9) : .white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(white: 0.1))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    guard !isGenerating else { return }
                    isGeneratingDayCaptionForDayId = day.id
                    Task {
                        let text = await StoryCaptionService.shared.generateDaySummary(day: day)
                        await MainActor.run {
                            guard let idx = draft.days.firstIndex(where: { $0.id == day.id }) else { return }
                            draft.days[idx].dayCaption = text.isEmpty ? nil : text
                            isGeneratingDayCaptionForDayId = nil
                            createdRecapStore.saveBlogDetail(draft)
                        }
                    }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .disabled(isGenerating)
                .padding(.top, 12)
            }
            .padding(.bottom, 4)
        } else if !(day.dayCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(day.dayCaption!)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
        }
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

    // MARK: - AI Caption Tracking

    /// Mark a photo caption as manually typed by the user (hides AI wand, disables auto-cascade for this photo).
    private func markPhotoCaptionManual(dayId: UUID, stopId: UUID, photoId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
              let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
        draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = true
    }

    /// Mark a photo caption as AI-generated (shows AI wand, allows auto-cascade for this photo).
    private func markPhotoCaptionAI(dayId: UUID, stopId: UUID, photoId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
              let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
        draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = false
    }

    /// Mark the overall story as manually typed (disables AI auto-cascade for this place).
    private func markOverallStoryManual(dayId: UUID, stopId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual = true
    }

    /// Mark the overall story as AI-generated (re-enables auto-cascade for this place).
    private func markOverallStoryAI(dayId: UUID, stopId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual = false
    }

    /// Regenerates the overall place story from current photo captions, unless the user has manually edited it.
    @MainActor
    private func cascadeOverallStory(dayId: UUID, stopId: UUID) async {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }
        let stop = draft.days[dayIdx].placeStops[stopIdx]
        let dayDate = draft.days[dayIdx].date
        let captions = stop.photos.filter(\.isIncluded).compactMap(\.caption).filter { !$0.isEmpty }
        let story = await StoryCaptionService.shared.generateOverallPlaceStory(stop: stop, dayDate: dayDate, photoCaptions: captions)
        guard draft.days.indices.contains(dayIdx),
              draft.days[dayIdx].placeStops.indices.contains(stopIdx),
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }
        draft.days[dayIdx].placeStops[stopIdx].overallStory = story
    }

    // MARK: - Place Caption on Name Pick

    /// Generates a place story caption when the user picks a place name.
    /// Only runs when the on-device LLM is available and the user hasn't manually written a caption.
    @MainActor
    private func generatePlaceCaption(dayId: UUID, stopId: UUID) async {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }
        let stop = draft.days[dayIdx].placeStops[stopIdx]
        let dayDate = draft.days[dayIdx].date
        generatingCaptionStopId = stopId
        let story = await StoryCaptionService.shared.generatePlaceStory(stop: stop, dayDate: dayDate)
        generatingCaptionStopId = nil
        guard draft.days.indices.contains(dayIdx),
              draft.days[dayIdx].placeStops.indices.contains(stopIdx),
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }
        draft.days[dayIdx].placeStops[stopIdx].overallStory = story
        createdRecapStore.saveBlogDetail(draft)
    }

    // MARK: - AI Auto-Fill (Case 1: first blog creation, and when new photos are added)

    /// Auto-generates photo captions and overall stories for all stops in the draft.
    /// Only runs on photos that are included, have no caption, and are not manually edited.
    @MainActor
    private func autoFillCaptionsAndStories() async {
        for dayIdx in draft.days.indices {
            guard draft.days.indices.contains(dayIdx) else { break }
            for stopIdx in draft.days[dayIdx].placeStops.indices {
                guard draft.days.indices.contains(dayIdx),
                      draft.days[dayIdx].placeStops.indices.contains(stopIdx) else { break }
                await autoFillCaptionsForStopAt(dayIdx: dayIdx, stopIdx: stopIdx)
            }
        }
    }

    /// Auto-generates photo captions (and overall story) for a single stop identified by dayId/stopId.
    /// Used after ManagePhotos to handle newly included photos.
    @MainActor
    private func autoFillCaptionsForStop(dayId: UUID, stopId: UUID) async {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        await autoFillCaptionsForStopAt(dayIdx: dayIdx, stopIdx: stopIdx)
    }

    /// Core auto-fill logic for a stop at given indices. Generates captions for eligible photos then cascades overall story.
    @MainActor
    private func autoFillCaptionsForStopAt(dayIdx: Int, stopIdx: Int) async {
        guard draft.days.indices.contains(dayIdx),
              draft.days[dayIdx].placeStops.indices.contains(stopIdx) else { return }

        var captionsGenerated = false
        let stop = draft.days[dayIdx].placeStops[stopIdx]

        for photoIdx in stop.photos.indices {
            let photo = stop.photos[photoIdx]
            guard photo.isIncluded,
                  !photo.captionIsManual,
                  photo.caption == nil || photo.caption!.isEmpty else { continue }

            let caption = await StoryCaptionService.shared.generateCaption(
                photo: photo,
                placeName: stop.placeTitle,
                placeSubtitle: stop.placeSubtitle
            )

            guard draft.days.indices.contains(dayIdx),
                  draft.days[dayIdx].placeStops.indices.contains(stopIdx),
                  draft.days[dayIdx].placeStops[stopIdx].photos.indices.contains(photoIdx) else { continue }
            draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].caption = caption
            draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].captionIsManual = false
            captionsGenerated = true
        }

        // After generating photo captions, cascade to overall story (if not manually edited).
        guard draft.days.indices.contains(dayIdx),
              draft.days[dayIdx].placeStops.indices.contains(stopIdx),
              captionsGenerated || draft.days[dayIdx].placeStops[stopIdx].overallStory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }

        let updatedStop = draft.days[dayIdx].placeStops[stopIdx]
        let dayDate = draft.days[dayIdx].date
        let captions = updatedStop.photos.filter(\.isIncluded).compactMap(\.caption).filter { !$0.isEmpty }
        let story = await StoryCaptionService.shared.generateOverallPlaceStory(
            stop: updatedStop, dayDate: dayDate, photoCaptions: captions)

        guard draft.days.indices.contains(dayIdx),
              draft.days[dayIdx].placeStops.indices.contains(stopIdx),
              !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { return }
        draft.days[dayIdx].placeStops[stopIdx].overallStory = story
    }

    /// Generates overall stories for any stops that have none and haven't been manually edited.
    /// Called when loading a saved blog so AI stories always appear even on older saved drafts.
    @MainActor
    private func autoFillMissingOverallStories() async {
        for dayIdx in draft.days.indices {
            guard draft.days.indices.contains(dayIdx) else { break }
            for stopIdx in draft.days[dayIdx].placeStops.indices {
                guard draft.days.indices.contains(dayIdx),
                      draft.days[dayIdx].placeStops.indices.contains(stopIdx) else { break }
                let stop = draft.days[dayIdx].placeStops[stopIdx]
                guard !stop.overallStoryIsManual,
                      stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { continue }
                let dayDate = draft.days[dayIdx].date
                let captions = stop.photos.filter(\.isIncluded).compactMap(\.caption).filter { !$0.isEmpty }
                let story = await StoryCaptionService.shared.generateOverallPlaceStory(stop: stop, dayDate: dayDate, photoCaptions: captions)
                guard draft.days.indices.contains(dayIdx),
                      draft.days[dayIdx].placeStops.indices.contains(stopIdx),
                      !draft.days[dayIdx].placeStops[stopIdx].overallStoryIsManual else { continue }
                draft.days[dayIdx].placeStops[stopIdx].overallStory = story
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
        // If the blog has been saved before, start in View Mode (unless forced into edit).
        if let existing = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }), existing.lastEditedAt != nil {
            isEditMode = forceEditMode
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
        } else if isEditMode {
            return "Edit Mode"
        } else {
            // Empty — the .principal toolbar item handles the title in read-only mode
            return ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                print("🔙 Back button tapped — isEditMode: \(isEditMode)")
                if isEditMode {
                    let isFirstCreation = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil
                    print("🔙 isFirstCreation: \(isFirstCreation)")

                    if isFirstCreation {
                        print("🔙 Setting showNewBlogExitConfirmation = true")
                        showSaveTipAlert = false
                        DispatchQueue.main.async {
                            let stillUnsaved = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil
                            guard stillUnsaved else { return }
                            showNewBlogExitConfirmation = true
                        }
                    } else {
                        if draftSnapshot != nil && draft == draftSnapshot {
                            // No changes made, leave uninterrupted
                            print("🔙 No changes, returning to read-only")
                            isEditMode = false
                        } else {
                            // Changes were made
                            print("🔙 Changes detected, showing unsaved alert")
                            showUnsavedChangesAlert = true
                        }
                    }
                } else {
                    print("🔙 View mode, dismissing")
                    performDismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
        }
        ToolbarItem(placement: .principal) {
            Text(draft.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .opacity(!isEditMode && showNavBarTitle ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showNavBarTitle)
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
            } else if !isExportingPDF {
                HStack(spacing: 16) {
                    Button {
                        if blogIsInCloud {
                            showRemoveFromCloudAlert = true
                        } else {
                            handleCloudUploadTap()
                        }
                    } label: {
                        Image(systemName: blogIsInCloud ? "checkmark.icloud.fill" : "icloud.and.arrow.up")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundColor(blogIsInCloud ? .green : .white)
                    }
                    .buttonStyle(.plain)
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



    @ViewBuilder
    private func cloudOnboardingModalContent() -> some View {
        VStack(spacing: 0) {
            // Scrollable content area
            VStack(spacing: 20) {
                Image(systemName: "cloud.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Your Blog is in the Cloud!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("Your blogs can now be uploaded to the cloud for web editing and sharing.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    cloudFeatureRow(icon: "pencil.and.outline", text: "Edit on any device via web")
                    cloudFeatureRow(icon: "arrow.clockwise.icloud", text: "Automatic cloud backup")
                    cloudFeatureRow(icon: "link", text: "Share your blog via a web link")
                }
                .padding(16)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)

                Text("Cloud access is currently available through early access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Fixed bottom buttons
            VStack(spacing: 12) {
                Button {
                    sendEmailToSelf()
                    showCloudOnboardingModal = false
                } label: {
                    Text("Send Link via Email")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                Button("Done") {
                    showCloudOnboardingModal = false
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .preferredColorScheme(.dark)
    }

    private func cloudFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func earlyAccessModalContent(isOnList: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "cloud.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
                    .padding(.top, 8)

                if isOnList {
                    VStack(spacing: 8) {
                        Text("You're on the List!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        Text("We'll notify you when cloud publishing becomes available. Uploading your blogs to the cloud lets you edit and share them from any device.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Early Access Feature")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        Text("Cloud publishing is a limited early access. \(authService.isSignedIn ? "Join the waitlist!" : "Create an account to join the waitlist!")")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                if isOnList {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Signed Up!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(12)
                } else {
                    Button {
                        if authService.isSignedIn {
                            Task {
                                await EarlyAccessManager.shared.registerWaitlist()
                                await MainActor.run {
                                    hasJoinedEarlyAccess = true
                                    earlyAccessShowOnListConfirm = true
                                }
                            }
                        } else {
                            pendingEarlyAccessAfterAuth = true
                            showAuth = true
                        }
                    } label: {
                        Text("Join Early Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }

                Button {
                    earlyAccessSheetPresented = false
                    if authService.isSignedIn {
                        exportBlogToPDF()
                    } else {
                        pendingExportAfterAuth = true
                        showAuth = true
                    }
                } label: {
                    Text("Export as PDF Instead")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .preferredColorScheme(.dark)
    }

    private func handleCloudUploadTap() {
        guard authService.isSignedIn else {
            pendingCloudUploadAfterAuth = true
            showAuth = true
            return
        }
        let cachedLevel = authService.currentUser?.userLevel ?? .normal
        if cachedLevel.isPremiumOrAbove {
            uploadBlogPhotos()
        } else {
            // Refresh from server in case the user recently upgraded
            Task {
                let latestLevel = await authService.refreshUserLevel() ?? .normal
                if latestLevel.isPremiumOrAbove {
                    EarlyAccessManager.shared.syncFromUserLevel(latestLevel)
                    uploadBlogPhotos()
                } else {
                    let onList = hasJoinedEarlyAccess || EarlyAccessManager.shared.hasRegistered
                    earlyAccessShowOnListConfirm = onList
                    earlyAccessSheetPresented = true
                }
            }
        }
    }

    private func exportBlogToPDF() {
        isExportingPDF = true
        Task {
            do {
                let url = try await PDFExportService.generatePDF(from: draft)
                await MainActor.run {
                    self.pdfExportURL = url
                    self.showPDFPreview = true
                    // Keep the exporting overlay (animation + percentage) visible until the preview sheet has had time to present, then hide it so the transition feels smooth.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 550_000_000) // ~0.55s for sheet to be ready
                        self.isExportingPDF = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExportingPDF = false
                    uploadErrorMessage = "PDF export failed: \(error.localizedDescription)"
                    showUploadErrorAlert = true
                }
            }
        }
    }

    private func sendEmailToSelf() {
        guard let key = newlyUploadedBlogKey,
              let user = AuthService.shared.currentUser,
              let username = user.username,
              let url = SecureShareToken.shareURL(username: username, blogKey: key) else { return }
        
        let subject = "My First Blog on Bloggo!".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "Here is the link to my first blog:\n\(url.absoluteString)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let mailtoUrl = URL(string: "mailto:?subject=\(subject)&body=\(body)") {
            UIApplication.shared.open(mailtoUrl)
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

                // Suppress Undo: If the photo being added back matches the one in our pending undo action, clear it.
                if case .deletePhoto(_, _, let undoPhoto, _) = lastUndoAction, undoPhoto.id == photo.id {
                    withAnimation {
                        lastUndoAction = nil
                        showUndoOverlay = false
                    }
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

    private var isDraft: Bool {
        guard let blog = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) else {
            return true // If not found in recents, it's in the process of being created (draft)
        }
        return blog.cloudState == .localOnly
    }

    private var currentBlogKey: Int? {
        createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.blogKey
    }

    // MARK: - Split Logic

    /// Splits a blog that hasn't been saved yet.
    /// - Parameters:
    ///   - afterDayIndex: The index of the day to split after.
    ///   - keepPart: 1 to keep the first part (Days 1...afterDayIndex+1), 2 to keep the second part.
    private func splitUnsavedBlog(afterDayIndex: Int, keepPart: Int) {
        // We do a similar split to CreatedRecapBlogStore.splitBlog, but we just want to update `draft`
        // and optionally save the part we keep, discarding the rest since it was never saved anyway.
        // Actually, the user asked "we ask the user which blog they would like to create". 
        // We will just keep the chosen part in the current view and discard the other part.
        
        var part1Days = Array(draft.days[0...afterDayIndex])
        var part2Days = Array(draft.days[(afterDayIndex + 1)...])
        
        for i in part1Days.indices { part1Days[i].dayIndex = i + 1 }
        for i in part2Days.indices { part2Days[i].dayIndex = i + 1 }

        let baseTitle = draft.title
            .replacingOccurrences(of: " \\(Part \\d+ of \\d+\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: " \\(Episode \\d+ of \\d+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if keepPart == 1 {
            draft.title = baseTitle
            draft.days = part1Days
            
            // Filter removed stops
            let part1DayIds = Set(part1Days.map(\.id))
            draft.removedPlaceStops = draft.removedPlaceStops.filter { part1DayIds.contains($0.dayId) }
            
        } else {
            draft.title = baseTitle
            draft.days = part2Days
            
            // Adjust Cover Photo if needed
            let part2CoverIdentifier = part2Days.first?.placeStops.first?.photos.first(where: \.isIncluded)?.localIdentifier
            draft.selectedCoverPhotoIdentifier = part2CoverIdentifier
            
            // Filter removed stops
            let part2DayIds = Set(part2Days.map(\.id))
            draft.removedPlaceStops = draft.removedPlaceStops.filter { part2DayIds.contains($0.dayId) }
        }
        
        // Auto-save the new draft state (preserve draft status so back button shows the correct "Save or Exit?" alert)
        createdRecapStore.saveBlogDetail(draft, asDraft: true)
        // Keep snapshot in sync so we don't get a false "Unsaved Changes?" prompt
        draftSnapshot = draft
        // Always land on Day 1 of whichever part was kept
        selectedDayIndex = 0
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Preserve the discarded part in the Trips list
        createdRecapStore.splitUnsavedTrip(tripId: blogId, afterDayIndex: afterDayIndex, keepPart: keepPart)
    }

    /// Splits a blog that has already been saved/created (Edit Mode).
    private func splitSavedBlog(afterDayIndex: Int) {
        // We just call the store's split functionality on the current blogId and afterDayIndex.
        createdRecapStore.splitBlog(blogId: blogId, afterDayIndex: afterDayIndex)
        
        // Since the current view is for `blogId`, which is now Part 1, we should refresh `draft`
        if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
            draft = updated
            if selectedDayIndex >= draft.days.count {
                selectedDayIndex = max(0, draft.days.count - 1)
            }
            
            // Show the Undo Banner
            withAnimation {
                showSplitUndoBanner = true
            }
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private func uploadBlogPhotos() {
        guard !isUploading else { return }
        guard authService.isSignedIn else { return }

        // 🚨 Free Tier Guardrails
        if EntitlementManager.shared.isFreeTier {
            // 1. Storage Limit Check
            let currentUsage = AuthService.shared.currentUser?.storageUsedBytes ?? 0
            if currentUsage >= EntitlementManager.freeTierStorageLimit {
                uploadErrorMessage = "Cloud storage limit reached.\nRemove a published blog to continue."
                showUploadErrorAlert = true
                return
            }
            
            // 2. Active Cloud Blogs Check
            if let maxCloud = EntitlementManager.shared.activeCloudBlogLimit {
                let currentCloudCount = createdRecapStore.visibleRecents.filter { $0.cloudState != .localOnly }.count
                let isThisBlogAlreadyInCloud = (createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == blogId })?.cloudState ?? .localOnly) != .localOnly
                
                if !isThisBlogAlreadyInCloud && currentCloudCount >= maxCloud {
                    uploadErrorMessage = "Cloud storage limit reached.\nRemove a published blog to continue."
                    showUploadErrorAlert = true
                    return
                }
            }
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

        uploadTask = Task {
            var failCount = 0
            for item in photosToUpload {
                if Task.isCancelled { break }
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

            if Task.isCancelled {
                // Return without doing any further cloud actions if cancelled
                return
            }

            // Save updated draft with cloud URLs
            createdRecapStore.saveBlogDetail(draft)

            // Publish blog to server; on success, show the first-blog modal.
            // The modal fires *after* the fullScreenCover has fully dismissed
            // to avoid iOS silently dropping a sheet presented during a cover's
            // dismiss animation.
            if failCount == 0 {
                let snapshot = draft
                let currentBlogId = blogId
                let isFirstBlog = !hasUploadedFirstBlog
                Task {
                    if let blogKey = await APIManager.shared.publishBlog(detail: snapshot) {
                        await MainActor.run {
                            createdRecapStore.setBlogKey(blogId: currentBlogId, blogKey: blogKey)
                        }
                        if isFirstBlog {
                            // Wait for the fullScreenCover dismiss animation to finish
                            // before presenting the sheet (iOS drops sheets presented
                            // while a fullScreenCover is mid-dismissal).
                            try? await Task.sleep(nanoseconds: 700_000_000) // 0.7 s
                            await MainActor.run {
                                if !hasUploadedFirstBlog {
                                    hasUploadedFirstBlog = true
                                    newlyUploadedBlogKey = blogKey
                                    showCloudOnboardingModal = true
                                }
                            }
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

    private func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        showUploadingFullScreen = false
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
    @Binding var draftSnapshot: RecapBlogDetail?
    @Binding var cancellables: Set<AnyCancellable>
    @Binding var isKeyboardVisible: Bool
    @Binding var isEditMode: Bool
    @Binding var draft: RecapBlogDetail
    var saveDraft: () -> Void
    var loadDraftIfNeeded: () -> Void
    var checkFirstTimeTip: () -> Void
    var createdRecapStore: CreatedRecapBlogStore
    var dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .alert("Welcome to Your Blog!", isPresented: $showSaveTipAlert) {
                        Button("Don't Show Again") { showFirstTimeSaveTip = false }
                        Button("Okay", role: .cancel) { }
                    } message: {
                        Text("Tap Save when you're done editing to keep your changes and unlock your map routes.")
                    }
            )
            .background(
                Color.clear
                    .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
                        Button("Yes") {
                            saveDraft()
                            isEditMode = false
                        }
                        Button("No", role: .destructive) {
                            if let snapshot = draftSnapshot {
                                draft = snapshot
                            }
                            isEditMode = false
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Do you want to save your changes?")
                    }
            )
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

// MARK: - Processing Day Popup

/// Center-screen modal shown when a user taps a day that is still being built.
struct ProcessingDayPopup: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Blurred scrim — tap anywhere to dismiss. Uses material blur so the
            // backdrop dims naturally without a hard black rectangle edge.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Frosted card
            VStack(spacing: 0) {
                // Spinner icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 64, height: 64)
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(Color.blue)
                }
                .padding(.top, 28)
                .padding(.bottom, 18)

                // Title
                Text("Almost There!")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Body
                Text("We're still drafting this day. It will be ready in just a moment!")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.top, 24)

                // CTA
                Button {
                    onDismiss()
                } label: {
                    Text("Okay")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - New Moments Review Sheet

private struct NewMomentsReviewSheet: View {
    let photos: [MockPhoto]
    let blogTitle: String
    var onAdd: ([MockPhoto]) -> Void
    var onLater: () -> Void

    @State private var selectedIds: Set<UUID> = []
    @State private var dragOffset: CGFloat = 0

    private var allSelected: Bool { selectedIds.count == photos.count }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Sheet content
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("\(photos.count) New Photo\(photos.count == 1 ? "" : "s")")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Select photos to add to blog")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Select All row
                HStack {
                    Spacer()
                    Button {
                        if allSelected {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(photos.map(\.id))
                        }
                    } label: {
                        Text(allSelected ? "Deselect All" : "Select All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(allSelected ? .red : .green)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Photo grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            let isSelected = selectedIds.contains(photo.id)
                            Button {
                                if isSelected {
                                    selectedIds.remove(photo.id)
                                } else {
                                    selectedIds.insert(photo.id)
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if let lid = photo.localIdentifier {
                                            AssetPhotoView(assetIdentifier: lid, cornerRadius: 0)
                                                .aspectRatio(3/4, contentMode: .fill)
                                                .clipped()
                                        } else {
                                            MockPhotoView(seed: photo.id.hashValue, cornerRadius: 0)
                                                .aspectRatio(3/4, contentMode: .fill)
                                        }
                                    }
                                    .overlay(
                                        Color.black.opacity(isSelected ? 0.4 : 0)
                                    )

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(.white, .green)
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Action buttons pinned at bottom
                VStack(spacing: 12) {
                    Button {
                        let selected = photos.filter { selectedIds.contains($0.id) }
                        onAdd(selected)
                    } label: {
                        Text(selectedIds.isEmpty ? "Add to Blog" : "Add \(selectedIds.count) Photo\(selectedIds.count == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedIds.isEmpty ? Color.green.opacity(0.4) : Color.green)
                            .cornerRadius(14)
                    }
                    .disabled(selectedIds.isEmpty)

                    Button {
                        onLater()
                    } label: {
                        Text("Later")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            onLater()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            selectedIds = Set(photos.map(\.id))
        }
    }
}

#Preview {
    NavigationStack {
        RecapBlogPageView(blogId: UUID(), initialTrip: nil)
            .environmentObject(CreatedRecapBlogStore.shared)
    }
}
