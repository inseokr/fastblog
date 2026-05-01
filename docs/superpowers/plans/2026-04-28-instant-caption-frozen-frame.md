# Instant Caption Frozen Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the real camera frame instantly when the shutter is tapped (Snapchat-style freeze), eliminating the 0.5–1s delay caused by `snapshotCurrentWindow()` failing to capture the Metal-rendered camera preview layer.

**Architecture:** Add `AVCaptureVideoDataOutput` to `CameraController` that continuously stores the latest `CVImageBuffer` from the live preview. At shutter press time, `presentImmediateCaptionOverlayPlaceholder()` grabs `cameraController.latestFrame` (a synchronous UIImage conversion from the stored pixel buffer) instead of calling `snapshotCurrentWindow()` which cannot render Metal/GPU layers and returns a black camera area.

**Tech Stack:** AVFoundation (`AVCaptureVideoDataOutput`, `AVCaptureVideoDataOutputSampleBufferDelegate`), Core Image (`CIContext`, `CIImage`), Swift concurrency (NSLock for thread-safe pixel buffer hand-off), SwiftUI/UIKit

---

## File Map

| File | Change |
|------|--------|
| `fastblog/Views/TripsView.swift` | Add `AVCaptureVideoDataOutput` conformance + properties to `CameraController` (lines ~1642–1890), wire up in `setupSession` (lines ~1719–1721), add delegate method, expose `latestFrame`, replace `snapshotCurrentWindow()` call in `presentImmediateCaptionOverlayPlaceholder` (lines ~3543–3571) |

No new files.

---

## Task 1: Add video data output support to `CameraController`

**Files:**
- Modify: `fastblog/Views/TripsView.swift:1642` (CameraController class declaration)
- Modify: `fastblog/Views/TripsView.swift:1642–1660` (stored properties block)
- Modify: `fastblog/Views/TripsView.swift:1719–1721` (setupSession output wiring)
- Modify: `fastblog/Views/TripsView.swift:1889` (end of CameraController — add delegate extension)

- [ ] **Step 1: Add `AVCaptureVideoDataOutputSampleBufferDelegate` to the class declaration**

At line 1642, change:
```swift
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
```
to:
```swift
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
```

- [ ] **Step 2: Add the video data output stored properties after the `photoOutput` declaration**

Current lines 1643–1649:
```swift
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "bloggo.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let locationManager = CLLocationManager()
    private var videoDevice: AVCaptureDevice?

    private var captureCompletion: ((UIImage?, String?) -> Void)?
```

Replace with:
```swift
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "bloggo.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataQueue = DispatchQueue(label: "bloggo.camera.videodata", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let latestFrameLock = NSLock()
    private var _latestPixelBuffer: CVImageBuffer?
    private let locationManager = CLLocationManager()
    private var videoDevice: AVCaptureDevice?

    private var captureCompletion: ((UIImage?, String?) -> Void)?

    /// The most recent camera frame captured from the live preview.
    /// Returns nil until the session starts producing frames.
    /// Safe to call from any thread.
    var latestFrame: UIImage? {
        latestFrameLock.lock()
        let buffer = _latestPixelBuffer
        latestFrameLock.unlock()
        guard let buffer else { return nil }
        let ciImage = CIImage(cvImageBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
```

- [ ] **Step 3: Wire the video data output into `setupSession` alongside `photoOutput`**

Current lines 1719–1721:
```swift
                if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
```

Replace with:
```swift
                if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                if !self.session.outputs.contains(self.videoDataOutput), self.session.canAddOutput(self.videoDataOutput) {
                    self.videoDataOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataQueue)
                    // Discard frames if processing falls behind — we only need the latest one.
                    self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                    self.session.addOutput(self.videoDataOutput)
                    // Orient frames upright for portrait capture so UIImage needs no transform.
                    if let connection = self.videoDataOutput.connection(with: .video) {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                    }
                }
```

- [ ] **Step 4: Add the `AVCaptureVideoDataOutputSampleBufferDelegate` method**

After the closing `}` of `CameraController` (currently line 1890, after the `photoOutput(_:didFinishProcessingPhoto:)` delegate ends), add a new extension **before** the `CLLocationManagerDelegate` extension:

```swift
extension CameraController: /* AVCaptureVideoDataOutputSampleBufferDelegate already declared on class */ {
```

