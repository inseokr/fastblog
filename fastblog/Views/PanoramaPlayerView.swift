import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Gallery chrome ignores the safe area; match status-bar inset for close / full-screen photo bars.
private enum SlideshowGalleryLayout {
    static func chromeTopPadding() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return 47 + 2
        }
        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
        let top = window?.safeAreaInsets.top ?? 0
        let resolvedTop = top > 0 ? top : 47
        return resolvedTop + 2
    }
}

// MARK: - Photo entry (asset ID + optional caption)

struct PanoramaPhotoEntry: Equatable {
    let id: String
    let caption: String?
    let placeName: String?
    let timestamp: Date?
    /// GPS from the recap photo, when available — used for "open in Maps" in slideshow / gallery detail.
    let location: PhotoCoordinate?
    /// Local file URL for a moment-video reel attached to this photo (in-app camera captures only).
    let momentVideoURL: URL?
    /// Zero-based index of the blog day this photo belongs to; used for day-scope filtering.
    let dayIndex: Int

    init(
        id: String,
        caption: String?,
        placeName: String?,
        timestamp: Date?,
        location: PhotoCoordinate?,
        momentVideoURL: URL? = nil,
        dayIndex: Int = 0
    ) {
        self.id = id
        self.caption = caption
        self.placeName = placeName
        self.timestamp = timestamp
        self.location = location
        self.momentVideoURL = momentVideoURL
        self.dayIndex = dayIndex
    }
}

// MARK: - Layout variant (solo or top/bottom diptych only)

private enum SlideLayout: Equatable {
    case solo
    case diptych
}

/// Top vs bottom pane in diptych layout (for paused full-screen inspect).
private enum DiptychHalf {
    case top
    case bottom
}

/// What the slideshow renders for each slide.
enum SlideshowContentMode: Equatable {
    /// Show still photos with Ken Burns zoom (original behavior).
    case photos
    /// Show moment-video reels; only entries that have a reel are included.
    case reels
}

/// Which days to include in the active slide pool.
private enum SlideshowDayScope: Equatable {
    case allDays
    case day(Int)
}

/// Full-screen slideshow that advances through photos grouped by place.
///
/// - `photoGroups`: each sub-array is one place's included photos.
///   Diptych always picks two photos from the **same** group.
/// - `.solo`: single full-bleed photo with a slow left→right pan.
/// - `.diptych`: two photos from the same place, split top/bottom.
///   Top photo exits upward / enters from below; bottom is the opposite.
struct PanoramaPlayerView: View {
    /// Photos grouped by place (PlaceStop). Each inner array = one place.
    let photoGroups: [[PanoramaPhotoEntry]]
    /// Used to persist the chosen slideshow track for this recap (`UserDefaults`, keyed by blog).
    let blogId: UUID
    /// Shown centered on the gallery hero (matches recap cover title treatment).
    let blogTitle: String
    /// Display labels for each day (e.g. "Day 1", "Day 2") — drives the day-scope picker.
    let dayLabels: [String]
    /// When true, present the gallery overlay immediately instead of starting on slideshow playback.
    var startInGallery: Bool = false
    var onDismiss: () -> Void
    /// When the user deletes an in-app capture (`bloggo-capture:` id) from the slideshow gallery full-screen viewer.
    var onAppCaptureDeletedFromSlideshow: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    init(
        photoGroups: [[PanoramaPhotoEntry]],
        blogId: UUID,
        blogTitle: String,
        dayLabels: [String] = [],
        startInGallery: Bool = false,
        onDismiss: @escaping () -> Void,
        onAppCaptureDeletedFromSlideshow: ((String) -> Void)? = nil
    ) {
        self.photoGroups = photoGroups
        self.blogId = blogId
        self.blogTitle = blogTitle
        self.dayLabels = dayLabels
        self.startInGallery = startInGallery
        self.onDismiss = onDismiss
        self.onAppCaptureDeletedFromSlideshow = onAppCaptureDeletedFromSlideshow
        _isPlaying = State(initialValue: !startInGallery)
        _showGallery = State(initialValue: startInGallery)
    }

    // MARK: - Image cache (keyed by asset identifier)
    @State private var loadedImages: [String: UIImage] = [:]

    // MARK: - Slide position
    /// Which place/group is currently showing.
    @State private var currentGroupIndex: Int = 0
    /// Offset within the current group (first photo of the current slide).
    @State private var currentSlideOffset: Int = 0
    @State private var currentLayout: SlideLayout = .solo

    // MARK: - Zoom state (solo only)
    /// Ken Burns scale, derived from `soloElapsed` while playing (linear); frozen while paused.
    @State private var currentScale: CGFloat = 1.0
    /// Alternates each slide: true = zoom in (1.0→1.12), false = zoom out (1.12→1.0).
    @State private var zoomIn: Bool = true
    /// Elapsed seconds within the current solo slide — drives the progress bar.
    @State private var soloElapsed: CGFloat = 0
    /// Pinch zoom while paused (solo only); reset when the slide changes or playback resumes.
    @State private var pinchBaseScale: CGFloat = 1.0
    @State private var pinchGestureScale: CGFloat = 1.0

    /// Diptych only: full-screen one photo while **paused** (pinch + tap to dismiss).
    @State private var diptychExpandedHalf: DiptychHalf?
    @State private var diptychExpandPinchBase: CGFloat = 1.0
    @State private var diptychExpandPinchGesture: CGFloat = 1.0

    // MARK: - Playback
    @State private var isPlaying: Bool = true
    @State private var timer: Timer?

    // MARK: - Gallery
    @State private var showGallery: Bool = false
    /// True only when dismissing gallery via Play; switches transition to fade instead of swipe-down.
    @State private var useFadeForGalleryTransition = false
    @State private var wasPlayingBeforeGallery: Bool = false
    /// Full-screen photo paging within the gallery overlay (grid tap); `nil` = grid / hero visible.
    @State private var galleryDetailPhotoId: String?
    /// Toast when saving the current slideshow photo from the paused overlay.
    @State private var pausedSlideshowDownloadToast: String?

    // MARK: - Music
    @State private var showMusicPicker: Bool = false
    /// Bundled track filename when slideshow has background music; `nil` = none selected.
    @State private var selectedSlideshowMusicFilename: String?
    @State private var slideshowMusic = SlideshowMusicPlaybackCoordinator()
    /// True when we paused slideshow music because the bundled-track sheet was open (resume on cancel only).
    @State private var pausedSlideshowMusicForPicker = false

