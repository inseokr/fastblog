import Photos
import SwiftUI

// MARK: - Photo entry (asset ID + optional caption)

struct PanoramaPhotoEntry: Equatable {
    let id: String
    let caption: String?
}

// MARK: - Layout variant (solo or top/bottom diptych only)

private enum SlideLayout: Equatable {
    case solo
    case diptych
}

/// Which half of a diptych slide was opened full screen.
private enum DiptychHalf {
    case top
    case bottom
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
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

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

    /// Diptych: one pane tapped → full screen + pinch until play resumes.
    @State private var diptychExpandedHalf: DiptychHalf?
    @State private var diptychExpandPinchBase: CGFloat = 1.0
    @State private var diptychExpandPinchGesture: CGFloat = 1.0

    // MARK: - Playback
    @State private var isPlaying: Bool = true
    @State private var timer: Timer?

    // MARK: - Music
    @State private var showMusicPicker: Bool = false
    /// Bundled track filename when slideshow has background music; `nil` = none selected.
    @State private var selectedSlideshowMusicFilename: String?
    @State private var slideshowMusic = SlideshowMusicPlaybackCoordinator()
    /// True when we paused slideshow music because the bundled-track sheet was open (resume on cancel only).
    @State private var pausedSlideshowMusicForPicker = false

    // MARK: - Constants
    private let soloDurationSeconds: Double = 4.0
    private let diptychDurationSeconds: Double = 4.0
    private let timerInterval: Double = 1.0 / 60.0
    private let zoomScale: CGFloat = 1.12   // how far to zoom in/out
    private let pinchScaleMin: CGFloat = 0.5
    private let pinchScaleMax: CGFloat = 4.0

    // MARK: - Derived

    private var currentGroup: [PanoramaPhotoEntry] {
        guard currentGroupIndex < photoGroups.count else { return [] }
        return photoGroups[currentGroupIndex]
    }

    /// Asset ID of the top (or only) photo on the current slide.
    private var topPhotoId: String? {
        guard currentSlideOffset < currentGroup.count else { return nil }
        return currentGroup[currentSlideOffset].id
    }

    /// Caption of the top (or only) photo on the current slide.
    private var topPhotoCaption: String? {
        guard currentSlideOffset < currentGroup.count else { return nil }
        return currentGroup[currentSlideOffset].caption
    }

    /// Asset ID of the bottom photo in diptych mode (same group, next slot).
    private var bottomPhotoId: String? {
        guard currentLayout == .diptych,
              currentSlideOffset + 1 < currentGroup.count
        else { return nil }
        return currentGroup[currentSlideOffset + 1].id
    }

    private var totalPhotos: Int { photoGroups.reduce(0) { $0 + $1.count } }