Actually, since `CameraController` already conforms on the class declaration, just add the method inside the existing `// MARK: - AVCapturePhotoCaptureDelegate` section or in a new MARK block right before the `CLLocationManagerDelegate` extension. Insert at line 1891 (after `}`  closes `photoOutput(_:didFinishProcessingPhoto:)`):

```swift
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestFrameLock.lock()
        _latestPixelBuffer = pixelBuffer
        latestFrameLock.unlock()
    }
```

Place it inside the `CameraController` class body, just before the closing `}` on line 1890.

- [ ] **Step 5: Build and confirm no compiler errors**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

Common errors to watch for:
- `cannot find type 'AVCaptureVideoDataOutputSampleBufferDelegate'` → make sure `AVFoundation` is imported (it already is at the top of TripsView.swift)
- `'videoOrientation' is deprecated` → this is a warning not an error; acceptable for now since `videoRotationAngle` requires iOS 17+ and the codebase targets lower

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat(camera): add AVCaptureVideoDataOutput to CameraController for instant frame capture"
```

---

## Task 2: Replace `snapshotCurrentWindow()` with `latestFrame` in the placeholder function

**Files:**
- Modify: `fastblog/Views/TripsView.swift:3543–3571` (`presentImmediateCaptionOverlayPlaceholder`)

- [ ] **Step 1: Replace the snapshot call**

Current `presentImmediateCaptionOverlayPlaceholder` body (lines 3543–3557):
```swift
    private func presentImmediateCaptionOverlayPlaceholder() {
        guard captionModeFrozenImage == nil else { return }

        let fallback = latestCaptureWithPreview?.previewImage
        let snapshot = snapshotCurrentWindow()
        guard let frozen = snapshot ?? fallback else { return }

        captionModePlaceTitle = "Captured Moment"
        captionModePlaceSubtitle = nil
        captionModeWantsKeyboard = false
        captionModeFrozenImage = frozen
        withAnimation(.easeOut(duration: 0.12)) {
            isCaptionModeActive = true
        }
    }
```

Replace with:
```swift
    private func presentImmediateCaptionOverlayPlaceholder() {
        guard captionModeFrozenImage == nil else { return }

        // Use the live video frame captured by AVCaptureVideoDataOutput — this correctly captures
        // the Metal-rendered camera preview, unlike snapshotCurrentWindow() which renders it black.
        guard let frozen = cameraController.latestFrame ?? latestCaptureWithPreview?.previewImage else { return }

        captionModePlaceTitle = "Captured Moment"
        captionModePlaceSubtitle = nil
        captionModeWantsKeyboard = false
        captionModeFrozenImage = frozen
        withAnimation(.easeOut(duration: 0.12)) {
            isCaptionModeActive = true
        }
    }
```

- [ ] **Step 2: Delete `snapshotCurrentWindow()` since it is no longer called**

Find and delete the entire `snapshotCurrentWindow` function (lines ~3559–3571):
```swift
    private func snapshotCurrentWindow() -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
```

Delete it entirely. It is only called from `presentImmediateCaptionOverlayPlaceholder` which no longer uses it.

- [ ] **Step 3: Build**

```bash
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "fix(camera): use live video frame for instant caption overlay instead of UIKit window snapshot"
```

---

## Manual Verification Checklist

After both tasks are done, run on a **physical device** (simulator has no real camera):

1. Open the camera from a trip
2. Enable caption mode (tap the caption toolbar button)
3. Press the shutter — the frozen preview should appear **instantly** (< 100ms), showing the actual scene
4. The caption text editor and keyboard should then appear
5. Tap Done or X — camera returns to live view
6. Flip to front camera, repeat steps 2–5 — frozen preview should still appear instantly
7. Take a photo without caption mode enabled — normal behavior unaffected

---

## Self-Review

**Spec coverage:**
- Root cause (Metal layer not captured) — fixed by video data output ✓
- Instant photo appearance on shutter tap — fixed by `latestFrame` ✓
- Orientation (portrait) — handled via `videoOrientation = .portrait` on the connection ✓
- Front camera — outputs stay in session when switching cameras (only inputs are removed in `switchCamera`); video data output persists ✓
- `snapshotCurrentWindow` removed (no dead code) ✓

**Placeholder scan:** No TBDs, all code is complete.

**Type consistency:** `latestFrame: UIImage?` used consistently in Task 1 and Task 2.