    // MARK: - Mode / scope
    @State private var contentMode: SlideshowContentMode = .photos
    @State private var dayScope: SlideshowDayScope = .allDays
    @State private var showDayPicker = false
    @State private var showNoReelsAlert = false
    /// AVPlayer for reel-mode video slides (original clip audio; bundled music is ducked).
    @State private var videoPlayer: AVPlayer?
    /// Controls the auto-dismissing place/caption overlay shown at the start of each reel slide.
    @State private var showReelInfoOverlay = false

    // MARK: - Constants
    private let soloDurationSeconds: Double = 4.0
    private let diptychDurationSeconds: Double = 4.0
    private let timerInterval: Double = 1.0 / 60.0
    private let zoomScale: CGFloat = 1.12   // how far to zoom in/out
    private let pinchScaleMin: CGFloat = 0.5
    private let pinchScaleMax: CGFloat = 4.0
    /// Bundled slideshow music level while a reel clip with its own soundtrack is playing.
    private static let slideshowMusicDuckedVolume: Float = 0.2

    // MARK: - Derived

    /// Groups filtered by `dayScope` and `contentMode`; used for all slideshow navigation.
    private var activeGroups: [[PanoramaPhotoEntry]] {
        var groups = photoGroups
        if case .day(let idx) = dayScope {
            groups = groups.map { $0.filter { $0.dayIndex == idx } }.filter { !$0.isEmpty }
        }
        if contentMode == .reels {
            groups = groups.map { $0.filter { $0.momentVideoURL != nil } }.filter { !$0.isEmpty }
        }
        return groups
    }

    /// True when any entry in the full photo set has a moment-video reel attached.
    private var hasAnyReels: Bool {
        photoGroups.contains { $0.contains { $0.momentVideoURL != nil } }
    }

    /// True when the current day scope contains at least one reel (used before switching to reel mode).
    private var hasReelsInCurrentScope: Bool {
        var groups = photoGroups
        if case .day(let idx) = dayScope {
            groups = groups.map { $0.filter { $0.dayIndex == idx } }.filter { !$0.isEmpty }
        }
        return groups.contains { $0.contains { $0.momentVideoURL != nil } }
    }

    private var dayScopeLabel: String {
        switch dayScope {
        case .allDays: return "All Days"
        case .day(let idx): return dayLabels.indices.contains(idx) ? dayLabels[idx] : "Day \(idx + 1)"
        }
    }

    /// Stable key for `.task(id:)` — drives AVPlayer creation/teardown when the current reel slide changes.
    private var currentVideoKey: String {
        "\(currentGroupIndex)-\(currentSlideOffset)-\(contentMode == .reels)"
    }

    private var currentGroup: [PanoramaPhotoEntry] {
        guard currentGroupIndex < activeGroups.count else { return [] }
        return activeGroups[currentGroupIndex]
    }

    /// Asset ID of the top (or only) photo on the current slide.
    private var topPhotoId: String? {
        guard currentSlideOffset < currentGroup.count else { return nil }
        return currentGroup[currentSlideOffset].id
    }

    /// Asset ID of the bottom photo in diptych mode (same group, next slot).
    private var bottomPhotoId: String? {
        guard currentLayout == .diptych,
              currentSlideOffset + 1 < currentGroup.count
        else { return nil }
        return currentGroup[currentSlideOffset + 1].id
    }

    /// Primary visible photo for captions / timestamp / map (top slot, or solo).
    private var currentPrimaryEntry: PanoramaPhotoEntry? {
        guard currentGroupIndex < activeGroups.count else { return nil }
        let group = activeGroups[currentGroupIndex]
        guard currentSlideOffset < group.count else { return nil }
        return group[currentSlideOffset]
    }

    private var totalPhotos: Int { activeGroups.reduce(0) { $0 + $1.count } }

    private var currentFlatIndex: Int {
        activeGroups[0..<currentGroupIndex].reduce(0) { $0 + $1.count } + currentSlideOffset
    }

    private var soloProgress: CGFloat {
        guard currentLayout == .solo else { return 0 }
        return (soloElapsed / CGFloat(soloDurationSeconds)).clamped(to: 0...1)
    }

    private var overallProgress: CGFloat {
        guard totalPhotos > 0 else { return 0 }
        return (CGFloat(currentFlatIndex) + soloProgress) / CGFloat(totalPhotos)
    }

