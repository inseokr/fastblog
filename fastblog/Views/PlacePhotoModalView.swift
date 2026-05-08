//
//  PlacePhotoModalView.swift
//  fastblog
//

import SwiftUI
import CoreLocation
import Photos
import UIKit
/// Typed + prompt styling for “Leave a story for this photo…” (full opacity, softer than pure white).
private enum PlacePhotoStoryCaptionFieldColor {
    static let text = Color(white: 0.88)
    /// Placeholder only — a touch brighter than typed text so it reads clearly on the dark overlay.
    static let placeholder = Color(white: 0.94)
}

private extension View {
    /// Keeps top chrome (Cancel/Done) from riding up when the keyboard or embedded browser panel appears.
    /// The photo+chrome ZStack must always fill the full screen so Cancel/Done stay anchored at the top.
    @ViewBuilder
    func placePhotoModalIgnoreKeyboardSafeAreaForPhotoLayer(_ active: Bool) -> some View {
        if active {
            // Ignore only the container safe area. Keeping keyboard safe-area behavior allows
            // the caption editor inset (place name + text field) to stay above the keyboard.
            self.ignoresSafeArea(.container, edges: .bottom)
        } else {
            self
        }
    }
}

/// Identifiable item for presenting the place photo modal (day + stop + initial photo).
struct PlacePhotoModalItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    let initialPhotoId: UUID
    var autoFocusCaption: Bool = false
    /// Open with the same inline caption chrome as blog edit (Cancel / Done, caption above keyboard), not read-only full photo.
    var openInCaptionEditor: Bool = false
    /// With `openInCaptionEditor`, omit top-bar Done — the parent caption edit overlay already has Save.
    var hideChromeDoneFromCaptionEditorSheet: Bool = false
    var id: String { "\(dayId.uuidString)-\(stopId.uuidString)-\(initialPhotoId.uuidString)" }
}

// MARK: - Fullscreen place presentation (shared chrome)

/// Entry point for a fullscreen / sheet place viewer; drives title-row affordances (e.g. Places Visited → blog).
enum PlaceDetailSource: Equatable {
    case blogRecap
    case blogMap
    case placesVisited
}

/// Sheet vs fullscreen overlay. All `fullscreen` sources share identical top chrome metrics and layout.
enum PlaceDetailPresentation: Equatable {
    case sheet
    case fullscreen(source: PlaceDetailSource)

    var isSheet: Bool {
        if case .sheet = self { return true }
        return false
    }

    var fullscreenSource: PlaceDetailSource? {
        if case .fullscreen(let s) = self { return s }
        return nil
    }

    /// Blog control belongs in the place title row (`BottomInfoOverlay`), not the top-right action stack.
    var showsBlogButtonInTitleRow: Bool {
        fullscreenSource == .placesVisited
    }
}

/// Single source of truth for place detail top chrome and matching horizontal rhythm with the bottom stack.
private enum PlaceDetailChromeLayout {
    static let horizontalPadding: CGFloat = 16
    static let actionStackSpacing: CGFloat = 14
    /// Fullscreen: inset header below the device safe top (status bar / Dynamic Island).
    static let fullscreenPaddingBelowSafeAreaTop: CGFloat = 2
    static let sheetGrabberTopPadding: CGFloat = 10
    /// Inner padding for the header row (below grabber for sheet; below safe-area inset for fullscreen).
    static let sheetInnerTopPadding: CGFloat = 20
    static let fullscreenInnerTopPadding: CGFloat = 6
    /// Fullscreen top fade: safe area + this height.
    static let fullscreenTopGradientExtensionBelowSafeArea: CGFloat = 120
    static let circleActionSize: CGFloat = 44
    /// Close / Cancel / Done / Save in `PlaceDetailTopChrome` — one font + pill size.
    static let headerPillHorizontalPadding: CGFloat = 12
    static let headerPillVerticalPadding: CGFloat = 6

    static func bottomContentVerticalPadding(sheet: Bool) -> CGFloat { sheet ? 20 : 14 }
    static func bottomContentHorizontalPadding(sheet: Bool) -> CGFloat { sheet ? 20 : horizontalPadding }
    static func thumbnailStripBottomPadding(sheet: Bool) -> CGFloat { sheet ? 8 : 4 }
    static func bottomGradientNegativeTopPadding(sheet: Bool) -> CGFloat { sheet ? -120 : -100 }
}

/// Presents when user taps a photo in a Place. Full-screen photo viewer with overlays.
///
/// **Fullscreen (blog timeline, blog map, Places Visited):** use `presentation: .fullscreen(source:)` so top chrome
/// matches across entry points. **Sheet (e.g. removed places):** use `presentation: .sheet` (default).
struct PlacePhotoModalView: View {
    private enum NavigationMapAppPreference: String {
        case apple
        case google
    }

