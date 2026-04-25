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
    var onTap: (CLLocationCoordinate2D) -> Void

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
            // notified of the new size.  Force the UIView to fill us so the Metal
            // drawable is the correct size.
            renderView?.frame = bounds
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
        private var currentZoomLevel: Int = 5   // 5 ≈ whole Korea peninsula; raise for street detail
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
            debugPrint("[KakaoMap] map view ready, setting up pin")
            setupPin(on: map)
        }

        @objc func addViewFailed(_ viewName: String, viewInfoName: String) {
            debugPrint("[KakaoMap] addView FAILED '\(viewName)'")
        }

        @objc func containerDidResized(_ size: CGSize) {
            // Keep the renderView UIView in sync whenever the engine reports a resize.
            if let c = container { c.renderView?.frame = c.bounds }
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
            debugPrint("[KakaoMap] terrain tapped lat=\(coord.latitude) lon=\(coord.longitude)")
            DispatchQueue.main.async { self.parent.onTap(coord) }
        }

        // MARK: - Pin

        private func setupPin(on map: KakaoMap) {
            let coord = pendingCenter ?? parent.center
            let mapPoint = MapPoint(longitude: coord.longitude, latitude: coord.latitude)
            let mgr = map.getLabelManager()

            // Kakao SDK (K3fCore) only accepts plain 8-bit sRGB bitmaps.
            // UIGraphicsImageRenderer defaults to Display-P3 on modern hardware;
            // UIGraphicsBeginImageContextWithOptions still uses a device-dependent
            // color space that can mismatch. Use an explicit CGContext backed by the
            // named sRGB color space with non-premultiplied alpha — the most
            // unambiguous format we can give the SDK.
            let pinSide = 44
            let pinImage: UIImage? = {
                guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx  = CGContext(
                          data: nil,
                          width: pinSide, height: pinSide,
                          bitsPerComponent: 8,
                          bytesPerRow: 0,
                          space: srgb,
                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                              | CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else { return nil }
                // outer red circle
                ctx.setFillColor(UIColor.systemRed.cgColor)
                ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 40, height: 40))
                // inner white dot
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: 16, y: 16, width: 12, height: 12))
                guard let cg = ctx.makeImage() else { return nil }
                return UIImage(cgImage: cg, scale: 1.0, orientation: .up)
            }()
            if let img = pinImage {
                let icon  = PoiIconStyle(symbol: img, anchorPoint: CGPoint(x: 0.5, y: 1.0))
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