    private var slideshowMusicAccessibilityLabel: String {
        selectedSlideshowMusicFilename != nil
            ? "Slideshow music, change track"
            : "Slideshow music, none selected"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Full-bleed photo content
            GeometryReader { geo in
                ZStack {
                    slideContent(geo: geo)
                    if diptychExpandedHalf != nil {
                        diptychExpandedOverlay(size: geo.size)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: diptychExpandedHalf)
            }
            .ignoresSafeArea()

            // Gradient scrims
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 160)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Left/right tap zones for photo navigation. Pause/resume is only via the bottom control.
            if !activeGroups.isEmpty, diptychExpandedHalf == nil {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.35)
                            .onTapGesture { navigateToPreviousSlide() }
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.35)
                            .onTapGesture { navigateToNextSlide() }
                    }
                    .frame(maxHeight: .infinity)
                }
                .ignoresSafeArea()
            }

            // Reel info overlay — place name + caption, fades in on slide start then auto-dismisses.
            if contentMode == .reels, showReelInfoOverlay, let entry = currentPrimaryEntry {
                reelInfoPanel(entry: entry)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.4), value: showReelInfoOverlay)
            }

            // Chrome — extend to physical bottom; explicit padding replaces implicit safe-area inset
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 2)
                    .padding(.horizontal, 20)
                Spacer()
                VStack(spacing: 10) {
                    progressBar
                        .padding(.horizontal, 24)
                    if !isPlaying, !showGallery, diptychExpandedHalf == nil, let entry = currentPrimaryEntry {
                        pausedSlideshowMetadataRow(entry: entry)
                            .padding(.horizontal, 24)
                    }
                    bottomControls
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(nil, value: currentGroupIndex)
            .animation(nil, value: currentSlideOffset)
            .animation(nil, value: currentLayout)

            // Gallery panel — slides up from bottom
            if showGallery {
                galleryOverlay
                    .transition(
                        useFadeForGalleryTransition
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .zIndex(20)
            }

            if let pausedSlideshowDownloadToast {
                VStack {
                    Spacer()
                    Text(pausedSlideshowDownloadToast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(25)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: galleryDetailPhotoId)
        .sheet(isPresented: $showMusicPicker) {
            SlideshowBundledTrackPickerSheet(
                tracks: SlideshowBundledMusicLibrary.tracksInAppBundle(),
                selectedFilename: selectedSlideshowMusicFilename,
                onPickTrack: { track in
                    pausedSlideshowMusicForPicker = false
                    showMusicPicker = false
                    selectedSlideshowMusicFilename = track.filename
                    SlideshowMusicPreference.save(
                        blogId: blogId.uuidString,
                        filename: track.filename,
                        displayTitle: track.displayTitle
                    )
                    Task { @MainActor in
                        await slideshowMusic.play(url: track.fileURL, startPlayback: true)
                    }
                },
                onPickNone: {
                    pausedSlideshowMusicForPicker = false
                    showMusicPicker = false
                    selectedSlideshowMusicFilename = nil
                    SlideshowMusicPreference.saveNone(blogId: blogId.uuidString)
                    Task { @MainActor in
                        await slideshowMusic.stopAll()
                    }
                },
                onCancel: { showMusicPicker = false }
            )
        }
        .onChange(of: showMusicPicker) { wasShowing, isShowing in
            if isShowing, !wasShowing {
                if isPlaying, selectedSlideshowMusicFilename != nil {
                    pausedSlideshowMusicForPicker = true
                    Task { await slideshowMusic.pause() }
                } else {
                    pausedSlideshowMusicForPicker = false
                }
            }
            if wasShowing, !isShowing {
                resumeSlideshowTimingIfPlaying()
                if pausedSlideshowMusicForPicker {
                    pausedSlideshowMusicForPicker = false
                    Task { await slideshowMusic.resume() }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    guard !showGallery, diptychExpandedHalf == nil else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // Swipe up: open gallery (vertical dominates, finger moved up → negative dy)
                    if abs(dy) > abs(dx), dy < -56 {
                        presentSlideshowGallery()
                        return
                    }
                    // Horizontal: prev / next slide
                    guard abs(dx) > abs(dy) else { return }
                    if dx < 0 {
                        navigateToNextSlide()
                    } else {
                        navigateToPreviousSlide()
                    }
                }
        )
        .task {
            await preloadAround(groupIndex: 0, offset: 0)
            currentLayout = chooseLayout(groupIndex: 0, offset: 0)
            await restorePersistedSlideshowMusic()
        }
        .task(id: currentVideoKey) {
            // Hide the info overlay before the new slide begins.
            await MainActor.run { showReelInfoOverlay = false }

            guard contentMode == .reels, let url = currentPrimaryEntry?.momentVideoURL else {
                // No new video — fade out whatever is showing.
                await MainActor.run {
                    restoreSlideshowMusicVolumeForPhotos()
                    withAnimation(.easeOut(duration: 0.4)) { videoPlayer = nil }
                }
                return
            }

            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = false
            newPlayer.volume = 1
            let obs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in newPlayer.seek(to: .zero); newPlayer.play() }

            await MainActor.run {
                duckSlideshowMusicForReelPlayback()
                configureAudioSessionForReelSlideshow()
                // Crossfade: replacing videoPlayer with a new instance changes the view's
                // .id(ObjectIdentifier(player)), so SwiftUI dissolves the old view out while
                // scaling+fading the new one in — no black flash between slides.
                withAnimation(.easeInOut(duration: 0.55)) { videoPlayer = newPlayer }
                if isPlaying { newPlayer.play() }
                // Fade in the place/caption overlay.
                withAnimation(.easeIn(duration: 0.35).delay(0.2)) { showReelInfoOverlay = true }
                // Restart the advance timer for this reel slide. In reel mode soloZoomView
                // never appears so its onAppear-based startSoloTimer() never fires — the
                // timer must be (re)started here after every slide change.
                soloElapsed = 0
                if isPlaying { startSoloTimer() }
            }

            // Auto-dismiss the info overlay after 2.5 seconds.
            try? await Task.sleep(for: .milliseconds(2500))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.5)) { showReelInfoOverlay = false }
                }
            }

            // Keep player alive until the task is cancelled (slide or mode changed).
            do { try await Task.sleep(for: .seconds(3600)) } catch {}
            NotificationCenter.default.removeObserver(obs)
            newPlayer.pause()
        }
        .onChange(of: isPlaying) { _, playing in
            if playing { videoPlayer?.play() } else { videoPlayer?.pause() }
        }
        .onChange(of: contentMode) { _, mode in
            if mode == .photos {
                restoreSlideshowMusicVolumeForPhotos()
            }
            resetToFirstSlide()
        }
        .onChange(of: dayScope) { _, _ in resetToFirstSlide() }
        .alert("No Videos Available", isPresented: $showNoReelsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            let scopeDescription: String = {
                if case .day(let idx) = dayScope {
                    return dayLabels.indices.contains(idx) ? dayLabels[idx] : "Day \(idx + 1)"
                }
                return ""
            }()
            if scopeDescription.isEmpty {
                Text("No video reels are available for this blog. Use the in-app camera to capture video reels.")
            } else {
                Text("No video reels are available for \(scopeDescription). Try switching to All Days or use the in-app camera to capture video reels.")
            }
        }
        .sheet(isPresented: $showDayPicker) {
            DayScopePickerSheet(dayLabels: dayLabels, currentScope: dayScope) { newScope in
                dayScope = newScope
                showDayPicker = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            stopTimer()
            Task { await slideshowMusic.stopAll() }
        }
    }

    // MARK: - Reset

    private func resetToFirstSlide() {
        stopTimer()
        soloElapsed = 0
        withAnimation(.easeInOut(duration: 0.3)) {
            currentGroupIndex = 0
            currentSlideOffset = 0
            currentLayout = chooseLayout(groupIndex: 0, offset: 0)
        }
        if isPlaying { resumeSlideshowTimingIfPlaying() }
        Task { await preloadAround(groupIndex: 0, offset: 0) }
    }

    // MARK: - Slide content

    @ViewBuilder
    private func slideContent(geo: GeometryProxy) -> some View {
        let W = geo.size.width
        let H = geo.size.height

        switch currentLayout {

        case .solo:
            if contentMode == .reels, let player = videoPlayer {
                SlideshowVideoSlideView(player: player)
                    .ignoresSafeArea()
                    // Identity keyed on the player instance — changing the player triggers
                    // a proper SwiftUI crossfade between outgoing and incoming video views.
                    .id(ObjectIdentifier(player))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .opacity
                    ))
            } else if let id = topPhotoId, let img = loadedImages[id] {
                soloZoomView(img: img, size: geo.size)
                    .transition(.opacity)   // crossfade between photos
                    .id("solo-\(currentGroupIndex)-\(currentSlideOffset)")
            } else {
                loadingPlaceholder
            }

        case .diptych:
            let paneH = (H - 2) / 2
            VStack(spacing: 2) {
                // Top: enters from below, exits upward
                photoPane(id: topPhotoId, width: W, height: paneH, diptychExpandHalf: .top)
                    .id("dtop-\(currentGroupIndex)-\(currentSlideOffset)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
                // Bottom: enters from above, exits downward
                photoPane(id: bottomPhotoId, width: W, height: paneH, diptychExpandHalf: .bottom)
                    .id("dbot-\(currentGroupIndex)-\(currentSlideOffset)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
            .frame(width: W, height: H)
            .clipped()
            .onAppear { if isPlaying { startDiptychTimer() } }
            .onChange(of: currentSlideOffset) {
                guard currentLayout == .diptych, isPlaying else { return }
                startDiptychTimer()
            }
            .onChange(of: currentGroupIndex) {
                guard currentLayout == .diptych, isPlaying else { return }
                startDiptychTimer()
            }
        }
    }

    // MARK: - Solo zoom view (Ken Burns style)

    @ViewBuilder
    private func soloZoomView(img: UIImage, size: CGSize) -> some View {
        let combinedScale = currentScale * pinchBaseScale * pinchGestureScale

        Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(combinedScale)
            .clipped()
            .ignoresSafeArea()
            .animation(nil, value: currentScale)
            .animation(nil, value: pinchBaseScale)
            .animation(nil, value: pinchGestureScale)
            .gesture(soloPinchGesture)
            .onAppear {
                pinchBaseScale = 1
                pinchGestureScale = 1
                soloElapsed = 0
                updateSoloKenBurnsScale()
                if isPlaying { startSoloTimer() }
            }
    }

    /// Two-finger pinch zoom while paused (solo). `pinchGestureScale` is live factor during the gesture (starts at 1).
    private var soloPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !isPlaying else { return }
                pinchGestureScale = value
            }
            .onEnded { _ in
                guard !isPlaying else { return }
                pinchBaseScale = (pinchBaseScale * pinchGestureScale).clamped(to: pinchScaleMin...pinchScaleMax)
                pinchGestureScale = 1
            }
    }

    private func updateSoloKenBurnsScale() {
        let start: CGFloat = zoomIn ? 1.0 : zoomScale
        let end: CGFloat = zoomIn ? zoomScale : 1.0
        let t = (soloElapsed / CGFloat(soloDurationSeconds)).clamped(to: 0...1)
        currentScale = start + (end - start) * t
    }

    // MARK: - Diptych full-screen (paused only)

    private func openDiptychExpanded(_ half: DiptychHalf) {
        guard currentLayout == .diptych, diptychExpandedHalf == nil, !isPlaying else { return }
        let id = (half == .top) ? topPhotoId : bottomPhotoId
        guard let id, loadedImages[id] != nil else { return }
        diptychExpandPinchBase = 1
        diptychExpandPinchGesture = 1
        diptychExpandedHalf = half
    }

    private func clearDiptychExpanded() {
        diptychExpandedHalf = nil
        diptychExpandPinchBase = 1
        diptychExpandPinchGesture = 1
    }

    @ViewBuilder
    private func diptychExpandedOverlay(size: CGSize) -> some View {
        let id: String? = {
            switch diptychExpandedHalf {
            case .some(.top): return topPhotoId
            case .some(.bottom): return bottomPhotoId
            case .none: return nil
            }
        }()
        if let id, let img = loadedImages[id] {
            let scale = diptychExpandPinchBase * diptychExpandPinchGesture
            ZStack {
                Color.black
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .clipped()
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .animation(nil, value: diptychExpandPinchBase)
            .animation(nil, value: diptychExpandPinchGesture)
            // highPriorityGesture ensures pinch is never blocked by the parent DragGesture.
            .highPriorityGesture(diptychExpandedMagnificationGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    // Only dismiss when at (or near) normal scale — not while zoomed in.
                    if diptychExpandPinchBase * diptychExpandPinchGesture < 1.1 {
                        clearDiptychExpanded()
                    }
                }
            )
        }
    }

    private var diptychExpandedMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { diptychExpandPinchGesture = $0 }
            .onEnded { _ in
                diptychExpandPinchBase = (diptychExpandPinchBase * diptychExpandPinchGesture)
                    .clamped(to: pinchScaleMin...pinchScaleMax)
                diptychExpandPinchGesture = 1
            }
    }

    // MARK: - Photo pane

    /// `diptychExpandHalf`: which diptych pane this is; tap opens full view only while slideshow is **paused**.
    @ViewBuilder
    private func photoPane(id: String?, width: CGFloat, height: CGFloat, diptychExpandHalf: DiptychHalf? = nil) -> some View {
        if let id, let img = loadedImages[id] {
            if !isPlaying, let half = diptychExpandHalf {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { openDiptychExpanded(half) }
            } else {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .allowsHitTesting(false)
            }
        } else {
            Color.gray.opacity(0.25)
                .frame(width: width, height: height)
                .overlay(ProgressView().tint(.white).scaleEffect(0.7))
        }
    }

    private var loadingPlaceholder: some View {
        ProgressView().tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {

            // Dismiss slideshow → blog (gallery uses text "Close" in `galleryOverlay`).
            Button(action: dismissSlideshowToBlog) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            // Day scope pill — only when blog spans multiple days.
            if dayLabels.count > 1 {
                Button { showDayPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(dayScopeLabel)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter by day: \(dayScopeLabel)")
            }

            Spacer()

            // Content-mode toggle (photos ↔ reels) — only when reels exist.
            if hasAnyReels {
                Button {
                    let nextMode: SlideshowContentMode = contentMode == .photos ? .reels : .photos
                    if nextMode == .reels && !hasReelsInCurrentScope {
                        showNoReelsAlert = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            contentMode = nextMode
                        }
                    }
                } label: {
                    let isReels = contentMode == .reels
                    ZStack {
                        Circle().fill(.black.opacity(isReels ? 0.65 : 0.38))
                        Circle().strokeBorder(.white.opacity(isReels ? 0.3 : 0.12), lineWidth: 0.5)
                        Image(systemName: isReels ? "video.fill" : "photo.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isReels ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white.opacity(0.6))
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(contentMode == .reels ? "Switch to photo slideshow" : "Switch to reel slideshow")
            }

            // Music picker (muted when no background track is selected)
            Button { showMusicPicker = true } label: {
                let active = selectedSlideshowMusicFilename != nil
                ZStack {
                    Circle().fill(.black.opacity(active ? 0.6 : 0.38))
                    Circle().strokeBorder(.white.opacity(active ? 0.25 : 0.12), lineWidth: 0.5)
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(active ? 1 : 0.38))
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(slideshowMusicAccessibilityLabel)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: max(8, geo.size.width * overallProgress), height: 4)
                    .shadow(color: .white.opacity(0.55), radius: 4)
                    .animation(.linear(duration: timerInterval), value: overallProgress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack(spacing: 0) {
            // Gallery button — bottom left
            Button {
                presentSlideshowGallery()
            } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.6))
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 56)
            Spacer()

            Button(action: togglePlayPause) {
                ZStack {
                    Circle().fill(.black.opacity(0.6))
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
                .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)

            Spacer()

            // Group counter (which place we're on)
            if activeGroups.count > 1 {
                Text("\(currentGroupIndex + 1)/\(activeGroups.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            } else {
                Color.clear.frame(width: 56, height: 1)
            }
        }
    }

    @ViewBuilder
    private func pausedSlideshowMetadataRow(entry: PanoramaPhotoEntry) -> some View {
        let placeTitle: String = {
            let n = entry.placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return n.isEmpty ? "" : n
        }()
        let hasText = !placeTitle.isEmpty || entry.timestamp != nil
            || !(entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let hasMap = entry.location != nil
        if hasText || hasMap {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if !placeTitle.isEmpty {
                        Text(placeTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                    if let ts = entry.timestamp {
                        Text(Self.captionTimestampFormatter.string(from: ts))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    }
                    if let cap = entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                        Text(cap)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if let coord = entry.location {
                        Button {
                            openSlideshowLocationInAppleMaps(coordinate: coord)
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open in Maps")
                    }
                    Button {
                        Task { await downloadSlideshowPhotoFromPausedOverlay(entry: entry) }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Download Photo")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.42))
            )
        } else {
            HStack {
                Spacer()
                Button {
                    Task { await downloadSlideshowPhotoFromPausedOverlay(entry: entry) }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download Photo")
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private func openSlideshowLocationInAppleMaps(coordinate: PhotoCoordinate) {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        guard let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)") else { return }
        UIApplication.shared.open(url)
    }

    private func downloadSlideshowPhotoFromPausedOverlay(entry: PanoramaPhotoEntry) async {
        let screen = UIScreen.main.bounds.size
        let target = CGSize(width: screen.width * 3, height: screen.height * 3)
        let image: UIImage?
        if let cached = loadedImages[entry.id] ?? AppCapturePhotoService.shared.loadImage(identifier: entry.id) {
            image = cached
        } else {
            image = await ImageLoader.shared.loadImage(assetIdentifier: entry.id, targetSize: target)
        }
        guard let image else {
            await MainActor.run {
                pausedSlideshowDownloadToast = "Could not load photo"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pausedSlideshowDownloadToast = nil }
            }
            return
        }
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { cont.resume(returning: ok) }
            }
        }
        await MainActor.run {
            pausedSlideshowDownloadToast = success ? "1 photo saved to Photos" : "Could not save to Photos"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pausedSlideshowDownloadToast = nil }
        }
    }

    // MARK: - Reel info overlay

    /// Place name + caption panel shown at the start of each reel slide, anchored above the bottom controls.
    @ViewBuilder
    private func reelInfoPanel(entry: PanoramaPhotoEntry) -> some View {
        let placeName = entry.placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !placeName.isEmpty || !caption.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !placeName.isEmpty {
                    Label(placeName, systemImage: "mappin.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                        .lineLimit(2)
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            // Position above progress bar + play button + safe area (≈120 pt from bottom).
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Gallery overlay

    private func presentSlideshowGallery() {
        useFadeForGalleryTransition = false
        wasPlayingBeforeGallery = isPlaying
        stopTimer()
        if isPlaying {
            Task { await slideshowMusic.pause() }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showGallery = true
        }
    }

    private func dismissSlideshowGallery() {
        galleryDetailPhotoId = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showGallery = false
        }
    }

    /// Resume slideshow playback from gallery mode.
    private func resumePlaybackFromGalleryCover() {
        useFadeForGalleryTransition = true
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                showGallery = false
            }
            isPlaying = true
            resumeSlideshowTimingIfPlaying()
            Task { await slideshowMusic.resume() }
        }
    }

    /// Leave slideshow entirely and return to the recap blog.
    private func dismissSlideshowToBlog() {
        stopTimer()
        Task { @MainActor in
            await slideshowMusic.stopAll()
            dismiss()
            onDismiss()
        }
    }

    /// Matches `RecapBlogPageView.coverPhotoHero` — full width, 55% of screen height.
    private static let coverHeroHeightFraction: CGFloat = 0.55

    /// Same column/spacing model as `ManagePhotosView.photoGrid`.
    private static let galleryGridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// Gallery ignores the safe area; top chrome uses `SlideshowGalleryLayout.chromeTopPadding()` so controls clear the status bar.
    private var galleryOverlay: some View {
        GeometryReader { geo in
            let coverHeight = geo.size.height * Self.coverHeroHeightFraction
            let allPhotos = activeGroups.flatMap { $0 }
            let groupedPhotosByPlace: [(placeName: String, photos: [PanoramaPhotoEntry])] = {
                var orderedGroups: [(placeName: String, photos: [PanoramaPhotoEntry])] = []
                for entry in allPhotos {
                    let normalizedPlace = {
                        let trimmed = entry.placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? "Unknown Place" : trimmed
                    }()
                    if let idx = orderedGroups.firstIndex(where: { $0.placeName == normalizedPlace }) {
                        orderedGroups[idx].photos.append(entry)
                    } else {
                        orderedGroups.append((placeName: normalizedPlace, photos: [entry]))
                    }
                }
                return orderedGroups
            }()
            let heroPhotoId: String? = {
                guard currentFlatIndex >= 0, currentFlatIndex < allPhotos.count else { return nil }
                return allPhotos[currentFlatIndex].id
            }()

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                if let detailId = galleryDetailPhotoId {
                    SlideshowGalleryPhotoDetailView(
                        photos: allPhotos,
                        initialPhotoId: detailId,
                        cachedImages: loadedImages,
                        onClose: {
                            galleryDetailPhotoId = nil
                        },
                        onAppCaptureDeleted: { identifier in
                            loadedImages.removeValue(forKey: identifier)
                            onAppCaptureDeletedFromSlideshow?(identifier)
                        }
                    )
                    .transition(.opacity)
                } else {
                    ZStack(alignment: .topLeading) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Cover-sized hero: current slide + title + Play (scrolls with grid)
                        ZStack {
                            Group {
                                if let heroPhotoId, let img = loadedImages[heroPhotoId] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else if heroPhotoId != nil {
                                    Color.gray.opacity(0.25)
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Color.gray.opacity(0.35)
                                }
                            }
                            .frame(width: geo.size.width, height: coverHeight)
                            .clipped()

                            Color.black.opacity(0.28)

                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.55),
                                    Color.black.opacity(0.12),
                                    Color.black.opacity(0.4)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )

                            VStack(spacing: 14) {
                                Text(blogTitle)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                                    .padding(.horizontal, 24)

                                Button {
                                    resumePlaybackFromGalleryCover()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Play")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.white.opacity(0.22)))
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: geo.size.width, height: coverHeight)
                        }
                        .frame(width: geo.size.width, height: coverHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resumePlaybackFromGalleryCover()
                        }
                        .task(id: heroPhotoId) {
                            guard let id = heroPhotoId, loadedImages[id] == nil else { return }
                            let target = CGSize(width: geo.size.width * 2, height: coverHeight * 2)
                            if let img = await ImageLoader.shared.loadImage(assetIdentifier: id, targetSize: target) {
                                await MainActor.run { loadedImages[id] = img }
                            }
                        }
                        .padding(.bottom, 16)

                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(groupedPhotosByPlace, id: \.placeName) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(group.placeName)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 18)

                                    LazyVGrid(columns: Self.galleryGridColumns, spacing: 2) {
                                        ForEach(group.photos, id: \.id) { photo in
                                            GeometryReader { cellGeo in
                                                GalleryThumbCell(
                                                    entry: photo,
                                                    loadedImages: loadedImages,
                                                    isCurrentPhoto: photo.id == heroPhotoId
                                                )
                                                .frame(width: cellGeo.size.width, height: cellGeo.size.width)
                                                .clipped()
                                            }
                                            .aspectRatio(1, contentMode: .fit)
                                            .onTapGesture {
                                                galleryDetailPhotoId = photo.id
                                            }
                                        }
                                    }
                                    .padding(2)
                                }
                            }
                        }

                        Color.clear
                            .frame(height: geo.safeAreaInsets.bottom + 16)
                    }
                }

                // Close gallery and return to slideshow playback.
                Button(action: resumePlaybackFromGalleryCover) {
                    Text("Close")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, SlideshowGalleryLayout.chromeTopPadding())
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Layout logic

    /// Choose layout for a given group position.
    private func chooseLayout(groupIndex: Int, offset: Int) -> SlideLayout {
        guard groupIndex < activeGroups.count else { return .solo }
        // Reels mode always uses solo layout (video fills the screen).
        if contentMode == .reels { return .solo }
        let remaining = activeGroups[groupIndex].count - offset
        if remaining >= 2 {
            return [.solo, .diptych].randomElement()!
        }
        return .solo
    }

    private func toggleLayout() {
        stopTimer()
        let next: SlideLayout = currentLayout == .solo ? .diptych : .solo
        // Can only switch to diptych if current group has a second photo at this offset
        guard next == .solo || currentSlideOffset + 1 < currentGroup.count else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            currentLayout = next
        }
        if isPlaying {
            if next == .solo { /* onAppear of soloZoomView restarts the solo timer */ }
            else { startDiptychTimer() }
        }
    }

    // MARK: - Manual navigation (tap / swipe; does not change `isPlaying`)

    private func navigateToNextSlide() {
        stopTimer()
        advanceSlide()
        if isPlaying {
            soloElapsed = 0
            resumeSlideshowTimingIfPlaying()
        }
    }

    private func navigateToPreviousSlide() {
        stopTimer()
        retreatSlide()
        if isPlaying {
            soloElapsed = 0
            resumeSlideshowTimingIfPlaying()
        }
    }

    // MARK: - Advance

    private func advanceSlide() {
        guard !activeGroups.isEmpty else { return }
        clearDiptychExpanded()

        // How many photos does the current slide consume?
        let step = (currentLayout == .diptych) ? 2 : 1
        let group = currentGroup
        let nextOffset = currentSlideOffset + step

        let (nextGroupIdx, nextOffset_, nextLayout): (Int, Int, SlideLayout)

        if nextOffset < group.count {
            // Still within the same group
            let layout = chooseLayout(groupIndex: currentGroupIndex, offset: nextOffset)
            nextGroupIdx  = currentGroupIndex
            nextOffset_   = nextOffset
            nextLayout    = layout
        } else {
            // Move to the next group (wrap around)
            let ng = (currentGroupIndex + 1) % activeGroups.count
            let layout = chooseLayout(groupIndex: ng, offset: 0)
            nextGroupIdx  = ng
            nextOffset_   = 0
            nextLayout    = layout
        }

        // Alternate zoom direction each solo slide for visual variety
        if nextLayout == .solo { zoomIn.toggle() }

        withAnimation(.easeInOut(duration: 0.5)) {
            currentGroupIndex  = nextGroupIdx
            currentSlideOffset = nextOffset_
            currentLayout      = nextLayout
        }

        Task { await preloadAround(groupIndex: nextGroupIdx, offset: nextOffset_) }
    }

    private func retreatSlide() {
        guard !activeGroups.isEmpty else { return }
        clearDiptychExpanded()
        soloElapsed = 0

        let prevGroupIdx: Int
        let prevOffset: Int

        if currentSlideOffset > 0 {
            prevGroupIdx = currentGroupIndex
            prevOffset   = currentSlideOffset - 1
        } else if currentGroupIndex > 0 {
            prevGroupIdx = currentGroupIndex - 1
            prevOffset   = max(0, activeGroups[prevGroupIdx].count - 1)
        } else {
            // Already at the very first photo — wrap to the last
            prevGroupIdx = activeGroups.count - 1
            prevOffset   = max(0, activeGroups[prevGroupIdx].count - 1)
        }

        let prevLayout = chooseLayout(groupIndex: prevGroupIdx, offset: prevOffset)
        if prevLayout == .solo { zoomIn.toggle() }

        withAnimation(.easeInOut(duration: 0.5)) {
            currentGroupIndex  = prevGroupIdx
            currentSlideOffset = prevOffset
            currentLayout      = prevLayout
        }

        if isPlaying, prevLayout == .diptych { startDiptychTimer() }
        Task { await preloadAround(groupIndex: prevGroupIdx, offset: prevOffset) }
    }

    // MARK: - Timers

    /// Per-frame timer for the solo slide: updates `soloElapsed` (progress bar)
    /// and fires `advanceSlide()` when the duration is reached.
    private func startSoloTimer() {
        stopTimer()
        let frozenElapsed = soloElapsed
        let anchor = Date()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
            Task { @MainActor in
                self.soloElapsed = frozenElapsed + CGFloat(Date().timeIntervalSince(anchor))
                if self.currentLayout == .solo {
                    self.updateSoloKenBurnsScale()
                }
                if self.soloElapsed >= CGFloat(self.soloDurationSeconds) {
                    self.stopTimer()
                    self.advanceSlide()
                }
            }
        }
    }

    private func startDiptychTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: diptychDurationSeconds, repeats: false) { _ in
            Task { @MainActor in self.advanceSlide() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Restores bundled track from `UserDefaults` when the file is still in the app bundle.
    private func duckSlideshowMusicForReelPlayback() {
        slideshowMusic.setVolume(Self.slideshowMusicDuckedVolume)
    }

    private func restoreSlideshowMusicVolumeForPhotos() {
        slideshowMusic.setVolume(1)
    }

    private func configureAudioSessionForReelSlideshow() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func restorePersistedSlideshowMusic() async {
        let key = blogId.uuidString
        let saved = SlideshowMusicPreference.load(blogId: key)

        // No preference saved yet — apply the default track.
        if saved == nil {
            let defaultFilename = SlideshowMusicPreference.defaultFilename
            if let url = SlideshowMusicPreference.bundleURL(forBundledFilename: defaultFilename) {
                selectedSlideshowMusicFilename = defaultFilename
                await slideshowMusic.play(url: url, startPlayback: isPlaying)
            }
            return
        }

        // User explicitly chose "No background music".
        if saved!.isExplicitNone {
            selectedSlideshowMusicFilename = nil
            return
        }

        guard let url = SlideshowMusicPreference.bundleURL(forBundledFilename: saved!.filename) else {
            SlideshowMusicPreference.clear(blogId: key)
            selectedSlideshowMusicFilename = nil
            return
        }
        selectedSlideshowMusicFilename = saved!.filename
        await slideshowMusic.play(url: url, startPlayback: isPlaying)
    }

    /// Restarts solo/diptych advance timers after an interruption (e.g. music picker sheet).
    private func resumeSlideshowTimingIfPlaying() {
        guard isPlaying, diptychExpandedHalf == nil else { return }
        switch currentLayout {
        case .solo: startSoloTimer()
        case .diptych: startDiptychTimer()
        }
    }

    private func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            pinchBaseScale = 1
            pinchGestureScale = 1
            clearDiptychExpanded()
            switch currentLayout {
            case .solo:    startSoloTimer()
            case .diptych: startDiptychTimer()
            }
            Task { await slideshowMusic.resume() }
        } else {
            stopTimer()
            // Collapse diptych to solo when pausing — show one photo at a time while paused.
            if currentLayout == .diptych {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentLayout = .solo
                }
            }
            updateSoloKenBurnsScale()
            Task { await slideshowMusic.pause() }
        }
    }

    // MARK: - Image loading

    /// Preload photos around the current position: current group + neighbours.
    private func preloadAround(groupIndex: Int, offset: Int) async {
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * 3, height: screenSize.height * 2)

        // Collect IDs to preload: up to 6 photos starting from current position
        var ids: [String] = []
        var gIdx = groupIndex
        var pIdx = offset
        let groups = activeGroups
        while ids.count < 6, gIdx < groups.count {
            let group = groups[gIdx]
            while pIdx < group.count, ids.count < 6 {
                ids.append(group[pIdx].id)
                pIdx += 1
            }
            gIdx += 1
            pIdx = 0
        }

        for id in ids {
            guard loadedImages[id] == nil else { continue }
            if let img = await ImageLoader.shared.loadImage(assetIdentifier: id, targetSize: targetSize) {
                await MainActor.run { loadedImages[id] = img }
            }
        }
    }

}

