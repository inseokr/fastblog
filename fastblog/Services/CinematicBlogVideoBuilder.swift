// fastblog/Services/CinematicBlogVideoBuilder.swift
import AVFoundation
import UIKit
import Foundation
import MapKit

/// Builds the cinematic video frame sequence and streams each frame to the caller via
/// `frameHandler` so memory stays flat (one frame live at a time).
///
/// Sequence: cover (hold) → optional cross-dissolve into the first day’s overview map, then per-place:
///   1. Pan animation  — 14 true snapshots: first stop of each day from day-wide map → neighborhood;
///      later stops pan neighborhood→neighborhood (retains secondary zoom, no zoom-out reset).
///   2. Zoom-in        — `MapAnimationQuality.efficient`: cross-dissolve at cinematicZoomSegmentTargetFPS.
///                       `.highFidelity`: interpolated MKMapSnapshotter frames (true tile zoom; slower export).
///   3. Focused reveal — 0.003° with place info overlaid at bottom (2.5 s wall; bottom chrome fades in over the first ~0.5 s)
///   4. Photo/reel slides — if a moment-video reel exists for a photo, the reel plays directly (with place/time overlay) instead of a Ken-Burns still; otherwise the still is shown with Ken Burns
enum CinematicBlogVideoBuilder {

    /// Target temporal sampling for the wide→tight zoom dissolve (no extra MapKit work).
    private static let cinematicZoomSegmentTargetFPS: Double = 30
    /// Wall-clock for the zoom segment. Split into two phases: pure crop-scale (0→65 %) then a
    /// dissolve to sharp tight tiles (65→100 %). 1.1 s gives the physical zoom enough screen time
    /// before the sharpening dissolve.
    private static let cinematicZoomSegmentDurationSeconds: Double = 1.1

    private static let cinematicPanFrameDurationSeconds: Double = 0.11

    /// Supersample MapKit snapshots (@3× logical canvas) then downscale into the 1080p frame for sharper
    /// tiles and overlay text than @2× alone; matches `BlogVideoExportService` 2× logical → 1080×1920 output.
    private static let exportMapDisplayScale: CGFloat = 3
    private static let cinematicPanFrameCount = 14
    /// After the first place on a day, the map “hands off” from the previous marker (still highlighted)
    /// → brief all-muted beat → new marker + optional on-map place pill for the rest of the pan.
    private static let cinematicPanHandoffPreviousHighlightFrames = 5
    private static let cinematicPanHandoffAllMutedFrames = 3
    /// Snapshot-based wide→tight zoom when using `MapAnimationQuality.highFidelity`.
    private static let cinematicHighFidelityZoomFrameCount = 22

    /// Tight map + place overlay hold before photo slides (includes bottom-chrome fade-in).
    private static let cinematicFocusedMapHoldSeconds: Double = 1.5
    /// Bottom place chrome (gradient, pin, title, time, thumbs) eases in over the held tight map.
    private static let cinematicPlaceOverlayFadeInSeconds: Double = 0.5
    private static let cinematicPlaceOverlayFadeInFPS: Double = 30

    /// Map hold → first photo: hero zoom from the in-map thumbnail cell to the slide aspect-fill rect.
    private static let mapToFirstPhotoTransitionSeconds: Double = 0.50
    private static let mapToFirstPhotoTransitionFPS: Double = 30

    /// Last photo slide → next place's map: cross-dissolve out.
    private static let lastPhotoToMapFadeSeconds: Double = 0.50
    private static let lastPhotoToMapFadeFPS: Double = 30

    /// Ken Burns slow zoom on each photo hold.  Even-indexed photos zoom in, odd zoom out.
    private static let cinematicPhotoKenBurnsFactor: CGFloat = 0.06
    private static let cinematicPhotoKenBurnsFPS: Double = 15
    /// Cross-dissolve between consecutive photo slides within a place stop.
    private static let cinematicPhotoToPhotoDissolveDurationSeconds: Double = 0.40
    private static let cinematicPhotoToPhotoDissolveTargetFPS: Double = 30

    /// Map → moment-video reel transition (zoom-burst reveal).
    private static let mapToReelTransitionSeconds: Double = 0.50
    private static let mapToReelTransitionFPS: Double = 30
    private static let momentVideoExportFPS: Double = 30

    /// After the cover hold, cross-dissolve into the first day’s overview map (same frame as pan start).
    private static let coverToMapTransitionSeconds: Double = 0.72
    private static let coverToMapTransitionFPS: Double = 30

    // MARK: Opening hook (cover → hero still → map)

    /// Title card before the hero still (down from a flat 2 s hold so the hook lands faster).
    private static let openingCoverHoldSeconds: Double = 1.15
    private static let openingCoverToHeroDissolveSeconds: Double = 0.45
    private static let openingCoverToHeroDissolveFPS: Double = 30
    /// Ken Burns duration on the hook hero still (cover photo).
    private static let openingHeroKenBurnsSeconds: Double = 2.10
    private static let openingHeroKenBurnsFactor: CGFloat = 0.09
    private static let openingHeroKenBurnsFPS: Double = 24

    /// Day itinerary card: how long the card is held between crossfades.
    private static let cinematicDayCardHoldSeconds: Double = 2.0
    /// Day itinerary card: crossfade duration in→card and card→map.
    private static let cinematicDayCardCrossfadeSeconds: Double = 0.40
    private static let cinematicDayCardCrossfadeFPS: Double = 30

    /// Total extra seconds added per day when day itinerary cards are enabled.
    private static var cinematicDayCardTotalSeconds: Double {
        cinematicDayCardCrossfadeSeconds + cinematicDayCardHoldSeconds + cinematicDayCardCrossfadeSeconds
    }

    private static var cinematicZoomFrameDurationSeconds: Double {
        1.0 / cinematicZoomSegmentTargetFPS
    }

    /// Number of synthesized dissolve steps after the initial wide frame (at least 12).
    private static var cinematicZoomBlendFrameCount: Int {
        let fromDuration = Int(round(cinematicZoomSegmentDurationSeconds * cinematicZoomSegmentTargetFPS)) - 1
        return max(12, fromDuration)
    }

    private static var cinematicZoomSegmentEmittedSeconds: Double {
        Double(cinematicZoomBlendFrameCount) * cinematicZoomFrameDurationSeconds
    }

    private static var coverToFirstMapCrossfadeSeconds: Double {
        let frames = max(14, Int((coverToMapTransitionSeconds * coverToMapTransitionFPS).rounded()))
        return Double(frames) / coverToMapTransitionFPS
    }

    private static func hasFiniteCoord(_ stop: PlaceStop) -> Bool {
        guard let c = stop.representativeLocation?.clCoordinate else { return false }
        return c.latitude.isFinite && c.longitude.isFinite
    }

    // MARK: - Export duration estimate

    /// Wall-clock timeline matching `buildFrames` pacing (map pan/zoom, dissolves, travel, Ken Burns photo budget).
    /// Omits `BlogVideoExportService`’s final writer pad — add `1/30` s there to match the encoded file.
    ///
    /// Assumes snapshot and photo loads succeed; failed MapKit/photo fetches produce a shorter real export.
    static func estimatedTimelineSecondsForExportConfiguration(
        draft: RecapBlogDetail,
        secondsPerPhoto: Double,
        maxPhotosPerPlace: Int,
        includedPlaceIDs: Set<UUID>? = nil,
        showDayItineraryCards: Bool = false
    ) -> Double {
        let days: [RecapBlogDay] = draft.days.compactMap { day in
            let filteredStops: [PlaceStop]
            if let ids = includedPlaceIDs {
                filteredStops = day.placeStops.filter { ids.contains($0.id) }
            } else {
                filteredStops = day.placeStops
            }
            guard !filteredStops.isEmpty else { return nil }
            var filtered = day
            filtered.placeStops = filteredStops
            return filtered
        }

        var total = 0.0
        total += estimatedOpeningHookSeconds(draft: draft, includedPlaceIDs: includedPlaceIDs)

        if let firstDay = days.first, let firstStop = firstDay.placeStops.first, hasFiniteCoord(firstStop) {
            // Day itinerary cards replace the cover→map crossfade with cover→card→map
            total += showDayItineraryCards ? cinematicDayCardTotalSeconds : coverToFirstMapCrossfadeSeconds
        }

        var handoffSkipsPanAndZoom = false

        for (dayIdx, day) in days.enumerated() {
            let stops = day.placeStops
            for (placeIdx, stop) in stops.enumerated() {
                let skipPanZoom = handoffSkipsPanAndZoom
                handoffSkipsPanAndZoom = false

                let coordOK = hasFiniteCoord(stop)
                if coordOK {
                    if !skipPanZoom {
                        total += Double(cinematicPanFrameCount) * cinematicPanFrameDurationSeconds
                        total += cinematicZoomSegmentEmittedSeconds
                    }
                    total += cinematicFocusedMapHoldSeconds
                }

                let photoCount = min(maxPhotosPerPlace, stop.includedPhotos.count)
                if photoCount > 0 {
                    for photoIdx in 0..<photoCount {
                        let photo = stop.includedPhotos[photoIdx]
                        let clipDur = momentVideoDurationSeconds(for: photo)
                        if clipDur > 0 {
                            // Reel replaces the photo: dissolve from previous frame + reel
                            total += mapToReelTransitionSeconds
                            total += clipDur
                        } else {
                            // Regular Ken-Burns photo slide
                            if photoIdx == 0, coordOK {
                                total += mapToFirstPhotoTransitionSeconds
                            }
                            if photoIdx > 0 {
                                total += cinematicPhotoToPhotoDissolveDurationSeconds
                            }
                            total += secondsPerPhoto
                        }
                    }
                }

                let isLastPlaceOverall = (dayIdx == days.count - 1) && (placeIdx == stops.count - 1)
                let isLastPlaceOfDay = placeIdx == stops.count - 1
                let hasEmittedPhotos = photoCount > 0

                guard !isLastPlaceOverall, hasEmittedPhotos else { continue }

                if isLastPlaceOfDay {
                    if dayIdx + 1 < days.count,
                       let nextFirst = days[dayIdx + 1].placeStops.first,
                       hasFiniteCoord(nextFirst) {
                        // Day itinerary cards replace the plain photo→map dissolve with photo→card→map
                        total += showDayItineraryCards ? cinematicDayCardTotalSeconds : lastPhotoToMapFadeSeconds
                    }
                } else {
                    let nextStop = stops[placeIdx + 1]
                    let nextCoordOK = hasFiniteCoord(nextStop)
                    if coordOK, nextCoordOK {
                        let mode = stop.transportModeToNextStop ?? TravelMode.detect(from: stop, to: nextStop)
                        total += mode.animationSeconds
                        total += 0.25 + cinematicZoomSegmentEmittedSeconds
                        handoffSkipsPanAndZoom = true
                    } else if nextCoordOK {
                        total += lastPhotoToMapFadeSeconds
                    }
                }
            }
        }

        return total
    }

    // MARK: - Entry point

