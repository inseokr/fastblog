//
//  PlacePhotoModalView.swift
//  fastblog
//

import SwiftUI
import CoreLocation
import Photos

/// Identifiable item for presenting the place photo modal (day + stop + initial photo).
struct PlacePhotoModalItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    let initialPhotoId: UUID
    var autoFocusCaption: Bool = false
    var id: String { "\(dayId.uuidString)-\(stopId.uuidString)-\(initialPhotoId.uuidString)" }
}

/// Presents when user taps a photo in a Place. Full-screen photo viewer with overlays.
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
    var photoCaption: (UUID) -> Binding<String>
    var onDismiss: () -> Void
    var onViewBlog: (() -> Void)?
    /// When provided, a magic wand button is shown in the caption editing panel (only when user has written text).
    /// Called with (photo, placeName, placeSubtitle, userText); returns enriched caption.
    var onGenerateCaption: ((RecapPhoto, String, String?, String) async -> String)?
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
        resolvedTimeZoneByPhotoId[currentPhotoId] ?? captureTimeZone ?? .current
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
        photoCaption: @escaping (UUID) -> Binding<String>,
        onDismiss: @escaping () -> Void,
        onViewBlog: (() -> Void)? = nil,
        onGenerateCaption: ((RecapPhoto, String, String?, String) async -> String)? = nil,
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
        self.photoCaption = photoCaption
        self.onDismiss = onDismiss
        self.onViewBlog = onViewBlog
        self.onGenerateCaption = onGenerateCaption
        self.onAICaptionApplied = onAICaptionApplied
        self.onPhotoCaptionManuallyEdited = onPhotoCaptionManuallyEdited
        self.onRemovePhoto = onRemovePhoto
        self.onSavePlaceName = onSavePlaceName
        self.onCaptionCommitted = onCaptionCommitted
        _currentPhotoId = State(initialValue: initialPhotoId)
    }

    private var currentPhoto: RecapPhoto? {
        photos.first { $0.id == currentPhotoId } ?? photos.first
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

    private var hasAnyChanges: Bool {
        trim(editedCaptionText) != trim(captionWhenEditingStarted) ||
        trim(editedPlaceTitle) != trim(titleWhenEditingStarted)
    }

    var body: some View {
        ZStack {
                // 1. Full screen media viewer — horizontal ScrollView with paging (not TabView) so the
                // sheet’s drag-to-dismiss doesn’t steal horizontal swipes. Tap/double-tap to zoom (same flow as non-modal).
                fullScreenPhotoView
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            if isCaptionFocused {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } else if !isZoomMode {
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

                // 2. Bottom overlay
            VStack {
                Color.clear
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
                // In edit mode (both blog edit and read mode editing),
                // the place title, timestamp and caption input are rendered in the safeAreaInset anchored above the keyboard.
                if !isEditing {
                    BottomInfoOverlay(
                        placeTitle: placeTitle,
                        dateTimeText: dateTimeTextForCurrentPhoto,
                        assetTimeMetadataLines: assetTimeMetadataLinesForCurrentPhoto,
                        showAssetTimeMetadata: showAssetTimeMetadata,
                        isEditing: $isEditing,
                        captionText: $editedCaptionText,
                        placeholder: "Leave a story for this photo...",
                        blogIsEditMode: blogIsEditMode,
                        onViewBlog: onViewBlog,
                        onTitleTap: { openGoogleSearch() },
                        onCommitCaption: { commitCaption() }
                    )
                }
                if !blogIsEditMode && !isEditing {
                    // print photos
                    if photos.count > 1 {
                        PlacePhotoThumbnailStrip(
                            photos: photos,
                            currentPhotoId: currentPhotoId,
                            onSelectPhoto: { currentPhotoId = $0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    } else if let single = photos.first {
                        RecapPhotoThumbnail(photo: single, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                            .frame(width: 56, height: 56)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .padding(.bottom, 24)
                    }
                }
            }
            .background(
                (isEditing || isZoomMode) ? nil :
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .opacity(isZoomMode ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: isZoomMode)

            // 4. Top bar + bottom-right action stack (drawn on top so never covered when modal is small).
            // Pass-through layer so taps in the center reach the photo view; only the bar content gets hits.
            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                // Drag Handle
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        if isEditing && !blogIsEditMode {
                            // Cancel button in top left when editing in read mode
                            Button(action: {
                                if hasAnyChanges {
                                    showSaveConfirmationAlert = true
                                } else {
                                    revertChanges()
                                    onDismiss()
                                }
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                        } else if blogIsEditMode {
                            // Cancel button in top left when in blog edit mode
                            Button(action: {
                                if hasAnyChanges {
                                    showSaveConfirmationAlert = true
                                } else {
                                    revertChanges()
                                    onDismiss()
                                }
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                        } else {
                            // Close button in top left when not editing
                            Button(action: onDismiss) {
                                Text("Close")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer()
                        
                        if !isEditing && !blogIsEditMode {
                            // Kebab menu + action buttons stacked vertically in top right
                            VStack(spacing: 16) {
                                // Vibe button — only shown when the current photo has a Vibe clip
                                if currentVibeURL != nil {
                                    let isPlaying = isVibeEnabled && vibePlayer.isPlaying
                                    Button {
                                        isVibeEnabled.toggle()
                                        if isVibeEnabled, let url = currentVibeURL {
                                            vibePlayer.play(url: url)
                                        } else {
                                            vibePlayer.stop()
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    isPlaying
                                                        ? LinearGradient(
                                                            colors: [.cyan, .green],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                        : LinearGradient(
                                                            colors: [Color.white.opacity(0.08)],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                )
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(isPlaying ? .white : Color.white.opacity(0.35))
                                        }
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isPlaying
                                                        ? LinearGradient(
                                                            colors: [.cyan, .green],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                        : LinearGradient(
                                                            colors: [Color.white.opacity(0.15)],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        ),
                                                    lineWidth: isPlaying ? 2 : 1
                                                )
                                        )
                                        .shadow(color: isPlaying ? .cyan.opacity(0.55) : .clear, radius: isPlaying ? 10 : 0)
                                    }
                                    .accessibilityLabel(isPlaying ? "Vibe playing" : (isVibeEnabled ? "Vibe enabled" : "Vibe disabled"))
                                    .overlay(alignment: .bottomTrailing) {
                                        if isPlaying {
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 7, height: 7)
                                                .overlay(Circle().stroke(Color.cyan.opacity(0.9), lineWidth: 1))
                                                .offset(x: -2, y: -2)
                                        }
                                    }
                                }

                                Menu {
                                    Button {
                                        showRenameSheet = true
                                    } label: {
                                        Label("Edit Place Name", systemImage: "mappin.and.ellipse")
                                    }

                                    Button {
                                        captionWhenEditingStarted = currentCaption
                                        titleWhenEditingStarted = placeTitle
                                        editedCaptionText = currentCaption
                                        editedPlaceTitle = placeTitle
                                        isEditing = true
                                        isCaptionFocused = true
                                    } label: {
                                        Label("Edit caption", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        onRemovePhoto?(currentPhotoId)
                                    } label: {
                                        Label("Remove photo", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.black.opacity(0.35))
                                        .clipShape(Circle())
                                }

                                RightActionStack(
                                    onSparkles: { /* AI assist */ },
                                    onNavigate: { openNavigation() },
                                    onLink: { openGoogleSearch() }
                                )
                            }
                        } else if isEditing && !blogIsEditMode {
                            // Save button in top right when editing in read mode
                            Button(action: {
                                commitCaption()
                                onDismiss()
                            }) {
                                Text("Save")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        } else if blogIsEditMode {
                            // Save button in top right when in blog edit mode
                            Button(action: {
                                commitCaption()
                                onDismiss()
                            }) {
                                Text("Done")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .allowsHitTesting(!isZoomMode)
            .opacity(isZoomMode ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: isZoomMode)

            // 5. Zoom mode overlay — appears when user taps the photo
            if isZoomMode, let photo = currentPhoto {
                zoomablePhotoOverlay(photo: photo)
            }

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
                    placeTitle = newName
                    onSavePlaceName?(newName, category, coord)
                }
            )
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
                                        Label("Revert", systemImage: "arrow.uturn.backward")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }

                                if let generate = onGenerateCaption, let photo = currentPhoto {
                                    Button {
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
                                    } label: {
                                        if isGeneratingCaption {
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.75)
                                                Text("Enhancing…")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.75))
                                            }
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "wand.and.stars")
                                                    .font(.subheadline)
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                Text("Enhance")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .disabled(isGeneratingCaption)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
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
                                        Label("Revert", systemImage: "arrow.uturn.backward")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }

                                if let generate = onGenerateCaption, let photo = currentPhoto {
                                    Button {
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
                                    } label: {
                                        if isGeneratingCaption {
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.75)
                                                Text("Enhancing…")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.75))
                                            }
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "wand.and.stars")
                                                    .font(.subheadline)
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                Text("Enhance")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .disabled(isGeneratingCaption)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.8), Color.black.opacity(0.4), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
        }
        .interactiveDismissDisabled(isEditing && hasAnyChanges)
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
            editedCaptionText = currentCaption
            editedPlaceTitle = placeTitle
            if blogIsEditMode {
                captionWhenEditingStarted = currentCaption
                titleWhenEditingStarted = placeTitle
                isEditing = true
                if autoFocusCaption {
                    isCaptionFocused = true
                }
            }
        }
        .onChange(of: currentPhotoId) { _, _ in
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
        TabView(selection: $currentPhotoId) {
            ForEach(photos) { photo in
                photoFullScreenImage(photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    /// Single tap or double tap enters zoom overlay (tap-to-zoom works the same in the modal as in the non-modal viewer).
    private func photoFullScreenImage(_ photo: RecapPhoto) -> some View {
        HorizontalScrollablePhotoView(photo: photo)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { enterZoomMode() }
            .simultaneousGesture(
                TapGesture(count: 1).onEnded {
                    guard !isZoomMode else { return }
                    if isCaptionFocused {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } else {
                        enterZoomMode()
                    }
                }
            )
    }

    private func enterZoomMode() {
        accumulatedZoomScale = 1.0
        accumulatedDragOffset = .zero
        withAnimation(.easeInOut(duration: 0.25)) { isZoomMode = true }
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        accumulatedZoomScale = 1.0
                                        accumulatedDragOffset = .zero
                                        isZoomMode = false
                                    }
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
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            accumulatedZoomScale = 1.0
                            accumulatedDragOffset = .zero
                            isZoomMode = false
                        }
                    }
                )

            // Close button — always visible so user can exit zoom mode easily
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isZoomMode = false
                    accumulatedZoomScale = 1.0
                    accumulatedDragOffset = .zero
                }
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
            return "\(dateFmt.string(from: creation)) (\(tzAbbr))"
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
                        return "\(dateDisplay.string(from: date)) at \(timeStr) (\(tzAbbr))"
                    }
                }
            }
        }

        // Fallback: use RecapPhoto.timestamp (e.g. from trip scan).
        return "\(dateFmt.string(from: photo.timestamp)) (\(tzAbbr))"
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
            lines.append("Created: \(dateFmt.string(from: creation)) (\(tzAbbr))")
        }
        if let modification = meta.modification, meta.creation != modification {
            lines.append("Modified: \(dateFmt.string(from: modification)) (\(tzAbbr))")
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

    private let spacing: CGFloat = 20

    var body: some View {
        VStack(spacing: spacing) {
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
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
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
    let placeholder: String
    var blogIsEditMode: Bool = false
    var onViewBlog: (() -> Void)?
    var onTitleTap: (() -> Void)? = nil
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
                        if onTitleTap != nil {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onTitleTap == nil)

                Spacer()

                if let onViewBlog {
                    Button(action: onViewBlog) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
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
                    Text(captionText)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height
            let displayW: CGFloat = {
                guard let img = loadedImage, img.size.height > 0 else { return screenW }
                let ar = img.size.width / img.size.height
                guard ar > 1.0 else { return screenW }  // portrait: fill screen as before
                return max(screenW, screenH * ar)        // landscape: natural width at screen height
            }()

            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if let img = loadedImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: displayW, height: screenH)
                            .clipped()
                    } else {
                        RecapPhotoThumbnail(
                            photo: photo, cornerRadius: 0, showIcon: false,
                            targetSize: CGSize(width: 1200, height: 1200)
                        )
                        .frame(width: screenW, height: screenH)
                        .clipped()
                    }
                }
                .frame(width: displayW, height: screenH)
            }
            .frame(width: screenW, height: screenH)
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: photo.localIdentifier ?? "") {
            guard let id = photo.localIdentifier, !id.isEmpty else { return }
            loadedImage = await ImageLoader.shared.loadThumbnail(
                assetIdentifier: id,
                targetSize: CGSize(width: 1200, height: 1200)
            )
        }
    }
}
