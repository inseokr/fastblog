//
//  PlacePhotoModalView.swift
//  fastblog
//

import SwiftUI
import CoreLocation
import Photos
import UIKit

/// Identifiable item for presenting the place photo modal (day + stop + initial photo).
struct PlacePhotoModalItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    let initialPhotoId: UUID
    var autoFocusCaption: Bool = false
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
    @Binding var placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    let initialPhotoId: UUID
    /// EXIF digitized timestamp of the stop's earliest photo ("yyyy:MM:dd HH:mm:ss" local time).
    /// Used to derive the capture location's timezone for correct photo time display.
    let stopDigitizedTime: String?
    var blogIsEditMode: Bool = false
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
    /// Called when the user chooses "Remove photo" from the kebab menu.
    var onRemovePhoto: ((UUID) -> Void)?
    /// Called when the user saves a place name edit from within this modal.
    /// Provides (newName, category, coordinate) so the caller can update the store and regenerate captions.
    var onSavePlaceName: ((String, String?, CLLocationCoordinate2D?) -> Void)?
    /// Called when the user commits the caption (Done/Save). Use to sync story to cloud.
    var onCaptionCommitted: ((UUID) -> Void)? = nil

    @State private var currentPhotoId: UUID
    @State private var isGeneratingCaption = false
    @State private var isTranslatingCaption = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    // Vibe
    @StateObject private var vibePlayer = VibePlayer()
    @State private var isVibeEnabled: Bool = false
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
    /// Read-only bottom overlay: multi-line captions start collapsed; user can expand.
    @State private var isReadOnlyCaptionExpanded = false
    /// Vertical drag for swipe-down dismiss (blog overlay & sheets without a drag indicator).
    @State private var interactiveDismissDragOffset: CGFloat = 0
    @State private var isDismissExitAnimating = false
    /// While non-nil, TabView paging is locked to this id so dismiss drags can’t swap photos or reload neighbors.
    @State private var dismissFrozenPhotoId: UUID?
    /// PHAsset time metadata for the current photo (creationDate, modificationDate). Loaded when photo has localIdentifier.
    @State private var currentPhotoAssetMetadata: (creation: Date?, modification: Date?)?
    /// Derives the UTC offset from the EXIF digitized local time vs photo timestamps.
    /// Digitized is the stop's earliest photo time in *local* time at capture; we compare to each photo's UTC timestamp to infer offset.
    /// Returns nil when: no digitized time, single photo (can't validate), parse failure, or median offset is 0 (digitized may be stored in UTC — prefer location-based TZ).
    private var captureTimeZone: TimeZone? {
        guard let digitized = stopDigitizedTime else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let localAsUTC = parser.date(from: digitized) else { return nil }
        // Per photo: offset = (parsed "local" as if UTC) - (photo UTC). When digitized is true local time, this gives capture TZ offset.
        let offsets: [Int] = photos.map { Int(localAsUTC.timeIntervalSince($0.timestamp)) }
        let sorted = offsets.sorted()
        let medianOffset: Int
        if sorted.count.isMultiple(of: 2), sorted.count >= 2 {
            medianOffset = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            medianOffset = sorted[sorted.count / 2]
        }
        let roundedOffset = (medianOffset / 900) * 900
        // Offset 0 is ambiguous: digitized might be stored in UTC (no EXIF TZ), which would show wrong local time (e.g. morning instead of evening).
        if roundedOffset == 0 { return nil }
        guard let tz = TimeZone(secondsFromGMT: roundedOffset) else { return nil }
        return tz
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
        photos: [RecapPhoto],
        initialPhotoId: UUID,
        stopDigitizedTime: String? = nil,
        blogIsEditMode: Bool = false,
        showAssetTimeMetadata: Bool = true,
        autoFocusCaption: Bool = false,
        presentation: PlaceDetailPresentation = .sheet,
        photoCaption: @escaping (UUID) -> Binding<String>,
        onDismiss: @escaping () -> Void,
        onDismissSlideBegan: (() -> Void)? = nil,
        onViewBlog: (() -> Void)? = nil,
        onGenerateCaption: ((RecapPhoto, String, String?, String) async -> String)? = nil,
        onTranslateCaption: ((String) async -> String)? = nil,
        onAICaptionApplied: ((UUID) -> Void)? = nil,
        onPhotoCaptionManuallyEdited: ((UUID) -> Void)? = nil,
        onRemovePhoto: ((UUID) -> Void)? = nil,
        onSavePlaceName: ((String, String?, CLLocationCoordinate2D?) -> Void)? = nil,
        onCaptionCommitted: ((UUID) -> Void)? = nil
    ) {
        self._placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.stopDigitizedTime = stopDigitizedTime
        self.blogIsEditMode = blogIsEditMode
        self.showAssetTimeMetadata = showAssetTimeMetadata
        self.autoFocusCaption = autoFocusCaption
        self.presentation = presentation
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
        self.onCaptionCommitted = onCaptionCommitted
        _currentPhotoId = State(initialValue: initialPhotoId)
        // Blog edit: show caption editor from the first frame (no onAppear flip).
        _isEditing = State(initialValue: blogIsEditMode)
    }

    private var currentPhoto: RecapPhoto? {
        photos.first { $0.id == effectiveDisplayedPhotoId } ?? photos.first
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

    /// Local vibe file URL for the current photo, if it was captured with the in-app camera and has a Vibe clip.
    private var currentVibeURL: URL? {
        guard let id = currentPhoto?.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.vibeFileURL(for: captureId)
    }

    private var currentCaption: String {
        photoCaption(currentPhotoId).wrappedValue
    }

    private func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Full-screen / blog overlay: inset bottom chrome from the home indicator and nudge it upward vs sheet layout.
    private func bottomPhotoChromeInset(safeBottom: CGFloat) -> CGFloat {
        if presentation.isSheet { return 0 }
        return max(safeBottom, 10) + 6
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
        if !isEditing && !blogIsEditMode {
            animateSwipeDismissCompletion { onDismiss() }
            return
        }
        if hasAnyChanges {
            showSaveConfirmationAlert = true
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
        let response: CGFloat = blogIsEditMode ? 0.32 : 0.4
        let damping: CGFloat = blogIsEditMode ? 0.9 : 0.93
        let settleNanoseconds: UInt64 = blogIsEditMode ? 380_000_000 : 480_000_000
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
            .onChanged { value in
                guard swipeToDismissEnabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard isPrimarilyVerticalDismissDrag(dx: dx, dy: dy) else { return }
                // Lock paging on first accepted vertical frame — avoids horizontal wobble before dy was > 40.
                if dismissFrozenPhotoId == nil {
                    dismissFrozenPhotoId = currentPhotoId
                }
                interactiveDismissDragOffset = dy
            }
            .onEnded { value in
                guard !isDismissExitAnimating else { return }
                guard swipeToDismissEnabled || interactiveDismissDragOffset > 0 else {
                    dismissFrozenPhotoId = nil
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86, blendDuration: 0)) {
                        interactiveDismissDragOffset = 0
                    }
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let mostlyVertical = isPrimarilyVerticalDismissDrag(dx: dx, dy: dy)
                let predicted = value.predictedEndTranslation.height
                let shouldDismiss = mostlyVertical && (dy > 115 || predicted > 220)
                if shouldDismiss {
                    let needsSaveAlert = (isEditing || blogIsEditMode) && hasAnyChanges
                    if needsSaveAlert {
                        dismissFrozenPhotoId = nil
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86, blendDuration: 0)) {
                            interactiveDismissDragOffset = 0
                        }
                        showSaveConfirmationAlert = true
                    } else {
                        handleUserRequestedDismiss()
                    }
                } else {
                    dismissFrozenPhotoId = nil
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86, blendDuration: 0)) {
                        interactiveDismissDragOffset = 0
                    }
                }
            }
    }

    var body: some View {
        GeometryReader { geo in
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
                        // Stop any playing Vibe and auto-play the new photo's Vibe if enabled.
                        vibePlayer.stop()
                        if isVibeEnabled, let url = currentVibeURL {
                            vibePlayer.play(url: url)
                        }
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
                                    assetTimeMetadataLines: assetTimeMetadataLinesForCurrentPhoto,
                                    showAssetTimeMetadata: showAssetTimeMetadata,
                                    isEditing: $isEditing,
                                    captionText: $editedCaptionText,
                                    isCaptionExpanded: $isReadOnlyCaptionExpanded,
                                    placeholder: "Leave a story for this photo...",
                                    blogIsEditMode: blogIsEditMode,
                                    contentVerticalPadding: PlaceDetailChromeLayout.bottomContentVerticalPadding(sheet: presentation.isSheet),
                                    contentHorizontalPadding: PlaceDetailChromeLayout.bottomContentHorizontalPadding(sheet: presentation.isSheet),
                                    onTitleTap: { openGoogleSearch() },
                                    onViewBlog: titleRowOnViewBlog,
                                    onCommitCaption: { commitCaption() }
                                )
                            }

                            if !blogIsEditMode && !isEditing {
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
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
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
                        )
                        .opacity(isZoomMode ? 0 : 1)
                        .animation(.easeInOut(duration: 0.25), value: isZoomMode)
                    }

            // 4. Shared top chrome (Close + actions): identical for every fullscreen source; sheet adds grabber.
            PlaceDetailTopChrome(
                safeAreaTop: deviceSafeAreaInsets.top,
                presentation: presentation,
                isEditing: isEditing,
                blogIsEditMode: blogIsEditMode,
                hasUnsavedChanges: hasUnsavedChanges,
                currentPhotoId: effectiveDisplayedPhotoId,
                hasVibeClip: currentVibeURL != nil,
                isVibeEnabled: isVibeEnabled,
                isVibePlaying: isVibeEnabled && vibePlayer.isPlaying,
                onLeadingPrimary: { handleUserRequestedDismiss() },
                onSaveCaptionAndDismiss: {
                    commitCaption()
                    onDismiss()
                },
                onDoneBlogEdit: {
                    if hasUnsavedChanges {
                        commitCaption()
                    }
                    onDismiss()
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
                        vibePlayer.play(url: url)
                    } else {
                        vibePlayer.stop()
                    }
                },
                onNavigate: { openNavigation() },
                onLink: { openGoogleSearch() }
            )
            .ignoresSafeArea(.all, edges: presentation.isSheet ? [] : .top)
            .allowsHitTesting(!isZoomMode)
            .opacity(isZoomMode ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: isZoomMode)

            // 5. Zoom mode overlay — appears when user taps the photo
            if isZoomMode, let photo = currentPhoto {
                zoomablePhotoOverlay(photo: photo)
            }

        }
        .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .statusBar(hidden: false)
        .onDisappear {
            vibePlayer.stop()
        }
        .sheet(isPresented: $showRenameSheet) {
            EditPlaceStopNameSheet(
                placeTitle: $placeTitle,
                location: photos.compactMap({ $0.location?.clCoordinate }).first,
                photos: photos,
                onSave: { newName, coord, category in
                    debugPrint("[Category] PlacePhotoModal onSave: name='\(newName)' category=\(category ?? "nil") onSavePlaceName wired=\(onSavePlaceName != nil)")
                    placeTitle = newName
                    onSavePlaceName?(newName, category, coord)
                }
            )
            // Root photo modal disables UIKit sheet dismiss; nested sheets must stay interactively dismissible.
            .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showWritingStyleSheet) {
            StoryWritingStyleSheet()
                .interactiveDismissDisabled(false)
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
            if isEditing {
                if blogIsEditMode {
                    // ── Blog edit mode: caption TextField anchored above keyboard ──
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editedPlaceTitle)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            if !dateTimeTextForCurrentPhoto.isEmpty {
                                Text(dateTimeTextForCurrentPhoto)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.bottom, 4)

                        TextField("Leave a story for this photo...", text: $editedCaptionText, axis: .vertical)
                            .focused($isCaptionFocused)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(2...6)
                            .padding(12)

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
                                        Label("", systemImage: "arrow.uturn.backward")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack(alignment: .bottom) {
                            // Material connects seamlessly with the keyboard (no gap at rounded corners)
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(.keyboard, edges: .bottom)
                            // Extra darkening for legibility over bright photos
                            Color.black.opacity(0.45)
                                .ignoresSafeArea(.keyboard, edges: .bottom)
                            // Gradient that fades up into the photo
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.2), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        }
                    }
                } else {
                    // ── Read mode editing panel ──
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editedPlaceTitle)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            if !dateTimeTextForCurrentPhoto.isEmpty {
                                Text(dateTimeTextForCurrentPhoto)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.bottom, 4)

                        TextField("Leave a story for this photo...", text: $editedCaptionText, axis: .vertical)
                            .focused($isCaptionFocused)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(2...6)
                            .padding(12)

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
                                        Label("", systemImage: "arrow.uturn.backward")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack(alignment: .bottom) {
                            // Material connects seamlessly with the keyboard (no gap at rounded corners)
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(.keyboard, edges: .bottom)
                            // Extra darkening for legibility over bright photos
                            Color.black.opacity(0.45)
                                .ignoresSafeArea(.keyboard, edges: .bottom)
                            // Gradient that fades up into the photo
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.2), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        }
                    }
                }
            }
        }
        .offset(y: interactiveDismissDragOffset)
        .opacity(dismissDragOverlayOpacity)
        .simultaneousGesture(photoModalSwipeDismissGesture)
        // Avoid UIKit sheet dismiss + this view’s vertical offset both driving the same drag (jitter, uneven speed).
        .interactiveDismissDisabled(true)
        .alert("Save changes?", isPresented: $showSaveConfirmationAlert) {
            Button("Save") {
                commitCaption()
                onDismiss()
            }
            Button("Discard", role: .destructive) {
                revertChanges()
                onDismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You have unsaved changes to your photo caption. Would you like to save them before leaving?")
        }
        .onAppear {
            dismissFrozenPhotoId = nil
            isDismissExitAnimating = false
            editedCaptionText = currentCaption
            editedPlaceTitle = placeTitle
            if blogIsEditMode {
                captionWhenEditingStarted = currentCaption
                titleWhenEditingStarted = placeTitle
                // `isEditing` is already true from init when `blogIsEditMode` (caption UI is on screen from frame 0).
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
        .onChange(of: editedCaptionText) { _, newValue in
            guard isEditing else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                photoCaption(currentPhotoId).wrappedValue = newValue
                if !isGeneratingCaption {
                    onPhotoCaptionManuallyEdited?(currentPhotoId)
                }
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

        return HorizontalScrollablePhotoView(photo: photo)
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
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }

    private var dateTimeTextForCurrentPhoto: String {
        guard let photo = currentPhoto else { return "" }
        let tz = effectiveTimeZone
        let tzAbbr = Self.timeZoneDisplayLabel(for: tz)
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
        let tzAbbr = Self.timeZoneDisplayLabel(for: tz)
        var lines: [String] = []
        if let creation = meta.creation {
            lines.append("Created: \(dateFmt.string(from: creation))")
        }
        if let modification = meta.modification, meta.creation != modification {
            lines.append("Modified: \(dateFmt.string(from: modification))")
        }
        return lines
    }

    private func openNavigation() {
        guard let location = currentPhoto?.location else { return }
        let lat = location.latitude
        let lon = location.longitude
        // Open Apple Maps navigation to this coordinate
        let urlString = "http://maps.apple.com/?daddr=\(lat),\(lon)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openGoogleSearch() {
        // Query: "Place Name, City Name"
        let query = [placeTitle, placeSubtitle].compactMap { $0 }.joined(separator: ", ")
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        
        if let url = components?.url {
            UIApplication.shared.open(url)
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
        guard let generate = onGenerateCaption, let photo = currentPhoto else { return }
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
            let text = await generate(photo, editedPlaceTitle, placeSubtitle, userText)
            await MainActor.run {
                editedCaptionText = text
                photoCaption(photoId).wrappedValue = text
                isGeneratingCaption = false
                onAICaptionApplied?(photoId)
            }
        }
    }

    private func runTranslateForCurrentPhoto(_ translate: @escaping (String) async -> String) {
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

// MARK: - Shared fullscreen / sheet top chrome

/// Single implementation of the place detail header: safe-area-aware insets, grabber (sheet only), Close / Cancel / Done, and the vertical action stack.
private struct PlaceDetailTopChrome: View {
    let safeAreaTop: CGFloat
    let presentation: PlaceDetailPresentation
    let isEditing: Bool
    let blogIsEditMode: Bool
    let hasUnsavedChanges: Bool
    let currentPhotoId: UUID
    let hasVibeClip: Bool
    let isVibeEnabled: Bool
    let isVibePlaying: Bool
    let onLeadingPrimary: () -> Void
    let onSaveCaptionAndDismiss: () -> Void
    let onDoneBlogEdit: () -> Void
    let onMenuEditPlaceName: () -> Void
    let onMenuBeginCaptionEdit: () -> Void
    let onMenuRemovePhoto: (UUID) -> Void
    let onToggleVibe: () -> Void
    let onNavigate: () -> Void
    let onLink: () -> Void

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
                HStack(alignment: .top) {
                    if isEditing && !blogIsEditMode {
                        capsuleButton(title: "Cancel", action: onLeadingPrimary)
                    } else if blogIsEditMode {
                        capsuleButton(title: "Cancel", action: onLeadingPrimary)
                    } else {
                        Button(action: onLeadingPrimary) {
                            Text("Close")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Capsule().fill(Color.white.opacity(0.12))
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if !isEditing && !blogIsEditMode {
                        VStack(spacing: PlaceDetailChromeLayout.actionStackSpacing) {
                            Menu {
                                Button(action: onMenuEditPlaceName) {
                                    Label("Edit Place Name", systemImage: "mappin.and.ellipse")
                                }
                                Button(action: onMenuBeginCaptionEdit) {
                                    Label("Edit caption", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    onMenuRemovePhoto(currentPhotoId)
                                } label: {
                                    Label("Remove photo", systemImage: "trash")
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
                            }

                            RightActionStack(
                                onSparkles: { },
                                onNavigate: onNavigate,
                                onLink: onLink
                            )
                        }
                    } else if isEditing && !blogIsEditMode {
                        Button(action: onSaveCaptionAndDismiss) {
                            Text("Save")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    } else if blogIsEditMode {
                        Button(action: onDoneBlogEdit) {
                            Text("Done")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
                .padding(.horizontal, PlaceDetailChromeLayout.horizontalPadding)
                .padding(.top, presentation.isSheet ? PlaceDetailChromeLayout.sheetInnerTopPadding : (presentation.fullscreenSource == .placesVisited ? 0 : PlaceDetailChromeLayout.fullscreenInnerTopPadding))
            }
            .padding(.top, presentation.isSheet ? 0 : safeAreaTop + (presentation.fullscreenSource == .placesVisited ? 0 : PlaceDetailChromeLayout.fullscreenPaddingBelowSafeAreaTop))
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func capsuleButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
        }
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

            Button(action: onLink) {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: PlaceDetailChromeLayout.circleActionSize, height: PlaceDetailChromeLayout.circleActionSize)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.25), radius: 2)
    }
}

// MARK: - Bottom overlay content block

struct BottomInfoOverlay: View {
    let placeTitle: String
    let dateTimeText: String
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
    var onCommitCaption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Tappable place title — opens Google search
                Button(action: { onTitleTap?() }) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(placeTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .lineLimit(1)
                        if onTitleTap != nil {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(onTitleTap == nil)

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

            if !dateTimeText.isEmpty {
                Text(dateTimeText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 1)
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
                TextField(placeholder, text: $captionText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(.white)
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
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
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
                                .cornerRadius(3)
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
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
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
                    .cornerRadius(12)
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
                canPan
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