    private var currentFlatIndex: Int {
        photoGroups[0..<currentGroupIndex].reduce(0) { $0 + $1.count } + currentSlideOffset
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

            // Chrome — extend to physical bottom; explicit padding replaces implicit safe-area inset
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 2)
                    .padding(.horizontal, 20)
                Spacer()
                VStack(spacing: 10) {
                    if diptychExpandedHalf == nil, let caption = topPhotoCaption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 24)
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                            .transition(.opacity)
                    }
                    progressBar
                        .padding(.horizontal, 24)
                    bottomControls
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(nil, value: currentGroupIndex)
            .animation(nil, value: currentSlideOffset)
            .animation(nil, value: currentLayout)
        }
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
                    SlideshowMusicPreference.clear(blogId: blogId.uuidString)
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
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // Only handle horizontal swipes (horizontal > vertical)
                    guard abs(dx) > abs(dy) else { return }
                    if dx < 0 {
                        // Swipe left → next slide
                        stopTimer()
                        advanceSlide()
                    } else {
                        // Swipe right → previous slide
                        stopTimer()
                        retreatSlide()
                    }
                }
        )
        .task {
            await preloadAround(groupIndex: 0, offset: 0)
            currentLayout = chooseLayout(groupIndex: 0, offset: 0)
            await restorePersistedSlideshowMusic()
        }
        .onDisappear {
            stopTimer()
            Task { await slideshowMusic.stopAll() }
        }
    }

    // MARK: - Slide content

    @ViewBuilder
    private func slideContent(geo: GeometryProxy) -> some View {
        let W = geo.size.width
        let H = geo.size.height

        switch currentLayout {

        case .solo:
            if let id = topPhotoId, let img = loadedImages[id] {
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
                photoPane(id: topPhotoId, width: W, height: paneH, expandOnTap: .top)
                    .id("dtop-\(currentGroupIndex)-\(currentSlideOffset)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
                // Bottom: enters from above, exits downward
                photoPane(id: bottomPhotoId, width: W, height: paneH, expandOnTap: .bottom)
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

    // MARK: - Diptych full-screen expand

    private func openDiptychExpanded(_ half: DiptychHalf) {
        guard currentLayout == .diptych, diptychExpandedHalf == nil else { return }
        let id = (half == .top) ? topPhotoId : bottomPhotoId
        guard let id, loadedImages[id] != nil else { return }
        stopTimer()
        isPlaying = false
        diptychExpandPinchBase = 1
        diptychExpandPinchGesture = 1
        diptychExpandedHalf = half
        Task { await slideshowMusic.pause() }
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
            case .top: return topPhotoId
            case .bottom: return bottomPhotoId
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
            .gesture(diptychExpandedMagnificationGesture)
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

    @ViewBuilder
    private func photoPane(id: String?, width: CGFloat, height: CGFloat, expandOnTap: DiptychHalf? = nil) -> some View {
        if let id, let img = loadedImages[id] {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let expandOnTap else { return }
                    openDiptychExpanded(expandOnTap)
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
        HStack(alignment: .center, spacing: 10) {

            // Close
            Button {
                stopTimer()
                Task { @MainActor in
                    await slideshowMusic.stopAll()
                    dismiss()
                    onDismiss()
                }
            } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.6))
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

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
            Color.clear.frame(width: 56, height: 1)
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
            if photoGroups.count > 1 {
                Text("\(currentGroupIndex + 1)/\(photoGroups.count)")
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

    // MARK: - Layout logic

    /// Choose layout for a given group position.
    private func chooseLayout(groupIndex: Int, offset: Int) -> SlideLayout {
        guard groupIndex < photoGroups.count else { return .solo }
        let remaining = photoGroups[groupIndex].count - offset
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

    // MARK: - Advance

    private func advanceSlide() {
        guard !photoGroups.isEmpty else { return }
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
            let ng = (currentGroupIndex + 1) % photoGroups.count
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
        guard !photoGroups.isEmpty else { return }
        clearDiptychExpanded()
        soloElapsed = 0

        let prevGroupIdx: Int
        let prevOffset: Int

        if currentSlideOffset > 0 {
            prevGroupIdx = currentGroupIndex
            prevOffset   = currentSlideOffset - 1
        } else if currentGroupIndex > 0 {
            prevGroupIdx = currentGroupIndex - 1
            prevOffset   = max(0, photoGroups[prevGroupIdx].count - 1)
        } else {
            // Already at the very first photo — wrap to the last
            prevGroupIdx = photoGroups.count - 1
            prevOffset   = max(0, photoGroups[prevGroupIdx].count - 1)
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
    private func restorePersistedSlideshowMusic() async {
        let key = blogId.uuidString
        guard let saved = SlideshowMusicPreference.load(blogId: key) else {
            selectedSlideshowMusicFilename = nil
            return
        }
        guard let url = SlideshowMusicPreference.bundleURL(forBundledFilename: saved.filename) else {
            SlideshowMusicPreference.clear(blogId: key)
            selectedSlideshowMusicFilename = nil
            return
        }
        selectedSlideshowMusicFilename = saved.filename
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
            if currentLayout == .solo {
                updateSoloKenBurnsScale()
            }
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
        while ids.count < 6, gIdx < photoGroups.count {
            let group = photoGroups[gIdx]
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

// MARK: - Comparable clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