    /// Same gradient as `PlaceStopRowView` “Generate story” (sparkles + caption).
    private static let aiStoryGenerationForegroundGradient = LinearGradient(
        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let navigationChooserSuppressedKey = "placePhotoNavigationChooserSuppressed"
    private static let navigationChooserPreferredAppKey = "placePhotoNavigationChooserPreferredApp"

    @Binding var placeTitle: String
    let placeSubtitle: String?
    /// Persisted POI category for this stop (passed into the rename sheet so Save preserves it).
    var initialPlaceCategory: String? = nil
    let photos: [RecapPhoto]
    let initialPhotoId: UUID
    /// EXIF digitized timestamp of the stop's earliest photo ("yyyy:MM:dd HH:mm:ss" local time).
    /// Used to derive the capture location's timezone for correct photo time display.
    let stopDigitizedTime: String?
    var blogIsEditMode: Bool = false
    /// When true (recap timeline not in edit mode), hides Edit Place Name / Edit caption in the ⋯ menu and inline place-title rename in the caption panel. Other fullscreen entry points (Places Visited, map) keep `false`.
    var recapBlogIsReadOnly: Bool = false
    /// When true, opens in the same caption-editing layout as blog edit (even if the recap timeline is not in edit mode).
    var openInCaptionEditor: Bool = false
    /// With `openInCaptionEditor`, hide top-trailing Done (parent `PlaceCaptionEditSheet` / `PhotoCaptionEditSheet` already has Save).
    var hideChromeDoneFromCaptionEditorSheet: Bool = false
    /// When false, hide PHAsset "Created/Modified" metadata lines (useful for read-only presentation).
    var showAssetTimeMetadata: Bool = true
    var autoFocusCaption: Bool = false
    /// Sheet (removed places, etc.) vs fullscreen overlay; all `fullscreen` sources use the same header layout.
    var presentation: PlaceDetailPresentation = .sheet
    var photoCaption: (UUID) -> Binding<String>
    var onDismiss: () -> Void
    /// Blog overlay: fire when the slide-off dismiss animation begins so the recap nav bar can show in sync with the panel.
    var onDismissSlideBegan: (() -> Void)? = nil
    var onViewBlog: (() -> Void)?
    /// When provided, a magic wand button is shown in the caption editing panel (only when user has written text).
    /// Called with (photo, placeName, placeSubtitle, userText); returns enriched caption.
    var onGenerateCaption: ((RecapPhoto, String, String?, String) async -> String)?
    /// When provided, a translate button is shown. Pure translation — no AI story generation.
    var onTranslateCaption: ((String) async -> String)? = nil
    /// Called after the AI wand applies a caption. Used to mark captionIsManual = false and cascade overall story.
    var onAICaptionApplied: ((UUID) -> Void)?
    /// Called when the user manually edits a photo caption in the modal. Used to mark captionIsManual = true.
    var onPhotoCaptionManuallyEdited: ((UUID) -> Void)?
    /// Called when the user chooses "Hide photo" from the kebab menu.
    var onRemovePhoto: ((UUID) -> Void)?
    /// Called when the user saves a place name edit from within this modal.
    /// Provides (newName, category, coordinate, subtitleLine) so the caller can update the store; subtitle is trimmed (empty clears).
    var onSavePlaceName: ((String, String?, CLLocationCoordinate2D?, String) -> Void)?
    /// When set, the bottom category chip / “Add category” pill opens `PlaceStopCategoryPickerSheet` and persists via this callback (`nil` = Others / none).
    var onSavePlaceCategory: ((String?) -> Void)? = nil
    /// When true (e.g. Places Visited grid “Add category”), presents the category sheet once after the modal appears.
    var presentPlaceCategoryPickerOnAppear: Bool = false
    /// Called when the user commits the caption (Done/Save). Use to sync story to cloud.
    var onCaptionCommitted: ((UUID) -> Void)? = nil

    @State private var currentPhotoId: UUID
    @State private var isGeneratingCaption = false
    /// On-device “AI story” for the current photo caption (LLM capable **and** Vision tags present).
    @State private var isGeneratingFunPhotoInsight = false
    @State private var currentPhotoHasVisionTagsForAIStory = false
    @State private var isTranslatingCaption = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    // Vibe
    @StateObject private var vibePlayer = VibePlayer()
    @State private var isVibeEnabled: Bool = false
    /// Drives the cyan dot pulse on the top-center “Playing Vibe” pill (same rhythm as camera “Capturing Vibe”).
    @State private var playingVibePulse: Bool = false
    // Voice memo
    @StateObject private var voiceMemoPlayer = VibePlayer()
    /// Stores the user's original caption text per photo before AI first enhances it, enabling "Revert to original".
    @State private var captionOriginalDraftByPhotoId: [UUID: String] = [:]
    @State private var isZoomMode = false
    @State private var accumulatedZoomScale: CGFloat = 1.0
    @State private var accumulatedDragOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragState: CGSize = .zero
    @State private var isEditing = false
    @State private var editedCaptionText: String = ""
    @State private var editedPlaceTitle: String = ""
    /// Caption and Title when user entered edit mode; used by Cancel to revert with no save.
    @State private var captionWhenEditingStarted: String = ""
    @State private var titleWhenEditingStarted: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showSaveConfirmationAlert = false
    @State private var resolvedTimeZoneByPhotoId: [UUID: TimeZone] = [:]
    @FocusState private var isCaptionFocused: Bool
    @State private var showRenameSheet = false
    @State private var showNavigationAppChooser = false
    @State private var showPlaceGoogleSearchSheet = false
    @State private var navigationDoNotShowAgain = false
    @AppStorage(Self.navigationChooserSuppressedKey) private var navigationChooserSuppressed = false
    @AppStorage(Self.navigationChooserPreferredAppKey) private var navigationChooserPreferredAppRaw = ""
    @AppStorage("bloggo.camera.saveToPhotosEnabled") private var saveToPhotosEnabled: Bool = false
    /// When non-nil, replaces `placeSubtitle` for display after an in-modal rename (empty clears the line).
    @State private var subtitleOverride: String? = nil
    /// Local category (picker or rename) so choosing “Others” (`nil`) does not fall back to `initialPlaceCategory`.
    @State private var hasLocalPlaceCategoryOverride: Bool = false
    @State private var localPlaceCategoryRaw: String? = nil
    @State private var showPlaceCategoryPicker = false
    @State private var didPresentInitialPlaceCategoryPicker = false
    /// Read-only bottom overlay: multi-line captions start collapsed; user can expand.
    @State private var isReadOnlyCaptionExpanded = false
    @State private var downloadToast: String?
    /// Vertical drag for swipe-down dismiss (blog overlay & sheets without a drag indicator).
    @State private var interactiveDismissDragOffset: CGFloat = 0
    @State private var isDismissExitAnimating = false
    /// While non-nil, TabView paging is locked to this id so dismiss drags can’t swap photos or reload neighbors.
    @State private var dismissFrozenPhotoId: UUID?
    /// PHAsset time metadata for the current photo (creationDate, modificationDate). Loaded when photo has localIdentifier.
    @State private var currentPhotoAssetMetadata: (creation: Date?, modification: Date?)?
    /// Derived capture offset (same algorithm as ``PlaceStop.inferredCaptureTimeZone``).
    private var captureTimeZone: TimeZone? {
        PlaceStop.inferredCaptureTimeZone(
            visitedDigitized: stopDigitizedTime,
            photoTimestamps: photos.map(\.timestamp)
        )
    }

    /// Effective timezone for the current photo: per-photo cache first (so all photos get correct time), then derived from digitized, then device.
    private var effectiveTimeZone: TimeZone {
        resolvedTimeZoneByPhotoId[effectiveDisplayedPhotoId] ?? captureTimeZone ?? .current
    }

    /// Photo id driving on-screen metadata and TabView selection; frozen during dismiss drag / exit animation.
    private var effectiveDisplayedPhotoId: UUID {
        dismissFrozenPhotoId ?? currentPhotoId
    }

    private var isPhotoPagingLocked: Bool {
        dismissFrozenPhotoId != nil
    }

    private var tabSelectionBinding: Binding<UUID> {
        Binding(
            get: { effectiveDisplayedPhotoId },
            set: { newValue in
                guard dismissFrozenPhotoId == nil else { return }
                currentPhotoId = newValue
            }
        )
    }

    /// Timezone label for UI. Uses named abbreviation (e.g. PST) when available; for offset-only zones
    /// (e.g. from EXIF) shows "UTC−8" instead of "GMT-8" so all photos use a consistent style.
    private static func timeZoneDisplayLabel(for tz: TimeZone) -> String {
        let abbr = tz.abbreviation() ?? tz.identifier
        if abbr.hasPrefix("GMT+") || abbr.hasPrefix("GMT-") {
            let seconds = tz.secondsFromGMT()
            let hours = seconds / 3600
            let mins = abs(seconds % 3600) / 60
            if mins == 0 {
                return hours >= 0 ? "UTC+\(hours)" : "UTC−\(-hours)"
            }
            let sign = hours >= 0 ? "+" : "−"
            return String(format: "UTC%@%d:%02d", sign, abs(hours), mins)
        }
        return abbr
    }

    /// Subtitle for search / AI / rename seed; reflects in-modal edits before the parent reloads.
    private var effectivePlaceSubtitle: String? {
        if let override = subtitleOverride {
            let t = override.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return placeSubtitle
    }

    /// Matches recap place row / ``StoryPlaceGoogleSearch`` — used to show or hide web search affordances.
    private var canOpenPlaceWebSearch: Bool {
        StoryPlaceGoogleSearch.url(placeName: placeTitle, placeSubtitle: effectivePlaceSubtitle) != nil
    }

    private var effectivePlaceCategoryRaw: String? {
        if hasLocalPlaceCategoryOverride {
            let raw = localPlaceCategoryRaw
            let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let t = (initialPlaceCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Seed for category picker / rename sheet (preserves explicit clear vs inherited initial).
    private var categoryPickerSeedRaw: String? {
        if hasLocalPlaceCategoryOverride { return localPlaceCategoryRaw }
        return initialPlaceCategory
    }

    private var canEditPlaceCategoryFromOverlay: Bool {
        onSavePlaceCategory != nil && !recapBlogIsReadOnly
    }

    /// Earliest photo in this stop by timestamp (same as used for place stop visit time).
    private var earliestPhoto: RecapPhoto? {
        photos.min(by: { $0.timestamp < $1.timestamp })
    }

    /// True when the current photo is the earliest in the stop, so we can show the same visit time as the place stop row.
    private var isCurrentPhotoEarliest: Bool {
        guard let photo = currentPhoto, let earliest = earliestPhoto else { return false }
        return photo.id == earliest.id
    }

    init(
        placeTitle: Binding<String>,
        placeSubtitle: String?,
        initialPlaceCategory: String? = nil,
        photos: [RecapPhoto],
        initialPhotoId: UUID,
        stopDigitizedTime: String? = nil,
        blogIsEditMode: Bool = false,
        recapBlogIsReadOnly: Bool = false,
        openInCaptionEditor: Bool = false,
        hideChromeDoneFromCaptionEditorSheet: Bool = false,
        showAssetTimeMetadata: Bool = true,
        autoFocusCaption: Bool = false,
        presentation: PlaceDetailPresentation = .sheet,
        presentPlaceCategoryPickerOnAppear: Bool = false,
        photoCaption: @escaping (UUID) -> Binding<String>,
        onDismiss: @escaping () -> Void,
        onDismissSlideBegan: (() -> Void)? = nil,
        onViewBlog: (() -> Void)? = nil,
        onGenerateCaption: ((RecapPhoto, String, String?, String) async -> String)? = nil,
        onTranslateCaption: ((String) async -> String)? = nil,
        onAICaptionApplied: ((UUID) -> Void)? = nil,
        onPhotoCaptionManuallyEdited: ((UUID) -> Void)? = nil,
        onRemovePhoto: ((UUID) -> Void)? = nil,
        onSavePlaceName: ((String, String?, CLLocationCoordinate2D?, String) -> Void)? = nil,
        onSavePlaceCategory: ((String?) -> Void)? = nil,
        onCaptionCommitted: ((UUID) -> Void)? = nil
    ) {
        self._placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.initialPlaceCategory = initialPlaceCategory
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.stopDigitizedTime = stopDigitizedTime
        self.blogIsEditMode = blogIsEditMode
        self.recapBlogIsReadOnly = recapBlogIsReadOnly
        self.openInCaptionEditor = openInCaptionEditor
        self.hideChromeDoneFromCaptionEditorSheet = hideChromeDoneFromCaptionEditorSheet
        self.showAssetTimeMetadata = showAssetTimeMetadata
        self.autoFocusCaption = autoFocusCaption
        self.presentation = presentation
        self.presentPlaceCategoryPickerOnAppear = presentPlaceCategoryPickerOnAppear
        self.photoCaption = photoCaption
        self.onDismiss = onDismiss
        self.onDismissSlideBegan = onDismissSlideBegan
        self.onViewBlog = onViewBlog
        self.onGenerateCaption = onGenerateCaption
        self.onTranslateCaption = onTranslateCaption
        self.onAICaptionApplied = onAICaptionApplied
        self.onPhotoCaptionManuallyEdited = onPhotoCaptionManuallyEdited
        self.onRemovePhoto = onRemovePhoto
        self.onSavePlaceName = onSavePlaceName
        self.onSavePlaceCategory = onSavePlaceCategory
        self.onCaptionCommitted = onCaptionCommitted
        _currentPhotoId = State(initialValue: initialPhotoId)
        // Blog edit or caption-sheet handoff: caption editor from the first frame (no onAppear flip).
        _isEditing = State(initialValue: blogIsEditMode || openInCaptionEditor)
    }

    /// Inline caption panel + top chrome aligned with blog edit (`Cancel` / `Done`), including when opened from caption edit sheets.
    /// When true, caption editing uses the same keyboard panel and photo dimming as blog edit mode (not the frosted read-path bar).
    private var usesInlineCaptionChrome: Bool {
        blogIsEditMode || openInCaptionEditor || isEditing
    }

    private var currentPhoto: RecapPhoto? {
        photos.first { $0.id == effectiveDisplayedPhotoId } ?? photos.first
    }

    private var currentPhotoLocalIdentifier: String? {
        let id = currentPhoto?.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? nil : id
    }

    private var isCurrentPhotoFromInAppCameraStorage: Bool {
        guard let id = currentPhotoLocalIdentifier else { return false }
        return id.hasPrefix(AppCapturePhotoService.prefix)
    }

    /// Manual download is only needed for Bloggo-stored in-app captures when camera auto-save is off.
    private var shouldShowManualDownloadAction: Bool {
        isCurrentPhotoFromInAppCameraStorage && !saveToPhotosEnabled
    }

    /// Device-level safe area insets from UIKit — bypasses SwiftUI's navigation-stack-consumed safe area
    /// so fullscreen overlays presented inside a NavigationStack get the correct top/bottom values.
    private var deviceSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    /// Full window height for sizing the embedded browser (matches dismiss math; avoids depending on `GeometryReader` in the inset).
    private var referenceScreenBoundsHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.height
            ?? UIScreen.main.bounds.height
    }

    /// Local vibe file URL for the current photo, if it was captured with the in-app camera and has a Vibe clip.
    private var currentVibeURL: URL? {
        guard let id = currentPhoto?.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.vibeFileURL(for: captureId)
    }

    /// Local voice memo URL for the current photo, if one was explicitly recorded.
    private var currentVoiceMemoURL: URL? {
        guard let id = currentPhoto?.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.voiceMemoFileURL(for: captureId)
    }

    private var currentCaption: String {
        photoCaption(currentPhotoId).wrappedValue
    }

    private func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Full-screen / blog overlay: inset bottom chrome to clear the home indicator.
    /// Keep recap/map visual rhythm unchanged; Places Visited needs this extra lift
    /// because its title row can include an additional trailing action.
    private func bottomPhotoChromeInset(safeBottom: CGFloat) -> CGFloat {
        if presentation.isSheet { return 0 }
        if presentation.fullscreenSource == .placesVisited {
            return safeBottom
        }
        return 0
    }

    /// Title-row “View blog” only for Places Visited; never in the top-right stack.
    private var titleRowOnViewBlog: (() -> Void)? {
        guard presentation.showsBlogButtonInTitleRow, !blogIsEditMode, let onViewBlog else { return nil }
        return onViewBlog
    }

    private var hasAnyChanges: Bool {
        trim(editedCaptionText) != trim(captionWhenEditingStarted) ||
        trim(editedPlaceTitle) != trim(titleWhenEditingStarted)
    }

    /// Whether an interactive swipe-down should move / dismiss the modal (not while zoomed or a child sheet is up).
    private var swipeToDismissEnabled: Bool {
        !isZoomMode && !showRenameSheet && !isDismissExitAnimating
    }

    private var dismissDragOverlayOpacity: Double {
        let y = Double(interactiveDismissDragOffset)
        guard y > 0 else { return 1 }
        let screenH = Double(UIScreen.main.bounds.height)
        // Stay opaque while sliding so the blog/map shows through the *uncovered* region (clear overlay / sheet bg),
        // not through a fading full-screen layer (which reads as a black hold before teardown).
        let startFadeAt = max(380, screenH * 0.7)
        guard y > startFadeAt else { return 1 }
        let span = max(140, screenH * 0.22)
        let t = min(1, (y - startFadeAt) / span)
        return max(0, 1 - t * t)
    }

    /// Close / Cancel / swipe-down share the same rules (including unsaved-changes alert).
    private func handleUserRequestedDismiss() {
        isCaptionFocused = false
        if !isEditing && !usesInlineCaptionChrome {
            animateSwipeDismissCompletion { onDismiss() }
            return
        }
        if hasAnyChanges {
            if openInCaptionEditor {
                // Nested full-screen viewer from caption edit: closing should save like Done, no confirmation.
                animateSwipeDismissCompletion {
                    commitCaption()
                    onDismiss()
                }
            } else {
                showSaveConfirmationAlert = true
            }
        } else {
            animateSwipeDismissCompletion {
                revertChanges()
                onDismiss()
            }
        }
    }

    /// Slides the modal the rest of the way off-screen, then runs `completion` (typically `onDismiss`).
    /// Uses a spring (not ease-in) so the finish matches system sheet / pull-modal dismiss: quick to start, smooth settle.
    private func animateSwipeDismissCompletion(_ completion: @escaping () -> Void) {
        let response: CGFloat = usesInlineCaptionChrome ? 0.02 : 0.02
        let damping: CGFloat = usesInlineCaptionChrome ? 0.10 : 0.10
        let settleNanoseconds: UInt64 = usesInlineCaptionChrome ? 260_000_000 : 400_000_000
        onDismissSlideBegan?()
        dismissFrozenPhotoId = currentPhotoId
        isDismissExitAnimating = true
        let h = UIScreen.main.bounds.height
        let baseline = interactiveDismissDragOffset
        let target = max(baseline + h * 0.42, h * 0.94)
        withAnimation(.spring(response: response, dampingFraction: damping, blendDuration: 0)) {
            interactiveDismissDragOffset = target
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: settleNanoseconds)
            completion()
        }
    }

    /// Downward drag must dominate horizontal movement so TabView paging never fights dismiss (diagonal swipes).
    private func isPrimarilyVerticalDismissDrag(dx: CGFloat, dy: CGFloat) -> Bool {
        dy > 0 && dy > abs(dx) * 1.75
    }

    private var photoModalSwipeDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard !isDismissExitAnimating, swipeToDismissEnabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.height
                guard isPrimarilyVerticalDismissDrag(dx: dx, dy: dy) else { return }
                guard dy > 115 || predicted > 220 else { return }
                let needsSaveAlert = (isEditing || usesInlineCaptionChrome) && hasAnyChanges && !openInCaptionEditor
                if needsSaveAlert {
                    showSaveConfirmationAlert = true
                } else {
                    handleUserRequestedDismiss()
                }
            }
    }

    @ViewBuilder
    private func photoModalMainStack(geo: GeometryProxy) -> some View {
        ZStack {
                // 1. Full screen media viewer — horizontal ScrollView with paging (not TabView) so the
                // sheet’s drag-to-dismiss doesn’t steal horizontal swipes. Tap/double-tap to zoom (same flow as non-modal).
                fullScreenPhotoView
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            if isCaptionFocused {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } else if !isZoomMode, !isEditing {
                                enterZoomMode()
                            }
                        }
                    )
                    .task(id: currentPhotoId) {
                        // Stop any playing Vibe; when the header vibe control is available, auto-play once per landed photo.
                        vibePlayer.stop()
                        voiceMemoPlayer.stop()
                        let canUseVibeChrome = !isEditing && !blogIsEditMode && !openInCaptionEditor
                        if canUseVibeChrome, let url = currentVibeURL {
                            isVibeEnabled = true
                            vibePlayer.play(url: url)
                        } else {
                            isVibeEnabled = false
                        }
                    }
                    .onChange(of: vibePlayer.naturalFinishCount) { _, _ in
                        // After one full play, return to idle so the waveform reads inactive; user can tap to replay.
                        isVibeEnabled = false
                    }
                    .task(id: currentPhotoId) {
                        // Resolve timezone per photo so every photo (not just the first) shows correct local time.
                        let photoId = currentPhotoId
                        guard let photo = currentPhoto, let loc = photo.location else { return }
                        let cl = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                        guard let tz = await GeocodingService.shared.timeZone(for: cl) else { return }
                        guard currentPhotoId == photoId else { return }
                        var updated = resolvedTimeZoneByPhotoId
                        updated[photoId] = tz
                        resolvedTimeZoneByPhotoId = updated
                    }
                    .task(id: currentPhotoId) {
                        // Load PHAsset time metadata (creation, modification) for the current photo.
                        let photoId = currentPhotoId
                        guard let photo = currentPhoto, let id = photo.localIdentifier, !id.isEmpty else {
                            currentPhotoAssetMetadata = nil
                            return
                        }
                        let result = await Task.detached(priority: .userInitiated) {
                            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                            guard let asset = result.firstObject else { return (creation: nil as Date?, modification: nil as Date?) }
                            return (creation: asset.creationDate, modification: asset.modificationDate)
                        }.value
                        guard currentPhotoId == photoId else { return }
                        currentPhotoAssetMetadata = result
                    }
                    .overlay(alignment: .bottom) {
                        let bottomInset = bottomPhotoChromeInset(safeBottom: deviceSafeAreaInsets.bottom)
                        VStack(spacing: 0) {
                            if !isEditing {
                                BottomInfoOverlay(
                                    placeTitle: placeTitle,
                                    dateTimeText: dateTimeTextForCurrentPhoto,
                                    hasVoiceMemo: currentVoiceMemoURL != nil,
                                    isVoiceMemoPlaying: voiceMemoPlayer.isPlaying,
                                    assetTimeMetadataLines: assetTimeMetadataLinesForCurrentPhoto,
                                    showAssetTimeMetadata: showAssetTimeMetadata,
                                    isEditing: $isEditing,
                                    captionText: $editedCaptionText,
                                    isCaptionExpanded: $isReadOnlyCaptionExpanded,
                                    placeholder: "Leave a story for this photo...",
                                    blogIsEditMode: usesInlineCaptionChrome,
                                    contentVerticalPadding: PlaceDetailChromeLayout.bottomContentVerticalPadding(sheet: presentation.isSheet),
                                    contentHorizontalPadding: PlaceDetailChromeLayout.bottomContentHorizontalPadding(sheet: presentation.isSheet),
                                    onTitleTap: recapBlogIsReadOnly ? nil : {
                                        isCaptionFocused = false
                                        showRenameSheet = true
                                    },
                                    onViewBlog: titleRowOnViewBlog,
                                    onToggleVoiceMemo: {
                                        guard let memoURL = currentVoiceMemoURL else { return }
                                        if voiceMemoPlayer.isPlaying {
                                            voiceMemoPlayer.stop()
                                        } else {
                                            vibePlayer.stop()
                                            isVibeEnabled = false
                                            voiceMemoPlayer.play(url: memoURL)
                                        }
                                    },
                                    onCommitCaption: { commitCaption() }
                                )
                            }

                            if !usesInlineCaptionChrome && !isEditing {
                                if photos.count > 1 {
                                    PlacePhotoThumbnailStrip(
                                        photos: photos,
                                        currentPhotoId: effectiveDisplayedPhotoId,
                                        onSelectPhoto: { currentPhotoId = $0 }
                                    )
                                    .disabled(isPhotoPagingLocked)
                                    .padding(.horizontal, PlaceDetailChromeLayout.horizontalPadding)
                                    .padding(.top, 0)
                                    .padding(.bottom, PlaceDetailChromeLayout.thumbnailStripBottomPadding(sheet: presentation.isSheet))
                                } else if let single = photos.first {
                                    HStack {
                                        RecapPhotoThumbnail(photo: single, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                                            .frame(width: 56, height: 56)
                                            .clipped()
                                            .appChromeCornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(appChromeBaseRadius: 8)
                                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                            )
                                        Spacer()
                                    }
                                    .padding(.horizontal, PlaceDetailChromeLayout.horizontalPadding)
                                    .padding(.bottom, PlaceDetailChromeLayout.thumbnailStripBottomPadding(sheet: presentation.isSheet))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, bottomInset)
                        .background(
                            (isEditing || isZoomMode) ? nil :
                            LinearGradient(
                                colors: [Color.black.opacity(0.9), Color.black.opacity(0.75), Color.black.opacity(0.45), Color.black.opacity(0.1), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            .padding(.top, PlaceDetailChromeLayout.bottomGradientNegativeTopPadding(sheet: presentation.isSheet))
                            .ignoresSafeArea(edges: .bottom)
                        )
                        .opacity(isZoomMode ? 0 : 1)
                        .animation(.easeInOut(duration: 0.25), value: isZoomMode)
                    }

            // Dim the photo while editing with the caption field focused so the panel reads clearly.
            // Applies to blog edit-mode chrome and non–recap-read-only caption edit (e.g. Places Visited) alike.
            if isEditing && isCaptionFocused {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 4. Shared top chrome (Close + actions): identical for every fullscreen source; sheet adds grabber.
            PlaceDetailTopChrome(
                safeAreaTop: deviceSafeAreaInsets.top,
                presentation: presentation,
                isEditing: isEditing,
                blogIsEditMode: blogIsEditMode,
                recapBlogIsReadOnly: recapBlogIsReadOnly,
                openInCaptionEditor: openInCaptionEditor,
                hideChromeDoneFromCaptionEditorSheet: hideChromeDoneFromCaptionEditorSheet,
                hasUnsavedChanges: hasUnsavedChanges,
                currentPhotoId: effectiveDisplayedPhotoId,
                hasVibeClip: currentVibeURL != nil,
                isVibeEnabled: isVibeEnabled,
                isVibePlaying: isVibeEnabled && vibePlayer.isPlaying,
                playingVibePulse: playingVibePulse,
                placeCategoryRaw: effectivePlaceCategoryRaw,
                onCategoryTap: canEditPlaceCategoryFromOverlay ? { showPlaceCategoryPicker = true } : nil,
                onLeadingPrimary: {
                    // Caption edit from kebab menu: "Cancel" should leave edit mode and
                    // return to read-only in the same full-screen viewer.
                    if isEditing && !blogIsEditMode && !openInCaptionEditor {
                        isCaptionFocused = false
                        revertChanges()
                    } else {
                        handleUserRequestedDismiss()
                    }
                },
                onSaveCaptionAndDismiss: {
                    commitCaption()
                },
                onDoneBlogEdit: {
                    if hasUnsavedChanges {
                        commitCaption()
                    }
                    animateSwipeDismissCompletion { onDismiss() }
                },
                onMenuEditPlaceName: { showRenameSheet = true },
                onMenuBeginCaptionEdit: {
                    captionWhenEditingStarted = currentCaption
                    titleWhenEditingStarted = placeTitle
                    editedCaptionText = currentCaption
                    editedPlaceTitle = placeTitle
                    isEditing = true
                    focusCaptionFieldOnNextLayout()
                },
                onMenuRemovePhoto: { photoId in onRemovePhoto?(photoId) },
                onToggleVibe: {
                    isVibeEnabled.toggle()
                    if isVibeEnabled, let url = currentVibeURL {
                        voiceMemoPlayer.stop()
                        vibePlayer.play(url: url)
                    } else {
                        vibePlayer.stop()
                    }
                },
                onNavigate: { handleNavigationTap() },
                onLink: { presentPlaceGoogleSearchSheet() },
                canOpenWebSearch: canOpenPlaceWebSearch,
                showDownloadAction: shouldShowManualDownloadAction,
                onDownload: { saveCurrentInAppCaptureToPhotos() }
            )
            .ignoresSafeArea(.all, edges: presentation.isSheet ? [] : .top)
            // Hide top chrome while zoomed so it doesn’t compete with the full-screen photo overlay.
            .allowsHitTesting(!isZoomMode)
            .opacity(isZoomMode ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: isZoomMode)

            if let toast = downloadToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.72)))
                        .padding(.bottom, 32)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // 5. Zoom mode overlay — appears when user taps the photo
            if isZoomMode, let photo = currentPhoto {
                zoomablePhotoOverlay(photo: photo)
            }

        }
        // In blog-edit mode the caption `safeAreaInset` can shrink `geo.size.height`, which shifts top chrome.
        // Use full window height for the photo layer so chrome stays anchored; `ignoresSafeArea(.all, .bottom)` pins it.
        .frame(width: geo.size.width, height: usesInlineCaptionChrome ? referenceScreenBoundsHeight : geo.size.height)
        .placePhotoModalIgnoreKeyboardSafeAreaForPhotoLayer(usesInlineCaptionChrome)
        // Keep dismiss gesture on this stack only so structure stays stable (avoids TabView flash).
        .simultaneousGesture(photoModalSwipeDismissGesture)
        .onChange(of: vibePlayer.isPlaying) { _, playing in
            if playing {
                playingVibePulse = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard vibePlayer.isPlaying else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        playingVibePulse = true
                    }
                }
            } else {
                playingVibePulse = false
            }
        }
        .animation(.easeInOut(duration: 0.2), value: downloadToast != nil)
    }

    var body: some View {
        GeometryReader { geo in
            photoModalMainStack(geo: geo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .statusBar(hidden: false)
        .overlay {
            if showNavigationAppChooser {
                navigationAppChooserOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onDisappear {
            vibePlayer.stop()
            voiceMemoPlayer.stop()
        }
        .fullScreenCover(isPresented: $showRenameSheet) {
            EditPlaceStopNameSheet(
                placeTitle: $placeTitle,
                initialPlaceSubtitle: effectivePlaceSubtitle,
                initialPlaceCategory: categoryPickerSeedRaw,
                location: photos.compactMap({ $0.location?.clCoordinate }).first,
                photos: photos,
                onSave: { newName, coord, category, subtitleLine in
                    debugPrint("[Category] PlacePhotoModal onSave: name='\(newName)' category=\(category ?? "nil") subtitle='\(subtitleLine)' onSavePlaceName wired=\(onSavePlaceName != nil)")
                    placeTitle = newName
                    editedPlaceTitle = newName
                    titleWhenEditingStarted = newName
                    subtitleOverride = subtitleLine
                    hasLocalPlaceCategoryOverride = true
                    localPlaceCategoryRaw = category
                    onSavePlaceName?(newName, category, coord, subtitleLine)
                }
            )
        }
        .sheet(isPresented: $showPlaceCategoryPicker) {
            PlaceStopCategoryPickerSheet(
                initialCategoryRaw: categoryPickerSeedRaw,
                onCancel: { showPlaceCategoryPicker = false },
                onDone: { newCategory in
                    hasLocalPlaceCategoryOverride = true
                    localPlaceCategoryRaw = newCategory
                    onSavePlaceCategory?(newCategory)
                    showPlaceCategoryPicker = false
                }
            )
        }
        .sheet(isPresented: $showWritingStyleSheet) {
            StoryWritingStyleSheet()
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showPlaceGoogleSearchSheet) {
            PlaceGoogleSearchSheet(
                placeTitle: placeTitle,
                placeSubtitle: effectivePlaceSubtitle,
                displayTitle: placeTitle.cleanedAsPlaceTitle
            )
        }
        .confirmationDialog("Choose writing style", isPresented: $showEnhanceStylePicker, titleVisibility: .visible) {
            Button("Use \(currentStyleTitle)") {
                runEnhanceForCurrentPhoto(preset: nil)
            }
            ForEach(StoryWritingStyle.presets) { preset in
                Button(preset.title) {
                    runEnhanceForCurrentPhoto(preset: preset)
                }
            }
            Button("Custom guideline...") {
                showWritingStyleSheet = true
            }
            Button("Cancel", role: .cancel) {}
        }
        // Editing panel anchors just above the keyboard via safeAreaInset
        .safeAreaInset(edge: .bottom, spacing: 0) {
            photoModalCaptionEditingInset
        }
        .offset(y: interactiveDismissDragOffset)
        .opacity(dismissDragOverlayOpacity)
        // Avoid UIKit sheet dismiss + this view’s vertical offset both driving the same drag (jitter, uneven speed).
        .interactiveDismissDisabled(true)
        .alert("Update caption?", isPresented: $showSaveConfirmationAlert) {
            Button("Update") {
                commitCaption()
                animateSwipeDismissCompletion { onDismiss() }
            }
            Button("Keep Editing", role: .cancel) { }
            Button("Leave", role: .destructive) {
                revertChanges()
                animateSwipeDismissCompletion { onDismiss() }
            }
        } message: {
            Text("Your changes will be lost if you leave")
        }
        .onAppear {
            dismissFrozenPhotoId = nil
            isDismissExitAnimating = false
            editedCaptionText = currentCaption
            editedPlaceTitle = placeTitle
            if usesInlineCaptionChrome {
                captionWhenEditingStarted = currentCaption
                titleWhenEditingStarted = placeTitle
                // `isEditing` is already true from init when `blogIsEditMode` or `openInCaptionEditor`.
                if autoFocusCaption {
                    // Caption row open: keyboard + inset are intended to be immediate, not a second-phase state change.
                    var t = Transaction()
                    t.animation = nil
                    withTransaction(t) {
                        isCaptionFocused = true
                    }
                } else {
                    isCaptionFocused = false
                }
            } else {
                // In non-editing mode, ensure stale focus state doesn't intercept photo taps.
                // Otherwise a tap may only dismiss focus instead of entering zoom.
                isEditing = false
                isCaptionFocused = false
            }
            if presentPlaceCategoryPickerOnAppear, !didPresentInitialPlaceCategoryPicker {
                didPresentInitialPlaceCategoryPicker = true
                if canEditPlaceCategoryFromOverlay {
                    DispatchQueue.main.async {
                        showPlaceCategoryPicker = true
                    }
                }
            }
        }
        .onChange(of: currentPhotoId) { _, _ in
            guard !isDismissExitAnimating, dismissFrozenPhotoId == nil else { return }
            isReadOnlyCaptionExpanded = false
            interactiveDismissDragOffset = 0
            editedCaptionText = currentCaption
            if isEditing {
                captionWhenEditingStarted = currentCaption
                // Place Title is same for all photos in this modal
            }
        }
        .task(id: currentPhotoId) {
            let id = currentPhotoId
            guard LocalLLMStoryCaptionGenerator.isCapable,
                  let p = photos.first(where: { $0.id == id }) else {
                await MainActor.run {
                    if currentPhotoId == id { currentPhotoHasVisionTagsForAIStory = false }
                }
                return
            }
            let has = await StoryCaptionService.shared.photoHasAnalyzedVisionTags(photo: p)
            await MainActor.run {
                guard currentPhotoId == id else { return }
                currentPhotoHasVisionTagsForAIStory = has
            }
        }
        .onChange(of: photos) { oldPhotos, newPhotos in
            // If the currently-displayed photo was just hidden, navigate to the nearest remaining photo.
            guard !newPhotos.contains(where: { $0.id == currentPhotoId }) else { return }
            if let oldIndex = oldPhotos.firstIndex(where: { $0.id == currentPhotoId }) {
                let targetIndex = min(oldIndex, newPhotos.count - 1)
                if targetIndex >= 0 {
                    currentPhotoId = newPhotos[targetIndex].id
                }
            } else if let first = newPhotos.first {
                currentPhotoId = first.id
            }
        }
        .onChange(of: editedCaptionText) { _, newValue in
            guard isEditing else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                photoCaption(currentPhotoId).wrappedValue = newValue
                if !isGeneratingCaption && !isGeneratingFunPhotoInsight {
                    onPhotoCaptionManuallyEdited?(currentPhotoId)
                }
            }
        }
    }

    private var navigationAppChooserOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    showNavigationAppChooser = false
                }

            VStack(spacing: 14) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.green)
                    .padding(.top, 4)

                Text("Navigate")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Pick your preferred map app to start directions instantly.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                Toggle(isOn: $navigationDoNotShowAgain) {
                    Text("Do not show again")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .tint(.green)
                .padding(.top, 2)

                VStack(spacing: 10) {
                    Button(action: { chooseNavigationApp(.apple) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Apple Maps")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 14)
                        .background(Color.gray.opacity(0.42), in: RoundedRectangle(appChromeBaseRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: { chooseNavigationApp(.google) }) {
                        HStack(spacing: 10) {
                            googleMapsLogoBadge
                            Text("Google Maps")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 14)
                        .background(Color.gray.opacity(0.42), in: RoundedRectangle(appChromeBaseRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(22)
            .background(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
            .padding(.horizontal, 26)
        }
    }

    private var googleMapsLogoBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Text("G")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
        .frame(width: 18, height: 18)
    }

    /// Caption editor above the keyboard — blog edit mode, caption-sheet handoff, or other fullscreen contexts that allow caption editing.
    @ViewBuilder
    private var photoModalCaptionEditingInset: some View {
        if isEditing {
            photoModalBlogInlineCaptionEditingPanel
        }
    }

    /// Caption field + place title (matches blog edit-mode place row: tap name or pencil to rename).
    @ViewBuilder
    private var photoModalBlogInlineCaptionEditingPanel: some View {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            if !dateTimeTextForCurrentPhoto.isEmpty {
                                VStack(spacing: 6) {
                                    HStack {
                                        Spacer(minLength: 0)
                                        Text(dateTimeTextForCurrentPhoto)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(Color.black.opacity(0.52))
                                            )
                                        Spacer(minLength: 0)
                                    }
                                    if currentVoiceMemoURL != nil {
                                        HStack {
                                            Spacer(minLength: 0)
                                            Button {
                                                guard let memoURL = currentVoiceMemoURL else { return }
                                                if voiceMemoPlayer.isPlaying {
                                                    voiceMemoPlayer.stop()
                                                } else {
                                                    vibePlayer.stop()
                                                    isVibeEnabled = false
                                                    voiceMemoPlayer.play(url: memoURL)
                                                }
                                            } label: {
                                                Label(voiceMemoPlayer.isPlaying ? "Stop voice memo" : "Play voice memo", systemImage: voiceMemoPlayer.isPlaying ? "stop.circle.fill" : "mic.fill")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(
                                                        Capsule(style: .continuous)
                                                            .fill(Color.blue.opacity(0.85))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }

                            Group {
                                if recapBlogIsReadOnly {
                                    Text(editedPlaceTitle)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    HStack(alignment: .top, spacing: 10) {
                                        Button {
                                            isCaptionFocused = false
                                            showRenameSheet = true
                                        } label: {
                                            Text(editedPlaceTitle)
                                                .font(.title3)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            isCaptionFocused = false
                                            showRenameSheet = true
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.white.opacity(0.22))
                                                Image(systemName: "square.and.pencil")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(.white)
                                            }
                                            .frame(width: 28, height: 28)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Edit place name")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                        .padding(.bottom, 4)

                        TextField(
                            "",
                            text: $editedCaptionText,
                            prompt: Text("Leave a story for this photo...")
                                .foregroundColor(PlacePhotoStoryCaptionFieldColor.placeholder),
                            axis: .vertical
                        )
                            .focused($isCaptionFocused)
                            .textFieldStyle(.plain)
                            .tint(PlacePhotoStoryCaptionFieldColor.text)
                            .font(.body)
                            .foregroundColor(PlacePhotoStoryCaptionFieldColor.text)
                            .lineLimit(2...6)
                            .padding(12)

                        if LocalLLMStoryCaptionGenerator.isCapable && currentPhotoHasVisionTagsForAIStory && !photoCaptionBlocksAIShortStory {
                            HStack {
                                Spacer(minLength: 0)
                                if isGeneratingFunPhotoInsight {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.85)))
                                            .scaleEffect(0.75)
                                        Text("Thinking…")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                } else {
                                    Button(action: runFunPhotoInsightForCurrentPhoto) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                                .font(.caption)
                                                .foregroundStyle(Self.aiStoryGenerationForegroundGradient)
                                            Text("AI story")
                                                .font(.caption)
                                                .foregroundStyle(Self.aiStoryGenerationForegroundGradient)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isGeneratingCaption || isGeneratingFunPhotoInsight)
                                    .accessibilityLabel("Generate up to two sentences from on-device photo tags")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                        }

                        // Action bar — mirrors place story sheet layout
                        let trimmed = editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            HStack(spacing: 16) {
                                Button(role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        editedCaptionText = ""
                                        captionOriginalDraftByPhotoId.removeValue(forKey: currentPhotoId)
                                    }
                                } label: {
                                    Label("Clear", systemImage: "trash")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                Spacer()

                                if let originalDraft = captionOriginalDraftByPhotoId[currentPhotoId] {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            editedCaptionText = originalDraft
                                            captionOriginalDraftByPhotoId.removeValue(forKey: currentPhotoId)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.caption)
                                            Text("Revert")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white.opacity(0.75))
                                    }
                                    .accessibilityLabel("Revert caption")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    // Keep the caption panel/dark backdrop slightly higher above the keyboard.
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        // When the caption field is focused, transparent — dim overlay on the photo handles readability.
                        if !isCaptionFocused {
                            LinearGradient(
                                colors: [Color.black.opacity(0.9), Color.black.opacity(0.75), Color.black.opacity(0.45), Color.black.opacity(0.1), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            .ignoresSafeArea(.all, edges: .bottom)
                        }
                    }
    }

    /// Full-width paging photo viewer. TabView with page style gives reliable horizontal swipe
    /// in a sheet context — ScrollView(.horizontal) conflicts with the sheet's pan-to-dismiss.
    private var fullScreenPhotoView: some View {
        TabView(selection: tabSelectionBinding) {
            ForEach(photos) { photo in
                photoFullScreenImage(photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDisabled(isPhotoPagingLocked)
        .ignoresSafeArea()
    }

    /// Single tap or double tap enters zoom overlay (tap-to-zoom works the same in the modal as in the non-modal viewer).
    private func photoFullScreenImage(_ photo: RecapPhoto) -> some View {
        let singleTap = TapGesture().onEnded {
            guard !isZoomMode else { return }
            if isCaptionFocused {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } else if !isEditing {
                enterZoomMode()
            }
        }

        let doubleTap = TapGesture(count: 2).onEnded {
            guard !isZoomMode, !isEditing else { return }
            enterZoomMode()
        }

        // Prefer double-tap semantics over single-tap when the user taps quickly.
        let tapGesture = doubleTap.exclusively(before: singleTap)

        // With multiple photos, TabView paging must win horizontal drags. `HorizontalPanOverlay` would otherwise
        // capture them for in-photo pan on wide shots (see HorizontalScrollablePhotoView).
        return HorizontalScrollablePhotoView(
            photo: photo,
            allowsIntrinsicHorizontalPan: photos.count <= 1
        )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .highPriorityGesture(tapGesture)
    }

    private func enterZoomMode() {
        accumulatedZoomScale = 1.0
        accumulatedDragOffset = .zero
        withAnimation(.easeInOut(duration: 0.25)) { isZoomMode = true }
    }

    private func exitZoomMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isZoomMode = false
            accumulatedZoomScale = 1.0
            accumulatedDragOffset = .zero
        }
    }

    /// Single tap exits zoom back to the place chrome; double-tap also exits without firing a lone single tap first (avoids re-entering zoom on the page below).
    private func zoomOverlayTapToExitGesture() -> some Gesture {
        let doubleTap = TapGesture(count: 2).onEnded { exitZoomMode() }
        let singleTap = TapGesture(count: 1).onEnded { exitZoomMode() }
        return doubleTap.exclusively(before: singleTap)
    }

    @ViewBuilder
    private func zoomablePhotoOverlay(photo: RecapPhoto) -> some View {
        let scale = max(1.0, accumulatedZoomScale * pinchScale)
        let offset = CGSize(
            width: accumulatedDragOffset.width + dragState.width,
            height: accumulatedDragOffset.height + dragState.height
        )

        ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea()

            RecapPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false, targetSize: CGSize(width: 1200, height: 1200))
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .updating($pinchScale) { current, state, _ in state = current }
                            .onEnded { value in
                                let newScale = max(1.0, min(5.0, accumulatedZoomScale * value))
                                if newScale <= 1.05 {
                                    exitZoomMode()
                                } else {
                                    accumulatedZoomScale = newScale
                                }
                            },
                        DragGesture(minimumDistance: 5)
                            .updating($dragState) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                accumulatedDragOffset = CGSize(
                                    width: accumulatedDragOffset.width + value.translation.width,
                                    height: accumulatedDragOffset.height + value.translation.height
                                )
                            }
                    )
                )
                .highPriorityGesture(zoomOverlayTapToExitGesture())

            // Close button — always visible so user can exit zoom mode easily
            Button {
                exitZoomMode()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.top, max(8, deviceSafeAreaInsets.top - 2))
        }
    }

    private var dateTimeTextForCurrentPhoto: String {
        guard let photo = currentPhoto else { return "" }
        let tz = effectiveTimeZone
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMM yyyy 'at' h:mm a"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = tz

        // Prefer PHAsset creation date when available so the main "visited time" matches the photo's
        // actual metadata (e.g. after user manually changes date in Photos). This keeps the main
        // line consistent with the "Created:" line below.
        if let meta = currentPhotoAssetMetadata, let creation = meta.creation {
            return dateFmt.string(from: creation)
        }

        // When showing the earliest photo and no asset metadata yet, build from digitized string
        // so the modal and place stop row show the same visit time (avoids 15-min TZ rounding).
        if isCurrentPhotoEarliest, let digitized = stopDigitizedTime {
            let parts = digitized.split(separator: " ")
            if parts.count == 2 {
                let datePart = String(parts[0]) // "yyyy:MM:dd"
                let timePart = String(parts[1]) // "HH:mm:ss"
                let timeComponents = timePart.split(separator: ":")
                if timeComponents.count >= 2,
                   let hours = Int(timeComponents[0]),
                   let minutes = Int(timeComponents[1]) {
                    let period = hours >= 12 ? "PM" : "AM"
                    let h = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
                    let timeStr = "\(h):\(String(format: "%02d", minutes)) \(period)"
                    let dateParser = DateFormatter()
                    dateParser.dateFormat = "yyyy:MM:dd"
                    dateParser.timeZone = TimeZone(secondsFromGMT: 0)
                    dateParser.locale = Locale(identifier: "en_US_POSIX")
                    if let date = dateParser.date(from: datePart) {
                        let dateDisplay = DateFormatter()
                        dateDisplay.dateFormat = "d MMM yyyy"
                        dateDisplay.timeZone = TimeZone(secondsFromGMT: 0)
                        dateDisplay.locale = Locale(identifier: "en_US_POSIX")
                        return "\(dateDisplay.string(from: date)) at \(timeStr)"
                    }
                }
            }
        }

        // Fallback: use RecapPhoto.timestamp (e.g. from trip scan).
        return dateFmt.string(from: photo.timestamp)
    }

    /// Formatted PHAsset time metadata lines (creation, modification) with timezone, for display in the bottom overlay.
    private var assetTimeMetadataLinesForCurrentPhoto: [String] {
        guard let meta = currentPhotoAssetMetadata else { return [] }
        let tz = effectiveTimeZone
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMM yyyy 'at' h:mm a"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = tz
        var lines: [String] = []
        if let creation = meta.creation {
            lines.append("Created: \(dateFmt.string(from: creation))")
        }
        if let modification = meta.modification, meta.creation != modification {
            lines.append("Modified: \(dateFmt.string(from: modification))")
        }
        return lines
    }

    private var preferredNavigationApp: NavigationMapAppPreference? {
        NavigationMapAppPreference(rawValue: navigationChooserPreferredAppRaw)
    }

    private func handleNavigationTap() {
        guard currentPhoto?.location != nil else { return }
        if navigationChooserSuppressed, let preferredNavigationApp {
            openNavigation(with: preferredNavigationApp)
            return
        }
        navigationDoNotShowAgain = false
        showNavigationAppChooser = true
    }

    private func chooseNavigationApp(_ app: NavigationMapAppPreference) {
        if navigationDoNotShowAgain {
            navigationChooserSuppressed = true
            navigationChooserPreferredAppRaw = app.rawValue
        } else {
            navigationChooserSuppressed = false
        }
        showNavigationAppChooser = false
        openNavigation(with: app)
    }

    private func openNavigation(with app: NavigationMapAppPreference) {
        guard let location = currentPhoto?.location else { return }
        let lat = location.latitude
        let lon = location.longitude

        switch app {
        case .apple:
            let urlString = "http://maps.apple.com/?daddr=\(lat),\(lon)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        case .google:
            let nativeURL = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")
            if let nativeURL, UIApplication.shared.canOpenURL(nativeURL) {
                UIApplication.shared.open(nativeURL)
                return
            }
            let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)")
            if let webURL {
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    private func presentPlaceGoogleSearchSheet() {
        guard canOpenPlaceWebSearch else { return }
        showPlaceGoogleSearchSheet = true
    }

    private func saveCurrentInAppCaptureToPhotos() {
        guard let localId = currentPhotoLocalIdentifier,
              localId.hasPrefix(AppCapturePhotoService.prefix),
              let image = AppCapturePhotoService.shared.loadImage(identifier: localId) else {
            presentDownloadToast("Couldn't save to Photos")
            return
        }

        Task {
            var auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if auth == .notDetermined {
                auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
            guard auth == .authorized || auth == .limited else {
                await MainActor.run {
                    presentDownloadToast("Allow Photos access to save")
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                DispatchQueue.main.async {
                    presentDownloadToast(success ? "1 photo saved to Photos" : "Couldn't save to Photos")
                }
            }
        }
    }

    @MainActor
    private func presentDownloadToast(_ message: String) {
        downloadToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if downloadToast == message {
                    downloadToast = nil
                }
            }
        }
    }

    /// After `isEditing` becomes true, the caption `TextField` only exists inside `safeAreaInset`.
    /// Setting `FocusState` in the same update as `isEditing = true` often fails or defers first responder
    /// until a later layout pass, so yield once, then focus without inheriting slow implicit animations.
    private func focusCaptionFieldOnNextLayout() {
        Task { @MainActor in
            await Task.yield()
            guard isEditing else { return }
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                isCaptionFocused = true
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines) != captionWhenEditingStarted.trimmingCharacters(in: .whitespacesAndNewlines)
            || editedPlaceTitle.trimmingCharacters(in: .whitespacesAndNewlines) != titleWhenEditingStarted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentStyleTitle: String {
        StoryWritingStyle.preset(for: stylePresetId)?.title
            ?? StoryWritingStyle.preset(matching: UserDefaults.standard.string(forKey: StoryWritingStyle.storageKey) ?? "")?.title
            ?? "Custom"
    }

    private func runEnhanceForCurrentPhoto(preset: StoryWritingStylePreset?) {
        guard !isGeneratingFunPhotoInsight, let generate = onGenerateCaption, let photo = currentPhoto else { return }
        if let preset {
            stylePresetId = preset.id
            UserDefaults.standard.set(preset.prompt, forKey: StoryWritingStyle.storageKey)
        }
        let photoId = currentPhotoId
        if captionOriginalDraftByPhotoId[photoId] == nil {
            captionOriginalDraftByPhotoId[photoId] = editedCaptionText
        }
        isGeneratingCaption = true
        let userText = editedCaptionText
        Task {
            let text = await generate(photo, editedPlaceTitle, effectivePlaceSubtitle, userText)
            await MainActor.run {
                editedCaptionText = text
                photoCaption(photoId).wrappedValue = text
                isGeneratingCaption = false
                onAICaptionApplied?(photoId)
            }
        }
    }

    private func runTranslateForCurrentPhoto(_ translate: @escaping (String) async -> String) {
        guard !isGeneratingFunPhotoInsight else { return }
        let photoId = currentPhotoId
        if captionOriginalDraftByPhotoId[photoId] == nil {
            captionOriginalDraftByPhotoId[photoId] = editedCaptionText
        }
        isTranslatingCaption = true
        let userText = editedCaptionText
        Task {
            let text = await translate(userText)
            await MainActor.run {
                editedCaptionText = text
                photoCaption(photoId).wrappedValue = text
                isTranslatingCaption = false
            }
        }
    }

    /// True when the traveler already has a hand-written caption for this photo (hide on-device “AI story”).
    private var photoCaptionBlocksAIShortStory: Bool {
        guard let p = currentPhoto else { return false }
        return p.captionIsManual && !editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Short grounded blurb from on-device Vision tags + place/daypart (only when capable, tags exist, and no manual caption).
    private func runFunPhotoInsightForCurrentPhoto() {
        guard !isGeneratingCaption,
              LocalLLMStoryCaptionGenerator.isCapable,
              currentPhotoHasVisionTagsForAIStory,
              !photoCaptionBlocksAIShortStory,
              let photo = currentPhoto else { return }
        let photoId = currentPhotoId
        if captionOriginalDraftByPhotoId[photoId] == nil {
            captionOriginalDraftByPhotoId[photoId] = editedCaptionText
        }
        isGeneratingFunPhotoInsight = true
        isCaptionFocused = false
        let hintRaw = editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let text = await StoryCaptionService.shared.generateFunPhotoInsight(
                photo: photo,
                placeName: editedPlaceTitle,
                placeSubtitle: effectivePlaceSubtitle,
                placeCategoryMK: effectivePlaceCategoryRaw,
                visitTimeZone: effectiveTimeZone,
                userCaptionHint: hintRaw.isEmpty ? nil : hintRaw
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                isGeneratingFunPhotoInsight = false
                guard currentPhotoId == photoId else { return }
                if !trimmed.isEmpty {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        editedCaptionText = trimmed
                    }
                    photoCaption(photoId).wrappedValue = trimmed
                    onAICaptionApplied?(photoId)
                }
            }
        }
    }

    private func commitCaption() {
        let text = editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        photoCaption(currentPhotoId).wrappedValue = text
        let titleText = editedPlaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titleText.isEmpty {
            placeTitle = titleText
        }
        let committedPhotoId = currentPhotoId
        isEditing = false
        onCaptionCommitted?(committedPhotoId)
    }

    private func revertChanges() {
        editedCaptionText = captionWhenEditingStarted
        photoCaption(currentPhotoId).wrappedValue = captionWhenEditingStarted
        placeTitle = titleWhenEditingStarted
        isEditing = false
    }
}

// MARK: - Playing Vibe header pill (in-app camera “Capturing Vibe” styling)

private struct PlayingVibeHeaderPill: View {
    var pulse: Bool

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(pulse ? 0 : 0.45))
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
            }
            Text("Playing Vibe")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .background(Color.cyan.opacity(0.22))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.25), radius: 8)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playing vibe")
    }
}

// MARK: - Shared fullscreen / sheet top chrome

/// Single implementation of the place detail header: safe-area-aware insets, grabber (sheet only), Close / Cancel / Done, and the vertical action stack.
private struct PlaceDetailTopChrome: View {
    let safeAreaTop: CGFloat
    let presentation: PlaceDetailPresentation
    let isEditing: Bool
    let blogIsEditMode: Bool
    let recapBlogIsReadOnly: Bool
    let openInCaptionEditor: Bool
    let hideChromeDoneFromCaptionEditorSheet: Bool
    let hasUnsavedChanges: Bool
    let currentPhotoId: UUID
    let hasVibeClip: Bool
    let isVibeEnabled: Bool
    let isVibePlaying: Bool
    let playingVibePulse: Bool
    let placeCategoryRaw: String?
    let onCategoryTap: (() -> Void)?
    let onLeadingPrimary: () -> Void
    let onSaveCaptionAndDismiss: () -> Void
    let onDoneBlogEdit: () -> Void
    let onMenuEditPlaceName: () -> Void
    let onMenuBeginCaptionEdit: () -> Void
    let onMenuRemovePhoto: (UUID) -> Void
    let onToggleVibe: () -> Void
    let onNavigate: () -> Void
    let onLink: () -> Void
    let canOpenWebSearch: Bool
    let showDownloadAction: Bool
    let onDownload: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var topCenterCategoryPill: some View {
        if let raw = placeCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let onCategoryTap {
                Button(action: onCategoryTap) {
                    PlacePOICategoryBadge(rawCategory: raw)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change place category")
            } else {
                PlacePOICategoryBadge(rawCategory: raw)
            }
        } else if let onCategoryTap {
            Button(action: onCategoryTap) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.caption2)
                    Text("Add category")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change place category")
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(false)

            if !presentation.isSheet {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.52),
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: safeAreaTop + PlaceDetailChromeLayout.fullscreenTopGradientExtensionBelowSafeArea)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }

            if presentation.isSheet {
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, PlaceDetailChromeLayout.sheetGrabberTopPadding)
            }

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(alignment: .top) {
                        if openInCaptionEditor {
                            // Handoff from place/photo caption edit sheet — reads as leaving the viewer, not aborting an edit.
                            leadingCloseCircleButton(action: onLeadingPrimary)
                        } else if isEditing || blogIsEditMode {
                            capsuleButton(title: "Cancel", action: onLeadingPrimary)
                        } else {
                            leadingCloseCircleButton(action: onLeadingPrimary)
                        }

                        Spacer()

                        if !isEditing && !blogIsEditMode && !openInCaptionEditor {
                            // Trailing alignment keeps the waveform + ⋯ + nav/link column fixed when "Playing Vibe"
                            // appears; default center alignment re-centers a wider top row and shifts buttons.
                            VStack(alignment: .trailing, spacing: PlaceDetailChromeLayout.actionStackSpacing) {
                                Menu {
                                    if !recapBlogIsReadOnly {
                                        Button(action: onMenuEditPlaceName) {
                                            Label("Edit Place Name", systemImage: "mappin.and.ellipse")
                                        }
                                        Button(action: onMenuBeginCaptionEdit) {
                                            Label("Edit caption", systemImage: "text.alignleft")
                                        }
                                    }
                                    if canOpenWebSearch {
                                        Button(action: onLink) {
                                            Label("Web results", systemImage: "safari")
                                        }
                                    }
                                    Button {
                                        onMenuRemovePhoto(currentPhotoId)
                                    } label: {
                                        Label("Hide photo", systemImage: "minus.circle")
                                            .foregroundStyle(.white)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                                        .background(Color.white.opacity(0.22))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                                }
                                .frame(width: PlaceDetailChromeLayout.circleActionSize, alignment: .center)
                                .dynamicTypeSize(.xSmall ... .accessibility5)

                                RightActionStack(
                                    onSparkles: { },
                                    onNavigate: onNavigate,
                                    onLink: onLink,
                                    showWebSearchLink: canOpenWebSearch,
                                    showDownloadAction: showDownloadAction,
                                    onDownload: onDownload
                                )
                                .frame(width: PlaceDetailChromeLayout.circleActionSize, alignment: .center)

                                if hasVibeClip {
                                    Button(action: onToggleVibe) {
                                        AtmosphericWaveformView(isActive: isVibeEnabled)
                                            .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                                            .background(.ultraThinMaterial)
                                            .background(isVibeEnabled ? Color.cyan.opacity(0.22) : Color.clear)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle().stroke(
                                                    isVibeEnabled ? Color.cyan.opacity(0.5) : Color.clear,
                                                    lineWidth: 1
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isVibePlaying ? "Vibe playing" : "Play vibe")
                                    .frame(width: PlaceDetailChromeLayout.circleActionSize, alignment: .center)
                                }
                            }
                        } else if isEditing && !blogIsEditMode && !openInCaptionEditor {
                            accentHeaderPill(title: "Save", fill: Color.blue, action: onSaveCaptionAndDismiss)
                        } else if blogIsEditMode && !openInCaptionEditor {
                            blogEditPhotoSaveCapsule(action: onDoneBlogEdit)
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                        } else if openInCaptionEditor && !hideChromeDoneFromCaptionEditorSheet {
                            capsuleButton(title: "Done", action: onDoneBlogEdit)
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                        }
                    }

                    if !isEditing && !blogIsEditMode && !openInCaptionEditor {
                        topCenterCategoryPill
                            .padding(.top, 6)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
                .padding(.horizontal, PlaceDetailChromeLayout.horizontalPadding)
                .padding(.top, presentation.isSheet ? PlaceDetailChromeLayout.sheetInnerTopPadding : PlaceDetailChromeLayout.fullscreenInnerTopPadding)
            }
            .padding(.top, presentation.isSheet ? 0 : safeAreaTop +  PlaceDetailChromeLayout.fullscreenPaddingBelowSafeAreaTop)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func capsuleButton(title: String, action: @escaping () -> Void) -> some View {
        accentHeaderPill(title: title, fill: Color.black.opacity(0.35), action: action)
    }

    private func leadingCloseCircleButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                .background(Color.white.opacity(0.22))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func blogEditPhotoSaveCapsule(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Save")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .padding(.horizontal, PlaceDetailChromeLayout.headerPillHorizontalPadding)
                .padding(.vertical, PlaceDetailChromeLayout.headerPillVerticalPadding)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func accentHeaderPill(title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, PlaceDetailChromeLayout.headerPillHorizontalPadding)
                .padding(.vertical, PlaceDetailChromeLayout.headerPillVerticalPadding)
                .background(fill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top overlay controls

struct TopControlsRow: View {
    var onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                Text("Edit")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
            }
            .shadow(color: .black.opacity(0.4), radius: 2)

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Right side vertical action stack

struct RightActionStack: View {
    var onSparkles: () -> Void
    var onNavigate: () -> Void
    var onLink: () -> Void
    /// When false, hides the in-app web search control (no place query to open).
    var showWebSearchLink: Bool = true
    var showDownloadAction: Bool = false
    var onDownload: () -> Void = { }

    var body: some View {
        VStack(spacing: PlaceDetailChromeLayout.actionStackSpacing) {
/*
            Button(action: onSparkles) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
*/

            Button(action: onNavigate) {
                // Navigation icon replacing Share, and removed Heart/Comment/Bookmark
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.green)
            }
            .buttonStyle(.plain)

            if showWebSearchLink {
                Button(action: onLink) {
                    StoryPlaceExternalLinkIcon(titleFontSize: 22, foregroundColor: .white)
                        .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Web results for place")
            }

            if showDownloadAction {
                Button(action: onDownload) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                        .background(Color.blue.opacity(0.78))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save to Photos")
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2)
    }
}

// MARK: - Bottom overlay content block

struct BottomInfoOverlay: View {
    let placeTitle: String
    let dateTimeText: String
    var hasVoiceMemo: Bool = false
    var isVoiceMemoPlaying: Bool = false
    /// PHAsset time metadata lines (e.g. "Created: ... (PST)", "Modified: ... (PST)"); shown below dateTimeText when non-empty.
    var assetTimeMetadataLines: [String] = []
    /// When false, suppress Created/Modified metadata lines.
    var showAssetTimeMetadata: Bool = true
    @Binding var isEditing: Bool
    @Binding var captionText: String
    /// When read-only caption is long / multi-line, user can expand; parent resets when the photo changes.
    @Binding var isCaptionExpanded: Bool
    let placeholder: String
    var blogIsEditMode: Bool = false
    /// Tighter vertical padding when presented as full-screen overlay (not a sheet).
    var contentVerticalPadding: CGFloat = 20
    /// Matches top chrome / thumbnail strip (16 full-screen, 20 sheet).
    var contentHorizontalPadding: CGFloat = 20
    var onTitleTap: (() -> Void)? = nil
    /// Places Visited only: opens the source blog; trailing-aligned with the place title row.
    var onViewBlog: (() -> Void)? = nil
    var onToggleVoiceMemo: (() -> Void)? = nil
    var onCommitCaption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // Tappable place title — opens Edit Place Name when editing is available.
                    Button(action: { onTitleTap?() }) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(placeTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .lineLimit(1)
                            if onTitleTap != nil {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.22))
                                    Image(systemName: "link")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 28, height: 28)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(onTitleTap == nil)
                    .accessibilityLabel("Edit place name")

                    if let onViewBlog {
                        Button(action: onViewBlog) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.22))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View blog")
                    }
                }
            }

            if !dateTimeText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateTimeText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
            }

            if showAssetTimeMetadata {
                ForEach(assetTimeMetadataLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
            }

            if blogIsEditMode {
                // Caption input is now in safeAreaInset — show nothing here
                EmptyView()
            } else if isEditing {
                TextField(
                    "",
                    text: $captionText,
                    prompt: Text(placeholder).foregroundColor(PlacePhotoStoryCaptionFieldColor.placeholder),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(PlacePhotoStoryCaptionFieldColor.text)
                    .lineLimit(2...6)
                    .padding(10)
                    .onSubmit { onCommitCaption() }
                Button("Done") {
                    onCommitCaption()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            } else {
                if !captionText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(captionText)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(isCaptionExpanded ? nil : 2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(10)

                        if Self.captionMayNeedExpansion(captionText) || isCaptionExpanded {
                            Button {
                                isCaptionExpanded.toggle()
                            } label: {
                                Text(isCaptionExpanded ? "Show less" : "Show more")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.92))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .accessibilityHint(isCaptionExpanded ? "Collapses the photo caption" : "Shows the full photo caption")
                        }
                    }
                }
            }

            if hasVoiceMemo {
                Button(action: { onToggleVoiceMemo?() }) {
                    Label(isVoiceMemoPlaying ? "Stop voice memo" : "Play voice memo", systemImage: isVoiceMemoPlaying ? "stop.circle.fill" : "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.blue.opacity(0.85))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
                .buttonStyle(.plain)
                .disabled(onToggleVoiceMemo == nil)
            }
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.vertical, contentVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Heuristic: 2-line clamp likely truncates (extra paragraphs or a long single block that wraps).
    private static func captionMayNeedExpansion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let paragraphs = t.split(separator: "\n", omittingEmptySubsequences: false)
        if paragraphs.count > 2 { return true }
        return t.count > 110
    }
}

// MARK: - Bottom thumbnail strip (all photos when multiple; tap to navigate)

struct PlacePhotoThumbnailStrip: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID
    var onSelectPhoto: (UUID) -> Void

    /// AI rank badges (1–3) computed from quality scores.
    private var aiRanks: [UUID: Int] { photos.aiRanksByPhotoId() }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    Button {
                        onSelectPhoto(photo.id)
                    } label: {
                        ZStack(alignment: .topLeading) {
                            RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 300, height: 300))
                                .frame(width: 56, height: 56)
                                .clipped()
                                .appChromeCornerRadius(8)
                                .overlay(
                                    RoundedRectangle(appChromeBaseRadius: 8)
                                        .stroke(photo.id == currentPhotoId ? Color.white : Color.white.opacity(0.35), lineWidth: photo.id == currentPhotoId ? 2 : 1)
                                )
                            // AI rank badge on thumbnails
                            if let rank = aiRanks[photo.id] {
                                HStack(spacing: 1) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                    Text("\(rank)")
                                        .font(.system(size: 7, weight: .heavy))
                                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                }
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.72))
                                .appChromeCornerRadius(3)
                                .padding(3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 64)
    }
}