// MARK: - Slideshow gallery full-screen photo (3×3 grid tap)

/// Full-screen paging viewer inside the slideshow pull-up grid; matches Bloggo gallery chrome (download; delete only for `bloggo-capture:` assets).
private struct SlideshowGalleryPhotoDetailView: View {
    private enum NavigationMapAppPreference: String {
        case apple
        case google
    }
    private static let navigationChooserSuppressedKey = "placePhotoNavigationChooserSuppressed"
    private static let navigationChooserPreferredAppKey = "placePhotoNavigationPreferredApp"

    let photos: [PanoramaPhotoEntry]
    let initialPhotoId: String
    let cachedImages: [String: UIImage]
    var onClose: () -> Void
    var onAppCaptureDeleted: (String) -> Void

    @State private var selectedPhotoId: String
    @State private var showControls = true
    @State private var showDeleteConfirm = false
    @State private var downloadToast: String?
    @State private var showNavigationAppChooser = false
    @State private var navigationDoNotShowAgain = false
    @AppStorage(Self.navigationChooserSuppressedKey) private var navigationChooserSuppressed = false
    @AppStorage(Self.navigationChooserPreferredAppKey) private var navigationChooserPreferredAppRaw = ""

    init(
        photos: [PanoramaPhotoEntry],
        initialPhotoId: String,
        cachedImages: [String: UIImage],
        onClose: @escaping () -> Void,
        onAppCaptureDeleted: @escaping (String) -> Void
    ) {
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.cachedImages = cachedImages
        self.onClose = onClose
        self.onAppCaptureDeleted = onAppCaptureDeleted
        _selectedPhotoId = State(initialValue: initialPhotoId)
    }

    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy 'at' h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var currentEntry: PanoramaPhotoEntry? {
        photos.first { $0.id == selectedPhotoId }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                Text("No photos")
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                TabView(selection: $selectedPhotoId) {
                    ForEach(photos, id: \.id) { entry in
                        SlideshowGalleryDetailZoomPage(
                            entry: entry,
                            cached: cachedImages[entry.id]
                        )
                        .tag(entry.id)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                if showControls {
                    VStack {
                        topChrome
                        Spacer()
                        bottomChrome
                    }
                    .ignoresSafeArea(edges: .bottom)
                }

                if let downloadToast {
                    VStack {
                        Spacer()
                        Text(downloadToast)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .padding(.bottom, 32)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }

            if showNavigationAppChooser {
                navigationAppChooserOverlay
                    .zIndex(30)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !photos.contains(where: { $0.id == selectedPhotoId }), let first = photos.first {
                selectedPhotoId = first.id
            }
        }
        .onChange(of: photos) { oldList, newList in
            if newList.isEmpty {
                onClose()
                return
            }
            guard !newList.contains(where: { $0.id == selectedPhotoId }) else { return }
            let oldIndex = oldList.firstIndex { $0.id == selectedPhotoId } ?? 0
            let idx = min(oldIndex, newList.count - 1)
            selectedPhotoId = newList[idx].id
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeleteCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the photo from your device.")
        }
    }

    private var topChrome: some View {
        VStack {
            ZStack {
                HStack(alignment: .top) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer(minLength: 0)

                    // Top-trailing slot for Vibe (or other controls) when wired per-photo.
                    Color.clear
                        .frame(width: 36, height: 36)
                }

                if photos.count > 1, let idx = photos.firstIndex(where: { $0.id == selectedPhotoId }) {
                    Text("\(idx + 1) / \(photos.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, SlideshowGalleryLayout.chromeTopPadding())
            Spacer()
        }
    }

    private var bottomChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let entry = currentEntry {
                let placeTitle: String = {
                    let n = entry.placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return n.isEmpty ? "Unknown Place" : n
                }()

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)

                    if let ts = entry.timestamp {
                        Text(Self.detailDateFormatter.string(from: ts))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 1)
                    }
                }

                if let cap = entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                    Text(cap)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }

                HStack {
                    Button {
                        Task { await downloadCurrentPhoto() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                    }
                    .accessibilityLabel("Download Photo")

                    if let coord = entry.location {
                        Button {
                            handleNavigationTap(for: coord)
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                        }
                        .accessibilityLabel("Open in Maps")
                    }

                    Spacer()

                    if AppCapturePhotoService.uuid(from: entry.id) != nil {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                        }
                        .accessibilityLabel("Delete Photo")
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func downloadCurrentPhoto() async {
        guard let entry = currentEntry else { return }
        let screen = UIScreen.main.bounds.size
        let target = CGSize(width: screen.width * 3, height: screen.height * 3)
        let image: UIImage?
        if let cached = cachedImages[entry.id] ?? AppCapturePhotoService.shared.loadImage(identifier: entry.id) {
            image = cached
        } else {
            image = await ImageLoader.shared.loadImage(assetIdentifier: entry.id, targetSize: target)
        }
        guard let image else {
            await MainActor.run {
                downloadToast = "Could not load photo"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
            }
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    if success {
                        downloadToast = "1 photo saved to Photos"
                    } else {
                        downloadToast = "Could not save to Photos"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                    cont.resume()
                }
            }
        }
    }

    private func confirmDeleteCurrent() {
        guard let id = currentEntry?.id, AppCapturePhotoService.uuid(from: id) != nil else { return }
        onAppCaptureDeleted(id)
        showDeleteConfirm = false
    }

    private var preferredNavigationApp: NavigationMapAppPreference? {
        NavigationMapAppPreference(rawValue: navigationChooserPreferredAppRaw)
    }

    private func handleNavigationTap(for coordinate: PhotoCoordinate) {
        if navigationChooserSuppressed, let preferredNavigationApp {
            openNavigation(with: preferredNavigationApp, coordinate: coordinate)
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
        guard let coord = currentEntry?.location else { return }
        openNavigation(with: app, coordinate: coord)
    }

    private func openNavigation(with app: NavigationMapAppPreference, coordinate: PhotoCoordinate) {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

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
}

private struct SlideshowGalleryDetailZoomPage: View {
    let entry: PanoramaPhotoEntry
    let cached: UIImage?

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var resolved: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = resolved ?? cached {
                    zoomableImage(geo: geo, image: image)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .ignoresSafeArea()
        .task(id: entry.id) {
            guard resolved == nil, cached == nil else { return }
            let screen = UIScreen.main.bounds.size
            let target = CGSize(width: screen.width * 2.5, height: screen.height * 2.5)
            if let img = await ImageLoader.shared.loadImage(assetIdentifier: entry.id, targetSize: target) {
                await MainActor.run { resolved = img }
            }
        }
    }

    @ViewBuilder
    private func zoomableImage(geo: GeometryProxy, image: UIImage) -> some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * magnifyBy)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .updating($magnifyBy) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = max(1, scale * value)
                        if scale <= 1 { offset = .zero }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1 { scale = 1; offset = .zero }
                    else { scale = 2.5 }
                }
            }
        if scale > 1 {
            base.gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
            )
        } else {
            base
        }
    }
}

