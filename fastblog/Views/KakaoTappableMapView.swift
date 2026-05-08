//
//  KakaoTappableMapView.swift
//  fastblog
//
//  SwiftUI-embeddable Kakao Maps view using the KakaoMaps iOS SDK v2.
//  Used in place of TappableMapView when placeCountryCode == "KR".
//  Requires a Kakao Native App Key in KAKAO_NATIVE_APP_KEY (Secrets.xcconfig).
//

import CoreLocation
import KakaoMapsSDK
import SwiftUI

struct KakaoTappableMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let title: String?
    var zoomInTrigger: Int = 0
    var zoomOutTrigger: Int = 0
    /// Second parameter is Kakao zoom level (1…21, higher = closer). Third is true when the user
    /// tapped directly on a built-in Kakao tile POI (vs. bare terrain). Used to widen the attraction search.
    var onTap: (CLLocationCoordinate2D, Int, Bool) -> Void

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> EngineStartingContainer {
        Self.initSDKIfNeeded()
        let container = EngineStartingContainer()
        let controller = KMController(viewContainer: container)
        controller.delegate = context.coordinator
        context.coordinator.configure(controller: controller, container: container, center: center)
        // prepareEngine() + activateEngine() are driven from EngineStartingContainer
        // once the view has a non-zero frame and is in a window. Calling them earlier
        // produces "Prepare engine failed! ViewSize is zero." and CAMetalLayer warnings.
        container.engineController = controller
        return container
    }

    func updateUIView(_ uiView: EngineStartingContainer, context: Context) {
        let c = context.coordinator
        if zoomInTrigger != c.lastZoomInTrigger {
            c.lastZoomInTrigger = zoomInTrigger
            c.zoomIn()
        }
        if zoomOutTrigger != c.lastZoomOutTrigger {
            c.lastZoomOutTrigger = zoomOutTrigger
            c.zoomOut()
        }
        c.updatePin(to: center)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleUIView(_ uiView: EngineStartingContainer, coordinator: Coordinator) {
        uiView.engineController?.pauseEngine()
    }

    // MARK: - KMViewContainer that starts the engine after first layout

    /// Drives the Kakao engine lifecycle in lockstep with the view's window
    /// membership and layout state. The required Kakao sequence is:
    ///   1. `prepareEngine()` — only valid once the view has a non-zero frame
    ///   2. `activateEngine()` — must be called *before* the SDK will invoke
    ///      the `addViews()` delegate callback
    ///   3. delegate `addViews()` fires → we add the actual map view
    ///   4. `pauseEngine()` via `dismantleUIView` when the view is truly removed
    final class EngineStartingContainer: KMViewContainer {
        weak var engineController: KMController?
        private var enginePrepared = false
        private var engineActivated = false
        override func layoutSubviews() {
            super.layoutSubviews()
            // renderView is created during KMController init with frame=.zero and is
            // never resized by the SDK's own layoutSubviews — only the engine is
            // notified of the new size.  Only push a new frame when bounds actually
            // change so pinch / pan gestures are not reset mid-gesture.
            if let rv = renderView {
                if !rv.frame.equalTo(bounds) {
                    rv.frame = bounds
                }
            }
            startEngineIfReady()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                startEngineIfReady()
            }
            // Do NOT pause here. Sheet animations temporarily set window=nil,
            // which would trigger pauseEngine() → activateEngine() → addViews()
            // on return, wiping tiles and producing a white flash.
            // dismantleUIView handles true teardown when the view is removed for real.
        }

        private func startEngineIfReady() {
            guard let engineController,
                  window != nil,
                  bounds.width > 0, bounds.height > 0 else { return }
            if !enginePrepared {
                let ok = engineController.prepareEngine()
                enginePrepared = ok
                debugPrint("[KakaoMap] prepareEngine() → \(ok)")
                guard ok else { return }

                // prepareEngine() creates renderView (the Metal UIView) but does NOT
                // guarantee it is in our subview hierarchy. Add it now so the Metal
                // drawable is actually visible, then size it to fill us.
                if let rv = renderView {
                    if rv.superview == nil { addSubview(rv) }
                    if !rv.frame.equalTo(bounds) {
                        rv.frame = bounds
                    }
                }
            }
            if !engineActivated {
                engineController.activateEngine()
                engineActivated = true
                debugPrint("[KakaoMap] activateEngine() called")
            }
        }
    }

    // MARK: - SDK init (once per app session)

    private static var sdkInitialized = false
    private static func initSDKIfNeeded() {
        guard !sdkInitialized else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String,
              !key.isEmpty, !key.hasPrefix("$"), !key.contains("YOUR_KAKAO") else {
            debugPrint("[KakaoMap] skipping SDK init — key missing or placeholder")
            return
        }
        SDKInitializer.InitSDK(appKey: key)
        sdkInitialized = true
        debugPrint("[KakaoMap] SDK initialized, key=\(key.prefix(6))...")
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MapControllerDelegate, KakaoMapEventDelegate {
        var parent: KakaoTappableMapView
        private var controller: KMController?   // strong — keeps engine alive
        private weak var container: EngineStartingContainer?
        private var map: KakaoMap?
        private var pin: Poi?
        private var pendingCenter: CLLocationCoordinate2D?
        /// Default ~neighborhood zoom so map tiles show Kakao POI labels; user can zoom out with controls.
        private var currentZoomLevel: Int = 15
        var lastZoomInTrigger = 0
        var lastZoomOutTrigger = 0

        private static let viewName = "mapview"
        private static let layerID  = "pinLayer"
        private static let styleID  = "redPin"
        private static let pinID    = "centerPin"

        init(_ parent: KakaoTappableMapView) { self.parent = parent }

        func configure(controller: KMController, container: EngineStartingContainer, center: CLLocationCoordinate2D) {
            self.controller = controller
            self.container = container
            self.pendingCenter = center
        }

        // MARK: - MapControllerDelegate

        @objc func addViews() {
            debugPrint("[KakaoMap] addViews() called — engine ready")
            let coord = pendingCenter ?? parent.center
            let pos = MapPoint(longitude: coord.longitude, latitude: coord.latitude)
            let info = MapviewInfo(
                viewName: Self.viewName,
                appName: "openmap",    // use "openmap" when no Cocoa-registered app name
                viewInfoName: "map",   // SDK config name — distinct from viewName
                defaultPosition: pos,
                defaultLevel: currentZoomLevel
            )
            controller?.addView(info)
        }

        @objc func addViewSucceeded(_ viewName: String, viewInfoName: String) {
            guard viewName == Self.viewName,
                  let map = controller?.getView(viewName) as? KakaoMap else {
                debugPrint("[KakaoMap] addViewSucceeded: could not get map for '\(viewName)'")
                return
            }
            self.map = map
            map.eventDelegate = self
            // Two-finger rotate and "rotate + zoom" share the same touch path as pinch zoom.
            // Leaving them enabled often makes pinch feel inverted or erratic; keep plain `.zoom`.
            map.setGestureEnable(type: .rotate, enable: false)
            map.setGestureEnable(type: .rotateZoom, enable: false)
            currentZoomLevel = map.zoomLevel
            debugPrint("[KakaoMap] map view ready, setting up pin")
            setupPin(on: map)
        }

        @objc func addViewFailed(_ viewName: String, viewInfoName: String) {
            debugPrint("[KakaoMap] addView FAILED '\(viewName)'")
        }

        @objc func containerDidResized(_ size: CGSize) {
            // Keep the renderView UIView in sync whenever the engine reports a resize.
            guard let c = container, let rv = c.renderView, !rv.frame.equalTo(c.bounds) else { return }
            rv.frame = c.bounds
        }

        @objc func authenticationSucceeded() {
            debugPrint("[KakaoMap] authentication succeeded ✓")
        }

        @objc func authenticationFailed(_ errorCode: Int, desc: String) {
            debugPrint("[KakaoMap] authentication FAILED — code=\(errorCode) desc=\(desc)")
        }

        // MARK: - KakaoMapEventDelegate

        @objc func terrainDidTapped(kakaoMap: KakaoMap, position: MapPoint) {
            let coord = CLLocationCoordinate2D(
                latitude: position.wgsCoord.latitude,
                longitude: position.wgsCoord.longitude
            )
            let zoom = kakaoMap.zoomLevel
            debugPrint("[KakaoMap] terrain tapped lat=\(coord.latitude) lon=\(coord.longitude) zoom=\(zoom)")
            DispatchQueue.main.async { self.parent.onTap(coord, zoom, false) }
        }

        /// Fires when the user taps a built-in Kakao tile POI or a custom label-layer POI.
        /// Passes `isDirectPOITap: true` so the resolution layer can widen its attraction search —
        /// large outdoor sites (e.g. 첨성대) often have a registered coordinate offset by 150–250 m
        /// from the visible map icon.
        @objc func poiDidTapped(kakaoMap: KakaoMap, layerID: String, poiID: String, position: MapPoint) {
            // Skip taps on our own center pin — that location is already selected.
            guard layerID != Self.layerID || poiID != Self.pinID else { return }
            let coord = CLLocationCoordinate2D(
                latitude: position.wgsCoord.latitude,
                longitude: position.wgsCoord.longitude
            )
            let zoom = kakaoMap.zoomLevel
            debugPrint("[KakaoMap] POI tapped layerID=\(layerID) poiID=\(poiID) lat=\(coord.latitude) lon=\(coord.longitude) zoom=\(zoom)")
            DispatchQueue.main.async { self.parent.onTap(coord, zoom, true) }
        }

        /// Keeps `currentZoomLevel` aligned with pinch / pan so +/- buttons stay consistent.
        @objc func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
            currentZoomLevel = kakaoMap.zoomLevel
        }

        // MARK: - Pin

        private func setupPin(on map: KakaoMap) {
            let coord = pendingCenter ?? parent.center
            let mapPoint = MapPoint(longitude: coord.longitude, latitude: coord.latitude)
            let mgr = map.getLabelManager()

            // K3fCore is strict about pixel formats. Every raw CGContext approach
            // (BGRA, RGBA, opaque, premultiplied) has triggered "unsupported image
            // format". The only reliable solution: draw into any context, then
            // encode to PNG and decode back. iOS's PNG decoder always produces a
            // format-normalised CGImage that K3fCore accepts without complaint.
            let pinSide = CGSize(width: 44, height: 44)
            UIGraphicsBeginImageContextWithOptions(pinSide, false, 1.0)
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 40, height: 40)).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 16, y: 16, width: 12, height: 12)).fill()
            let rawImg = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            // PNG encode → decode normalises the pixel format to one K3fCore accepts.
            if let raw = rawImg,
               let pngData = raw.pngData(),
               let img = UIImage(data: pngData, scale: 1.0) {
                let icon  = PoiIconStyle(symbol: img, anchorPoint: CGPoint(x: 0.5, y: 0.5))
                let level = PerLevelPoiStyle(iconStyle: icon, padding: 0, level: 0)
                mgr.addPoiStyle(PoiStyle(styleID: Self.styleID, styles: [level]))
            }

            let layerOpt = LabelLayerOptions(
                layerID: Self.layerID,
                competitionType: .none,
                competitionUnit: .symbolFirst,
                orderType: .rank,
                zOrder: 10001
            )
            guard let layer = mgr.addLabelLayer(option: layerOpt) else {
                debugPrint("[KakaoMap] addLabelLayer returned nil")
                return
            }

            let poiOpt = PoiOptions(styleID: Self.styleID, poiID: Self.pinID)
            poiOpt.rank = 0
            let poi = layer.addPoi(option: poiOpt, at: mapPoint)
            poi?.show()
            self.pin = poi
            debugPrint("[KakaoMap] pin added at \(coord.latitude),\(coord.longitude)")
        }

        func updatePin(to center: CLLocationCoordinate2D) {
            guard pin != nil else { return }
            let mapPoint = MapPoint(longitude: center.longitude, latitude: center.latitude)
            pin?.moveAt(mapPoint, duration: 250)
        }

        // MARK: - Zoom

        func zoomIn() {
            currentZoomLevel = min(21, currentZoomLevel + 2)
            applyZoom()
        }

        func zoomOut() {
            currentZoomLevel = max(1, currentZoomLevel - 2)
            applyZoom()
        }

        private func applyZoom() {
            guard let map else { return }
            map.moveCamera(CameraUpdate.make(zoomLevel: currentZoomLevel, mapView: map))
        }
    }
}
