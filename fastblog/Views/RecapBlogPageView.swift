//
//  RecapBlogPageView.swift
//  Capper
//

import SwiftUI
import MapKit
import Combine
import UIKit
import Photos

private struct TitleMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// Measured height of the hero title row (view or edit) so we can vertically center the title on the cover image.
private struct CoverHeroTitleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        value = max(value, next)
    }
}

/// Global-frame anchor for the Blog Settings (gear) toolbar control — used by the first-save spotlight.
private struct BlogSettingsGearFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next.width > 0.5, next.height > 0.5 else { return }
        value = next
    }
}

// MARK: - Caption Edit Sheet Item Types

/// Carries the day identity + header lines for the full-screen day caption editor overlay.
struct DayCaptionEditItem: Identifiable {
    let dayId: UUID
    let dayNumber: Int
    let dateLine: String
    var id: UUID { dayId }
}

/// Carries the stop identity for the place caption editor (fade overlay).
struct PlaceCaptionEditItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    var id: UUID { stopId }
}

/// Carries the stop + photo identity for the photo caption editor (fade overlay).
struct PhotoCaptionEditItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    let photoId: UUID
    var id: UUID { photoId }
}

/// Sheet target for changing a stop’s POI category (`PlaceStop.placeCategory`).
private struct PlaceCategoryPickerTarget: Identifiable {
    let id: UUID
}

struct RecapBlogPageView: View {
    /// Stable `ScrollViewReader` targets (strings can be unreliable across `TabView` layout passes).
    private enum RecapBlogScrollAnchor: Hashable {
        case pageTop
        case mapForDay(UUID)
    }

    private enum ShareYourBlogSheetPhase: Equatable {
        case menu
        case guestWebLinkCloudBackup
        case guestBloggoQR
    }

    /// Crossfade + detent animation when switching between the share menu and guest tooltips.
    private let shareYourBlogSheetPhaseTransitionDuration: Double = 0.52

    let blogId: UUID
    let initialTrip: TripDraft?
    /// When set (e.g. from new-moments "Add to blog"), open scrolled to this day (0-based).
    var initialDayIndex: Int? = nil
    /// When set (e.g. from Places Visited "View blog"), select that day and scroll to this place row.
    var initialScrollToStopId: UUID? = nil
    let forceEditMode: Bool
    /// When true (e.g. My Blogs country kebab "Share Blog"), present the Share Your Blog sheet after load.
    let forcePresentShareYourBlogSheet: Bool
    /// When set (e.g. when presented as overlay), called instead of environment dismiss to close the blog.
    var onRequestDismiss: (() -> Void)? = nil
    /// When true (e.g. opening a day from Split Blog manage flow), skip the photo-grouping tip on appear — day picker stays visible so users can browse all days.
    var suppressPhotoGroupingTipOnAppear: Bool = false

    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @EnvironmentObject private var nearbyShare: TripNearbyShareSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var recapScreenBackground: Color {
        colorScheme == .dark ? .black : Color(uiColor: .systemGroupedBackground)
    }