// MARK: - Bottom thumbnail preview (single thumbnail; used elsewhere if needed)

struct ThumbnailPreview: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID
    var onSelectPhoto: (UUID) -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let current = photos.first(where: { $0.id == currentPhotoId }) {
                RecapPhotoThumbnail(photo: current, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                    .frame(width: 56, height: 56)
                    .clipped()
                    .appChromeCornerRadius(8)
                    .overlay(
                        RoundedRectangle(appChromeBaseRadius: 8)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Place Name Sheet

private struct EditPlaceNameSheet: View {
    let currentName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Edit Place Name")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundColor(.secondary)
            }

            HStack {
                TextField("Place name", text: $nameText)
                    .focused($isNameFocused)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit {
                        save()
                    }
                if !nameText.isEmpty {
                    Button {
                        nameText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                save()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    .appChromeCornerRadius(12)
            }
            .disabled(nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .onAppear {
            nameText = currentName
            isNameFocused = true
        }
    }

    private func save() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

/// Full-screen photo with horizontal scrolling for landscape images.
/// Portrait images display the same as before (fill + clip).
/// Landscape images are fit to screen height and can be panned left/right.
private struct HorizontalScrollablePhotoView: View {
    let photo: RecapPhoto
    /// When false, wide shots are shown center-cropped without the UIKit pan overlay so a parent `TabView` can page.
    /// Single-photo viewers and zoom overlay still allow full pan via zoom mode.
    var allowsIntrinsicHorizontalPan: Bool = true
    @State private var loadedImage: UIImage?
    @State private var panOffsetX: CGFloat = 0
    @State private var liveDragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height
            let displayW: CGFloat = {
                guard let img = loadedImage, img.size.height > 0 else { return screenW }
                let ar = img.size.width / img.size.height
                guard ar > 1.0 else { return screenW }
                return max(screenW, screenH * ar)
            }()

            let canPan = displayW > screenW + 0.5
            let maxPan = max(0, (displayW - screenW) / 2)
            let effectivePan = canPan ? max(-maxPan, min(maxPan, panOffsetX + liveDragX)) : 0

            ZStack {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: displayW, height: screenH)
                        .clipped()
                        .offset(x: effectivePan)
                } else {
                    RecapPhotoThumbnail(
                        photo: photo,
                        cornerRadius: 0,
                        showIcon: false,
                        targetSize: CGSize(width: 1200, height: 1200)
                    )
                    .frame(width: screenW, height: screenH)
                    .clipped()
                }
            }
            .frame(width: screenW, height: screenH)
            .clipped()
            .overlay(
                canPan && allowsIntrinsicHorizontalPan
                ? HorizontalPanOverlay(
                    onChanged: { liveDragX = $0 },
                    onEnded: { tx in
                        panOffsetX = max(-maxPan, min(maxPan, panOffsetX + tx))
                        liveDragX = 0
                    },
                    onCancelled: { liveDragX = 0 }
                )
                : nil
            )
        }
        .onAppear { panOffsetX = 0 }
        .task(id: photo.localIdentifier ?? "") {
            guard let id = photo.localIdentifier, !id.isEmpty else { return }
            loadedImage = await ImageLoader.shared.loadThumbnail(
                assetIdentifier: id,
                targetSize: CGSize(width: 1200, height: 1200)
            )
        }
    }
}

/// Transparent overlay that installs a UIKit pan recognizer which hard-fails when the
/// initial movement is predominantly vertical. This prevents any horizontal offset from
/// being applied while a sheet-dismiss or vertical scroll gesture is in progress.
private struct HorizontalPanOverlay: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let gr = HorizontalOnlyPanRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        gr.maximumNumberOfTouches = 1
        view.addGestureRecognizer(gr)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
    }

    final class Coordinator {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat) -> Void)?
        var onCancelled: (() -> Void)?

        @objc func handle(_ gr: UIPanGestureRecognizer) {
            let tx = gr.translation(in: gr.view).x
            switch gr.state {
            case .changed:
                onChanged?(tx)
            case .ended:
                onEnded?(tx)
            case .cancelled, .failed:
                onCancelled?()
            default:
                break
            }
        }
    }
}

/// A pan recognizer that fails itself as soon as it detects the gesture is moving
/// more vertically than horizontally, giving vertical gestures (sheet dismiss, scroll)
/// a clean win with no horizontal interference.
private final class HorizontalOnlyPanRecognizer: UIPanGestureRecognizer {
    private var axisLocked = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        axisLocked = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard !axisLocked else { return }
        let t = translation(in: view)
        let dx = abs(t.x), dy = abs(t.y)
        guard dx > 5 || dy > 5 else { return }   // wait for enough travel
        axisLocked = true
        if dy > dx {
            state = .failed   // vertical — give up immediately
        }
    }
}