private extension PanoramaPlayerView {
    static let captionTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMM d, yyyy  h:mm a"
        return f
    }()
}

// MARK: - Gallery thumb cell

private struct GalleryThumbCell: View {
    let entry: PanoramaPhotoEntry
    let loadedImages: [String: UIImage]
    let isCurrentPhoto: Bool
    @State private var thumb: UIImage?

    var body: some View {
        let img = thumb ?? loadedImages[entry.id]
        ZStack {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.25)
                ProgressView().tint(.white).scaleEffect(0.7)
            }
        }
        .clipped()
        .task(id: entry.id) {
            guard thumb == nil, loadedImages[entry.id] == nil else { return }
            thumb = await ImageLoader.shared.loadThumbnail(
                assetIdentifier: entry.id,
                targetSize: CGSize(width: 200, height: 200)
            )
        }
    }
}

// MARK: - Video slide (reel mode)

private final class _SlideshowPlayerView: UIView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct SlideshowVideoSlideView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> _SlideshowPlayerView {
        _SlideshowPlayerView(player: player)
    }

    func updateUIView(_ uiView: _SlideshowPlayerView, context: Context) {}
}

// MARK: - Day scope picker sheet

private struct DayScopePickerSheet: View {
    let dayLabels: [String]
    let currentScope: SlideshowDayScope
    let onSelect: (SlideshowDayScope) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(.allDays)
                } label: {
                    HStack {
                        Text("All Days")
                            .foregroundStyle(.primary)
                        Spacer()
                        if case .allDays = currentScope {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                ForEach(dayLabels.indices, id: \.self) { idx in
                    Button {
                        onSelect(.day(idx))
                    } label: {
                        HStack {
                            Text(dayLabels[idx])
                                .foregroundStyle(.primary)
                            Spacer()
                            if case .day(let selected) = currentScope, selected == idx {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Show")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Comparable clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