    /// Generates frames in order and calls `frameHandler(image, duration)` for each.
    /// The handler is expected to write the frame to video immediately; the image is
    /// released once the handler returns.
    static func buildFrames(
        from draft: RecapBlogDetail,
        logicalSize: CGSize,
        secondsPerPhoto: Double,
        showPhotoCaptions: Bool = true,
        maxPhotosPerPlace: Int = 5,
        includedPlaceIDs: Set<UUID>? = nil,
        showDayItineraryCards: Bool = false,
        progressHandler: ((Double) -> Void)? = nil,
        momentAudioHandler: ((URL, Double, Double) -> Void)? = nil,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws {
        let pixelSize = CGSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
        // Accumulates each stop's coordinate in visit order for the persistent trail overlay.
        var visitedTrailCoords: [CLLocationCoordinate2D] = []
        let days: [RecapBlogDay] = draft.days.compactMap { day in
            let filteredStops: [PlaceStop]
            if let ids = includedPlaceIDs {
                filteredStops = day.placeStops.filter { ids.contains($0.id) }
            } else {
                filteredStops = day.placeStops
            }
            guard !filteredStops.isEmpty else { return nil }
            var filtered = day
            filtered.placeStops = filteredStops
            return filtered
        }
        let totalDays = Double(max(days.count, 1))

        let coverImage = await loadCoverImageForVideo(draft: draft, pixelSize: pixelSize)
        let coverComposite = autoreleasepool {
            drawCoverPage(draft: draft, pixelSize: pixelSize, coverImage: coverImage)
        }
        let postHookFrame = try await emitOpeningHook(
            coverComposite: coverComposite,
            coverImage: coverImage,
            pixelSize: pixelSize,
            frameHandler: frameHandler
        )

        if let firstDay = days.first, !firstDay.placeStops.isEmpty {
            let firstStops = firstDay.placeStops
            if let firstStop = firstStops.first,
               let fc = firstStop.representativeLocation?.clCoordinate,
               fc.latitude.isFinite, fc.longitude.isFinite,
               let mapBase = await MapSnapshotHelper.generateSnapshotAtRegion(
                   region: dayOverviewRegion(for: firstStops),
                   focusedStopIndex: 0,
                   allStops: firstStops,
                   logicalSize: logicalSize,
                   displayScale: exportMapDisplayScale,
                   showPlaceNamePillForFocused: false,
                   showDistancePills: false  // crossfade transition frame — not stable
               ) {
                let firstMapWithHeader = autoreleasepool {
                    drawDayHeaderOverlay(on: mapBase, day: firstDay, dayNumber: 1, pixelSize: pixelSize)
                }
                let firstMapForCrossfade = autoreleasepool {
                    applyingPoweredByBloggoWatermarkIfNeeded(
                        to: firstMapWithHeader, pixelSize: pixelSize, show: true
                    )
                }

                if showDayItineraryCards {
                    // cover → day 1 card → first map (replacing the direct cover→map crossfade)
                    let day1Card = autoreleasepool {
                        drawDayItineraryCard(day: firstDay, dayNumber: 1, pixelSize: pixelSize)
                    }
                    let cardFrames = max(10, Int(round(cinematicDayCardCrossfadeSeconds * cinematicDayCardCrossfadeFPS)))
                    let cardDt = cinematicDayCardCrossfadeSeconds / Double(cardFrames)
                    for fi in 0..<cardFrames {
                        try Task.checkCancellation()
                        let u = easeInOutCubic(CGFloat(fi) / CGFloat(max(cardFrames - 1, 1)))
                        let blended = autoreleasepool {
                            blendCoverToMap(from: postHookFrame, to: day1Card, progress: u, size: pixelSize)
                        }
                        try await frameHandler(blended, cardDt)
                    }
                    try await frameHandler(day1Card, cinematicDayCardHoldSeconds)
                    for fi in 0..<cardFrames {
                        try Task.checkCancellation()
                        let u = easeInOutCubic(CGFloat(fi) / CGFloat(max(cardFrames - 1, 1)))
                        let blended = autoreleasepool {
                            blendCoverToMap(from: day1Card, to: firstMapForCrossfade, progress: u, size: pixelSize)
                        }
                        try await frameHandler(blended, cardDt)
                    }
                } else {
                    let crossDt = 1.0 / coverToMapTransitionFPS
                    let crossFrames = max(14, Int((coverToMapTransitionSeconds * coverToMapTransitionFPS).rounded()))
                    for fi in 1...crossFrames {
                        try Task.checkCancellation()
                        let u = easeInOutCubic(CGFloat(fi) / CGFloat(crossFrames))
                        let blended = autoreleasepool {
                            blendCoverToMap(from: postHookFrame, to: firstMapForCrossfade, progress: u, size: pixelSize)
                        }
                        try await frameHandler(blended, crossDt)
                    }
                }
            }
        }

        // When the travel animation zooms into the next stop, it hands off the tight
        // arrival image here so the next iteration can skip pan + zoom.
        var travelHandoffTightImage: UIImage? = nil

        for (dayIdx, day) in days.enumerated() {
            try Task.checkCancellation()

            let stops = day.placeStops

            let dayOverviewRegion = dayOverviewRegion(for: stops)

            for (placeIdx, stop) in stops.enumerated() {
                try Task.checkCancellation()
                var lastFocusedMapCompositeForPhotoTransition: UIImage?
                var mapToPhotoThumbCell: CGRect?
                var mapToPhotoThumbCorner: CGFloat?
                /// Cinematic export: brand chip only on the first map segment (first day, first stop).
                let isFirstMapSegmentInVideo = (dayIdx == 0 && placeIdx == 0)

                // Consume any tight-image handoff from the previous stop's travel arrival zoom.
                let handoffTight = travelHandoffTightImage
                travelHandoffTightImage = nil

                if let focusedCoord = stop.representativeLocation?.clCoordinate,
                   focusedCoord.latitude.isFinite, focusedCoord.longitude.isFinite {

                    var photoThumbs: [UIImage] = []
                    var lastZoomFrame: UIImage?

                    if let handoffTight {
                        // Travel transition already zoomed into this stop — skip pan + zoom.
                        lastZoomFrame = handoffTight
                        photoThumbs = await loadThumbnailsForPlaceMapOverlay(stop: stop)
                    } else {
                        let neighborhoodSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                        let wideRegion  = MKCoordinateRegion(center: focusedCoord, span: neighborhoodSpan)
                        let tightRegion = MKCoordinateRegion(center: focusedCoord,
                                                             span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))

                        let previousIdx = placeIdx - 1
                        let previousHasMapPin: Bool = {
                            guard placeIdx > 0,
                                  let loc = stops[previousIdx].representativeLocation else { return false }
                            let c = loc.clCoordinate
                            return c.latitude.isFinite && c.longitude.isFinite
                        }()
                        /// First stop of the day: pan from full-day overview into neighborhood. Later stops: stay at
                        /// neighborhood zoom and pan from the previous marker’s frame so export does not zoom out again.
                        let panFromRegion: MKCoordinateRegion = {
                            guard placeIdx > 0, previousHasMapPin,
                                  let prevCoord = stops[previousIdx].representativeLocation?.clCoordinate,
                                  prevCoord.latitude.isFinite, prevCoord.longitude.isFinite else {
                                return dayOverviewRegion
                            }
                            return MKCoordinateRegion(center: prevCoord, span: neighborhoodSpan)
                        }()

                        // Pre-fetch zoom snapshots and thumbnails concurrently with the pan.
                        // The pan takes ~1.5 s (14 real MapKit calls); starting these here means they
                        // will be ready (or near-ready) the moment the zoom loop finishes, so no
                        // stall freezes the last zoom frame before the overlay reveal begins.
                        async let wideSnapFetch = MapSnapshotHelper.generateSnapshotAtRegion(
                            region: wideRegion,
                            focusedStopIndex: placeIdx,
                            allStops: stops,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: false,
                            showFocusedMarker: false,
                            showDistancePills: false  // crop-scaled during zoom animation — pills must not be baked in
                        )
                        async let tightSnapFetch = MapSnapshotHelper.generateSnapshotAtRegion(
                            region: tightRegion,
                            focusedStopIndex: placeIdx,
                            allStops: stops,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: true,
                            showDistancePills: false  // tight view (0.003°) — adjacent stops are out of frame
                        )
                        async let photoThumbsFetch = loadThumbnailsForPlaceMapOverlay(stop: stop)

                        // 1. Pan: day-wide (first stop only) or neighborhood → neighborhood around the focus.
                        let panDt = cinematicPanFrameDurationSeconds
                        let handoffEnd = cinematicPanHandoffPreviousHighlightFrames + cinematicPanHandoffAllMutedFrames
                        try await MapSnapshotHelper.forEachInterpolatedFrame(
                            from: panFromRegion, to: wideRegion,
                            allStops: stops,
                            focusedStopIndexForFrame: { frameIdx in
                                if placeIdx == 0 { return 0 }
                                guard previousHasMapPin else { return placeIdx }
                                if frameIdx < cinematicPanHandoffPreviousHighlightFrames { return previousIdx }
                                if frameIdx < handoffEnd { return nil }
                                return placeIdx
                            },
                            showPlaceNamePillForFrame: { frameIdx in
                                guard frameIdx >= handoffEnd else { return false }
                                if placeIdx == 0 { return true }
                                return previousHasMapPin
                            },
                            logicalSize: logicalSize, displayScale: exportMapDisplayScale,
                            frameCount: cinematicPanFrameCount, inclusiveEndpoints: true,
                            showDistancePills: false  // pan frames change zoom level — pills would scale with the map
                        ) { img in
                            let out = autoreleasepool {
                                let withHeader = mapSnapshotWithFirstPlaceDayHeaderIfNeeded(
                                    placeIdx: placeIdx, mapImage: img, day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize
                                )
                                return applyingPoweredByBloggoWatermarkIfNeeded(
                                    to: withHeader, pixelSize: pixelSize, show: isFirstMapSegmentInVideo
                                )
                            }
                            try await frameHandler(out, panDt)
                        }

                        let zoomDt = cinematicZoomFrameDurationSeconds

                        // 2. Zoom-in to POI — await pre-fetched snapshots (ran concurrently with pan).
                        let wideSnap = await wideSnapFetch
                        let tightSnap = await tightSnapFetch
                        photoThumbs = await photoThumbsFetch
                        if let wideSnap, let tightSnap {
                            lastZoomFrame = tightSnap
                            let blendCount = cinematicZoomBlendFrameCount
                            let zoomRatio = CGFloat(wideRegion.span.latitudeDelta / tightRegion.span.latitudeDelta)
                            // Fixed-size overlay (circle halo + colored pin + name pill) composited over the
                            // zoom frames at a constant size — not crop-scaled with the map tiles.
                            let focusedOverlay = MapSnapshotHelper.generateFocusedMarkerOverlay(
                                displayNumber: placeIdx + 1,
                                totalCount: stops.count,
                                title: stop.placeTitle,
                                logicalSize: logicalSize,
                                displayScale: exportMapDisplayScale
                            )
                            for fi in 0..<blendCount {
                                try Task.checkCancellation()
                                let rawT = blendCount > 1 ? CGFloat(fi) / CGFloat(blendCount - 1) : 1
                                let blended = autoreleasepool {
                                    drawZoomBlendFrame(
                                        wideImage: wideSnap, tightImage: tightSnap,
                                        overlayImage: focusedOverlay,
                                        progress: rawT,
                                        zoomRatio: zoomRatio,
                                        size: pixelSize
                                    )
                                }
                                let out = autoreleasepool {
                                    let withHeader = mapSnapshotWithFirstPlaceDayHeaderIfNeeded(
                                        placeIdx: placeIdx, mapImage: blended, day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize
                                    )
                                    return applyingPoweredByBloggoWatermarkIfNeeded(
                                        to: withHeader, pixelSize: pixelSize, show: isFirstMapSegmentInVideo
                                    )
                                }
                                try await frameHandler(out, zoomDt)
                            }
                        }
                    } // end of handoff vs. normal branch

                    if let tightMap = lastZoomFrame {
                        let mapForPlaceOverlay = autoreleasepool {
                            mapSnapshotWithFirstPlaceDayHeaderIfNeeded(
                                placeIdx: placeIdx, mapImage: tightMap, day: day, dayNumber: dayIdx + 1, pixelSize: pixelSize
                            )
                        }
                        let overlaid = try await emitFocusedPlaceOverlayReveal(
                            mapImageWithHeader: mapForPlaceOverlay,
                            stop: stop,
                            focusedPlaceIndex: placeIdx,
                            allStops: stops,
                            pixelSize: pixelSize,
                            photoThumbnails: photoThumbs,
                            isFirstMapSegmentInVideo: isFirstMapSegmentInVideo,
                            frameHandler: frameHandler
                        )
                        lastFocusedMapCompositeForPhotoTransition = overlaid
                        if let thumb = firstThumbnailCellOnFocusedPlaceMap(
                            pixelSize: pixelSize, stop: stop, photoThumbnails: photoThumbs
                        ) {
                            mapToPhotoThumbCell = thumb.rect
                            mapToPhotoThumbCorner = thumb.cornerRadius
                        }
                    }

                    // Record this stop so the persistent trail grows with each visit.
                    if let c = stop.representativeLocation?.clCoordinate,
                       c.latitude.isFinite, c.longitude.isFinite {
                        visitedTrailCoords.append(c)
                    }

                    let stopCount = Double(max(stops.count, 1))
                    progressHandler?((Double(dayIdx) + Double(placeIdx + 1) / stopCount) / totalDays)
                }

                // 4. Photo/reel slides — if a photo has a reel, the reel plays directly with
                //    place/time overlay (no still shown); otherwise a Ken-Burns still is shown.
                var lastPhotoSlide: UIImage?
                var lastPhotoKBLastFrame: UIImage?
                for (photoIdx, photo) in stop.includedPhotos.prefix(maxPhotosPerPlace).enumerated() {
                    try Task.checkCancellation()
                    let timeLabel = photoSlideTimeDisplayText(for: photo, stop: stop)

                    if let clipURL = momentVideoURL(for: photo) {
                        // Reel found: show it directly with place/time overlay, dissolving from the
                        // previous frame (focused map for the first photo, last KB frame otherwise).
                        let dissolveFrom: UIImage? = lastPhotoKBLastFrame ?? lastFocusedMapCompositeForPhotoTransition
                        if let clipLast = try await emitMomentVideoClipWithPlaceOverlay(
                            url: clipURL,
                            pixelSize: pixelSize,
                            dissolveFrom: dissolveFrom,
                            placeName: stop.placeTitle,
                            timestampText: timeLabel,
                            momentAudioHandler: momentAudioHandler,
                            frameHandler: frameHandler
                        ) {
                            lastPhotoKBLastFrame = clipLast
                            lastPhotoSlide = clipLast
                        }
                        continue
                    }

                    if let img = await loadPhoto(photo, targetSize: pixelSize) {
                        // First photo: hero zoom from the focused-map thumbnail cell.
                        if photoIdx == 0,
                           let mapComposite = lastFocusedMapCompositeForPhotoTransition,
                           let fromCell = mapToPhotoThumbCell,
                           let fromCorner = mapToPhotoThumbCorner {
                            let toRect = photoAspectFillDrawRect(for: img, pixelSize: pixelSize)
                            let nFrames = max(
                                14,
                                Int(round(mapToFirstPhotoTransitionSeconds * mapToFirstPhotoTransitionFPS))
                            )
                            let transitionDt = mapToFirstPhotoTransitionSeconds / Double(nFrames)
                            let denom = max(nFrames - 1, 1)
                            for fi in 0..<nFrames {
                                try Task.checkCancellation()
                                let rawT = CGFloat(fi) / CGFloat(denom)
                                let eased = easeInOutCubic(rawT)
                                let frame = autoreleasepool {
                                    drawMapToFirstPhotoTransitionFrame(
                                        lastMapComposite: mapComposite,
                                        photo: img,
                                        progress: eased,
                                        fromCell: fromCell,
                                        fromCornerRadius: fromCorner,
                                        toPhotoRect: toRect,
                                        pixelSize: pixelSize
                                    )
                                }
                                try await frameHandler(frame, transitionDt)
                            }
                        }

                        // Ken Burns: even photos zoom in (1.0 → 1+factor), odd zoom out (1+factor → 1.0).
                        let kbZoomsIn = photoIdx % 2 == 0
                        let kbStart: CGFloat = kbZoomsIn ? 1.0 : (1.0 + cinematicPhotoKenBurnsFactor)
                        let kbEnd: CGFloat   = kbZoomsIn ? (1.0 + cinematicPhotoKenBurnsFactor) : 1.0
                        let kbFrameCount = max(8, Int(round(secondsPerPhoto * cinematicPhotoKenBurnsFPS)))
                        let kbDt = secondsPerPhoto / Double(kbFrameCount)

                        let firstKBFrame = autoreleasepool {
                            drawPhotoSlide(
                                img,
                                caption: showPhotoCaptions ? photo.caption : nil,
                                placeName: stop.placeTitle,
                                timestampText: timeLabel,
                                pixelSize: pixelSize,
                                kbScale: kbStart
                            )
                        }

                        // Cross-dissolve from the previous frame (photo or reel last frame).
                        if let prevLast = lastPhotoKBLastFrame {
                            let nD = max(8, Int(round(cinematicPhotoToPhotoDissolveDurationSeconds * cinematicPhotoToPhotoDissolveTargetFPS)))
                            let dDt = cinematicPhotoToPhotoDissolveDurationSeconds / Double(nD)
                            let dDenom = max(nD - 1, 1)
                            for fi in 0..<nD {
                                try Task.checkCancellation()
                                let t = easeInOutCubic(CGFloat(fi) / CGFloat(dDenom))
                                let blended = autoreleasepool {
                                    blendCoverToMap(from: prevLast, to: firstKBFrame, progress: t, size: pixelSize)
                                }
                                try await frameHandler(blended, dDt)
                            }
                        }

                        var kbLastFrame = firstKBFrame
                        for fi in 0..<kbFrameCount {
                            try Task.checkCancellation()
                            let t = kbFrameCount > 1 ? CGFloat(fi) / CGFloat(kbFrameCount - 1) : 0
                            let kbScale = kbStart + (kbEnd - kbStart) * t
                            let frame = autoreleasepool {
                                drawPhotoSlide(
                                    img,
                                    caption: showPhotoCaptions ? photo.caption : nil,
                                    placeName: stop.placeTitle,
                                    timestampText: timeLabel,
                                    pixelSize: pixelSize,
                                    kbScale: kbScale
                                )
                            }
                            kbLastFrame = frame
                            try await frameHandler(frame, kbDt)
                        }
                        lastPhotoKBLastFrame = kbLastFrame
                        lastPhotoSlide = kbLastFrame
                    }
                }

                // Transition to next stop: travel animation (path reveal + vehicle icon) for
                // same-day moves; simple cross-dissolve to the next day's overview for day changes.
                let isLastPlaceOverall = (dayIdx == days.count - 1) && (placeIdx == stops.count - 1)
                let isLastPlaceOfDay   = placeIdx == stops.count - 1

                if !isLastPlaceOverall, let lastSlide = lastPhotoSlide {
                    if isLastPlaceOfDay {
                        // Cross-day transition: dissolve from the last photo into the next day's
                        // overview (or via an itinerary card when enabled); the next iteration
                        // starts its normal pan+zoom from that overview.
                        let nextDayStops = days[dayIdx + 1].placeStops
                        let nextDay = days[dayIdx + 1]
                        let nextDayOverview = Self.dayOverviewRegion(for: nextDayStops)
                        if let nextMapBase = await MapSnapshotHelper.generateSnapshotAtRegion(
                            region: nextDayOverview,
                            focusedStopIndex: 0,
                            allStops: nextDayStops,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: false,
                            showDistancePills: false
                        ) {
                            let nextMapOut = autoreleasepool {
                                applyingPoweredByBloggoWatermarkIfNeeded(to: nextMapBase, pixelSize: pixelSize, show: false)
                            }
                            if showDayItineraryCards {
                                // lastPhoto → nextDayCard → nextMap
                                let nextDayCard = autoreleasepool {
                                    drawDayItineraryCard(day: nextDay, dayNumber: dayIdx + 2, pixelSize: pixelSize)
                                }
                                let cf = max(10, Int(round(cinematicDayCardCrossfadeSeconds * cinematicDayCardCrossfadeFPS)))
                                let cdt = cinematicDayCardCrossfadeSeconds / Double(cf)
                                for fi in 0..<cf {
                                    try Task.checkCancellation()
                                    let u = easeInOutCubic(CGFloat(fi) / CGFloat(max(cf - 1, 1)))
                                    let blended = autoreleasepool {
                                        blendCoverToMap(from: lastSlide, to: nextDayCard, progress: u, size: pixelSize)
                                    }
                                    try await frameHandler(blended, cdt)
                                }
                                try await frameHandler(nextDayCard, cinematicDayCardHoldSeconds)
                                for fi in 0..<cf {
                                    try Task.checkCancellation()
                                    let u = easeInOutCubic(CGFloat(fi) / CGFloat(max(cf - 1, 1)))
                                    let blended = autoreleasepool {
                                        blendCoverToMap(from: nextDayCard, to: nextMapOut, progress: u, size: pixelSize)
                                    }
                                    try await frameHandler(blended, cdt)
                                }
                            } else {
                                let nFadeFrames = max(14, Int(round(lastPhotoToMapFadeSeconds * lastPhotoToMapFadeFPS)))
                                let fadeDt = lastPhotoToMapFadeSeconds / Double(nFadeFrames)
                                let denom = max(nFadeFrames - 1, 1)
                                for fi in 0..<nFadeFrames {
                                    try Task.checkCancellation()
                                    let eased = easeInOutCubic(CGFloat(fi) / CGFloat(denom))
                                    let blended = autoreleasepool {
                                        blendCoverToMap(from: lastSlide, to: nextMapOut, progress: eased, size: pixelSize)
                                    }
                                    try await frameHandler(blended, fadeDt)
                                }
                            }
                        }
                        // travelHandoffTightImage stays nil → next day starts with its normal pan+zoom.
                    } else {
                    // Resolve the same-day next stop.
                    let nextStop: PlaceStop = stops[placeIdx + 1]
                    let transitionFromImage: UIImage = lastSlide

                    // Pre-fetch BOTH wide (0.008°) and tight (0.003°) arrival snapshots concurrently
                    // with the travel animation (~2 s), so both are ready for the two-stage zoom.
                    let nextAllStops: [PlaceStop] = stops
                    let nextFocusIdx: Int         = placeIdx + 1
                    let arrivalWideTask = Task<UIImage?, Never> {
                        guard let coord = nextStop.representativeLocation?.clCoordinate,
                              coord.latitude.isFinite, coord.longitude.isFinite else { return nil }
                        let region = MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                        )
                        return await MapSnapshotHelper.generateSnapshotAtRegion(
                            region: region,
                            focusedStopIndex: nextFocusIdx,
                            allStops: nextAllStops,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: false,
                            showFocusedMarker: false,
                            showDistancePills: false
                        )
                    }
                    let arrivalTightTask = Task<UIImage?, Never> {
                        guard let coord = nextStop.representativeLocation?.clCoordinate,
                              coord.latitude.isFinite, coord.longitude.isFinite else { return nil }
                        let region = MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                        )
                        return await MapSnapshotHelper.generateSnapshotAtRegion(
                            region: region,
                            focusedStopIndex: nextFocusIdx,
                            allStops: nextAllStops,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale,
                            showPlaceNamePillForFocused: true,
                            showDistancePills: false
                        )
                    }

                    // Travel animation: path reveal + vehicle icon.
                    let travelLast = try await CinematicTravelSegment.emitTravelTransitionFrames(
                        fromImage: transitionFromImage,
                        fromStop: stop,
                        toStop: nextStop,
                        visitedTrailCoords: visitedTrailCoords,
                        modeOverride: stop.transportModeToNextStop,
                        logicalSize: logicalSize,
                        pixelSize: pixelSize,
                        displayScale: exportMapDisplayScale,
                        frameHandler: frameHandler
                    )

                    // Arrival zoom: two-stage transition that mirrors the normal stop zoom animation.
                    // Stage 1 — short dissolve from travel map → wide neighborhood (~0.25 s):
                    //   bridges the spatial gap (travel map centers the full route, not just the destination).
                    // Stage 2 — drawZoomBlendFrame wide → tight (~1.1 s):
                    //   identical crop-zoom as the normal per-stop zoom, so arrival always looks smooth.
                    if let travelEnd = travelLast,
                       let wideArrival = await arrivalWideTask.value,
                       let tightArrival = await arrivalTightTask.value {

                        // Stage 1: dissolve travel map → wide neighborhood
                        let dissolveFrames = max(5, Int((0.25 * TravelMode.fps).rounded()))
                        let dissolveDt = 0.25 / Double(dissolveFrames)
                        for di in 0..<dissolveFrames {
                            try Task.checkCancellation()
                            let t = CinematicTravelSegment.easeInOutCubic(CGFloat(di + 1) / CGFloat(dissolveFrames))
                            let frame = autoreleasepool {
                                CinematicTravelSegment.blendImages(from: travelEnd, to: wideArrival, progress: t, size: pixelSize)
                            }
                            try await frameHandler(frame, dissolveDt)
                        }

                        // Stage 2: crop-zoom wide → tight (same animation as the normal stop zoom)
                        let arrivalZoomRatio = CGFloat(0.008 / 0.003)
                        let focusedOverlay = MapSnapshotHelper.generateFocusedMarkerOverlay(
                            displayNumber: nextFocusIdx + 1,
                            totalCount: nextAllStops.count,
                            title: nextStop.placeTitle,
                            logicalSize: logicalSize,
                            displayScale: exportMapDisplayScale
                        )
                        let blendCount = cinematicZoomBlendFrameCount
                        let zoomDt = cinematicZoomFrameDurationSeconds
                        for fi in 0..<blendCount {
                            try Task.checkCancellation()
                            let rawT = blendCount > 1 ? CGFloat(fi) / CGFloat(blendCount - 1) : 1
                            let frame = autoreleasepool {
                                drawZoomBlendFrame(
                                    wideImage: wideArrival,
                                    tightImage: tightArrival,
                                    overlayImage: focusedOverlay,
                                    progress: rawT,
                                    zoomRatio: arrivalZoomRatio,
                                    size: pixelSize
                                )
                            }
                            try await frameHandler(frame, zoomDt)
                        }
                        travelHandoffTightImage = tightArrival
                    }

                    // Fallback plain cross-dissolve if travel animation couldn't generate frames
                    // (missing coordinates, MapKit error, etc.).
                    if travelLast == nil {
                        if let coord = stop.representativeLocation?.clCoordinate,
                           coord.latitude.isFinite, coord.longitude.isFinite,
                           let nextMapBase = await MapSnapshotHelper.generateSnapshotAtRegion(
                               region: MKCoordinateRegion(center: coord,
                                                          span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)),
                               focusedStopIndex: nextFocusIdx, allStops: nextAllStops,
                               logicalSize: logicalSize, displayScale: exportMapDisplayScale,
                               showPlaceNamePillForFocused: false, showDistancePills: false) {
                            let nextMapOut = autoreleasepool {
                                applyingPoweredByBloggoWatermarkIfNeeded(to: nextMapBase, pixelSize: pixelSize, show: false)
                            }
                            let nFadeFrames = max(14, Int(round(lastPhotoToMapFadeSeconds * lastPhotoToMapFadeFPS)))
                            let fadeDt = lastPhotoToMapFadeSeconds / Double(nFadeFrames)
                            let denom = max(nFadeFrames - 1, 1)
                            for fi in 0..<nFadeFrames {
                                try Task.checkCancellation()
                                let eased = easeInOutCubic(CGFloat(fi) / CGFloat(denom))
                                let blended = autoreleasepool {
                                    blendCoverToMap(from: lastSlide, to: nextMapOut, progress: eased, size: pixelSize)
                                }
                                try await frameHandler(blended, fadeDt)
                            }
                        }
                    }
                    } // end same-day else branch
                }
            }

            progressHandler?(Double(dayIdx + 1) / totalDays)
        }
    }

    // MARK: - Opening hook

    private static func estimatedOpeningHookSeconds(
        draft: RecapBlogDetail,
        includedPlaceIDs: Set<UUID>?
    ) -> Double {
        var total = openingCoverHoldSeconds
        let hasCoverPhoto = (draft.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)).map { !$0.isEmpty } ?? false
        if hasCoverPhoto {
            total += openingCoverToHeroDissolveSeconds + openingHeroKenBurnsSeconds
        }
        return total
    }

    /// Cover title card → hero still (Ken Burns) → returns last frame for map handoff.
    private static func emitOpeningHook(
        coverComposite: UIImage,
        coverImage: UIImage?,
        pixelSize: CGSize,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws -> UIImage {
        try await frameHandler(coverComposite, openingCoverHoldSeconds)
        var lastFrame = coverComposite

        guard let hero = coverImage else { return lastFrame }

        let heroBase = autoreleasepool { drawHookHeroSlide(hero, pixelSize: pixelSize) }

        let dissolveFrames = max(
            10,
            Int(round(openingCoverToHeroDissolveSeconds * openingCoverToHeroDissolveFPS))
        )
        let dissolveDt = openingCoverToHeroDissolveSeconds / Double(dissolveFrames)
        let dissolveDenom = max(dissolveFrames - 1, 1)
        for fi in 0..<dissolveFrames {
            try Task.checkCancellation()
            let t = easeInOutCubic(CGFloat(fi) / CGFloat(dissolveDenom))
            let blended = autoreleasepool {
                blendCoverToMap(from: lastFrame, to: heroBase, progress: t, size: pixelSize)
            }
            try await frameHandler(blended, dissolveDt)
        }
        lastFrame = heroBase

        let kbFrameCount = max(10, Int(round(openingHeroKenBurnsSeconds * openingHeroKenBurnsFPS)))
        let kbDt = openingHeroKenBurnsSeconds / Double(kbFrameCount)
        let kbDenom = max(kbFrameCount - 1, 1)
        let kbStart: CGFloat = 1.0
        let kbEnd: CGFloat = 1.0 + openingHeroKenBurnsFactor
        for fi in 0..<kbFrameCount {
            try Task.checkCancellation()
            let t = CGFloat(fi) / CGFloat(kbDenom)
            let kbScale = kbStart + (kbEnd - kbStart) * t
            let frame = autoreleasepool { drawHookHeroSlide(hero, pixelSize: pixelSize, kbScale: kbScale) }
            lastFrame = frame
            try await frameHandler(frame, kbDt)
        }

        return lastFrame
    }

    /// Full-bleed hook still — no story chrome so the reel punch reads instantly.
    private static func drawHookHeroSlide(
        _ photo: UIImage,
        pixelSize: CGSize,
        kbScale: CGFloat = 1.0
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: pixelSize))

            let photoAR = photo.size.width / max(photo.size.height, 1)
            let frameAR = w / h
            let baseRect: CGRect
            if photoAR > frameAR {
                let dh = h
                let dw = dh * photoAR
                baseRect = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
            } else {
                let dw = w
                let dh = dw / photoAR
                baseRect = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
            }
            let kbW = baseRect.width * kbScale, kbH = baseRect.height * kbScale
            let photoRect = integralRect(CGRect(
                x: baseRect.midX - kbW / 2, y: baseRect.midY - kbH / 2,
                width: kbW, height: kbH
            ))
            prepareContextForSharpBitmapCompositing(cg)
            photo.draw(in: photoRect)

            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.35).cgColor
                ] as CFArray, locations: [0.55, 1])!,
                start: CGPoint(x: 0, y: h * 0.55), end: CGPoint(x: 0, y: h), options: []
            )
        }
    }

    // MARK: - Cover page

    private static func loadCoverImageForVideo(draft: RecapBlogDetail, pixelSize: CGSize) async -> UIImage? {
        guard let lid = draft.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lid.isEmpty else { return nil }
        let dummy = RecapPhoto(timestamp: Date(), imageName: "cover", localIdentifier: lid)
        return await loadPhoto(dummy, targetSize: pixelSize)
    }

    private static func videoCoverDateRangeString(from days: [RecapBlogDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.monthDayStringForStoryBookRange()) – \(last.monthDayStringForStoryBookRange())\(last.yearSuffixForStoryBookRange())"
    }

    private static func drawCoverPage(
        draft: RecapBlogDetail, pixelSize: CGSize, coverImage: UIImage?
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            if let photo = coverImage {
                let photoAR = photo.size.width / max(photo.size.height, 1)
                let frameAR = w / h
                let drawRect: CGRect
                if photoAR > frameAR {
                    let dh = h, dw = dh * photoAR
                    drawRect = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
                } else {
                    let dw = w, dh = dw / photoAR
                    drawRect = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
                }
                let photoRect = integralRect(drawRect)
                prepareContextForSharpBitmapCompositing(cg)
                photo.draw(in: photoRect)

                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.black.withAlphaComponent(0.58).cgColor, UIColor.clear.cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h * 0.24), options: []
                )
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.78).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: CGPoint(x: 0, y: h * 0.48), end: CGPoint(x: 0, y: h), options: []
                )
                // Extra lift for centered type on bright cover photos
                cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
                cg.fill(CGRect(origin: .zero, size: pixelSize))
            } else {
                cg.drawLinearGradient(
                    CGGradient(colorsSpace: cs, colors: [
                        UIColor(red: 5/255, green: 10/255, blue: 48/255, alpha: 1).cgColor,
                        UIColor(red: 2/255, green: 5/255, blue: 30/255, alpha: 1).cgColor
                    ] as CFArray, locations: [0, 1])!,
                    start: .zero, end: CGPoint(x: 0, y: h), options: []
                )
            }

            let iceBlue = UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.70)
            let labelFont = UIFont.monospacedSystemFont(ofSize: (w * 0.028).rounded(), weight: .medium)
            let labelStr = "Recap" as NSString
            let labelAttribs: [NSAttributedString.Key: Any] = [
                .font: labelFont, .foregroundColor: iceBlue, .kern: w * 0.006
            ]
            let labelSize = labelStr.size(withAttributes: labelAttribs)

            let titleFont = UIFont.systemFont(ofSize: (w * 0.062).rounded(), weight: .black)
            let titlePara = NSMutableParagraphStyle()
            titlePara.alignment = .center
            let titleAttribs: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: titlePara
            ]
            let titleStr = draft.title as NSString
            let titleMaxW = w - 100
            let titleMeasured = titleStr.boundingRect(
                with: CGSize(width: titleMaxW, height: h * 0.45),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttribs, context: nil
            ).integral.size

            let dateFont = UIFont.systemFont(ofSize: (w * 0.036).rounded(), weight: .medium)
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont, .foregroundColor: UIColor.white.withAlphaComponent(0.75)
            ]
            let dateStr = videoCoverDateRangeString(from: draft.days) as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let momentsCount = draft.days.filter { !$0.placeStops.isEmpty }.flatMap(\.placeStops).count
            let daysCount = draft.days.count
            let photosCount = draft.allIncludedPhotos.count
            let numFont = UIFont.systemFont(ofSize: (w * 0.034).rounded(), weight: .semibold)
            let capFont = UIFont.systemFont(ofSize: (w * 0.026).rounded(), weight: .regular)
            let sepColor = UIColor.white.withAlphaComponent(0.20)

            let momentsNum = "\(momentsCount)" as NSString
            let momentsCap = "Moments" as NSString
            let daysNum = "\(daysCount)" as NSString
            let daysCap = (daysCount == 1 ? "Day" : "Days") as NSString
            let photosNum = "\(photosCount)" as NSString
            let photosCap = "Photos" as NSString
            let mNumSize = momentsNum.size(withAttributes: [.font: numFont])
            let mCapSize = momentsCap.size(withAttributes: [.font: capFont])
            let dNumSize = daysNum.size(withAttributes: [.font: numFont])
            let dCapSize = daysCap.size(withAttributes: [.font: capFont])
            let pNumSize = photosNum.size(withAttributes: [.font: numFont])
            let pCapSize = photosCap.size(withAttributes: [.font: capFont])
            // Left → right: Days | Moments | Photos (Moments centered between the other two).
            let col1W = max(dNumSize.width, dCapSize.width)
            let col2W = max(mNumSize.width, mCapSize.width)
            let col3W = max(pNumSize.width, pCapSize.width)
            let statsGap: CGFloat = 14
            let sepW: CGFloat = 1
            let statsRowW = col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW + statsGap + col3W
            let statsRowH = max(
                mNumSize.height + 2 + mCapSize.height,
                dNumSize.height + 2 + dCapSize.height,
                pNumSize.height + 2 + pCapSize.height
            )

            let dividerW: CGFloat = min(200, w * 0.22)
            let dividerMargin: CGFloat = 8
            let lineGap: CGFloat = 10
            let stackH = labelSize.height + lineGap + titleMeasured.height + dividerMargin + 1.5 + dividerMargin
                + lineGap + dateSize.height + lineGap + statsRowH
            var y = (h - stackH) / 2

            labelStr.draw(
                at: CGPoint(x: ((w - labelSize.width) / 2).rounded(), y: y.rounded()),
                withAttributes: labelAttribs
            )
            y += labelSize.height + lineGap
            titleStr.draw(
                with: CGRect(x: 40, y: y, width: titleMaxW, height: titleMeasured.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttribs, context: nil
            )
            y += titleMeasured.height + dividerMargin
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.42).cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: (w - dividerW) / 2, y: y))
            cg.addLine(to: CGPoint(x: (w + dividerW) / 2, y: y))
            cg.strokePath()
            y += 1.5 + dividerMargin + lineGap
            dateStr.draw(at: CGPoint(x: (w - dateSize.width) / 2, y: y), withAttributes: dateAttribs)
            y += dateSize.height + lineGap

            let statsX = (w - statsRowW) / 2
            let col1CenterX = statsX + col1W / 2
            let col2CenterX = statsX + col1W + statsGap + sepW + statsGap + col2W / 2
            let col3CenterX = statsX + col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW + statsGap + col3W / 2
            daysNum.draw(
                at: CGPoint(x: col1CenterX - dNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            daysCap.draw(
                at: CGPoint(x: col1CenterX - dCapSize.width / 2, y: y + dNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            momentsNum.draw(
                at: CGPoint(x: col2CenterX - mNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            momentsCap.draw(
                at: CGPoint(x: col2CenterX - mCapSize.width / 2, y: y + mNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            photosNum.draw(
                at: CGPoint(x: col3CenterX - pNumSize.width / 2, y: y),
                withAttributes: [.font: numFont, .foregroundColor: UIColor.white]
            )
            photosCap.draw(
                at: CGPoint(x: col3CenterX - pCapSize.width / 2, y: y + pNumSize.height + 2),
                withAttributes: [.font: capFont, .foregroundColor: UIColor.white]
            )
            cg.setStrokeColor(sepColor.cgColor)
            cg.setLineWidth(1)
            let sep1X = statsX + col1W + statsGap + sepW / 2
            cg.move(to: CGPoint(x: sep1X, y: y))
            cg.addLine(to: CGPoint(x: sep1X, y: y + statsRowH))
            cg.strokePath()
            let sep2X = statsX + col1W + statsGap + sepW + statsGap + col2W + statsGap + sepW / 2
            cg.move(to: CGPoint(x: sep2X, y: y))
            cg.addLine(to: CGPoint(x: sep2X, y: y + statsRowH))
            cg.strokePath()
        }
    }

    // MARK: - Day Header Overlay on Map

    /// First stop of each day (`placeIdx == 0`): keep Day / date / city readable for the whole pan + zoom;
    /// later stops use tighter pans without this block.
    private static func mapSnapshotWithFirstPlaceDayHeaderIfNeeded(
        placeIdx: Int,
        mapImage: UIImage,
        day: RecapBlogDay,
        dayNumber: Int,
        pixelSize: CGSize
    ) -> UIImage {
        guard placeIdx == 0 else { return mapImage }
        return drawDayHeaderOverlay(on: mapImage, day: day, dayNumber: dayNumber, pixelSize: pixelSize)
    }

    /// Top-trailing “Powered by Bloggo” chip on **only** the first map segment of a cinematic export.
    private static func applyingPoweredByBloggoWatermarkIfNeeded(
        to mapImage: UIImage,
        pixelSize: CGSize,
        show: Bool
    ) -> UIImage {
        guard show else { return mapImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            prepareContextForSharpBitmapCompositing(cg)
            mapImage.draw(in: CGRect(origin: .zero, size: pixelSize))
            drawPoweredByBloggoWatermark(in: cg, pixelSize: pixelSize)
        }
    }

    private static func drawPoweredByBloggoWatermark(in cg: CGContext, pixelSize: CGSize) {
        let w = pixelSize.width, h = pixelSize.height
        let margin = max(32, w * 0.038)

        let poweredFont = UIFont.systemFont(ofSize: (w * 0.026).rounded(), weight: .medium)
        let bloggoFont = UIFont.systemFont(ofSize: (w * 0.026).rounded(), weight: .bold)
        let poweredStr = "Powered by " as NSString
        let bloggoStr = "Bloggo" as NSString
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let poweredAttrs: [NSAttributedString.Key: Any] = [
            .font: poweredFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.78),
            .shadow: shadow
        ]
        let bloggoAttrs: [NSAttributedString.Key: Any] = [
            .font: bloggoFont,
            .foregroundColor: UIColor.white,
            .shadow: shadow
        ]
        let poweredSize = poweredStr.size(withAttributes: poweredAttrs)
        let bloggoSize = bloggoStr.size(withAttributes: bloggoAttrs)
        let textRowH = max(poweredSize.height, bloggoSize.height)

        let iconSide = min(56, w * 0.056)
        let appMark = UIImage(named: "AppIconMark")
        let iconGap: CGFloat = appMark != nil ? w * 0.018 : 0
        let iconBlockW: CGFloat = appMark != nil ? iconSide : 0

        let chipPadH = max(14, w * 0.022)
        let chipPadV = max(10, w * 0.016)
        let innerTextW = poweredSize.width + bloggoSize.width
        let chipW = chipPadH * 2 + iconBlockW + iconGap + innerTextW
        let chipH = chipPadV * 2 + max(iconSide, textRowH)
        let chipRect = CGRect(
            x: w - margin - chipW,
            y: h - margin - chipH,
            width: chipW,
            height: chipH
        )

        let chipPath = UIBezierPath(roundedRect: chipRect, cornerRadius: w * 0.028)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.black.withAlphaComponent(0.52).setFill()
        chipPath.fill()
        cg.restoreGState()
        UIColor.white.withAlphaComponent(0.38).setStroke()
        chipPath.lineWidth = 1
        chipPath.stroke()

        var textX = chipRect.minX + chipPadH + iconBlockW + iconGap
        let textY = chipRect.midY - textRowH / 2
        if let appMark {
            let iconRect = CGRect(
                x: chipRect.minX + chipPadH,
                y: chipRect.midY - iconSide / 2,
                width: iconSide,
                height: iconSide
            )
            cg.saveGState()
            UIBezierPath(roundedRect: iconRect, cornerRadius: iconSide * 0.22).addClip()
            prepareContextForSharpBitmapCompositing(cg)
            appMark.draw(in: iconRect)
            cg.restoreGState()
        }
        poweredStr.draw(at: CGPoint(x: textX, y: textY), withAttributes: poweredAttrs)
        textX += poweredSize.width
        bloggoStr.draw(at: CGPoint(x: textX, y: textY), withAttributes: bloggoAttrs)
    }

    private static func drawDayHeaderOverlay(
        on mapImage: UIImage, day: RecapBlogDay, dayNumber: Int, pixelSize: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            prepareContextForSharpBitmapCompositing(cg)
            mapImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            // Top scrim so the day header stays readable on light MapKit tiles; slightly stronger than
            // in-app preview so export stays legible on busy roads / POI labels.
            let scrimBottom = h * 0.34
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.58).cgColor,
                    UIColor.black.withAlphaComponent(0.22).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray, locations: [0, 0.52, 1])!,
                start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: scrimBottom), options: []
            )

            // Generous leading inset: plate extends left of `padX` by `plateInsetL`, and hosts (Reels, etc.)
            // often crop 9:16 slightly — keep “DAY n” and the plate inside the safe visual area.
            let padX = max(84, w * 0.095).rounded()
            // Extra ~50pt downward shift so preview chrome (e.g. Instagram) clears the header block.
            let padY = (max(88, h * 0.052) + 50).rounded()
            let lineGap: CGFloat = 5

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.72)
            shadow.shadowBlurRadius = 5
            shadow.shadowOffset = CGSize(width: 0, height: 1.5)

            let dayFont = UIFont.systemFont(ofSize: (w * 0.052).rounded(), weight: .bold)
            let dayAttribs: [NSAttributedString.Key: Any] = [
                .font: dayFont, .foregroundColor: UIColor.white, .shadow: shadow
            ]
            let dayStr = "DAY \(dayNumber)" as NSString
            let daySize = dayStr.size(withAttributes: dayAttribs)

            let dateFont = UIFont.systemFont(ofSize: (w * 0.034).rounded(), weight: .semibold)
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.white,
                .shadow: shadow
            ]
            let dateStr = day.shortDateText as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let subtitle = day.placeStops.first?.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cityFont = UIFont.systemFont(ofSize: (w * 0.030).rounded(), weight: .medium)
            // High-contrast secondary line (pale blue at low alpha washed out on tan/grey map).
            let cityAttribs: [NSAttributedString.Key: Any] = [
                .font: cityFont,
                .foregroundColor: UIColor(white: 1, alpha: 0.92),
                .shadow: shadow
            ]
            let cityStr = subtitle as NSString
            let citySize = subtitle.isEmpty ? .zero : cityStr.size(withAttributes: cityAttribs)

            let plateInsetL: CGFloat = max(14, w * 0.022)
            let plateInsetR: CGFloat = max(18, w * 0.028)
            let plateInsetT: CGFloat = max(10, h * 0.012)
            let plateInsetB: CGFloat = max(12, h * 0.014)
            let blockW = max(daySize.width, max(dateSize.width, citySize.width))
            let blockH = daySize.height + lineGap + dateSize.height
                + (subtitle.isEmpty ? 0 : lineGap + citySize.height)
            let plateRect = CGRect(
                x: padX - plateInsetL,
                y: padY - plateInsetT,
                width: blockW + plateInsetL + plateInsetR,
                height: blockH + plateInsetT + plateInsetB
            )
            let platePath = UIBezierPath(roundedRect: plateRect, cornerRadius: max(12, w * 0.018))
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 10, color: UIColor.black.withAlphaComponent(0.4).cgColor)
            UIColor.black.withAlphaComponent(0.52).setFill()
            platePath.fill()
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.22).setStroke()
            platePath.lineWidth = max(1, w * 0.002)
            platePath.stroke()

            var y = padY
            dayStr.draw(at: CGPoint(x: padX, y: y), withAttributes: dayAttribs)
            y = (y + daySize.height + lineGap).rounded()
            dateStr.draw(at: CGPoint(x: padX, y: y), withAttributes: dateAttribs)
            y = (y + dateSize.height + lineGap).rounded()
            if !subtitle.isEmpty {
                cityStr.draw(at: CGPoint(x: padX, y: y), withAttributes: cityAttribs)
            }
        }
    }

    // MARK: - Day Itinerary Card

    /// Full-frame dark card shown before each day's map sequence listing all places for that day.
    static func drawDayItineraryCard(day: RecapBlogDay, dayNumber: Int, pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            // Deep navy background
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor(red: 5/255, green: 10/255, blue: 48/255, alpha: 1).cgColor,
                    UIColor(red: 2/255, green: 5/255, blue: 30/255, alpha: 1).cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h), options: []
            )

            let iceBlue = UIColor(red: 200/255, green: 235/255, blue: 255/255, alpha: 0.80)
            let accentBlue = UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0)

            let labelFont = UIFont.monospacedSystemFont(ofSize: (w * 0.028).rounded(), weight: .medium)
            let labelAttribs: [NSAttributedString.Key: Any] = [
                .font: labelFont, .foregroundColor: iceBlue, .kern: w * 0.006
            ]
            let labelStr = "DAY \(dayNumber)" as NSString
            let labelSize = labelStr.size(withAttributes: labelAttribs)

            let numPara = NSMutableParagraphStyle(); numPara.alignment = .center
            let numFont = UIFont.systemFont(ofSize: (w * 0.13).rounded(), weight: .black)
            let numAttribs: [NSAttributedString.Key: Any] = [
                .font: numFont, .foregroundColor: UIColor.white, .paragraphStyle: numPara
            ]
            let numStr = "\(dayNumber)" as NSString
            let numSize = numStr.boundingRect(
                with: CGSize(width: w - 80, height: h * 0.3),
                options: [.usesLineFragmentOrigin], attributes: numAttribs, context: nil
            ).integral.size

            let datePara = NSMutableParagraphStyle(); datePara.alignment = .center
            let dateFont = UIFont.systemFont(ofSize: (w * 0.036).rounded(), weight: .medium)
            let dateAttribs: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .paragraphStyle: datePara
            ]
            let dateStr = day.shortDateText as NSString
            let dateSize = dateStr.size(withAttributes: dateAttribs)

            let blockH = labelSize.height + 4 + numSize.height + 10 + dateSize.height
            let blockTop = ((h / 2) - (blockH / 2) - (h * 0.07)).rounded()
            let centerX = w / 2

            labelStr.draw(
                at: CGPoint(x: (centerX - labelSize.width / 2).rounded(), y: blockTop),
                withAttributes: labelAttribs
            )
            let numY = (blockTop + labelSize.height + 4).rounded()
            numStr.draw(
                in: CGRect(x: (w - numSize.width) / 2, y: numY,
                           width: numSize.width, height: numSize.height),
                withAttributes: numAttribs
            )
            let dateY = (numY + numSize.height + 10).rounded()
            dateStr.draw(
                in: CGRect(x: (w - dateSize.width) / 2, y: dateY,
                           width: dateSize.width, height: dateSize.height),
                withAttributes: dateAttribs
            )

            // Separator
            let sepY = (dateY + dateSize.height + 30).rounded()
            let sepInset = w * 0.18
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(max(1.0, w * 0.0015))
            cg.move(to: CGPoint(x: sepInset, y: sepY))
            cg.addLine(to: CGPoint(x: w - sepInset, y: sepY))
            cg.strokePath()

            // Place list (up to 6 items)
            let maxItems = 6
            let stops = day.placeStops
            let listStops = stops.prefix(maxItems)
            let overflow = max(0, stops.count - maxItems)

            let placeFont = UIFont.systemFont(ofSize: (w * 0.030).rounded(), weight: .semibold)
            let placeAttribs: [NSAttributedString.Key: Any] = [
                .font: placeFont, .foregroundColor: UIColor.white.withAlphaComponent(0.88)
            ]
            let dotAttribs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: (w * 0.020).rounded(), weight: .bold),
                .foregroundColor: accentBlue
            ]
            let dotStr = "•" as NSString
            let dotSize = dotStr.size(withAttributes: dotAttribs)
            let rowH = placeFont.lineHeight
            let rowSpacing: CGFloat = 13
            let listInset = w * 0.22
            var listY = (sepY + 26).rounded()

            for stop in listStops {
                let dotX = (listInset - dotSize.width - 10).rounded()
                dotStr.draw(
                    at: CGPoint(x: dotX, y: (listY + (rowH - dotSize.height) / 2).rounded()),
                    withAttributes: dotAttribs
                )
                let nameStr = stop.placeTitle as NSString
                let maxNameW = w - listInset - sepInset
                nameStr.draw(
                    in: CGRect(x: listInset, y: listY, width: maxNameW, height: rowH + 4),
                    withAttributes: placeAttribs
                )
                listY = (listY + rowH + rowSpacing).rounded()
            }

            if overflow > 0 {
                let moreFont = UIFont.systemFont(ofSize: (w * 0.025).rounded(), weight: .regular)
                let moreAttribs: [NSAttributedString.Key: Any] = [
                    .font: moreFont, .foregroundColor: UIColor.white.withAlphaComponent(0.42)
                ]
                ("+ \(overflow) more" as NSString).draw(
                    at: CGPoint(x: listInset, y: listY),
                    withAttributes: moreAttribs
                )
            }
        }
    }

    // MARK: - Focused Map with Place Info Overlay

    /// Loads images for the in-map thumbnail strip (large enough to stay sharp when tiles are scaled up on export).
    /// At most three tiles are drawn; `stop.includedPhotos.count` supplies the overflow `+N` hint.
    private static func loadThumbnailsForPlaceMapOverlay(stop: PlaceStop, maxCount: Int = 3) async -> [UIImage] {
        let photos = stop.includedPhotos.prefix(maxCount)
        let target = CGSize(width: 1200, height: 1200)
        var images: [UIImage] = []
        images.reserveCapacity(photos.count)
        for photo in photos {
            try? Task.checkCancellation()
            if let img = await loadPhoto(photo, targetSize: target) {
                images.append(img)
            }
        }
        return images
    }

    /// Aspect-fill rect for drawing a bitmap into a square cell.
    private static func mapOverlayAspectFillRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let sw = imageSize.width * scale
        let sh = imageSize.height * scale
        return CGRect(x: bounds.midX - sw / 2, y: bounds.midY - sh / 2, width: sw, height: sh)
    }

    /// One row of thumbnails: at most **three** tiles, generous spacing, `+N` on the dimmed third when this place has more than three photos.
    @discardableResult
    private static func drawMapOverlayThumbnailRow(
        images: [UIImage],
        totalPhotoCount: Int,
        origin: CGPoint,
        rowWidth: CGFloat,
        context: UIGraphicsImageRendererContext
    ) -> CGFloat {
        guard !images.isEmpty, rowWidth > 8 else { return 0 }

        let cg = context.cgContext
        let maxSlots = 3
        let displayCount = min(maxSlots, images.count)
        let overflowPastSlots = max(0, totalPhotoCount - maxSlots)
        let needsTrailingPill = overflowPastSlots > 0 && displayCount < maxSlots

        let spacing: CGFloat = max(12, min(20, rowWidth * 0.028))
        let gapBeforeBadge: CGFloat = needsTrailingPill ? 10 : 0
        let pillW: CGFloat = needsTrailingPill ? min(80, rowWidth * 0.18) : 0
        let availForThumbs = rowWidth - gapBeforeBadge - pillW
        guard availForThumbs > 8 else { return 0 }

        let minSide = max(72, rowWidth * 0.096)
        let maxSide = min(220, rowWidth * 0.28)
        let rawFit = (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount)
        var side = min(maxSide, max(minSide, rawFit))
        let thumbsWidthCheck = CGFloat(displayCount) * side + CGFloat(displayCount - 1) * spacing
        if thumbsWidthCheck > availForThumbs + 0.5 {
            side = max(44, (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount))
        }
        let thumbsWidth = CGFloat(displayCount) * side + CGFloat(displayCount - 1) * spacing

        let cornerR = side * 0.2
        let dimThird = displayCount >= maxSlots && overflowPastSlots > 0

        for i in 0..<displayCount {
            let x = origin.x + CGFloat(i) * (side + spacing)
            let cell = CGRect(x: x, y: origin.y, width: side, height: side)
            let img = images[i]
            cg.saveGState()
            UIBezierPath(roundedRect: cell, cornerRadius: cornerR).addClip()
            img.draw(in: mapOverlayAspectFillRect(imageSize: img.size, bounds: cell))
            cg.restoreGState()

            if dimThird, i == displayCount - 1 {
                UIColor.black.withAlphaComponent(0.42).setFill()
                UIBezierPath(roundedRect: cell, cornerRadius: cornerR).fill()
                let badgeFont = UIFont.systemFont(ofSize: min(22, max(13, side * 0.36)), weight: .bold)
                let str = "+\(overflowPastSlots)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: UIColor.white]
                let sz = str.size(withAttributes: attrs)
                str.draw(
                    at: CGPoint(x: cell.midX - sz.width / 2, y: cell.midY - sz.height / 2),
                    withAttributes: attrs
                )
            }

            UIColor.white.withAlphaComponent(dimThird && i == displayCount - 1 ? 0.65 : 0.45).setStroke()
            let border = UIBezierPath(roundedRect: cell, cornerRadius: cornerR)
            border.lineWidth = max(1, side * 0.04)
            border.stroke()
        }

        if needsTrailingPill {
            let pillFont = UIFont.systemFont(ofSize: min(15, max(11, side * 0.34)), weight: .bold)
            let str = "+\(overflowPastSlots)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: UIColor.white]
            let sz = str.size(withAttributes: attrs)
            let bx = origin.x + thumbsWidth + gapBeforeBadge
            let pillH = min(side, sz.height + 10)
            let pillDrawW = min(max(sz.width + 16, pillH * 1.55), pillW)
            let pill = CGRect(x: bx, y: origin.y + (side - pillH) / 2, width: pillDrawW, height: pillH)
            UIColor.white.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: pillH * 0.35).fill()
            UIColor.white.withAlphaComponent(0.5).setStroke()
            let outline = UIBezierPath(roundedRect: pill, cornerRadius: pillH * 0.35)
            outline.lineWidth = 1
            outline.stroke()
            str.draw(
                at: CGPoint(x: pill.midX - sz.width / 2, y: pill.midY - sz.height / 2),
                withAttributes: attrs
            )
        }

        return side + 6
    }

    private static func drawPlaceOverlayOnMap(
        mapImage: UIImage, stop: PlaceStop, markerNumber: Int, totalStops: Int, pixelSize: CGSize,
        photoThumbnails: [UIImage],
        overlayContentAlpha: CGFloat = 1
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let alpha = min(1, max(0, overlayContentAlpha))
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            prepareContextForSharpBitmapCompositing(cg)
            mapImage.draw(in: CGRect(origin: .zero, size: pixelSize))

            // Fade the entire place chrome (gradient, title, subtitle, time, notes, thumbnail strip) as one unit.
            // A plain `cg.setAlpha` before `UIImage.draw(in:)` does not reliably multiply thumbnail pixels in this
            // renderer path, so photos could appear at full opacity while text/gradient eased in.
            cg.saveGState()
            cg.setAlpha(alpha)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)

            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.92).cgColor,
                    UIColor.black.withAlphaComponent(0.75).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray, locations: [0, 0.45, 1])!,
                start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.38), options: []
            )

            let leadingPad: CGFloat = 72 // inset marker + column from left edge / host crop (was 43)
            let trailingPad: CGFloat = 28
            let markerR: CGFloat = w * 0.052
            let contentY: CGFloat = h * 0.63

            let markerColor: UIColor = markerNumber == 1 ? .systemGreen
                : (markerNumber == totalStops ? .systemOrange : .systemBlue)
            let markerCenter = CGPoint(x: leadingPad + markerR, y: contentY + markerR)
            let markerRect = CGRect(x: markerCenter.x - markerR, y: markerCenter.y - markerR,
                                    width: markerR * 2, height: markerR * 2)
            cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 12,
                         color: markerColor.withAlphaComponent(0.5).cgColor)
            cg.setFillColor(markerColor.cgColor)
            cg.fillEllipse(in: markerRect)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: markerRect)
            let numStr = "\(markerNumber)" as NSString
            let numFont = UIFont.systemFont(ofSize: (markerR * 0.95).rounded(), weight: .bold)
            let numAttribs: [NSAttributedString.Key: Any] = [.font: numFont, .foregroundColor: UIColor.white]
            let numSize = numStr.size(withAttributes: numAttribs)
            numStr.draw(at: CGPoint(x: markerCenter.x - numSize.width / 2,
                                    y: markerCenter.y - numSize.height / 2), withAttributes: numAttribs)

            let titleX = markerCenter.x + markerR + 14
            let titleFont = UIFont.systemFont(ofSize: (w * 0.050).rounded(), weight: .bold)
            let titleAttribs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.white]
            (stop.placeTitle as NSString).draw(
                in: CGRect(x: titleX, y: contentY, width: w - titleX - trailingPad, height: titleFont.lineHeight * 2),
                withAttributes: titleAttribs
            )
            var nextY = contentY + titleFont.lineHeight + 4

            if let sub = stop.placeSubtitle, !sub.isEmpty {
                let subFont = UIFont.systemFont(ofSize: (w * 0.032).rounded(), weight: .regular)
                let subAttribs: [NSAttributedString.Key: Any] = [.font: subFont,
                                                                   .foregroundColor: UIColor.white.withAlphaComponent(0.72)]
                (sub as NSString).draw(at: CGPoint(x: titleX, y: nextY), withAttributes: subAttribs)
                nextY += subFont.lineHeight + 8
            }

            if let ts = formattedTimestamp(stop.visitedTimeDigitized) {
                let tsFont = UIFont.monospacedSystemFont(ofSize: (w * 0.028).rounded(), weight: .medium)
                let tsAttribs: [NSAttributedString.Key: Any] = [.font: tsFont, .foregroundColor: UIColor.white]
                let tsStr = ts as NSString
                let tsSize = tsStr.size(withAttributes: tsAttribs)
                let pH: CGFloat = 10, pV: CGFloat = 5
                let pillRect = CGRect(x: titleX, y: nextY,
                                      width: tsSize.width + pH * 2, height: tsSize.height + pV * 2)
                // Same capsule fill as centered place/timestamp stack (`placePillRect` / `tsPillRect` path).
                UIColor.black.withAlphaComponent(0.52).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2).fill()
                tsStr.draw(at: CGPoint(x: pillRect.minX + pH, y: pillRect.minY + pV), withAttributes: tsAttribs)
                nextY += pillRect.height + 12
            }

            // Place caption / notes — below time stamp, above photo strip (when present).
            let storyText = stop.noteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storyText.isEmpty {
                let storyFont = UIFont.systemFont(ofSize: (w * 0.031).rounded(), weight: .regular)
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 4
                para.lineBreakMode = .byTruncatingTail
                let storyAttribs: [NSAttributedString.Key: Any] = [
                    .font: storyFont,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                    .paragraphStyle: para
                ]
                let maxW = w - titleX - trailingPad
                let maxH = storyFont.lineHeight * 3 + 8
                let fitted = (storyText as NSString).boundingRect(
                    with: CGSize(width: maxW, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs,
                    context: nil
                )
                let drawH = min(ceil(fitted.height), maxH)
                (storyText as NSString).draw(
                    with: CGRect(x: titleX, y: nextY, width: maxW, height: drawH),
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                    attributes: storyAttribs,
                    context: nil
                )
                nextY += drawH + 10
            }

            if !photoThumbnails.isEmpty {
                let rowWidth = w - titleX - trailingPad
                let rowH = drawMapOverlayThumbnailRow(
                    images: photoThumbnails,
                    totalPhotoCount: stop.includedPhotos.count,
                    origin: CGPoint(x: titleX, y: nextY),
                    rowWidth: rowWidth,
                    context: ctx
                )
                nextY += rowH + 8
            }

            cg.endTransparencyLayer()
            cg.restoreGState()
        }
    }

    /// Streams the tight-map + place overlay: chrome fades in, then holds for the remainder of `cinematicFocusedMapHoldSeconds`.
    /// Returns the full-opacity composite for the map → first photo transition.
    private static func emitFocusedPlaceOverlayReveal(
        mapImageWithHeader: UIImage,
        stop: PlaceStop,
        focusedPlaceIndex: Int,
        allStops: [PlaceStop],
        pixelSize: CGSize,
        photoThumbnails: [UIImage],
        isFirstMapSegmentInVideo: Bool,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws -> UIImage {
        let fadeSeconds = min(cinematicPlaceOverlayFadeInSeconds, cinematicFocusedMapHoldSeconds * 0.85)
        let fadeFrames = max(12, Int(round(fadeSeconds * cinematicPlaceOverlayFadeInFPS)))
        let fadeDt = fadeSeconds / Double(fadeFrames)
        let denom = max(fadeFrames - 1, 1)
        var lastEmitted: UIImage?

        for fi in 0..<fadeFrames {
            try Task.checkCancellation()
            let rawT = fadeFrames == 1 ? 1 as CGFloat : CGFloat(fi) / CGFloat(denom)
            let overlayAlpha = easeInOutCubic(rawT)
            let composite = autoreleasepool {
                let base = drawPlaceOverlayOnMap(
                    mapImage: mapImageWithHeader, stop: stop,
                    markerNumber: focusedPlaceIndex + 1, totalStops: allStops.count,
                    pixelSize: pixelSize,
                    photoThumbnails: photoThumbnails,
                    overlayContentAlpha: overlayAlpha
                )
                return applyingPoweredByBloggoWatermarkIfNeeded(
                    to: base, pixelSize: pixelSize, show: isFirstMapSegmentInVideo
                )
            }
            try await frameHandler(composite, fadeDt)
            lastEmitted = composite
        }

        let holdSeconds = cinematicFocusedMapHoldSeconds - fadeSeconds
        if holdSeconds > 0.001, let holdImage = lastEmitted {
            try await frameHandler(holdImage, holdSeconds)
        }

        return autoreleasepool {
            let base = drawPlaceOverlayOnMap(
                mapImage: mapImageWithHeader, stop: stop,
                markerNumber: focusedPlaceIndex + 1, totalStops: allStops.count,
                pixelSize: pixelSize,
                photoThumbnails: photoThumbnails,
                overlayContentAlpha: 1
            )
            return applyingPoweredByBloggoWatermarkIfNeeded(
                to: base, pixelSize: pixelSize, show: isFirstMapSegmentInVideo
            )
        }
    }

    /// First in-map thumbnail cell (export pixel space) for hero transition into the first photo slide.
    private static func firstThumbnailCellOnFocusedPlaceMap(
        pixelSize: CGSize,
        stop: PlaceStop,
        photoThumbnails: [UIImage]
    ) -> (rect: CGRect, cornerRadius: CGFloat)? {
        guard !photoThumbnails.isEmpty else { return nil }
        let w = pixelSize.width, h = pixelSize.height
        let leadingPad: CGFloat = 72 // match `drawPlaceOverlayOnMap`
        let trailingPad: CGFloat = 28
        let markerR: CGFloat = w * 0.052
        let contentY: CGFloat = h * 0.63
        let markerCenter = CGPoint(x: leadingPad + markerR, y: contentY + markerR)
        let titleX = markerCenter.x + markerR + 14
        let titleFont = UIFont.systemFont(ofSize: (w * 0.050).rounded(), weight: .bold)
        var nextY = contentY + titleFont.lineHeight + 4

        if let sub = stop.placeSubtitle, !sub.isEmpty {
            let subFont = UIFont.systemFont(ofSize: (w * 0.032).rounded(), weight: .regular)
            nextY += subFont.lineHeight + 8
        }

        if let ts = formattedTimestamp(stop.visitedTimeDigitized) {
            let tsFont = UIFont.monospacedSystemFont(ofSize: (w * 0.028).rounded(), weight: .medium)
            let tsStr = ts as NSString
            let tsSize = tsStr.size(withAttributes: [.font: tsFont])
            let pV: CGFloat = 5
            let pillH = tsSize.height + pV * 2
            nextY += pillH + 12
        }

        let storyText = stop.noteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storyText.isEmpty {
            let storyFont = UIFont.systemFont(ofSize: (w * 0.031).rounded(), weight: .regular)
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 4
            para.lineBreakMode = .byTruncatingTail
            let storyAttribs: [NSAttributedString.Key: Any] = [
                .font: storyFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                .paragraphStyle: para
            ]
            let maxW = w - titleX - trailingPad
            let maxH = storyFont.lineHeight * 3 + 8
            let fitted = (storyText as NSString).boundingRect(
                with: CGSize(width: maxW, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: storyAttribs,
                context: nil
            )
            let drawH = min(ceil(fitted.height), maxH)
            nextY += drawH + 10
        }

        let rowWidth = w - titleX - trailingPad
        return thumbnailStripFirstCellLayout(
            images: photoThumbnails,
            totalPhotoCount: stop.includedPhotos.count,
            origin: CGPoint(x: titleX, y: nextY),
            rowWidth: rowWidth
        )
    }

    /// Geometry of the first thumbnail tile; mirrors `drawMapOverlayThumbnailRow` without drawing.
    private static func thumbnailStripFirstCellLayout(
        images: [UIImage],
        totalPhotoCount: Int,
        origin: CGPoint,
        rowWidth: CGFloat
    ) -> (rect: CGRect, cornerRadius: CGFloat)? {
        guard !images.isEmpty, rowWidth > 8 else { return nil }

        let maxSlots = 3
        let displayCount = min(maxSlots, images.count)
        let overflowPastSlots = max(0, totalPhotoCount - maxSlots)
        let needsTrailingPill = overflowPastSlots > 0 && displayCount < maxSlots

        let spacing: CGFloat = max(12, min(20, rowWidth * 0.028))
        let gapBeforeBadge: CGFloat = needsTrailingPill ? 10 : 0
        let pillW: CGFloat = needsTrailingPill ? min(80, rowWidth * 0.18) : 0
        let availForThumbs = rowWidth - gapBeforeBadge - pillW
        guard availForThumbs > 8 else { return nil }

        let minSide = max(72, rowWidth * 0.096)
        let maxSide = min(220, rowWidth * 0.28)
        let rawFit = (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount)
        var side = min(maxSide, max(minSide, rawFit))
        let thumbsWidthCheck = CGFloat(displayCount) * side + CGFloat(displayCount - 1) * spacing
        if thumbsWidthCheck > availForThumbs + 0.5 {
            side = max(44, (availForThumbs - CGFloat(displayCount - 1) * spacing) / CGFloat(displayCount))
        }

        let cornerR = side * 0.2
        let x = origin.x
        let y = origin.y
        let cell = CGRect(x: x, y: y, width: side, height: side)
        return (cell, cornerR)
    }

    private static func photoAspectFillDrawRect(for photo: UIImage, pixelSize: CGSize) -> CGRect {
        let w = pixelSize.width, h = pixelSize.height
        let photoAR = photo.size.width / max(photo.size.height, 1)
        let frameAR = w / h
        let r: CGRect
        if photoAR > frameAR {
            let dh = h
            let dw = dh * photoAR
            r = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
        } else {
            let dw = w
            let dh = dw / photoAR
            r = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
        }
        return integralRect(r)
    }

    private static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        let u = min(1, max(0, t))
        if u < 0.5 { return 4 * u * u * u }
        let v = 2 * u - 2
        return 1 + v * v * v / 2
    }

    /// One transition frame: frozen map composite + photo growing from thumbnail cell toward full slide rect.
    private static func drawMapToFirstPhotoTransitionFrame(
        lastMapComposite: UIImage,
        photo: UIImage,
        progress t: CGFloat,
        fromCell: CGRect,
        fromCornerRadius: CGFloat,
        toPhotoRect: CGRect,
        pixelSize: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            prepareContextForSharpBitmapCompositing(cg)
            lastMapComposite.draw(in: CGRect(origin: .zero, size: pixelSize))

            let u = min(1, max(0, t))
            let rect = CGRect(
                x: fromCell.minX + (toPhotoRect.minX - fromCell.minX) * u,
                y: fromCell.minY + (toPhotoRect.minY - fromCell.minY) * u,
                width: fromCell.width + (toPhotoRect.width - fromCell.width) * u,
                height: fromCell.height + (toPhotoRect.height - fromCell.height) * u
            )
            let corner = fromCornerRadius * (1 - u)

            cg.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: corner).addClip()
            prepareContextForSharpBitmapCompositing(cg)
            photo.draw(in: mapOverlayAspectFillRect(imageSize: photo.size, bounds: rect))
            cg.restoreGState()
        }
    }

    // MARK: - Moment video clip

    private static func momentVideoURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              id.hasPrefix(AppCapturePhotoService.prefix),
              let uuid = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.momentVideoFileURL(for: uuid)
    }

    private static func momentVideoDurationSeconds(for photo: RecapPhoto) -> Double {
        guard let url = momentVideoURL(for: photo) else { return 0 }
        let sec = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        guard sec.isFinite, sec > 0.02 else { return 0 }
        return sec
    }

    /// Decodes `moment_video.mov` at export FPS, overlays place name + timestamp on every frame,
    /// and streams through `frameHandler`. Cross-dissolves from `dissolveFrom` when provided.
    /// Returns the last emitted frame (for dissolves into the next slide).
    private static func emitMomentVideoClipWithPlaceOverlay(
        url: URL,
        pixelSize: CGSize,
        dissolveFrom previousFrame: UIImage?,
        placeName: String,
        timestampText: String,
        momentAudioHandler: ((URL, Double, Double) -> Void)?,
        frameHandler: (UIImage, Double) async throws -> Void
    ) async throws -> UIImage? {
        let asset = AVURLAsset(url: url)
        let durationSec: Double
        if #available(iOS 16.0, *) {
            durationSec = CMTimeGetSeconds(try await asset.load(.duration))
        } else {
            durationSec = CMTimeGetSeconds(asset.duration)
        }
        guard durationSec.isFinite, durationSec > 0.02 else { return previousFrame }

        let transitionSeconds = previousFrame != nil ? mapToReelTransitionSeconds : 0
        momentAudioHandler?(url, transitionSeconds, durationSec)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize.width, height: pixelSize.height)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

        let frameCount = max(1, Int((durationSec * momentVideoExportFPS).rounded()))
        let dt = durationSec / Double(frameCount)

        func videoFrameWithOverlay(at index: Int) throws -> UIImage {
            let t = min(Double(index) / momentVideoExportFPS, max(durationSec - 0.001, 0))
            let time = CMTime(seconds: t, preferredTimescale: 600)
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            return drawPhotoSlide(
                UIImage(cgImage: cg),
                caption: nil,
                placeName: placeName,
                timestampText: timestampText,
                pixelSize: pixelSize,
                kbScale: 1.0
            )
        }

        var lastEmitted: UIImage?

        if let prev = previousFrame {
            let firstVF = try videoFrameWithOverlay(at: 0)
            let nD = max(10, Int(round(mapToReelTransitionSeconds * mapToReelTransitionFPS)))
            let dDt = mapToReelTransitionSeconds / Double(nD)
            let denom = max(nD - 1, 1)
            for fi in 0..<nD {
                try Task.checkCancellation()
                let t = CGFloat(fi) / CGFloat(denom)
                let blended = autoreleasepool {
                    drawMapToReelTransitionFrame(mapFrame: prev, reelFrame: firstVF, progress: t, pixelSize: pixelSize)
                }
                try await frameHandler(blended, dDt)
            }
            lastEmitted = firstVF
            for fi in 1..<frameCount {
                try Task.checkCancellation()
                let frame = try videoFrameWithOverlay(at: fi)
                lastEmitted = frame
                try await frameHandler(frame, dt)
            }
        } else {
            for fi in 0..<frameCount {
                try Task.checkCancellation()
                let frame = try videoFrameWithOverlay(at: fi)
                lastEmitted = frame
                try await frameHandler(frame, dt)
            }
        }

        return lastEmitted
    }

    // MARK: - Photo Slide

    private static func drawPhotoSlide(
        _ photo: UIImage,
        caption: String?,
        placeName: String,
        timestampText: String,
        pixelSize: CGSize,
        kbScale: CGFloat = 1.0
    ) -> UIImage {
        let hasStory = !(caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = pixelSize.width, h = pixelSize.height
            let cs = CGColorSpaceCreateDeviceRGB()

            // Aspect-fill, then expand from the center for Ken Burns.
            let photoAR = photo.size.width / max(photo.size.height, 1)
            let frameAR = w / h
            let baseRect: CGRect
            if photoAR > frameAR {
                let dh = h; let dw = dh * photoAR
                baseRect = CGRect(x: (w - dw) / 2, y: 0, width: dw, height: dh)
            } else {
                let dw = w; let dh = dw / photoAR
                baseRect = CGRect(x: 0, y: (h - dh) / 2, width: dw, height: dh)
            }
            let kbW = baseRect.width * kbScale, kbH = baseRect.height * kbScale
            let photoRect = integralRect(CGRect(
                x: baseRect.midX - kbW / 2, y: baseRect.midY - kbH / 2,
                width: kbW, height: kbH
            ))
            prepareContextForSharpBitmapCompositing(cg)
            photo.draw(in: photoRect)

            // Light top scrim — keeps the fixed-position clock readable on bright skies
            cg.drawLinearGradient(
                CGGradient(colorsSpace: cs, colors: [
                    UIColor.black.withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor
                ] as CFArray, locations: [0, 1])!,
                start: .zero, end: CGPoint(x: 0, y: h * 0.16), options: []
            )

            let maxW = w - 80
            let capTrimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let storyFont = UIFont.systemFont(ofSize: (w * 0.042).rounded(), weight: .semibold)
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 7
            para.lineBreakMode = .byWordWrapping
            para.alignment = .center
            let storyAttribs: [NSAttributedString.Key: Any] = [
                .font: storyFont, .foregroundColor: UIColor.white, .paragraphStyle: para
            ]
            let capHeight: CGFloat = {
                guard hasStory, !capTrimmed.isEmpty else { return 0 }
                let measured = (capTrimmed as NSString).boundingRect(
                    with: CGSize(width: maxW, height: storyFont.lineHeight * 4 + 16),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs, context: nil
                )
                return ceil(measured.height)
            }()

            // Place name above timestamp — top center stack, kept low to clear faces / skyline
            let placeFont = UIFont.systemFont(ofSize: w * 0.038, weight: .semibold)
            let placeStr = placeName as NSString
            let placePara = NSMutableParagraphStyle()
            placePara.alignment = .center
            placePara.lineBreakMode = .byWordWrapping
            let pPX: CGFloat = 22, pPY: CGFloat = 11
            let maxPlacePillW: CGFloat = w - 32
            let placeMeasureAttribs: [NSAttributedString.Key: Any] = [
                .font: placeFont, .foregroundColor: UIColor.white, .paragraphStyle: placePara
            ]
            let placeMeasured = placeStr.boundingRect(
                with: CGSize(width: maxPlacePillW - pPX * 2, height: placeFont.lineHeight * 2 + 4),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: placeMeasureAttribs, context: nil
            )
            let placePillW = min(ceil(placeMeasured.width) + pPX * 2, maxPlacePillW)
            let placePillH = ceil(placeMeasured.height) + pPY * 2
            let placePillX = (w - placePillW) / 2

            let tsFont = UIFont.monospacedDigitSystemFont(ofSize: (w * 0.034).rounded(), weight: .semibold)
            let tsStr = timestampText as NSString
            let tsAttribs: [NSAttributedString.Key: Any] = [.font: tsFont, .foregroundColor: UIColor.white]
            let tsSize = tsStr.size(withAttributes: tsAttribs)
            let tsPadH: CGFloat = 18, tsPadV: CGFloat = 10
            let tsPillW = min(tsSize.width + tsPadH * 2, w - 64)
            let tsPillH = tsSize.height + tsPadV * 2

            let pillStackGap: CGFloat = 10
            let reelTopChromePad: CGFloat = 92
            let topStackOriginY = (max(100, h * 0.078) + reelTopChromePad).rounded()
            let placePillY = topStackOriginY
            let placePillRect = integralRect(
                CGRect(x: placePillX, y: placePillY, width: placePillW, height: placePillH)
            )
            UIColor.black.withAlphaComponent(0.52).setFill()
            UIBezierPath(roundedRect: placePillRect, cornerRadius: placePillRect.height / 2).fill()
            let placeDrawAttribs = placeMeasureAttribs
            let placeTextRect = integralRect(
                CGRect(
                    x: placePillRect.minX + pPX,
                    y: placePillRect.minY + pPY,
                    width: placePillW - pPX * 2,
                    height: placePillH - pPY * 2
                )
            )
            placeStr.draw(
                with: placeTextRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: placeDrawAttribs,
                context: nil
            )

            let tsPillRect = integralRect(
                CGRect(x: (w - tsPillW) / 2, y: placePillRect.maxY + pillStackGap, width: tsPillW, height: tsPillH)
            )
            // Match place-name pill (same fill as `placePillRect` above).
            UIColor.black.withAlphaComponent(0.52).setFill()
            UIBezierPath(roundedRect: tsPillRect, cornerRadius: tsPillH * 0.5).fill()
            let tsDraw = CGPoint(
                x: (tsPillRect.midX - tsSize.width / 2).rounded(),
                y: (tsPillRect.midY - tsSize.height / 2).rounded()
            )
            tsStr.draw(at: tsDraw, withAttributes: tsAttribs)

            // Story caption — vertically centered (~62 % down) so it clears both the top
            // place/time pills and the bottom chrome on TikTok / Facebook / Instagram.
            if hasStory, !capTrimmed.isEmpty, capHeight > 0 {
                // Measure the true single-line width so we can CENTER the draw rect on the
                // canvas directly — never rely on paragraph .center alignment for positioning
                // (it doesn't work when the container is wider than the text content).
                let singleLineW = ceil((capTrimmed as NSString).size(withAttributes: storyAttribs).width)
                let capWidth = min(singleLineW, maxW)
                let capX = ((w - capWidth) / 2).rounded()
                let capY  = (h * 0.62 - capHeight / 2).rounded()
                let capRect = CGRect(x: capX, y: capY, width: capWidth, height: capHeight)

                // Single rounded panel (matches top place/time pills) — avoids multi-axis
                // gradient bands that read as muddy or uneven on photos.
                let bandPadH: CGFloat = 44
                let bandPadV: CGFloat = 28
                let bandX = (capX - bandPadH).rounded()
                let bandW = capWidth + bandPadH * 2
                let bandY = capY - bandPadV
                let bandH = capHeight + bandPadV * 2
                let panelRect = integralRect(CGRect(x: bandX, y: bandY, width: bandW, height: bandH))
                let panelCorner = min(26, max(14, panelRect.height * 0.22))
                let panelPath = UIBezierPath(roundedRect: panelRect, cornerRadius: panelCorner)
                UIColor.black.withAlphaComponent(0.56).setFill()
                panelPath.fill()

                (capTrimmed as NSString).draw(
                    with: capRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: storyAttribs,
                    context: nil
                )
            }
        }
    }

    // MARK: - Helpers

    private static func prepareContextForSharpBitmapCompositing(_ cg: CGContext) {
        cg.interpolationQuality = .high
        cg.setShouldAntialias(true)
        // Video frames are drawn into a bitmap; disable subpixel font rendering to avoid
        // colored/fringed edges and “textured” glyphs in the exported H.264 output.
        cg.setAllowsFontSmoothing(true)
        cg.setShouldSmoothFonts(true)
        cg.setAllowsFontSubpixelPositioning(false)
        cg.setAllowsFontSubpixelQuantization(false)
    }

    private static func integralRect(_ r: CGRect) -> CGRect {
        CGRect(
            x: (r.origin.x + 0.5).rounded(.down),
            y: (r.origin.y + 0.5).rounded(.down),
            width: (r.size.width + 0.5).rounded(.down),
            height: (r.size.height + 0.5).rounded(.down)
        )
    }

    /// Day-wide region for the first pan segment (matches cinematic map intro).
    private static func dayOverviewRegion(for stops: [PlaceStop]) -> MKCoordinateRegion {
        if let r = MapSnapshotHelper.regionBoundingAllStops(stops, padding: 0.16) { return r }
        let c = stops.compactMap { $0.representativeLocation?.clCoordinate }
            .first { $0.latitude.isFinite && $0.longitude.isFinite }
            ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902)
        return MKCoordinateRegion(
            center: c,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    }

    /// Map → reel transition: map punches in (zoom-burst) while the reel materialises from the
    /// centre with a delayed scale-up. A luminance flash at the midpoint sharpens the cut.
    private static func drawMapToReelTransitionFrame(
        mapFrame: UIImage,
        reelFrame: UIImage,
        progress rawT: CGFloat,
        pixelSize: CGSize
    ) -> UIImage {
        let t = min(1, max(0, rawT))
        let w = pixelSize.width, h = pixelSize.height

        // Map punches in: 1.0 → 1.40x zoom from centre (ease-in so it accelerates)
        let mapZoom = 1.0 + 0.40 * easeInOutCubic(t)

        // Reel materialises: scale 0.84 → 1.0, opacity delayed until t = 0.22
        let reelAlpha = easeInOutCubic(max(0, (t - 0.22) / 0.78))
        let reelScale = 0.84 + 0.16 * easeInOutCubic(t)

        // Luminance flash peaks at t ≈ 0.5 (sin arch, max 30% white)
        let flash = CGFloat(sin(Double(t) * .pi) * 0.30)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext

            // Map zoomed in from centre
            cg.saveGState()
            cg.translateBy(x: w / 2, y: h / 2)
            cg.scaleBy(x: mapZoom, y: mapZoom)
            cg.translateBy(x: -w / 2, y: -h / 2)
            prepareContextForSharpBitmapCompositing(cg)
            mapFrame.draw(in: CGRect(origin: .zero, size: pixelSize))
            cg.restoreGState()

            // Reel scaled up from centre + fade in
            if reelAlpha > 0 {
                cg.saveGState()
                cg.setAlpha(reelAlpha)
                cg.translateBy(x: w / 2, y: h / 2)
                cg.scaleBy(x: reelScale, y: reelScale)
                cg.translateBy(x: -w / 2, y: -h / 2)
                prepareContextForSharpBitmapCompositing(cg)
                reelFrame.draw(in: CGRect(origin: .zero, size: pixelSize))
                cg.restoreGState()
            }

            // Luminance flash
            if flash > 0 {
                cg.setFillColor(UIColor.white.withAlphaComponent(flash).cgColor)
                cg.fill(CGRect(origin: .zero, size: pixelSize))
            }
        }
    }

    /// Cross-fade from the rendered cover to the first map frame (`progress` 0…1).
    private static func blendCoverToMap(from cover: UIImage, to map: UIImage, progress: CGFloat, size: CGSize) -> UIImage {
        let u = min(1, max(0, progress))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            prepareContextForSharpBitmapCompositing(ctx.cgContext)
            cover.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: 1 - u)
            map.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: u)
        }
    }

    /// Zoom-blend frame: two distinct phases so the motion reads as a real zoom-in.
    ///
    /// **Phase 1 (progress 0 → `zoomPhaseSplit`)** — pure crop-based zoom of `wideImage`.
    ///   The center (1/scale × 1/scale) of the wide snapshot is cropped and stretched to fill the
    ///   canvas, producing continuous motion with no competing dissolve.  CGImage.cropping is
    ///   zero-copy for contiguous bitmaps so no large intermediate is allocated.
    ///
    /// **Phase 2 (`zoomPhaseSplit` → 1)** — cross-dissolve from the fully-zoomed wide image to the
    ///   crisp tile set of `tightImage`.  The map is already at the right zoom level; this phase only
    ///   sharpens the tiles.
    ///
    /// `zoomRatio` = wideSpan / tightSpan (~2.67 for 0.008° → 0.003°).
    /// `overlayImage` contains the focused-stop circle halo + coloured pin + name pill on a transparent
    /// background, at the same logical size/scale as `wideImage`.  It is drawn at a fixed canvas rect
    /// (no crop-scale) so the marker visually stays the same size while the map tiles zoom underneath.
    private static func drawZoomBlendFrame(
        wideImage: UIImage,
        tightImage: UIImage,
        overlayImage: UIImage,
        progress: CGFloat,
        zoomRatio: CGFloat,
        size: CGSize
    ) -> UIImage {
        let p = min(1, max(0, progress))
        let zoomPhaseSplit: CGFloat = 0.65
        let fullRect = CGRect(origin: .zero, size: size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            prepareContextForSharpBitmapCompositing(ctx.cgContext)
            let cgWide = wideImage.cgImage

            func drawWideCropped(scale: CGFloat, alpha: CGFloat) {
                guard let cgWide else {
                    wideImage.draw(in: fullRect, blendMode: .normal, alpha: alpha)
                    return
                }
                let pw = CGFloat(cgWide.width), ph = CGFloat(cgWide.height)
                let cw = pw / scale, ch = ph / scale
                let cropRect = CGRect(x: (pw - cw) / 2, y: (ph - ch) / 2, width: cw, height: ch)
                if let cropped = cgWide.cropping(to: cropRect) {
                    UIImage(cgImage: cropped, scale: wideImage.scale, orientation: wideImage.imageOrientation)
                        .draw(in: fullRect, blendMode: .normal, alpha: alpha)
                }
            }

            if p <= zoomPhaseSplit {
                // Phase 1: pure crop-zoom of the wide map base (no baked overlay) + fixed-size overlay.
                let u = easeInOutCubic(p / zoomPhaseSplit)
                let scale = 1.0 + (zoomRatio - 1.0) * u
                drawWideCropped(scale: scale, alpha: 1.0)
                overlayImage.draw(in: fullRect, blendMode: .normal, alpha: 1.0)
            } else {
                // Phase 2: dissolve from fully-zoomed wide to sharp tight tiles.
                // Fixed overlay fades out as tightImage (with baked overlay) fades in — no jump.
                let u = easeInOutCubic((p - zoomPhaseSplit) / (1.0 - zoomPhaseSplit))
                drawWideCropped(scale: zoomRatio, alpha: 1.0 - u)
                overlayImage.draw(in: fullRect, blendMode: .normal, alpha: 1.0 - u)
                tightImage.draw(in: fullRect, blendMode: .normal, alpha: u)
            }
        }
    }

    /// One cross-dissolve frame between two already-rendered images (`stepIndex` is 1...`blendStepCount`).
    /// No MKMapSnapshotter calls — pure pixel blending with smooth-step easing.
    /// When `imageA` and `imageB` share the same center (zoom-in), this looks like a smooth zoom.
    private static func synthesizeBlendFrame(
        from imageA: UIImage,
        to imageB: UIImage,
        stepIndex: Int,
        blendStepCount: Int,
        size: CGSize
    ) -> UIImage {
        let t = CGFloat(stepIndex) / CGFloat(blendStepCount + 1)
        let alpha = t * t * (3 - 2 * t) // smooth-step ease
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            prepareContextForSharpBitmapCompositing(cg)
            imageA.draw(in: CGRect(origin: .zero, size: size))
            imageB.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: alpha)
        }
    }

    /// Formats EXIF-style `yyyy:MM:dd HH:mm:ss` digitized strings for on-screen overlays. Parse and display
    /// both use UTC so calendar components appear unchanged (matches ``PlaceStopRowView`` digitized handling).
    private static func formattedTimestamp(_ digitized: String?) -> String? {
        guard let raw = digitized?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let parse = DateFormatter()
        parse.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parse.date(from: raw) else { return nil }
        let display = DateFormatter()
        display.dateFormat = "h:mm a"
        display.locale = Locale.current
        display.timeZone = TimeZone(secondsFromGMT: 0)
        return display.string(from: date)
    }

    /// Same rules as thumbnails (``PlaceStopRowView.photoTimeDisplayText``): prefer per-photo digitized wall
    /// clock when present so export matches map overlays and publishing; otherwise format capture `Date`
    /// with ``PlaceStop/recapThumbnailTimeZone`` (inferred offset + identifiers), not only `timeZoneIdentifier`.
    private static func photoSlideTimeDisplayText(for photo: RecapPhoto, stop: PlaceStop) -> String {
        if let d = formattedTimestamp(photo.digitizedTime) { return d }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale.current
        f.timeZone = stop.recapThumbnailTimeZone
        return f.string(from: photo.timestamp)
    }

    /// `targetSize` is in pixels so `PHImageManager` returns a full-resolution image.
    private static func loadPhoto(_ photo: RecapPhoto, targetSize: CGSize) async -> UIImage? {
        if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
            if lid.hasPrefix(AppCapturePhotoService.prefix) {
                return AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            return await ImageLoader.shared.loadImageBypassingMemoryCache(assetIdentifier: lid, targetSize: targetSize)
        }
        guard let permanentURL = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !permanentURL.isEmpty else { return nil }
        do {
            let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: permanentURL)
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            return UIImage(data: data)
        } catch { return nil }
    }
}