    private var recapChromeForeground: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var recapSecondaryOnChrome: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .secondary
    }

    private var recapCardBackground: Color {
        colorScheme == .dark ? Color(white: 0.14) : Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var recapNarrativeCardBackground: Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(uiColor: .tertiarySystemGroupedBackground)
    }

    private var recapDayPillIdleBackground: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(uiColor: .systemGray5)
    }

    private var recapHairline: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var recapMapExpandBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.45)
    }

    @State private var draft: RecapBlogDetail
    @State private var selectedDayIndex: Int = 0  // 0 = Day 1, 1 = Day 2, ...
    /// Hides the scroll view while Day 2+ jumps to the map so the cover hero never flashes on screen.
    @State private var recapDayScrollCoverMaskActive = false
    /// iOS 17+ horizontal paging ScrollView position. Kept in sync with `selectedDayIndex`.
    @State private var dayPagerScrollIndex: Int? = 0
    /// While true, child views that pan horizontally (e.g. maps) temporarily stop hit-testing
    /// so the day pager can complete a clean snap.
    @State private var isDayPagerHorizontalDragActive: Bool = false
    /// Deterministic day navigation via swipe (no partial offsets).
    @State private var daySwipeTransitionDirection: Int = 0 // -1 = moved to previous, +1 = moved to next
    /// True only for swipe-driven day changes. Pill taps / programmatic changes render immediately.
    @State private var shouldAnimateDayChange: Bool = false
    /// Require swipes to begin at the screen edge to avoid fighting inner horizontal carousels.
    private let daySwipeEdgeInset: CGFloat = 80
    @State private var overflowStop: OverflowItem?
    @State private var transportModePickerItem: OverflowItem?
    @State private var mergeSelectionItem: MergeSelectionItem?
    @State private var showEditNameForStop: PlaceStop?
    @State private var placeCategoryPickerTarget: PlaceCategoryPickerTarget?
    @State private var showManagePhotosForStop: ManagePhotosItem?
    /// The stop currently having its place caption generated (triggered by place name pick).
    @State private var generatingCaptionStopId: UUID?
    /// The stop currently having its place narrative generated via "Tell Story".
    @State private var generatingNarrativeStopId: UUID?
    /// The day currently having its day narrative generated via "Tell Story".
    @State private var generatingNarrativeDayId: UUID?
    /// Whether the trip-level narrative is currently being AI-generated.
    @State private var isGeneratingTripNarrative = false
    /// Whether the trip narrative card is expanded (shows full text vs. 4-line preview).
    @State private var tripNarrativeExpanded = false
    /// Day IDs whose caption is expanded beyond the 4-line preview.
    @State private var expandedDayCaptionIds: Set<UUID> = []
    /// Snapshot taken when ManagePhotosView opens, used to diff on dismiss for targeted cloud sync.
    @State private var managePhotosEditInfo: ManagePhotosEditInfo?
    /// After popping Manage Photos, `dayPageScrollView.onAppear` runs again; skip the default scroll-to-map/top so the user's offset is preserved.
    @State private var skipDefaultDayPageScrollOnNextAppear = false
    /// Presents the system photo picker while managing a place's photo group.
    @State private var showLibraryImportForManageStop = false
    /// Presents the Bloggo Gallery picker while managing a place's photo group.
    @State private var showBloggoGalleryImportForManageStop = false
    @State private var isEditMode = true
    @State private var showBlogSettings = false
    @State private var showShareSheet = false
    @State private var fullScreenMapDay: RecapBlogDay?
    @State private var fullScreenMapFocusedPlaceId: UUID?
    @State private var showTitleChange = false
    @State private var placePhotoModalItem: PlacePhotoModalItem?
    /// While the photo overlay is still animating off, show the recap navigation bar so it tracks the dismiss instead of popping in after teardown.
    @State private var revealRecapNavigationDuringPhotoDismiss = false
    @State private var showUnsavedChangesAlert = false
    @State private var showCoverPhotoPicker = false
    /// The cover photo asset identifier captured just before the cover picker opens, used to detect changes on dismiss.
    @State private var coverPhotoIdentifierBeforeEdit: String? = nil
    /// Cycling photo shown while cover selection scoring is still in progress.
    @State private var cyclingCoverPhotoId: String? = nil
    /// Stabilizes cover hero sizing so transient share/QR layout changes don't stretch the cover.
    @State private var coverHeroBaseScreenHeight: CGFloat? = nil
    /// Last measured height of the cover-hero title (view or edit) for vertical centering on the photo.
    @State private var coverHeroMeasuredTitleHeight: CGFloat = 0
    /// Prevents transient hero metadata overlap when switching edit → view after Save.
    @State private var showHeroMetadata = true
    /// Snapshot of the draft when edit mode was entered; compared to detect changes.
    @State private var draftSnapshot: RecapBlogDetail?
    /// Independent of the legacy "tap Save" tip — many users dismissed that key; split/merge onboarding uses its own flag.
    @AppStorage("bloggo.hasSeenPhotoGroupingTip") private var hasSeenPhotoGroupingTip = false
    @AppStorage("hasUploadedFirstBlog") private var hasUploadedFirstBlog = false
    @AppStorage(WeatherTemperatureUnit.storageKey) private var weatherTemperatureUnitRaw: String = WeatherTemperatureUnit.fahrenheit.rawValue
    @AppStorage(DistanceUnit.storageKey) private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    @AppStorage("selectedBlogFont") private var selectedBlogFont: String = "Serif"
    @State private var showCloudOnboardingModal = false
    @State private var newlyUploadedBlogKey: Int? = nil
    @State private var showSaveTipAlert = false
    @State private var showFirstSaveBanner = false
    /// One-time coachmark after the very first toolbar Save, highlighting Blog Settings (gear).
    @AppStorage("bloggo.hasSeenFirstSaveBlogSettingsCoachmark") private var hasSeenFirstSaveBlogSettingsCoachmark = false
    @State private var showFirstSaveBlogSettingsSpotlight = false
    @State private var blogSettingsGearFrameGlobal: CGRect = .zero
    @State private var showNewBlogExitConfirmation = false
    /// Overlay presentation (e.g. ContentView blog layer from Places visited): back with unsaved edits.
    @State private var showOverlayDraftExitConfirmation = false
    @State private var showUploadPromptAlert = false
    @State private var showNavBarTitle = false
    @State private var hasFinishedInitialLoad = false
    /// Education for account users when blog photos only exist on another device.
    @State private var showMissingPhotosTooltip = false
    @State private var sessionDismissedMissingPhotosTooltip = false
    @State private var missingPhotosTooltipDebounceTask: Task<Void, Never>?
    /// Debounced autosave for rapid photo include/exclude toggles (Manage Photos).
    /// Prevents losing selection state if the app is killed before leaving the screen.
    @State private var photoSelectionAutosaveTask: Task<Void, Never>?
    @StateObject private var blogReelAutoplay = BlogReelAutoplayCoordinator()

    // Undo State
    @State private var lastUndoAction: UndoAction?
    @State private var showUndoToast = false
    @State private var undoToastText = ""
    @State private var undoToastTask: Task<Void, Never>?
    @State private var isKeyboardVisible = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visitedDayIndices: Set<Int> = [0]
    @State private var cachedDayPagerThumbnailAssetIds: [String] = []

    // Cloud Upload State
    @State private var isUploading = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadProgress: (current: Int, total: Int) = (0, 0)
    @State private var showUploadingFullScreen = false
    @State private var uploadingViewTitle = "Uploading Your Blog!"
    @State private var uploadingViewProgressDetail: String? = nil
    /// Optional rotating subtitles for `UploadingBlogView`; nil uses default cloud-oriented copy.
    @State private var uploadingViewStepCycleLabels: [String]? = nil
    @State private var uploadingViewAllowsCancel = true
    @State private var showUploadSuccessBanner = false
    @State private var showUploadErrorAlert = false
    @State private var uploadErrorMessage = ""
    @State private var showAuth = false
    @State private var showGuestSecondSaveLimitModal = false
    @State private var pendingSecondSaveCommitAfterAuth = false
    @State private var pendingEarlyAccessAfterAuth = false
    @State private var pendingCloudUploadAfterAuth = false
    /// Pull-up modal shown when a guest taps the cloud upload button.
    @State private var showGuestCloudUploadModal = false
    /// Single pull-up modal: shown when non-nil; content is "You're on the list" when true, else "Join Early Access" prompt.
    @State private var earlyAccessSheetPresented: Bool = false
    @State private var earlyAccessShowOnListConfirm: Bool = false
    @State private var weatherEditDayId: UUID? = nil
    @AppStorage("hasJoinedEarlyAccess") private var hasJoinedEarlyAccess = false
    @State private var isExportingPDF = false
    @State private var pdfExportURL: URL?
    @State private var showPDFPreview = false
    @State private var showPDFExportOptions = false
    @State private var showStoryMode = false
    @State private var showStoryModePDFOptions = false
    @State private var showShareYourBlogSheet = false
    /// Which screen is shown inside the “Share Your Blog” pull-up (menu vs guest prompts).
    @State private var shareYourBlogSheetPhase: ShareYourBlogSheetPhase = .menu
    @State private var shareSheetPresentationDetent: PresentationDetent = .height(492) // updated to shareMenuDetentHeight on appear
    @State private var showVideoExportOptions = false
    @State private var showSocialPostStudio = false
    @State private var blogVideoShareURL: URL? = nil
    @State private var showBlogVideoShareSheet = false
    @State private var showCloudSharingComingSoonAlert = false
    @State private var pendingWebLinkAfterAuth = false
    /// After guest signs in from the “Share with Bloggo” prompt, open the QR share overlay.
    @State private var pendingBloggoQRAfterAuth = false
    @State private var pendingWebLinkShareAfterUpload = false
    @State private var showBloggoQRSheet = false
    @State private var pendingBloggoQRSheetAfterShareDismiss = false
    @State private var storyShareTrigger = false
    @State private var storyContentReady = false
    @State private var storyChromeVisible = true
    /// Matches `StoryBookView` loading / PDF light-dark so the system status bar uses dark or light content.
    @State private var storyStatusBarColorScheme: ColorScheme = .dark
    @State private var pendingStoryOpen = false
    @AppStorage("pdfExportOptions") private var pdfExportOptionsData: Data = (try? JSONEncoder().encode(PDFExportOptions())) ?? Data()
    @State private var showProfileManagement = false
    @State private var showRestorePlaces = false
    /// Tracks whether AI auto-fill is running so we don't show the blog as empty during generation.
    @State private var isAutoFillingCaptions = false
    /// The day ID currently having its caption AI-generated (nil when idle).
    /// Day caption full-screen overlay trigger.
    @State private var dayCaptionEditItem: DayCaptionEditItem?
    /// Trip-level opening story (`tripNarrative`) full-screen overlay.
    @State private var showTripNarrativeEdit = false
    /// Place caption full-screen overlay trigger.
    @State private var placeCaptionEditItem: PlaceCaptionEditItem?
    /// Photo caption full-screen overlay trigger.
    @State private var photoCaptionEditItem: PhotoCaptionEditItem?
    /// Alert when user taps a day that is not yet processed (geocoding still in progress).
    @State private var showUnprocessedDayAlert = false
    /// Limited-access users: controls the \"Photo Library Access\" prompt sheet.
    @State private var showPhotoLibraryAccessPrompt = false
    
    // MARK: - New Moments
    @State private var newMomentPhotos: [MockPhoto] = []
    @State private var showNewMomentsReviewSheet = false
    /// Cached place-cluster count for `newMomentPhotos` — computed with the same algorithm as `NewMomentsReviewSheet` so the card label matches the sheet contents.
    @State private var newMomentsGroupCount: Int = 0
    @State private var isCheckingNewMoments = false
    @State private var hasCheckedNewMoments = false
    @State private var showNoNewMomentsAlert = false
    @State private var showRescanResultAlert = false
    @State private var rescanResultMessage = ""
    @State private var hasCheckedFirstTimeTip = false
    /// Avoids repeated auto-jumps when new library moments are detected.
    @State private var hasAutoScrolledToNewMomentsDay = false
    /// Persists which days to highlight until the user adds or dismisses the new-moments batch.
    @State private var highlightedNewMomentsDayIndices: Set<Int> = []
    /// Presents the in-app camera from an ongoing/current blog.
    @State private var showCameraCaptureFromRecap = false

    private static let newMomentsAccent = Color(red: 1.0, green: 0.45, blue: 0.25)

    // MARK: - Panorama
    @State private var showPanorama = false
    @State private var showCleanupFromGallery = false

    /// True if the user has saved this blog to the local device at least once (tap Save on recap page).
    /// We only show "X moments found" for blogs that have been saved; camera-originated trips that are still just trips use the timeline only.
    private var hasBlogBeenSavedToDevice: Bool {
        guard let r = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) else { return false }
        return r.hasCommittedRecapSave || r.lastEditedAt != nil
    }

    /// Number of unique places in new moments (for "N moments found").
    private var newMomentsPlaceCount: Int {
        Set(newMomentPhotos.map { $0.locationName ?? "Moment" }).count
    }

    /// 0-based day indices to highlight in the day filter and section header.
    private var newMomentsDayIndices: Set<Int> {
        highlightedNewMomentsDayIndices
    }

    /// Latest day index that has pending new moments (typical continuation-trip case).
    private var preferredNewMomentsDayIndex: Int? {
        draft.preferredDayIndexForNewMoments(
            from: newMomentPhotos,
            fallbackDayIndex: clampedInitialDayIndex ?? clampedOnTheGoDayIndex
        )
    }

    private var clampedInitialDayIndex: Int? {
        guard let idx = initialDayIndex, !draft.days.isEmpty else { return nil }
        return min(max(0, idx), draft.days.count - 1)
    }

    private var clampedOnTheGoDayIndex: Int? {
        guard OnTheGoTripStore.activeBlogId == blogId,
              OnTheGoTripStore.hasNewMoments,
              let idx = OnTheGoTripStore.newMomentsDayIndex,
              !draft.days.isEmpty else { return nil }
        return min(max(0, idx), draft.days.count - 1)
    }

    private func refreshHighlightedNewMomentsDays() {
        var indices = draft.dayIndicesForNewMomentPhotos(newMomentPhotos)
        if let idx = clampedInitialDayIndex {
            indices.insert(idx)
        }
        if indices.isEmpty, let idx = clampedOnTheGoDayIndex {
            indices.insert(idx)
        }
        if !indices.isEmpty {
            highlightedNewMomentsDayIndices = indices
        }
    }

    private func clearHighlightedNewMomentsDays() {
        highlightedNewMomentsDayIndices = []
    }

    private func recomputeNewMomentsGroupCount() {
        guard !newMomentPhotos.isEmpty else { newMomentsGroupCount = 0; return }
        let service = PlaceStopClusteringService()
        let inputs = newMomentPhotos.map { ClusterPhotoInput(id: $0.id, timestamp: $0.timestamp, location: $0.location) }
        newMomentsGroupCount = service.placeStops(from: inputs) { _ in "Moment" }.count
    }

    private func focusNewMomentsDayIfNeeded(animated: Bool = true, force: Bool = false) {
        // Only auto-scroll when there are actual new-moment photos in this session or an
        // explicit initialDayIndex was passed. Stale UserDefaults (hasNewMoments=true from a
        // previous scan that was never cleared) must not drive auto-scroll on its own —
        // that's what caused concluded trips to always open on the last day.
        guard !newMomentPhotos.isEmpty || clampedInitialDayIndex != nil else { return }
        // If the user already dismissed this batch via "Later", respect their reading
        // position — don't auto-scroll again on subsequent sessions.
        if !force, clampedInitialDayIndex == nil,
           let batchMax = newMomentPhotos.map(\.timestamp).max(),
           let dismissed = NewMomentsPullUpPresentationStore.dismissedBatchMaxTimestamp(for: blogId),
           batchMax <= dismissed { return }
        refreshHighlightedNewMomentsDays()
        guard !highlightedNewMomentsDayIndices.isEmpty else { return }
        guard force || !hasAutoScrolledToNewMomentsDay,
              initialScrollToStopId == nil,
              let idx = preferredNewMomentsDayIndex,
              draft.days.indices.contains(idx) else { return }
        hasAutoScrolledToNewMomentsDay = true
        shouldAnimateDayChange = animated
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedDayIndex = idx
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                selectedDayIndex = idx
            }
        }
    }

    private var pdfExportOptions: PDFExportOptions {
        (try? JSONDecoder().decode(PDFExportOptions.self, from: pdfExportOptionsData)) ?? PDFExportOptions()
    }

    /// Matches story book backdrop so the recap page never flashes the wrong color behind Story mode.
    private var storyPresentationUnderlayColor: Color {
        pdfExportOptions.colorStyle == .black ? Color.black : Color.white
    }

    /// Close / Export in Story Mode: must contrast with both the story backdrop and the inner gradient.
    private var storyChromeForegroundColor: Color {
        pdfExportOptions.colorStyle == .black ? Color.white : Color(white: 0.13)
    }

    private var storyChromeGlyphShadowColor: Color {
        pdfExportOptions.colorStyle == .black
            ? Color.black.opacity(0.55)
            : Color.white.opacity(0.92)
    }

    /// UIKit status bar content: dark glyphs on light story, light glyphs on dark story.
    private var storyUIKitStatusBarStyle: UIStatusBarStyle {
        storyStatusBarColorScheme == .light ? .darkContent : .lightContent
    }

    // MARK: - Split Blog Properties
    @State private var showSplitActionSheet = false
    @State private var dayIndexToSplit: Int?
    @State private var unsavedSplitPromptIndex: Int?
    @State private var showSplitUndoBanner = false
    @State private var splitUndoBannerDismissTask: Task<Void, Never>?
    @State private var showContinueEditingAfterSplit = false
    @State private var savedSplitPartPreviews: (part1: ContinueEditingAfterSplitPartInfo, part2: ContinueEditingAfterSplitPartInfo)?
    @State private var didPickSavedSplitEditorPart = false

    // MARK: - Place Stop Merge / Split
    private struct SplitPlaceStopItem: Identifiable {
        let dayId: UUID
        let stop: PlaceStop
        var id: UUID { stop.id }
    }
    @State private var splitPlaceStopItem: SplitPlaceStopItem?

    private enum UndoAction {
        /// `dayBeforeRemoval` is the full day (including the removed stop) before hide; `dayIndexInDraft` is its index in `draft.days` at that moment — needed when removing the last stop deletes the whole day.
        /// `coverPhotoIdentifierBeforeRemoval` is ``draft.selectedCoverPhotoIdentifier`` before hide; restored on undo so multi-day blogs keep the same cover after restoring a removed day.
        case deletePlace(
            dayBeforeRemoval: RecapBlogDay,
            removedStopIndex: Int,
            dayIndexInDraft: Int,
            coverPhotoIdentifierBeforeRemoval: String?
        )
        case deletePhoto(dayId: UUID, stopId: UUID, photo: RecapPhoto, index: Int)
        case mergePlaceStops(dayId: UUID, originalFirst: PlaceStop, originalSecond: PlaceStop, firstIndex: Int)

        /// Message for the toast after the user taps Undo (describes what was reversed, not the original action).
        var messageAfterUndo: String {
            switch self {
            case .deletePlace: return "Place restored"
            case .deletePhoto: return "Photo restored"
            case .mergePlaceStops: return "Merge undone"
            }
        }
    }

    init(blogId: UUID, initialTrip: TripDraft?, initialDayIndex: Int? = nil, initialScrollToStopId: UUID? = nil, forceEditMode: Bool = false, forcePresentShareYourBlogSheet: Bool = false, onRequestDismiss: (() -> Void)? = nil, suppressPhotoGroupingTipOnAppear: Bool = false) {
        self.blogId = blogId
        self.initialTrip = initialTrip
        self.initialDayIndex = initialDayIndex
        self.initialScrollToStopId = initialScrollToStopId
        self.forceEditMode = forceEditMode
        self.forcePresentShareYourBlogSheet = forcePresentShareYourBlogSheet
        self.onRequestDismiss = onRequestDismiss
        self.suppressPhotoGroupingTipOnAppear = suppressPhotoGroupingTipOnAppear
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

            if showStoryMode {
                // Opaque underlay + no fade-in on the whole stack so the blog never shows through during presentation.
                ZStack {
                    storyPresentationUnderlayColor
                        .ignoresSafeArea()
                    StoryBookView(
                        detail: draft,
                        onDismiss: { showStoryMode = false; storyContentReady = false; storyChromeVisible = true },
                        triggerShare: $storyShareTrigger,
                        contentReady: $storyContentReady,
                        showChrome: $storyChromeVisible,
                        statusBarColorScheme: $storyStatusBarColorScheme
                    )
                        .environment(\.storyRecapTopContentInset, StoryRenderMetrics.recapStoryContentTopInset)
                        .ignoresSafeArea()

                }
                .overlay(
                    StatusBarStyleApplier(style: storyUIKitStatusBarStyle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                )
                .zIndex(200)
            }

            if showPanorama {
                panoramaOverlayLayer()
                    .transition(.opacity)
                    .zIndex(127)
            }

            if let day = fullScreenMapDay {
                let initialDayIndex = draft.days.firstIndex(where: { $0.id == day.id }) ?? 0
                FullScreenMapView(
                    allDays: draft.days,
                    initialDayIndex: initialDayIndex,
                    onDismiss: {
                        fullScreenMapDay = nil
                        fullScreenMapFocusedPlaceId = nil
                    },
                    onCaptionSaved: { dayId, stopId, photoId, newCaption in
                        bindingForPhotoCaption(dayId: dayId, stopId: stopId, photoId: photoId).wrappedValue = newCaption
                        persistRecapBlogDetail()
                        syncStoryToCloudIfNeeded(stopId: stopId, isPlaceNote: false, photoId: photoId)
                    },
                    onPlaceNameSaved: { stopId, name, category, coordinate, subtitleLine in
                        updatePlaceTitle(
                            stopId: stopId,
                            to: name,
                            category: category,
                            coordinate: coordinate,
                            placeSubtitleLine: subtitleLine
                        )
                    },
                    initialFocusedPlaceId: fullScreenMapFocusedPlaceId
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(145)
            }

            if let item = placeCaptionEditItem, let stop = placeStop(dayId: item.dayId, stopId: item.stopId) {
                placeCaptionEditLayer(item: item, stop: stop)
                    .transition(.opacity)
                    .zIndex(130)
            }

            if let item = dayCaptionEditItem {
                dayCaptionEditLayer(item: item)
                    .transition(.opacity)
                    .zIndex(131)
            }

            if showTripNarrativeEdit {
                tripNarrativeEditLayer()
                    .transition(.opacity)
                    .zIndex(133)
            }

            if let item = placePhotoModalItem {
                placePhotoModalOverlay(item: item)
                    // Clear under the sliding panel so the blog shows through during dismiss; instant removal avoids an extra fade on black.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    // Above place / single-photo caption editors (z 130 / 132) when opened from those flows.
                    .zIndex((placeCaptionEditItem != nil || photoCaptionEditItem != nil) ? 135 : 128)
            }

            if let item = photoCaptionEditItem,
               let stop = placeStop(dayId: item.dayId, stopId: item.stopId),
               let photo = stop.photos.first(where: { $0.id == item.photoId }) {
                photoCaptionEditLayer(item: item, photo: photo, stop: stop)
                    .transition(.opacity)
                    .zIndex(132)
            }

            if earlyAccessSheetPresented {
                earlyAccessOverlay()
                    .transition(.opacity)
                    .zIndex(160)
            }

            if showMissingPhotosTooltip {
                MissingPhotosTooltipOverlay(
                    onGotIt: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            sessionDismissedMissingPhotosTooltip = true
                            showMissingPhotosTooltip = false
                        }
                    },
                    onDoNotShowAgain: {
                        MissingPhotosTooltipPresentationStore.suppressPermanently(blogId: blogId)
                        withAnimation(.easeInOut(duration: 0.22)) {
                            sessionDismissedMissingPhotosTooltip = true
                            showMissingPhotosTooltip = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(158)
            }

            if showFirstSaveBlogSettingsSpotlight {
                FirstSaveBlogSettingsSpotlightOverlay(
                    holeInGlobal: blogSettingsGearFrameGlobal,
                    onOpenBlogSettings: { showBlogSettings = true }
                )
                .transition(.opacity)
                .zIndex(165)
            }

        }
        // When Story Mode is open, drive the entire hierarchy’s color scheme (including status bar) from the story.
        .preferredColorScheme(showStoryMode ? storyStatusBarColorScheme : nil)
        .dynamicTypeSize(.large)
        .animation(.easeInOut(duration: 0.35), value: isExportingPDF)
        .animation(.easeOut(duration: 0.22), value: placeCaptionEditItem?.id)
        .animation(.easeOut(duration: 0.22), value: dayCaptionEditItem?.id)
        .animation(.easeOut(duration: 0.22), value: showTripNarrativeEdit)
        .animation(.easeInOut(duration: 0.22), value: showPanorama)
        .animation(.easeInOut(duration: 0.28), value: fullScreenMapDay?.id)
        .animation(.easeInOut(duration: 0.38), value: placePhotoModalItem?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: revealRecapNavigationDuringPhotoDismiss)
        .animation(.easeOut(duration: 0.22), value: photoCaptionEditItem?.id)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: earlyAccessSheetPresented)
        .animation(.easeInOut(duration: 0.28), value: showMissingPhotosTooltip)
        .animation(.easeOut(duration: 0.22), value: showFirstSaveBlogSettingsSpotlight)
        .onPreferenceChange(BlogSettingsGearFramePreferenceKey.self) { rect in
            if rect.width > 0.5, rect.height > 0.5 {
                blogSettingsGearFrameGlobal = rect
            }
        }
        .onChange(of: showBlogSettings) { _, isPresented in
            guard isPresented, showFirstSaveBlogSettingsSpotlight else { return }
            dismissFirstSaveBlogSettingsSpotlight(markedSeen: true)
        }
        .onAppear {
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
            Task { await createdRecapStore.inferTransportModesIfNeeded(for: blogId) }
        }
        .onDisappear {
            blogReelAutoplay.setAutoplayEnabled(false)
            // Overlay blogs dismiss entirely — do not mark "initial exit" or the next open will flip to
            // read-only instead of dismissing back to Places visited (see toolbar back handling).
            if onRequestDismiss == nil {
                createdRecapStore.markInitialRecapEditorExit(for: blogId)
            }
        }
        .onChange(of: showStoryMode) { _, _ in
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
        }
        .onChange(of: showPanorama) { _, _ in
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
        }
        .onChange(of: isExportingPDF) { _, _ in
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
        }
        .onChange(of: showAuth) { _, _ in refreshMissingPhotosTooltipVisibility() }
        .onChange(of: showGuestSecondSaveLimitModal) { _, _ in refreshMissingPhotosTooltipVisibility() }
        .onChange(of: createdRecapStore.guestSecondSaveBlockedSignal) { _, _ in
            showGuestSecondSaveLimitModal = true
        }
        .onChange(of: earlyAccessSheetPresented) { _, _ in refreshMissingPhotosTooltipVisibility() }
        .onChange(of: isEditMode) { _, _ in refreshBlogReelAutoplayEnabled() }
        .onChange(of: hasFinishedInitialLoad) { _, _ in refreshBlogReelAutoplayEnabled() }
        .onChange(of: placePhotoModalItem?.id) { _, newId in
            if newId != nil {
                revealRecapNavigationDuringPhotoDismiss = false
            }
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
        }
    }

    private func bodyContent(screenHeight: CGFloat) -> some View {
        bodyContentBase(screenHeight: screenHeight)
            .fullScreenCover(isPresented: $showAuth, onDismiss: {
                if pendingEarlyAccessAfterAuth {
                    earlyAccessSheetPresented = false
                }
                pendingWebLinkAfterAuth = false
                pendingBloggoQRAfterAuth = false
                pendingSecondSaveCommitAfterAuth = false
            }) {
                AuthView(
                    onAuthenticated: {
                        if pendingSecondSaveCommitAfterAuth {
                            pendingSecondSaveCommitAfterAuth = false
                            showAuth = false
                            // Stay on this blog after sign-in; saving must not pop the recap.
                            if saveDraft(suppressPostSaveOnboarding: true) {
                                isEditMode = false
                            }
                        } else if pendingEarlyAccessAfterAuth {
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
                        } else if pendingBloggoQRAfterAuth {
                            pendingBloggoQRAfterAuth = false
                            showAuth = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showBloggoQRSheet = true
                            }
                        } else if pendingWebLinkAfterAuth {
                            pendingWebLinkAfterAuth = false
                            showAuth = false
                            handleShareWebLinkTap()
                        } else {
                            showAuth = false
                        }
                    },
                    onDismiss: {
                        showAuth = false
                    },
                    hostControlsDismiss: true
                )
                .environmentObject(authService)
            }
            .sheet(isPresented: $showPDFPreview) {
                if let url = pdfExportURL {
                    PDFPreviewSheet(pdfURL: url)
                }
            }
            .sheet(isPresented: $showPDFExportOptions) {
                PDFExportOptionsSheet(
                    options: Binding(
                        get: { (try? JSONDecoder().decode(PDFExportOptions.self, from: pdfExportOptionsData)) ?? PDFExportOptions() },
                        set: { pdfExportOptionsData = (try? JSONEncoder().encode($0)) ?? Data() }
                    ),
                    onExport: { opts in exportBlogToPDF(options: opts) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showShareYourBlogSheet, onDismiss: {
                shareYourBlogSheetPhase = .menu
                shareSheetPresentationDetent = .height(shareMenuDetentHeight)
                if pendingBloggoQRSheetAfterShareDismiss {
                    pendingBloggoQRSheetAfterShareDismiss = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBloggoQRSheet = true
                    }
                }
            }) {
                shareYourBlogSheetContent()
                    .onAppear {
                        shareSheetPresentationDetent = shareYourBlogSheetPhase == .menu ? .height(shareMenuDetentHeight) : .height(538)
                    }
                    .onChange(of: shareYourBlogSheetPhase) { _, phase in
                        withAnimation(.easeInOut(duration: shareYourBlogSheetPhaseTransitionDuration)) {
                            shareSheetPresentationDetent = phase == .menu ? .height(shareMenuDetentHeight) : .height(538)
                        }
                    }
                    .presentationDetents([.height(shareMenuDetentHeight), .height(538)], selection: $shareSheetPresentationDetent)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStoryModePDFOptions, onDismiss: {
                if pendingStoryOpen {
                    pendingStoryOpen = false
                    showStoryMode = true
                    AppAnalytics.track(.blogPlaySlideshow(blogId: blogId.uuidString))
                }
            }) {
                StoryModePDFOptionsSheet {
                    pendingStoryOpen = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showProfileManagement, onDismiss: {
                if let updatedDetail = createdRecapStore.getBlogDetail(blogId: blogId) {
                    draft = updatedDetail
                }
            }) {
                ProfileManagementView()
                    .environmentObject(createdRecapStore)
                    .environmentObject(nearbyShare)
            }
            .sheet(isPresented: $showGuestSecondSaveLimitModal) {
                guestSecondSaveLimitModalContent
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
    }

    private var guestSecondSaveLimitModalContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image("SplashIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundColor(.white)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Create an Account")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Sign in to save and download unlimited blogs. Guest users can only save one blog to try Bloggo.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showGuestSecondSaveLimitModal = false
                    pendingSecondSaveCommitAfterAuth = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAuth = true
                    }
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .appChromeCornerRadius(12)
                }

                Button {
                    showGuestSecondSaveLimitModal = false
                    createdRecapStore.saveBlogDetail(draft, asDraft: true)
                    createdRecapStore.showDraftSavedToast = true
                    performDismiss()
                } label: {
                    Text("Save as Draft")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }

    private func bodyContentBase(screenHeight: CGFloat) -> some View {
        coreContent(screenHeight: screenHeight)
            .environmentObject(blogReelAutoplay)
            .overlay(alignment: .top) { firstSaveBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFirstSaveBanner)
            .overlay(alignment: .top) { uploadSuccessBannerOverlay }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showUploadSuccessBanner)
            .fullScreenCover(isPresented: $showCameraCaptureFromRecap) {
                NavigationStack {
                    CameraCaptureView(
                        tripsViewModel: TripsViewModel(createdRecapStore: createdRecapStore),
                        postDismissToast: nil,
                        forcedTargetBlogId: blogId
                    )
                    .environmentObject(createdRecapStore)
                }
            }
            .fullScreenCover(isPresented: $showUploadingFullScreen) {
                UploadingBlogView(
                    uploadProgress: $uploadProgress,
                    title: uploadingViewTitle,
                    progressDetail: uploadingViewProgressDetail,
                    stepCycleLabels: uploadingViewStepCycleLabels,
                    allowsCancel: uploadingViewAllowsCancel,
                    onCancel: cancelUpload
                )
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
            .alert("Upload to Cloud?", isPresented: $showUploadPromptAlert) {
                Button("Yes") {
                    uploadBlogPhotos()
                }
                Button("No", role: .cancel) { }
            } message: {
                Text("This blog needs to be uploaded to the cloud before you can share a link. Would you like to upload it now?")
            }
            .sheet(isPresented: $showGuestCloudUploadModal) {
                guestCloudUploadModalContent
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
            .alert("No New Moments Found", isPresented: $showNoNewMomentsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No new photos were found in your library for this trip's date range.")
            }
            .alert("Rescan Complete", isPresented: $showRescanResultAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rescanResultMessage)
            }
            .alert("Cloud sharing coming soon", isPresented: $showCloudSharingComingSoonAlert) {
                Button("Join Early Access") {
                    showCloudSharingComingSoonAlert = false
                    Task {
                        await EarlyAccessManager.shared.registerWaitlist()
                        await MainActor.run {
                            hasJoinedEarlyAccess = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    showCloudSharingComingSoonAlert = false
                }
            } message: {
                Text("We’re gradually releasing web sharing to early users.")
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
                if showPhotoLibraryAccessPrompt {
                    PhotoLibraryAccessPromptView(
                        onOpenSettings: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPhotoLibraryAccessPrompt = false
                            }
                            openAppSettings()
                        },
                        onSelectPhotos: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPhotoLibraryAccessPrompt = false
                            }
                            presentLimitedLibraryPickerFromBlog()
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPhotoLibraryAccessPrompt = false
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(998)
                }
                if showBloggoQRSheet {
                    bloggoQRSharePopup()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: showBloggoQRSheet)
                        .zIndex(1000)
                }
                if showSocialPostStudio {
                    SocialPostStudioSheet(
                        blog: draft,
                        opensInEditMode: true,
                        onDismissFromParent: { showSocialPostStudio = false }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1002)
                }
            }
            .onReceive(createdRecapStore.objectWillChange) {
                // Default `isEditMode` is true, so we must still merge background work (rate-limited geocoding per day)
                // from the store; otherwise `draft` stays stale while `blogDetailsBySourceId` updates and days look stuck until reopen.
                if let updated = createdRecapStore.getBlogDetail(blogId: blogId),
                   !updated.days.isEmpty {
                    if isEditMode {
                        let draftBeforeMerge = draft
                        let snapshotBeforeMerge = draftSnapshot
                        mergeResolvedBlogDaysFromStore(updated: updated, into: &draft)
                        Task { @MainActor in
                            _ = await pruneEmptyPhotoGroupsFromDraftAsync()
                        }
                        // If the user hadn't changed anything since the snapshot, keep the snapshot aligned with
                        // background geocode/cover updates so we don't show a false "Unsaved changes" prompt.
                        if let snap = snapshotBeforeMerge, draftBeforeMerge == snap {
                            draftSnapshot = draft
                        }
                    } else if updated != draft {
                        draft = updated
                    }
                }
                if !newMomentPhotos.isEmpty || !highlightedNewMomentsDayIndices.isEmpty {
                    refreshHighlightedNewMomentsDays()
                    if !hasAutoScrolledToNewMomentsDay, initialScrollToStopId == nil {
                        focusNewMomentsDayIfNeeded(animated: false)
                    }
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
                scheduleMissingPhotosTooltipRefresh()
            }
    }

    @ViewBuilder
    private func coreContentRoot(screenHeight: CGFloat) -> some View {
        if !hasFinishedInitialLoad {
            blogInitialLoadView
        } else {
            mainContent(screenHeight: screenHeight)
        }
    }

    private var blogInitialLoadView: some View {
        LoadingScanView(
            message: "Opening your blog…",
            useCenteredLayout: true,
            showsTopTrailingActions: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(recapScreenBackground.ignoresSafeArea())
    }

    private func coreContent(screenHeight: CGFloat) -> some View {
        coreContentWithSheets(screenHeight: screenHeight)
    }

    private func coreContentWithSheets(screenHeight: CGFloat) -> some View {
        applyFinalContentModifiers(
            to: applySecondarySheetModifiers(
                to: applyPrimarySheetModifiers(
                    to: coreContentChrome(screenHeight: screenHeight)
                )
            )
        )
    }

    private var shouldHideRecapNavigationBar: Bool {
        showStoryMode ||
        showPanorama ||
        showSocialPostStudio ||
        fullScreenMapDay != nil ||
        placeCaptionEditItem != nil ||
        dayCaptionEditItem != nil ||
        showTripNarrativeEdit ||
        (placePhotoModalItem != nil && !revealRecapNavigationDuringPhotoDismiss) ||
        photoCaptionEditItem != nil
    }

    private func coreContentChrome(screenHeight: CGFloat) -> some View {
        coreContentRoot(screenHeight: screenHeight)
            .navigationBarBackButtonHidden(true)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(recapNavigationBarBackgroundVisibility, for: .navigationBar)
            .toolbarBackground(recapNavigationBarBackgroundFill, for: .navigationBar)
            .toolbar { toolbarContent }
            .toolbar(shouldHideRecapNavigationBar ? .hidden : .automatic, for: .navigationBar)
    }

    private func applyPrimarySheetModifiers<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showVideoExportOptions) {
                BlogVideoExportOptionsSheet(
                    draft: draft,
                    onShare: { url in
                        blogVideoShareURL = url
                        // Brief delay lets the options sheet fully dismiss before the system share sheet appears.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            showBlogVideoShareSheet = true
                        }
                    },
                    onRequestReelCapture: {
                        UserDefaults.standard.set("reel", forKey: "bloggo.camera.captureMode")
                        openCameraCaptureFromRecap()
                    }
                )
            }
            .sheet(isPresented: $showBlogVideoShareSheet) {
                if let url = blogVideoShareURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showBlogSettings) {
                BlogSettingsSheet(
                    draft: $draft,
                    selectedDayIndex: $selectedDayIndex,
                    blogKey: currentBlogKey,
                    onSave: { saveDraft() },
                    onBlogPhotosUpdated: {
                        if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
                            draft = updated
                            draftSnapshot = updated
                        }
                    },
                    onAddNewMoments: newMomentsPlaceCount == 0 ? nil : {
                        showBlogSettings = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showNewMomentsReviewSheet = true
                        }
                    },
                    onRescanAllMoments: isOnTheGoBlogForRescan
                        ? {
                            showBlogSettings = false
                            rescanAllMomentsFromStart()
                        }
                        : nil,
                    onDelete: {
                        AppAnalytics.track(.blogDelete(blogId: blogId.uuidString))
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
                        persistRecapBlogDetail()
                        syncWithCloudIfNeeded()
                    },
                    canShareNearby: hasBlogBeenSavedToDevice,
                    onCoverCloudUploadStateChanged: { starting in
                        if starting {
                            beginAuxiliaryCloudUploadOverlay(
                                title: "Updating cover",
                                progressDetail: "Uploading cover photo…",
                                progress: (0, 1)
                            )
                        } else {
                            endAuxiliaryCloudUploadOverlay()
                        }
                    }
                )
                .environmentObject(nearbyShare)
                .environmentObject(createdRecapStore)
            }
            .sheet(isPresented: $showTitleChange, onDismiss: {
                persistRecapBlogDetail()
            }) {
                BlogTitleChangeSheet(title: $draft.title, blogKey: currentBlogKey) {
                    showTitleChange = false
                }
            }
            .sheet(isPresented: $showCoverPhotoPicker, onDismiss: {
                persistRecapBlogDetail()
                // Only push to cloud if the selection actually changed and the blog is published
                if let blogKey = currentBlogKey,
                   let newId = draft.selectedCoverPhotoIdentifier,
                   newId != coverPhotoIdentifierBeforeEdit {
                    Task { @MainActor in
                        beginAuxiliaryCloudUploadOverlay(
                            title: "Updating cover",
                            progressDetail: "Uploading cover photo…",
                            progress: (0, 1)
                        )
                        defer { endAuxiliaryCloudUploadOverlay() }
                        do {
                            let url = try await APIManager.shared.uploadAndUpdateCoverPhoto(
                                blogKey: blogKey,
                                assetIdentifier: newId
                            )
                            uploadProgress.current = 1
                            draft.setCloudURL(url, forLocalAssetIdentifier: newId)
                            persistRecapBlogDetail()
                        } catch {
                            print("🚨 Cover photo cloud update failed: \(error)")
                        }
                    }
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
    }

    private func applySecondarySheetModifiers<Content: View>(to content: Content) -> some View {
        content
            .sheet(item: $overflowStop) { item in
                let mergeCandidatesForStop = mergeCandidates(dayId: item.dayId, sourceStopId: item.stop.id)
                let displayablePhotoCount = item.stop.photos.filter(\.hasDisplayableLocalBacking).count
                PlaceStopActionSheet(
                    placeTitle: item.stop.placeTitle,
                    placeSubtitle: item.stop.placeSubtitle,
                    onEditPlaceName: {
                        AppAnalytics.track(.blogPlaceChangeName(blogId: blogId.uuidString, placeId: item.stop.id.uuidString))
                        showEditNameForStop = item.stop
                    },
                    onManagePhotos: {
                        AppAnalytics.track(.blogPlaceManagePhoto(blogId: blogId.uuidString, placeId: item.stop.id.uuidString))
                        openManagePhotos(dayId: item.dayId, stopId: item.stop.id)
                    },
                    onEditCaption: {
                        placeCaptionEditItem = PlaceCaptionEditItem(dayId: item.dayId, stopId: item.stop.id)
                    },
                    onMergePlaces: isEditMode && !mergeCandidatesForStop.isEmpty ? {
                        mergeSelectionItem = MergeSelectionItem(dayId: item.dayId, sourceStopId: item.stop.id)
                    } : nil,
                    onSplit: displayablePhotoCount > 1 ? {
                        presentSplitPlaceStopSheet(dayId: item.dayId, stop: item.stop)
                    } : nil,
                    onSetTransportMode: nextStop(dayId: item.dayId, stopId: item.stop.id) != nil ? {
                        transportModePickerItem = item
                    } : nil,
                    currentTransportMode: item.stop.transportModeToNextStop,
                    onRemoveFromBlog: { removePlaceStop(dayId: item.dayId, stopId: item.stop.id) }
                )
            }
            .sheet(item: $transportModePickerItem) { item in
                let next = nextStop(dayId: item.dayId, stopId: item.stop.id)
                let autoMode: TravelMode? = {
                    guard let next else { return nil }
                    return TravelMode.detect(from: item.stop, to: next)
                }()
                TransportModePickerSheet(
                    fromPlaceTitle: item.stop.placeTitle,
                    toPlaceTitle: next?.placeTitle ?? "Next Stop",
                    autoDetectedMode: autoMode,
                    currentMode: item.stop.transportModeToNextStop,
                    onSelect: { mode in
                        setTransportMode(mode, dayId: item.dayId, stopId: item.stop.id)
                    }
                )
            }
            .sheet(item: $mergeSelectionItem) { item in
                RecapMergePlacesSelectionSheet(
                    sourcePlaceTitle: placeStop(dayId: item.dayId, stopId: item.sourceStopId)?.placeTitle ?? "This place",
                    sourcePreviewPhoto: placeStop(dayId: item.dayId, stopId: item.sourceStopId)?.photos.first,
                    candidates: mergeCandidates(dayId: item.dayId, sourceStopId: item.sourceStopId),
                    onSelectCandidate: { candidate in
                        DispatchQueue.main.async {
                            mergeSelectedStops(dayId: item.dayId, sourceStopId: item.sourceStopId, targetStopId: candidate.stopId)
                        }
                    }
                )
            }
            .sheet(item: $splitPlaceStopItem) { item in
                SplitPlaceStopView(
                    placeTitle: item.stop.placeTitle,
                    photos: item.stop.photos.sorted { $0.timestamp < $1.timestamp },
                    onSplit: { afterIndex in
                        print("[SplitPlaceStop] sheet onSplit callback afterPhotoIndex=\(afterIndex) dayId=\(item.dayId) stopId=\(item.stop.id) photoCount=\(item.stop.photos.count)")
                        splitPlaceStop(dayId: item.dayId, stopId: item.stop.id, afterPhotoIndex: afterIndex)
                    }
                )
            }
            .fullScreenCover(item: $showEditNameForStop) { stop in
                EditPlaceStopNameSheet(
                    placeTitle: bindingForPlaceTitle(stopId: stop.id),
                    initialPlaceSubtitle: stop.placeSubtitle,
                    initialPlaceCategory: stop.placeCategory,
                    location: stop.representativeLocation?.clCoordinate ?? stop.photos.first?.location?.clCoordinate,
                    photos: stop.includedPhotos,
                    onSave: { newTitle, newCoordinate, newCategory, subtitleLine in
                        updatePlaceTitle(stopId: stop.id, to: newTitle, category: newCategory, coordinate: newCoordinate, placeSubtitleLine: subtitleLine)
                    },
                    onAutoResolve: { resolvedTitle in
                        silentlyUpdatePlaceName(stopId: stop.id, to: resolvedTitle)
                    }
                )
            }
            .sheet(item: $placeCategoryPickerTarget) { target in
                PlaceStopCategoryPickerSheet(
                    initialCategoryRaw: placeStop(stopId: target.id)?.placeCategory,
                    onCancel: { placeCategoryPickerTarget = nil },
                    onDone: { newCategory in
                        updatePlaceCategory(stopId: target.id, category: newCategory)
                        placeCategoryPickerTarget = nil
                    }
                )
            }
            .navigationDestination(item: $showManagePhotosForStop) { pair in
                ManagePhotosView(
                    placeTitle: placeStop(dayId: pair.dayId, stopId: pair.stopId)?.placeTitle ?? "Photos",
                    photos: bindingForPhotos(dayId: pair.dayId, stopId: pair.stopId),
                    onSplitRequested: {
                        guard let stop = placeStop(dayId: pair.dayId, stopId: pair.stopId) else { return }
                        presentSplitPlaceStopSheet(dayId: pair.dayId, stop: stop)
                    },
                    onAddFromLibrary: { showLibraryImportForManageStop = true },
                    onAddFromBloggoGallery: { showBloggoGalleryImportForManageStop = true },
                    isLimitedPhotoLibraryAccess: photoAuth.status == .limited,
                    onExpandSharedPhotoLibrary: {
                        presentLimitedLibraryPickerForManageStopImport(dayId: pair.dayId, stopId: pair.stopId)
                    },
                )
            }
            .sheet(isPresented: $showLibraryImportForManageStop) {
                CameraRollPickerView { identifiers in
                    showLibraryImportForManageStop = false
                    guard let pair = showManagePhotosForStop, !identifiers.isEmpty else { return }
                    Task {
                        await importLibraryPhotosIntoStop(assetIdentifiers: identifiers, dayId: pair.dayId, stopId: pair.stopId)
                    }
                }
            }
            .sheet(isPresented: $showBloggoGalleryImportForManageStop) {
                let alreadyAdded: Set<String> = {
                    guard let pair = showManagePhotosForStop,
                          let stop = placeStop(dayId: pair.dayId, stopId: pair.stopId) else { return [] }
                    return Set(stop.photos.compactMap(\.localIdentifier))
                }()
                AppCaptureGalleryView(
                    onPickerComplete: { captureIds in
                        showBloggoGalleryImportForManageStop = false
                        guard let pair = showManagePhotosForStop, !captureIds.isEmpty else { return }
                        importBloggoPhotosIntoStop(captureIds: captureIds, dayId: pair.dayId, stopId: pair.stopId)
                    },
                    excludedIdentifiers: alreadyAdded
                )
            }
            .onChange(of: showManagePhotosForStop) { old, new in
                guard old != nil, new == nil else { return }
                // Equivalent of onDismiss: save and sync after user navigates back.
                skipDefaultDayPageScrollOnNextAppear = true
                print("📸 [ManagePhotos] dismissed — editInfo=\(managePhotosEditInfo != nil ? "set(stopId=\(managePhotosEditInfo!.stopId))" : "nil")")
                Task { @MainActor in
                    _ = await pruneEmptyPhotoGroupsFromDraftAsync()
                    persistRecapBlogDetail()
                    syncPhotoChangesWithCloud()
                }
            }
            .sheet(isPresented: $showRestorePlaces) {
                RemovedPlacesSheet(draft: $draft, selectedDayIndex: $selectedDayIndex) {
                    persistRecapBlogDetail()
                    syncWithCloudIfNeeded()
                }
            }
            .sheet(isPresented: $showCloudOnboardingModal) {
                cloudOnboardingModalContent()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder
    private func panoramaOverlayLayer() -> some View {
        // Build one group per PlaceStop so diptych never mixes places.
        // Enumerate days so each entry carries a dayIndex for scope filtering.
        let groups: [[PanoramaPhotoEntry]] = draft.days
            .enumerated()
            .flatMap { (dayIdx, day) in
                day.placeStops.compactMap { stop -> [PanoramaPhotoEntry]? in
                    let entries = stop.photos
                        .filter(\.isIncluded)
                        .compactMap { photo -> PanoramaPhotoEntry? in
                            guard let id = photo.localIdentifier, !id.isEmpty else { return nil }
                            // Resolve a moment-video reel for in-app camera captures.
                            let reelURL: URL? = {
                                guard let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
                                return AppCapturePhotoService.shared.momentVideoFileURL(for: captureId)
                            }()
                            return PanoramaPhotoEntry(
                                id: id,
                                caption: photo.caption,
                                placeName: stop.placeTitle,
                                timestamp: photo.timestamp,
                                location: photo.location,
                                momentVideoURL: reelURL,
                                dayIndex: dayIdx
                            )
                        }
                    return entries.isEmpty ? nil : entries
                }
            }
        // Build day labels: prefer the day's caption if set, else "Day N".
        let dayLabels: [String] = draft.days.enumerated().map { idx, day in
            let caption = day.dayCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return caption.isEmpty ? "Day \(idx + 1)" : caption
        }
        // Fall back to cover photo when no included photos exist.
        let photoGroups = groups.isEmpty
            ? draft.selectedCoverPhotoIdentifier.map {
                [[PanoramaPhotoEntry(id: $0, caption: nil, placeName: nil, timestamp: nil, location: nil)]]
            } ?? []
            : groups
        if !photoGroups.isEmpty {
            PanoramaPlayerView(
                photoGroups: photoGroups,
                blogId: blogId,
                blogTitle: draft.title,
                dayLabels: dayLabels,
                startInGallery: true,
                onDismiss: { showPanorama = false },
                onAppCaptureDeletedFromSlideshow: { identifier in
                    removeAppCapturePhotoFromSlideshow(identifier: identifier)
                },
                onPausedMetadataTapped: { identifier in
                    openPlaceModalFromPanoramaCaptionTap(localIdentifier: identifier)
                },
                onPhotosRemovedFromBlog: { identifiers in
                    removePhotosFromBlogViaGallery(identifiers: identifiers)
                },
                onCleanupUnused: {
                    showCleanupFromGallery = true
                }
            )
        }
    }

    private func applyFinalContentModifiers<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: $showCleanupFromGallery) {
                NavigationStack {
                    StorageManagementView(draft: $draft, onSave: { saveDraft() })
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: Binding(
                get: { unsavedSplitPromptIndex != nil },
                set: { if !$0 { unsavedSplitPromptIndex = nil } }
            )) {
                if let splitIdx = unsavedSplitPromptIndex {
                    unsavedSplitModal(splitIdx: splitIdx)
                }
            }
            .sheet(isPresented: $showContinueEditingAfterSplit, onDismiss: handleSavedContinueEditingSheetDismissed) {
                if let previews = savedSplitPartPreviews {
                    ContinueEditingAfterSplitSheet(
                        part1: previews.part1,
                        part2: previews.part2,
                        onSelectPart1: {
                            didPickSavedSplitEditorPart = true
                            showContinueEditingAfterSplit = false
                            savedSplitPartPreviews = nil
                            applySavedSplitEditorFocus(keepPart: 1)
                        },
                        onSelectPart2: {
                            didPickSavedSplitEditorPart = true
                            showContinueEditingAfterSplit = false
                            savedSplitPartPreviews = nil
                            applySavedSplitEditorFocus(keepPart: 2)
                        }
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { weatherEditDayId != nil },
                set: { if !$0 { weatherEditDayId = nil } }
            )) {
                if let dayId = weatherEditDayId,
                   let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }) {
                    WeatherEditSheet(day: $draft.days[dayIdx], onDismiss: { weatherEditDayId = nil })
                }
            }
            .overlay {
                if showNewMomentsReviewSheet {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissNewMomentsReviewWithoutAdding()
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
                            dismissNewMomentsReviewWithoutAdding()
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
                }
            }
            .modifier(coreContentAlertsAndLifecycleModifier())
            .alert("Save as Draft?", isPresented: $showNewBlogExitConfirmation) {
                if isDraft {
                    Button("Exit Draft", role: .destructive) {
                        performDismiss()
                    }
                } else {
                    Button("Save as Draft") {
                        createdRecapStore.saveBlogDetail(draft, asDraft: true)
                        createdRecapStore.showDraftSavedToast = true
                        performDismiss()
                    }
                }
                Button("Exit", role: .destructive) {
                    createdRecapStore.removeLocalCopy(sourceTripId: blogId)
                    performDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if isDraft {
                    Text("This blog is already a draft. Exit now?")
                } else {
                    Text("Would you like to save this blog as a draft and finish it later?")
                }
            }
            .alert("Save as Draft?", isPresented: $showOverlayDraftExitConfirmation) {
                if isDraft {
                    Button("Exit Draft", role: .destructive) {
                        performDismiss()
                    }
                } else {
                    Button("Save as Draft") {
                        createdRecapStore.saveBlogDetail(draft, asDraft: true)
                        createdRecapStore.showDraftSavedToast = true
                        performDismiss()
                    }
                }
                Button("Discard changes", role: .destructive) {
                    if let snapshot = draftSnapshot {
                        draft = snapshot
                    }
                    _ = createdRecapStore.saveBlogDetail(draft, asDraft: true)
                    performDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if isDraft {
                    Text("This blog is already a draft. Exit now or discard unsaved changes before going back.")
                } else {
                    Text("You have unsaved changes. Save as a draft or discard changes before going back.")
                }
            }
    }

    private func coreContentAlertsAndLifecycleModifier() -> some ViewModifier {
        CoreContentAlertsAndLifecycleModifier(
            showSaveTipAlert: $showSaveTipAlert,
            hasSeenPhotoGroupingTip: $hasSeenPhotoGroupingTip,
            showUnsavedChangesAlert: $showUnsavedChangesAlert,
            draftSnapshot: $draftSnapshot,
            cancellables: $cancellables,
            isKeyboardVisible: $isKeyboardVisible,
            isEditMode: $isEditMode,
            draft: $draft,
            saveDraft: { saveDraft(suppressPostSaveOnboarding: $0) },
            loadDraftIfNeeded: loadDraftIfNeeded,
            checkFirstTimeTip: checkFirstTimeTip,
            createdRecapStore: createdRecapStore,
            needsCommittedRecapToolbarSave: { needsCommittedRecapToolbarSave },
            performRecapDismiss: performDismiss
        )
    }

    @State private var scrollToStopId: UUID?
    /// When the user focuses a story/caption field we store the row id here and scroll when the keyboard actually appears (no fixed delay).
    @State private var pendingScrollToStopId: UUID?
    /// Non-nil while jumping to a place from Places Visited — blocks default Day 2+ scroll-to-map so the stop row stays visible.
    @State private var pendingDeepLinkStopScrollId: UUID?
    @State private var didApplyPlacesVisitedDeepLink = false
    @State private var placesVisitedDeepLinkTask: Task<Void, Never>?

    private static let dayFilterApproxHeight: CGFloat = 52

    private static func placeMediaTileHeight(for screenHeight: CGFloat) -> CGFloat {
        screenHeight * 0.80
    }

    /// Scroll timeline to `initialScrollToStopId` after the blog (and stop rows) are available.
    private func schedulePlacesVisitedDeepLinkScroll() {
        guard let targetStopId = initialScrollToStopId else { return }
        guard hasFinishedInitialLoad else { return }
        guard !didApplyPlacesVisitedDeepLink else { return }

        placesVisitedDeepLinkTask?.cancel()
        let snapshotDraft = draft
        placesVisitedDeepLinkTask = Task { @MainActor in
            defer { placesVisitedDeepLinkTask = nil }
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                let fromStore = createdRecapStore.getBlogDetail(blogId: blogId)
                let effective = fromStore ?? snapshotDraft
                guard let dayIdx = effective.days.firstIndex(where: { $0.placeStops.contains(where: { $0.id == targetStopId }) }) else {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                didApplyPlacesVisitedDeepLink = true
                if draft != effective {
                    draft = effective
                }
                selectedDayIndex = dayIdx
                // Set pendingDeepLinkStopScrollId — the day page's ScrollViewReader will handle the actual scroll.
                pendingDeepLinkStopScrollId = targetStopId
                return
            }
        }
    }

    private func mainContent(screenHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            recapScreenBackground.ignoresSafeArea()

            // Day view — deterministic snap navigation via swipe (no horizontal scrolling).
            if draft.days.isEmpty {
                emptyDayPage(screenHeight: screenHeight)
            } else {
                if let day = day(at: selectedDayIndex) {
                    GeometryReader { _ in
                        dayPageView(
                            blogDay: day,
                            index: selectedDayIndex,
                            screenHeight: screenHeight,
                            scrollCoverMaskActive: $recapDayScrollCoverMaskActive
                        )
                            .id(day.id) // ensures per-day scroll state resets appropriately on day change
                            .transition(
                                shouldAnimateDayChange
                                ? .asymmetric(
                                    insertion: .move(edge: daySwipeTransitionDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: daySwipeTransitionDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                                )
                                : .identity
                            )
                            // Keep swipe transitions smooth and directional, but make pill taps render immediately.
                            .transaction { txn in
                                // Faster, more responsive feel for swipe-to-change-day.
                                txn.animation = shouldAnimateDayChange ? .easeOut(duration: 0.08) : nil
                            }
                            // Day-swipe gesture disabled: conflicts with inner horizontal photo carousels.
                            // Use the day pill buttons to navigate between days.
                    }
                } else {
                    // Safety fallback (should not happen because indices are clamped elsewhere).
                    emptyDayPage(screenHeight: screenHeight)
                }
            }

            // Undo Toast (appears for 3s after undo is performed)
            if showUndoToast {
                UndoToastView(text: undoToastText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Self.dayFilterApproxHeight + 10)
                    .zIndex(20)
            } else if showSplitUndoBanner {
                // Above the day filter (same z-index treatment as `UndoToastView`).
                HStack(alignment: .center, spacing: 12) {
                    Text("Blog split into two parts")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Button("Undo") {
                        splitUndoBannerDismissTask?.cancel()
                        splitUndoBannerDismissTask = nil
                        createdRecapStore.undoSplit()
                        withAnimation { showSplitUndoBanner = false }
                        if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
                            draft = updated
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Self.dayFilterApproxHeight + 14)
                .zIndex(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !isKeyboardVisible {
                dayFilterSection
                    .zIndex(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if shouldShowRecapCameraQuickCapture && !isKeyboardVisible {
                recapCameraQuickCaptureButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, Self.dayFilterApproxHeight + 14)
                    .zIndex(21)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(recapScreenBackground)
        .onChange(of: selectedDayIndex) { _, newIndex in
            visitedDayIndices.insert(newIndex)
            preloadDayPagerThumbnails(around: newIndex)
            // Reset so subsequent non-swipe changes don't inherit swipe animation.
            shouldAnimateDayChange = false
            if newIndex > 0, pendingDeepLinkStopScrollId == nil {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    recapDayScrollCoverMaskActive = true
                }
            } else {
                recapDayScrollCoverMaskActive = false
            }
        }
        .onChange(of: pendingDeepLinkStopScrollId) { _, id in
            if id != nil {
                recapDayScrollCoverMaskActive = false
            }
        }
        .onChange(of: draft.days.count) { _, _ in
            schedulePlacesVisitedDeepLinkScroll()
        }
        .onChange(of: newMomentsPlaceCount) { _, count in
            guard count > 0, hasFinishedInitialLoad else { return }
            focusNewMomentsDayIfNeeded()
        }
        .onChange(of: newMomentPhotos.count) { _, count in
            guard count > 0, hasFinishedInitialLoad else { return }
            focusNewMomentsDayIfNeeded()
        }
        .onChange(of: hasFinishedInitialLoad) { _, finished in
            guard finished else { return }
            if initialScrollToStopId == nil {
                if let idx = clampedInitialDayIndex {
                    highlightedNewMomentsDayIndices.insert(idx)
                    selectedDayIndex = idx
                    hasAutoScrolledToNewMomentsDay = true
                } else {
                    focusNewMomentsDayIfNeeded(animated: false)
                }
            }
            preloadDayPagerThumbnails(around: selectedDayIndex)
            schedulePlacesVisitedDeepLinkScroll()
        }
        .onDisappear {
            placesVisitedDeepLinkTask?.cancel()
            placesVisitedDeepLinkTask = nil
            pendingDeepLinkStopScrollId = nil
            splitUndoBannerDismissTask?.cancel()
            splitUndoBannerDismissTask = nil
        }
        .onChange(of: isEditMode) { _, editing in
            if editing {
                visitedDayIndices = [selectedDayIndex]
                showHeroMetadata = true
            } else {
                // When tapping Save, the hero header can briefly re-layout while the day pager/nav updates.
                // Delay metadata so multi-line titles never collide with duration/moment captions.
                showHeroMetadata = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    // Only re-enable if we're still in view mode.
                    if !isEditMode {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showHeroMetadata = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Day Page Views

    /// A single horizontally-paged day view: shared trip header (cover, narrative) + per-day map + places.
    private func dayPageView(
        blogDay: RecapBlogDay,
        index: Int,
        screenHeight: CGFloat,
        scrollCoverMaskActive: Binding<Bool>
    ) -> some View {
        ScrollViewReader { proxy in
            dayPageScrollView(
                blogDay: blogDay,
                index: index,
                screenHeight: screenHeight,
                proxy: proxy,
                scrollCoverMaskActive: scrollCoverMaskActive
            )
        }
    }

    @ViewBuilder
    private func dayPageScrollInner(blogDay: RecapBlogDay, index: Int, screenHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
                .id(RecapBlogScrollAnchor.pageTop)

            // Always show the trip header (cover/title) on every day so swiping doesn't feel like the
            // cover "disappears" after Day 1. (Other trip-level affordances can still be Day 1 only.)
            if draft.selectedCoverPhotoIdentifier != nil {
                coverPhotoHero(screenHeight: screenHeight)
            } else {
                blogTitleView
            }

            // Day 1 shows trip narrative under the cover; Day 2+ omit it in view mode. Edit mode keeps it on every day.
            let showHeroHeader = isEditMode || index == 0

            if showHeroHeader {
                // Trip-level edit affordances stay on day 1 so they are not repeated on every tab.
                if index == 0 {
                    if isEditMode && photoAuth.status == .limited {
                        photoLibraryAccessBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }

                tripNarrativeCard
            }

            // New moments card — shown once, on the latest day that has new photos.
            if newMomentsPlaceCount > 0 && preferredNewMomentsDayIndex == index {
                newMomentsCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }

            // Read-only: map on every day. Edit: map from Day 2+ (Day 1 keeps edit chrome uncluttered).
            if !isEditMode || index > 0 {
                mapCard(for: blogDay)
            }

            // Restore hidden places: shown in edit mode below the map so it's visible at the default scroll position on every day.
            if isEditMode && !draft.removedPlaceStops.isEmpty {
                restoreRemovedPlacesCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }

            VStack(alignment: .leading, spacing: 16) {
                daySection(day: blogDay, dayIndex: index, screenHeight: screenHeight)
                    .id("day-section-\(blogDay.id)")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 32)

            Color.clear.frame(height: Self.dayFilterApproxHeight + 80)
        }
        .background(recapScreenBackground)
    }

    private var dayPagerThumbnailTargetSize: CGSize {
        // A fairly "universal" size used across recap cards so the first paint during paging doesn't wait on decoding.
        let s = UIScreen.main.scale
        return CGSize(width: 240 * s, height: 240 * s)
    }

    private func thumbnailAssetIdsForDay(index: Int) -> [String] {
        guard draft.days.indices.contains(index) else { return [] }
        return draft.days[index]
            .placeStops
            .flatMap(\.photos)
            .filter(\.isIncluded)
            .compactMap(\.localIdentifier)
    }

    /// Preload thumbnails for the currently selected day and its immediate neighbors.
    /// This reduces "empty" or placeholder frames while swiping between days.
    private func preloadDayPagerThumbnails(around index: Int) {
        let ids =
            thumbnailAssetIdsForDay(index: index)
            + thumbnailAssetIdsForDay(index: index - 1)
            + thumbnailAssetIdsForDay(index: index + 1)

        // Stop caching old set (PHCachingImageManager), then start caching the new set.
        if !cachedDayPagerThumbnailAssetIds.isEmpty {
            ImageLoader.shared.stopCachingThumbnails(
                assetIdentifiers: cachedDayPagerThumbnailAssetIds,
                targetSize: dayPagerThumbnailTargetSize
            )
        }
        cachedDayPagerThumbnailAssetIds = ids
        if !ids.isEmpty {
            ImageLoader.shared.startCachingThumbnails(
                assetIdentifiers: ids,
                targetSize: dayPagerThumbnailTargetSize
            )
        }
    }

    /// Day 1: top of scroll. Day 2+: scroll to inline map (cover stays above in layout; no animation to avoid a visible slide).
    private func applyDefaultDayPageScrollPosition(proxy: ScrollViewProxy, dayPageIndex: Int) {
        guard selectedDayIndex == dayPageIndex else { return }
        if pendingDeepLinkStopScrollId != nil { return }
        if dayPageIndex == 0 {
            proxy.scrollTo(RecapBlogScrollAnchor.pageTop, anchor: .top)
        } else if let d = day(at: dayPageIndex) {
            proxy.scrollTo(RecapBlogScrollAnchor.mapForDay(d.id), anchor: .top)
        }
    }

    private func dayPageScrollView(
        blogDay: RecapBlogDay,
        index: Int,
        screenHeight: CGFloat,
        proxy: ScrollViewProxy,
        scrollCoverMaskActive: Binding<Bool>
    ) -> some View {
        let showScrollCoverMask = index > 0
            && scrollCoverMaskActive.wrappedValue
            && pendingDeepLinkStopScrollId == nil

        return ZStack(alignment: .top) {
            ScrollView {
                dayPageScrollInner(blogDay: blogDay, index: index, screenHeight: screenHeight)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(BlogReelCandidatePreferenceKey.self) { candidates in
                guard index == selectedDayIndex else { return }
                blogReelAutoplay.updateCandidates(candidates)
            }
            .onPreferenceChange(TitleMinYPreferenceKey.self) { minY in
                guard index == selectedDayIndex else { return }
                let shouldShow = minY < 0
                if shouldShow != showNavBarTitle {
                    showNavBarTitle = shouldShow
                }
            }
            .background(recapScreenBackground)
            .ignoresSafeArea(edges: isKeyboardVisible ? [] : .bottom)

            if showScrollCoverMask {
                recapScreenBackground
                    .ignoresSafeArea(edges: isKeyboardVisible ? [] : .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: scrollToStopId) { _, newId in
            guard let id = newId, selectedDayIndex == index else { return }
            scrollToStopId = nil
            if isKeyboardVisible {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            } else {
                pendingScrollToStopId = id
            }
        }
        .onChange(of: isKeyboardVisible) { _, visible in
            guard selectedDayIndex == index else { return }
            if visible, let id = pendingScrollToStopId {
                pendingScrollToStopId = nil
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
        .onChange(of: selectedDayIndex) { _, newIndex in
            guard newIndex == index else { return }
            if pendingDeepLinkStopScrollId != nil {
                scrollCoverMaskActive.wrappedValue = false
                return
            }
            guard newIndex > 0 else { return }
            // Mask (from parent) hides the cover until scroll lands on the map; second async lets UIKit apply offset before fade-out.
            DispatchQueue.main.async {
                applyDefaultDayPageScrollPosition(proxy: proxy, dayPageIndex: newIndex)
                DispatchQueue.main.async {
                    guard selectedDayIndex == newIndex else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        scrollCoverMaskActive.wrappedValue = false
                    }
                }
            }
        }
        .onAppear {
            if skipDefaultDayPageScrollOnNextAppear {
                skipDefaultDayPageScrollOnNextAppear = false
                withAnimation(.easeOut(duration: 0.16)) {
                    scrollCoverMaskActive.wrappedValue = false
                }
                return
            }
            guard index > 0 else { return }
            if pendingDeepLinkStopScrollId != nil {
                scrollCoverMaskActive.wrappedValue = false
                return
            }
            DispatchQueue.main.async {
                applyDefaultDayPageScrollPosition(proxy: proxy, dayPageIndex: index)
                DispatchQueue.main.async {
                    guard selectedDayIndex == index else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        scrollCoverMaskActive.wrappedValue = false
                    }
                }
            }
        }
        .onChange(of: hasFinishedInitialLoad) { _, finished in
            guard finished else { return }
            if index == 0, isEditMode, initialScrollToStopId == nil {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(RecapBlogScrollAnchor.pageTop, anchor: .top)
                }
            }
        }
        .onChange(of: pendingDeepLinkStopScrollId) { _, stopId in
            guard let id = stopId, selectedDayIndex == index else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(id, anchor: .top)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: .top)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                pendingDeepLinkStopScrollId = nil
            }
        }
    }

    /// Shown when `draft.days` is empty (all places hidden).
    private func emptyDayPage(screenHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if draft.selectedCoverPhotoIdentifier != nil {
                    coverPhotoHero(screenHeight: screenHeight)
                } else {
                    blogTitleView
                }
                tripNarrativeCard
                if hasFinishedInitialLoad {
                    Text("All places are hidden.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .padding(.bottom, 60)
                }
                Color.clear.frame(height: Self.dayFilterApproxHeight + 80)
            }
            .background(recapScreenBackground)
        }
        .background(recapScreenBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    private var blogTitleView: some View {
        Group {
            if isEditMode {
                Button {
                    showTitleChange = true
                } label: {
                    let titleBoxRadius: CGFloat = 14
                    let titleEditIconOutset: CGFloat = 22
                    Text(draft.title)
                        .font(.blog(selectedBlogFont, size: 28, bold: true))
                        .foregroundColor(recapChromeForeground)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: titleBoxRadius, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: titleBoxRadius, style: .continuous)
                                .strokeBorder(recapChromeForeground.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1.5)
                        )
                        .overlay(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.1))
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(recapChromeForeground)
                            }
                            .frame(width: 30, height: 30)
                            .offset(x: titleEditIconOutset, y: -titleEditIconOutset)
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 32)
                .padding(.top, 12)
                .padding(.bottom, 8)
            } else {
                Text(draft.title)
                    .font(.blog(selectedBlogFont, size: 30, bold: true))
                    .foregroundColor(recapChromeForeground)
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

    /// True while photo quality scoring is still running (cover not yet finalized).
    private var isCoverPending: Bool {
        !draft.days.allSatisfy(\.isPlaceNamesResolved)
    }

    /// Vertical offset so the hero title’s midpoint sits at the cover image’s vertical center (until measured, uses a stable estimate).
    private func coverHeroTitleTopInset(heroHeight: CGFloat, measuredTitleHeight: CGFloat) -> CGFloat {
        let titleH = measuredTitleHeight > 0 ? measuredTitleHeight : 72
        return max(0, heroHeight * 0.5 - titleH * 0.5)
    }

    private func coverPhotoHero(screenHeight: CGFloat) -> some View {
        let displayCoverId = cyclingCoverPhotoId ?? draft.selectedCoverPhotoIdentifier
        let resolvedBaseHeight = coverHeroBaseScreenHeight ?? screenHeight
        let heroHeight = Self.placeMediaTileHeight(for: resolvedBaseHeight)
        let scale = UIScreen.main.scale
        let coverTargetWidth = max(320, UIScreen.main.bounds.width) * scale
        let coverTargetHeight = heroHeight * scale
        return GeometryReader { geo in
            ZStack {
                // Cover photo — cycles through trip photos while scoring, shows best when done
                if let coverId = displayCoverId {
                    AssetPhotoView(
                        assetIdentifier: coverId,
                        cornerRadius: 0,
                        targetSize: CGSize(width: coverTargetWidth, height: coverTargetHeight)
                    )
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .brightness(-0.05)
                        .blur(radius: isCoverPending ? 4 : 0)
                        .animation(.easeInOut(duration: 0.6), value: isCoverPending)
                        .id(coverId)
                        .transition(.opacity)
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

                // Title is pinned to a stable position (center of hero).
                // Edit mode: VStack layout so title box and Change Cover button
                // never overlap regardless of title length or Dynamic Type size.
                // View mode: VStack title + trip metadata so 2-line titles never overlap dates.
                ZStack {
                    let titleTopInset = coverHeroTitleTopInset(
                        heroHeight: geo.size.height,
                        measuredTitleHeight: coverHeroMeasuredTitleHeight
                    )
                    let viewModeLift: CGFloat = 12

                    if isEditMode {
                        // Edit mode: vertically center the title on the cover; keep 20pt before Change Cover.
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: max(0, titleTopInset - viewModeLift))
                            VStack(spacing: 20) {
                                HStack {
                                    Spacer(minLength: 0)
                                    Button { showTitleChange = true } label: {
                                        let heroTitleBoxRadius: CGFloat = 16
                                        let heroTitleMaxWidth = max(120, geo.size.width - 120)
                                        let heroTitleEditIconOutset: CGFloat = 22
                                        Text(draft.title)
                                            .font(.blog(selectedBlogFont, size: 30, bold: true))
                                            .foregroundColor(.white)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.center)
                                            .minimumScaleFactor(0.88)
                                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 14)
                                            .padding(.top, 6)
                                            .frame(maxWidth: heroTitleMaxWidth)
                                            .background(
                                                RoundedRectangle(cornerRadius: heroTitleBoxRadius, style: .continuous)
                                                    .fill(Color.black.opacity(0.22))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: heroTitleBoxRadius, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                                            )
                                            .overlay(alignment: .topTrailing) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color.white.opacity(0.28))
                                                    Image(systemName: "pencil")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(.white)
                                                }
                                                .frame(width: 30, height: 30)
                                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                                .offset(x: heroTitleEditIconOutset, y: -heroTitleEditIconOutset)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    Spacer(minLength: 0)
                                }
                                .background(
                                    GeometryReader { titleRowGeo in
                                        Color.clear.preference(
                                            key: CoverHeroTitleHeightPreferenceKey.self,
                                            value: titleRowGeo.size.height
                                        )
                                    }
                                )

                                Button {
                                    coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
                                    showCoverPhotoPicker = true
                                } label: {
                                    Text("Change Cover")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .id("hero-edit-layout")
                    } else {
                        // View mode: title vertically centered on the cover; same 14pt / 6pt spacing below the title.
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: max(0, titleTopInset - 10))
                            VStack(spacing: 14) {
                                Text(draft.title)
                                    .font(.blog(selectedBlogFont, size: 30, bold: true))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.85)
                                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                                    .background(
                                        GeometryReader { titleGeo in
                                            Color.clear
                                                .preference(key: TitleMinYPreferenceKey.self, value: titleGeo.frame(in: .named("scroll")).maxY)
                                                .preference(key: CoverHeroTitleHeightPreferenceKey.self, value: titleGeo.size.height)
                                        }
                                    )
                                    .frame(maxWidth: .infinity)
                                    .id("hero-title-view")

                                VStack(spacing: 6) {
                                    if showHeroMetadata {
                                        let dayCount = draft.days.count
                                        let momentCount = draft.days.flatMap(\.placeStops).count
                                        let photoCount = draft.days
                                            .flatMap(\.placeStops)
                                            .flatMap(\.photos)
                                            .filter(\.isIncluded)
                                            .count

                                        Text(tripDateText)
                                            .font(.callout)
                                            .foregroundColor(.white.opacity(0.92))
                                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                                        HStack(spacing: 8) {
                                            Text("\(dayCount) Day\(dayCount == 1 ? "" : "s")")
                                            Text("•")
                                            Text("\(momentCount) Moment\(momentCount == 1 ? "" : "s")")
                                            Text("•")
                                            Text("\(photoCount) Photo\(photoCount == 1 ? "" : "s")")
                                        }
                                        .font(.callout)
                                        .foregroundColor(.white.opacity(0.92))
                                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                                        Button {
                                            showShareYourBlogSheet = true
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "book.pages")
                                                    .font(.system(size: 14, weight: .medium))
                                                Text("Share Your Blog")
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
                                        .transition(.opacity)
                                    }
                                }
                                .id("hero-controls-view")
                            }
                            .offset(y: -40)
                            Spacer(minLength: 0)
                        }
                        .dynamicTypeSize(.medium)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }

                // Badge shown while cover selection is still in progress
                if isCoverPending {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.75)
                                .tint(.white)
                            Text("Selecting best cover…")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 14)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .transition(.opacity)
                }

                // Slideshow — top-trailing of cover, same column as nav gear (16pt inset, 44pt target); sits just below Blog Settings.
                if !isEditMode, !isCoverPending, displayCoverId != nil, !isExportingPDF, !showStoryMode {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Button {
                                showPanorama = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.55))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "square.grid.3x3.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Gallery")
                            .padding(.trailing, 16)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
                    .allowsHitTesting(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isCoverPending, displayCoverId != nil else { return }
                if isEditMode {
                    coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
                    showCoverPhotoPicker = true
                } else {
                    showPanorama = true
                }
            }
        }
        .onPreferenceChange(CoverHeroTitleHeightPreferenceKey.self) { h in
            if h > 0 {
                coverHeroMeasuredTitleHeight = h
            }
        }
        .onChange(of: isEditMode) { _, _ in
            coverHeroMeasuredTitleHeight = 0
        }
        .animation(.easeInOut(duration: 0.5), value: isCoverPending)
        .onAppear {
            if coverHeroBaseScreenHeight == nil {
                coverHeroBaseScreenHeight = screenHeight
            }
        }
        .onChange(of: screenHeight) { _, newHeight in
            // Ignore transient geometry shifts while Share/QR overlays are active.
            if !showShareYourBlogSheet && !showBloggoQRSheet {
                coverHeroBaseScreenHeight = newHeight
            }
        }
        .task(id: isCoverPending) {
            guard isCoverPending else {
                // Scoring complete — fade out cycling and let the real cover show
                withAnimation(.easeInOut(duration: 0.6)) { cyclingCoverPhotoId = nil }
                return
            }
            // Collect all photo identifiers across all days for the slideshow
            let ids = draft.days.flatMap(\.placeStops).flatMap(\.photos)
                .compactMap(\.localIdentifier)
                .shuffled()
            guard !ids.isEmpty else { return }
            var idx = 0
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.6)) {
                    cyclingCoverPhotoId = ids[idx % ids.count]
                }
                idx += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .frame(height: heroHeight)
    }

    // MARK: - Photo Library Access (Limited users)

    private var photoLibraryAccessBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPhotoLibraryAccessPrompt = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo Library Access")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Limited access enabled — manage photo permissions.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
            .background(
                Color.blue.opacity(0.75)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(appChromeBaseRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func presentLimitedLibraryPickerFromBlog() {
        // Similar to TripsView.presentLimitedLibraryPicker, but scoped to this blog context.
        DispatchQueue.main.async {
            guard let topVC = topViewControllerForPresentation() else { return }
            let photoCountBeforePicker = photoAuth.selectedPhotoCount
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    photoAuth.refreshStatus()
                    // No automatic rescan here; blogs use existing trips/photos.
                    // We only care about updated access for future scans/edits.
                    let _ = photoCountBeforePicker
                }
            }
        }
    }

    /// Image assets readable with the current Photos authorization (the limited subset when access is `.limited`).
    private func imageAssetLocalIdentifiersAccessible() -> Set<String> {
        var set = Set<String>()
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        set.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            set.insert(asset.localIdentifier)
        }
        return set
    }

    /// System limited-library UI (same as Trips / Settings **Select more photos**). Imports any newly shared assets into this place stop.
    private func presentLimitedLibraryPickerForManageStopImport(dayId: UUID, stopId: UUID) {
        DispatchQueue.main.async {
            guard let topVC = topViewControllerForPresentation() else { return }
            let idsBefore = imageAssetLocalIdentifiersAccessible()
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    photoAuth.refreshStatus()
                    let idsAfter = imageAssetLocalIdentifiersAccessible()
                    let added = idsAfter.subtracting(idsBefore)
                    guard !added.isEmpty else { return }
                    Task { @MainActor in
                        await importLibraryPhotosIntoStop(assetIdentifiers: Array(added), dayId: dayId, stopId: stopId)
                    }
                }
            }
        }
    }

    private func topViewControllerForPresentation() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    private var tripDurationText: String {
        let range = RecapBlogDay.tripCoverDateRangeText(from: draft.days)
        guard !range.isEmpty else { return "" }
        let dayCount = draft.days.count
        return "\(range) · \(dayCount) day\(dayCount == 1 ? "" : "s")"
    }

    private var tripDateText: String {
        RecapBlogDay.tripCoverDateRangeText(from: draft.days)
    }

    /// Day filter fixed at top; scrollable content (map + timeline) sits below it.
    private var dayFilterSection: some View {
        let processingIndex = createdRecapStore.processingDayIndexByBlogId[blogId]
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
            .onChange(of: selectedDayIndex) { _, newIndex in
                guard let day = day(at: newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    // anchor: nil = minimum scroll to make the item visible; no-op if already visible.
                    proxy.scrollTo(day.id, anchor: nil)
                }
            }
        }
    }

    private var recapCameraQuickCaptureButton: some View {
        Button {
            openCameraCaptureFromRecap()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.blue)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open In-App Camera")
    }

    /// Shows quick capture only while the recap is truly "on the go":
    /// latest included photo was taken within the last 24 hours.
    private var shouldShowRecapCameraQuickCapture: Bool {
        isOnTheGoBlogForRescan
    }

    private func openCameraCaptureFromRecap() {
        if let blog = createdRecapStore.visibleRecents.first(where: { $0.sourceTripId == blogId }) {
            let fallbackEndDate = draft.days.last?.date ?? Date()
            let endDate = blog.tripEndDate ?? fallbackEndDate
            OnTheGoTripStore.markTripAsActive(
                blogId: blogId,
                title: blog.title,
                tripEndDate: endDate,
                country: blog.countryName
            )
        }
        AppAnalytics.track(.appInAppCameraOpen)
        showCameraCaptureFromRecap = true
    }

    private func dayPill(title: String, index: Int, day: RecapBlogDay, processingIndex: Int?) -> some View {
        let isSelected = selectedDayIndex == index
        let isProcessed = day.isPlaceNamesResolved
        let isProcessing = processingIndex == index
        let isUnprocessed = !isProcessed && !isProcessing
        let isBlocked = isUnprocessed || isProcessing
        let hasNewMoments = newMomentsDayIndices.contains(index)
        return Button {
            if isBlocked {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showUnprocessedDayAlert = true
                }
            } else {
                // Day selected from bottom pills: no slide motion, render ASAP.
                shouldAnimateDayChange = false
                withTransaction(Transaction(animation: nil)) {
                    selectedDayIndex = index
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(recapChromeForeground)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : (isUnprocessed ? .secondary.opacity(0.6) : .secondary))
                    .opacity(isUnprocessed ? 0.7 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue : recapDayPillIdleBackground)
            .clipShape(Capsule())
            .overlay {
                if hasNewMoments {
                    Capsule()
                        .stroke(Self.newMomentsAccent.opacity(isSelected ? 0.55 : 0.9), lineWidth: 2)
                }
            }
            .opacity(isUnprocessed ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasNewMoments ? "\(title), new moments" : title)
    }

    @ViewBuilder
    private func mapCard(for day: RecapBlogDay) -> some View {
        ZStack(alignment: .topTrailing) {
            MapDayView(
                placeStops: day.placeStops,
                onTap: {
                    fullScreenMapFocusedPlaceId = nil
                    fullScreenMapDay = day
                },
                onAnnotationTap: { stopId in
                    fullScreenMapFocusedPlaceId = stopId
                    fullScreenMapDay = day
                }
            )
            Button {
                fullScreenMapFocusedPlaceId = nil
                fullScreenMapDay = day
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(recapMapExpandBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .allowsHitTesting(!isDayPagerHorizontalDragActive)
        .id(RecapBlogScrollAnchor.mapForDay(day.id))
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
                    Text("Restore Hidden Places")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(recapChromeForeground)
                    Text(draft.removedPlaceStops.count == 1
                         ? "1 place was hidden"
                         : "\(draft.removedPlaceStops.count) places were hidden")
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
            .background(recapCardBackground)
            .appChromeCornerRadius(12)
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 12)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Inline card shown when new photos were detected for this recent blog.
    private var newMomentsCard: some View {
        Button {
            AppAnalytics.track(.blogMoreMemories(blogId: blogId.uuidString))
            withAnimation(.easeInOut(duration: 0.3)) {
                showNewMomentsReviewSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Self.newMomentsAccent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Self.newMomentsAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(newMomentsGroupCount) moment\(newMomentsGroupCount == 1 ? "" : "s") found")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(recapChromeForeground)
                    Text("Tap to review and add to your blog")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(recapCardBackground)
        .appChromeCornerRadius(12)
        .overlay(
            RoundedRectangle(appChromeBaseRadius: 12)
                .stroke(Self.newMomentsAccent.opacity(0.35), lineWidth: 1)
        )
    }

    private func daySection(day: RecapBlogDay, dayIndex: Int, screenHeight: CGFloat) -> some View {
        let mediaTileHeight = Self.placeMediaTileHeight(for: screenHeight)
        let isDayLoading = !day.isPlaceNamesResolved
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(day.shortDateText)
                    .font(.blog(selectedBlogFont, size: 20, bold: true))
                    .foregroundColor(recapChromeForeground)
                if isDayLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.secondary)
                } else if let weather = day.weather {
                    let temps = weather.temperatureHighLow(for: WeatherTemperatureUnit(rawValue: weatherTemperatureUnitRaw) ?? .fahrenheit)
                    let chip = HStack(spacing: 4) {
                        Text(weather.emoji)
                            .font(.body)
                        Text("\(temps.high)\(temps.suffix)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(recapChromeForeground.opacity(0.88))
                        Text("/")
                            .font(.subheadline)
                            .foregroundColor(recapSecondaryOnChrome)
                        Text("\(temps.low)\(temps.suffix)")
                            .font(.subheadline)
                            .foregroundColor(recapSecondaryOnChrome.opacity(0.95))
                        if day.weatherIsManual {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(recapSecondaryOnChrome.opacity(0.85))
                        }
                    }
                    if isEditMode {
                        Button { weatherEditDayId = day.id } label: { chip }
                            .buttonStyle(.plain)
                    } else {
                        chip
                    }
                } else {
                    if isEditMode {
                        Button { weatherEditDayId = day.id } label: {
                            Image(systemName: "sun.max")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "sun.max")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()

                // Scissors on Day N (dayIdx > 0) means "split before Day N":
                // Part 1 = Days 1..N-1, Part 2 = Days N..end. Not shown on Day 1.
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
                            .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.orange.opacity(0.12))
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
                        if let splitIdx = dayIndexToSplit, splitIdx > 0, splitIdx < draft.days.count {
                            let p1 = CreatedRecapBlogStore.formatDateRange(
                                start: draft.days.first?.dateAlignedWithShortDateText,
                                end: draft.days[splitIdx - 1].dateAlignedWithShortDateText
                            ) ?? "—"
                            let p2 = CreatedRecapBlogStore.formatDateRange(
                                start: draft.days[splitIdx].dateAlignedWithShortDateText,
                                end: draft.days.last?.dateAlignedWithShortDateText
                            ) ?? "—"
                            Text("This will create two separate blogs:\n\nPart 1: \(p1)\nPart 2: \(p2)")
                        } else {
                            Text("Split this blog into two separate blogs.")
                        }
                    }
                }
            }
            .padding(.top, 4)

            // Day-level caption — right below the date header
            dayCaptionRow(day: day)

            if isEditMode, LocalLLMStoryCaptionGenerator.isCapable {
                let dayCaptionEmpty = (day.dayCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasAIDayNarrative = (day.dayNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                if generatingNarrativeDayId == day.id {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.secondary)
                            .padding(.trailing, 0)
                    }
                    .padding(.top, -8)
                } else if dayCaptionEmpty {
                    HStack {
                        Spacer()
                        Button {
                            triggerDayNarrative(day: day)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "wand.and.sparkles")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Generate story")
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, -8)
                } else if hasAIDayNarrative {
                    HStack(spacing: 12) {
                        Spacer()
                        Button {
                            if let dayIdx = draft.days.firstIndex(where: { $0.id == day.id }) {
                                draft.days[dayIdx].dayNarrative = nil
                                draft.days[dayIdx].dayCaption = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption)
                                Text("Revert")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            triggerDayNarrative(day: day)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "wand.and.sparkles")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Regenerate")
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, -8)
                }
            }

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
                    reelAutoplay: blogReelAutoplay,
                    mediaTileHeight: mediaTileHeight,
                    onDelete: {
                        removePlaceStop(dayId: day.id, stopId: stop.id)
                    },
                    onKebab: {
                        overflowStop = OverflowItem(dayId: day.id, stop: stop)
                    },
                    onRemovePhoto: { photoId in
                        removePhoto(dayId: day.id, stopId: stop.id, photoId: photoId)
                    },
                    onPhotoTapped: { photo in
                        placePhotoModalItem = PlacePhotoModalItem(dayId: day.id, stopId: stop.id, initialPhotoId: photo.id)
                    },
                    onCaptionFocus: { focusId in scrollToStopId = focusId },
                    onNavigate: { openNavigation(for: stop) },
                    onEditName: {
                        AppAnalytics.track(.blogPlaceChangeName(blogId: blogId.uuidString, placeId: stop.id.uuidString))
                        showEditNameForStop = stop
                    },
                    onEditCategory: isEditMode ? { placeCategoryPickerTarget = PlaceCategoryPickerTarget(id: stop.id) } : nil,
                    onDoneEditingStory: { stopId, isPlaceNote, photoId in
                        syncStoryToCloudIfNeeded(stopId: stopId, isPlaceNote: isPlaceNote, photoId: photoId)
                    },
                    onGeneratePlaceStory: { userText in
                        guard let currentStop = placeStop(dayId: day.id, stopId: stop.id) else { return userText }
                        return await StoryCaptionService.shared.enhancePlaceStory(stop: currentStop, userText: userText, dayDate: day.date)
                    },
                    onGenerateOverallStory: { userText in
                        guard let currentStop = placeStop(dayId: day.id, stopId: stop.id) else { return userText }
                        let captions = currentStop.photos.filter(\.isIncluded).map { $0.caption ?? "" }
                        return await StoryCaptionService.shared.enhanceOverallPlaceStory(stop: currentStop, userText: userText, dayDate: day.date, photoCaptions: captions)
                    },
                    onGeneratePhotoCaption: { photo, userText in
                        await StoryCaptionService.shared.enhanceCaption(photo: photo, userText: userText, placeName: stop.placeTitle, placeSubtitle: stop.placeSubtitle)
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
                    },
                    onAIOverallStoryApplied: {
                        markOverallStoryAI(dayId: day.id, stopId: stop.id)
                    },
                    onEditPlaceCaption: {
                        placeCaptionEditItem = PlaceCaptionEditItem(dayId: day.id, stopId: stop.id)
                    },
                    isGeneratingCaption: generatingCaptionStopId == stop.id,
                    isGeneratingNarrative: generatingNarrativeStopId == stop.id,
                    onTellPlaceStory: {
                        triggerPlaceNarrative(dayId: day.id, stopId: stop.id, dayDate: day.date)
                    },
                    onRevertPlaceStory: {
                        guard let dayIdx = draft.days.firstIndex(where: { $0.id == day.id }),
                              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stop.id }) else { return }
                        draft.days[dayIdx].placeStops[stopIdx].placeNarrative = nil
                        persistRecapBlogDetail()
                    },
                    onSentimentChanged: { newValue in
                        guard let dayIdx = draft.days.firstIndex(where: { $0.id == day.id }),
                              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stop.id }) else { return }
                        AppAnalytics.track(.blogSentimentAdjustment(blogId: blogId.uuidString))
                        draft.days[dayIdx].placeStops[stopIdx].sentiment = newValue
                        persistRecapBlogDetail()
                        syncSentimentToCloudIfNeeded(dayId: day.id, stopId: stop.id)
                    },
                    onManagePhotos: {
                        AppAnalytics.track(.blogPlaceManagePhoto(blogId: blogId.uuidString, placeId: stop.id.uuidString))
                        openManagePhotos(dayId: day.id, stopId: stop.id)
                    }
                )
                .id(stop.id)
                
                if index < day.placeStops.count - 1 {
                    let nextStop = day.placeStops[index + 1]
                    let manualMode = stop.transportModeToNextStop
                    let effectiveMode: TravelMode? = manualMode ?? {
                        guard let a = stop.representativeLocation?.clCoordinate,
                              let b = nextStop.representativeLocation?.clCoordinate,
                              a.latitude.isFinite, a.longitude.isFinite,
                              b.latitude.isFinite, b.longitude.isFinite else { return nil }
                        return TravelMode.detect(from: stop, to: nextStop)
                    }()
                    let pillTint: Color = effectiveMode.map { Color(uiColor: $0.tintColor) } ?? .secondary
                    let isManual = manualMode != nil

                    HStack(alignment: .center, spacing: 10) {
                        // Route connector: stub lines above/below the pill to imply a path
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(pillTint.opacity(0.35))
                                .frame(width: 2, height: 8)
                            Button {
                                transportModePickerItem = OverflowItem(dayId: day.id, stop: stop)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: effectiveMode?.sfSymbolName ?? "arrow.down")
                                        .font(.caption2.weight(.semibold))
                                    Text(effectiveMode?.displayName ?? "—")
                                        .font(.caption.weight(.medium))
                                    if isEditMode {
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 8, weight: .semibold))
                                            .opacity(0.55)
                                    }
                                }
                                .foregroundColor(pillTint.opacity(isManual ? 1.0 : 0.75))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(pillTint.opacity(isManual ? 0.14 : 0.09))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(pillTint.opacity(isManual ? 0.3 : 0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            Rectangle()
                                .fill(pillTint.opacity(0.35))
                                .frame(width: 2, height: 8)
                        }

                        if let dist = distanceString(from: stop, to: nextStop) {
                            Text(dist)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        let sameNameDetected = !stop.placeTitle.isEmpty &&
                            stop.placeTitle.trimmingCharacters(in: .whitespaces).lowercased() ==
                            nextStop.placeTitle.trimmingCharacters(in: .whitespaces).lowercased()
                        if isEditMode && sameNameDetected {
                            Button {
                                mergePlaceStops(dayId: day.id, firstStopId: stop.id, secondStopId: nextStop.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.triangle.merge")
                                        .font(.subheadline.weight(.bold))
                                    Text("Same place? Merge")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.45), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        } else if isEditMode {
                            Button {
                                mergePlaceStops(dayId: day.id, firstStopId: stop.id, secondStopId: nextStop.id)
                            } label: {
                                Label("Merge groups", systemImage: "arrow.triangle.merge")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.vertical, 2)
                }
            }
        }
        .id("day-section-\(day.id)")
    }

    /// Full-screen fade overlay (not a sheet) so the photo stays fixed and the caption bar can sit above the keyboard quickly.
    @ViewBuilder
    private func placePhotoModalOverlay(item: PlacePhotoModalItem) -> some View {
        Group {
            if let stop = placeStop(dayId: item.dayId, stopId: item.stopId) {
                let includedPhotos = stop.photos.filter(\.isIncluded).filter(\.hasDisplayableLocalBacking)
                if !includedPhotos.isEmpty {
                    PlacePhotoModalView(
                        placeTitle: bindingForPlaceTitle(stopId: item.stopId),
                        placeSubtitle: stop.placeSubtitle,
                        initialPlaceCategory: stop.placeCategory,
                        photos: includedPhotos,
                        initialPhotoId: includedPhotos.contains(where: { $0.id == item.initialPhotoId }) ? item.initialPhotoId : includedPhotos[0].id,
                        stopDigitizedTime: stop.visitedTimeDigitized,
                        blogIsEditMode: isEditMode,
                        recapBlogIsReadOnly: false,
                        openInCaptionEditor: item.openInCaptionEditor,
                        hideChromeDoneFromCaptionEditorSheet: item.hideChromeDoneFromCaptionEditorSheet,
                        showAssetTimeMetadata: isEditMode,
                        autoFocusCaption: item.autoFocusCaption,
                        presentation: .fullscreen(source: .blogRecap),
                        photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
                        onDismiss: {
                            persistRecapBlogDetail()
                            placePhotoModalItem = nil
                        },
                        onDismissSlideBegan: {
                            revealRecapNavigationDuringPhotoDismiss = true
                        },
                        onGenerateCaption: { photo, placeName, placeSubtitle, userText in
                            await StoryCaptionService.shared.enhanceCaption(
                                photo: photo,
                                userText: userText,
                                placeName: placeName,
                                placeSubtitle: placeSubtitle
                            )
                        },
                        onAICaptionApplied: { photoId in
                            markPhotoCaptionAI(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                        },
                        onPhotoCaptionManuallyEdited: { photoId in
                            markPhotoCaptionManual(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                        },
                        onRemovePhoto: { photoId in
                            removePhoto(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                        },
                        onSavePlaceName: { name, category, coord, subtitleLine in
                            updatePlaceTitle(stopId: item.stopId, to: name, category: category, coordinate: coord, placeSubtitleLine: subtitleLine)
                        },
                        onSavePlaceCategory: { newCategory in
                            updatePlaceCategory(stopId: item.stopId, category: newCategory)
                        },
                        onCaptionCommitted: { photoId in
                            syncStoryToCloudIfNeeded(stopId: item.stopId, isPlaceNote: false, photoId: photoId)
                        }
                    )
                } else {
                    recapScreenBackground
                        .onAppear {
                            persistRecapBlogDetail()
                            placePhotoModalItem = nil
                        }
                }
            } else {
                recapScreenBackground
                    .onAppear {
                        persistRecapBlogDetail()
                        placePhotoModalItem = nil
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Must stay clear: a black backing matches the modal and hides the real blog until this layer is removed (flash after dismiss).
        .background(Color.clear)
    }

    @ViewBuilder
    private func unsavedSplitModal(splitIdx: Int) -> some View {
        // splitIdx is the 0-based array index of the day where scissors was tapped.
        // Scissors on Day N means "split before Day N": Part 1 = Days 1..N-1, Part 2 = Days N..end.
        let part1Days = Array(draft.days[0..<splitIdx])
        let part2Days = Array(draft.days[splitIdx...])

        let part1StartDate = part1Days.first?.dateAlignedWithShortDateText
        let part1EndDate = part1Days.last?.dateAlignedWithShortDateText
        let part1DateStr = CreatedRecapBlogStore.formatDateRange(start: part1StartDate, end: part1EndDate) ?? "Unknown Date"

        let part2StartDate = part2Days.first?.dateAlignedWithShortDateText
        let part2EndDate = part2Days.last?.dateAlignedWithShortDateText
        let part2DateStr = CreatedRecapBlogStore.formatDateRange(start: part2StartDate, end: part2EndDate) ?? "Unknown Date"

        let part1Cities = part1Days
            .flatMap(\.placeStops)
            .compactMap { $0.placeSubtitle }
            .filter { !$0.isEmpty }

        var seen1 = Set<String>()
        let part1CityString = part1Cities.filter { seen1.insert($0).inserted }.joined(separator: ", ")

        let part2Cities = part2Days
            .flatMap(\.placeStops)
            .compactMap { $0.placeSubtitle }
            .filter { !$0.isEmpty }

        var seen2 = Set<String>()
        let part2CityString = part2Cities.filter { seen2.insert($0).inserted }.joined(separator: ", ")

        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Which part do you want to continue editing?")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 16) {
                Button {
                    unsavedSplitPromptIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitUnsavedBlog(afterDayIndex: splitIdx - 1, keepPart: 1)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Part 1")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(part1DateStr)
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
                    .appChromeCornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    unsavedSplitPromptIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        splitUnsavedBlog(afterDayIndex: splitIdx - 1, keepPart: 2)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Part 2")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(part2DateStr)
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
                    .appChromeCornerRadius(12)
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
                        .appChromeCornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .presentationDetents([.fraction(0.50)])
        .presentationDragIndicator(.visible)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Applies per-day geocoding / scoring / weather from the store while the user is in edit mode, without replacing the whole draft (preserves other in-progress edits).
    private func mergeResolvedBlogDaysFromStore(updated: RecapBlogDetail, into draft: inout RecapBlogDetail) {
        guard updated.id == draft.id, updated.days.count == draft.days.count else { return }
        for i in draft.days.indices where !draft.days[i].isPlaceNamesResolved && updated.days[i].isPlaceNamesResolved {
            var merged = updated.days[i]
            if let caption = draft.days[i].dayCaption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.dayCaption = caption
            }
            draft.days[i] = merged
        }
        // In-app camera captures inject into already-resolved days in the store; merge new stops/photos
        // into the local draft so the map and Manage Photos see them without leaving edit mode.
        for i in draft.days.indices where draft.days[i].isPlaceNamesResolved && updated.days[i].isPlaceNamesResolved {
            mergePlaceStopsFromStore(updatedStops: updated.days[i].placeStops, into: &draft.days[i].placeStops)
            // Day 0 is resolved before weather runs; applyWeather may fill it in while later days geocode.
            if !draft.days[i].weatherIsManual, draft.days[i].weather == nil, let weather = updated.days[i].weather {
                draft.days[i].weather = weather
            }
        }
        // Sync cover photo from store: quality-based selection updates selectedCoverPhotoIdentifier
        // in the store as scoring completes, but the local draft never received that update.
        draft.selectedCoverPhotoIdentifier = updated.selectedCoverPhotoIdentifier
    }

    /// Merges background store updates (camera inject, rescan) into an in-progress draft day without dropping user edits.
    private func mergePlaceStopsFromStore(updatedStops: [PlaceStop], into draftStops: inout [PlaceStop]) {
        for updatedStop in updatedStops {
            if let stopIdx = draftStops.firstIndex(where: { $0.id == updatedStop.id }) {
                mergePhotosFromStore(updatedPhotos: updatedStop.photos, into: &draftStops[stopIdx].photos)
            } else {
                draftStops.append(updatedStop)
            }
        }
        draftStops.sort { ($0.photos.first?.timestamp ?? .distantFuture) < ($1.photos.first?.timestamp ?? .distantFuture) }
        for i in draftStops.indices {
            draftStops[i].orderIndex = i
        }
    }

    /// Appends photos newly injected in the store; propagates quality scores without overwriting manual include toggles.
    private func mergePhotosFromStore(updatedPhotos: [RecapPhoto], into draftPhotos: inout [RecapPhoto]) {
        let existingIds = Set(draftPhotos.map(\.id))
        let existingLocalIds = Set(draftPhotos.compactMap(\.localIdentifier))
        for updatedPhoto in updatedPhotos {
            if let photoIdx = draftPhotos.firstIndex(where: { $0.id == updatedPhoto.id }) {
                guard draftPhotos[photoIdx].qualityScore == nil,
                      updatedPhoto.qualityScore != nil else { continue }
                draftPhotos[photoIdx].qualityScore = updatedPhoto.qualityScore
                draftPhotos[photoIdx].isFavorite = updatedPhoto.isFavorite
                continue
            }
            if let lid = updatedPhoto.localIdentifier, existingLocalIds.contains(lid) { continue }
            draftPhotos.append(updatedPhoto)
        }
        draftPhotos.sort { $0.timestamp < $1.timestamp }
    }

    private func loadDraftIfNeeded() {
        guard !hasFinishedInitialLoad else { return }
        if let saved = createdRecapStore.getBlogDetail(blogId: blogId) {
            draft = saved
            hasFinishedInitialLoad = true
            if draftSnapshot == nil { draftSnapshot = draft }
            Task { @MainActor in
                let didChange = await pruneEmptyPhotoGroupsFromDraftAsync()
                if didChange {
                    persistRecapBlogDetail()
                }
            }
            // Score already-geocoded days (day 0) and process remaining days in background.
            Task { @MainActor in await createdRecapStore.scoreResolvedDaysInBackground(blogId: blogId) }
            Task { @MainActor in await createdRecapStore.continueGeocodingDays(blogId: blogId) }
            // Check for new moments for this recent blog (if it passes the recency + cutoff checks).
            checkForNewMomentsIfRecent()
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
            return
        }
        guard let trip = initialTrip ?? createdRecapStore.tripDraft(for: blogId) else {
            hasFinishedInitialLoad = true
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
            return
        }
        Task { @MainActor in
            let detail = await createdRecapStore.buildBlogDetailFirstDayOnly(from: trip)
            createdRecapStore.saveBlogDetail(detail, asDraft: true)
            draft = detail
            hasFinishedInitialLoad = true
            if draftSnapshot == nil { draftSnapshot = draft }
            let didChange = await pruneEmptyPhotoGroupsFromDraftAsync()
            if didChange {
                createdRecapStore.saveBlogDetail(draft, asDraft: true)
            }
            // Process remaining days in background (rate limit: 50 geocode/min).
            await createdRecapStore.continueGeocodingDays(blogId: blogId)
            refreshMissingPhotosTooltipVisibility()
            refreshBlogReelAutoplayEnabled()
        }
    }

    private func refreshBlogReelAutoplayEnabled() {
        let enabled = hasFinishedInitialLoad
            && !isEditMode
            && !showStoryMode
            && !showPanorama
            && !isExportingPDF
            && placePhotoModalItem == nil
        blogReelAutoplay.setAutoplayEnabled(enabled)
    }

    private func refreshMissingPhotosTooltipVisibility() {
        guard hasFinishedInitialLoad else { return }
        let blockingChrome = showStoryMode || showPanorama || isExportingPDF || showAuth || showGuestSecondSaveLimitModal
            || placePhotoModalItem != nil || dayCaptionEditItem != nil || placeCaptionEditItem != nil
            || photoCaptionEditItem != nil || earlyAccessSheetPresented || showTripNarrativeEdit
        if blockingChrome {
            if showMissingPhotosTooltip {
                withAnimation(.easeInOut(duration: 0.2)) { showMissingPhotosTooltip = false }
            }
            return
        }
        let recap = createdRecapStore.recents.first { $0.sourceTripId == blogId }
        let eligible = BlogMissingPhotosEvaluator.shouldOfferTooltip(
            isSignedIn: authService.currentUser != nil,
            ownerScope: recap?.ownerScope,
            detail: draft,
            recapSummary: recap,
            isSuppressedForBlog: MissingPhotosTooltipPresentationStore.isSuppressed(blogId: blogId)
        )
        let show = eligible && !sessionDismissedMissingPhotosTooltip
        withAnimation(.easeInOut(duration: 0.25)) {
            showMissingPhotosTooltip = show
        }
    }

    private func scheduleMissingPhotosTooltipRefresh() {
        missingPhotosTooltipDebounceTask?.cancel()
        missingPhotosTooltipDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            refreshMissingPhotosTooltipVisibility()
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
            recomputeNewMomentsGroupCount()
            isCheckingNewMoments = false
            if !photos.isEmpty {
                BlogMenuIndicatorStore.shared.noteMomentsAdded(to: blogId)
                refreshHighlightedNewMomentsDays()
                if hasFinishedInitialLoad {
                    focusNewMomentsDayIfNeeded()
                }
            }
            considerPresentingNewMomentsReviewSheetIfNeeded()
        }
    }

    /// Presents the same bottom sheet as the “N moments found” card when new photos are detected, once per batch until dismissed (Later, swipe, or scrim).
    private func considerPresentingNewMomentsReviewSheetIfNeeded() {
        guard !showStoryMode, !isExportingPDF,
              newMomentsPlaceCount > 0,
              createdRecapStore.recents.contains(where: { $0.sourceTripId == blogId }) else { return }
        let batchMax = newMomentPhotos.map(\.timestamp).max() ?? .distantPast
        if let dismissed = NewMomentsPullUpPresentationStore.dismissedBatchMaxTimestamp(for: blogId),
           batchMax <= dismissed {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard newMomentsPlaceCount > 0, !showStoryMode, !isExportingPDF else { return }
            focusNewMomentsDayIfNeeded(force: true)
            withAnimation(.easeInOut(duration: 0.3)) {
                showNewMomentsReviewSheet = true
            }
        }
    }

    private func dismissNewMomentsReviewWithoutAdding() {
        guard let maxDate = newMomentPhotos.map(\.timestamp).max() else {
            withAnimation(.easeInOut(duration: 0.3)) { showNewMomentsReviewSheet = false }
            return
        }
        NewMomentsPullUpPresentationStore.recordDismissal(for: blogId, batchMaxPhotoDate: maxDate)
        // Keep newMomentPhotos intact so the inline card remains tappable after "Later".
        withAnimation(.easeInOut(duration: 0.3)) {
            showNewMomentsReviewSheet = false
        }
    }

    private func addNewMomentsToBlog(_ selected: [MockPhoto]) {
        guard !selected.isEmpty else { return }
        AppAnalytics.track(.blogMoreMemoriesCreateBlog(sourceBlogId: blogId.uuidString))
        let batchMax = newMomentPhotos.map(\.timestamp).max()
        newMomentPhotos = []
        newMomentsGroupCount = 0
        withAnimation(.easeInOut(duration: 0.3)) {
            showNewMomentsReviewSheet = false
        }
        Task { @MainActor in
            await createdRecapStore.injectPhotosAndWait(
                selected,
                intoSourceTripId: blogId,
                notifyMenuIndicator: false
            )
            if let maxDate = batchMax {
                ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blogId)
                if let created = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) {
                    ScanSessionStore.saveBlogNotifiedDate(maxDate, for: created.id)
                }
            }
            NewMomentsPullUpPresentationStore.clear(for: blogId)
            if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
                draft = updated
                draftSnapshot = updated
            }
            if let idx = draft.preferredDayIndexForNewMoments(from: selected),
               draft.days.indices.contains(idx) {
                highlightedNewMomentsDayIndices = [idx]
                hasAutoScrolledToNewMomentsDay = true
                withAnimation(.easeInOut(duration: 0.35)) {
                    selectedDayIndex = idx
                }
            }
            BlogMenuIndicatorStore.shared.clear(sourceTripId: blogId)
        }
    }

    private func rescanAllMomentsFromStart() {
        guard isOnTheGoBlogForRescan else { return }
        Task { @MainActor in
            isCheckingNewMoments = true
            let result = await createdRecapStore.performFullRescanAndInject(blogId: blogId)
            isCheckingNewMoments = false

            if result.newStops == 0 && result.addedToExisting == 0 {
                showNoNewMomentsAlert = true
            } else {
                // Reload draft so newly injected photos are visible immediately.
                if let updated = createdRecapStore.getBlogDetail(blogId: blogId) {
                    draft = updated
                    draftSnapshot = updated
                }
                var parts: [String] = []
                if result.newStops > 0 {
                    parts.append("\(result.newStops) new place\(result.newStops == 1 ? "" : "s") added")
                }
                if result.addedToExisting > 0 {
                    parts.append("\(result.addedToExisting) photo\(result.addedToExisting == 1 ? "" : "s") added to existing places (unselected)")
                }
                rescanResultMessage = parts.joined(separator: "\n")
                showRescanResultAlert = true
            }
        }
    }

    private func dismissNewMoments() {
        newMomentPhotos = []
        newMomentsGroupCount = 0
        clearHighlightedNewMomentsDays()
    }

    private func dismissAndSuppressNewMoments() {
        // Save cutoff so these photos don't resurface until genuinely new ones appear.
        if let maxDate = newMomentPhotos.map(\.timestamp).max() {
            ScanSessionStore.saveBlogNotifiedDate(maxDate, for: blogId)
            // Also save under `CreatedRecapBlog.id` because Trips-flow scan logic uses that UUID.
            if let created = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) {
                ScanSessionStore.saveBlogNotifiedDate(maxDate, for: created.id)
            }
        }
        NewMomentsPullUpPresentationStore.clear(for: blogId)
        newMomentPhotos = []
        newMomentsGroupCount = 0
        clearHighlightedNewMomentsDays()
        BlogMenuIndicatorStore.shared.clear(sourceTripId: blogId)
        withAnimation(.easeInOut(duration: 0.3)) {
            showNewMomentsReviewSheet = false
        }
    }

    /// All included photos across all days/stops, for cover photo selection.
    private var allIncludedPhotos: [RecapPhoto] {
        draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
    }

    /// “On the go” for rescan: latest included photo is from the last 24 hours.
    private var isOnTheGoBlogForRescan: Bool {
        guard let latest = allIncludedPhotos.map(\.timestamp).max() else { return false }
        return Date().timeIntervalSince(latest) < 24 * 3600
    }

    private var shareMenuDetentHeight: CGFloat {
        // Primary card (3 rows: Social Post Studio, Slideshow Video, PDF)
        // + secondary card (1 row: Share with Bloggo) with a gap between them.
        510
    }

    private var shareText: String {
        let placeCount = draft.days.flatMap(\.placeStops).count
        if placeCount > 0 {
            return "\(draft.title) – My Recap Blog (\(placeCount) places)"
        }
        return "\(draft.title) – My Recap Blog"
    }

    private var shareItems: [Any] {
        if blogIsInCloud,
           let blog = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }),
           let key = blog.blogKey {
            let user = AuthService.shared.currentUser
            let username = user?.username ?? user?.displayName ?? user?.email ?? "user"
            if let url = SecureShareToken.shareURL(username: username, blogKey: key) {
                return [LinkCaptionActivityItemSource(url: url, caption: shareText)]
            }
        }
        return [shareText]
    }

    private var hasEarlyCloudAccess: Bool {
        hasJoinedEarlyAccess || EarlyAccessManager.shared.hasRegistered
    }

    @ViewBuilder
    private func shareYourBlogSheetContent() -> some View {
        ZStack(alignment: .top) {
            shareYourBlogSheetMenuBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(shareYourBlogSheetPhase == .menu ? 1 : 0)
                .allowsHitTesting(shareYourBlogSheetPhase == .menu)

            guestShareWebLinkRequiresCloudBackupSheetBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(shareYourBlogSheetPhase == .guestWebLinkCloudBackup ? 1 : 0)
                .allowsHitTesting(shareYourBlogSheetPhase == .guestWebLinkCloudBackup)

            guestShareBloggoQRSheetBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(shareYourBlogSheetPhase == .guestBloggoQR ? 1 : 0)
                .allowsHitTesting(shareYourBlogSheetPhase == .guestBloggoQR)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: shareYourBlogSheetPhaseTransitionDuration), value: shareYourBlogSheetPhase)
    }

    /// Main “Share Your Blog” options list inside the pull-up sheet.
    @ViewBuilder
    private func shareYourBlogSheetMenuBody() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "book.pages")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text("Share Your Blog")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Choose how you want to share")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 18)

            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    shareOptionRow(
                        title: "Post to Social Media",
                        subtitle: "TikTok, Instagram, and others..",
                        icon: "rectangle.stack",
                        iconColor: .white,
                        titleColor: .white
                    ) {
                        AppAnalytics.track(.blogShareSocialMedia(blogId: blogId.uuidString))
                        showShareYourBlogSheet = false
                        showSocialPostStudio = true
                    }
                    Divider().padding(.leading, 52)
                    shareOptionRow(
                        title: "Stitch Reels",
                        subtitle: "Video from your moments",
                        icon: "video.badge.plus"
                    ) {
                        AppAnalytics.track(.blogShareStitchReels(blogId: blogId.uuidString))
                        showShareYourBlogSheet = false
                        showVideoExportOptions = true
                    }
                    Divider().padding(.leading, 52)
                    shareOptionRow(
                        title: "Export as PDF",
                        subtitle: "Save as a storybook",
                        icon: "doc.richtext"
                    ) {
                        showShareYourBlogSheet = false
                        showStoryModePDFOptions = true
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .appChromeCornerRadius(14)

                VStack(spacing: 0) {
                    shareOptionRow(
                        title: "Share with Bloggo",
                        subtitle: "Open instantly in the app",
                        icon: "qrcode"
                    ) {
                        if authService.isSignedIn {
                            pendingBloggoQRSheetAfterShareDismiss = true
                            showShareYourBlogSheet = false
                        } else {
                            shareYourBlogSheetPhase = .guestBloggoQR
                        }
                    }
                    .opacity(!authService.isSignedIn ? 0.4 : 1)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .appChromeCornerRadius(14)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 18)
        }
        .padding(.top, 26)
    }

    /// Guest prompt: same pull-up sheet, replaces the share menu (no separate full-screen overlay).
    @ViewBuilder
    private func guestShareWebLinkRequiresCloudBackupSheetBody() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(spacing: 4) {
                    Text("Share Web Link")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    Text("Requires Cloud Backup")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }

                Text("""
Sign in to your Bloggo account to join early access and enable cloud backup for sharing.

Your blog remains private unless you choose to share it.
""")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    shareYourBlogSheetPhase = .menu
                    showShareYourBlogSheet = false
                    pendingWebLinkAfterAuth = true
                    showAuth = true
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                }

                Button {
                    shareYourBlogSheetPhase = .menu
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 26)
    }

    /// Guest prompt: sign in to use Bloggo QR sharing (same pull-up sheet as the share menu).
    @ViewBuilder
    private func guestShareBloggoQRSheetBody() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "qrcode")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                Text("Share Between Bloggo Users")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Sign in to generate a QR code that another Bloggo user can scan with their phone to instantly open your blog in the app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    shareYourBlogSheetPhase = .menu
                    showShareYourBlogSheet = false
                    pendingBloggoQRAfterAuth = true
                    showAuth = true
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                }

                Button {
                    shareYourBlogSheetPhase = .menu
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 26)
    }

    private func shareOptionRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color = .primary,
        titleColor: Color = .primary,
        subtitleColor: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(titleColor)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(subtitleColor)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleShareWebLinkTap() {
        guard authService.isSignedIn else {
            shareYourBlogSheetPhase = .guestWebLinkCloudBackup
            showShareYourBlogSheet = true
            return
        }
        guard hasEarlyCloudAccess else {
            showCloudSharingComingSoonAlert = true
            return
        }
        startWebLinkShareFlow()
    }

    private func startWebLinkShareFlow() {
        guard !isUploading else { return }
        if blogIsInCloud {
            presentWebLinkShareSheetIfPossible()
        } else {
            uploadBlogPhotos(openShareAfterSuccess: true)
        }
    }

    private func presentWebLinkShareSheetIfPossible() {
        if blogIsInCloud,
           let blog = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }),
           blog.blogKey != nil {
            showShareSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showShareSheet = true
            }
        }
    }

    /// From panorama caption tap, open the place pull-up focused on that photo's caption.
    private func openPlaceModalFromPanoramaCaptionTap(localIdentifier: String) {
        guard !localIdentifier.isEmpty else { return }
        for day in draft.days {
            for stop in day.placeStops {
                if let photo = stop.photos.first(where: {
                    $0.isIncluded && ($0.localIdentifier ?? "") == localIdentifier
                }) {
                    placePhotoModalItem = PlacePhotoModalItem(
                        dayId: day.id,
                        stopId: stop.id,
                        initialPhotoId: photo.id,
                        autoFocusCaption: true
                    )
                    return
                }
            }
        }
    }

    /// Center-screen popup for “Sharing Between Bloggo Users” (not a bottom sheet).
    @ViewBuilder
    private func bloggoQRSharePopup() -> some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBloggoQRSheet = false
                    }
                }

            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image("Blogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Image("SplashIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Image("Blogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

                    Text("Sharing Between Bloggo Users")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Other Bloggo users can scan this to open your blog in the app.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    Group {
                        if let url = nearbyShare.receiveURLForQR {
                            if let image = TripShareQRCodeGenerator.image(from: url.absoluteString, scale: 12) {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding(16)
                                    .background(Color.white)
                                    .appChromeCornerRadius(14)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Could not build QR")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        } else {
                            ProgressView("Preparing QR…")
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.top, 6)

                    Group {
                        switch nearbyShare.phase {
                        case .hostingPreparing:
                            ProgressView("Preparing trip…")
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        case .hostingAdvertising:
                            Label("Waiting for a nearby device…", systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        case .hostingConnected(let name):
                            Label("Connected to \(name)", systemImage: "link")
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity, alignment: .center)
                        case .transferring(let cur, let total):
                            ProgressView(value: Double(cur), total: Double(total)) {
                                Text("Sending photos \(cur) of \(total)")
                            }
                            .tint(.white)
                        case .succeeded:
                            Label("Trip sent successfully", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .center)
                        case .failed(let msg):
                            Text(msg)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.top, 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBloggoQRSheet = false
                        }
                    } label: {
                        Text("Close")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(appChromeBaseRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: 400)
            .frame(maxHeight: 620)
            .background(
                RoundedRectangle(appChromeBaseRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(appChromeBaseRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
            .padding(.horizontal, 24)
            .overlay {
                if let glow = nearbyShareGlowStyle {
                    GeometryReader { geo in
                        let margin: CGFloat = 44
                        let s = geo.size
                        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
                            TripNearbySiriCardGlow(
                                size: CGSize(width: s.width + margin * 2, height: s.height + margin * 2),
                                cornerRadius: 30,
                                phase: glow == .searching ? .searching : .linked,
                                time: context.date.timeIntervalSinceReferenceDate
                            )
                            .frame(width: s.width + margin * 2, height: s.height + margin * 2)
                            .position(x: s.width * 0.5, y: s.height * 0.5)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }

        }
        .preferredColorScheme(.dark)
        .onAppear {
            AppAnalytics.track(.blogShareNearby(blogId: blogId.uuidString))
            nearbyShare.startHosting(recapDetail: draft)
        }
        .onDisappear {
            nearbyShare.cancel()
        }
        .onChange(of: nearbyShare.phase) { oldPhase, newPhase in
            TripNearbyShareHaptics.playForPhaseTransition(from: oldPhase, to: newPhase)
        }
    }

    /// Border animation while the host is discoverable vs after a peer has paired (stronger “radiation”).
    private enum NearbyShareGlowStyle {
        case searching
        case paired
    }

    private var nearbyShareGlowStyle: NearbyShareGlowStyle? {
        switch nearbyShare.phase {
        case .hostingAdvertising:
            return .searching
        case .hostingConnected, .transferring:
            return .paired
        default:
            return nil
        }
    }

    /// Anonymous guest recap that has never used toolbar Save — intermediate persists must use `asDraft: true` so only explicit Save runs the second-blog gate (`guestSecondSaveBlockedSignal`).
    private var isGuestUncommittedRecapBlog: Bool {
        guard AuthService.shared.currentUser == nil,
              let r = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) else { return false }
        return r.ownerScope == .anonymous && !r.hasCommittedRecapSave
    }

    /// Persists local draft edits. For guest uncommitted recaps, uses draft-style save so place renames, captions, etc. do not show the "Create an Account" modal.
    @discardableResult
    private func persistRecapBlogDetail() -> Bool {
        if isGuestUncommittedRecapBlog {
            return createdRecapStore.saveBlogDetail(draft, asDraft: true)
        }
        return createdRecapStore.saveBlogDetail(draft)
    }

    /// Writes `draft` without a toolbar Save (`hasCommittedRecapSave` unchanged). Used when leaving an uncommitted recap via X so we never run the guest second-blog gate or force a double-tap (edit → view → back).
    @discardableResult
    private func persistRecapWithoutToolbarCommit() -> Bool {
        createdRecapStore.saveBlogDetail(draft, asDraft: true)
    }

    @discardableResult
    private func saveDraft(suppressPostSaveOnboarding: Bool = false) -> Bool {
        // Check if this is the first save before saving
        let isFirstSave = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.lastEditedAt == nil

// AutosaveManager.shared.cancelPending() — removed
        guard createdRecapStore.saveBlogDetail(draft) else { return false }
        AppAnalytics.track(.blogSave(blogId: blogId.uuidString))

        withAnimation {
            lastUndoAction = nil
        }

        if isFirstSave {
            withAnimation {
                showFirstSaveBanner = true
            }
            let shouldShowSettingsSpotlight = !suppressPostSaveOnboarding
                && !hasSeenFirstSaveBlogSettingsCoachmark
            if shouldShowSettingsSpotlight {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showFirstSaveBlogSettingsSpotlight = true
                    }
                }
            } else {
                // Guarantee first-time split/merge onboarding appears even when the
                // initial on-appear sheet presentation is skipped (e.g. camera-first flow).
                presentPhotoGroupingTipIfNeeded(afterNanoseconds: 800_000_000)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    showFirstSaveBanner = false
                }
            }
        } else {
            // savedToast removed — user requested only the "Saved as draft" notification in TripsView
        }
        return true
    }

    private func day(at index: Int) -> RecapBlogDay? {
        guard draft.days.indices.contains(index) else { return nil }
        return draft.days[index]
    }

    private func removePlaceStop(dayId: UUID, stopId: UUID) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIndex = draft.days[dayIndex].placeStops.firstIndex(where: { $0.id == stopId }) else { return }

        let coverPhotoIdentifierBeforeRemoval = draft.selectedCoverPhotoIdentifier

        // Prepare Undo
        let day = draft.days[dayIndex]
        let stop = day.placeStops[stopIndex]
        withAnimation {
            lastUndoAction = .deletePlace(
                dayBeforeRemoval: day,
                removedStopIndex: stopIndex,
                dayIndexInDraft: dayIndex,
                coverPhotoIdentifierBeforeRemoval: coverPhotoIdentifierBeforeRemoval
            )
        }
        
        // Soft-delete: preserve stop in removedPlaceStops so it can be restored later
        let removedEntry = RemovedPlaceEntry(
            dayId: dayId,
            dayIndex: day.dayIndex,
            dayDate: day.date,
            stop: stop,
            coverPhotoIdentifierBeforeRemoval: coverPhotoIdentifierBeforeRemoval
        )
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
        
        persistRecapBlogDetail()
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

        persistRecapBlogDetail()
        if let placeKey = stop.visitedTimeDigitized, photo.cloudURL != nil {
            Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "delete") }
        }
    }

    /// Marks a set of photos as not included in the blog (called from the gallery select mode).
    private func removePhotosFromBlogViaGallery(identifiers: [String]) {
        for identifier in identifiers {
            for day in draft.days {
                for stop in day.placeStops {
                    guard let photo = stop.photos.first(where: { $0.localIdentifier == identifier }) else { continue }
                    removePhoto(dayId: day.id, stopId: stop.id, photoId: photo.id)
                    break
                }
            }
        }
    }

    /// Removes an in-app camera capture from disk and excludes it from the recap (same as manage-photos delete).
    private func removeAppCapturePhotoFromSlideshow(identifier: String) {
        guard let captureUUID = AppCapturePhotoService.uuid(from: identifier) else { return }
        AppCapturePhotoService.shared.deleteCapture(captureId: captureUUID)
        for day in draft.days {
            for stop in day.placeStops {
                guard let photo = stop.photos.first(where: { $0.localIdentifier == identifier }) else { continue }
                removePhoto(dayId: day.id, stopId: stop.id, photoId: photo.id)
                return
            }
        }
    }

    private func mergePlaceStops(dayId: UUID, firstStopId: UUID, secondStopId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let firstIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == firstStopId }),
              let secondIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == secondStopId }),
              firstIdx < secondIdx else { return }

        var day = draft.days[dayIdx]
        let first = day.placeStops[firstIdx]
        let second = day.placeStops[secondIdx]

        withAnimation {
            lastUndoAction = .mergePlaceStops(dayId: dayId, originalFirst: first, originalSecond: second, firstIndex: firstIdx)
        }

        var merged = first
        merged.photos = (first.photos + second.photos).sorted { $0.timestamp < $1.timestamp }
        if let firstTime = first.visitedTimeDigitized, let secondTime = second.visitedTimeDigitized {
            merged.visitedTimeDigitized = min(firstTime, secondTime)
        } else {
            merged.visitedTimeDigitized = first.visitedTimeDigitized ?? second.visitedTimeDigitized
        }

        day.placeStops[firstIdx] = merged
        day.placeStops.remove(at: secondIdx)
        for i in day.placeStops.indices { day.placeStops[i].orderIndex = i }
        draft.days[dayIdx] = day
        AppAnalytics.track(.blogMerge(blogId: blogId.uuidString))
    }

    private func mergeCandidates(dayId: UUID, sourceStopId: UUID) -> [RecapMergePlaceCandidateItem] {
        guard let day = draft.days.first(where: { $0.id == dayId }),
              let sourceIdx = day.placeStops.firstIndex(where: { $0.id == sourceStopId }) else { return [] }

        func detailText(for stop: PlaceStop) -> String {
            let includedCount = stop.includedPhotos.count
            return includedCount == 1 ? "1 photo" : "\(includedCount) photos"
        }

        var items: [RecapMergePlaceCandidateItem] = []

        if sourceIdx > 0 {
            let previous = day.placeStops[sourceIdx - 1]
            items.append(
                RecapMergePlaceCandidateItem(
                    stopId: previous.id,
                    position: .previous,
                    placeTitle: previous.placeTitle,
                    detailText: detailText(for: previous),
                    previewPhoto: previous.photos.first
                )
            )
        }

        if sourceIdx < day.placeStops.count - 1 {
            let next = day.placeStops[sourceIdx + 1]
            items.append(
                RecapMergePlaceCandidateItem(
                    stopId: next.id,
                    position: .next,
                    placeTitle: next.placeTitle,
                    detailText: detailText(for: next),
                    previewPhoto: next.photos.first
                )
            )
        }

        return items
    }

    private func mergeSelectedStops(dayId: UUID, sourceStopId: UUID, targetStopId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let sourceIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == sourceStopId }),
              let targetIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == targetStopId }) else { return }

        guard abs(sourceIdx - targetIdx) == 1 else { return }

        let firstId = sourceIdx < targetIdx ? sourceStopId : targetStopId
        let secondId = sourceIdx < targetIdx ? targetStopId : sourceStopId
        mergePlaceStops(dayId: dayId, firstStopId: firstId, secondStopId: secondId)
        mergeSelectionItem = nil
    }

    /// Split sheet must not be presented in the same update as (or while) the place overflow sheet is up;
    /// stacked `.sheet` presentations often show UI that does not receive touches.
    private func presentSplitPlaceStopSheet(dayId: UUID, stop: PlaceStop) {
        overflowStop = nil
        let payload = SplitPlaceStopItem(dayId: dayId, stop: stop)
        DispatchQueue.main.async {
            splitPlaceStopItem = payload
        }
    }

    private func splitPlaceStop(dayId: UUID, stopId: UUID, afterPhotoIndex: Int) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else {
            print("[SplitPlaceStop] splitPlaceStop ABORT — day or stop not found dayId=\(dayId) stopId=\(stopId)")
            return
        }

        var day = draft.days[dayIdx]
        let original = day.placeStops[stopIdx]
        guard afterPhotoIndex >= 0, afterPhotoIndex < original.photos.count - 1 else {
            print("[SplitPlaceStop] splitPlaceStop ABORT — invalid afterPhotoIndex=\(afterPhotoIndex) photoCount=\(original.photos.count) (need 0..<\(max(0, original.photos.count - 1)))")
            return
        }
        print("[SplitPlaceStop] splitPlaceStop applying — stopIdx=\(stopIdx) afterPhotoIndex=\(afterPhotoIndex) photos=\(original.photos.count)")

        var firstHalf = original
        firstHalf.photos = Array(original.photos[0...afterPhotoIndex])

        // Ensure all second-half photos are included by default
        var secondPhotos = Array(original.photos[(afterPhotoIndex + 1)...])
        for i in secondPhotos.indices { secondPhotos[i].isIncluded = true }

        // Derive visitedTimeDigitized for the second half using the same timezone offset
        // as the original stop (EXIF local time minus UTC timestamp = location offset).
        var secondVisitedTime: String? = nil
        let exifFmt = DateFormatter()
        exifFmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exifFmt.timeZone = TimeZone(secondsFromGMT: 0)
        if let originalDigitized = original.visitedTimeDigitized,
           let originalFirstPhoto = original.photos.first,
           let exifDate = exifFmt.date(from: originalDigitized),
           let secondFirstPhoto = secondPhotos.first {
            let locationOffsetSeconds = exifDate.timeIntervalSince(originalFirstPhoto.timestamp)
            let localTime = secondFirstPhoto.timestamp.addingTimeInterval(locationOffsetSeconds)
            secondVisitedTime = exifFmt.string(from: localTime)
        }

        let secondHalf = PlaceStop(
            orderIndex: stopIdx + 1,
            placeTitle: original.placeTitle,
            placeSubtitle: original.placeSubtitle,
            placeTitleIsManual: original.placeTitleIsManual,
            representativeLocation: secondPhotos.first?.location,
            photos: secondPhotos,
            visitedTimeDigitized: secondVisitedTime
        )

        day.placeStops[stopIdx] = firstHalf
        day.placeStops.insert(secondHalf, at: stopIdx + 1)
        for i in day.placeStops.indices { day.placeStops[i].orderIndex = i }
        draft.days[dayIdx] = day
        splitPlaceStopItem = nil
        showManagePhotosForStop = nil  // pop ManagePhotosView so user sees both new stops
    }

    private func performUndo() {
        guard let action = lastUndoAction else { return }

        withAnimation {
            switch action {
            case .deletePlace(
                let dayBeforeRemoval,
                let removedStopIndex,
                let dayIndexInDraft,
                let coverPhotoIdentifierBeforeRemoval
            ):
                let removedStop = dayBeforeRemoval.placeStops[removedStopIndex]
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayBeforeRemoval.id }) {
                    var day = draft.days[dayIdx]
                    if !day.placeStops.contains(where: { $0.id == removedStop.id }) {
                        let insertAt = min(removedStopIndex, day.placeStops.count)
                        day.placeStops.insert(removedStop, at: insertAt)
                        for i in day.placeStops.indices { day.placeStops[i].orderIndex = i }
                        draft.days[dayIdx] = day
                    }
                } else {
                    // Last place on that day was removed, so the day row was dropped — restore the full day.
                    let insertAt = min(dayIndexInDraft, draft.days.count)
                    draft.days.insert(dayBeforeRemoval, at: insertAt)
                    selectedDayIndex = min(insertAt, max(0, draft.days.count - 1))
                }
                // Put cover back to what it was before hide (removePlaceStop may have reassigned when the cover asset was on the removed day).
                draft.selectedCoverPhotoIdentifier = coverPhotoIdentifierBeforeRemoval
                // Remove from the soft-deleted list since user chose to undo (not just restore later)
                draft.removedPlaceStops.removeAll { $0.stop.id == removedStop.id }

            case .deletePhoto(let dayId, let stopId, let photo, _):
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                   let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) {
                    var day = draft.days[dayIdx]
                    var stop = day.placeStops[stopIdx]
                    if let pIdx = stop.photos.firstIndex(where: { $0.id == photo.id }) {
                        stop.photos[pIdx].isIncluded = true
                        day.placeStops[stopIdx] = stop
                        draft.days[dayIdx] = day
                        if isCloudEditingEnabled, let placeKey = stop.visitedTimeDigitized {
                            if photo.cloudURL != nil {
                                Task { try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "add") }
                            } else {
                                Task {
                                    let fallback = await PlaceLibraryPhotoImport.placeTimeZone(for: stop)
                                    await uploadAndAddPhotoToCloud(photo: photo, placeKey: placeKey, stopId: stopId, digitizedTimeZoneFallback: fallback)
                                }
                            }
                        }
                    }
                }

            case .mergePlaceStops(let dayId, let originalFirst, let originalSecond, let firstIndex):
                if let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }) {
                    var day = draft.days[dayIdx]
                    day.placeStops.remove(at: firstIndex)
                    day.placeStops.insert(originalSecond, at: firstIndex)
                    day.placeStops.insert(originalFirst, at: firstIndex)
                    for i in day.placeStops.indices { day.placeStops[i].orderIndex = i }
                    draft.days[dayIdx] = day
                }
            }

            lastUndoAction = nil

            persistRecapBlogDetail()
        }

        // Show toast confirming what was undone (`action` is still in scope from the guard let above)
        undoToastText = action.messageAfterUndo
        undoToastTask?.cancel()
        withAnimation {
            showUndoToast = true
        }
        undoToastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    showUndoToast = false
                }
            }
        }
    }

    /// Persists an auto-resolved place name without dismissing the edit sheet.
    /// Called by EditPlaceStopNameSheet when it resolves "Unknown Place" on appear.
    private func silentlyUpdatePlaceName(stopId: UUID, to title: String) {
        for i in draft.days.indices {
            guard let j = draft.days[i].placeStops.firstIndex(where: { $0.id == stopId }) else { continue }
            var day = draft.days[i]
            var stop = day.placeStops[j]
            stop.placeTitle = title
            stop.placeTitleIsManual = true
            day.placeStops[j] = stop
            draft.days[i] = day
            break
        }
        persistRecapBlogDetail()
    }

    private func updatePlaceTitle(stopId: UUID, to title: String, category: String? = nil, coordinate: CLLocationCoordinate2D? = nil, placeSubtitleLine: String = "") {
        let subTrimmed = placeSubtitleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetMomentKey = placeStop(stopId: stopId)?.visitedTimeDigitized
        debugPrint("[Category] updatePlaceTitle called: stopId=\(stopId) title='\(title)' category=\(category ?? "nil") coord=\(coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "nil") subtitle='\(subTrimmed)' momentKey=\(targetMomentKey ?? "nil")")

        var didUpdateAnyStop = false
        var apiPlaceKey: String? = nil
        var apiCategories: [String]? = nil

        for i in draft.days.indices {
            var day = draft.days[i]
            var didUpdateDay = false

            for j in day.placeStops.indices {
                let existing = day.placeStops[j]
                let matchesTargetStop = existing.id == stopId
                let matchesMoment = targetMomentKey != nil && existing.visitedTimeDigitized == targetMomentKey
                guard matchesTargetStop || matchesMoment else { continue }

                var stop = existing
                stop.placeTitle = title
                stop.placeTitleIsManual = true
                stop.placeSubtitle = subTrimmed.isEmpty ? nil : subTrimmed
                // `EditPlaceStopNameSheet` passes the resolved category (including nil to clear after a rename).
                stop.placeCategory = category
                if let coordinate {
                    stop.representativeLocation = PhotoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                day.placeStops[j] = stop
                didUpdateDay = true
                didUpdateAnyStop = true
                debugPrint("[Category] updatePlaceTitle stored: stopId=\(stop.id) placeTitle='\(stop.placeTitle)' placeSubtitle=\(stop.placeSubtitle ?? "nil") placeCategory=\(stop.placeCategory ?? "nil")")
                // Bloggo Gallery reads the `bloggo-capture:` meta cache first — keep it in sync so
                // it doesn't keep showing a stale "Near …" title after a manual rename here.
                createdRecapStore.syncAppCaptureMetaFromResolvedStop(stop, force: true)

                if apiPlaceKey == nil {
                    apiPlaceKey = stop.visitedTimeDigitized
                    apiCategories = stop.placeCategory.map { [$0] }
                }
            }

            if didUpdateDay {
                draft.days[i] = day
            }
        }

        if didUpdateAnyStop {
            persistRecapBlogDetail()
            if draft.blogKey != nil, let placeKey = apiPlaceKey {
                Task { try? await APIManager.shared.updatePlaceName(visitedTimeDigitized: placeKey, placeName: title, categories: apiCategories) }
            }
        }

        showEditNameForStop = nil
    }

    private func updatePlaceCategory(stopId: UUID, category: String?) {
        debugPrint("[Category] updatePlaceCategory called: stopId=\(stopId) category=\(category ?? "nil")")
        for i in draft.days.indices {
            guard let j = draft.days[i].placeStops.firstIndex(where: { $0.id == stopId }) else { continue }
            var day = draft.days[i]
            var stop = day.placeStops[j]
            stop.placeCategory = category
            day.placeStops[j] = stop
            draft.days[i] = day
            debugPrint("[Category] updatePlaceCategory stored: placeTitle='\(stop.placeTitle)' placeCategory=\(stop.placeCategory ?? "nil")")
            persistRecapBlogDetail()
            if draft.blogKey != nil, let placeKey = stop.visitedTimeDigitized {
                let categories = category.map { [$0] } ?? ["unknown"]
                Task { try? await APIManager.shared.updatePlaceName(visitedTimeDigitized: placeKey, placeName: stop.placeTitle, categories: categories) }
            }
            break
        }
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
                        stop.placeTitleIsManual = true
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
                scheduleAutosaveAfterPhotoSelectionChange()
            }
        )
    }

    /// Debounced autosave for Manage Photos toggles so selection survives force-quit.
    @MainActor
    private func scheduleAutosaveAfterPhotoSelectionChange() {
        photoSelectionAutosaveTask?.cancel()
        photoSelectionAutosaveTask = Task { @MainActor in
            // Small delay batches rapid taps without feeling laggy.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            persistRecapBlogDetail()
        }
    }

    private func placeStop(dayId: UUID, stopId: UUID) -> PlaceStop? {
        draft.days.first(where: { $0.id == dayId })?.placeStops.first(where: { $0.id == stopId })
    }

    private func placeStop(stopId: UUID) -> PlaceStop? {
        for d in draft.days {
            if let s = d.placeStops.first(where: { $0.id == stopId }) { return s }
        }
        return nil
    }

    private func setTransportMode(_ mode: TravelMode?, dayId: UUID, stopId: UUID) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIndex = draft.days[dayIndex].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        draft.days[dayIndex].placeStops[stopIndex].transportModeToNextStop = mode
    }

    /// Returns the next PlaceStop after the given stop (same day or first of next day), if any.
    private func nextStop(dayId: UUID, stopId: UUID) -> PlaceStop? {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIndex = draft.days[dayIndex].placeStops.firstIndex(where: { $0.id == stopId }) else { return nil }
        let day = draft.days[dayIndex]
        if stopIndex + 1 < day.placeStops.count { return day.placeStops[stopIndex + 1] }
        if dayIndex + 1 < draft.days.count { return draft.days[dayIndex + 1].placeStops.first }
        return nil
    }

    /// Full-screen fade overlay (not a sheet) so the editor does not slide up from the bottom.
    @ViewBuilder
    private func dayCaptionEditLayer(item: DayCaptionEditItem) -> some View {
        DayCaptionEditSheet(
            dayNumber: item.dayNumber,
            dateLine: item.dateLine,
            caption: bindingForDayCaption(dayId: item.dayId),
            onSave: {
                AppAnalytics.track(.blogDayStory(blogId: blogId.uuidString, dayIndex: draft.days.firstIndex(where: { $0.id == item.dayId }) ?? 0))
                dayCaptionEditItem = nil
                persistRecapBlogDetail()
                syncDayCaptionToCloudIfNeeded(dayId: item.dayId)
            },
            onCancel: {
                dayCaptionEditItem = nil
            },
            onEnhance: LocalLLMStoryCaptionGenerator.isCapable ? { userText in
                guard let day = draft.days.first(where: { $0.id == item.dayId }) else { return userText }
                return await StoryCaptionService.shared.enhanceDaySummary(
                    day: day,
                    userText: userText
                )
            } : nil,
            onEnhanceApplied: LocalLLMStoryCaptionGenerator.isCapable ? {
                AppAnalytics.track(.blogStoryAIStory(blogId: blogId.uuidString))
                persistRecapBlogDetail()
            } : nil
        )
    }

    @ViewBuilder
    private func tripNarrativeEditLayer() -> some View {
        TripNarrativeEditSheet(
            blogTitle: draft.title,
            narrative: bindingForTripNarrative(),
            onSave: {
                showTripNarrativeEdit = false
                AppAnalytics.track(.blogStory(blogId: blogId.uuidString))
                persistRecapBlogDetail()
            },
            onCancel: {
                showTripNarrativeEdit = false
            }
        )
    }

    private func bindingForTripNarrative() -> Binding<String> {
        Binding(
            get: { draft.tripNarrative ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.tripNarrative = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    /// Full-screen fade overlay (not a sheet) so the editor does not slide up from the bottom.
    @ViewBuilder
    private func placeCaptionEditLayer(item: PlaceCaptionEditItem, stop: PlaceStop) -> some View {
        PlaceCaptionEditSheet(
            placeTitle: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            placeCategory: stop.placeCategory,
            photos: stop.includedPhotos,
            caption: bindingForOverallStory(dayId: item.dayId, stopId: item.stopId),
            photoCaption: { bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: $0) },
            onSave: { placeCaptionChanged, changedPhotoIds in
                placeCaptionEditItem = nil
                if placeCaptionChanged {
                    AppAnalytics.track(.blogPlaceStory(blogId: blogId.uuidString, placeId: item.stopId.uuidString))
                    markOverallStoryManual(dayId: item.dayId, stopId: item.stopId)
                    syncOverallStoryToCloudIfNeeded(dayId: item.dayId, stopId: item.stopId)
                    triggerSentimentAnalysis(dayId: item.dayId, stopId: item.stopId)
                }
                for photoId in changedPhotoIds {
                    AppAnalytics.track(.blogPlacePhotoStory(blogId: blogId.uuidString, placeId: item.stopId.uuidString, photoId: photoId.uuidString))
                    markPhotoCaptionManual(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                    syncStoryToCloudIfNeeded(stopId: item.stopId, isPlaceNote: false, photoId: photoId)
                    triggerPhotoSentimentAnalysis(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
                }
                persistRecapBlogDetail()
            },
            onCancel: {
                placeCaptionEditItem = nil
            },
            onEnhance: LocalLLMStoryCaptionGenerator.isCapable ? { userText in
                guard let currentStop = placeStop(dayId: item.dayId, stopId: item.stopId),
                      let dayDate = draft.days.first(where: { $0.id == item.dayId })?.date else { return userText }
                let captions = currentStop.photos.filter(\.isIncluded).map { $0.caption ?? "" }
                return await StoryCaptionService.shared.enhanceOverallPlaceStory(
                    stop: currentStop,
                    userText: userText,
                    dayDate: dayDate,
                    photoCaptions: captions
                )
            } : nil,
            onEnhanceApplied: LocalLLMStoryCaptionGenerator.isCapable ? {
                AppAnalytics.track(.blogStoryAIStory(blogId: blogId.uuidString))
                markOverallStoryAI(dayId: item.dayId, stopId: item.stopId)
            } : nil,
            onFunPhotoInsightApplied: LocalLLMStoryCaptionGenerator.isCapable ? { photoId in
                markPhotoCaptionAI(dayId: item.dayId, stopId: item.stopId, photoId: photoId)
            } : nil,
            onRequestEditPlaceName: {
                showEditNameForStop = stop
            },
            overallStoryIsManual: stop.overallStoryIsManual,
            onGeneratePlaceAIShortStory: LocalLLMStoryCaptionGenerator.isCapable
                ? {
                    guard let currentStop = placeStop(dayId: item.dayId, stopId: item.stopId),
                          let dayDate = draft.days.first(where: { $0.id == item.dayId })?.date else { return "" }
                    return await StoryCaptionService.shared.generatePlaceLevelAIShortStory(stop: currentStop, dayDate: dayDate)
                }
                : nil
        )
    }

    private func photoCaptionEditLayer(item: PhotoCaptionEditItem, photo: RecapPhoto, stop: PlaceStop) -> some View {
        PhotoCaptionEditSheet(
            photo: photo,
            placeTitle: stop.placeTitle,
            placeSubtitle: stop.placeSubtitle,
            placeCategory: stop.placeCategory,
            captionIsManual: photo.captionIsManual,
            caption: bindingForPhotoCaption(dayId: item.dayId, stopId: item.stopId, photoId: item.photoId),
            onSave: {
                photoCaptionEditItem = nil
                markPhotoCaptionManual(dayId: item.dayId, stopId: item.stopId, photoId: item.photoId)
                persistRecapBlogDetail()
                syncStoryToCloudIfNeeded(stopId: item.stopId, isPlaceNote: false, photoId: item.photoId)
                triggerPhotoSentimentAnalysis(dayId: item.dayId, stopId: item.stopId, photoId: item.photoId)
            },
            onCancel: {
                photoCaptionEditItem = nil
            },
            onEnhance: LocalLLMStoryCaptionGenerator.isCapable ? { userText in
                await StoryCaptionService.shared.enhanceCaption(
                    photo: photo,
                    userText: userText,
                    placeName: stop.placeTitle,
                    placeSubtitle: stop.placeSubtitle
                )
            } : nil,
            onEnhanceApplied: LocalLLMStoryCaptionGenerator.isCapable ? {
                markPhotoCaptionAI(dayId: item.dayId, stopId: item.stopId, photoId: item.photoId)
            } : nil,
            onRequestFullPhotoView: {
                placePhotoModalItem = PlacePhotoModalItem(
                    dayId: item.dayId,
                    stopId: item.stopId,
                    initialPhotoId: item.photoId,
                    openInCaptionEditor: true,
                    hideChromeDoneFromCaptionEditorSheet: true
                )
            },
            activePhotoModalToken: placePhotoModalItem?.id,
            onRequestEditPlaceName: {
                showEditNameForStop = stop
            }
        )
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
    /// The getter matches `PlaceStopRowView` / `StoryBookBuilder`: manual `overallStory` wins, then AI `placeNarrative`, else `overallStory`.
    /// Without that, the full-screen editor bound only to `overallStory` stayed empty when the visible text came from `placeNarrative`.
    private func bindingForOverallStory(dayId: UUID, stopId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }) else { return "" }
                let manual = (stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if stop.overallStoryIsManual, !manual.isEmpty {
                    return stop.overallStory ?? ""
                }
                if let narrative = stop.placeNarrative?.trimmingCharacters(in: .whitespacesAndNewlines), !narrative.isEmpty {
                    return stop.placeNarrative ?? ""
                }
                return stop.overallStory ?? ""
            },
            set: { newValue in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                var day = draft.days[dayIdx]
                var stop = day.placeStops[stopIdx]
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    stop.overallStory = nil
                    stop.placeNarrative = nil
                } else {
                    stop.overallStory = newValue.isEmpty ? nil : newValue
                }
                day.placeStops[stopIdx] = stop
                draft.days[dayIdx] = day
            }
        )
    }

    private func bindingForSentiment(dayId: UUID, stopId: UUID) -> Binding<Int> {
        Binding(
            get: {
                guard let day = draft.days.first(where: { $0.id == dayId }),
                      let stop = day.placeStops.first(where: { $0.id == stopId }) else { return 2 }
                return stop.sentiment
            },
            set: { newValue in
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                draft.days[dayIdx].placeStops[stopIdx].sentiment = newValue
                persistRecapBlogDetail()
                syncSentimentToCloudIfNeeded(dayId: dayId, stopId: stopId)
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
        if isEditMode {
            let isExpanded = expandedDayCaptionIds.contains(day.id)
            let trimmed = captionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 0) {
                Text(trimmed.isEmpty ? "Describe your day in a sentence…" : trimmed)
                    .font(.subheadline)
                    .foregroundColor(trimmed.isEmpty ? .secondary.opacity(0.9) : .white)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dayCaptionEditItem = DayCaptionEditItem(
                            dayId: day.id,
                            dayNumber: day.dayIndex,
                            dateLine: day.dayStoryDateLine
                        )
                    }
                if !trimmed.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedDayCaptionIds.remove(day.id)
                            } else {
                                expandedDayCaptionIds.insert(day.id)
                            }
                        }
                    } label: {
                        Text(isExpanded ? "Less" : "More")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(white: 0.1))
            .appChromeCornerRadius(10)
            .padding(.bottom, 4)
        } else {
            let displayCaption: String? = {
                // User-entered caption should win when both exist.
                if let c = day.dayCaption, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
                if let n = day.dayNarrative, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
                return nil
            }()
            if let text = displayCaption {
                let isExpanded = expandedDayCaptionIds.contains(day.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.blog(selectedBlogFont, size: 17))
                        .lineSpacing(8)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(isExpanded ? nil : 4)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedDayCaptionIds.remove(day.id)
                            } else {
                                expandedDayCaptionIds.insert(day.id)
                            }
                        }
                    } label: {
                        Text(isExpanded ? "Less" : "More")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }
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
        guard blogIsInCloud else {
            print("⏭️ [syncStory] skipped — blog not in cloud")
            return
        }
        guard let day = draft.days.first(where: { $0.placeStops.contains(where: { $0.id == stopId }) }),
              let stop = day.placeStops.first(where: { $0.id == stopId }),
              let placeKey = stop.visitedTimeDigitized else {
            print("⚠️ [syncStory] skipped — could not resolve stop or placeKey for stopId:\(stopId)")
            return
        }
        Task {
            if isPlaceNote {
                let storyText = stop.noteText ?? ""
                print("🔵 [syncStory] place note → updateStory placeKey:\(placeKey) text:\"\(storyText)\"")
                try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: storyText, photoIndex: nil)
            } else if let pid = photoId,
                      let photo = stop.photos.first(where: { $0.id == pid }) {
                let included = stop.photos.filter(\.isIncluded)
                guard let filteredIndex = included.firstIndex(where: { $0.id == pid }) else {
                    print("⚠️ [syncStory] skipped — photo \(pid) not found in included list")
                    return
                }
                let storyText = photo.caption ?? ""
                print("🔵 [syncStory] photo caption → updateStory placeKey:\(placeKey) photoIndex:\(filteredIndex) text:\"\(storyText)\"")
                try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: storyText, photoIndex: filteredIndex, photoIndexType: "filtered")

                // Prevent backend auto-generating a place story as a side effect of photo caption updates.
                // Requirement: if a place story already exists in the backend, we should sync it (so do NOT clear it).
                // Only enforce "keep empty" when the place has no story locally and the user hasn't authored one.
                let localOverall = (stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !stop.overallStoryIsManual, localOverall.isEmpty {
                    print("🟣 [syncStory] clearing place story to keep it empty — placeKey:\(placeKey)")
                    try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: "", photoIndex: nil)
                }
            }
        }
    }

    /// Pushes the place overall story (overallStory) to the backend when the blog is in the cloud.
    private func syncOverallStoryToCloudIfNeeded(dayId: UUID, stopId: UUID) {
        guard blogIsInCloud else { return }
        guard let stop = placeStop(dayId: dayId, stopId: stopId),
              let placeKey = stop.visitedTimeDigitized else { return }
        let storyText = stop.overallStory ?? ""
        Task { try? await APIManager.shared.updateStory(placeKey: placeKey, storyText: storyText) }
    }

    /// Pushes the sentiment value to the backend when the blog is in the cloud.
    private func syncSentimentToCloudIfNeeded(dayId: UUID, stopId: UUID) {
        guard blogIsInCloud else { return }
        guard let stop = placeStop(dayId: dayId, stopId: stopId),
              let placeKey = stop.visitedTimeDigitized else { return }
        let sentimentValue = stop.sentiment
        Task { try? await APIManager.shared.updateSentiment(placeKey: placeKey, sentiment: sentimentValue) }
    }

    /// Analyzes sentiment of a photo caption, then re-derives the place-level sentiment.
    /// No-ops when LLM is unavailable or the photo has no caption.
    private func triggerPhotoSentimentAnalysis(dayId: UUID, stopId: UUID, photoId: UUID) {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return }
        guard let stop = placeStop(dayId: dayId, stopId: stopId),
              let photo = stop.photos.first(where: { $0.id == photoId }),
              let caption = photo.caption,
              !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            let photoSentiment = await StoryCaptionService.shared.analyzeSentiment(text: caption)
            await MainActor.run {
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }),
                      let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
                draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].sentiment = photoSentiment
                // Re-derive place sentiment from all photo sentiments + place caption
                let updatedStop = draft.days[dayIdx].placeStops[stopIdx]
                let derived = updatedStop.computeDerivedSentiment(placeCaption: updatedStop.overallStory)
                draft.days[dayIdx].placeStops[stopIdx].sentiment = derived
                persistRecapBlogDetail()
                syncSentimentToCloudIfNeeded(dayId: dayId, stopId: stopId)
            }
        }
    }

    /// Analyzes sentiment of the place's overall story caption, then re-derives place-level sentiment
    /// from photo sentiments + this new place caption sentiment.
    /// No-ops when LLM is unavailable or no caption text exists.
    private func triggerSentimentAnalysis(dayId: UUID, stopId: UUID) {
        guard LocalLLMStoryCaptionGenerator.isCapable else { return }
        guard let stop = placeStop(dayId: dayId, stopId: stopId) else { return }
        let captionText = stop.overallStory ?? stop.noteText ?? ""
        guard !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            // Analyze the place caption itself
            let placeCaptionSentiment = await StoryCaptionService.shared.analyzeSentiment(text: captionText)
            await MainActor.run {
                guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
                // Store the analyzed place caption sentiment, then derive the combined value
                draft.days[dayIdx].placeStops[stopIdx].sentiment = placeCaptionSentiment
                let updatedStop = draft.days[dayIdx].placeStops[stopIdx]
                let derived = updatedStop.computeDerivedSentiment(placeCaption: updatedStop.overallStory)
                draft.days[dayIdx].placeStops[stopIdx].sentiment = derived
                persistRecapBlogDetail()
                syncSentimentToCloudIfNeeded(dayId: dayId, stopId: stopId)
            }
        }
    }

    /// Pushes the day caption to the backend via /trips/day-story when the blog is in the cloud.
    private func syncDayCaptionToCloudIfNeeded(dayId: UUID) {
        guard blogIsInCloud else { return }
        guard let blogKey = currentBlogKey else {
            print("⚠️ [syncDayCaption] skipped — no blogKey")
            return
        }
        guard let day = draft.days.first(where: { $0.id == dayId }) else { return }
        let dateKey = day.dayIndex - 1  // dayIndex is 1-based; API expects 0-based
        let storyText = day.dayCaption ?? ""
        Task { try? await APIManager.shared.updateDayStory(blogKey: blogKey, dateKey: dateKey, story: storyText) }
    }

    // MARK: - Narrative Generation

    private func triggerPlaceNarrative(dayId: UUID, stopId: UUID, dayDate: Date) {
        AppAnalytics.track(.blogPlaceStory(blogId: blogId.uuidString, placeId: stopId.uuidString))
        generatingNarrativeStopId = stopId
        Task {
            guard let currentStop = placeStop(dayId: dayId, stopId: stopId) else {
                generatingNarrativeStopId = nil
                return
            }
            let narrative = await StoryCaptionService.shared.generatePlaceNarrative(stop: currentStop, dayDate: dayDate)
            await MainActor.run {
                guard let narrative,
                      let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else {
                    generatingNarrativeStopId = nil
                    return
                }
                draft.days[dayIdx].placeStops[stopIdx].placeNarrative = narrative
                generatingNarrativeStopId = nil
            }
        }
    }

    private func triggerDayNarrative(day: RecapBlogDay) {
        AppAnalytics.track(.blogDayStory(blogId: blogId.uuidString, dayIndex: draft.days.firstIndex(where: { $0.id == day.id }) ?? 0))
        generatingNarrativeDayId = day.id
        Task {
            guard let currentDay = draft.days.first(where: { $0.id == day.id }) else {
                generatingNarrativeDayId = nil
                return
            }
            let narrative = await StoryCaptionService.shared.generateDayNarrative(day: currentDay)
            await MainActor.run {
                guard let narrative,
                      let dayIdx = draft.days.firstIndex(where: { $0.id == day.id }) else {
                    generatingNarrativeDayId = nil
                    return
                }
                draft.days[dayIdx].dayNarrative = narrative
                // In edit mode the caption row shows dayCaption, not dayNarrative,
                // so copy the result there so it's immediately visible.
                if isEditMode {
                    draft.days[dayIdx].dayCaption = narrative
                }
                generatingNarrativeDayId = nil
            }
        }
    }

    // MARK: - Trip Narrative Card

    @ViewBuilder
    private var tripNarrativeCard: some View {
        let narrativeText = draft.tripNarrative?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasNarrative = !narrativeText.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            if hasNarrative {
                VStack(alignment: .leading, spacing: 6) {
                    Text(narrativeText)
                        .font(Font.custom("Georgia", size: 17))
                        .lineSpacing(8)
                        .foregroundColor(recapChromeForeground.opacity(colorScheme == .dark ? 0.9 : 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(tripNarrativeExpanded ? nil : 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                showTripNarrativeEdit = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    tripNarrativeExpanded.toggle()
                                }
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(isEditMode ? "Opens the trip story editor" : "Shows the full trip story")
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tripNarrativeExpanded.toggle()
                        }
                    } label: {
                        Text(tripNarrativeExpanded ? "Less" : "More")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, isEditMode ? 16 : 0)
                .padding(.vertical, isEditMode ? 12 : 0)
                .background(isEditMode ? recapNarrativeCardBackground : Color.clear)
                .appChromeCornerRadius(isEditMode ? 12 : 0)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if isEditMode {
                if !hasNarrative {
                    Button {
                        showTripNarrativeEdit = true
                    } label: {
                        Text("Your trip story will appear here…")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(white: 0.1))
                            .appChromeCornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                if LocalLLMStoryCaptionGenerator.isCapable {
                    if isGeneratingTripNarrative {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.secondary)
                                .padding(.trailing, 20)
                                .padding(.top, hasNarrative ? 0 : 8)
                        }
                    } else if !hasNarrative {
                        HStack {
                            Spacer()
                            Button {
                                triggerTripNarrative()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "wand.and.sparkles")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Generate story")
                                        .font(.footnote.weight(.medium))
                                }
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.top, hasNarrative ? 2 : 8)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Spacer()
                            Button {
                                draft.tripNarrative = nil
                                tripNarrativeExpanded = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.caption)
                                    Text("Revert")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            Button {
                                triggerTripNarrative()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "wand.and.sparkles")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Regenerate")
                                        .font(.footnote.weight(.medium))
                                }
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.top, isEditMode ? 16 : 0)
    }

    private func triggerTripNarrative() {
        AppAnalytics.track(.blogStory(blogId: blogId.uuidString))
        isGeneratingTripNarrative = true
        tripNarrativeExpanded = false
        Task {
            let narrative = await StoryCaptionService.shared.generateTripNarrative(detail: draft)
            await MainActor.run {
                if let narrative {
                    draft.tripNarrative = narrative
                }
                isGeneratingTripNarrative = false
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
        persistRecapBlogDetail()
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
        }
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
        let unit = DistanceUnit(rawValue: distanceUnitRaw) ?? .miles
        switch unit {
        case .miles:
            let miles = distanceInMeters / 1609.34
            if miles < 0.1 { return nil }
            return String(format: "%.1f mi", miles)
        case .kilometers:
            let km = distanceInMeters / 1000.0
            if km < 0.1 { return nil }
            return String(format: "%.1f km", km)
        }
    }

    private func checkFirstTimeTip() {
        guard !hasCheckedFirstTimeTip else { return }
        hasCheckedFirstTimeTip = true
        // If the blog has been saved before, start in View Mode (unless forced into edit).
        if let existing = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }),
           existing.hasCommittedRecapSave || existing.lastEditedAt != nil {
            isEditMode = forceEditMode
        }
        // Photo grouping split/merge: show once (dedicated AppStorage), not tied to legacy save tip or draft state.
        presentPhotoGroupingTipIfNeeded(afterNanoseconds: 550_000_000)
        
        // Snapshot for change detection (after a brief delay so draft is loaded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.draftSnapshot == nil {
                self.draftSnapshot = self.draft
            }
        }

        if forcePresentShareYourBlogSheet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.showShareYourBlogSheet = true
            }
        }
    }

    @MainActor
    private func presentPhotoGroupingTipIfNeeded(afterNanoseconds delay: UInt64) {
        guard !suppressPhotoGroupingTipOnAppear else { return }
        guard !hasSeenPhotoGroupingTip else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !hasSeenPhotoGroupingTip, !showSaveTipAlert, !showFirstSaveBlogSettingsSpotlight else { return }
            showSaveTipAlert = true
        }
    }

    private func dismissFirstSaveBlogSettingsSpotlight(markedSeen: Bool) {
        withAnimation(.easeOut(duration: 0.22)) {
            showFirstSaveBlogSettingsSpotlight = false
        }
        guard markedSeen else { return }
        hasSeenFirstSaveBlogSettingsCoachmark = true
        presentPhotoGroupingTipIfNeeded(afterNanoseconds: 600_000_000)
    }

    // MARK: - Extracted Body Helpers

    private var navTitle: String {
        let hasBeenSaved = hasBlogBeenSavedToDevice
        if !hasBeenSaved {
            return "Draft"
        } else if isEditMode {
            return "Edit Mode"
        } else {
            // Empty — the .principal toolbar item handles the title in read-only mode
            return ""
        }
    }

    /// Read-only, edit, and story mode: hidden bar — no solid tint strip over the blog or story book.
    private var recapNavigationBarBackgroundVisibility: Visibility {
        .hidden
    }

    private var recapNavigationBarBackgroundFill: Color {
        Color.clear
    }

    private var hasUnsavedChanges: Bool {
        guard let snapshot = draftSnapshot else { return false }
        return draft != snapshot
    }

    /// True until an explicit recap toolbar Save completes (`hasCommittedRecapSave`). Without this, `draftSnapshot` is initialized equal to `draft`, so `hasUnsavedChanges` stays false and Save stays disabled—blocking first saves and the guest second-blog sign-in flow (`guestSecondSaveBlockedSignal`).
    private var needsCommittedRecapToolbarSave: Bool {
        guard let r = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) else { return false }
        return !r.hasCommittedRecapSave
    }

    private var isToolbarSaveEnabled: Bool {
        hasUnsavedChanges || needsCommittedRecapToolbarSave
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if isEditMode {
                    if needsCommittedRecapToolbarSave {
                        if hasUnsavedChanges {
                            showUnsavedChangesAlert = true
                        } else {
                            // Draft, no edits since snapshot: leave without prompting; keep as on-device draft only.
                            _ = persistRecapWithoutToolbarCommit()
                            performDismiss()
                        }
                    } else if hasUnsavedChanges {
                        showUnsavedChangesAlert = true
                    } else {
                        isEditMode = false
                    }
                } else {
                    print("🔙 View mode, dismissing")
                    performDismiss()
                }
            } label: {
                Image(systemName: isEditMode ? "xmark" : "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(recapChromeForeground)
            }
        }
        ToolbarItem(placement: .principal) {
            Text(draft.title)
                .font(.headline)
                .foregroundColor(recapChromeForeground)
                .lineLimit(1)
                .opacity(!isEditMode && showNavBarTitle ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showNavBarTitle)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isEditMode {
                Button {
                    performUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .foregroundColor(lastUndoAction != nil ? recapChromeForeground : recapChromeForeground.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
                .disabled(lastUndoAction == nil)
            } else if !isExportingPDF && !showStoryMode && fullScreenMapDay == nil {
                Button {
                    isEditMode = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundColor(recapChromeForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Blog")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isEditMode {
                Button {
                    if saveDraft() {
                        isEditMode = false
                    }
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .dynamicTypeSize(.small ... .xLarge)
                        .fixedSize()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(isToolbarSaveEnabled ? Color.blue : Color.gray.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isToolbarSaveEnabled)
            } else if !isExportingPDF && !showStoryMode && fullScreenMapDay == nil {
                Button {
                    showBlogSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                        .foregroundColor(recapChromeForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Blog Settings")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BlogSettingsGearFramePreferenceKey.self,
                            value: geo.frame(in: .global)
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var firstSaveBannerOverlay: some View {
        if showFirstSaveBanner {
            HStack(spacing: 12) {
                Image("MyBlogsIcon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.green)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft has been saved")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(recapChromeForeground)
                    Text("Your blog is ready")
                        .font(.caption)
                        .foregroundColor(recapSecondaryOnChrome)
                }
                Spacer()
                Button {
                    withAnimation { showFirstSaveBanner = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(recapSecondaryOnChrome.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(appChromeBaseRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .stroke(recapHairline, lineWidth: 1)
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
                Image("MyBlogsIcon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.green)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploaded to cloud")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(recapChromeForeground)
                    Text("All photos are now in the cloud.")
                        .font(.caption)
                        .foregroundColor(recapSecondaryOnChrome)
                }
                Spacer()
                Button {
                    withAnimation { showUploadSuccessBanner = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(recapSecondaryOnChrome.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(appChromeBaseRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .stroke(recapHairline, lineWidth: 1)
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
                Image(systemName: "externaldrive.fill")
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
                    cloudFeatureRow(icon: "arrow.clockwise", text: "Automatic cloud backup")
                    cloudFeatureRow(icon: "link", text: "Share your blog via a web link")
                }
                .padding(16)
                .background(Color(.systemGray6).opacity(0.5))
                .appChromeCornerRadius(12)

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
                        .appChromeCornerRadius(12)
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

    private func earlyAccessOverlay() -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    earlyAccessSheetPresented = false
                }

            earlyAccessCard(isOnList: earlyAccessShowOnListConfirm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func earlyAccessCard(isOnList: Bool) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    // Drag pill
                    RoundedRectangle(appChromeBaseRadius: 3)
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    // Icon + text
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: isOnList ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(isOnList ? .green : .blue)
                        }

                        if isOnList {
                            VStack(spacing: 6) {
                                Text("You're on the List!")
                                    .font(.title3.weight(.bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                                Text("We'll notify you when cloud publishing becomes available. Uploading your blogs to the cloud lets you edit and share them from any device.")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            VStack(spacing: 6) {
                                Text("Early Access Feature")
                                    .font(.title3.weight(.bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                                Text("Cloud publishing is currently limited.\n\(authService.isSignedIn ? "Join the waitlist to be notified when it opens up." : "Create an account to join the waitlist.")")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    // Buttons — directly below text, no Spacer
                    VStack(spacing: 10) {
                        if isOnList {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("You're signed up!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))

                            Button {
                                earlyAccessSheetPresented = false
                            } label: {
                                Text("Done")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
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
                                    .padding(.vertical, 15)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                            }

                            Button {
                                earlyAccessSheetPresented = false
                                showPDFExportOptions = true
                            } label: {
                                Text("Export as PDF Instead")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(appChromeBaseRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: -6)
            }
        }
    }

    private var guestCloudUploadModalContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Back Up Your Blog")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Securely back up this blog to the cloud so you can edit it on your computer and keep it safe.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    Text("Your blog stays private. Nothing is shared unless you choose to share it.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showGuestCloudUploadModal = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        pendingCloudUploadAfterAuth = true
                        showAuth = true
                    }
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .appChromeCornerRadius(12)
                }

                Button {
                    showGuestCloudUploadModal = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }

    private func handleCloudUploadTap() {
        guard authService.isSignedIn else {
            showGuestCloudUploadModal = true
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

    private func exportBlogToPDF(options: PDFExportOptions = PDFExportOptions()) {
        AppAnalytics.track(.blogSharePDF(blogId: blogId.uuidString))
        isExportingPDF = true
        Task {
            do {
                let url = try await PDFExportService.generatePDF(from: draft, options: options)
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

    private func resetUploadingViewChrome() {
        uploadingViewTitle = "Uploading Your Blog!"
        uploadingViewProgressDetail = nil
        uploadingViewStepCycleLabels = nil
        uploadingViewAllowsCancel = true
    }

    /// Full-screen progress for uploads that are not driven by `uploadTask` (cover, republish sync).
    private func beginAuxiliaryCloudUploadOverlay(title: String, progressDetail: String?, progress: (Int, Int)) {
        isUploading = true
        uploadingViewTitle = title
        uploadingViewProgressDetail = progressDetail
        uploadingViewAllowsCancel = false
        uploadProgress = progress
        showUploadingFullScreen = true
    }

    private func endAuxiliaryCloudUploadOverlay() {
        isUploading = false
        showUploadingFullScreen = false
        resetUploadingViewChrome()
    }

    private func syncWithCloudIfNeeded() {
        guard blogIsInCloud else { return }
        guard !isUploading else { return }

        let snapshot = draft
        let currentBlogId = blogId

        // Hide existing cloud blog if we have its key
        if let existingKey = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId })?.blogKey {
            Task {
                try? await APIManager.shared.setBlogPrivacy(blogKey: existingKey, level: "hidden")
            }
        }

        Task { @MainActor in
            beginAuxiliaryCloudUploadOverlay(
                title: "Syncing your blog",
                progressDetail: "Publishing to the cloud…",
                progress: (0, 1)
            )
            defer { endAuxiliaryCloudUploadOverlay() }
            let newKey = await APIManager.shared.publishBlog(detail: snapshot)
            uploadProgress.current = 1
            if let newKey = newKey {
                createdRecapStore.setBlogKey(blogId: currentBlogId, blogKey: newKey)
            }
        }
    }

    /// Captures photo inclusion state for a stop before ManagePhotosView opens so we can diff on dismiss.
    private func openManagePhotos(dayId: UUID, stopId: UUID) {
        // `removingUndisplayablePhotos()` does a bulk PHAsset fetch, which can be slow for large stops.
        // Run it off the critical path so opening Manage Photos is instant.
        Task { @MainActor in
            _ = await pruneEmptyPhotoGroupsFromDraftAsync()
            guard let stop = placeStop(dayId: dayId, stopId: stopId) else { return }
            guard stop.photos.contains(where: \.hasDisplayableLocalBacking) else {
                removePlaceStop(dayId: dayId, stopId: stopId)
                return
            }
            managePhotosEditInfo = ManagePhotosEditInfo(
                dayId: dayId, stopId: stopId,
                photoInclusionBefore: Dictionary(uniqueKeysWithValues: stop.photos.map { ($0.id, $0.isIncluded) })
            )
            showManagePhotosForStop = ManagePhotosItem(dayId: dayId, stopId: stopId)
        }
    }

    /// Strips broken photo rows and removes place stops / days that no longer have any photos.
    private func pruneEmptyPhotoGroupsFromDraft() {
        let sanitized = draft.removingUndisplayablePhotos()
        guard sanitized != draft else { return }
        draft = sanitized
        if selectedDayIndex >= draft.days.count {
            selectedDayIndex = max(0, draft.days.count - 1)
        }
        let allIncludedPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        if let currentCover = draft.selectedCoverPhotoIdentifier,
           !allIncludedPhotos.contains(where: { $0.localIdentifier == currentCover }) {
            draft.selectedCoverPhotoIdentifier = allIncludedPhotos.compactMap(\.localIdentifier).first
        }
    }

    /// Async variant of `pruneEmptyPhotoGroupsFromDraft()` that runs PHAsset fetch work off the main thread.
    /// Returns true when `draft` was mutated.
    @MainActor
    private func pruneEmptyPhotoGroupsFromDraftAsync() async -> Bool {
        let captured = draft
        let sanitized = await Task.detached(priority: .userInitiated) { captured.removingUndisplayablePhotos() }.value
        if draft != captured {
            // Draft changed while we were sanitizing (e.g. user toggled photos). Re-run once on latest state.
            let latest = draft
            let sanitizedLatest = await Task.detached(priority: .userInitiated) { latest.removingUndisplayablePhotos() }.value
            guard sanitizedLatest != latest else { return false }
            draft = sanitizedLatest
        } else {
            guard sanitized != captured else { return false }
            draft = sanitized
        }

        if selectedDayIndex >= draft.days.count {
            selectedDayIndex = max(0, draft.days.count - 1)
        }
        let allIncludedPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded)
        if let currentCover = draft.selectedCoverPhotoIdentifier,
           !allIncludedPhotos.contains(where: { $0.localIdentifier == currentCover }) {
            draft.selectedCoverPhotoIdentifier = allIncludedPhotos.compactMap(\.localIdentifier).first
        }
        return true
    }

    /// Diffs photo inclusion changes made in ManagePhotosView and fires targeted updatePhoto calls.
    /// For newly included photos that have never been uploaded, uploads first then adds.
    /// Photos added mid-session (e.g. library import) are not in `photoInclusionBefore`; they are treated as newly included.
    private func syncPhotoChangesWithCloud() {
        guard let info = managePhotosEditInfo else {
            print("📸 [syncPhoto] ⚠️ managePhotosEditInfo is nil — skipping cloud sync")
            return
        }
        guard isCloudEditingEnabled else {
            print("📸 [syncPhoto] cloud editing disabled (cloudState=localOnly) — skipping cloud calls")
            managePhotosEditInfo = nil
            return
        }
        guard let stop = placeStop(dayId: info.dayId, stopId: info.stopId) else {
            print("📸 [syncPhoto] ⚠️ could not find stop dayId=\(info.dayId) stopId=\(info.stopId)")
            managePhotosEditInfo = nil
            return
        }
        guard let placeKey = stop.visitedTimeDigitized else {
            print("📸 [syncPhoto] ⚠️ stop '\(stop.placeTitle)' has no visitedTimeDigitized — blog not published yet, skipping")
            managePhotosEditInfo = nil
            return
        }

        let before = info.photoInclusionBefore
        let stopId = stop.id
        let dayId = info.dayId
        managePhotosEditInfo = nil

        print("📸 [syncPhoto] placeKey=\(placeKey) stop='\(stop.placeTitle)' totalPhotos=\(stop.photos.count)")
        print("📸 [syncPhoto] before-snapshot: \(before.map { "\($0.key.uuidString.prefix(6))=\($0.value)" }.joined(separator: ", "))")

        Task { @MainActor in
            let fallbackTZ = await PlaceLibraryPhotoImport.placeTimeZone(for: stop)
            guard let currentStop = placeStop(dayId: dayId, stopId: stopId) else {
                print("📸 [syncPhoto] ⚠️ stop disappeared after await — aborting")
                return
            }

            var steps: [ManagePhotosCloudStep] = []
            for photo in currentStop.photos {
                let wasIncluded = before[photo.id] ?? false
                let isIncluded = photo.isIncluded
                if wasIncluded == isIncluded { continue }
                if wasIncluded && !isIncluded {
                    if photo.cloudURL == nil {
                        print("📸 [syncPhoto] skip delete — photo has no cloudURL (id=\(photo.id.uuidString.prefix(6)))")
                        continue
                    }
                    print("📸 [syncPhoto] → DELETE photoId=\(photo.id.uuidString.prefix(6)) cloudURL=\(photo.cloudURL ?? "nil")")
                    steps.append(.delete(photo))
                } else if !wasIncluded && isIncluded {
                    if photo.cloudURL != nil {
                        print("📸 [syncPhoto] → ADD(cloud) photoId=\(photo.id.uuidString.prefix(6)) cloudURL=\(photo.cloudURL!)")
                        steps.append(.addCloud(photo))
                    } else {
                        print("📸 [syncPhoto] → UPLOAD+ADD photoId=\(photo.id.uuidString.prefix(6)) localId=\(photo.localIdentifier ?? "nil")")
                        steps.append(.uploadAndAdd(photo))
                    }
                }
            }

            // Check for photos in current stop not in before-snapshot (added mid-session)
            let newPhotoIds = Set(currentStop.photos.map(\.id)).subtracting(before.keys)
            if !newPhotoIds.isEmpty {
                print("📸 [syncPhoto] \(newPhotoIds.count) photo(s) added mid-session not in snapshot — they are handled via uploadAndAdd above if included")
            }

            guard !steps.isEmpty else {
                print("📸 [syncPhoto] no changes detected — skipping API calls")
                return
            }

            print("📸 [syncPhoto] \(steps.count) step(s) to execute, isUploading=\(isUploading)")

            if isUploading {
                for step in steps {
                    await runManagePhotosCloudStep(step, placeKey: placeKey, stopId: stopId, fallbackTZ: fallbackTZ)
                }
                return
            }

            isUploading = true
            let onlyNewLocalAdds = steps.allSatisfy {
                if case .uploadAndAdd = $0 { return true }
                return false
            }
            if onlyNewLocalAdds {
                uploadingViewTitle = "Adding New Photos"
                uploadingViewStepCycleLabels = [
                    "Preparing your photos…",
                    "Adding to your blog…",
                    "Almost there…"
                ]
            } else {
                uploadingViewTitle = "Syncing photos"
                uploadingViewStepCycleLabels = nil
            }
            uploadingViewProgressDetail = nil
            uploadingViewAllowsCancel = true
            uploadProgress = (0, steps.count)
            showUploadingFullScreen = true

            uploadTask = Task { @MainActor in
                for (idx, step) in steps.enumerated() {
                    if Task.isCancelled { break }
                    await runManagePhotosCloudStep(step, placeKey: placeKey, stopId: stopId, fallbackTZ: fallbackTZ)
                    uploadProgress.current = idx + 1
                }
                isUploading = false
                showUploadingFullScreen = false
                uploadTask = nil
                resetUploadingViewChrome()
            }
        }
    }

    private enum ManagePhotosCloudStep {
        case delete(RecapPhoto)
        case addCloud(RecapPhoto)
        case uploadAndAdd(RecapPhoto)
    }

    private func clearUndoIfRestoredIncludedPhoto(photoId: UUID) {
        if case .deletePhoto(_, _, let undoPhoto, _) = lastUndoAction, undoPhoto.id == photoId {
            withAnimation {
                lastUndoAction = nil
            }
        }
    }

    private func runManagePhotosCloudStep(
        _ step: ManagePhotosCloudStep,
        placeKey: String,
        stopId: UUID,
        fallbackTZ: TimeZone
    ) async {
        switch step {
        case .delete(let photo):
            _ = try? await APIManager.shared.updatePhoto(placeKey: placeKey, photo: photo, operation: "delete")
        case .addCloud(let photo):
            _ = try? await APIManager.shared.updatePhoto(
                placeKey: placeKey,
                photo: photo,
                operation: "add",
                digitizedTimeZoneFallback: fallbackTZ
            )
            clearUndoIfRestoredIncludedPhoto(photoId: photo.id)
        case .uploadAndAdd(let photo):
            await uploadAndAddPhotoToCloud(
                photo: photo,
                placeKey: placeKey,
                stopId: stopId,
                digitizedTimeZoneFallback: fallbackTZ
            )
            clearUndoIfRestoredIncludedPhoto(photoId: photo.id)
        }
    }

    /// Uploads a photo that has no cloudURL yet, persists the URL locally, then calls updatePhoto(add).
    private func uploadAndAddPhotoToCloud(photo: RecapPhoto, placeKey: String, stopId: UUID, digitizedTimeZoneFallback: TimeZone? = nil) async {
        guard let assetId = photo.localIdentifier else { return }
        do {
            let cloudURL = try await APIManager.shared.uploadPhoto(assetIdentifier: assetId)

            var uploaded = photo
            uploaded.cloudURL = cloudURL

            // Call add first so the backend records the photo with the digitizedTime we're about to store.
            let usedDigitizedTime = try await APIManager.shared.updatePhoto(
                placeKey: placeKey,
                photo: uploaded,
                operation: "add",
                digitizedTimeZoneFallback: digitizedTimeZoneFallback
            )

            // Persist cloudURL and the digitizedTime used by the backend so future delete/re-add
            // calls send the exact same value and the backend can locate this photo.
            for dayIdx in draft.days.indices {
                for stopIdx in draft.days[dayIdx].placeStops.indices
                    where draft.days[dayIdx].placeStops[stopIdx].id == stopId {
                    if let photoIdx = draft.days[dayIdx].placeStops[stopIdx].photos
                        .firstIndex(where: { $0.id == photo.id }) {
                        draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = cloudURL
                        if !usedDigitizedTime.isEmpty {
                            draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].digitizedTime = usedDigitizedTime
                        }
                        persistRecapBlogDetail()
                    }
                }
            }
        } catch {
            print("🚨 uploadAndAddPhotoToCloud failed: \(error)")
        }
    }

    /// Resolves a library asset after PHPicker returns its local identifier.
    ///
    /// With **limited** photo library access, `PHAsset.fetchAssets(withLocalIdentifiers:)` often returns empty on the first
    /// query while Photos finishes extending the user's authorized asset set. Imports still proceed using place/day fallbacks;
    /// longer retry schedules help attach richer metadata when the asset appears.
    private func fetchPHAssetForLibraryImport(localIdentifier id: String) async -> PHAsset? {
        let isLimited = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
        let delaysMs: [UInt64] = isLimited
            ? [0, 50, 120, 250, 500, 900, 1600, 2500, 3500, 5000]
            : [0, 50, 120, 250, 500, 900, 1600]
        for delayMs in delaysMs {
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            if let asset = assets.firstObject { return asset }
        }
        return nil
    }

    /// Appends library picks to the managed place and fills missing metadata from the place/day.
    /// Photos appear in the grid immediately after a single synchronous PHAsset lookup; any photos
    /// whose assets are not yet visible under limited library access are refined in a background Task.
    @MainActor
    private func importLibraryPhotosIntoStop(assetIdentifiers: [String], dayId: UUID, stopId: UUID) async {
        guard let initDayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let initStop = draft.days[initDayIdx].placeStops.first(where: { $0.id == stopId }) else { return }

        // Fast path when the place already has a resolved timezone (no geocoding needed).
        let placeTZ = await PlaceLibraryPhotoImport.placeTimeZone(for: initStop)

        // Re-validate indices after the async pause — other @MainActor work may have run during geocoding.
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }

        let day = draft.days[dayIdx]
        var stop = draft.days[dayIdx].placeStops[stopIdx]
        var existingIds = Set(stop.photos.compactMap(\.localIdentifier))
        var pendingRefinement: [String] = []

        // Batch-fetch all newly selected PHAssets in a single call instead of one per photo.
        let newIds = assetIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !existingIds.contains($0) }
        var fetchedAssets: [String: PHAsset] = [:]
        if !newIds.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: newIds, options: nil)
            result.enumerateObjects { asset, _, _ in fetchedAssets[asset.localIdentifier] = asset }
        }

        for id in newIds {
            let asset = fetchedAssets[id]
            let coord = PlaceLibraryPhotoImport.resolvedCoordinate(asset: asset, stop: stop)
            let timestamp = PlaceLibraryPhotoImport.resolvedTimestamp(asset: asset, stop: stop, day: day, placeTimeZone: placeTZ)
            let recap = RecapPhoto(
                timestamp: timestamp,
                location: coord,
                imageName: "photo",
                isIncluded: true,
                localIdentifier: id
            )
            stop.photos.append(recap)
            existingIds.insert(id)

            if asset == nil { pendingRefinement.append(id) }
        }

        guard stop.photos.count > draft.days[dayIdx].placeStops[stopIdx].photos.count else { return }

        stop.photos.sort { $0.timestamp < $1.timestamp }
        draft.days[dayIdx].placeStops[stopIdx] = stop
        await syncStopLocationAndGeocodeIfNeeded(dayId: dayId, stopId: stopId)

        // Refine timestamp/location in the background for any photos whose PHAsset wasn't immediately available.
        guard !pendingRefinement.isEmpty else { return }
        let capturedDay = day
        Task {
            for localId in pendingRefinement {
                guard !Task.isCancelled else { return }
                guard let asset = await fetchPHAssetForLibraryImport(localIdentifier: localId) else { continue }
                guard let dIdx = draft.days.firstIndex(where: { $0.id == dayId }),
                      let sIdx = draft.days[dIdx].placeStops.firstIndex(where: { $0.id == stopId }),
                      let pIdx = draft.days[dIdx].placeStops[sIdx].photos.firstIndex(where: { $0.localIdentifier == localId })
                else { continue }
                let refinedStop = draft.days[dIdx].placeStops[sIdx]
                draft.days[dIdx].placeStops[sIdx].photos[pIdx].timestamp =
                    PlaceLibraryPhotoImport.resolvedTimestamp(asset: asset, stop: refinedStop, day: capturedDay, placeTimeZone: placeTZ)
                draft.days[dIdx].placeStops[sIdx].photos[pIdx].location =
                    PlaceLibraryPhotoImport.resolvedCoordinate(asset: asset, stop: refinedStop)
            }
            await syncStopLocationAndGeocodeIfNeeded(dayId: dayId, stopId: stopId)
        }
    }

    /// Points cover at an included library photo when the stored cover id is missing from the blog.
    private func syncCoverPhotoToIncludedPhotosIfNeeded() {
        let included = draft.days
            .flatMap(\.placeStops)
            .flatMap(\.photos)
            .filter(\.isIncluded)
        let includedIds = Set(included.compactMap(\.localIdentifier))
        if let cover = draft.selectedCoverPhotoIdentifier, includedIds.contains(cover) {
            return
        }
        draft.selectedCoverPhotoIdentifier = included.compactMap(\.localIdentifier).first
    }

    /// Sets the trip day date from the earliest included photo timestamp (library EXIF), not "today".
    private func alignDayDateFromIncludedPhotos(dayId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }) else { return }
        let included = draft.days[dayIdx].placeStops.flatMap(\.photos).filter(\.isIncluded)
        guard let earliest = included.map(\.timestamp).min() else { return }

        let tz = draft.days[dayIdx].placeStops
            .compactMap(\.timeZoneIdentifier)
            .compactMap(TimeZone.init(identifier:))
            .first ?? .current
        let key = TripCalendarDayKey.from(date: earliest, timeZone: tz)
        guard let canonical = TripCalendarDayKey.canonicalDate(from: key) else { return }
        draft.days[dayIdx].date = canonical
    }

    private func finalizePhotoImportToDay(dayId: UUID) {
        alignDayDateFromIncludedPhotos(dayId: dayId)
        syncCoverPhotoToIncludedPhotosIfNeeded()
        persistRecapBlogDetail()
    }

    /// Copies photo GPS onto the stop when missing, then reverse-geocodes placeholder place names.
    @MainActor
    private func syncStopLocationAndGeocodeIfNeeded(dayId: UUID, stopId: UUID) async {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }

        var stop = draft.days[dayIdx].placeStops[stopIdx]
        if stop.representativeLocation == nil {
            stop.representativeLocation = stop.photos.compactMap(\.location).first
            draft.days[dayIdx].placeStops[stopIdx].representativeLocation = stop.representativeLocation
        }
        guard let coord = stop.representativeLocation else {
            finalizePhotoImportToDay(dayId: dayId)
            return
        }

        let shouldGeocode = !stop.placeTitleIsManual
            && PlacePlaceholderNaming.isResolvablePlaceholder(stop.placeTitle)
        guard shouldGeocode else {
            finalizePhotoImportToDay(dayId: dayId)
            return
        }

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let place = await GeocodingService.shared.place(for: loc)
        let (resolvedTitle, resolvedCategory) = await GeocodingService.shared.resolvePlaceLabel(
            areaName: place.areaName,
            coordinate: loc.coordinate
        )

        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }
        var updated = draft.days[dayIdx].placeStops[stopIdx]
        guard !updated.placeTitleIsManual,
              PlacePlaceholderNaming.isResolvablePlaceholder(updated.placeTitle) else {
            finalizePhotoImportToDay(dayId: dayId)
            return
        }

        updated.placeTitle = resolvedTitle
        updated.placeSubtitle = place.subtitle.isEmpty ? nil : place.subtitle
        if let cat = resolvedCategory, updated.placeCategory == nil {
            updated.placeCategory = cat
        }
        if updated.timeZoneIdentifier == nil,
           let tz = await GeocodingService.shared.timeZone(for: loc) {
            updated.timeZoneIdentifier = tz.identifier
        }
        draft.days[dayIdx].placeStops[stopIdx] = updated
        finalizePhotoImportToDay(dayId: dayId)
    }

    private func importBloggoPhotosIntoStop(captureIds: [UUID], dayId: UUID, stopId: UUID) {
        guard let dayIdx = draft.days.firstIndex(where: { $0.id == dayId }),
              let stopIdx = draft.days[dayIdx].placeStops.firstIndex(where: { $0.id == stopId }) else { return }

        var stop = draft.days[dayIdx].placeStops[stopIdx]
        var existingIds = Set(stop.photos.compactMap(\.localIdentifier))

        for uuid in captureIds {
            let identifier = AppCapturePhotoService.identifier(for: uuid)
            guard !existingIds.contains(identifier),
                  let info = AppCapturePhotoService.shared.metadata(captureId: uuid) else { continue }
            let recap = RecapPhoto(
                timestamp: info.timestamp,
                location: info.location,
                imageName: "photo",
                isIncluded: true,
                localIdentifier: identifier,
                caption: info.caption
            )
            stop.photos.append(recap)
            existingIds.insert(identifier)
        }

        stop.photos.sort { $0.timestamp < $1.timestamp }
        draft.days[dayIdx].placeStops[stopIdx] = stop
        Task { await syncStopLocationAndGeocodeIfNeeded(dayId: dayId, stopId: stopId) }
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

    /// True only when this blog is in a cloud-enabled lifecycle state.
    /// When false, **never** call cloud photo endpoints from Manage Photos / Undo flows.
    private var isCloudEditingEnabled: Bool {
        guard let blog = createdRecapStore.recents.first(where: { $0.sourceTripId == blogId }) else { return false }
        return blog.cloudState != .localOnly
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

    /// Splits a blog that has already been saved/created (Edit Mode), then asks which part to continue editing.
    private func splitSavedBlog(afterDayIndex: Int) {
        didPickSavedSplitEditorPart = false
        savedSplitPartPreviews = Self.splitPartPreviews(from: draft.days, afterDayIndex: afterDayIndex)
        AppAnalytics.track(.blogSplit(blogId: blogId.uuidString))
        createdRecapStore.splitBlog(blogId: blogId, afterDayIndex: afterDayIndex)
        showContinueEditingAfterSplit = true
    }

    private func handleSavedContinueEditingSheetDismissed() {
        savedSplitPartPreviews = nil
        guard !didPickSavedSplitEditorPart else {
            didPickSavedSplitEditorPart = false
            return
        }
        applySavedSplitEditorFocus(keepPart: 1)
    }

    private func applySavedSplitEditorFocus(keepPart: Int) {
        if keepPart == 2 {
            createdRecapStore.focusSplitPart(keepPart: 2)
        }
        guard let updated = createdRecapStore.getBlogDetail(blogId: blogId) else { return }
        draft = updated
        selectedDayIndex = 0
        draftSnapshot = draft

        splitUndoBannerDismissTask?.cancel()
        withAnimation {
            showSplitUndoBanner = true
        }
        splitUndoBannerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    showSplitUndoBanner = false
                }
            }
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private static func splitPartPreviews(from days: [RecapBlogDay], afterDayIndex: Int) -> (part1: ContinueEditingAfterSplitPartInfo, part2: ContinueEditingAfterSplitPartInfo) {
        let part1Days = Array(days[0...afterDayIndex])
        let part2Days = Array(days[(afterDayIndex + 1)...])
        return (
            part1: partPreview(for: part1Days),
            part2: partPreview(for: part2Days)
        )
    }

    private static func partPreview(for days: [RecapBlogDay]) -> ContinueEditingAfterSplitPartInfo {
        let start = days.first?.dateAlignedWithShortDateText
        let end = days.last?.dateAlignedWithShortDateText
        let dateRangeText = CreatedRecapBlogStore.formatDateRange(start: start, end: end) ?? "Unknown Date"
        let cities = days
            .flatMap(\.placeStops)
            .compactMap { $0.placeSubtitle }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let citySummary = cities.filter { seen.insert($0).inserted }.joined(separator: ", ")
        return ContinueEditingAfterSplitPartInfo(dateRangeText: dateRangeText, citySummary: citySummary)
    }

    private func uploadBlogPhotos(openShareAfterSuccess: Bool = false) {
        guard !isUploading else { return }
        guard authService.isSignedIn else { return }
        pendingWebLinkShareAfterUpload = openShareAfterSuccess

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
            if pendingWebLinkShareAfterUpload {
                pendingWebLinkShareAfterUpload = false
                presentWebLinkShareSheetIfPossible()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showUploadSuccessBanner = false }
            }
            return
        }

        resetUploadingViewChrome()
        isUploading = true
        uploadProgress = (0, photosToUpload.count)
        showUploadingFullScreen = true

        uploadTask = Task { @MainActor in
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
                isUploading = false
                showUploadingFullScreen = false
                resetUploadingViewChrome()
                uploadTask = nil
                return
            }

            // Save updated draft with cloud URLs
            persistRecapBlogDetail()

            // Publish blog to server; keep the upload overlay visible until publish finishes.
            if failCount == 0 {
                let snapshot = draft
                let currentBlogId = blogId
                let isFirstBlog = !hasUploadedFirstBlog
                let shouldOpenWebShare = pendingWebLinkShareAfterUpload
                uploadingViewProgressDetail = "Publishing your blog…"
                uploadProgress.current = max(1, uploadProgress.total)
                let blogKey = await APIManager.shared.publishBlog(detail: snapshot)
                if let blogKey = blogKey {
                    createdRecapStore.setBlogKey(blogId: currentBlogId, blogKey: blogKey)
                    if shouldOpenWebShare {
                        pendingWebLinkShareAfterUpload = false
                        presentWebLinkShareSheetIfPossible()
                    }
                    if isFirstBlog {
                        Task {
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
            resetUploadingViewChrome()
            uploadTask = nil

            if failCount > 0 {
                uploadErrorMessage = "\(failCount) photo\(failCount == 1 ? "" : "s") failed to upload. Tap the cloud button to retry."
                showUploadErrorAlert = true
                pendingWebLinkShareAfterUpload = false
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
        resetUploadingViewChrome()
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

// MARK: - Photo Library Access Prompt View

private struct PhotoLibraryAccessPromptView: View {
    var onOpenSettings: () -> Void
    var onSelectPhotos: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            // Dimmed, slightly blurred backdrop similar to Early Access sheet.
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Limited Access Enabled")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Text("Enable Full Access in Settings to add photos to this blog.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                VStack(spacing: 12) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .appChromeCornerRadius(12)
                    }

                    Button {
                        onSelectPhotos()
                    } label: {
                        Text("Select Photos")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .appChromeCornerRadius(12)
                    }

                    Button {
                        onClose()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(appChromeBaseRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Core content alerts & lifecycle (split out to help type-checker)
private struct CoreContentAlertsAndLifecycleModifier: ViewModifier {
    @Binding var showSaveTipAlert: Bool
    @Binding var hasSeenPhotoGroupingTip: Bool
    @Binding var showUnsavedChangesAlert: Bool
    @Binding var draftSnapshot: RecapBlogDetail?
    @Binding var cancellables: Set<AnyCancellable>
    @Binding var isKeyboardVisible: Bool
    @Binding var isEditMode: Bool
    @Binding var draft: RecapBlogDetail
    /// Pass `true` to skip first-save spotlight / deferred tips when saving immediately before dismiss.
    var saveDraft: (_ suppressPostSaveOnboarding: Bool) -> Bool
    var loadDraftIfNeeded: () -> Void
    var checkFirstTimeTip: () -> Void
    var createdRecapStore: CreatedRecapBlogStore
    /// True when this recap has never had a toolbar Save (`hasCommittedRecapSave` is false).
    var needsCommittedRecapToolbarSave: () -> Bool
    /// Dismisses the recap (respects overlay `onRequestDismiss` when set).
    var performRecapDismiss: () -> Void
    @State private var blogGroupingTipPage = 0

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSaveTipAlert, onDismiss: {
                blogGroupingTipPage = 0
                hasSeenPhotoGroupingTip = true
            }) {
                blogGroupingTooltipContent
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
            .background(
                Color.clear
                    .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
                        Button("Yes") {
                            let leavingUncommittedDraft = needsCommittedRecapToolbarSave()
                            if saveDraft(leavingUncommittedDraft) {
                                if leavingUncommittedDraft {
                                    performRecapDismiss()
                                } else {
                                    isEditMode = false
                                }
                            }
                        }
                        Button("No", role: .destructive) {
                            if let snapshot = draftSnapshot {
                                draft = snapshot
                            }
                            if needsCommittedRecapToolbarSave() {
                                _ = createdRecapStore.saveBlogDetail(draft, asDraft: true)
                                performRecapDismiss()
                            } else {
                                isEditMode = false
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Do you want to save your changes?")
                    }
            )
            .onAppear {
                // Defer so the first frame can show the loading animation before sync decode work.
                Task { @MainActor in
                    if createdRecapStore.isLoading {
                        for await loading in createdRecapStore.$isLoading.values where !loading {
                            break
                        }
                    }
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

    @ViewBuilder private var blogGroupingTooltipContent: some View {
        VStack(spacing: 0) {
            if blogGroupingTipPage == 0 {
                VStack(spacing: 20) {
                    HStack {
                        Text("1/2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Image(systemName: "scissors")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.orange)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("Split Moments")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        Text("If a moment includes photos from different places, you can split it into separate moments.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            } else {
                VStack(spacing: 20) {
                    HStack {
                        Text("2/2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Image(systemName: "arrow.triangle.merge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.orange)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("Merge Moments")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        Text("If photos from the same place appear in separate moments, you can merge them together.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            Spacer()

            Button {
                if blogGroupingTipPage == 0 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        blogGroupingTipPage = 1
                    }
                } else {
                    showSaveTipAlert = false
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }
}

private struct OverflowItem: Identifiable {
    let dayId: UUID
    let stop: PlaceStop
    var id: UUID { stop.id }
}

private struct RecapMergePlaceCandidateItem: Identifiable {
    enum Position {
        case previous
        case next

        var label: String {
            switch self {
            case .previous: return "Previous place"
            case .next: return "Next place"
            }
        }
    }

    let stopId: UUID
    let position: Position
    let placeTitle: String
    let detailText: String
    let previewPhoto: RecapPhoto?
    var id: UUID { stopId }
}

private struct RecapMergePlacesSelectionSheet: View {
    let sourcePlaceTitle: String
    let sourcePreviewPhoto: RecapPhoto?
    let candidates: [RecapMergePlaceCandidateItem]
    let onSelectCandidate: (RecapMergePlaceCandidateItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var photoThumbSize: CGFloat = 52
    @State private var contentHeight: CGFloat = 300

    private var previousCandidate: RecapMergePlaceCandidateItem? {
        candidates.first(where: { $0.position == .previous })
    }

    private var nextCandidate: RecapMergePlaceCandidateItem? {
        candidates.first(where: { $0.position == .next })
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.title2.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Merge this place with another")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Choose the place you want to combine with this one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if candidates.isEmpty {
                    currentPlaceCard
                    Text("No adjacent places are available to merge.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        if let previousCandidate {
                            candidateButton(previousCandidate)
                            betweenCardArrow(for: .previous)
                        }
                        currentPlaceCard
                        if let nextCandidate {
                            betweenCardArrow(for: .next)
                            candidateButton(nextCandidate)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { contentHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newHeight in
                            contentHeight = newHeight
                        }
                }
            )
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(contentHeight + 60), .large])
        .presentationDragIndicator(.visible)
    }
    
    private var currentPlaceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                photoPreview(photo: sourcePreviewPhoto)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current place")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sourcePlaceTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(appChromeBaseRadius: 12)
                .fill(Color.orange.opacity(0.2))
        )
    }
    
    @ViewBuilder
    private func candidateButton(_ candidate: RecapMergePlaceCandidateItem) -> some View {
        Button {
            dismiss()
            onSelectCandidate(candidate)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                photoPreview(photo: candidate.previewPhoto)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.position.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.placeTitle.cleanedAsPlaceTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(appChromeBaseRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func betweenCardArrow(for position: RecapMergePlaceCandidateItem.Position) -> some View {
        Image(systemName: position == .previous ? "arrow.up" : "arrow.down")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func photoPreview(photo: RecapPhoto?) -> some View {
        if let photo {
            RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 200, height: 200))
                .frame(width: photoThumbSize, height: photoThumbSize)
                .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
        } else {
            RoundedRectangle(appChromeBaseRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: photoThumbSize, height: photoThumbSize)
                .overlay(
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct MergeSelectionItem: Identifiable {
    let dayId: UUID
    let sourceStopId: UUID
    var id: UUID { sourceStopId }
}

private struct ManagePhotosItem: Identifiable, Hashable {
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
                RoundedRectangle(appChromeBaseRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(appChromeBaseRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - New Moments Review Sheet

private let newMomentsTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// One place group for the new moments sheet: key (e.g. location name) and photos sorted earliest → latest.
private struct NewMomentPlaceGroup: Identifiable {
    /// Stable composite ID: same cluster always produces the same key, no collision across same-city clusters.
    var id: String { "\(placeKey)-\(earliestTimestamp.timeIntervalSince1970)" }
    let placeKey: String
    let photos: [MockPhoto]
    var earliestTimestamp: Date { photos.map(\.timestamp).min() ?? .distantPast }
}

private struct NewMomentsReviewSheet: View {
    let photos: [MockPhoto]
    let blogTitle: String
    var onAdd: ([MockPhoto]) -> Void
    var onLater: () -> Void

    /// Place keys the user chose to hide (whole card dimmed, those photos excluded from add count).
    @State private var hiddenPlaceKeys: Set<String> = []
    @State private var dragOffset: CGFloat = 0

    /// Photos clustered by time+location proximity (same algorithm as PlaceStop building), then labelled
    /// by the dominant locationName in each cluster. This keeps separate visits to the same city as
    /// distinct moment cards rather than collapsing them into one.
    private var placeGroups: [NewMomentPlaceGroup] {
        let service = PlaceStopClusteringService()
        let inputs = photos.map { ClusterPhotoInput(id: $0.id, timestamp: $0.timestamp, location: $0.location) }
        let clusters = service.placeStops(from: inputs) { _ in "Moment" }
        return clusters.map { _, clusterInputs in
            let clusterPhotos = clusterInputs.compactMap { input in photos.first { $0.id == input.id } }
                .sorted { $0.timestamp < $1.timestamp }
            let locationNames = clusterPhotos.compactMap(\.locationName)
            let freq = locationNames.reduce(into: [String: Int]()) { counts, name in counts[name, default: 0] += 1 }
            let placeKey = freq.max(by: { $0.value < $1.value })?.key ?? "Moment"
            return NewMomentPlaceGroup(placeKey: placeKey, photos: clusterPhotos)
        }.sorted { $0.earliestTimestamp < $1.earliestTimestamp }
    }

    /// Total photos in visible (non-hidden) place groups — used for disable state and onAdd payload.
    private var visibleCount: Int {
        placeGroups
            .filter { !hiddenPlaceKeys.contains($0.id) }
            .flatMap(\.photos)
            .count
    }

    /// Number of visible place groups (moments) — used for CTA label ("Add 1 Moment" / "Add N Moments").
    private var visibleMomentCount: Int {
        placeGroups
            .filter { !hiddenPlaceKeys.contains($0.id) }
            .count
    }

    private var visiblePhotos: [MockPhoto] {
        placeGroups
            .filter { !hiddenPlaceKeys.contains($0.id) }
            .flatMap(\.photos)
    }

    /// Gray background to match cloud early access pull-up.
    private var sheetBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                Text("New moments found")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text("Hide any places you don’t want to add")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(placeGroups) { group in
                            newMomentPlaceCard(group: group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    Button {
                        onAdd(visiblePhotos)
                    } label: {
                        Text(visibleCount == 0 ? "Add 0 Moments" : "Add \(visibleMomentCount) Moment\(visibleMomentCount == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(visibleCount > 0 ? Color.green : Color.green.opacity(0.4))
                            .appChromeCornerRadius(14)
                    }
                    .disabled(visibleCount == 0)

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
            .frame(maxHeight: UIScreen.main.bounds.height * 0.80)
            .background(sheetBackground)
            .clipShape(RoundedRectangle(appChromeBaseRadius: 20, style: .continuous))
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture()
                    .onChanged { value in dragOffset = value.translation.height }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            onLater()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func newMomentThumbnail(photo: MockPhoto, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let lid = photo.localIdentifier {
                AssetPhotoView(assetIdentifier: lid, cornerRadius: 0, targetSize: CGSize(width: 240, height: 240))
            } else {
                MockPhotoView(seed: photo.id.hashValue, cornerRadius: 0, showIcon: false, iconName: photo.imageName)
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(appChromeBaseRadius: cornerRadius, style: .continuous))
    }

    private func newMomentPlaceCard(group: NewMomentPlaceGroup) -> some View {
        let isHidden = hiddenPlaceKeys.contains(group.id)
        let thumbSize: CGFloat = 72
        let thumbSpacing: CGFloat = 8
        let thumbCorner: CGFloat = 10
        let contentSpacing: CGFloat = 12
        let photoRows = chunkedPhotos(group.photos, chunkSize: 3)
        let rowCount = max(photoRows.count, 1)
        let gridHeight = CGFloat(rowCount) * thumbSize + CGFloat(max(rowCount - 1, 0)) * thumbSpacing
        let gridWidth = thumbSize * 3 + thumbSpacing * 2
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isHidden {
                    hiddenPlaceKeys.remove(group.id)
                } else {
                    hiddenPlaceKeys.insert(group.id)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: contentSpacing) {
                VStack(alignment: .leading, spacing: thumbSpacing) {
                    ForEach(Array(photoRows.enumerated()), id: \.offset) { _, rowPhotos in
                        HStack(spacing: thumbSpacing) {
                            ForEach(rowPhotos) { photo in
                                newMomentThumbnail(photo: photo, size: thumbSize, cornerRadius: thumbCorner)
                            }
                        }
                    }
                }
                .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.placeKey)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(newMomentsTimeFormatter.string(from: group.earliestTimestamp))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: gridHeight, alignment: .topLeading)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isHidden ? .green : .secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: 40, height: gridHeight)
                .contentShape(Rectangle())
            }
            .padding(12)
            .background(
                RoundedRectangle(appChromeBaseRadius: 16)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(appChromeBaseRadius: 16))
        }
        .buttonStyle(.plain)
        .opacity(isHidden ? 0.35 : 1.0)
    }

    private func chunkedPhotos(_ photos: [MockPhoto], chunkSize: Int) -> [[MockPhoto]] {
        guard chunkSize > 0 else { return [photos] }
        var rows: [[MockPhoto]] = []
        var index = 0
        while index < photos.count {
            let endIndex = min(index + chunkSize, photos.count)
            rows.append(Array(photos[index..<endIndex]))
            index += chunkSize
        }
        return rows
    }
}

// MARK: - First-save Blog Settings spotlight

/// Dims the recap except a cutout over the Blog Settings (gear) control; dismisses when settings open or via the primary CTA.
private struct FirstSaveBlogSettingsSpotlightOverlay: View {
    let holeInGlobal: CGRect
    let onOpenBlogSettings: () -> Void

    private let dimOverlayOpacity: Double = 0.5

    var body: some View {
        GeometryReader { proxy in
            let containerGlobal = proxy.frame(in: .global)
            let w = proxy.size.width
            let h = proxy.size.height
            let hasHole = holeInGlobal.width > 0.5 && holeInGlobal.height > 0.5
            let paddedHole = holeInGlobal.insetBy(dx: -10, dy: -10)
            let holeLocal = CGRect(
                x: paddedHole.minX - containerGlobal.minX,
                y: paddedHole.minY - containerGlobal.minY,
                width: paddedHole.width,
                height: paddedHole.height
            )

            ZStack {
                if hasHole {
                    ZStack(alignment: .topLeading) {
                        dimStrip
                            .frame(width: w, height: max(0, holeLocal.minY))
                        dimStrip
                            .frame(width: w, height: max(0, h - holeLocal.maxY))
                            .offset(x: 0, y: holeLocal.maxY)
                        dimStrip
                            .frame(width: max(0, holeLocal.minX), height: holeLocal.height)
                            .offset(x: 0, y: holeLocal.minY)
                        dimStrip
                            .frame(width: max(0, w - holeLocal.maxX), height: holeLocal.height)
                            .offset(x: holeLocal.maxX, y: holeLocal.minY)

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.42), lineWidth: 2)
                            .frame(width: holeLocal.width, height: holeLocal.height)
                            .position(x: holeLocal.midX, y: holeLocal.midY)
                            .allowsHitTesting(false)
                    }
                } else {
                    dimStrip
                        .frame(width: w, height: h)
                }

                tooltipCard
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    private var dimStrip: some View {
        Rectangle()
            .fill(Color.black.opacity(dimOverlayOpacity))
        .contentShape(Rectangle())
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Blog Settings")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Draft saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                (Text("Cover, title, fonts, backups, and more live behind the ") +
                    Text("gear").fontWeight(.semibold) +
                    Text("."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onOpenBlogSettings) {
                Text("Open Blog Settings")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.2), in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(22)
        .background(
            RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

// MARK: - Missing photos (other device) tooltip

private struct MissingPhotosTooltipOverlay: View {
    let onGotIt: () -> Void
    let onDoNotShowAgain: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(alignment: .leading, spacing: 14) {
                Text("Photos Not Available")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Photos for this blog are stored on another device.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text("This blog's text and structure were saved, but the photos remain on the original device.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button(action: onGotIt) {
                        Text("Got it")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.2), in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDoNotShowAgain) {
                        Text("Do not show again")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(24)
            .background(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.horizontal, 28)
        }
    }
}


#Preview {
    NavigationStack {
        RecapBlogPageView(blogId: UUID(), initialTrip: nil)
            .environmentObject(CreatedRecapBlogStore.shared)
            .environmentObject(TripNearbyShareSessionController.shared)
    }
}
