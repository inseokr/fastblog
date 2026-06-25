// CarouselStudioSheet.swift
// fastblog

import CoreImage
import PDFKit
import Photos
import PhotosUI
import SwiftUI
import UIKit
import Vision

extension Notification.Name {
    /// Alerts from `SocialPostStudioSheet` surfaced in Carousel Studio (`SlideTextEditorView`) above sheets/covers — Photos saves, share limits, etc.
    static let carouselStudioEditorExportBanner = Notification.Name("carouselStudioEditorExportBanner")
}

// MARK: - PIP background removal (Vision)

private let pipBackgroundRemovalCIContext = CIContext()

/// Downscales in **pixel** space (`size × scale`). Used for PIP Vision work, studio export-sized loads,
/// and any path that can decode larger than the export pixel budget (e.g. AppCapture originals).
private func downscaleUIImageByPixelLongEdge(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
    let w = image.size.width * image.scale
    let h = image.size.height * image.scale
    let long = max(w, h)
    guard long > 1 else { return image }
    guard long > maxLongEdge else { return image }
    let scaleFactor = min(1.0, maxLongEdge / long)
    let nw = max(1, floor(w * scaleFactor))
    let nh = max(1, floor(h * scaleFactor))
    return autoreleasepool {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
        }
    }
}

private func uiImageFromPixelBuffer(_ buffer: CVPixelBuffer, orientation: UIImage.Orientation = .up) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let extent = ciImage.extent.integral
    guard extent.width > 1, extent.height > 1,
          let cg = pipBackgroundRemovalCIContext.createCGImage(ciImage, from: extent) else { return nil }
    return UIImage(cgImage: cg, scale: 1, orientation: orientation)
}

/// Subject-only cutout with alpha, or `nil` if Vision cannot produce a mask (callers keep the original).
private func removePIPBackground(from image: UIImage) async -> UIImage? {
    let working = downscaleUIImageByPixelLongEdge(image, maxLongEdge: 1024)
    guard let cgImage = working.cgImage else { return nil }
    return await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            // Deployment target is iOS 17+; Vision foreground mask API is 17+ only.
            let result = removePIPForegroundInstanceMaskIOS17(cgImage: cgImage)
            cont.resume(returning: result)
        }
    }
}

@available(iOS 17.0, *)
private func removePIPForegroundInstanceMaskIOS17(cgImage: CGImage) -> UIImage? {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
        try handler.perform([request])
        guard let obs = request.results?.first as? VNInstanceMaskObservation,
              !obs.allInstances.isEmpty else { return nil }
        let buffer = try obs.generateMaskedImage(
            ofInstances: obs.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        return uiImageFromPixelBuffer(buffer, orientation: .up)
    } catch {
        return nil
    }
}

@available(iOS 16.0, *)
private func removePIPPersonSegmentationMaskIOS16(cgImage: CGImage) -> UIImage? {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    do {
        try handler.perform([request])
        guard let obs = request.results?.first as? VNPixelBufferObservation else { return nil }
        return blendSourceWithPersonMask(cgImage: cgImage, maskPixelBuffer: obs.pixelBuffer)
    } catch {
        return nil
    }
}

@available(iOS 16.0, *)
private func blendSourceWithPersonMask(cgImage: CGImage, maskPixelBuffer: CVPixelBuffer) -> UIImage? {
    let input = CIImage(cgImage: cgImage)
    var mask = CIImage(cvPixelBuffer: maskPixelBuffer)
    if mask.extent.width > 1, mask.extent.height > 1,
       abs(mask.extent.width - input.extent.width) > 0.5 || abs(mask.extent.height - input.extent.height) > 0.5 {
        let sx = input.extent.width / mask.extent.width
        let sy = input.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
    let clear = CIImage(color: .clear).cropped(to: input.extent)
    guard let blended = CIFilter(name: "CIBlendWithMask", parameters: [
        kCIInputImageKey: input,
        kCIInputBackgroundImageKey: clear,
        kCIInputMaskImageKey: mask
    ])?.outputImage,
          let cgOut = pipBackgroundRemovalCIContext.createCGImage(blended, from: blended.extent.integral)
    else { return nil }
    return UIImage(cgImage: cgOut, scale: 1, orientation: .up)
}

// MARK: - Carousel Studio chrome

/// Shared accent for Carousel Studio toolbars and selection rings. Prefer this over
/// `Color.accentColor` under `SlideTextEditorView`: the hierarchy applies
/// `.tint(.white)` for nav items, and on older iOS `accentColor` follows that tint
/// and reads as white instead of the intended blue.
private enum CarouselStudioChrome {
    static let accent = Color(red: 0.28, green: 0.64, blue: 1.0)
    static let navigationBarUIColor = UIColor(red: 5.0 / 255.0, green: 10.0 / 255.0, blue: 48.0 / 255.0, alpha: 1.0)
}

/// Clears the default navigation bar bottom shadow/hairline on OS versions where
/// SwiftUI's `toolbarBackground(_:for:)` still leaves a line above the content.
private struct CarouselStudioNavigationBarHairlineDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let nav = uiViewController.navigationController else { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = CarouselStudioChrome.navigationBarUIColor
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.compactAppearance = appearance
            nav.navigationBar.compactScrollEdgeAppearance = appearance
            nav.navigationBar.shadowImage = UIImage()
        }
    }
}

// MARK: - Asset loading

/// Ensures `PHImageManager.requestImage` resumes the continuation at most once (cancel / XPC oddities).
private final class CarouselPhotoLoadContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func resumeOnce(_ continuation: CheckedContinuation<UIImage?, Never>, returning value: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return }
        consumed = true
        continuation.resume(returning: value)
    }
}

/// Loads a `PHAsset` image by local identifier at the requested size. Shared
/// between `SocialPostStudioSheet` (initial slide load) and `SlideTextEditorView`
/// (loading a new photo into the PIP cluster via the "Add photo" picker). Kept
/// at file scope so both callers use identical request options and there's no
/// duplicated photo-framework boilerplate to drift out of sync.
private func loadCarouselAssetImage(identifier: String, size: CGSize, pixelCap: CGFloat = 3072) async -> UIImage? {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        #if DEBUG
        print("[CarouselStudio] loadCarouselAssetImage: empty localIdentifier after trim")
        #endif
        return nil
    }
    // `PHImageManager` expects a size in **pixels**; logical export points × screen scale
    // avoids undersized / odd results on older devices. Cap the long edge to limit memory.
    let scale = await MainActor.run { max(1.0, UIScreen.main.scale) }
    let rawW = max(1, size.width * scale)
    let rawH = max(1, size.height * scale)
    let target: CGSize = {
        guard rawW > pixelCap || rawH > pixelCap else {
            return CGSize(width: rawW, height: rawH)
        }
        let r = pixelCap / max(rawW, rawH)
        return CGSize(width: floor(rawW * r), height: floor(rawH * r))
    }()

    return await withCheckedContinuation { cont in
        let gate = CarouselPhotoLoadContinuationGate()
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [trimmed], options: nil)
        guard let asset = fetch.firstObject else {
            #if DEBUG
            print("[CarouselStudio] loadCarouselAssetImage: no PHAsset for id prefix \(trimmed.prefix(16))…")
            #endif
            cont.resume(returning: nil)
            return
        }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        opts.resizeMode = .fast
        PHImageManager.default().requestImage(for: asset, targetSize: target,
                                              contentMode: .aspectFill, options: opts) { img, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled {
                gate.resumeOnce(cont, returning: nil)
                return
            }
            #if DEBUG
            if img == nil {
                let err = info?[PHImageErrorKey] as? Error
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool
                print("[CarouselStudio] loadCarouselAssetImage: nil image cancelled=\(cancelled) degraded=\(String(describing: degraded)) err=\(String(describing: err)) target=\(target)")
            }
            #endif
            gate.resumeOnce(cont, returning: img)
        }
    }
}

/// Full-resolution load for carousel / Social Post Studio. Supports Photos assets,
/// on-disk app captures (`AppCapturePhotoService` ids), and signed cloud URLs.
private func loadRecapPhotoUIImage(photo: RecapPhoto, size: CGSize, pixelCap: CGFloat = 3072) async -> UIImage? {
    if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
        if lid.hasPrefix(AppCapturePhotoService.prefix) {
            let img = await MainActor.run {
                AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            #if DEBUG
            if img == nil { print("[CarouselStudio] loadRecapPhotoUIImage: AppCapture nil photo=\(photo.id)") }
            #endif
            guard let img else { return nil }
            return downscaleUIImageByPixelLongEdge(img, maxLongEdge: pixelCap)
        }
        let img = await loadCarouselAssetImage(identifier: lid, size: size, pixelCap: pixelCap)
        #if DEBUG
        if img == nil { print("[CarouselStudio] loadRecapPhotoUIImage: Photos nil photo=\(photo.id) localId.prefix=\(lid.prefix(12))…") }
        #endif
        return img
    }
    guard let cloud = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines), !cloud.isEmpty else {
        #if DEBUG
        print("[CarouselStudio] loadRecapPhotoUIImage: no local id or cloud photo=\(photo.id)")
        #endif
        return nil
    }
    do {
        let signedURL = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: cloud)
        let (data, _) = try await URLSession.shared.data(from: signedURL)
        let img = UIImage(data: data)
        #if DEBUG
        if img == nil { print("[CarouselStudio] loadRecapPhotoUIImage: cloud data not UIImage photo=\(photo.id)") }
        #endif
        return img
    } catch {
        #if DEBUG
        print("[CarouselStudio] loadRecapPhotoUIImage: cloud error photo=\(photo.id) \(error.localizedDescription)")
        #endif
        return nil
    }
}

// MARK: - Model

enum CarouselSlideKind {
    case cover
    case mapRoute
    /// Zoomed map beat before each place’s photos (cinematic-video style focus + muted sibling pins).
    case placeIntroMap
    case placeStop
}

private func isCarouselStudioMapKind(_ kind: CarouselSlideKind) -> Bool {
    kind == .mapRoute || kind == .placeIntroMap
}

/// Steps for JPEG share export — deck indices plus synthetic place slides when maps are omitted from share.
private enum ShareJPEGExportStep: Equatable {
    case deckIndex(Int)
    case recoveredPlace(stopID: UUID, photoID: UUID)
}

/// Raw index of the first `.mapRoute` / `.placeIntroMap` slide (Studio map watermark target).
private func indexOfFirstCarouselStudioMapSlide(in slides: [CarouselSlide]) -> Int? {
    slides.firstIndex(where: { isCarouselStudioMapKind($0.kind) })
}

// MARK: - Text Style Models

enum StudioFontDesign: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case serif = "Serif"
    case rounded = "Rounded"
    case mono = "Mono"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .default:  return .default
        case .serif:    return .serif
        case .rounded:  return .rounded
        case .mono:     return .monospaced
        }
    }
}

enum StudioTextColor: String, CaseIterable, Identifiable {
    case white, cream, yellow, orange, red, pink, magenta, purple,
         blue, cyan, teal, mint, green, brown, gray, black

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white:   return .white
        case .cream:   return Color(red: 1.00, green: 0.97, blue: 0.88)
        case .yellow:  return Color(red: 1.00, green: 0.92, blue: 0.30)
        case .orange:  return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .red:     return Color(red: 1.00, green: 0.29, blue: 0.29)
        case .pink:    return Color(red: 1.00, green: 0.40, blue: 0.70)
        case .magenta: return Color(red: 0.93, green: 0.27, blue: 0.83)
        case .purple:  return Color(red: 0.66, green: 0.40, blue: 1.00)
        case .blue:    return Color(red: 0.30, green: 0.55, blue: 1.00)
        case .cyan:    return Color(red: 0.38, green: 0.92, blue: 1.00)
        case .teal:    return Color(red: 0.20, green: 0.78, blue: 0.78)
        case .mint:    return Color(red: 0.56, green: 0.95, blue: 0.78)
        case .green:   return Color(red: 0.36, green: 0.85, blue: 0.45)
        case .brown:   return Color(red: 0.72, green: 0.53, blue: 0.38)
        case .gray:    return Color(red: 0.62, green: 0.64, blue: 0.68)
        case .black:   return Color(red: 0.08, green: 0.08, blue: 0.10)
        }
    }
}

/// Identifies which block in a slide is active in the editor. Text blocks
/// (`.primary`, `.secondary`) are independent draggable text layers; the
/// `.pipCluster` block is the stacked multi-photo cluster that replaces a
/// single hero when `slide.layout == .pip`.
enum SlideBlockID: Equatable, Hashable {
    case primary    // cover title / map heading / place name+subtitle
    case secondary  // map story / place caption
    case pipCluster // stacked PIP photo thumbnails (multi-photo mode)
}

/// Visual layout variant for place-stop slides (named to avoid conflict with PanoramaPlayerView.SlideLayout).
enum CarouselSlideLayout: String, CaseIterable, Identifiable {
    case single  // one full-bleed hero photo (default)
    case pip     // hero photo + 2–3 inset PIP thumbnails (default: top-trailing stack)
    case split   // top hero + bottom companion photo
    var id: String { rawValue }
}

enum CarouselSplitDividerStyle: String, CaseIterable, Identifiable {
    case straight
    case curve
    var id: String { rawValue }
}

/// Where place-stop **subtitle / title+caption** blocks sit relative to the inset photo cluster (PIP).
/// Hero imagery is unchanged; only overlay anchors and default offsets move.
enum CarouselPlaceZoneLayout: String, CaseIterable, Identifiable {
    /// Subtitle top-leading, name+caption bottom-leading; inset photos top-trailing (classic).
    case textLeadingPhotosTrailing
    /// Mirror: subtitle top-trailing, primary bottom-trailing; inset photos top-leading.
    case textTrailingPhotosLeading
    /// Subtitle top-center, primary bottom-center; inset photos top-trailing.
    case textCenterPhotosTrailing
    /// Like `textCenterPhotosTrailing`, but the bottom block sits slightly higher toward the frame center.
    case textCenterPhotosTrailingRaisedPrimary

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .textLeadingPhotosTrailing:
            return "Text left, photos right"
        case .textTrailingPhotosLeading:
            return "Text right, photos left"
        case .textCenterPhotosTrailing:
            return "Centered text, photos right"
        case .textCenterPhotosTrailingRaisedPrimary:
            return "Centered (raised bottom)"
        }
    }

    var pickerSubtitle: String {
        switch self {
        case .textLeadingPhotosTrailing:
            return "Subtitle top left · title bottom left · stack top right"
        case .textTrailingPhotosLeading:
            return "Subtitle top right · title bottom right · stack top left"
        case .textCenterPhotosTrailing:
            return "Subtitle top center · title bottom center · stack top right"
        case .textCenterPhotosTrailingRaisedPrimary:
            return "Like centered, with the bottom block nudged toward the middle"
        }
    }

    /// Normalized primary offset applied when the user picks this layout (fractions of slide size).
    var templatePrimaryOffset: CGSize {
        switch self {
        case .textCenterPhotosTrailingRaisedPrimary:
            return CGSize(width: 0, height: -0.08)
        default:
            return .zero
        }
    }

    fileprivate var secondaryOverlayAlignment: Alignment {
        switch self {
        case .textLeadingPhotosTrailing: return .topLeading
        case .textTrailingPhotosLeading: return .topTrailing
        case .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary: return .top
        }
    }

    fileprivate var primaryOverlayAlignment: Alignment {
        switch self {
        case .textLeadingPhotosTrailing: return .bottomLeading
        case .textTrailingPhotosLeading: return .bottomTrailing
        case .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary: return .bottom
        }
    }

    fileprivate var pipOverlayAlignment: Alignment {
        switch self {
        case .textTrailingPhotosLeading: return .topLeading
        default: return .topTrailing
        }
    }

    /// Ungrouped PIP thumbnails stack from this corner inside the cluster `ZStack`.
    fileprivate var pipZStackAlignment: Alignment {
        pipOverlayAlignment
    }

    fileprivate func primaryHorizontalFallback(for style: TextBlockStyle) -> HorizontalAlignment {
        switch self {
        case .textLeadingPhotosTrailing:
            return style.alignment.stackAlignment(fallback: .leading)
        case .textTrailingPhotosLeading:
            return style.alignment.stackAlignment(fallback: .trailing)
        case .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary:
            return style.alignment.stackAlignment(fallback: .center)
        }
    }

    fileprivate func secondaryHorizontalFallback(for style: TextBlockStyle) -> HorizontalAlignment {
        primaryHorizontalFallback(for: style)
    }

    fileprivate func primaryTextAlignmentFallback(for style: TextBlockStyle) -> TextAlignment {
        switch self {
        case .textLeadingPhotosTrailing:
            return style.resolvedMultilineAlignment(fallback: .leading)
        case .textTrailingPhotosLeading:
            return style.resolvedMultilineAlignment(fallback: .trailing)
        case .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary:
            return style.resolvedMultilineAlignment(fallback: .center)
        }
    }

    fileprivate func secondaryTextAlignmentFallback(for style: TextBlockStyle) -> TextAlignment {
        primaryTextAlignmentFallback(for: style)
    }

    /// Text zone presets shown when bulk-applying by photo layout mode (`CarouselSlideLayout`).
    static func bulkZonePresets(for slidePhotoLayout: CarouselSlideLayout) -> [CarouselPlaceZoneLayout] {
        switch slidePhotoLayout {
        case .single:
            return [.textLeadingPhotosTrailing, .textTrailingPhotosLeading,
                    .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary]
        case .pip:
            return CarouselPlaceZoneLayout.allCases
        case .split:
            // Split seams: list centered stacks first, then corner anchors.
            return [.textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary,
                    .textLeadingPhotosTrailing, .textTrailingPhotosLeading]
        }
    }
}

// MARK: - Place zone preset thumbnails (strip + sheets)

/// Schematic postcard for choosing `CarouselPlaceZoneLayout` without long text lists.
private struct PlaceZoneLayoutDiagramThumb: View {
    let zone: CarouselPlaceZoneLayout
    /// Drives whether the inset stack glyph is drawn.
    let slidePhotoLayout: CarouselSlideLayout
    var isSelected: Bool = false
    var width: CGFloat = 52
    var height: CGFloat = 66

    private var cornerR: CGFloat { min(width, height) * 0.11 }

    private var photoLayoutShort: String {
        switch slidePhotoLayout {
        case .single: return "Single"
        case .pip: return "Multi"
        case .split: return "Split"
        }
    }

    private func subtitlePill(width W: CGFloat, height H: CGFloat) -> some View {
        let w = max(14, W * 0.4)
        let h = max(8, H * 0.1)
        return RoundedRectangle(cornerRadius: h * 0.45, style: .continuous)
            .fill(Color.clear)
            .frame(width: w, height: h)
            .overlay(
                RoundedRectangle(cornerRadius: h * 0.45, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 0.95)
            )
    }

    private func primaryPill(width W: CGFloat, height H: CGFloat) -> some View {
        let w = max(18, W * 0.56)
        let h = max(10, H * 0.13)
        return RoundedRectangle(cornerRadius: h * 0.35, style: .continuous)
            .fill(Color.clear)
            .frame(width: w, height: h)
            .overlay(
                RoundedRectangle(cornerRadius: h * 0.35, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.0)
            )
    }

    @ViewBuilder
    private func pipStackGlyphs(W: CGFloat, H: CGFloat) -> some View {
        let cw = max(12, W * 0.19)
        let ch = max(11, H * 0.12)
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: cw * 0.15, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: cw, height: ch * 0.88)
                    .overlay(
                        RoundedRectangle(cornerRadius: cw * 0.15, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 0.95)
                    )
            }
        }
        .padding(W * 0.055)
        .allowsHitTesting(false)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(isSelected ? CarouselStudioChrome.accent.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .strokeBorder(
                            isSelected ? CarouselStudioChrome.accent : Color.white.opacity(0.42),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            GeometryReader { geo in
                let W = geo.size.width
                let H = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: cornerR * 0.75, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerR * 0.75, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.9)
                        )
                        .padding(W * 0.045)
                        .allowsHitTesting(false)

                    // Subtitle
                    switch zone {
                    case .textLeadingPhotosTrailing:
                        subtitlePill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, W * 0.07)
                            .padding(.top, H * 0.07)
                    case .textTrailingPhotosLeading:
                        subtitlePill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, W * 0.07)
                            .padding(.top, H * 0.07)
                    case .textCenterPhotosTrailing, .textCenterPhotosTrailingRaisedPrimary:
                        subtitlePill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, H * 0.07)
                    }

                    // Primary
                    switch zone {
                    case .textLeadingPhotosTrailing:
                        primaryPill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.leading, W * 0.07)
                            .padding(.bottom, H * 0.22)
                    case .textTrailingPhotosLeading:
                        primaryPill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, W * 0.07)
                            .padding(.bottom, H * 0.22)
                    case .textCenterPhotosTrailing:
                        primaryPill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, H * 0.22)
                    case .textCenterPhotosTrailingRaisedPrimary:
                        primaryPill(width: W, height: H)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, H * 0.32)
                    }

                    if slidePhotoLayout == .pip {
                        let pipTopOffset: CGFloat = (zone == .textCenterPhotosTrailing || zone == .textCenterPhotosTrailingRaisedPrimary) ? H * 0.22 : 0
                        pipStackGlyphs(W: W, H: H)
                            .padding(.top, pipTopOffset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: zone.pipOverlayAlignment)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(zone.pickerTitle), \(photoLayoutShort) mode")
        .accessibilityHint(zone.pickerSubtitle)
    }
}

/// Pan/zoom for a photo in a fixed slot (split top/bottom). Values are resolution‑independent:
/// `fillScale` ≥ 1 multiplies the minimum aspect‑fill scale; pans are −1…1 of the range at that scale.
struct StudioImageFraming: Equatable {
    /// Upper bound for pinch zoom in Carousel Studio reposition (split + PIP).
    static let maxFillScale: CGFloat = 8

    var fillScale: CGFloat
    var panX: CGFloat
    var panY: CGFloat

    static let neutral = StudioImageFraming(fillScale: 1, panX: 0, panY: 0)

    func clamped() -> StudioImageFraming {
        StudioImageFraming(
            fillScale: min(max(fillScale, 1), Self.maxFillScale),
            panX: min(max(panX, -1), 1),
            panY: min(max(panY, -1), 1)
        )
    }

    /// `nil` when equivalent to aspect‑fill centered (default split appearance).
    var storedFormOrNil: StudioImageFraming? {
        let c = clamped()
        if abs(c.fillScale - 1) < 0.001, abs(c.panX) < 0.001, abs(c.panY) < 0.001 { return nil }
        return c
    }

    static func framedMetrics(
        image: UIImage,
        slotW: CGFloat,
        slotH: CGFloat,
        framing: StudioImageFraming
    ) -> (rw: CGFloat, rh: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let f = framing.clamped()
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, slotW > 0, slotH > 0 else {
            return (max(slotW, 1), max(slotH, 1), 0, 0)
        }
        let sBase = max(slotW / iw, slotH / ih)
        let s = sBase * f.fillScale
        let rw = iw * s
        let rh = ih * s
        let excessX = max(0, (rw - slotW) * 0.5)
        let excessY = max(0, (rh - slotH) * 0.5)
        let offsetX = f.panX * excessX
        let offsetY = f.panY * excessY
        return (rw, rh, offsetX, offsetY)
    }

    static func clampFraming(_ framing: StudioImageFraming, image: UIImage, slotW: CGFloat, slotH: CGFloat) -> StudioImageFraming {
        var f = framing.clamped()
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, slotW > 0, slotH > 0 else { return .neutral }
        let sBase = max(slotW / iw, slotH / ih)
        let s = sBase * f.fillScale
        let rw = iw * s
        let rh = ih * s
        let excessX = max(0, (rw - slotW) * 0.5)
        let excessY = max(0, (rh - slotH) * 0.5)
        if excessX <= 0.5 { f.panX = 0 } else { f.panX = min(max(f.panX, -1), 1) }
        if excessY <= 0.5 { f.panY = 0 } else { f.panY = min(max(f.panY, -1), 1) }
        return f
    }
}

/// Chooses the largest preview rect that fits the given container while keeping the slot’s
/// width÷height ratio (`slotAspectWH`). Caps height so the editor can use up to ~half the
/// screen — easier to see the full crop than sizing from width alone on tall phones.
private func studioRepositionSlotDimensions(
    container: CGSize,
    slotAspectWH: CGFloat,
    sideMargin: CGFloat = 20
) -> (slotW: CGFloat, slotH: CGFloat) {
    let aspect = max(slotAspectWH, 0.01)
    let maxW = max(40, container.width - sideMargin * 2)
    // Nav + hint + segmented picker + Reset + padding (approximate).
    let verticalChromeReserve: CGFloat = 210
    let maxH = max(
        120,
        min(container.height * 0.5, container.height - verticalChromeReserve)
    )
    var slotW = min(maxW, maxH * aspect)
    var slotH = slotW / aspect
    if slotH > maxH {
        slotH = maxH
        slotW = slotH * aspect
    }
    if slotW > maxW {
        slotW = maxW
        slotH = slotW / aspect
    }
    return (max(slotW, 40), max(slotH, 40))
}

/// How inset PIP thumbnails are arranged when `CarouselSlideLayout` is `.pip`.
enum CarouselPIPClusterStackStyle: String, CaseIterable, Identifiable {
    /// Thumbnails stacked top-to-bottom along the trailing edge (default; anchored top-trailing).
    case vertical
    /// Thumbnails in a row, growing toward the leading edge from the top-trailing corner.
    case horizontal
    var id: String { rawValue }
}

/// Visual mask for each inset PIP thumbnail (`.pip` multi-photo cluster only).
enum CarouselPIPThumbMaskStyle: String, CaseIterable, Identifiable {
    case roundedRect
    case circle
    var id: String { rawValue }
    var optionsStripLabel: String {
        switch self {
        case .roundedRect: return "Rounded"
        case .circle: return "Circle"
        }
    }
}

/// How much readable contrast sits behind carousel text on busy photos.
/// In Carousel Studio, tap a **selected** text block to cycle **Off → Dark → Light → Off**.
/// Same values are stored in `TextBlockStyle.background` for export / previews.
enum StudioTextBackground: String, CaseIterable {
    case none, darkPill, lightPill

    func next() -> StudioTextBackground {
        switch self {
        case .none:      return .darkPill
        case .darkPill:  return .lightPill
        case .lightPill: return .none
        }
    }
}

/// Identifies which backing field receives caption edits from the inline text editor.
private enum PlaceSlideCaptionTarget { case none }

/// Categories in the bottom style tab bar. Selecting one opens a drop-up panel
/// with horizontally-scrollable options for that category.
private enum StyleCategory: String, CaseIterable, Identifiable {
    case color   = "Color"
    case font    = "Font Style"
    case format  = "Format"
    case size    = "Font Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .color:    return "paintpalette.fill"
        case .font:     return "textformat"
        case .size:     return "textformat.size"
        case .format:   return "bold.italic.underline"
        }
    }
}

/// Categories in the bottom tab bar when the PIP photo cluster is selected.
/// Order is left-to-right: Border, Shape, Size, Remove BG. Border picks the outline
/// color; Shape toggles rounded vs circular inset thumbnails.
/// Add and remove are separate scrollable pills — see `pipAddPhotosTabButton` /
/// `pipRemovePhotosTabButton`.
private enum PIPStyleCategory: String, CaseIterable, Identifiable {
    case border     = "Border"
    case shape      = "Shape"
    case size       = "Size"
    case background = "Remove BG"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .border:      return "paintpalette.fill"
        case .shape:       return "square.on.circle"
        case .size:        return "aspectratio"
        case .background: return "person.crop.rectangle.stack"
        }
    }
}

/// Case transformation applied to the rendered text. `none` leaves the text
/// exactly as the user typed it (the default); the others apply `.textCase()`
/// without mutating the underlying string.
enum StudioTextCase: String, CaseIterable, Identifiable {
    case none, upper, lower

    var id: String { rawValue }

    var textCase: Text.Case? {
        switch self {
        case .none:  return nil
        case .upper: return .uppercase
        case .lower: return .lowercase
        }
    }
}

/// User-chosen multiline alignment. `.natural` means "use the block's
/// built-in alignment" (center for cover titles, leading for everything
/// else) — the value a freshly-initialized style should have so we don't
/// silently change how existing blogs render.
enum StudioTextAlignment: String, CaseIterable, Identifiable {
    case natural, leading, center, trailing

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .natural:  return "text.alignleft"
        case .leading:  return "text.alignleft"
        case .center:   return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    /// Maps to a VStack/HStack `HorizontalAlignment` so a multi-line stack
    /// (e.g. place name + subtitle) actually shifts its rows — the outer
    /// stack owns row placement, not `multilineTextAlignment`.
    func stackAlignment(fallback: HorizontalAlignment) -> HorizontalAlignment {
        switch self {
        case .natural:  return fallback
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

/// Style settings for a single independent text block.
struct TextBlockStyle: Equatable {
    var sizeScale: CGFloat = 1.0      // multiplier, 0.6 – 1.8
    var textColor: StudioTextColor = .white
    var fontDesign: StudioFontDesign = .default
    // Format toggles from the Format drop-up panel. Each is a simple
    // additive modifier applied at render time — defaults of `false` /
    // `.natural` preserve the exact visual each text block had before
    // this feature shipped.
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var isStrikethrough: Bool = false
    var textCase: StudioTextCase = .none
    var alignment: StudioTextAlignment = .natural
    /// Extra contrast behind the text on busy photos (gradient bar; see
    /// `StudioTextReadableBehindModifier`). Default `.none`. Tap the **selected**
    /// block in Carousel Studio to cycle Off / Dark / Light.
    var background: StudioTextBackground = .none
    /// Normalized displacement from the block's natural anchor position, expressed as
    /// a fraction of the slide's own dimensions (e.g. `width = 0.10` ⇒ 10% of the slide
    /// width to the right of the anchor). `.zero` means the block sits at its layout
    /// anchor (e.g. centered / top-leading).
    ///
    /// Storing a normalized fraction (rather than absolute points) keeps the position
    /// consistent across surfaces of different sizes — the editor renders slides at
    /// ~297pt wide, but the studio preview renders 4:5 Post at ~260pt and 9:16 Story/Reel
    /// at ~183pt. Absolute-point offsets captured in the editor would land in different
    /// relative spots on each preview (and could push the block out of the clipped slide
    /// entirely on Story/Reel), making it look like edits "didn't apply."
    var offset: CGSize = .zero
}

/// Holds per-block styles for a slide. Each block is independently styled and draggable.
struct TextOverlayStyle: Equatable {
    var primary: TextBlockStyle = TextBlockStyle()    // title / heading / name+subtitle
    var secondary: TextBlockStyle = TextBlockStyle()  // story / caption
}

extension TextOverlayStyle {
    /// Starting typography for `.placeStop` slides in the social-post studio.
    /// The Font-Size readout is `sizeScale × 20pt`, so `0.7` snaps exactly
    /// to the 14pt marker used across the place name / caption (primary
    /// block) and the "city, country" subtitle (secondary block).
    static let placeStopDefault: TextOverlayStyle = {
        var style = TextOverlayStyle()
        style.primary.sizeScale = 0.7
        style.secondary.sizeScale = 0.7
        return style
    }()
}

private extension TextBlockStyle {
    /// Copies font, color, size, and all Format-panel toggles from `source`;
    /// leaves `offset` unchanged. Format toggles are treated as typography so
    /// "Apply typography to all slides" pulls a consistent look across every
    /// slide in the carousel.
    mutating func mergeTypography(from source: TextBlockStyle) {
        fontDesign = source.fontDesign
        textColor = source.textColor
        sizeScale = source.sizeScale
        isBold = source.isBold
        isItalic = source.isItalic
        isUnderlined = source.isUnderlined
        isStrikethrough = source.isStrikethrough
        textCase = source.textCase
        alignment = source.alignment
        background = source.background
    }

    /// Copies `offset` from `source`; leaves typography unchanged.
    mutating func mergeLayout(from source: TextBlockStyle) {
        offset = source.offset
    }

    /// Resolves the user's alignment choice. `.natural` falls back to the
    /// block's built-in default (`fallback`), so pre-existing slides render
    /// identically until the user explicitly picks a new alignment.
    func resolvedMultilineAlignment(fallback: TextAlignment) -> TextAlignment {
        switch alignment {
        case .natural:  return fallback
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

/// Applies the Format-panel toggles (bold/italic/underline/strikethrough/case)
/// to any `Text` view. Alignment is handled separately by the caller because
/// `multilineTextAlignment` is sensitive to the surrounding VStack's alignment
/// and the text block's anchor (leading / center).
private struct StudioTextFormatModifier: ViewModifier {
    let style: TextBlockStyle

    func body(content: Content) -> some View {
        content
            .italic(style.isItalic)
            .underline(style.isUnderlined)
            .strikethrough(style.isStrikethrough)
            .textCase(style.textCase.textCase)
    }
}

private extension View {
    /// Apply the Format-panel italic / underline / strikethrough / case modifiers.
    /// Bold and alignment are applied at the call site because they interact
    /// with the specific `Font` and layout being used.
    func studioTextFormat(_ style: TextBlockStyle) -> some View {
        modifier(StudioTextFormatModifier(style: style))
    }
}

/// Returns the rendered font weight: if the user toggled Bold, override the
/// natural weight with `.black` for heading-level text (or `.bold` for
/// body-level text). Otherwise use the block's natural weight.
private func studioFontWeight(base: Font.Weight, isBold: Bool) -> Font.Weight {
    guard isBold else { return base }
    switch base {
    case .heavy, .black: return .black
    case .bold:          return .black
    case .semibold:      return .bold
    default:             return .bold
    }
}

/// Resolves the foreground color for a text layer. When a **behind-text**
/// contrast fill is on, we force white (on dark) or black (on light) so the
/// label stays readable on the frosted bar. `naturalOpacity` keeps caption
/// hierarchy (e.g. subtitle at 0.85) when fill is off.
private func studioEffectiveForegroundColor(_ style: TextBlockStyle,
                                            naturalOpacity: Double = 1.0) -> Color {
    switch style.background {
    case .none:      return style.textColor.color.opacity(naturalOpacity)
    case .darkPill:  return Color.white.opacity(naturalOpacity)
    case .lightPill: return Color.black.opacity(naturalOpacity)
    }
}

/// Soft gradient + hairline behind carousel text. Tap the **selected** block
/// on the slide to cycle Off / Dark / Light. Avoids flat “pill” blocks and
/// avoids `Material` (which can render inconsistently in `ImageRenderer` exports).
///
/// **Padding is always applied** (same as Dark/Light) even when the mode is **Off**, so
/// the block’s layout size / `naturalRect` does not change when toggling the bar —
/// that keeps drag clamping and committed offsets stable.
private struct StudioTextReadableBehindModifier: ViewModifier {
    let style: TextBlockStyle
    let cornerRadius: CGFloat
    let hPadding: CGFloat
    let vPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(fill)
    }

    @ViewBuilder
    private var fill: some View {
        switch style.background {
        case .none:
            Color.clear
        case .darkPill:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.50),
                            Color.black.opacity(0.76),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        case .lightPill:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.86),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private extension View {
    /// Optional frosted bar behind block text (busy-photo readability).
    func studioTextPill(_ style: TextBlockStyle,
                        cornerRadius: CGFloat,
                        hPadding: CGFloat,
                        vPadding: CGFloat) -> some View {
        modifier(StudioTextReadableBehindModifier(style: style,
                                                  cornerRadius: cornerRadius,
                                                  hPadding: hPadding,
                                                  vPadding: vPadding))
    }
}

private struct DiagonalRoundedBadgeShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private enum CurvedSplitSeamGeometry {
    static let c1x: CGFloat = 0.28
    static let c2x: CGFloat = 0.72

    static func amplitude(for rect: CGRect) -> CGFloat {
        min(22, max(10, rect.width * 0.038))
    }
}

/// Horizontal curved seam used only for **map / photo** split outline (matches mask geometry).
private struct CurvedSplitDividerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let curveHeight = min(CurvedSplitSeamGeometry.amplitude(for: rect), rect.height * 0.45)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c1x, y: rect.midY - curveHeight),
            control2: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c2x, y: rect.midY + curveHeight)
        )
        return path
    }
}

/// Curved mask for the top split slot. The seam bows upward near the leading side
/// and returns to the baseline so the slot edge is no longer perfectly straight.
private struct CurvedSplitTopMaskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let seamLift = CurvedSplitSeamGeometry.amplitude(for: rect)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c2x, y: rect.maxY + seamLift),
            control2: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c1x, y: rect.maxY - seamLift)
        )
        path.closeSubpath()
        return path
    }
}

/// Curved mask for the bottom split slot. Mirrors the top seam so both photos
/// appear carved by the same divider rather than two straight rectangles.
private struct CurvedSplitBottomMaskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let seamDrop = CurvedSplitSeamGeometry.amplitude(for: rect)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c1x, y: rect.minY - seamDrop),
            control2: CGPoint(x: rect.width * CurvedSplitSeamGeometry.c2x, y: rect.minY + seamDrop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Per-photo style overrides used when `slide.pipIsUngrouped == true`.
/// Nil fields fall through to the slide-level cluster defaults.
struct PIPPhotoStyle {
    var borderColor: StudioTextColor = .white
    var borderEnabled: Bool = true
    var thumbMaskStyle: CarouselPIPThumbMaskStyle = .roundedRect
    /// Ungrouped Multi only: when non-nil, scales this inset’s footprint; `nil` uses `pipClusterSizeScale`.
    var sizeScale: CGFloat? = nil
}

struct CarouselSlide: Identifiable {
    let id: String
    let kind: CarouselSlideKind
    var isSelected = true
    var heroImage: UIImage?
    var coverTitle: String?
    var mapSnapshot: UIImage?
    /// Short month/day for map slides (e.g. "Mar 13"); used in Slides Management labels only.
    var mapShortDateLine: String? = nil
    var dayInfoLine1: String?
    var dayInfoLine2: String?
    var placeStop: PlaceStop?
    var dayTitle: String?
    var photoCaption: String?
    /// `true` when this slide represents the first included photo of its place stop.
    /// Only the first slide falls back to the place story caption when the photo has no caption.
    var isFirstPhotoOfStop: Bool = false
    var dayStory: String?
    var textStyle: TextOverlayStyle = TextOverlayStyle()
    /// When true, the primary text block (title / heading / place name) is hidden on this slide.
    var isPrimaryHidden: Bool = false
    /// When true, the secondary text block (story / caption) is hidden on this slide.
    var isSecondaryHidden: Bool = false
    /// Layout variant — meaningful for `.placeStop` (single / PIP / split) and
    /// `.placeIntroMap` (single = full‑bleed map; split = map over photo with
    /// shared split seam + bottom framing like place slides).
    var layout: CarouselSlideLayout = .single
    /// Text block anchors vs PIP cluster for `.placeStop` slides (single / pip / split hero).
    var placeZoneLayout: CarouselPlaceZoneLayout = .textLeadingPhotosTrailing
    /// Additional photo thumbnails used when `layout == .pip`. Pre-loaded at export size.
    var pipImages: [UIImage] = []
    /// Parallel array to `pipImages` holding the `RecapPhoto.id` of each thumbnail.
    /// Nil entries are allowed for legacy callers that didn't track IDs; the editor
    /// only uses them to compute the "available to add" set, so a missing ID simply
    /// excludes that slot from that calculation (it never crashes).
    var pipPhotoIDs: [UUID] = []
    /// Normalized position offset for the PIP cluster, stored as a fraction of slide dimensions.
    /// `.zero` keeps the cluster at its default top-trailing anchor position.
    var pipOffset: CGSize = .zero
    /// Index-aligned with `pipImages` / `pipPhotoIDs` — framing for each inset thumbnail.
    var pipThumbnailFramings: [StudioImageFraming?] = []
    /// Outline color painted around each PIP thumbnail. Defaults to white to
    /// preserve the classic "photo print" look; users can change it per slide
    /// in the edit toolbar when the PIP cluster is selected.
    var pipBorderColor: StudioTextColor = .white
    /// Whether the PIP thumbnail outline is drawn at all. When `false`, each
    /// thumbnail renders without a border regardless of `pipBorderColor`. Users
    /// toggle this via the "no border" option at the start of the Border
    /// color strip.
    var pipBorderEnabled: Bool = true
    /// How many inset PIP thumbnails to render (1 ... 3; hero + insets = up to four photos per Multi group).
    /// Clamped at render time against available images so visibility can be lowered without discarding data.
    var pipVisibleCount: Int = 3
    /// Row vs column layout for the inset PIP thumbnails (`.pip` only).
    var pipClusterStackStyle: CarouselPIPClusterStackStyle = .vertical
    /// Scales PIP thumbnail footprint relative to the default (~30% of slide width).
    /// Driven from the multi-photo toolbar Size strip; `.pip` layout only.
    var pipClusterSizeScale: CGFloat = 1.0
    /// Rounded-rectangle insets (classic) vs circular thumbnails. `.pip` only.
    var pipThumbMaskStyle: CarouselPIPThumbMaskStyle = .roundedRect
    /// When `true`, slots with a non-nil entry in `pipProcessedImages` render subject cutouts.
    var pipBackgroundRemoved: Bool = false
    /// Optional per-slot cutouts (`nil` = use original `pipImages[i]`). Populated async when
    /// the user enables Remove background for that inset (selected slot when separated).
    var pipProcessedImages: [UIImage?] = []
    /// When `true`, each PIP thumbnail is positioned independently on the slide
    /// rather than moving as a single cluster. See `pipPhotoOffsets`.
    var pipIsUngrouped: Bool = false
    /// Normalized per-photo offsets used when `pipIsUngrouped == true`.
    /// Index-aligned with `pipImages`. `.zero` means the natural top-trailing anchor.
    var pipPhotoOffsets: [CGSize] = []
    /// Per-photo style overrides for border color/enabled and shape when ungrouped.
    /// Nil at a given index means "inherit cluster-level defaults".
    var pipPhotoStyles: [PIPPhotoStyle?] = []
    /// Ungrouped Multi only: bottom→top **paint order** for inset indices. Updated only when
    /// the user selects an inset (`onSelectPIPPhoto`); hero taps / pager never mutate this.
    var pipUngroupedZOrder: [Int] = []

    /// Bottom-to-top indices to paint in a `ZStack` so the last entry is topmost.
    func pipUngroupedDrawOrder(visibleCount visIn: Int) -> [Int] {
        let vis = min(max(0, visIn), pipImages.count, 3)
        guard pipIsUngrouped, vis > 0 else {
            return Array(0..<vis)
        }
        var seen = Set<Int>()
        var ordered: [Int] = []
        for x in pipUngroupedZOrder where x >= 0 && x < vis && !seen.contains(x) {
            ordered.append(x)
            seen.insert(x)
        }
        for i in 0..<vis where !seen.contains(i) {
            ordered.append(i)
            seen.insert(i)
        }
        return ordered
    }

    /// Returns the effective border+shape style for the photo at `index`,
    /// merging any per-photo override with the cluster-level defaults.
    func effectivePIPPhotoStyle(at index: Int) -> PIPPhotoStyle {
        let override = index < pipPhotoStyles.count ? pipPhotoStyles[index] : nil
        var style = PIPPhotoStyle()
        style.borderColor    = override?.borderColor    ?? pipBorderColor
        style.borderEnabled  = override?.borderEnabled  ?? pipBorderEnabled
        style.thumbMaskStyle = override?.thumbMaskStyle ?? pipThumbMaskStyle
        style.sizeScale      = override?.sizeScale
        return style
    }

    /// Footprint scale for inset `index` (grouped cluster uses `pipClusterSizeScale` only).
    func effectivePIPPhotoSizeScale(at index: Int) -> CGFloat {
        guard pipIsUngrouped, index >= 0 else {
            return StudioPIPClusterSize.clampOnly(pipClusterSizeScale)
        }
        let override = index < pipPhotoStyles.count ? pipPhotoStyles[index] : nil
        if let s = override?.sizeScale {
            return StudioPIPClusterSize.clampOnly(s)
        }
        return StudioPIPClusterSize.clampOnly(pipClusterSizeScale)
    }

    /// Chooses the correct image array for rendering and export. Per-slot cutouts when present.
    var effectivePIPImages: [UIImage] {
        guard pipBackgroundRemoved else { return pipImages }
        let n = pipImages.count
        guard n > 0, pipProcessedImages.count == n else { return pipImages }
        return pipImages.indices.map { i in
            if let cut = pipProcessedImages[i] { return cut }
            return pipImages[i]
        }
    }

    /// Border stroke for one inset: off when this slot uses a subject cutout.
    func effectivePIPInsetBorderEnabled(at index: Int) -> Bool {
        guard pipBorderEnabled else { return false }
        if pipBackgroundRemoved,
           index >= 0,
           index < pipProcessedImages.count,
           pipProcessedImages[index] != nil {
            return false
        }
        return true
    }

    /// `RecapPhoto.id` of the current hero photo. Lets the "Add photo" picker
    /// exclude it from the available list so users don't duplicate the hero
    /// into the cluster.
    var heroPhotoID: UUID? = nil
    /// Optional second photo shown in the bottom half when `layout == .split`.
    var splitBottomImage: UIImage? = nil
    /// `RecapPhoto.id` of `splitBottomImage`.
    var splitBottomPhotoID: UUID? = nil
    /// Visual style for the top/bottom split seam.
    var splitDividerStyle: CarouselSplitDividerStyle = .curve
    /// Framing for the hero in the **top** split half (session‑local studio state).
    var splitTopFraming: StudioImageFraming? = nil
    /// Framing for `splitBottomImage` in the **bottom** split half.
    var splitBottomFraming: StudioImageFraming? = nil
    /// 1-based sequential stop number across all days; when set, a white POI marker is shown before the place name.
    var stopIndex: Int? = nil
    /// Legacy full‑bleed place‑intro strip (thumbnails). New decks use `layout == .split`
    /// with `splitBottomImage` instead; non‑empty here is shown only when `layout != .split`.
    var placeIntroBottomPhotos: [UIImage] = []

    var caption: String? {
        guard kind == .placeStop, let placeStop else { return nil }
        if let photo = photoCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !photo.isEmpty {
            return photo
        }
        guard isFirstPhotoOfStop else { return nil }
        return [placeStop.placeNarrative, placeStop.overallStory, placeStop.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Multi (PIP) shows one hero plus up to three inset thumbnails — four photos per group.
private enum CarouselStudioMultiPhotoGroup {
    static let maxPhotos = 4
    static let maxInsetThumbnails = maxPhotos - 1
}

/// Photo IDs represented on a `.pip` slide (hero + assigned inset slots, not merely visible count).
private func multiClusterPhotoIDs(for slide: CarouselSlide) -> Set<UUID> {
    guard slide.layout == .pip, let hero = slide.heroPhotoID else { return [] }
    var ids = [hero]
    ids.append(contentsOf: slide.pipPhotoIDs.prefix(CarouselStudioMultiPhotoGroup.maxInsetThumbnails))
    return Set(ids)
}

private func placeStopSiblingIndices(stopID: UUID, in slides: [CarouselSlide]) -> [Int] {
    slides.indices.filter {
        slides[$0].kind == .placeStop && slides[$0].placeStop?.id == stopID
    }.sorted()
}

/// Deck-order indices for a Multi cluster: `primary` + up to three **following** `.single` slides; stops at the first non-single.
private func multiClusterCandidateIndices(from primaryIndex: Int, stopID: UUID, in slides: [CarouselSlide]) -> [Int] {
    let siblings = placeStopSiblingIndices(stopID: stopID, in: slides)
    guard let start = siblings.firstIndex(of: primaryIndex) else { return [] }
    var cluster = [primaryIndex]
    var i = start + 1
    while cluster.count < CarouselStudioMultiPhotoGroup.maxPhotos, i < siblings.count {
        let idx = siblings[i]
        guard slides[idx].layout == .single else { break }
        cluster.append(idx)
        i += 1
    }
    return cluster
}

/// Single / Multi / Split row: not on absorbed slides; on Multi/Split so you can exit; on Single only if another Single follows in deck order.
private func placeStopOffersLayoutModes(at index: Int, in slides: [CarouselSlide]) -> Bool {
    guard slides.indices.contains(index),
          slides[index].kind == .placeStop,
          !isSlideHiddenBySiblingPIP(at: index, in: slides) else { return false }
    switch slides[index].layout {
    case .pip, .split:
        return true
    case .single:
        guard let stopID = slides[index].placeStop?.id else { return false }
        return multiClusterCandidateIndices(from: index, stopID: stopID, in: slides).count > 1
    }
}

/// Per-slide PIP payload for re-entering Multi: next singles after this slide only (up to three insets).
private func repopulatePipPayloadForSlide(at index: Int, stopID: UUID, slides: inout [CarouselSlide]) {
    guard slides.indices.contains(index), slides[index].kind == .placeStop else { return }
    let insetIndices = Array(multiClusterCandidateIndices(from: index, stopID: stopID, in: slides).dropFirst())
    let pipAligned: [(UUID, UIImage)] = insetIndices.compactMap { si in
        guard let pid = slides[si].heroPhotoID, let img = slides[si].heroImage else { return nil }
        return (pid, img)
    }
    slides[index].pipPhotoIDs = pipAligned.map(\.0)
    slides[index].pipImages = pipAligned.map(\.1)
}

private func repopulatePipPayloadsForPlaceStop(stopID: UUID, slides: inout [CarouselSlide]) {
    for i in placeStopSiblingIndices(stopID: stopID, in: slides) where slides[i].layout == .single {
        repopulatePipPayloadForSlide(at: i, stopID: stopID, slides: &slides)
    }
}

/// Group current slide + following single slides (≤4). Does not move `heroPhotoID` between slides.
private func applyMultiLayoutGrouping(primaryIndex: Int, slides: inout [CarouselSlide]) {
    guard slides.indices.contains(primaryIndex),
          slides[primaryIndex].kind == .placeStop,
          slides[primaryIndex].layout == .pip,
          let stopID = slides[primaryIndex].placeStop?.id else { return }

    let clusterIndices = multiClusterCandidateIndices(from: primaryIndex, stopID: stopID, in: slides)
    guard clusterIndices.count > 1 else { return }

    let insetIndices = Array(clusterIndices.dropFirst())
    let pipAligned: [(UUID, UIImage)] = insetIndices.compactMap { si in
        guard let pid = slides[si].heroPhotoID, let img = slides[si].heroImage else { return nil }
        return (pid, img)
    }
    slides[primaryIndex].pipPhotoIDs = pipAligned.map(\.0)
    slides[primaryIndex].pipImages = pipAligned.map(\.1)
    slides[primaryIndex].pipThumbnailFramings = []
    slides[primaryIndex].pipProcessedImages = []
    slides[primaryIndex].pipVisibleCount = pipAligned.isEmpty
        ? 1
        : min(
            CarouselStudioMultiPhotoGroup.maxInsetThumbnails,
            max(1, min(slides[primaryIndex].pipVisibleCount, pipAligned.count))
        )

    let clusterSet = Set(clusterIndices)
    for si in placeStopSiblingIndices(stopID: stopID, in: slides) {
        if clusterSet.contains(si) {
            if si == primaryIndex {
                slides[si].isSelected = true
            } else {
                slides[si].layout = .single
                slides[si].isSelected = false
                slides[si].pipImages = []
                slides[si].pipPhotoIDs = []
                slides[si].pipThumbnailFramings = []
                slides[si].pipBackgroundRemoved = false
                slides[si].pipProcessedImages = []
            }
        }
    }
}

/// Ungroup Multi without reassigning heroes (avoids duplicate / missing slides after mode changes).
private func releaseMultiLayoutGrouping(primaryIndex: Int, slides: inout [CarouselSlide]) {
    guard slides.indices.contains(primaryIndex),
          slides[primaryIndex].layout == .pip,
          let stopID = slides[primaryIndex].placeStop?.id else { return }
    let clusterPhotos = multiClusterPhotoIDs(for: slides[primaryIndex])
    for si in placeStopSiblingIndices(stopID: stopID, in: slides) {
        guard let pid = slides[si].heroPhotoID, clusterPhotos.contains(pid) else { continue }
        slides[si].layout = .single
        slides[si].isSelected = true
        if si != primaryIndex {
            slides[si].pipImages = []
            slides[si].pipPhotoIDs = []
            slides[si].pipThumbnailFramings = []
            slides[si].pipBackgroundRemoved = false
            slides[si].pipProcessedImages = []
        }
    }
}

private func releaseSplitLayoutGrouping(splitIndex: Int, slides: inout [CarouselSlide]) {
    guard slides.indices.contains(splitIndex),
          slides[splitIndex].layout == .split,
          let stopID = slides[splitIndex].placeStop?.id,
          let bottomID = slides[splitIndex].splitBottomPhotoID else { return }
    for si in placeStopSiblingIndices(stopID: stopID, in: slides) {
        if slides[si].heroPhotoID == bottomID {
            slides[si].layout = .single
            slides[si].isSelected = true
        }
    }
    slides[splitIndex].splitBottomImage = nil
    slides[splitIndex].splitBottomPhotoID = nil
    slides[splitIndex].splitTopFraming = nil
    slides[splitIndex].splitBottomFraming = nil
}

/// Returns `true` when the slide at `index` is a `.placeStop` slide in `.single`
/// layout whose photo is already represented inside a sibling's grouped mode
/// (`.pip` or `.split`) for the same stop. The preview and export pipelines
/// hide only photos in that Multi cluster (up to four), not every photo at the stop;
/// flipping the sibling back to `.single` resurfaces them.
private func isSlideHiddenBySiblingPIP(at index: Int, in slides: [CarouselSlide]) -> Bool {
    guard slides.indices.contains(index) else { return false }
    let slide = slides[index]
    guard slide.kind == .placeStop,
          slide.layout == .single,
          let stopID = slide.placeStop?.id,
          let photoID = slide.heroPhotoID else { return false }
    return slides.contains { other in
        guard other.id != slide.id,
              other.kind == .placeStop,
              other.placeStop?.id == stopID,
              other.isSelected else { return false }
        if other.layout == .pip {
            return multiClusterPhotoIDs(for: other).contains(photoID)
        }
        if other.layout == .split {
            guard let hiddenPhotoID = other.splitBottomPhotoID else { return false }
            return hiddenPhotoID == photoID
        }
        return false
    }
}


/// Export order matching `SocialPostStudioSheet.orderedExportSlideIndices` — PIP-collapsed siblings
/// excluded and only `isSelected` slides; Reel / single-slide mode takes the first selected only.
private func orderedStudioExportSlideIndices(slides: [CarouselSlide], singleSlideExport: Bool) -> [Int] {
    let linear = slides.enumerated().compactMap { idx, slide -> Int? in
        guard !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { return nil }
        guard slide.isSelected else { return nil }
        return idx
    }
    if singleSlideExport { return Array(linear.prefix(1)) }
    return linear
}

/// Heuristic slide-count guidance for the export hub (not platform carousel limits).
private enum StudioExportMemoryGuidance {
    private static let fourGB: UInt64 = 4 * 1024 * 1024 * 1024

    static var isLowRAMDevice: Bool {
        ProcessInfo.processInfo.physicalMemory < fourGB
    }

    /// Non-blocking notice in the export hub when at or above this selected export count.
    static var softWarningSlideThreshold: Int { isLowRAMDevice ? 12 : 18 }
}

/// Hard caps to avoid Jetsam crashes; aligned with common social carousel limits (34).
enum CarouselStudioExportHardLimit {
    /// JPEG share and each Photos/PDF package may include at most this many slides.
    static let maxSlidesPerShareOrPackage: Int = 34
}

/// Splits slide indices into consecutive packages of size `chunkSize`.
private func carouselStudioChunkedSlideIndexGroups(indices: [Int], chunkSize: Int) -> [[Int]] {
    guard chunkSize > 0 else { return indices.isEmpty ? [] : [indices] }
    var out: [[Int]] = []
    var cur: [Int] = []
    cur.reserveCapacity(min(chunkSize, indices.count))
    for idx in indices {
        cur.append(idx)
        if cur.count >= chunkSize {
            out.append(cur)
            cur = []
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

/// **Slides Management** and similar pickers use **raw** `slides` indices. The editor pager and
/// horizontal preview only render PIP-“visible” pages (`!isSlideHiddenBySiblingPIP`). Remap a raw
/// index so navigation targets a page that actually exists in the strip.
private func indexVisibleInEditorOrPreviewStrip(slides: [CarouselSlide], rawIndex: Int) -> Int? {
    guard slides.indices.contains(rawIndex) else { return nil }
    if !isSlideHiddenBySiblingPIP(at: rawIndex, in: slides) { return rawIndex }
    if slides[rawIndex].kind == .placeStop, let stopID = slides[rawIndex].placeStop?.id {
        return slides.indices.first { i in
            !isSlideHiddenBySiblingPIP(at: i, in: slides) && slides[i].placeStop?.id == stopID
        }
    }
    return nil
}

// MARK: - Carousel Studio photo exclusion (Social Post Studio)

private func studioExclusionKey(stop: UUID, photo: UUID) -> String { "\(stop.uuidString)|\(photo.uuidString)" }

private func parseStudioExclusionKey(_ key: String) -> (stop: UUID, photo: UUID)? {
    let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2,
          let stop = UUID(uuidString: parts[0]),
          let photo = UUID(uuidString: parts[1]) else { return nil }
    return (stop, photo)
}

private func globalStopIndexInBlog(blog: RecapBlogDetail, stopID: UUID) -> Int? {
    var n = 0
    for day in blog.days {
        for stop in day.placeStops {
            let inc = stop.photos.filter(\.isIncluded)
            guard !inc.isEmpty else { continue }
            n += 1
            if stop.id == stopID { return n }
        }
    }
    return nil
}

private func freshPlaceStop(stopID: UUID, blog: RecapBlogDetail) -> PlaceStop? {
    for day in blog.days {
        if let s = day.placeStops.first(where: { $0.id == stopID }) { return s }
    }
    return nil
}

private func expectedPlaceTuples(day: RecapBlogDay, excludedKeys: Set<String>) -> [(stop: UUID, photo: UUID)] {
    var out: [(stop: UUID, photo: UUID)] = []
    for stop in day.placeStops {
        for p in stop.photos where p.isIncluded {
            if excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: p.id)) { continue }
            out.append((stop: stop.id, photo: p.id))
        }
    }
    return out
}

/// Non‑nil when this stop belongs on a Studio map slide (included photos minus session exclusions).
private func carouselStudioCoordinateForStop(stop: PlaceStop, includedPhotos: [RecapPhoto]) -> CLLocationCoordinate2D? {
    let c = stop.representativeLocation?.clCoordinate
        ?? includedPhotos.first(where: { $0.location != nil })?.location?.clCoordinate
    guard let c, c.latitude.isFinite, c.longitude.isFinite else { return nil }
    guard (-89.999...89.999).contains(c.latitude),
          (-179.999...179.999).contains(c.longitude) else { return nil }
    return c
}

/// Drawable stops for a day map / place-intro snapshots — same exclusion filter as hero slides.
private func carouselDrawableStopsForStudioDay(day: RecapBlogDay, excludedKeys: Set<String>) -> [PlaceStop] {
    day.placeStops.filter { stop in
        let included = stop.photos.filter { $0.isIncluded }
            .filter { !excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
        guard !included.isEmpty else { return false }
        return carouselStudioCoordinateForStop(stop: stop, includedPhotos: included) != nil
    }
}

/// Matches the `await` budget in `SocialPostStudioSheet.loadSlides` so preparation progress stays in sync with real work.
/// Place intro map after the first stop in a day when a day-route map exists; in My Places share, each place with geometry gets one.
private func shouldIncludePlaceIntroMapSlide(
    placesOnlyMode: Bool,
    isFirstDrawableStop: Bool,
    stopID: UUID,
    drawableForMap: [PlaceStop]
) -> Bool {
    guard drawableForMap.firstIndex(where: { $0.id == stopID }) != nil else { return false }
    return placesOnlyMode || !isFirstDrawableStop
}

private func carouselStudioSlideBlockSupportsInlineTextEdit(
    kind: CarouselSlideKind,
    block: SlideBlockID
) -> Bool {
    switch (kind, block) {
    case (.cover, .primary): return true
    case (.mapRoute, .primary), (.mapRoute, .secondary): return true
    case (.placeIntroMap, .primary), (.placeIntroMap, .secondary): return true
    case (.placeStop, .primary), (.placeStop, .secondary): return true
    default: return false
    }
}

private func socialPostStudioLoadSlidesPreparationUnitCount(
    blog: RecapBlogDetail,
    excludedKeys: Set<String>,
    placesOnlyMode: Bool = false
) -> Int {
    var units = 1 // cover hero
    for day in blog.days {
        let drawableForMap = carouselDrawableStopsForStudioDay(day: day, excludedKeys: excludedKeys)
        var isFirstDrawableStop = true
        for stop in day.placeStops {
            let included = stop.photos.filter { $0.isIncluded }
                .filter { !excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
            guard !included.isEmpty else { continue }
            units += included.count
            if shouldIncludePlaceIntroMapSlide(
                placesOnlyMode: placesOnlyMode,
                isFirstDrawableStop: isFirstDrawableStop,
                stopID: stop.id,
                drawableForMap: drawableForMap
            ) {
                units += 1
            }
            isFirstDrawableStop = false
        }
        if !placesOnlyMode {
            units += 1 // day route map snapshot
        }
    }
    return max(units, 1)
}

/// Row count `loadSlides()` will produce (cover + per-day map + place intro / place stops), **without** awaiting snapshots.
/// Assumes a place intro map is added whenever drawable geometry exists (matches the common success case). Used so Slides
/// Management summary updates immediately while `loadSlides()` runs (e.g. format change).
private func expectedSocialPostStudioDeckSlideCountAfterReload(
    blog: RecapBlogDetail,
    excludedKeys: Set<String>,
    placesOnlyMode: Bool = false
) -> Int {
    var count = 1 // cover
    for day in blog.days {
        let drawableForMap = carouselDrawableStopsForStudioDay(day: day, excludedKeys: excludedKeys)
        var isFirstDrawableStop = true
        var dayPlaceSlides = 0
        for stop in day.placeStops {
            let included = stop.photos.filter { $0.isIncluded }
                .filter { !excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
            guard !included.isEmpty else { continue }

            if shouldIncludePlaceIntroMapSlide(
                placesOnlyMode: placesOnlyMode,
                isFirstDrawableStop: isFirstDrawableStop,
                stopID: stop.id,
                drawableForMap: drawableForMap
            ) {
                dayPlaceSlides += 1
            }
            isFirstDrawableStop = false

            dayPlaceSlides += included.count
        }
        let mapSlideCount = placesOnlyMode ? 0 : 1
        count += mapSlideCount + dayPlaceSlides
    }
    return max(count, 1)
}

/// Bounds of this day's place slides in deck order: after the day route map through the next `.mapRoute`, or the
/// contiguous place-intro / place-stop block when the day has no route map (e.g. My Places).
private func dayPlaceDeckSliceBounds(
    day: RecapBlogDay,
    blog: RecapBlogDetail,
    slides: [CarouselSlide]
) -> (start: Int, boundary: Int)? {
    let mapSlideId = "map-\(day.id.uuidString)"
    if let mapIdx = slides.firstIndex(where: { $0.id == mapSlideId }) {
        let start = slides.index(after: mapIdx)
        let boundary = slides[start...].firstIndex(where: { $0.kind == .mapRoute }) ?? slides.endIndex
        return (start, boundary)
    }
    let stopIDs = Set(day.placeStops.map(\.id))
    let indices = slides.indices.filter { idx in
        guard let sid = slides[idx].placeStop?.id else { return false }
        return stopIDs.contains(sid)
    }
    if let lo = indices.min(), let hi = indices.max() {
        return (lo, hi + 1)
    }
    guard let dayIdx = blog.days.firstIndex(where: { $0.id == day.id }) else { return nil }
    if dayIdx == 0 {
        if let coverIdx = slides.firstIndex(where: { $0.kind == .cover }) {
            return (slides.index(after: coverIdx), slides.count)
        }
        return (0, slides.count)
    }
    let prevDay = blog.days[dayIdx - 1]
    if let prev = dayPlaceDeckSliceBounds(day: prevDay, blog: blog, slides: slides) {
        return (prev.boundary, slides.count)
    }
    return (slides.count, slides.count)
}

private func isFirstExpectedPhotoTupleOfStop(
    expected: [(stop: UUID, photo: UUID)],
    at index: Int
) -> Bool {
    index == 0 || expected[index - 1].stop != expected[index].stop
}

/// Deck index where a restored / inserted place photo belongs — matches `loadSlides` (intro map, then each photo).
private func insertIndexForPlacePhotoInDay(
    day: RecapBlogDay,
    blog: RecapBlogDetail,
    stopID: UUID,
    photoID: UUID,
    slides: [CarouselSlide],
    excludedKeys: Set<String>
) -> Int {
    let expected = expectedPlaceTuples(day: day, excludedKeys: excludedKeys)
    guard let tupIdx = expected.firstIndex(where: { $0.stop == stopID && $0.photo == photoID }) else {
        return slides.count
    }
    guard let bounds = dayPlaceDeckSliceBounds(day: day, blog: blog, slides: slides) else {
        return slides.count
    }

    var i = bounds.start
    var expIdx = 0
    while expIdx < tupIdx && i < bounds.boundary {
        let exp = expected[expIdx]
        if isFirstExpectedPhotoTupleOfStop(expected: expected, at: expIdx),
           slides[i].kind == .placeIntroMap,
           slides[i].placeStop?.id == exp.stop {
            i = slides.index(after: i)
            if i >= bounds.boundary { break }
        }
        if slides[i].kind == .placeStop,
           slides[i].placeStop?.id == exp.stop,
           slides[i].heroPhotoID == exp.photo {
            i = slides.index(after: i)
        }
        expIdx += 1
    }

    if expIdx == tupIdx {
        if isFirstExpectedPhotoTupleOfStop(expected: expected, at: tupIdx),
           i < bounds.boundary,
           slides[i].kind == .placeIntroMap,
           slides[i].placeStop?.id == stopID {
            i = slides.index(after: i)
        }
        return i
    }
    return min(i, slides.count)
}

/// Re-sorts each day's place slides to match `loadSlides` when a photo was inserted out of order.
private func reconcilePlaceSlidesOrderInDeck(
    slides: inout [CarouselSlide],
    blog: RecapBlogDetail,
    excludedKeys: Set<String>,
    placesOnlyMode: Bool
) {
    for day in blog.days {
        guard let bounds = dayPlaceDeckSliceBounds(day: day, blog: blog, slides: slides),
              bounds.start < bounds.boundary else { continue }

        let segment = Array(slides[bounds.start..<bounds.boundary])
        let drawableForMap = carouselDrawableStopsForStudioDay(day: day, excludedKeys: excludedKeys)
        var isFirstDrawableStop = true
        var introByStop: [UUID: CarouselSlide] = [:]
        var photoByKey: [String: CarouselSlide] = [:]
        for slide in segment {
            switch slide.kind {
            case .placeIntroMap:
                if let id = slide.placeStop?.id { introByStop[id] = slide }
            case .placeStop:
                if let stop = slide.placeStop?.id, let photo = slide.heroPhotoID {
                    photoByKey["\(stop.uuidString)-\(photo.uuidString)"] = slide
                }
            case .cover, .mapRoute:
                break
            }
        }

        var ordered: [CarouselSlide] = []
        for stop in day.placeStops {
            let included = stop.photos.filter { $0.isIncluded }
                .filter { !excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
            guard !included.isEmpty else { continue }

            if shouldIncludePlaceIntroMapSlide(
                placesOnlyMode: placesOnlyMode,
                isFirstDrawableStop: isFirstDrawableStop,
                stopID: stop.id,
                drawableForMap: drawableForMap
            ), let intro = introByStop[stop.id] {
                ordered.append(intro)
            }
            isFirstDrawableStop = false

            for photo in included {
                let key = "\(stop.id.uuidString)-\(photo.id.uuidString)"
                if let slide = photoByKey[key] {
                    ordered.append(slide)
                }
            }
        }

        guard ordered.count == segment.count else { continue }
        slides.replaceSubrange(bounds.start..<bounds.boundary, with: ordered)
    }
}

// MARK: - Slides Management (unified grid: in-deck + session-excluded place photos)

/// One row in **Slides Management**: one **carousel slide** (cover, map, place map, or place photo slide),
/// or a session-excluded place photo not currently in the deck (dimmed, restorable).
private struct SlidesManagementItem: Identifiable {
    let id: String
    let ordinal: Int
    enum Payload {
        case cover(rawIndex: Int)
        case map(rawIndex: Int)
        case placeMap(rawIndex: Int)
        case placeInDeck(rawIndex: Int)
        case placeRemovedFromDeck(stop: PlaceStop, photo: RecapPhoto)
    }
    let payload: Payload
}

/// Build the grid in **deck order**: one row per **visible** slide (PIP-collapsed siblings skipped).
/// Session-excluded photos with no matching slide are listed after the deck.
private func makeSlidesManagementItems(
    blog: RecapBlogDetail,
    slides: [CarouselSlide],
    excludedKeys: Set<String>
) -> [SlidesManagementItem] {
    var out: [SlidesManagementItem] = []
    var ord = 0
    for idx in slides.indices {
        let slide = slides[idx]
        switch slide.kind {
        case .cover:
            ord += 1
            out.append(SlidesManagementItem(id: slide.id, ordinal: ord, payload: .cover(rawIndex: idx)))
        case .mapRoute:
            ord += 1
            out.append(SlidesManagementItem(id: slide.id, ordinal: ord, payload: .map(rawIndex: idx)))
        case .placeIntroMap:
            ord += 1
            out.append(SlidesManagementItem(id: slide.id, ordinal: ord, payload: .placeMap(rawIndex: idx)))
        case .placeStop:
            // Skip slides absorbed into a sibling's PIP cluster — they are not separate
            // carousel positions and should not appear as individual cards in the list.
            guard !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { continue }
            ord += 1
            out.append(SlidesManagementItem(id: slide.id, ordinal: ord, payload: .placeInDeck(rawIndex: idx)))
        }
    }
    for day in blog.days {
        for stop in day.placeStops {
            for photo in stop.photos where photo.isIncluded {
                let key = studioExclusionKey(stop: stop.id, photo: photo.id)
                guard excludedKeys.contains(key) else { continue }
                let stillInDeck = slides.contains(where: {
                    $0.kind == .placeStop
                        && $0.placeStop?.id == stop.id
                        && $0.heroPhotoID == photo.id
                })
                if stillInDeck { continue }
                ord += 1
                out.append(
                    SlidesManagementItem(
                        id: "excl-\(key)",
                        ordinal: ord,
                        payload: .placeRemovedFromDeck(stop: stop, photo: photo)
                    )
                )
            }
        }
    }
    return out
}

// MARK: - Download-style slide card (shared: Export → Download, Slides Management)

/// Matches the “pick slides to download” card: 10pt rounded preview, `checkmark.circle` in the
/// top-trailing corner, and a dim when not selected (not in the export pick / not in the carousel).
private enum CarouselStudioDownloadStylePickMode {
    /// Full-card tap: export toggles a pick, Slides: open, restore, or cover-only.
    case singleAction(() -> Void)
    /// Slide tap opens; corner check removes from the deck (place/map in carousel).
    case splitOpenInSlideRemoveFromCorner(onOpen: () -> Void, onRemoveFromDeck: () -> Void)
}

private struct CarouselStudioDownloadStylePickCard: View {
    let slide: CarouselSlide
    let width: CGFloat
    let aspectRatio: CGFloat
    let isInCarousel: Bool
    let mode: CarouselStudioDownloadStylePickMode

    private var cornerGlyph: some View {
        Image(systemName: isInCarousel ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isInCarousel ? CarouselStudioChrome.accent : .white.opacity(0.35))
            .padding(6)
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .singleAction(let onTap):
            // `Button` + `.plain` is more reliable over `CarouselSlideView` than `onTapGesture`.
            Button(action: onTap) {
                ZStack(alignment: .topTrailing) {
                    CarouselSlideView(
                        slide: slide,
                        width: width,
                        aspectRatio: aspectRatio,
                        onToggleSelection: {},
                        showsSelectionChrome: false,
                        clipsFloatingContentToRoundedSlideOutline: false,
                        showsBackgroundOnly: true
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if !isInCarousel {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.52))
                            .allowsHitTesting(false)
                    }
                    cornerGlyph
                }
            }
            .buttonStyle(.plain)

        case .splitOpenInSlideRemoveFromCorner(onOpen: let onOpen, onRemoveFromDeck: let onRemove):
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    CarouselSlideView(
                        slide: slide,
                        width: width,
                        aspectRatio: aspectRatio,
                        onToggleSelection: {},
                        showsSelectionChrome: false,
                        clipsFloatingContentToRoundedSlideOutline: false,
                        showsBackgroundOnly: true
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onRemove()
                } label: {
                    ZStack {
                        // Keep visual glyph size unchanged, but expand the tap target.
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 44, height: 44)
                        cornerGlyph
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from carousel")
            }
        }
    }
}

/// Builds one place-stop carousel slide (hero + PIP payload) matching `loadSlides` rules.
private func buildPlaceCarouselSlideForStudio(
    blog: RecapBlogDetail,
    stop: PlaceStop,
    photo: RecapPhoto,
    excludedKeys: Set<String>,
    exportWidth: CGFloat,
    exportHeight: CGFloat
) async -> CarouselSlide? {
    let included = stop.photos.filter { $0.isIncluded }
        .filter { !excludedKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
    guard let photoIdx = included.firstIndex(where: { $0.id == photo.id }) else { return nil }
    guard let stopIdx = globalStopIndexInBlog(blog: blog, stopID: stop.id) else { return nil }

    let heroCap = max(exportWidth, exportHeight)
    var stopImages: [UIImage?] = []
    for p in included {
        var img: UIImage?
        if let localId = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !localId.isEmpty {
            img = await loadCarouselAssetImage(identifier: localId,
                                               size: CGSize(width: exportWidth, height: exportHeight),
                                               pixelCap: heroCap)
        }
        if img == nil {
            img = await loadRecapPhotoUIImage(photo: p, size: CGSize(width: exportWidth, height: exportHeight),
                                              pixelCap: heroCap)
        }
        stopImages.append(img)
    }

    let hero = stopImages[photoIdx]
    let pipPairs: [(UIImage, UUID)] = included.enumerated()
        .compactMap { (idx, candidate) -> (UIImage, UUID)? in
            guard idx > photoIdx,
                  idx <= photoIdx + CarouselStudioMultiPhotoGroup.maxInsetThumbnails,
                  let img = stopImages[idx] else { return nil }
            return (img, candidate.id)
        }
        .map { $0 }
    let heroPhoto = included[photoIdx]
    return CarouselSlide(
        id: "\(stop.id.uuidString)-\(heroPhoto.id.uuidString)",
        kind: .placeStop,
        isSelected: true,
        heroImage: hero,
        placeStop: stop,
        photoCaption: heroPhoto.caption,
        isFirstPhotoOfStop: photoIdx == 0,
        textStyle: .placeStopDefault,
        pipImages: pipPairs.map(\.0),
        pipPhotoIDs: pipPairs.map(\.1),
        heroPhotoID: heroPhoto.id,
        stopIndex: stopIdx
    )
}

// MARK: - Slide View

/// Named coordinate space for the slide, used when measuring each block's natural
/// (anchor-based) frame so drags can be clamped to the slide bounds.
private let studioSlideCoordSpace = "studio.slide.space"

/// Edge inset (in points) used in two places that **must stay in sync**:
/// 1. `DraggableTextBlock.softClamped(proposed:baseline:)` shrinks the allowed slide
///    area so the block's visual rect stays inside the slide.
/// 2. Each anchored overlay in `CarouselSlideView` pads its draggable text block by the
///    same amount so the block's *natural* (anchor) rect already sits inside that
///    clamp region — avoiding a first-tap "nudge" when `savedOffset == .zero`.
///
/// Set to `0` so text blocks can sit flush on the left/right/top/bottom edges. Rubber-band
/// on finger lift is avoided by clamping the **displayed** offset during the gesture
/// (`displayPointOffset`), not only on `onEnded`.
private let studioTextBlockEdgeInset: CGFloat = 0

/// Inset of the PIP thumbnail cluster from the slide edges (default placement + drag clamp).
/// Kept separate from `studioTextBlockEdgeInset` so place titles can stay edge-to-edge
/// while PIP sits slightly inside the postcard border.
private let studioPIPClusterEdgeInset: CGFloat = 10

/// PIP cluster thumbnail scale range (`1.0` matches the original default footprint).
/// Shared by the Size toolbar strip, pinch-resize on the slide, and snap logic.
private enum StudioPIPClusterSize {
    static let minScale: CGFloat = 0.55
    /// Upper clamp for inset thumbnail pinch / Size strip (~60% larger than default footprint vs 1.45).
    static let maxScale: CGFloat = 2.0
    /// Finer than before so pinch release and the Size strip snap with smaller jumps.
    static let step: CGFloat = 0.01

    static func clampOnly(_ raw: CGFloat) -> CGFloat {
        min(max(raw, minScale), maxScale)
    }

    static func clampAndSnap(_ raw: CGFloat) -> CGFloat {
        let clamped = clampOnly(raw)
        return (clamped / step).rounded() * step
    }
}

/// Per-frame exponential smoothing for pinch scale (`MagnificationGesture` can feel jittery).
/// Higher = follows the finger more tightly; lower = smoother motion.
private let studioPIPClusterPinchSmoothingBlend: CGFloat = 0.42

/// Text block font-size pinch range (matches Size toolbar / `setSizeScaleLive`).
private enum StudioTextBlockSize {
    static let minScale: CGFloat = 0.6
    static let maxScale: CGFloat = 1.8
    static let step: CGFloat = 0.05

    static func clampOnly(_ raw: CGFloat) -> CGFloat {
        min(max(raw, minScale), maxScale)
    }

    static func clampAndSnap(_ raw: CGFloat) -> CGFloat {
        let clamped = clampOnly(raw)
        return (clamped / step).rounded() * step
    }
}

/// Multi (grouped PIP): user tapped an inset thumbnail to replace it from the place library.
private struct PIPInsetReplaceSession: Identifiable {
    let slideIndex: Int
    let clusterThumbIndex: Int
    var id: String { "\(slideIndex)-\(clusterThumbIndex)" }
}

/// Repositionable text block. The drag gesture lives on the block itself; SwiftUI's
/// `.offset()` is visually displacing AND hit-testable, so the on-screen rect is the
/// one that receives touches — no external hit catchers required.
///
/// `savedOffset` is the committed displacement (written on drag-end after clamping to
/// `slideBounds`). `liveDrag` is the in-flight translation held in gesture state so it
/// auto-resets on gesture end and there is no one-frame snap between end and commit.
private struct DraggableTextBlock<Content: View>: View {
    let id: SlideBlockID
    let isEditingText: Bool
    /// When `false`, no outline is drawn (clean slide) even in edit mode — used until the user selects a block.
    var showsEditingOutline: Bool = true
    let isSelected: Bool
    /// Committed displacement from the block's natural anchor, expressed as a normalized
    /// fraction of `slideBounds` (e.g. `width = 0.10` ⇒ 10% of slide width to the right).
    /// We multiply by `slideBounds` at render time so the same stored offset lands in the
    /// same relative spot at any rendering size (editor / preview / export).
    @Binding var savedOffset: CGSize
    /// Slide rect in its local coord space (e.g. `(0, 0, slideW, slideH)`), used to clamp drags.
    let slideBounds: CGRect
    var onSelect: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    /// Fires on gesture-end when the user lifted their finger without moving
    /// more than `tapSlop` points — i.e. it was a tap, not a drag. Editor uses
    /// this to cycle the readable bar when the block was already selected.
    var onTap: () -> Void = {}
    let content: () -> Content
    /// Current `sizeScale` for this block (drives pinch baseline).
    var textSizeScaleForPinch: CGFloat = 1.0
    /// Pinch to resize typography when the block is selected; `nil` disables.
    var onUpdateTextSizeScale: ((SlideBlockID, CGFloat) -> Void)? = nil
    var onTextPinchBegan: () -> Void = {}

    @GestureState private var liveDrag: CGSize = .zero
    /// Block frame at its natural (anchor-based) position in the slide coord space,
    /// used only for drag clamping. Captured once at `.zero` offset.
    @State private var naturalRect: CGRect?
    /// Snapshot of `isSelected` taken at the first `onChanged` of a gesture, used
    /// so taps on an unselected block only select it — they must not also fire
    /// `onTap` (which cycles the readable bar on an already-selected block).
    @State private var wasSelectedAtGestureStart: Bool = false
    /// True from first `onChanged` until `onEnded` — gates the snapshot above so
    /// we only capture on press-start, not on every drag update.
    @State private var didBeginGesture: Bool = false
    @State private var pinchTextBase: CGFloat = 1.0
    @State private var pinchTextActive = false
    @State private var pinchTextLastRaw: CGFloat = 1.0

    /// `savedOffset` converted from a normalized fraction into absolute points for the
    /// current `slideBounds`. This is what `.offset()` actually consumes.
    private var savedPointOffset: CGSize {
        CGSize(width: savedOffset.width * slideBounds.width,
               height: savedOffset.height * slideBounds.height)
    }

    /// In-slide offset actually applied.
    ///
    /// Clamp only while actively dragging, and **softly** — using the pre-drag visual
    /// position as the floor. If we hard-clamp every frame, any passive layout change
    /// (e.g. cycling the readable bar with a tap) can change the block's size, and the very first
    /// frame of the next drag would snap the block inward to fit `slideBounds` (the user
    /// reads this as "tap caused a snap" or "drag-start caused a snap"). With the soft
    /// clamp, a drag that started while the block was already extending past the slide
    /// edge can only ever bring it *closer* to bounds — never push it further out — and
    /// is otherwise free to move; no snap on the first finger movement.
    private var displayPointOffset: CGSize {
        let proposed = CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        )
        if liveDrag != .zero {
            return softClamped(proposed: proposed, baseline: savedPointOffset)
        }
        return savedPointOffset
    }

    var body: some View {
        content()
            .background(naturalRectCapture)
            .overlay(editingRing)
            .contentShape(Rectangle())
            .offset(x: displayPointOffset.width, y: displayPointOffset.height)
            // Inherited animation must not interpolate offset when parent state
            // updates (color/contrast bar, toolbar, etc.); that looks like drift.
            .animation(nil, value: savedOffset)
            .highPriorityGesture(
                // Slide space — not `.local`. `offset` is layout-preserving, so local gesture
                // translations do not match finger movement after the user drags a block away from
                // its anchor (taps can snap the block back toward the overlay edge).
                DragGesture(minimumDistance: 0, coordinateSpace: .named(studioSlideCoordSpace))
                    .updating($liveDrag) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { _ in
                        if !didBeginGesture {
                            didBeginGesture = true
                            wasSelectedAtGestureStart = isSelected
                        }
                        onDragStart()
                        onSelect()
                    }
                    .onEnded { value in
                        // Finger lifted with almost no movement → treat as a tap.
                        // We route small motions to `onTap` when the block was already
                        // selected, and *don't* rewrite `savedOffset`, so a tap never
                        // commits a position change. Readable bar: tap block when selected.
                        // 12pt matches UITapGestureRecognizer's tolerance; 6pt was
                        // too small and caused normal taps to commit a position change.
                        let tapSlop: CGFloat = 12
                        let moved = max(abs(value.translation.width),
                                        abs(value.translation.height))
                        let beganSelected = wasSelectedAtGestureStart
                        didBeginGesture = false
                        wasSelectedAtGestureStart = false
                        if moved < tapSlop {
                            // Tap cycles readable bar only if block was already selected.
                            if beganSelected { onTap() }
                        } else {
                            let proposedPoints = CGSize(
                                width: savedPointOffset.width + value.translation.width,
                                height: savedPointOffset.height + value.translation.height
                            )
                            // Hard-clamp at commit (not soft). The soft clamp is only there
                            // to keep the visual smooth during a drag whose *baseline* was
                            // already extending past the slide (e.g. after enabling readable bar).
                            // Persisting that overflow into `savedOffset` would leave the
                            // next gesture's baseline overflowing too, which then blocks any
                            // drag in the overflow direction — the user reads that as the
                            // block being "stuck" on one side until they cycle the pill to
                            // shrink the natural rect. Hard-clamping here keeps the saved
                            // position inside `slideBounds` so every fresh drag starts from
                            // a clean state.
                            let clampedPoints = clampedToBounds(proposed: proposedPoints)
                            // Store back in normalized form so the offset survives rendering
                            // at the smaller preview / export sizes (Story/Reel previews are
                            // ~62% of the editor slide width, so absolute points would drift).
                            savedOffset = CGSize(
                                width: slideBounds.width > 0 ? clampedPoints.width / slideBounds.width : 0,
                                height: slideBounds.height > 0 ? clampedPoints.height / slideBounds.height : 0
                            )
                        }
                        onDragEnd()
                    },
                including: isEditingText ? .all : .subviews
            )
            .simultaneousGesture(textPinchGesture)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var textPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnitude in
                guard isEditingText, isSelected, let update = onUpdateTextSizeScale else { return }
                if !pinchTextActive {
                    pinchTextActive = true
                    pinchTextBase = textSizeScaleForPinch
                    onTextPinchBegan()
                }
                let raw = pinchTextBase * magnitude
                pinchTextLastRaw = raw
                update(id, StudioTextBlockSize.clampOnly(raw))
            }
            .onEnded { _ in
                if pinchTextActive, isSelected, let update = onUpdateTextSizeScale {
                    update(id, StudioTextBlockSize.clampAndSnap(pinchTextLastRaw))
                }
                pinchTextActive = false
            }
    }

    @ViewBuilder
    private var naturalRectCapture: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { captureNaturalRect(from: geo) }
                .onChange(of: geo.size) { _, _ in captureNaturalRect(from: geo) }
                // Slides resize when the formatting toolbar opens/closes (9:16)
                // or when the aspect ratio is switched (e.g. 9:16 → 4:5).
                // The block's intrinsic size may not change, so `onChange(of: geo.size)`
                // won't fire. We must recapture on `slideBounds` changes instead.
                // Crucially, we nil `naturalRect` first: if the named coordinate space
                // hasn't been committed yet in this render pass, `captureNaturalRect`
                // returns a zero rect and bails out (guard), leaving `naturalRect = nil`.
                // `clamped()` then returns the proposed offset unconstrained, which is
                // far better than clamping against stale 9:16 coordinates on a 4:5 slide.
                .onChange(of: slideBounds) { _, _ in
                    naturalRect = nil
                    captureNaturalRect(from: geo)
                }
                .onChange(of: textSizeScaleForPinch) { _, _ in
                    if !pinchTextActive {
                        pinchTextBase = textSizeScaleForPinch
                    }
                }
        }
    }

    /// Stores the block's natural (un-offset) frame in slide coords.
    ///
    /// SwiftUI's `.offset()` modifier is **visual-only** — it shifts how the view is
    /// rendered on screen, but it does NOT change the view's layout frame. This means
    /// `geo.frame(in: .named(studioSlideCoordSpace))` always returns the block's
    /// natural (anchor-based) layout position regardless of the current `savedOffset`
    /// or in-flight `liveDrag`. We store it directly as `naturalRect` with no further
    /// adjustment needed.
    ///
    /// We recapture on every size/bounds change (not just once) because the slide can
    /// resize mid-session on 9:16 formats when the toolbar grows or collapses. A stale
    /// natural rect makes `softClamped(proposed:baseline:)` reject otherwise-valid drags
    /// and causes committed offsets to render in the wrong spot, which reads as "my move
    /// didn't save."
    ///
    /// IMPORTANT: do NOT mutate `savedOffset` here. Cycling the readable bar
    /// or other intrinsic layout change fires this callback — any silent rewrite
    /// of `savedOffset` reads to the user as the block "snapping to another position"
    /// right after that change, and (because the rewrite has to be scheduled on the
    /// next runloop tick) can also land mid-gesture when the user immediately tries
    /// to drag, causing the block to jump under the finger. If contrast-bar padding pushes the
    /// block slightly off-bounds at its committed offset, accept the temporary overflow —
    /// `softClamped` then lets the next drag move *toward* bounds without first snapping
    /// inward, and the user can recover the position simply by dragging.
    private func captureNaturalRect(from geo: GeometryProxy) {
        let current = geo.frame(in: .named(studioSlideCoordSpace))
        guard current.width > 0, current.height > 0 else { return }
        naturalRect = current
    }

    @ViewBuilder
    private var editingRing: some View {
        if isEditingText, showsEditingOutline {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isSelected
                        ? CarouselStudioChrome.accent
                        : Color.white.opacity(0.35),
                    style: isSelected
                        ? StrokeStyle(lineWidth: 2.0)
                        : StrokeStyle(lineWidth: 1.0, dash: [5, 3])
                )
                .padding(-3)
        }
    }

    /// Constrains the proposed offset so the block's visual rect cannot overflow
    /// `slideBounds` *more* than the baseline already does. When the baseline is fully
    /// inside `slideBounds` this collapses to a strict clamp at the slide edges; when
    /// the baseline already extends past an edge (e.g. because tapping a positioned
    /// block grew its contrast bar beyond the slide), that overflow becomes the cap on
    /// that side, so the user can freely drag *toward* bounds without the first finger
    /// movement snapping the block inward.
    ///
    /// Used only during an active drag (`displayPointOffset`). Drag-end commit goes
    /// through `clampedToBounds(proposed:)` instead, so the stored offset is always
    /// fully inside `slideBounds` — preventing the next gesture from inheriting a
    /// stuck-on-one-edge baseline.
    ///
    /// Oversized axes (block intrinsically wider/taller than the slide) skip the clamp
    /// entirely on that axis so the user can still slide them around without the two
    /// edge corrections fighting each other and producing a "trapped" feel.
    private func softClamped(proposed: CGSize, baseline: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }

        let bounds = slideBounds.insetBy(dx: studioTextBlockEdgeInset,
                                         dy: studioTextBlockEdgeInset)
        let baselineVisual = natural.offsetBy(dx: baseline.width, dy: baseline.height)
        let visual = natural.offsetBy(dx: proposed.width, dy: proposed.height)

        var dx: CGFloat = 0
        if natural.width <= bounds.width {
            let leftLimit = min(bounds.minX, baselineVisual.minX)
            let rightLimit = max(bounds.maxX, baselineVisual.maxX)
            if visual.minX < leftLimit { dx = leftLimit - visual.minX }
            if visual.maxX > rightLimit { dx = rightLimit - visual.maxX }
        }
        var dy: CGFloat = 0
        if natural.height <= bounds.height {
            let topLimit = min(bounds.minY, baselineVisual.minY)
            let bottomLimit = max(bounds.maxY, baselineVisual.maxY)
            if visual.minY < topLimit { dy = topLimit - visual.minY }
            if visual.maxY > bottomLimit { dy = bottomLimit - visual.maxY }
        }
        return CGSize(width: proposed.width + dx, height: proposed.height + dy)
    }

    /// Strict clamp: forces the block's visual rect fully inside `slideBounds` regardless
    /// of where it sits coming in. Used at drag-end commit so the stored `savedOffset`
    /// can never be off-bounds — every new gesture then starts from a clean baseline,
    /// and `softClamped` reduces to a standard clamp.
    ///
    /// The (small) trade-off is that lifting after only a partial recovery from a
    /// readable-bar overflow can look like the block "settles in" by a few points at lift.
    /// That's a single, user-initiated event; far less disruptive than a baseline that
    /// stays overflowing and blocks subsequent drags in the overflow direction.
    private func clampedToBounds(proposed: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }

        let bounds = slideBounds.insetBy(dx: studioTextBlockEdgeInset,
                                         dy: studioTextBlockEdgeInset)
        let visual = natural.offsetBy(dx: proposed.width, dy: proposed.height)

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if natural.width <= bounds.width {
            if visual.minX < bounds.minX { dx = bounds.minX - visual.minX }
            if visual.maxX > bounds.maxX { dx = bounds.maxX - visual.maxX }
        }
        if natural.height <= bounds.height {
            if visual.minY < bounds.minY { dy = bounds.minY - visual.minY }
            if visual.maxY > bounds.maxY { dy = bounds.maxY - visual.maxY }
        }
        return CGSize(width: proposed.width + dx, height: proposed.height + dy)
    }
}

/// Bold line for `.placeStop` or `.placeIntroMap` split primary blocks (shared `dayInfoLine1` backing for intro).
private func studioSplitOrPlacePrimaryTitle(slide: CarouselSlide, placeStop: PlaceStop) -> String {
    if slide.kind == .placeStop { return placeStop.placeTitle }
    let s = (slide.dayTitle ?? slide.dayInfoLine1 ?? placeStop.placeTitle)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? placeStop.placeTitle : s
}

/// City / area line under the place name — matches seeded `dayInfoLine2`, then `placeSubtitle`.
private func studioPlaceIntroSplitCityLine(slide: CarouselSlide, placeStop: PlaceStop) -> String? {
    let fromSlide = (slide.dayInfoLine2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !fromSlide.isEmpty { return fromSlide }
    let sub = (placeStop.placeSubtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return sub.isEmpty ? nil : sub
}

private func mapRouteStoryVisible(_ slide: CarouselSlide) -> Bool {
    guard isCarouselStudioMapKind(slide.kind) else { return false }
    return !(slide.dayStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Whether the place-stop slide has any top-leading secondary text to show.
/// The secondary block renders the place subtitle (city, country) at the top —
/// so the top gradient is gated on that, not on the primary block.
/// Same subtitle on `.placeIntroMap` split slides (photo strip + map).
private func placeSubtitleVisible(_ slide: CarouselSlide) -> Bool {
    guard let sub = slide.placeStop?.placeSubtitle else { return false }
    let t = sub.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    return slide.kind == .placeStop
}

/// PIP cluster default placement and clamping rules.
///
/// The cluster has **no internal padding** so its measured frame equals the visible
/// thumbnail rect (good for hit-testing and drag math). Default placement and drag limits
/// use `studioPIPClusterEdgeInset`: `CarouselSlideView` pads the top-trailing overlay by
/// that amount so `pipOffset == .zero` sits slightly inside the slide border, and
/// `DraggablePIPCluster.clampedOffset` insets `slideBounds` by the same value so drags
/// cannot push the cluster flush against the edge (rotation/shadow still need bleed; see below).
///
/// Rotation (`rotationEffect`) and the drop `shadow` extend a few points beyond
/// the visible thumb. Outside the editor, callers must allow that bleed:
///   - `SlideEditPage` clips to the rounded slide outline (small corner trim is
///     acceptable and looks intentional).
///   - `SocialPostStudioSheet` adds generous `previewCardBleedInsets` around
///     each preview card so the strip's `clipShape` doesn't shave the rotation/shadow.

extension View {
    /// Applies `clipShape` only when `active` — used to clip photo/gradient backgrounds
    /// to the postcard outline while leaving PIP shadows / rotations unclipped.
    @ViewBuilder
    fileprivate func clipCarouselPostcardOutline(_ active: Bool) -> some View {
        if active {
            self.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
        }
    }
}

/// One split half‑slot: optional framing (nil ⇒ neutral / default aspect‑fill).
private struct SplitFramedPhotoInSlot: View {
    let image: UIImage
    var framing: StudioImageFraming?
    let slotWidth: CGFloat
    let slotHeight: CGFloat

    var body: some View {
        let f = framing ?? .neutral
        let m = StudioImageFraming.framedMetrics(
            image: image,
            slotW: slotWidth,
            slotH: slotHeight,
            framing: f
        )
        ZStack {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: m.rw, height: m.rh)
                .position(x: slotWidth * 0.5 + m.offsetX, y: slotHeight * 0.5 + m.offsetY)
        }
        .frame(width: slotWidth, height: slotHeight)
        .clipped()
    }
}

struct CarouselSlideView: View {
    let slide: CarouselSlide
    let width: CGFloat
    let aspectRatio: CGFloat
    let onToggleSelection: () -> Void
    let showsSelectionChrome: Bool
    var isEditingText: Bool = false
    /// Which text block is currently selected for editing (shown with a solid blue border).
    var selectedBlockID: SlideBlockID? = nil
    /// Called when the user taps a block (text or PIP cluster) to select it.
    var onSelectBlock: ((SlideBlockID) -> Void)? = nil
    /// Edit-mode write-back: commit a block's new offset. Nil in read-only (preview/export) use.
    var onUpdateBlockOffset: ((SlideBlockID, CGSize) -> Void)? = nil
    /// Fires on drag-start — the editor uses it to lock horizontal slide paging.
    var onBlockDragStart: (() -> Void)? = nil
    /// Fires on drag-end — the editor uses it to release the paging lock.
    var onBlockDragEnd: (() -> Void)? = nil
    /// Fires on a true tap (no drag motion) — cycles readable bar Off / Dark / Light when
    /// the block was already selected (`CarouselStudioSheet` / `SlideEditPage`).
    var onBlockTap: ((SlideBlockID) -> Void)? = nil
    /// Edit-mode write-back: commit a new PIP cluster offset. Nil in read-only (preview/export) use.
    var onUpdatePIPOffset: ((CGSize) -> Void)? = nil
    /// Edit-mode write-back: commit a new per-photo offset when `slide.pipIsUngrouped == true`.
    var onUpdatePIPPhotoOffset: ((Int, CGSize) -> Void)? = nil
    /// Edit-mode: fires when the user taps a specific PIP thumbnail in ungrouped mode.
    var onSelectPIPPhoto: ((Int) -> Void)? = nil
    /// Index of the currently selected individual PIP photo (ungrouped mode only).
    var selectedPIPPhotoIndex: Int? = nil
    /// Multi-photo layout only: fired when the user taps the large hero backdrop (areas not covered
    /// by text blocks or the PIP cluster). Opens the hero-swap picker in `SlideTextEditorView`.
    var onTapHeroBackdrop: (() -> Void)? = nil
    /// Split layout only: fired when the user taps the bottom slot to choose a second photo.
    var onTapSplitBottomSlot: (() -> Void)? = nil
    /// Split layout only: fired when the user taps the top slot.
    var onTapSplitTopSlot: (() -> Void)? = nil
    /// Split layout only: which slot is currently selected — drives the highlight ring.
    fileprivate var selectedSplitSlot: SplitRepositionSlot? = nil
    /// Grouped Multi: tap an inset thumbnail to replace that slot (picker).
    var onPIPClusterThumbTap: ((Int) -> Void)? = nil
    /// Pinch-to-resize inset cluster footprint while the cluster block is selected.
    /// Second argument is `true` only for the final snapped value when the gesture ends.
    var onPIPClusterPinchScale: ((CGFloat, Bool) -> Void)? = nil
    var onPIPClusterPinchBegan: () -> Void = {}
    /// Pinch to resize text `sizeScale` for primary/secondary blocks when selected.
    var onUpdateTextSizeScale: ((SlideBlockID, CGFloat) -> Void)? = nil
    var onTextPinchBegan: () -> Void = {}
    /// When set, tapping the cover hero (behind title chrome) runs this — e.g. studio cover picker
    /// in Social Post Studio preview, or the same picker from Carousel Studio (`SlideTextEditorView`).
    var onCoverImageTap: (() -> Void)? = nil
    /// When `true` (default), floating overlays use the slide’s rounded-rect outline. For
    /// `.placeStop` + `.pip`, only the **background** stack is clipped so the inset cluster
    /// (rotation + shadow) is not shaved off; other kinds still get one outer clip. When
    /// `false`, only the photo/gradient stack is clipped — used for small studio previews.
    var clipsFloatingContentToRoundedSlideOutline: Bool = true
    /// When `true`, draws only imagery (hero, map snapshot, split slots) without title, captions, PIPs, or text legibility gradients.
    /// Used by the Carousel Studio download picker; export keeps the default `false` so saves include all overlays.
    var showsBackgroundOnly: Bool = false
    /// Carousel Studio: show the Bloggo watermark only on the first map slide (`false` for later day maps / place-intro maps).
    var showPoweredByBloggoMapWatermark: Bool = true
    /// Editor-only: stack positions (0,1,2) still awaiting Vision background removal.
    var pipBackgroundRemovalLoadingSlots: Set<Int> = []

    private var height: CGFloat { width / aspectRatio }

    /// Place-intro / day-map split layout: top half is the cover photo; bottom half is the map snapshot.
    private static let mapSplitPhotoHeightFraction: CGFloat = 0.5
    /// Curved map/photo split only: extra height (pt) taken from the map half and given to the photo strip
    /// so the scalloped seam sits slightly lower on the slide; negative `VStack` spacing still overlaps the halves.
    private static let mapCurvedSplitPhotoExtraYMin: CGFloat = 8
    private static let mapCurvedSplitPhotoExtraYMax: CGFloat = 22

    private static func mapCurvedSplitPhotoExtraHeight(forSlideHeight H: CGFloat) -> CGFloat {
        min(mapCurvedSplitPhotoExtraYMax, max(mapCurvedSplitPhotoExtraYMin, H * 0.024))
    }

    /// Photo-strip fraction for split map slides (must match `splitMapSplitBackground` straight vs curve).
    private func mapSplitPhotoFractionForStudioMapSplit() -> CGFloat {
        guard isCarouselStudioMapKind(slide.kind), slide.layout == .split else { return 0.5 }
        guard slide.splitDividerStyle == .curve else { return Self.mapSplitPhotoHeightFraction }
        let extra = Self.mapCurvedSplitPhotoExtraHeight(forSlideHeight: height)
        return Self.mapSplitPhotoHeightFraction + extra / height
    }

    private let heroImageScale: CGFloat = 1.12
    private var slideBounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// Dashed/solid block rings only after something is selected; with no selection the canvas matches export.
    private var showsDraggableBlockOutlines: Bool { isEditingText && selectedBlockID != nil }

    /// When `clipsFloatingContentToRoundedSlideOutline` is on, the default is one
    /// final `clipShape` around **everything** (text + PIP). PIP sits in the top-trailing
    /// corner with rotation/shadow, so that clip often removes the whole cluster. Clip
    /// only the photo/gradient stack for `.pip` place slides instead; keep the outer clip
    /// for all other layouts (matches studio preview, which passes `clips… = false`).
    private var pipClusterNeedsUnclippedFloatingChrome: Bool {
        slide.kind == .placeStop && slide.layout == .pip && !slide.pipImages.isEmpty
    }

    /// Binding for the block's committed offset. Reads from `slide.textStyle.*`; writes
    /// go through `onUpdateBlockOffset` (nil-callback in read-only contexts makes it a no-op).
    private func offsetBinding(for id: SlideBlockID) -> Binding<CGSize> {
        Binding(
            get: {
                switch id {
                case .primary:    return slide.textStyle.primary.offset
                case .secondary:  return slide.textStyle.secondary.offset
                case .pipCluster: return slide.pipOffset
                }
            },
            set: { newOffset in onUpdateBlockOffset?(id, newOffset) }
        )
    }

    private var pipOffsetBinding: Binding<CGSize> {
        Binding(
            get: { slide.pipOffset },
            set: { onUpdatePIPOffset?($0) }
        )
    }

    private func pipPhotoOffsetBinding(at index: Int) -> Binding<CGSize> {
        Binding(
            get: {
                guard index < slide.pipPhotoOffsets.count else { return .zero }
                return slide.pipPhotoOffsets[index]
            },
            set: { onUpdatePIPPhotoOffset?(index, $0) }
        )
    }

    /// Photo, map snapshot, gradients, and (in PIP edit mode) the hero tap catcher.
    @ViewBuilder
    private var slideBackgroundStack: some View {
        ZStack {
            // ── Backgrounds ───────────────────────────────────────────
            switch slide.kind {
            case .cover:
                coverBackground
                if !showsBackgroundOnly {
                    LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.3), .clear],
                                   startPoint: .bottom, endPoint: .top)
                        .frame(width: width, height: height)
                }
                if onCoverImageTap != nil, showsSelectionChrome || isEditingText {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: width, height: height)
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                #if DEBUG
                                print("[CarouselStudio] CarouselSlideView: cover hero tap")
                                #endif
                                onCoverImageTap?()
                            }
                        )
                }

            case .mapRoute, .placeIntroMap:
                ZStack {
                    if slide.layout == .split {
                        splitMapSplitBackground
                    } else {
                        fullBleedMapBackground
                    }
                    if isEditingText, slide.layout == .split {
                        let photoFrac = isCarouselStudioMapKind(slide.kind)
                            ? mapSplitPhotoFractionForStudioMapSplit()
                            : 0.5 as CGFloat
                        VStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: width, height: height * photoFrac)
                                .highPriorityGesture(
                                    TapGesture().onEnded { onTapSplitTopSlot?() }
                                )
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: width, height: height * (1 - photoFrac))
                                .highPriorityGesture(
                                    TapGesture().onEnded { onTapSplitBottomSlot?() }
                                )
                        }
                        .frame(width: width, height: height)
                    }
                    if isEditingText, slide.layout == .split, let slot = selectedSplitSlot {
                        let photoFrac = isCarouselStudioMapKind(slide.kind)
                            ? mapSplitPhotoFractionForStudioMapSplit()
                            : 0.5 as CGFloat
                        let mapSplitHighlightsInvert = isCarouselStudioMapKind(slide.kind)
                        let ringTop = mapSplitHighlightsInvert ? (slot == .bottom) : (slot == .top)
                        let ringBottom = mapSplitHighlightsInvert ? (slot == .top) : (slot == .bottom)
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 0)
                                .strokeBorder(
                                    ringTop ? Color.white.opacity(0.55) : Color.clear,
                                    lineWidth: 2
                                )
                                .frame(width: width, height: height * photoFrac)
                                .allowsHitTesting(false)
                            RoundedRectangle(cornerRadius: 0)
                                .strokeBorder(
                                    ringBottom ? Color.white.opacity(0.55) : Color.clear,
                                    lineWidth: 2
                                )
                                .frame(width: width, height: height * (1 - photoFrac))
                                .allowsHitTesting(false)
                        }
                        .frame(width: width, height: height)
                        .animation(.easeInOut(duration: 0.15), value: slot)
                    }
                }
                if !showsBackgroundOnly {
                    let mapSplitTopFade = slide.layout == .split
                        && placeSubtitleVisible(slide)
                        && !slide.isSecondaryHidden
                    if !slide.isPrimaryHidden || mapSplitTopFade {
                        LinearGradient(colors: [.black.opacity(0.6), .clear],
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                            .frame(width: width, height: height)
                    }
                    if mapRouteStoryVisible(slide), !slide.isSecondaryHidden {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                       startPoint: .init(x: 0.5, y: 0.52), endPoint: .bottom)
                            .frame(width: width, height: height)
                    }
                }

            case .placeStop:
                placeStopBackground
                if !showsBackgroundOnly {
                    // Top gradient: only when the city/country subtitle is present
                    if placeSubtitleVisible(slide), !slide.isSecondaryHidden {
                        LinearGradient(colors: [.black.opacity(0.65), .clear],
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                            .frame(width: width, height: height)
                    }
                    // Bottom gradient: protects the place name + caption
                    if !slide.isPrimaryHidden {
                        LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                       startPoint: .init(x: 0.5, y: 0.58), endPoint: .bottom)
                            .frame(width: width, height: height)
                    }
                }
                // Sits above the imagery but below all text/PIP overlays (they are `.overlay`s
                // applied after this `ZStack`). Taps choose the large hero backdrop only; blocks
                // on top keep their own gestures.
                if isEditingText, slide.layout == .pip, onTapHeroBackdrop != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: width, height: height)
                        .highPriorityGesture(
                            TapGesture().onEnded { onTapHeroBackdrop?() }
                        )
                }
                if isEditingText, slide.layout == .split {
                    VStack(spacing: 0) {
                        // Top half — selects top slot
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: height * 0.5)
                            .highPriorityGesture(
                                TapGesture().onEnded { onTapSplitTopSlot?() }
                            )
                        // Bottom half — selects bottom slot
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: height * 0.5)
                            .highPriorityGesture(
                                TapGesture().onEnded { onTapSplitBottomSlot?() }
                            )
                    }
                    .frame(width: width, height: height)
                }
                // Selection ring for split photo slots.
                if isEditingText, slide.layout == .split, let slot = selectedSplitSlot {
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                slot == .top ? Color.white.opacity(0.55) : Color.clear,
                                lineWidth: 2
                            )
                            .frame(width: width, height: height * 0.5)
                            .allowsHitTesting(false)
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                slot == .bottom ? Color.white.opacity(0.55) : Color.clear,
                                lineWidth: 2
                            )
                            .frame(width: width, height: height * 0.5)
                            .allowsHitTesting(false)
                    }
                    .frame(width: width, height: height)
                    .animation(.easeInOut(duration: 0.15), value: slot)
                }
            }
        }
    }

    var body: some View {
        carouselSlideRoot
    }

    /// Split from `body` so the type checker can finish (`CarouselSlideView` chains many overlays).
    @ViewBuilder
    private var carouselSlideRoot: some View {
        Group {
            if clipsFloatingContentToRoundedSlideOutline && pipClusterNeedsUnclippedFloatingChrome {
                slideBackgroundStack
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if clipsFloatingContentToRoundedSlideOutline {
                slideBackgroundStack
            } else {
                slideBackgroundStack
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        // ── Draggable text overlays ───────────────────────────────────
        // Cover title — centered
        .overlay {
            if !showsBackgroundOnly, slide.kind == .cover, !slide.isPrimaryHidden {
                let titleText = (slide.coverTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let showsPlaceholder = titleText.isEmpty && isEditingText
                DraggableTextBlock(
                    id: .primary,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .primary,
                    savedOffset: offsetBinding(for: .primary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.primary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.primary) },
                    content: {
                    Text(showsPlaceholder ? "Add a title" : titleText)
                        .font(.system(size: width * 0.085 * slide.textStyle.primary.sizeScale,
                                      weight: studioFontWeight(base: .heavy,
                                                               isBold: slide.textStyle.primary.isBold),
                                      design: slide.textStyle.primary.fontDesign.design))
                        .foregroundColor(
                            showsPlaceholder
                                ? studioEffectiveForegroundColor(slide.textStyle.primary).opacity(0.55)
                                : studioEffectiveForegroundColor(slide.textStyle.primary))
                        .lineLimit(3)
                        .multilineTextAlignment(
                            slide.textStyle.primary.resolvedMultilineAlignment(fallback: .center))
                        .studioTextFormat(slide.textStyle.primary)
                        .studioTextPill(slide.textStyle.primary,
                                        cornerRadius: width * 0.055,
                                        hPadding: width * 0.04,
                                        vPadding: width * 0.022)
                        .padding(.horizontal, width * 0.038)
                    },
                    textSizeScaleForPinch: slide.textStyle.primary.sizeScale,
                    onUpdateTextSizeScale: onUpdateTextSizeScale,
                    onTextPinchBegan: onTextPinchBegan
                )
            }
        }
        // Map heading — top-leading (hidden on split map slides: photo half carries the title /
        // place-intro split paints the same headline via the place-style block below).
        .overlay(alignment: .topLeading) {
            if !showsBackgroundOnly,
               isCarouselStudioMapKind(slide.kind),
               slide.layout != .split,
               !slide.isPrimaryHidden {
                DraggableTextBlock(
                    id: .primary,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .primary,
                    savedOffset: offsetBinding(for: .primary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.primary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.primary) },
                    content: {
                    VStack(alignment: slide.textStyle.primary.alignment.stackAlignment(fallback: .leading),
                           spacing: 4) {
                        // Must match `currentBlockText` / `commitInlineTextEdit` for map-style slides `.primary`:
                        // `loadSlides` seeds the heading in `dayInfoLine1` with `dayTitle` nil, so edits
                        // that only set `dayTitle` would otherwise not change what we paint here.
                        if let l1 = slide.dayTitle ?? slide.dayInfoLine1 {
                            Text(l1)
                                .font(.system(size: width * 0.075 * slide.textStyle.primary.sizeScale,
                                              weight: studioFontWeight(base: .heavy,
                                                                       isBold: slide.textStyle.primary.isBold),
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary))
                                .multilineTextAlignment(
                                    slide.textStyle.primary.resolvedMultilineAlignment(fallback: .leading))
                                .studioTextFormat(slide.textStyle.primary)
                        }
                        if let l2 = slide.dayInfoLine2 {
                            Text(l2)
                                .font(.system(size: width * 0.038 * slide.textStyle.primary.sizeScale,
                                              weight: studioFontWeight(base: .semibold,
                                                                       isBold: slide.textStyle.primary.isBold),
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary,
                                                                                naturalOpacity: 0.88))
                                .lineLimit(1)
                                .multilineTextAlignment(
                                    slide.textStyle.primary.resolvedMultilineAlignment(fallback: .leading))
                                .studioTextFormat(slide.textStyle.primary)
                        }
                    }
                    .studioTextPill(slide.textStyle.primary,
                                    cornerRadius: width * 0.045,
                                    hPadding: width * 0.032,
                                    vPadding: width * 0.02)
                    .padding(width * 0.038)
                    },
                    textSizeScaleForPinch: slide.textStyle.primary.sizeScale,
                    onUpdateTextSizeScale: onUpdateTextSizeScale,
                    onTextPinchBegan: onTextPinchBegan
                )
                // Nudge the block inward by the same amount the clamp enforces,
                // so a fresh `savedOffset == .zero` already renders at the
                // clamp's resting position (no visible snap on first tap).
                .padding(studioTextBlockEdgeInset)
            }
        }
        // Map story — bottom-leading
        .overlay(alignment: .bottomLeading) {
            let storyText = (slide.dayStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !showsBackgroundOnly, isCarouselStudioMapKind(slide.kind), !slide.isSecondaryHidden, !storyText.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .secondary,
                    savedOffset: offsetBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.secondary) },
                    content: {
                    Text(storyText)
                        .font(.system(size: width * 0.042 * slide.textStyle.secondary.sizeScale,
                                      weight: studioFontWeight(base: .regular,
                                                               isBold: slide.textStyle.secondary.isBold),
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.secondary,
                                                                        naturalOpacity: 0.88))
                        .lineLimit(4)
                        .multilineTextAlignment(
                            slide.textStyle.secondary.resolvedMultilineAlignment(fallback: .leading))
                        .studioTextFormat(slide.textStyle.secondary)
                        .studioTextPill(slide.textStyle.secondary,
                                        cornerRadius: width * 0.038,
                                        hPadding: width * 0.03,
                                        vPadding: width * 0.018)
                        .padding(width * 0.038)
                    },
                    textSizeScaleForPinch: slide.textStyle.secondary.sizeScale,
                    onUpdateTextSizeScale: onUpdateTextSizeScale,
                    onTextPinchBegan: onTextPinchBegan
                )
                .padding(studioTextBlockEdgeInset)
            }
        }
        // Bloggo watermark — bottom-leading on map slides (first Studio map only when `showPoweredByBloggoMapWatermark`).
        .overlay(alignment: .bottomLeading) {
            if !showsBackgroundOnly, isCarouselStudioMapKind(slide.kind), showPoweredByBloggoMapWatermark {
                HStack(spacing: width * 0.025) {
                    Image("AppIconMark")
                        .resizable()
                        .scaledToFill()
                        .frame(width: width * 0.072, height: width * 0.072)
                        .clipShape(RoundedRectangle(cornerRadius: width * 0.016))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    VStack(alignment: .leading, spacing: width * 0.006) {
                        HStack(spacing: width * 0.012) {
                            Text("Powered by")
                                .font(.system(size: width * 0.028, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Text("Bloggo")
                                .font(.system(size: width * 0.028, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                        }
                        Text("Available on the App Store")
                            .font(.system(size: width * 0.022, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, width * 0.034)
                .padding(.vertical, width * 0.022)
                .background(Color.black.opacity(0.45))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.04))
                .padding(width * 0.042)
            }
        }
        // Legacy place‑intro strip (full‑bleed map + thumbnails) when not using split layout.
        .overlay(alignment: .bottom) {
            if !showsBackgroundOnly, slide.kind == .placeIntroMap, slide.layout != .split,
               !slide.placeIntroBottomPhotos.isEmpty {
                let thumbW = width * 0.166
                let thumbH = thumbW * 4.0 / 3.0
                HStack(spacing: width * 0.014) {
                    ForEach(Array(slide.placeIntroBottomPhotos.prefix(3).enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbW, height: thumbH)
                            .clipShape(RoundedRectangle(cornerRadius: width * 0.018, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: width * 0.018, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.92), lineWidth: max(1.5, width * 0.004))
                            )
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                    }
                }
                .padding(.horizontal, width * 0.02)
                .padding(.bottom, width * 0.17)
            }
        }
        // Place name + caption — anchor driven by `placeZoneLayout` (full slide for `.placeStop`).
        .overlay(alignment: slide.placeZoneLayout.primaryOverlayAlignment) {
            let isPlaceIntroSplitPrimary = slide.kind == .placeIntroMap
                && slide.layout == .split
                && slide.placeStop != nil
            if !showsBackgroundOnly,
               slide.kind == .placeStop,
               !isPlaceIntroSplitPrimary,
               !slide.isPrimaryHidden,
               let placeStop = slide.placeStop {
                    DraggableTextBlock(
                        id: .primary,
                        isEditingText: isEditingText,
                        showsEditingOutline: showsDraggableBlockOutlines,
                        isSelected: selectedBlockID == .primary,
                        savedOffset: offsetBinding(for: .primary),
                        slideBounds: slideBounds,
                        onSelect: { onSelectBlock?(.primary) },
                        onDragStart: { onBlockDragStart?() },
                        onDragEnd: { onBlockDragEnd?() },
                        onTap: { onBlockTap?(.primary) },
                        content: {
                        VStack(alignment: slide.placeZoneLayout.primaryHorizontalFallback(for: slide.textStyle.primary),
                               spacing: 4) {
                            HStack(alignment: .center, spacing: 6) {
                                if slide.stopIndex != nil {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: width * 0.062 * slide.textStyle.primary.sizeScale,
                                                      weight: .medium))
                                        .foregroundStyle(studioEffectiveForegroundColor(slide.textStyle.primary))
                                        .symbolRenderingMode(.monochrome)
                                }
                                Text(studioSplitOrPlacePrimaryTitle(slide: slide, placeStop: placeStop))
                                    .font(.system(size: width * 0.065 * slide.textStyle.primary.sizeScale,
                                                  weight: studioFontWeight(base: .bold,
                                                                           isBold: slide.textStyle.primary.isBold),
                                                  design: slide.textStyle.primary.fontDesign.design))
                                    .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary))
                                    .lineLimit(2)
                                    .multilineTextAlignment(
                                        slide.placeZoneLayout.primaryTextAlignmentFallback(for: slide.textStyle.primary))
                                    .studioTextFormat(slide.textStyle.primary)
                            }
                            let primaryCaption = (slide.photoCaption ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !primaryCaption.isEmpty {
                                Text(primaryCaption)
                                    .font(.system(size: width * 0.044 * slide.textStyle.primary.sizeScale,
                                                  weight: studioFontWeight(base: .regular,
                                                                           isBold: slide.textStyle.primary.isBold),
                                                  design: slide.textStyle.primary.fontDesign.design))
                                    .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary,
                                                                                    naturalOpacity: 0.85))
                                    .lineLimit(3)
                                    .multilineTextAlignment(
                                        slide.placeZoneLayout.primaryTextAlignmentFallback(for: slide.textStyle.primary))
                                    .studioTextFormat(slide.textStyle.primary)
                            }
                        }
                        .studioTextPill(slide.textStyle.primary,
                                        cornerRadius: width * 0.045,
                                        hPadding: width * 0.032,
                                        vPadding: width * 0.02)
                        .padding(width * 0.038)
                        },
                        textSizeScaleForPinch: slide.textStyle.primary.sizeScale,
                        onUpdateTextSizeScale: onUpdateTextSizeScale,
                        onTextPinchBegan: onTextPinchBegan
                    )
                    .padding(studioTextBlockEdgeInset)
            } else if !showsBackgroundOnly, slide.kind == .placeStop {
                Text("Missing place data")
                    .font(.system(size: width * 0.05, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(width * 0.038)
                    .padding(studioTextBlockEdgeInset)
            }
        }
        // `.placeIntroMap` + split: primary must sit inside the **top photo strip** only (not over the map).
        .overlay(alignment: .topLeading) {
            let isPlaceIntroSplitPrimary = slide.kind == .placeIntroMap
                && slide.layout == .split
                && slide.placeStop != nil
            if !showsBackgroundOnly, isPlaceIntroSplitPrimary, !slide.isPrimaryHidden, let placeStop = slide.placeStop {
                let photoH = height * mapSplitPhotoFractionForStudioMapSplit()
                let photoStripBounds = CGRect(x: 0, y: 0, width: width, height: photoH)
                DraggableTextBlock(
                    id: .primary,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .primary,
                    savedOffset: offsetBinding(for: .primary),
                    slideBounds: photoStripBounds,
                    onSelect: { onSelectBlock?(.primary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.primary) },
                    content: {
                    VStack(alignment: slide.placeZoneLayout.primaryHorizontalFallback(for: slide.textStyle.primary),
                           spacing: 4) {
                        Text(studioSplitOrPlacePrimaryTitle(slide: slide, placeStop: placeStop))
                            .font(.system(size: width * 0.065 * slide.textStyle.primary.sizeScale,
                                          weight: studioFontWeight(base: .heavy,
                                                                   isBold: slide.textStyle.primary.isBold),
                                          design: slide.textStyle.primary.fontDesign.design))
                            .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary))
                            .lineLimit(2)
                            .multilineTextAlignment(
                                slide.placeZoneLayout.primaryTextAlignmentFallback(for: slide.textStyle.primary))
                            .studioTextFormat(slide.textStyle.primary)
                        if let city = studioPlaceIntroSplitCityLine(slide: slide, placeStop: placeStop) {
                            Text(city)
                                .font(.system(size: width * 0.038 * slide.textStyle.primary.sizeScale,
                                              weight: studioFontWeight(base: .semibold,
                                                                       isBold: slide.textStyle.primary.isBold),
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary,
                                                                                naturalOpacity: 0.88))
                                .lineLimit(1)
                                .multilineTextAlignment(
                                    slide.placeZoneLayout.primaryTextAlignmentFallback(for: slide.textStyle.primary))
                                .studioTextFormat(slide.textStyle.primary)
                        }
                    }
                    .studioTextPill(slide.textStyle.primary,
                                    cornerRadius: width * 0.045,
                                    hPadding: width * 0.032,
                                    vPadding: width * 0.02)
                    .padding(width * 0.038)
                    },
                    textSizeScaleForPinch: slide.textStyle.primary.sizeScale,
                    onUpdateTextSizeScale: onUpdateTextSizeScale,
                    onTextPinchBegan: onTextPinchBegan
                )
                .padding(studioTextBlockEdgeInset)
                .frame(width: width, height: photoH, alignment: .topLeading)
            }
        }
        // Place subtitle (city, country) — top anchor from `placeZoneLayout` (`.placeStop` only;
        // `.placeIntroMap` + split keeps city on the photo with the place name, like the original map heading).
        .overlay(alignment: slide.placeZoneLayout.secondaryOverlayAlignment) {
            let subtitleText = (slide.placeStop?.placeSubtitle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !showsBackgroundOnly,
               slide.kind == .placeStop,
               !slide.isSecondaryHidden,
               !subtitleText.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .secondary,
                    savedOffset: offsetBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.secondary) },
                    content: {
                    Text(subtitleText)
                        .font(.system(size: width * 0.048 * slide.textStyle.secondary.sizeScale,
                                      weight: studioFontWeight(base: .regular,
                                                               isBold: slide.textStyle.secondary.isBold),
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.secondary,
                                                                        naturalOpacity: 0.85))
                        .lineLimit(1)
                        .multilineTextAlignment(
                            slide.placeZoneLayout.secondaryTextAlignmentFallback(for: slide.textStyle.secondary))
                        .studioTextFormat(slide.textStyle.secondary)
                        .studioTextPill(slide.textStyle.secondary,
                                        cornerRadius: width * 0.038,
                                        hPadding: width * 0.03,
                                        vPadding: width * 0.018)
                        .padding(width * 0.038)
                    },
                    textSizeScaleForPinch: slide.textStyle.secondary.sizeScale,
                    onUpdateTextSizeScale: onUpdateTextSizeScale,
                    onTextPinchBegan: onTextPinchBegan
                )
                .padding(studioTextBlockEdgeInset)
            }
        }
        // PIP thumbnail cluster — top corner from `placeZoneLayout` (trailing or leading)
        .overlay(alignment: slide.kind == .placeStop ? slide.placeZoneLayout.pipOverlayAlignment : .topTrailing) {
            pipThumbnailClusterOverlay
        }
        // ── Chrome ────────────────────────────────────────────────────
        .overlay(alignment: .topTrailing) {
            if showsSelectionChrome {
                Button(action: onToggleSelection) {
                    Label(slide.isSelected ? "Deselect" : "Select", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: width * 0.06, weight: .bold))
                        .foregroundColor(.white)
                        .padding(width * 0.04)
                        .background(slide.isSelected ? Color.blue : Color.black.opacity(0.35), in: Circle())
                }
                .padding(width * 0.04)
            }
        }
        .overlay {
            if showsSelectionChrome && !slide.isSelected {
                ZStack {
                    Color.black.opacity(0.45)
                    Text("Not Selected")
                        .font(.system(size: width * 0.05, weight: .semibold))
                        .foregroundColor(.white)
                }
                // Dim sits above the hero tap catcher; without this, taps never reach
                // `onCoverImageTap` when the cover slide is deselected.
                .allowsHitTesting(!(slide.kind == .cover && onCoverImageTap != nil))
            }
        }
        .frame(width: width, height: height)
        .coordinateSpace(name: studioSlideCoordSpace)
        .clipCarouselPostcardOutline(
            clipsFloatingContentToRoundedSlideOutline && !pipClusterNeedsUnclippedFloatingChrome
        )
        .opacity(showsSelectionChrome && !slide.isSelected ? 0.72 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // Social Post Studio: cover `onCoverImageTap` sits inside the photo stack. A parent
        // `onTapGesture` here would compete with (and often swallow) that tap, so omit the
        // card-wide toggle when changing the studio cover from the hero — use the checkmark.
        .optionalOnTapGesture(
            isEnabled: showsSelectionChrome && !(slide.kind == .cover && onCoverImageTap != nil),
            perform: onToggleSelection
        )
        .animation(.easeInOut(duration: 0.2), value: slide.isSelected)
    }

    @ViewBuilder
    private var pipThumbnailClusterOverlay: some View {
        if !showsBackgroundOnly, slide.kind == .placeStop, slide.layout == .pip, !slide.pipImages.isEmpty {
            // For centered-text layouts the subtitle spans the full top edge, so push
            // the cluster down enough to clear it (~0.16w tall). Side-text layouts place
            // the subtitle on the opposite corner from the cluster, so a small inset suffices.
            let isCenteredText = slide.placeZoneLayout == .textCenterPhotosTrailing
                || slide.placeZoneLayout == .textCenterPhotosTrailingRaisedPrimary
            let extraTopInset = isCenteredText ? max(22, width * 0.22) : max(14, width * 0.085)
            if slide.pipIsUngrouped {
                let clamped = max(0, min(slide.pipVisibleCount, min(slide.effectivePIPImages.count, 3)))
                ZStack(alignment: slide.placeZoneLayout.pipZStackAlignment) {
                    ForEach(slide.pipUngroupedDrawOrder(visibleCount: clamped), id: \.self) { i in
                        let photoStyle = slide.effectivePIPPhotoStyle(at: i)
                        DraggablePIPThumb(
                            savedOffset: pipPhotoOffsetBinding(at: i),
                            slideBounds: slideBounds,
                            onDragStart: { onBlockDragStart?() },
                            onDragEnd: { onBlockDragEnd?() },
                            onSelect: { onSelectPIPPhoto?(i) },
                            image: slide.effectivePIPImages[i],
                            imageIndex: i,
                            framing: i < slide.pipThumbnailFramings.count ? slide.pipThumbnailFramings[i] : nil,
                            slideWidth: width,
                            pipBorderEnabled: photoStyle.borderEnabled && slide.effectivePIPInsetBorderEnabled(at: i),
                            borderColor: photoStyle.borderColor.color,
                            thumbMaskStyle: photoStyle.thumbMaskStyle,
                            sizeScale: slide.effectivePIPPhotoSizeScale(at: i),
                            isEditingText: isEditingText,
                            isSelected: selectedPIPPhotoIndex == i,
                            showsEditingOutline: showsDraggableBlockOutlines,
                            onThumbDoubleTapReplace: (isEditingText ? onPIPClusterThumbTap : nil),
                            showsBackgroundRemovalLoading: pipBackgroundRemovalLoadingSlots.contains(i),
                            onClusterPinchScale: (isEditingText && selectedPIPPhotoIndex == i)
                                ? { scale, isCommit in onPIPClusterPinchScale?(scale, isCommit) }
                                : nil,
                            onClusterPinchBegan: onPIPClusterPinchBegan
                        )
                        .padding(.horizontal, studioPIPClusterEdgeInset)
                        .padding(.bottom, studioPIPClusterEdgeInset)
                        .padding(.top, studioPIPClusterEdgeInset + extraTopInset)
                    }
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                DraggablePIPCluster(
                    savedOffset: pipOffsetBinding,
                    slideBounds: slideBounds,
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onSelect: { onSelectBlock?(.pipCluster) },
                    images: slide.effectivePIPImages,
                    pipPhotoIDs: slide.pipPhotoIDs,
                    thumbnailFramings: slide.pipThumbnailFramings,
                    slideWidth: width,
                    pipBorderEnabled: slide.pipBorderEnabled,
                    pipThumbBorderEnabled: { idx in slide.effectivePIPInsetBorderEnabled(at: idx) },
                    borderColor: slide.pipBorderColor.color,
                    visibleCount: slide.pipVisibleCount,
                    stackStyle: slide.pipClusterStackStyle,
                    pipSizeScale: slide.pipClusterSizeScale,
                    thumbMaskStyle: slide.pipThumbMaskStyle,
                    isEditingText: isEditingText,
                    showsEditingOutline: showsDraggableBlockOutlines,
                    isSelected: selectedBlockID == .pipCluster,
                    backgroundRemovalLoadingSlots: pipBackgroundRemovalLoadingSlots,
                    onClusterThumbTap: (isEditingText && slide.layout == .pip && !slide.pipIsUngrouped
                        ? onPIPClusterThumbTap
                        : nil),
                    onClusterPinchScale: (isEditingText && selectedBlockID == .pipCluster
                        ? { scale, isCommit in onPIPClusterPinchScale?(scale, isCommit) }
                        : nil),
                    onClusterPinchBegan: onPIPClusterPinchBegan
                )
                .padding(.horizontal, studioPIPClusterEdgeInset)
                .padding(.bottom, studioPIPClusterEdgeInset)
                .padding(.top, studioPIPClusterEdgeInset + extraTopInset)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    // MARK: - Backgrounds

    private var coverBackground: some View {
        Group {
            if let image = slide.heroImage {
                Image(uiImage: image).resizable().scaledToFill().scaleEffect(heroImageScale)
            } else {
                LinearGradient(colors: [Color(red: 26/255, green: 26/255, blue: 46/255),
                                        Color(red: 45/255, green: 53/255, blue: 97/255)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: width, height: height).clipped()
    }

    private var fullBleedMapBackground: some View {
        Group {
            if let image = slide.mapSnapshot {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(red: 12/255, green: 16/255, blue: 33/255)
            }
        }
        .frame(width: width, height: height).clipped()
    }

    /// Cover photo in the top half (slight transparency) + map in the bottom half.
    private var splitMapSplitBackground: some View {
        let slotW = width
        let useCurvedMasks = slide.splitDividerStyle == .curve
        let seamBleed = useCurvedMasks ? min(22, max(10, slotW * 0.038)) : 0
        let photoExtraY = useCurvedMasks ? Self.mapCurvedSplitPhotoExtraHeight(forSlideHeight: height) : 0
        let photoH = height * Self.mapSplitPhotoHeightFraction + photoExtraY
        let mapH = height * (1 - Self.mapSplitPhotoHeightFraction) - photoExtraY
        // Curved masks: map top seam sits at `photoH`, photo bottom seam at `photoH + seamBleed`. A stroke
        // centered only on `photoH` reads as sitting in the photo (thick glow is half above the path).
        let seamOutlineY = useCurvedMasks
            ? (photoH + seamBleed * 0.50 + 0.5)
            : photoH
        // Curved masks use negative spacing + `seamBleed`; optional stroked seam follows the same curve.
        return ZStack(alignment: .top) {
            VStack(spacing: useCurvedMasks ? -seamBleed : 0) {
                // TOP: cover photo (half height) — slight transparency over the curved seam into the map.
                Group {
                    if useCurvedMasks {
                        Group {
                            if let bottom = slide.splitBottomImage {
                                SplitFramedPhotoInSlot(
                                    image: bottom,
                                    framing: slide.splitBottomFraming,
                                    slotWidth: slotW,
                                    slotHeight: photoH
                                )
                            } else {
                                ZStack {
                                    Color(white: 0.13)
                                    if isEditingText {
                                        VStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: width * 0.08, weight: .semibold))
                                            Text("Tap to pick photo")
                                                .font(.system(size: width * 0.04, weight: .semibold))
                                        }
                                        .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                                .frame(width: slotW, height: photoH)
                            }
                        }
                        .opacity(0.8)
                        .clipShape(CurvedSplitTopMaskShape())
                        .frame(width: slotW, height: photoH + seamBleed)
                    } else {
                        Group {
                            if let bottom = slide.splitBottomImage {
                                SplitFramedPhotoInSlot(
                                    image: bottom,
                                    framing: slide.splitBottomFraming,
                                    slotWidth: slotW,
                                    slotHeight: photoH
                                )
                            } else {
                                ZStack {
                                    Color(white: 0.13)
                                    if isEditingText {
                                        VStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: width * 0.08, weight: .semibold))
                                            Text("Tap to pick photo")
                                                .font(.system(size: width * 0.04, weight: .semibold))
                                        }
                                        .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                                .frame(width: slotW, height: photoH)
                            }
                        }
                        .opacity(0.8)
                        .frame(width: slotW, height: photoH)
                    }
                }

                // BOTTOM: map snapshot (lower half)
                Group {
                    if useCurvedMasks {
                        Group {
                            if let map = slide.mapSnapshot {
                                SplitFramedPhotoInSlot(
                                    image: map,
                                    framing: slide.splitTopFraming,
                                    slotWidth: slotW,
                                    slotHeight: mapH
                                )
                            } else {
                                Color(red: 12/255, green: 16/255, blue: 33/255)
                                    .frame(width: slotW, height: mapH)
                            }
                        }
                        .clipShape(CurvedSplitBottomMaskShape())
                        .frame(width: slotW, height: mapH + seamBleed)
                    } else {
                        Group {
                            if let map = slide.mapSnapshot {
                                SplitFramedPhotoInSlot(
                                    image: map,
                                    framing: slide.splitTopFraming,
                                    slotWidth: slotW,
                                    slotHeight: mapH
                                )
                            } else {
                                Color(red: 12/255, green: 16/255, blue: 33/255)
                                    .frame(width: slotW, height: mapH)
                            }
                        }
                        .frame(width: slotW, height: mapH)
                    }
                }
            }
            splitSeamOutline(photoJoinY: seamOutlineY)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// White seam on the split boundary (straight bar or curved stroke aligned with split masks). Map + place slides.
    @ViewBuilder
    private func splitSeamOutline(photoJoinY: CGFloat) -> some View {
        let curveBandH: CGFloat = 48
        Group {
            if slide.splitDividerStyle == .straight {
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width, height: 3.5)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 0.5)
            } else {
                ZStack {
                    CurvedSplitDividerShape()
                        .stroke(Color.white.opacity(0.34), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    CurvedSplitDividerShape()
                        .stroke(Color.white.opacity(0.96), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                .frame(width: width, height: curveBandH)
                .shadow(color: .black.opacity(0.28), radius: 2.5, x: 0, y: 1)
            }
        }
        .transition(.identity)
        .transaction { t in
            t.animation = nil
            t.disablesAnimations = true
        }
        .position(x: width * 0.5, y: photoJoinY)
    }

    @ViewBuilder
    private var placeStopBackground: some View {
        if slide.layout == .split {
            splitPlaceStopBackground
        } else {
            coverBackground
        }
    }

    private var splitPlaceStopBackground: some View {
        let slotW = width
        let slotH = height * 0.5
        let useCurvedMasks = slide.splitDividerStyle == .curve
        // Curved seams need vertical bleed so the bezier can travel above/below the
        // nominal split line without flattening near the corners (especially bottom-left).
        let seamBleed = useCurvedMasks ? min(22, max(10, slotW * 0.038)) : 0
        let seamOutlineY = useCurvedMasks
            ? (slotH + seamBleed * 0.50 + 0.5)
            : slotH
        return ZStack(alignment: .top) {
            VStack(spacing: useCurvedMasks ? -seamBleed : 0) {
                Group {
                    if useCurvedMasks {
                        Group {
                            if let image = slide.heroImage {
                                SplitFramedPhotoInSlot(
                                    image: image,
                                    framing: slide.splitTopFraming,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                            } else {
                                Color(white: 0.16)
                                    .frame(width: slotW, height: slotH)
                            }
                        }
                        .clipShape(CurvedSplitTopMaskShape())
                        .frame(width: slotW, height: slotH + seamBleed)
                    } else {
                        Group {
                            if let image = slide.heroImage {
                                SplitFramedPhotoInSlot(
                                    image: image,
                                    framing: slide.splitTopFraming,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                            } else {
                                Color(white: 0.16)
                                    .frame(width: slotW, height: slotH)
                            }
                        }
                        .frame(width: slotW, height: slotH)
                    }
                }

                Group {
                    if useCurvedMasks {
                        Group {
                            if let bottom = slide.splitBottomImage {
                                SplitFramedPhotoInSlot(
                                    image: bottom,
                                    framing: slide.splitBottomFraming,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                            } else {
                                ZStack {
                                    Color(white: 0.13)
                                    if isEditingText {
                                        VStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: width * 0.08, weight: .semibold))
                                            Text("Tap to pick second photo")
                                                .font(.system(size: width * 0.04, weight: .semibold))
                                        }
                                        .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                                .frame(width: slotW, height: slotH)
                            }
                        }
                        .clipShape(CurvedSplitBottomMaskShape())
                        .frame(width: slotW, height: slotH + seamBleed)
                    } else {
                        Group {
                            if let bottom = slide.splitBottomImage {
                                SplitFramedPhotoInSlot(
                                    image: bottom,
                                    framing: slide.splitBottomFraming,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                            } else {
                                ZStack {
                                    Color(white: 0.13)
                                    if isEditingText {
                                        VStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: width * 0.08, weight: .semibold))
                                            Text("Tap to pick second photo")
                                                .font(.system(size: width * 0.04, weight: .semibold))
                                        }
                                        .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                                .frame(width: slotW, height: slotH)
                            }
                        }
                        .frame(width: slotW, height: slotH)
                    }
                }
            }
            splitSeamOutline(photoJoinY: seamOutlineY)
        }
        .frame(width: width, height: height)
        .clipped()
    }

}

private extension View {
    /// Applies `onTapGesture` only when `isEnabled` is true, so other tap targets on the same
    /// card (e.g. cover hero → studio cover picker) are not blocked by a parent tap handler.
    @ViewBuilder
    func optionalOnTapGesture(isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        if isEnabled {
            self.onTapGesture(perform: action)
        } else {
            self
        }
    }

    /// Attaches a gesture only when needed. `simultaneousGesture` is required so vertical
    /// swipe-up can coexist with a parent horizontal `ScrollView` (`.gesture` loses to it).
    @ViewBuilder
    func studioPreviewStripSwipeGesture<G: Gesture>(_ isEnabled: Bool, _ gesture: G) -> some View {
        if isEnabled {
            self.simultaneousGesture(gesture)
        } else {
            self
        }
    }
}

// MARK: - PIP Cluster

/// Stacked photo thumbnails rendered in the top-trailing corner for PIP layout.
/// Up to 3 images can be shown (clamped by `visibleCount`); each has a user-
/// configurable outline color, drop shadow, and a small alternating rotation
/// for an editorial "spread" feel.
private struct PIPClusterView: View {
    let images: [UIImage]
    /// Parallel to `images` for visible slots; stable `ForEach` identity across edits.
    var pipPhotoIDs: [UUID] = []
    let slideWidth: CGFloat
    /// Outline color when `pipBorderEnabled` (same as slide `pipBorderColor`).
    var borderColor: Color = .white
    /// When false, no thumbnail outline is drawn. May be combined with
    /// `pipThumbBorderEnabled` for per-index cutout borders.
    var pipBorderEnabled: Bool = true
    /// When set, overrides `pipBorderEnabled` for the inset at that image index (export + editor).
    var pipThumbBorderEnabled: ((Int) -> Bool)? = nil
    /// Maximum number of thumbnails to render (1 ... 3). Further clamped by
    /// the number of supplied images, so at most `min(images.count, visibleCount)`
    /// tiles ever appear.
    var visibleCount: Int = 3
    var stackStyle: CarouselPIPClusterStackStyle = .vertical
    /// 1.0 = default thumbnail width; clamped in the editor before assignment.
    var sizeScale: CGFloat = 1.0
    var thumbMaskStyle: CarouselPIPThumbMaskStyle = .roundedRect
    /// Per-stack-slot indices (0…2) showing a small progress cue while Vision runs.
    var backgroundRemovalLoadingSlots: Set<Int> = []

    private var thumbW: CGFloat { slideWidth * 0.30 * sizeScale }
    private var thumbH: CGFloat { thumbW * 0.72 }
    /// In circle mode the slot is square (`thumbW` × `thumbW`); otherwise classic postcard aspect.
    private var slotW: CGFloat { thumbW }
    private var slotH: CGFloat { thumbMaskStyle == .circle ? thumbW : thumbH }
    private let rotations: [Double] = [1.5, -1.0, 1.8]

    private struct PIPThumbTile: Identifiable {
        let id: AnyHashable
        let image: UIImage
        /// Index into `pipImages` / `thumbnailFramings` (stable even when the row is reversed for layout).
        let imageIndex: Int
        /// Stack position (0,1,2) for rotation styling — not the photo's identity.
        let slot: Int
    }

    /// Parallel to `pipImages`; may be shorter — missing entries read as default framing.
    var thumbnailFramings: [StudioImageFraming?] = []
    /// Grouped Multi mode: double-tap an inset thumbnail to replace that slot (parent presents picker).
    var onClusterThumbTap: ((Int) -> Void)? = nil

    private var shownThumbnails: [PIPThumbTile] {
        let clamped = max(0, min(visibleCount, min(images.count, 3)))
        return (0..<clamped).map { i in
            let id: AnyHashable = (i < pipPhotoIDs.count) ? pipPhotoIDs[i] : i
            return PIPThumbTile(id: id, image: images[i], imageIndex: i, slot: i)
        }
    }

    private func thumbnailFraming(at imageIndex: Int) -> StudioImageFraming? {
        guard imageIndex >= 0, imageIndex < thumbnailFramings.count else { return nil }
        return thumbnailFramings[imageIndex]
    }

    var body: some View {
        Group {
            switch stackStyle {
            case .vertical:
                VStack(alignment: .trailing, spacing: 5) { pipThumbnails }
            case .horizontal:
                // Keep slot 0 nearest the top-trailing anchor (same as vertical), so the
                // row grows leftward from the corner instead of pushing the hero thumb away.
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(shownThumbnails.reversed())) { tile in
                        pipThumb(tile)
                    }
                }
            }
        }
        // No internal top/trailing padding: cluster frame = visible thumbs, so the user can drag
        // PIP all the way into the top-right corner and the studio default sits flush to it.
        .animation(.easeInOut(duration: 0.2), value: stackStyle)
        .animation(.easeInOut(duration: 0.2), value: thumbMaskStyle)
    }

    @ViewBuilder
    private var pipThumbnails: some View {
        ForEach(shownThumbnails) { tile in
            pipThumb(tile)
        }
    }

    @ViewBuilder
    private func pipThumb(_ tile: PIPThumbTile) -> some View {
        let borderOn = pipThumbBorderEnabled?(tile.imageIndex) ?? pipBorderEnabled
        ZStack(alignment: .bottomTrailing) {
            let photo = SplitFramedPhotoInSlot(
                image: tile.image,
                framing: thumbnailFraming(at: tile.imageIndex),
                slotWidth: slotW,
                slotHeight: slotH
            )
            Group {
                if thumbMaskStyle == .circle {
                    photo
                        .clipShape(Circle())
                        .overlay {
                            if borderOn {
                                Circle()
                                    .strokeBorder(borderColor, lineWidth: 2.2)
                            }
                        }
                } else {
                    photo
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if borderOn {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(borderColor, lineWidth: 2.2)
                            }
                        }
                }
            }
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
            if backgroundRemovalLoadingSlots.contains(tile.slot) {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(.white)
                    .padding(5)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(4)
            }
        }
        .rotationEffect(.degrees(shownThumbnails.count > 1 ? rotations[tile.slot % rotations.count] : 0))
        .modifier(PIPClusterThumbTapModifier(
            imageIndex: tile.imageIndex,
            onSingleTap: nil,
            onDoubleTap: onClusterThumbTap
        ))
    }
}

/// Inset thumbnail gestures for Multi replace (double-tap) and optional single-tap.
/// Double-tap is used so it does not compete with drag-to-reposition on the cluster.
private struct PIPClusterThumbTapModifier: ViewModifier {
    let imageIndex: Int
    var onSingleTap: ((Int) -> Void)?
    var onDoubleTap: ((Int) -> Void)?

    func body(content: Content) -> some View {
        if let onDoubleTap {
            if let onSingleTap {
                content
                    .onTapGesture(count: 2) { onDoubleTap(imageIndex) }
                    .onTapGesture(count: 1) { onSingleTap(imageIndex) }
            } else {
                content.onTapGesture(count: 2) { onDoubleTap(imageIndex) }
            }
        } else if let onSingleTap {
            content.onTapGesture { onSingleTap(imageIndex) }
        } else {
            content
        }
    }
}

// MARK: - Draggable PIP Cluster

/// Wraps `PIPClusterView` with a drag gesture so the user can reposition the
/// thumbnail stack anywhere on the slide. The committed position is stored as a
/// normalized fraction of `slideBounds` (same convention as `TextBlockStyle.offset`)
/// so it renders correctly at every output size (editor / preview / export).
///
/// In editor mode (`isEditingText`), the cluster also behaves like a text block:
/// a tap (gesture with <`tapSlop` movement) selects it so the PIP-specific
/// toolbar can show, and a blue ring is drawn around the bounding rect while
/// selected. Drags reposition as before, with no selection side-effects.
private struct DraggablePIPCluster: View {
    @Binding var savedOffset: CGSize
    let slideBounds: CGRect
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onSelect: () -> Void = {}
    let images: [UIImage]
    var pipPhotoIDs: [UUID] = []
    var thumbnailFramings: [StudioImageFraming?] = []
    let slideWidth: CGFloat
    var pipBorderEnabled: Bool = true
    /// Per inset image index; when non-nil, overrides `pipBorderEnabled` for that thumb.
    var pipThumbBorderEnabled: ((Int) -> Bool)? = nil
    var borderColor: Color = .white
    var visibleCount: Int = 3
    var stackStyle: CarouselPIPClusterStackStyle = .vertical
    var pipSizeScale: CGFloat = 1.0
    var thumbMaskStyle: CarouselPIPThumbMaskStyle = .roundedRect
    /// True while the slide is in the full-screen text editor; enables the
    /// selection ring and routes taps through `onSelect`.
    var isEditingText: Bool = false
    /// When `false`, no cluster ring in edit mode until a block is selected on the slide.
    var showsEditingOutline: Bool = true
    /// True when `selectedBlock == .pipCluster` in the editor.
    var isSelected: Bool = false
    var backgroundRemovalLoadingSlots: Set<Int> = []
    /// Grouped cluster: tap a small photo to replace that inset slot (picker).
    var onClusterThumbTap: ((Int) -> Void)? = nil
    /// Pinch-to-resize cluster footprint (only when `isSelected`); `nil` disables pinch.
    /// Second bool: `true` when committing the snapped scale at gesture end.
    var onClusterPinchScale: ((CGFloat, Bool) -> Void)? = nil
    var onClusterPinchBegan: () -> Void = {}

    @GestureState private var liveDrag: CGSize = .zero
    @State private var naturalRect: CGRect?
    /// Avoid locking slide paging on tiny finger jitter; mirrors text-block tap slop.
    @State private var didBeginPIPClusterDrag = false
    @State private var pinchClusterBase: CGFloat = 1.0
    @State private var pinchClusterActive = false
    @State private var pinchSmoothedScale: CGFloat = 1.0

    private var savedPointOffset: CGSize {
        CGSize(width: savedOffset.width * slideBounds.width,
               height: savedOffset.height * slideBounds.height)
    }

    /// Same idea as `DraggableTextBlock.displayPointOffset` — clamp during drag so
    /// release does not rubber-band away from where the block visually sat.
    private var displayPointOffset: CGSize {
        clampedOffset(CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        ))
    }

    var body: some View {
        PIPClusterView(images: images,
                       pipPhotoIDs: pipPhotoIDs,
                       slideWidth: slideWidth,
                       borderColor: borderColor,
                       pipBorderEnabled: pipBorderEnabled,
                       pipThumbBorderEnabled: pipThumbBorderEnabled,
                       visibleCount: visibleCount,
                       stackStyle: stackStyle,
                       sizeScale: pipSizeScale,
                       thumbMaskStyle: thumbMaskStyle,
                       backgroundRemovalLoadingSlots: backgroundRemovalLoadingSlots,
                       thumbnailFramings: thumbnailFramings,
                       onClusterThumbTap: onClusterThumbTap)
            .background(naturalRectCapture)
            .overlay(selectionRing)
            .contentShape(Rectangle())
            .offset(x: displayPointOffset.width, y: displayPointOffset.height)
            // Thumbs use `PIPClusterThumbTapModifier` with `including: .subviews` on this
            // drag so inset taps reach the replace handler; drag matches the original tap/drag split.
            .highPriorityGesture(
                DragGesture(minimumDistance: isEditingText ? 0 : 4,
                            coordinateSpace: .local)
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onChanged { _ in
                        guard isEditingText else { return }
                        if !didBeginPIPClusterDrag {
                            didBeginPIPClusterDrag = true
                            onDragStart()
                        }
                    }
                    .onEnded { value in
                        let tapSlop: CGFloat = 6
                        let moved = max(abs(value.translation.width),
                                        abs(value.translation.height))
                        if moved < tapSlop {
                            if isEditingText { onSelect() }
                        } else {
                            let proposed = CGSize(
                                width: savedPointOffset.width + value.translation.width,
                                height: savedPointOffset.height + value.translation.height
                            )
                            let clamped = clampedOffset(proposed)
                            savedOffset = CGSize(
                                width: slideBounds.width > 0 ? clamped.width / slideBounds.width : 0,
                                height: slideBounds.height > 0 ? clamped.height / slideBounds.height : 0
                            )
                        }
                        didBeginPIPClusterDrag = false
                        onDragEnd()
                    },
                including: isEditingText ? .all : .subviews
            )
            .simultaneousGesture(clusterPinchGesture)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var clusterPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnitude in
                guard isEditingText, isSelected, let onScale = onClusterPinchScale else { return }
                if !pinchClusterActive {
                    pinchClusterActive = true
                    pinchClusterBase = pipSizeScale
                    pinchSmoothedScale = pipSizeScale
                    onClusterPinchBegan()
                }
                let raw = pinchClusterBase * magnitude
                let target = StudioPIPClusterSize.clampOnly(raw)
                pinchSmoothedScale += (target - pinchSmoothedScale) * studioPIPClusterPinchSmoothingBlend
                onScale(pinchSmoothedScale, false)
            }
            .onEnded { _ in
                let didPinch = pinchClusterActive
                if pinchClusterActive, isSelected, let onScale = onClusterPinchScale {
                    let committed = StudioPIPClusterSize.clampAndSnap(pinchSmoothedScale)
                    onScale(committed, true)
                }
                pinchClusterActive = false
                // Pinch is simultaneous with `DragGesture`; multi-touch can omit drag `onEnded`,
                // leaving `locksHorizontalSlidePaging` stuck after zoom — release it here.
                if didPinch {
                    didBeginPIPClusterDrag = false
                    onDragEnd()
                }
            }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isEditingText, showsEditingOutline {
            // Cluster frame is the visible thumb rect; expand the ring by a few points so
            // it visually hugs the tiles without sitting on top of them.
            let ringBreathing: CGFloat = 4
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected
                        ? CarouselStudioChrome.accent
                        : Color.white.opacity(0.35),
                    style: isSelected
                        ? StrokeStyle(lineWidth: 2.0)
                        : StrokeStyle(lineWidth: 1.0, dash: [5, 3])
                )
                .padding(-ringBreathing)
        }
    }

    @ViewBuilder
    private var naturalRectCapture: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { captureNaturalRect(from: geo) }
                .onChange(of: geo.size) { _, _ in captureNaturalRect(from: geo) }
                .onChange(of: slideBounds) { _, _ in
                    naturalRect = nil
                    captureNaturalRect(from: geo)
                }
            .onChange(of: stackStyle) { _, _ in captureNaturalRect(from: geo) }
            .onChange(of: pipSizeScale) { _, _ in captureNaturalRect(from: geo) }
        }
    }

    private func captureNaturalRect(from geo: GeometryProxy) {
        let current = geo.frame(in: .named(studioSlideCoordSpace))
        guard current.width > 0, current.height > 0 else { return }
        let activeOffset = CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        )
        naturalRect = current.offsetBy(dx: -activeOffset.width, dy: -activeOffset.height)
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }
        let bounds = slideBounds.insetBy(dx: studioPIPClusterEdgeInset, dy: studioPIPClusterEdgeInset)
        let visual = natural.offsetBy(dx: proposed.width, dy: proposed.height)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if visual.minX < bounds.minX { dx += bounds.minX - visual.minX }
        if visual.minY < bounds.minY { dy += bounds.minY - visual.minY }
        if visual.maxX > bounds.maxX { dx -= visual.maxX - bounds.maxX }
        if visual.maxY > bounds.maxY { dy -= visual.maxY - bounds.maxY }
        return CGSize(width: proposed.width + dx, height: proposed.height + dy)
    }
}

// MARK: - Draggable PIP Thumb (ungrouped)

/// Single PIP thumbnail with its own independent drag gesture.
/// Used when `slide.pipIsUngrouped == true` so each photo can be
/// repositioned freely anywhere on the slide.
private struct DraggablePIPThumb: View {
    @Binding var savedOffset: CGSize
    let slideBounds: CGRect
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onSelect: () -> Void = {}
    let image: UIImage
    let imageIndex: Int
    var framing: StudioImageFraming? = nil
    let slideWidth: CGFloat
    var pipBorderEnabled: Bool = true
    var borderColor: Color = .white
    var thumbMaskStyle: CarouselPIPThumbMaskStyle = .roundedRect
    var sizeScale: CGFloat = 1.0
    var isEditingText: Bool = false
    var isSelected: Bool = false
    var showsEditingOutline: Bool = true
    /// Ungrouped Multi: double-tap to replace this inset from the place library.
    var onThumbDoubleTapReplace: ((Int) -> Void)? = nil
    /// True while Vision is removing the background for this stack slot.
    var showsBackgroundRemovalLoading: Bool = false
    var onClusterPinchScale: ((CGFloat, Bool) -> Void)? = nil
    var onClusterPinchBegan: () -> Void = {}

    @GestureState private var liveDrag: CGSize = .zero
    @State private var naturalRect: CGRect?
    @State private var didBeginPIPThumbDrag = false
    @State private var pinchClusterBase: CGFloat = 1.0
    @State private var pinchClusterActive = false
    @State private var pinchSmoothedScale: CGFloat = 1.0

    private var thumbW: CGFloat { slideWidth * 0.30 * sizeScale }
    private var slotW: CGFloat { thumbW }
    private var slotH: CGFloat { thumbMaskStyle == .circle ? thumbW : thumbW * 0.72 }

    private var savedPointOffset: CGSize {
        CGSize(width: savedOffset.width * slideBounds.width,
               height: savedOffset.height * slideBounds.height)
    }

    private var displayPointOffset: CGSize {
        clampedOffset(CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        ))
    }

    var body: some View {
        let photo = SplitFramedPhotoInSlot(
            image: image,
            framing: framing,
            slotWidth: slotW,
            slotHeight: slotH
        )
        Group {
            if thumbMaskStyle == .circle {
                photo
                    .clipShape(Circle())
                    .overlay {
                        if pipBorderEnabled {
                            Circle().strokeBorder(borderColor, lineWidth: 2.2)
                        }
                    }
            } else {
                photo
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if pipBorderEnabled {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 2.2)
                        }
                    }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        .overlay(selectionRing)
        .overlay(alignment: .center) {
            if showsBackgroundRemovalLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(.white)
                    .padding(5)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .background(naturalRectCapture)
        .contentShape(Rectangle())
        .offset(x: displayPointOffset.width, y: displayPointOffset.height)
        .modifier(PIPClusterThumbTapModifier(
            imageIndex: imageIndex,
            onSingleTap: nil,
            onDoubleTap: onThumbDoubleTapReplace
        ))
        .highPriorityGesture(
            DragGesture(minimumDistance: isEditingText ? 0 : 4, coordinateSpace: .local)
                .updating($liveDrag) { value, state, _ in state = value.translation }
                .onChanged { _ in
                    guard isEditingText else { return }
                    if !didBeginPIPThumbDrag {
                        didBeginPIPThumbDrag = true
                        onDragStart()
                    }
                }
                .onEnded { value in
                    let tapSlop: CGFloat = 6
                    let moved = max(abs(value.translation.width), abs(value.translation.height))
                    if moved < tapSlop {
                        if isEditingText { onSelect() }
                    } else {
                        if isEditingText { onSelect() }
                        let proposed = CGSize(
                            width: savedPointOffset.width + value.translation.width,
                            height: savedPointOffset.height + value.translation.height
                        )
                        let clamped = clampedOffset(proposed)
                        savedOffset = CGSize(
                            width: slideBounds.width > 0 ? clamped.width / slideBounds.width : 0,
                            height: slideBounds.height > 0 ? clamped.height / slideBounds.height : 0
                        )
                    }
                    didBeginPIPThumbDrag = false
                    onDragEnd()
                },
            including: isEditingText ? .all : .subviews
        )
        .simultaneousGesture(ungroupedPIPThumbPinchGesture)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var ungroupedPIPThumbPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnitude in
                guard isEditingText, isSelected, let onScale = onClusterPinchScale else { return }
                if !pinchClusterActive {
                    pinchClusterActive = true
                    pinchClusterBase = sizeScale
                    pinchSmoothedScale = sizeScale
                    onClusterPinchBegan()
                }
                let raw = pinchClusterBase * magnitude
                let target = StudioPIPClusterSize.clampOnly(raw)
                pinchSmoothedScale += (target - pinchSmoothedScale) * studioPIPClusterPinchSmoothingBlend
                onScale(pinchSmoothedScale, false)
            }
            .onEnded { _ in
                let didPinch = pinchClusterActive
                if pinchClusterActive, isSelected, let onScale = onClusterPinchScale {
                    let committed = StudioPIPClusterSize.clampAndSnap(pinchSmoothedScale)
                    onScale(committed, true)
                }
                pinchClusterActive = false
                if didPinch {
                    didBeginPIPThumbDrag = false
                    onDragEnd()
                }
            }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isEditingText, showsEditingOutline {
            let cr: CGFloat = thumbMaskStyle == .circle ? 999 : 6
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .strokeBorder(
                    isSelected ? CarouselStudioChrome.accent : Color.white.opacity(0.35),
                    style: isSelected
                        ? StrokeStyle(lineWidth: 2.0)
                        : StrokeStyle(lineWidth: 1.0, dash: [5, 3])
                )
                .padding(-4)
        }
    }

    @ViewBuilder
    private var naturalRectCapture: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { captureNaturalRect(from: geo) }
                .onChange(of: geo.size) { _, _ in captureNaturalRect(from: geo) }
                .onChange(of: slideBounds) { _, _ in
                    naturalRect = nil
                    captureNaturalRect(from: geo)
                }
        }
    }

    private func captureNaturalRect(from geo: GeometryProxy) {
        let current = geo.frame(in: .named(studioSlideCoordSpace))
        guard current.width > 0, current.height > 0 else { return }
        let activeOffset = CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        )
        naturalRect = current.offsetBy(dx: -activeOffset.width, dy: -activeOffset.height)
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }
        // No extra inset: the outer .padding on each DraggablePIPThumb already
        // gives a 10pt natural margin from edges, so the photo can reach the edge
        // when dragged. Using studioPIPClusterEdgeInset here would double-count
        // that margin and block upward/inward movement from the default position.
        let bounds = slideBounds
        let visual = natural.offsetBy(dx: proposed.width, dy: proposed.height)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if visual.minX < bounds.minX { dx += bounds.minX - visual.minX }
        if visual.minY < bounds.minY { dy += bounds.minY - visual.minY }
        if visual.maxX > bounds.maxX { dx -= visual.maxX - bounds.maxX }
        if visual.maxY > bounds.maxY { dy -= visual.maxY - bounds.maxY }
        return CGSize(width: proposed.width + dx, height: proposed.height + dy)
    }
}

// MARK: - Per-slide edit page

private struct SlideEditPage: View {
    @Binding var slide: CarouselSlide
    let aspectRatio: CGFloat
    /// Width of the paging cell (used with `maxHeight` so the slide scales like the old screen-based math).
    let layoutWidth: CGFloat
    /// Maximum height the slide can occupy — used to scale width down for tall formats (e.g. 9:16).
    let maxHeight: CGFloat
    let selectedBlock: SlideBlockID?
    let onSelectBlock: (SlideBlockID) -> Void
    /// Called when the user taps the slide background (outside any text block) — used to deselect.
    let onDeselect: () -> Void
    /// Called immediately before committing a new text-block offset (drag end) so the parent can record undo.
    let recordUndoSnapshot: () -> Void
    /// While true, the slide pager's horizontal scrolling is disabled (text drag / tap on a block).
    @Binding var locksHorizontalSlidePaging: Bool
    /// Present the hero swap sheet (PIP layout): user tapped the large backdrop photo.
    /// Passes the pager index so swaps stay tied to this page if the sheet stays open while scrolling.
    let onRequestHeroSwap: (Int) -> Void
    /// Grouped Multi: user tapped an inset thumbnail to replace that slot (`slideIndex`, `thumbIndex`).
    let onRequestPIPInsetReplace: (Int, Int) -> Void
    /// Present the split-bottom picker (split layout): user tapped the bottom slot.
    let onRequestSplitBottomPick: (Int) -> Void
    /// Split layout: user tapped the top slot — select it in the parent.
    let onRequestSplitTopSelect: (Int) -> Void
    /// Split layout: which slot is currently selected (drives highlight in CarouselSlideView).
    fileprivate var selectedSplitSlot: SplitRepositionSlot? = nil
    /// Cover slide only: open the blog photo grid to change the slide hero (studio / editor).
    let onRequestStudioCoverPhotoPick: (() -> Void)?
    /// Second tap on an editable text block opens the inline text editor.
    let onRequestInlineTextEdit: () -> Void
    /// Which horizontal page this edit surface represents (`slides` index).
    let slidePageIndex: Int
    /// Matches export: Bloggo watermark only on the first map slide in the deck.
    let showPoweredByBloggoMapWatermark: Bool
    /// PIP stack slots (0…2) showing an inline spinner while Vision removes backgrounds.
    let pipBackgroundRemovalLoadingSlots: Set<Int>
    /// Index of the currently selected individual PIP photo (ungrouped mode only).
    var selectedPIPPhotoIndex: Int? = nil
    /// Fires when the user taps a PIP thumbnail in ungrouped mode.
    var onSelectPIPPhoto: ((Int) -> Void)? = nil

    private var slideWidth: CGFloat {
        let fromLayout = max(220, layoutWidth - 48)
        let fromHeight = maxHeight * aspectRatio
        return min(fromLayout, fromHeight)
    }

    var body: some View {
        CarouselSlideView(
            slide: slide,
            width: slideWidth,
            aspectRatio: aspectRatio,
            onToggleSelection: {},
            showsSelectionChrome: false,
            isEditingText: true,
            selectedBlockID: selectedBlock,
            onSelectBlock: { onSelectBlock($0) },
            onUpdateBlockOffset: { id, newOffset in
                recordUndoSnapshot()
                switch id {
                case .primary:    slide.textStyle.primary.offset = newOffset
                case .secondary:  slide.textStyle.secondary.offset = newOffset
                case .pipCluster: slide.pipOffset = newOffset
                }
            },
            onBlockDragStart: { locksHorizontalSlidePaging = true },
            onBlockDragEnd: { locksHorizontalSlidePaging = false },
            onBlockTap: { id in
                guard id == .primary || id == .secondary else { return }
                if carouselStudioSlideBlockSupportsInlineTextEdit(kind: slide.kind, block: id) {
                    onRequestInlineTextEdit()
                    return
                }
                // Tap-to-cycle readable bar: Off → Dark → Light → Off.
                recordUndoSnapshot()
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    if id == .primary {
                        slide.textStyle.primary.background =
                            slide.textStyle.primary.background.next()
                    } else {
                        slide.textStyle.secondary.background =
                            slide.textStyle.secondary.background.next()
                    }
                }
            },
            onUpdatePIPOffset: { newOffset in
                recordUndoSnapshot()
                slide.pipOffset = newOffset
            },
            onUpdatePIPPhotoOffset: { photoIndex, newOffset in
                recordUndoSnapshot()
                if slide.pipPhotoOffsets.count <= photoIndex {
                    let needed = photoIndex + 1 - slide.pipPhotoOffsets.count
                    slide.pipPhotoOffsets.append(contentsOf: Array(repeating: CGSize.zero, count: needed))
                }
                slide.pipPhotoOffsets[photoIndex] = newOffset
            },
            onSelectPIPPhoto: onSelectPIPPhoto,
            selectedPIPPhotoIndex: selectedPIPPhotoIndex,
            onTapHeroBackdrop: {
                guard slide.kind == .placeStop, slide.layout == .pip else { return }
                onRequestHeroSwap(slidePageIndex)
            },
            onTapSplitBottomSlot: {
                guard slide.layout == .split,
                      slide.kind == .placeStop || isCarouselStudioMapKind(slide.kind) else { return }
                onRequestSplitBottomPick(slidePageIndex)
            },
            onTapSplitTopSlot: {
                guard slide.layout == .split,
                      slide.kind == .placeStop || isCarouselStudioMapKind(slide.kind) else { return }
                onRequestSplitTopSelect(slidePageIndex)
            },
            selectedSplitSlot: selectedSplitSlot,
            onPIPClusterThumbTap: slide.layout == .pip
                ? { onRequestPIPInsetReplace(slidePageIndex, $0) }
                : nil,
            onPIPClusterPinchScale: slide.layout == .pip
                ? { newScale, isCommit in
                    func apply(_ value: CGFloat) {
                        if slide.pipIsUngrouped, let photoIdx = selectedPIPPhotoIndex {
                            if slide.pipPhotoStyles.count <= photoIdx {
                                slide.pipPhotoStyles.append(contentsOf: Array(
                                    repeating: nil,
                                    count: photoIdx + 1 - slide.pipPhotoStyles.count
                                ))
                            }
                            if slide.pipPhotoStyles[photoIdx] == nil {
                                slide.pipPhotoStyles[photoIdx] = slide.effectivePIPPhotoStyle(at: photoIdx)
                            }
                            slide.pipPhotoStyles[photoIdx]?.sizeScale = value
                        } else {
                            slide.pipClusterSizeScale = value
                        }
                    }
                    if isCommit {
                        // Gesture already sends snapped scale; ease the last step onto the Size-strip grid.
                        withAnimation(.spring(response: 0.48, dampingFraction: 0.91)) {
                            apply(newScale)
                        }
                    } else {
                        apply(StudioPIPClusterSize.clampOnly(newScale))
                    }
                }
                : nil,
            onPIPClusterPinchBegan: { recordUndoSnapshot() },
            onUpdateTextSizeScale: { block, scale in
                switch block {
                case .primary:   slide.textStyle.primary.sizeScale = scale
                case .secondary: slide.textStyle.secondary.sizeScale = scale
                default: break
                }
            },
            onTextPinchBegan: { recordUndoSnapshot() },
            onCoverImageTap: (slide.kind == .cover ? onRequestStudioCoverPhotoPick : nil),
            showPoweredByBloggoMapWatermark: showPoweredByBloggoMapWatermark,
            pipBackgroundRemovalLoadingSlots: pipBackgroundRemovalLoadingSlots
        )
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 20)
        // Tap anywhere on the slide outside a text block deselects. Omit when the cover
        // hero has its own tap target so that gesture is not swallowed by this parent.
        .optionalOnTapGesture(
            isEnabled: !(slide.kind == .cover && onRequestStudioCoverPhotoPick != nil),
            perform: onDeselect
        )
    }
}

// MARK: - Split photo reposition (Carousel Studio)

private enum SplitRepositionSlot: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
}

private struct SplitRepositionSession: Identifiable {
    let slideIndex: Int
    let initialSlot: SplitRepositionSlot
    var id: Int { slideIndex }
}

/// Full-screen pinch/pan editor for split top/bottom framing.
private struct SplitPhotoRepositionCover: View {
    @Binding var slides: [CarouselSlide]
    let slideIndex: Int
    let startingSlot: SplitRepositionSlot
    /// Slide `width ÷ height` (same as `CarouselSlideView`'s `aspectRatio`).
    let slideAspectRatio: CGFloat
    let onClose: () -> Void
    let onApply: (StudioImageFraming?, SplitRepositionSlot) -> Void
    let onRequestBottomPhotoPick: () -> Void

    @State private var activeSlot: SplitRepositionSlot
    @State private var working: StudioImageFraming = .neutral
    @State private var pinchBase: CGFloat = 1
    @State private var pinchActive = false
    @State private var dragBasePanX: CGFloat = 0
    @State private var dragBasePanY: CGFloat = 0
    @State private var dragBaseFillScale: CGFloat = 1
    @State private var dragHadLowExcessX = false
    @State private var dragActive = false

    init(
        slides: Binding<[CarouselSlide]>,
        slideIndex: Int,
        startingSlot: SplitRepositionSlot,
        slideAspectRatio: CGFloat,
        onClose: @escaping () -> Void,
        onApply: @escaping (StudioImageFraming?, SplitRepositionSlot) -> Void,
        onRequestBottomPhotoPick: @escaping () -> Void
    ) {
        _slides = slides
        self.slideIndex = slideIndex
        self.startingSlot = startingSlot
        self.slideAspectRatio = slideAspectRatio
        self.onClose = onClose
        self.onApply = onApply
        self.onRequestBottomPhotoPick = onRequestBottomPhotoPick
        _activeSlot = State(initialValue: startingSlot)
    }

    private var slotAspectWH: CGFloat { max(slideAspectRatio * 2, 0.01) }

    private var currentImage: UIImage? {
        guard slides.indices.contains(slideIndex) else { return nil }
        let s = slides[slideIndex]
        if isCarouselStudioMapKind(s.kind) {
            return activeSlot == .top ? s.mapSnapshot : s.splitBottomImage
        }
        return activeSlot == .top ? s.heroImage : s.splitBottomImage
    }

    private func loadWorkingFromSlide() {
        guard slides.indices.contains(slideIndex) else {
            working = .neutral
            return
        }
        let s = slides[slideIndex]
        let opt = activeSlot == .top ? s.splitTopFraming : s.splitBottomFraming
        working = opt ?? .neutral
    }

    private func combinedGesture(slotW: CGFloat, slotH: CGFloat, image: UIImage) -> some Gesture {
        let magnification = MagnificationGesture()
            .onChanged { mag in
                if !pinchActive {
                    pinchBase = working.fillScale
                    pinchActive = true
                }
                var w = working
                w.fillScale = min(max(pinchBase * mag, 1), StudioImageFraming.maxFillScale)
                working = StudioImageFraming.clampFraming(w.clamped(), image: image, slotW: slotW, slotH: slotH)
            }
            .onEnded { _ in
                pinchActive = false
            }

        let drag = DragGesture()
            .onChanged { g in
                if !dragActive {
                    dragBasePanX = working.panX
                    dragBasePanY = working.panY
                    dragBaseFillScale = working.fillScale
                    let mStart = StudioImageFraming.framedMetrics(
                        image: image,
                        slotW: slotW,
                        slotH: slotH,
                        framing: working.clamped()
                    )
                    let ex0 = max(0, (mStart.rw - slotW) * 0.5)
                    dragHadLowExcessX = ex0 <= 0.5
                    dragActive = true
                }
                var next = working.clamped()
                // Portrait (or similar) in a wide split slot: no horizontal slack until zoomed.
                // If the user drags mostly horizontally, grow fill slightly so left/right pan works.
                if dragHadLowExcessX,
                   abs(g.translation.width) > max(10, abs(g.translation.height) * 0.65) {
                    let stretch = 1 + min(abs(g.translation.width) / max(slotW * 2, 200), 0.5) * 0.55
                    next.fillScale = min(max(dragBaseFillScale * stretch, 1), StudioImageFraming.maxFillScale)
                }
                next = StudioImageFraming.clampFraming(next, image: image, slotW: slotW, slotH: slotH)
                let m = StudioImageFraming.framedMetrics(
                    image: image,
                    slotW: slotW,
                    slotH: slotH,
                    framing: next
                )
                let excessX = max(0, (m.rw - slotW) * 0.5)
                let excessY = max(0, (m.rh - slotH) * 0.5)
                if excessX > 0.5 {
                    next.panX = dragBasePanX + g.translation.width / excessX
                }
                if excessY > 0.5 {
                    next.panY = dragBasePanY + g.translation.height / excessY
                }
                working = StudioImageFraming.clampFraming(next, image: image, slotW: slotW, slotH: slotH)
            }
            .onEnded { _ in
                dragActive = false
            }

        return SimultaneousGesture(magnification, drag)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let slot = studioRepositionSlotDimensions(container: geo.size, slotAspectWH: slotAspectWH)
                let slotW = slot.slotW
                let slotH = slot.slotH

                ZStack {
                    Color(red: 8/255, green: 10/255, blue: 22/255).ignoresSafeArea()

                    VStack(spacing: 14) {
                        if let img = currentImage {
                            Text("Pinch to zoom · drag to pan")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.62))

                            ZStack {
                                SplitFramedPhotoInSlot(
                                    image: img,
                                    framing: working,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                    .frame(width: slotW, height: slotH)
                            }
                            .frame(width: slotW, height: slotH)
                            .contentShape(Rectangle())
                            .highPriorityGesture(combinedGesture(slotW: slotW, slotH: slotH, image: img))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                                if activeSlot == .bottom {
                                    Button("Select Bottom Photo") {
                                        onRequestBottomPhotoPick()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                                    .accessibilityLabel("Select Bottom Photo")
                                } else {
                                    Text("No image in this slot.")
                                        .font(.subheadline.weight(.medium))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white.opacity(0.55))
                                        .padding(.horizontal, 28)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: slotH)
                        }

                        // Keep slot selector directly below the photo area.
                        Picker("Photo", selection: $activeSlot) {
                            if slides.indices.contains(slideIndex),
                               isCarouselStudioMapKind(slides[slideIndex].kind) {
                                Text("Photo").tag(SplitRepositionSlot.bottom)
                                Text("Map").tag(SplitRepositionSlot.top)
                            } else {
                                Text("Top").tag(SplitRepositionSlot.top)
                                Text("Bottom").tag(SplitRepositionSlot.bottom)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: slotW)

                        Spacer(minLength: 0)

                        // Standalone reset action.
                        Button("Reset") {
                            pinchActive = false
                            dragActive = false
                            working = .neutral
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let out: StudioImageFraming? = working.storedFormOrNil == nil ? nil : working.clamped()
                        onApply(out, activeSlot)
                        onClose()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadWorkingFromSlide() }
        .onChange(of: activeSlot) { _, _ in
            pinchActive = false
            dragActive = false
            loadWorkingFromSlide()
        }
    }
}

// MARK: - PIP inset photo reposition (Carousel Studio)

private struct PIPClusterRepositionSession: Identifiable {
    let slideIndex: Int
    /// Index into `pipImages` to open on first appearance.
    let initialClusterIndex: Int
    var id: Int { slideIndex }
}

/// Full-screen pinch/pan editor for PIP (Multi) **inset thumbnails only** — not the main backdrop.
private struct PIPPhotoRepositionCover: View {
    @Binding var slides: [CarouselSlide]
    let slideIndex: Int
    let onClose: () -> Void
    let onApply: (StudioImageFraming?, Int) -> Void

    @State private var activeClusterIndex: Int
    @State private var working: StudioImageFraming = .neutral
    @State private var pinchBase: CGFloat = 1
    @State private var pinchActive = false
    @State private var dragBasePanX: CGFloat = 0
    @State private var dragBasePanY: CGFloat = 0
    @State private var dragBaseFillScale: CGFloat = 1
    @State private var dragHadLowExcessX = false
    @State private var dragActive = false

    init(
        slides: Binding<[CarouselSlide]>,
        slideIndex: Int,
        initialClusterIndex: Int,
        onClose: @escaping () -> Void,
        onApply: @escaping (StudioImageFraming?, Int) -> Void
    ) {
        _slides = slides
        self.slideIndex = slideIndex
        self.onClose = onClose
        self.onApply = onApply
        let count = slides.wrappedValue.indices.contains(slideIndex)
            ? slides.wrappedValue[slideIndex].pipImages.count
            : 0
        let clamped = count > 0 ? min(max(0, initialClusterIndex), count - 1) : 0
        _activeClusterIndex = State(initialValue: clamped)
    }

    private var pipImageCount: Int {
        guard slides.indices.contains(slideIndex) else { return 0 }
        return slides[slideIndex].pipImages.count
    }

    /// Matches `PIPClusterView` thumb width ÷ height (`thumbH = thumbW * 0.72`); for
    /// circular insets the slot is square (aspect 1:1), matching `slotW == slotH` on the slide.
    private static let pipThumbAspectWH: CGFloat = 1.0 / 0.72

    private var pipRepositionMaskStyle: CarouselPIPThumbMaskStyle {
        guard slides.indices.contains(slideIndex) else { return .roundedRect }
        return slides[slideIndex].pipThumbMaskStyle
    }

    private var pipRepositionSlotAspectWH: CGFloat {
        if pipRepositionMaskStyle == .circle { return 1.0 }
        return max(Self.pipThumbAspectWH, 0.01)
    }

    private var currentImage: UIImage? {
        guard slides.indices.contains(slideIndex) else { return nil }
        let s = slides[slideIndex]
        let i = activeClusterIndex
        guard s.pipImages.indices.contains(i) else { return nil }
        return s.effectivePIPImages.indices.contains(i) ? s.effectivePIPImages[i] : s.pipImages[i]
    }

    private func loadWorkingFromSlide() {
        guard slides.indices.contains(slideIndex) else {
            working = .neutral
            return
        }
        let s = slides[slideIndex]
        let i = activeClusterIndex
        if i < s.pipThumbnailFramings.count, let f = s.pipThumbnailFramings[i] {
            working = f
        } else {
            working = .neutral
        }
    }

    private func combinedGesture(slotW: CGFloat, slotH: CGFloat, image: UIImage) -> some Gesture {
        let magnification = MagnificationGesture()
            .onChanged { mag in
                if !pinchActive {
                    pinchBase = working.fillScale
                    pinchActive = true
                }
                var w = working
                w.fillScale = min(max(pinchBase * mag, 1), StudioImageFraming.maxFillScale)
                working = StudioImageFraming.clampFraming(w.clamped(), image: image, slotW: slotW, slotH: slotH)
            }
            .onEnded { _ in
                pinchActive = false
            }

        let drag = DragGesture()
            .onChanged { g in
                if !dragActive {
                    dragBasePanX = working.panX
                    dragBasePanY = working.panY
                    dragBaseFillScale = working.fillScale
                    let mStart = StudioImageFraming.framedMetrics(
                        image: image,
                        slotW: slotW,
                        slotH: slotH,
                        framing: working.clamped()
                    )
                    let ex0 = max(0, (mStart.rw - slotW) * 0.5)
                    dragHadLowExcessX = ex0 <= 0.5
                    dragActive = true
                }
                var next = working.clamped()
                if dragHadLowExcessX,
                   abs(g.translation.width) > max(10, abs(g.translation.height) * 0.65) {
                    let stretch = 1 + min(abs(g.translation.width) / max(slotW * 2, 200), 0.5) * 0.55
                    next.fillScale = min(max(dragBaseFillScale * stretch, 1), StudioImageFraming.maxFillScale)
                }
                next = StudioImageFraming.clampFraming(next, image: image, slotW: slotW, slotH: slotH)
                let m = StudioImageFraming.framedMetrics(
                    image: image,
                    slotW: slotW,
                    slotH: slotH,
                    framing: next
                )
                let excessX = max(0, (m.rw - slotW) * 0.5)
                let excessY = max(0, (m.rh - slotH) * 0.5)
                if excessX > 0.5 {
                    next.panX = dragBasePanX + g.translation.width / excessX
                }
                if excessY > 0.5 {
                    next.panY = dragBasePanY + g.translation.height / excessY
                }
                working = StudioImageFraming.clampFraming(next, image: image, slotW: slotW, slotH: slotH)
            }
            .onEnded { _ in
                dragActive = false
            }

        return SimultaneousGesture(magnification, drag)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let slot = studioRepositionSlotDimensions(container: geo.size, slotAspectWH: pipRepositionSlotAspectWH)
                let slotW = slot.slotW
                let slotH = slot.slotH

                ZStack {
                    Color(red: 8/255, green: 10/255, blue: 22/255).ignoresSafeArea()

                    VStack(spacing: 14) {
                        if let img = currentImage {
                            Text("Pinch to zoom · drag to pan")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.62))

                            ZStack {
                                let base = SplitFramedPhotoInSlot(
                                    image: img,
                                    framing: working,
                                    slotWidth: slotW,
                                    slotHeight: slotH
                                )
                                if pipRepositionMaskStyle == .circle {
                                    base
                                        .clipShape(Circle())
                                    Circle()
                                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                        .frame(width: slotW, height: slotH)
                                } else {
                                    base
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                        .frame(width: slotW, height: slotH)
                                }
                            }
                            .frame(width: slotW, height: slotH)
                            .contentShape(Rectangle())
                            .highPriorityGesture(combinedGesture(slotW: slotW, slotH: slotH, image: img))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                                Text("No image in this slot.")
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 28)
                            }
                            .frame(maxWidth: .infinity, maxHeight: slotH)
                        }

                        if pipImageCount > 1 {
                            Picker("Inset photo", selection: $activeClusterIndex) {
                                ForEach(0..<pipImageCount, id: \.self) { i in
                                    Text("Inset \(i + 1)").tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: slotW)
                        }

                        Spacer(minLength: 0)

                        Button("Reset") {
                            pinchActive = false
                            dragActive = false
                            working = .neutral
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Reposition inset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let out: StudioImageFraming? = working.storedFormOrNil == nil ? nil : working.clamped()
                        onApply(out, activeClusterIndex)
                        onClose()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadWorkingFromSlide() }
        .onChange(of: activeClusterIndex) { _, _ in
            pinchActive = false
            dragActive = false
            loadWorkingFromSlide()
        }
        .onChange(of: pipImageCount) { _, newCount in
            guard newCount > 0 else { return }
            if activeClusterIndex >= newCount {
                activeClusterIndex = max(0, newCount - 1)
                pinchActive = false
                dragActive = false
                loadWorkingFromSlide()
            }
        }
    }
}

// MARK: - Full-Screen Text Editor

/// Share / save / PDF from the editor nav bar — implemented by `SocialPostStudioSheet`.
struct SlideTextEditorExportActions {
    let share: () async -> Void
    /// Shares rendered slides for the given indices (same JPEG pipeline as **Share**).
    /// Second parameter: when `true`, map slides are skipped and single-photo stops that only appeared on a place map export as a photo slide instead.
    let shareAtIndices: ([Int], _ omitMapsFromShare: Bool) async -> Void
    let saveToPhotos: () async -> Void
    /// Saves rendered slides for the given indices (carousel order); used by Carousel Studio download picker.
    let saveToPhotosAtIndices: ([Int]) async -> Void
    /// Exports rendered slides for the given indices as one PDF and opens the share sheet.
    let exportPDFAtIndices: ([Int]) async -> Void
    let exportPDF: () async -> Void
    let exportActionsDisabled: () -> Bool
}

struct SlideTextEditorView: View {
    private static let studioPreviewRatio45: CGFloat = 4.0 / 5.0
    private static let studioPreviewRatio916: CGFloat = 9.0 / 16.0

    @Binding var slides: [CarouselSlide]
    let initialIndex: Int
    /// Export / download thumbnail aspect from the parent (Post vs Story/Reel).
    let aspectRatio: CGFloat
    /// Parent-owned aspect used for `ImageRenderer` export; kept in sync when the user toggles 4:5 ↔ 9:16.
    let exportCanvasAspectRatio: Binding<CGFloat>
    /// Live slide preview frame; user can tap the aspect pill to flip vs `aspectRatio` for comparison.
    @State private var editorPreviewAspectRatio: CGFloat
    /// Nav bar download affordance opens a bottom sheet (share / download / PDF); parent owns sheets, alerts, and export rendering.
    let exportActions: SlideTextEditorExportActions
    /// Mirrors parent `SocialPostStudioSheet.isRendering` so export progress covers the editor when presented in `fullScreenCover`.
    @Binding var exportInProgress: Bool
    /// Parent sets a raw slide index to move the pager without tearing down the editor (e.g. from the slide grid sheet).
    @Binding var externalJumpToSlideIndex: Int?
    /// When set (e.g. from `SocialPostStudioSheet`), the cover slide can change its hero via the same picker as the studio preview.
    let onRequestStudioCoverPhotoPick: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    /// Drives the paged `ScrollView`; optional to match `scrollPosition(id:)`.
    /// Seeded in `init` to `initialIndex` so the very first layout pass of the paging
    /// ScrollView already has the correct target page. Without this the ScrollView lays
    /// out at offset 0 first, then tries to scroll once `.onAppear`/`.task` sets the ID —
    /// which races with the `fullScreenCover` present animation and (especially for 9:16
    /// Story/Reel slides) lands a few points off-center.
    @State private var scrollPageID: Int?
    @State private var selectedBlock: SlideBlockID? = nil
    /// Which style category (Color / Font Style / Font Size) is currently open in
    /// the drop-up panel. `nil` collapses the panel and only the category tab bar is shown.
    @State private var activeStyleCategory: StyleCategory? = nil
    /// Which PIP category (Border / Size / Remove BG) is currently open. Parallels
    /// `activeStyleCategory` but for the photo-cluster toolbar that shows when
    /// `selectedBlock == .pipCluster`. Kept separate from `activeStyleCategory`
    /// so switching between a text block and the PIP block resets panel state.
    @State private var activePIPCategory: PIPStyleCategory? = nil
    /// Index of the PIP photo selected in ungrouped mode. Nil when no photo
    /// is individually selected or when in grouped (cluster) mode.
    @State private var selectedPIPPhotoIndex: Int? = nil
    /// True while the "Add photo" picker sheet is presented. Nil-able to work
    /// with `.sheet(isPresented:)`. The picker reads `currentSlide?.placeStop`
    /// and the exclusion set live, so no extra context needs to be captured.
    @State private var showsAddPhotoPicker: Bool = false
    /// PIP layout: pick another place photo to feature as the large backdrop.
    @State private var showsHeroPhotoSwapSheet: Bool = false
    /// Slide index captured when opening `showsHeroPhotoSwapSheet` (stable if user changes pages).
    @State private var heroSwapSlideIndex: Int?
    /// Grouped Multi: replace one inset thumbnail from the place photo grid.
    @State private var pipInsetReplaceSession: PIPInsetReplaceSession?
    /// Split layout: pick the optional second photo for the bottom half.
    @State private var showsSplitBottomPhotoPicker: Bool = false
    /// Slide index captured when opening `showsSplitBottomPhotoPicker`.
    @State private var splitBottomPickSlideIndex: Int?
    /// Split layout: which photo slot (top / bottom) the user has selected for editing.
    /// Nil means no split slot is selected; drives `splitPhotoActionToolbar` visibility.
    @State private var selectedSplitSlot: SplitRepositionSlot?
    /// Split layout: full-screen pinch/pan framing editor.
    @State private var splitRepositionSession: SplitRepositionSession?
    /// PIP (Multi): full-screen pinch/pan framing for inset thumbnails only.
    @State private var pipMultiRepositionSession: PIPClusterRepositionSession?
    /// Ensures `pushUndoSnapshot()` runs once at the start of a PIP size drag (coalesced undo).
    @State private var pipClusterSizeSliderUndoPrimed = false
    /// Bumps whenever PIP background work should abandon in-flight Vision tasks (slide change, mutation, toggle-off).
    @State private var pipBackgroundRemovalGeneration: UInt64 = 0
    /// Which `slides` index owns the in-flight Vision pass (nil when idle).
    @State private var pipBackgroundRemovalSlideIndex: Int?
    /// Visible PIP stack slots still awaiting a cutout for that slide.
    @State private var pipBackgroundRemovalLoadingSlots: Set<Int> = []
    /// Disables horizontal slide paging while the user touches a text block (see `SlideEditPage`).
    @State private var locksHorizontalSlidePaging = false
    /// One-shot guard so a swipe clears selection once per drag.
    @State private var didClearSelectionForPagerDrag = false
    /// Briefly true after a bulk "Apply to…" action to show a confirmation flash.
    @State private var didApplyToAll = false
    /// Prior `slides` arrays for incremental undo (shallow copy; `UIImage` refs unchanged).
    @State private var undoStack: [[CarouselSlide]] = []
    /// True after the first non-zero slot width has been observed and the initial page
    /// has been force-reasserted. Until this is true we ignore `scrollPageID` write-backs
    /// from the ScrollView, which would otherwise pull us to page 0 during the 0→real
    /// width transition (the default content offset (0) maps to page 0 once pages get
    /// real widths, so SwiftUI writes `scrollPageID = 0` back through the binding).
    @State private var didPerformInitialScroll = false
    /// Inline copy editor opened from the "Text" button in the formatting toolbar.
    @State private var showsTextEditLine = false
    /// When `true`, `commitInlineTextEdit` ran — skip draft revert in the text sheet's `onDismiss`.
    @State private var inlineTextEditCommitted = false
    @State private var inlineTextDraft = ""
    /// Secondary draft for the place caption field shown beneath the place name
    /// when editing a placeStop primary block.
    @State private var inlineCaptionDraft = ""
    /// Captures `selectedBlock` and `currentIndex` at the moment the text editor opens so
    /// `commitInlineTextEdit` always writes to the correct slide/block even if those
    /// values are cleared by lifecycle events (e.g. fullScreenCover onAppear) before Save fires.
    @State private var textEditBlockCapture: SlideBlockID? = nil
    @State private var textEditSlideIndexCapture: Int = 0
    private enum InlineTextFocusField: Hashable { case main, caption }
    @FocusState private var inlineTextFocusField: InlineTextFocusField?
    /// Which backing field receives caption edits for the current place-stop primary block.
    @State private var placeCaptionWriteTarget: PlaceSlideCaptionTarget = .none
    /// Tracks the on-screen keyboard height so the toolbar can be pushed above it.
    /// Needed because `fullScreenCover` + `GeometryReader` doesn't propagate keyboard
    /// safe-area changes to the nested `safeAreaInset`, causing the keyboard to overlay the toolbar.
    @State private var keyboardHeight: CGFloat = 0
    /// Full-screen text editor: `keyboardWillChangeFrame` still fires for this window while
    /// the cover is up; without ignoring those events, `keyboardHeight` becomes stale and
    /// the studio `safeAreaInset` chrome jumps when the cover dismisses.
    @State private var ignoreChromeKeyboardNotifications = false
    /// When set, the editor can remove the current place slide from the carousel (Social Post Studio).
    let onExcludePlaceFromStudio: ((Int) -> Void)?
    /// When set, the editor can remove a day-map slide from the carousel.
    let onExcludeMapFromStudio: ((Int) -> Void)?
    /// Opens the slide grid navigator (jump to any slide while editing).
    let onOpenPhotoGroupPicker: (() -> Void)?
    /// When `true` (e.g. Reel export), the download picker only allows one slide at a time.
    let isSingleSlideDownloadMode: Bool
    /// When embedded outside a dismissible presentation (e.g. recap overlay), Close calls this instead of `dismiss()`.
    private let onDismissEditor: (() -> Void)?
    /// Removes every map slide from the deck (same as Slides Management).
    let onExcludeAllMapsFromStudio: (() -> Void)?

    /// Persisted preference: skip the remove-slide confirmation alert.
    @AppStorage("blogify.studioSkipExcludeConfirm") private var skipExcludeConfirm = false
    /// True while the slide-exclusion confirmation overlay is visible.
    @State private var showExcludeConfirmOverlay = false
    /// First session in Carousel Studio: offer place text/photo zone layout before editing.
    @AppStorage("carouselStudio.hasSeenPlaceLayoutPicker") private var hasSeenPlaceLayoutPicker = false
    @State private var showPlaceZoneLayoutSheet = false
    @State private var placeZoneLayoutAppliesToAllPlaceSlides = false
    @State private var selectedPlaceZoneLayoutInSheet: CarouselPlaceZoneLayout = .textLeadingPhotosTrailing
    @State private var didOfferFirstRunPlaceLayout = false
    /// Whole-carousel text zones by Single / Multi / Split (`CarouselSlideLayout`).
    @State private var showCarouselWidePlaceZoneSheet = false
    /// Carousel Studio: download icon opens a bottom sheet (Share / Download / PDF).
    @State private var showCarouselStudioExportHub = false
    @State private var carouselStudioExportHubPhase: CarouselStudioExportHubPhase = .pickDownloadSlides
    /// Indices selected in the download-only picker (subset of `studioDownloadCandidateIndices`).
    @State private var downloadSlidePickSelection: Set<Int> = []
    /// Indices selected in the Share flow (subset of `studioDownloadCandidateIndices`).
    @State private var shareSlidePickSelection: Set<Int> = []
    /// Download modal output type; trailing toolbar menu shows the active format icon (photo vs PDF).
    @State private var downloadOutputMode: DownloadOutputMode = .photo
    @State private var editorExportBannerAlertTitle = ""
    @State private var editorExportBannerAlertMessage = ""
    @State private var showEditorExportBannerAlert = false
    /// Download → Done with >34 slides: confirm Photos save in batches of 34.
    @State private var showBulkPhotosDownloadConfirmation = false
    @State private var pendingBulkPhotosDownloadOrder: [Int] = []
    /// Download PDF with >34 slides: confirm multiple PDF exports.
    @State private var showBulkPdfDownloadConfirmation = false
    @State private var pendingBulkPdfDownloadOrder: [Int] = []
    /// Work to run **after** the export hub sheet fully dismisses (avoids SwiftUI refusing to parent-present share while nested sheet tears down).
    private enum CarouselStudioDeferredExportHubWork {
        case sharePickedIndices([Int], omitMapsFromShare: Bool)
        case savePhotosIndices([Int])
        case exportPDFIndices([Int])
    }

    @State private var deferredExportHubWork: CarouselStudioDeferredExportHubWork?

    private enum CarouselStudioExportHubPhase {
        case pickDownloadSlides
        case pickShareSlides
    }

    private enum DownloadOutputMode: String, CaseIterable, Identifiable {
        case photo
        case pdf

        var id: String { rawValue }

        var label: String {
            switch self {
            case .photo: return "Photo"
            case .pdf: return "PDF"
            }
        }

        /// Shown on the download sheet toolbar and in the format menu.
        var systemImage: String {
            switch self {
            case .photo: return "photo"
            case .pdf: return "doc.text.fill"
            }
        }
    }

    init(
        slides: Binding<[CarouselSlide]>,
        initialIndex: Int,
        aspectRatio: CGFloat,
        exportCanvasAspectRatio: Binding<CGFloat>,
        exportActions: SlideTextEditorExportActions,
        exportInProgress: Binding<Bool>,
        externalJumpToSlideIndex: Binding<Int?>,
        onRequestStudioCoverPhotoPick: (() -> Void)? = nil,
        onExcludePlaceFromStudio: ((Int) -> Void)? = nil,
        onExcludeMapFromStudio: ((Int) -> Void)? = nil,
        onOpenPhotoGroupPicker: (() -> Void)? = nil,
        isSingleSlideDownloadMode: Bool = false,
        onDismissEditor: (() -> Void)? = nil,
        onExcludeAllMapsFromStudio: (() -> Void)? = nil
    ) {
        self._slides = slides
        self.initialIndex = initialIndex
        self.aspectRatio = aspectRatio
        self.exportCanvasAspectRatio = exportCanvasAspectRatio
        self._editorPreviewAspectRatio = State(initialValue: aspectRatio)
        self.exportActions = exportActions
        self._exportInProgress = exportInProgress
        self._externalJumpToSlideIndex = externalJumpToSlideIndex
        self.onRequestStudioCoverPhotoPick = onRequestStudioCoverPhotoPick
        self.onExcludePlaceFromStudio = onExcludePlaceFromStudio
        self.onExcludeMapFromStudio = onExcludeMapFromStudio
        self.onOpenPhotoGroupPicker = onOpenPhotoGroupPicker
        self.isSingleSlideDownloadMode = isSingleSlideDownloadMode
        self.onDismissEditor = onDismissEditor
        self.onExcludeAllMapsFromStudio = onExcludeAllMapsFromStudio
        self._currentIndex = State(initialValue: initialIndex)
        self._scrollPageID = State(initialValue: initialIndex)
    }

    private var editorPreviewAspectLabel: String {
        abs(editorPreviewAspectRatio - Self.studioPreviewRatio916) < 0.001 ? "9:16" : "4:5"
    }

    /// Re-centers draggable text layers at their natural anchors.
    /// Called when preview ratio changes because offsets from the previous ratio
    /// can leave blocks in awkward/stale positions on the new canvas.
    private func reinitializeTextBoxPositionsAfterAspectChange() {
        for idx in slides.indices {
            if slides[idx].kind == .placeStop {
                slides[idx].textStyle.primary.offset = slides[idx].placeZoneLayout.templatePrimaryOffset
            } else {
                slides[idx].textStyle.primary.offset = .zero
            }
            slides[idx].textStyle.secondary.offset = .zero
            slides[idx].pipOffset = .zero
            slides[idx].pipPhotoOffsets = []
        }
    }

    private func toggleEditorPreviewAspect() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if abs(editorPreviewAspectRatio - Self.studioPreviewRatio916) < 0.001 {
                editorPreviewAspectRatio = Self.studioPreviewRatio45
            } else {
                editorPreviewAspectRatio = Self.studioPreviewRatio916
            }
            exportCanvasAspectRatio.wrappedValue = editorPreviewAspectRatio
            // Drop transient editor interaction state so the next ratio starts clean.
            selectedBlock = nil
            selectedSplitSlot = nil
            locksHorizontalSlidePaging = false
            reinitializeTextBoxPositionsAfterAspectChange()
        }
    }

    /// Number of visible (non-PIP-hidden) selected slides — used to badge the
    /// slide grid button when the count exceeds the typical social carousel limit (34).
    private var visibleSelectedSlideCount: Int {
        slides.enumerated().filter { idx, slide in
            !isSlideHiddenBySiblingPIP(at: idx, in: slides) && slide.isSelected
        }.count
    }

    /// Slides listed in the Carousel Studio download picker (Reel mode: only `isSelected` slides).
    private var studioDownloadCandidateIndices: [Int] {
        if isSingleSlideDownloadMode {
            return visibleSlideIndices.filter { slides[$0].isSelected }
        }
        return visibleSlideIndices
    }

    /// True when the download pick set is exactly the full candidate list.
    private var downloadPickSelectionMatchesAll: Bool {
        !studioDownloadCandidateIndices.isEmpty
            && Set(studioDownloadCandidateIndices) == downloadSlidePickSelection
    }

    /// Share candidates excluding map slides — used so "Select All / Deselect All"
    /// never touches maps (maps are controlled exclusively by the "Remove maps" toggle).
    private var sharePickPhotoOnlyCandidateIndices: [Int] {
        studioDownloadCandidateIndices.filter { !isCarouselStudioMapKind(slides[$0].kind) }
    }

    /// True when all non-map share candidates are selected.
    private var sharePickSelectionMatchesAll: Bool {
        let photoCandidates = sharePickPhotoOnlyCandidateIndices
        return !photoCandidates.isEmpty
            && Set(photoCandidates).isSubset(of: shareSlidePickSelection)
    }

    private func selectAllSlidesForDownloadPick() {
        downloadSlidePickSelection = Set(studioDownloadCandidateIndices)
    }

    private func toggleDownloadSlidePickSelectAll() {
        if downloadPickSelectionMatchesAll {
            downloadSlidePickSelection = []
        } else {
            selectAllSlidesForDownloadPick()
        }
    }

    private func toggleShareSlidePickSelectAll() {
        let photoCandidates = Set(sharePickPhotoOnlyCandidateIndices)
        if sharePickSelectionMatchesAll {
            // Deselect only photo slides — leave map selection state untouched.
            shareSlidePickSelection.subtract(photoCandidates)
        } else {
            shareSlidePickSelection.formUnion(photoCandidates)
        }
    }

    private func toggleDownloadPick(for index: Int) {
        guard studioDownloadCandidateIndices.contains(index) else { return }
        if isSingleSlideDownloadMode {
            downloadSlidePickSelection = [index]
        } else if downloadSlidePickSelection.contains(index) {
            downloadSlidePickSelection.remove(index)
        } else {
            downloadSlidePickSelection.insert(index)
        }
    }

    private func orderedPickedDownloadIndices() -> [Int] {
        studioDownloadCandidateIndices.filter { downloadSlidePickSelection.contains($0) }
    }

    private var studioCarouselHasMapSlides: Bool {
        slides.contains { isCarouselStudioMapKind($0.kind) }
    }

    private func selectAllSlidesForSharePick() {
        // Add all photo slides; maps are controlled by their own toggle.
        shareSlidePickSelection.formUnion(sharePickPhotoOnlyCandidateIndices)
    }

    private func toggleSharePick(for index: Int) {
        guard studioDownloadCandidateIndices.contains(index) else { return }
        if isSingleSlideDownloadMode {
            shareSlidePickSelection = [index]
        } else if shareSlidePickSelection.contains(index) {
            shareSlidePickSelection.remove(index)
        } else {
            shareSlidePickSelection.insert(index)
        }
    }

    private func orderedPickedShareIndices() -> [Int] {
        studioDownloadCandidateIndices.filter { shareSlidePickSelection.contains($0) }
    }

    private var pickedShareExportCount: Int {
        orderedPickedShareIndices().count
    }

    /// Map slides listed in the share grid (`studioDownloadCandidateIndices` ∩ map kinds).
    private var sharePickMapSlideIndices: [Int] {
        studioDownloadCandidateIndices.filter { idx in
            slides.indices.contains(idx) && isCarouselStudioMapKind(slides[idx].kind)
        }
    }

    /// Matches selection: `true` when map slides exist in the grid but none are checked (same as “remove maps from share”).
    private var sharePickEffectivelyOmitsMapsFromShare: Bool {
        let maps = sharePickMapSlideIndices
        guard !maps.isEmpty else { return false }
        return !maps.contains { shareSlidePickSelection.contains($0) }
    }

    private var sharePickOmitMapsToggleBinding: Binding<Bool> {
        Binding(
            get: { sharePickEffectivelyOmitsMapsFromShare },
            set: { shouldOmit in
                let mapIdx = Set(sharePickMapSlideIndices)
                if shouldOmit {
                    shareSlidePickSelection.subtract(mapIdx)
                } else {
                    shareSlidePickSelection.formUnion(mapIdx)
                }
            }
        )
    }

    /// Saves only the slide currently centered in the editor (same render path as bulk download).
    private func saveCurrentSlideOnlyToPhotos() {
        let idx = editorPagerFocusedSlideIndex
        guard visibleSlideIndices.contains(idx) else { return }
        guard !exportActions.exportActionsDisabled() else { return }
        Task { await exportActions.saveToPhotosAtIndices([idx]) }
    }

    private let maxUndoSteps = 40

    /// Reserved height for the bottom editing chrome in its "resting" states:
    /// the hint (before any block is tapped) and the collapsed formatting
    /// toolbar (action bar + category tab bar with no drop-up panel open).
    ///
    /// This value is critical for the tap-to-select drag gesture:
    /// `DraggableTextBlock` uses `DragGesture(minimumDistance: 0)`, so a tap
    /// starts the gesture. Selecting the block inside `.onChanged` swaps the
    /// hint for the toolbar — if *that* changed the reserved height, the
    /// slide would shift, the finger's position in the slide's local coord
    /// space would change, and `.onEnded` would commit a non-zero
    /// translation, drifting the block a few points on every tap.
    /// Keeping hint + collapsed toolbar at the *same* height prevents that.
    ///
    /// Sized to fit the collapsed toolbar: action bar (~44pt) + category tab
    /// bar (~65pt) ≈ 109pt, plus a small safety margin.
    private let bottomChromeCollapsed: CGFloat = 116

    /// Reserved height when a style drop-up panel (Color / Font Style / Font
    /// Size) is expanded. The extra ~60pt houses the panel's horizontally
    /// scrolling option strip. Toggling a category is a tap on the toolbar
    /// (not on the slide), so it's safe to grow the reserve here — the
    /// slide's own drag gesture is not in flight.
    private let bottomChromeExpanded: CGFloat = 176

    /// Reserve for the mode selector row so single-photo place groups keep the
    /// same slide position as groups that can switch Single/PIP/Split.
    private let modeSelectorReservedHeight: CGFloat = 46
    /// Reserve for the split-only tools row so paging between Single/PIP/Split
    /// does not shift the slide vertically.
    private let splitToolsReservedHeight: CGFloat = 40
    /// Active fill for rounded segment controls (layout mode row + split border).
    /// Uses `CarouselStudioChrome.accent` so fills stay blue under `.tint(.white)`.
    private let studioToolbarSegmentActiveColor = CarouselStudioChrome.accent
    /// Combined reserve for mode row + split row — applied to every slide type
    /// so cover / map / place slides share the same slide top position.
    private var studioModeChromeReserve: CGFloat {
        modeSelectorReservedHeight + splitToolsReservedHeight
    }

    /// Reserve subtracted from available height when computing `maxSlotH` for the
    /// slide pager. Uses `bottomChromeExpanded` so PIP drop-ups match text style panels.
    private var slotSizingBottomReserve: CGFloat {
        bottomChromeExpanded + studioModeChromeReserve
    }

    /// Current inset height. Drives the `.safeAreaInset` frame so the chrome
    /// is only as tall as it needs to be — eliminates the ~60pt of dead gray
    /// that previously sat above Delete / Apply to… when no panel was open.
    private var currentChromeHeight: CGFloat {
        let expanded = activeStyleCategory != nil || activePIPCategory != nil
        let base = expanded ? bottomChromeExpanded : bottomChromeCollapsed
        return base
    }

    // MARK: Helpers

    /// Slide index the horizontal pager is showing (or last reported). Prefer
    /// `scrollPageID` when it still names a rendered page — after swiping,
    /// `currentIndex` can lag until `onChange(scrollPageID)` runs, which made
    /// the PIP toggle apply to the wrong photo for non-first place slides.
    private var editorPagerFocusedSlideIndex: Int {
        if let sid = scrollPageID,
           slides.indices.contains(sid),
           visibleSlideIndices.contains(sid) {
            return sid
        }
        guard slides.indices.contains(currentIndex) else { return max(0, slides.count - 1) }
        return currentIndex
    }

    /// Slide index mutations must target this value — `scrollPageID` can lead `currentIndex`
    /// by a frame after horizontal paging, so `currentSlide` and `slides[currentIndex]` disagree.
    private var editorMutationSlideIndex: Int { editorPagerFocusedSlideIndex }

    private var currentSlide: CarouselSlide? {
        let idx = editorPagerFocusedSlideIndex
        guard slides.indices.contains(idx) else { return nil }
        return slides[idx]
    }

    /// PIP thumbnails actually on screen — `pipVisibleCount` capped by loaded photos.
    /// Toolbar logic must use this (not raw `pipVisibleCount`) so Style / Reorder
    /// disable correctly when only one photo exists in the cluster.
    private var currentSlideEffectivePIPVisibleCount: Int {
        guard let slide = currentSlide else { return 0 }
        return min(max(0, slide.pipVisibleCount), slide.pipImages.count)
    }

    /// Slides the editor's swipe pager should actually render — mirrors the
    /// filter used by the preview/export pipelines so a place-stop slide that
    /// has been "folded into" a sibling's PIP cluster (same stop, `.pip`
    /// layout) doesn't reappear here. Without this, flipping a stop to
    /// multi-photo in the preview grid and then tapping Edit would still let
    /// the user swipe across the very slides that were just collapsed away.
    private var visibleSlideIndices: [Int] {
        slides.indices.filter { slides[$0].isSelected && !isSlideHiddenBySiblingPIP(at: $0, in: slides) }
    }

    /// Position (0-based) of `currentIndex` within `visibleSlideIndices`, or `nil`
    /// if the current slide is somehow hidden. Drives the chevron counter so the
    /// user sees "page 2 of 4" over visible pages rather than "3 of 7" where
    /// three of those pages don't exist in the pager.
    private var currentVisiblePosition: Int? {
        visibleSlideIndices.firstIndex(of: editorPagerFocusedSlideIndex)
    }

    private var availableBlocks: [SlideBlockID] {
        guard let slide = currentSlide else { return [] }
        var blocks: [SlideBlockID] = []
        switch slide.kind {
        case .cover:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
        case .mapRoute, .placeIntroMap:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden { blocks.append(.secondary) }
        case .placeStop:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden { blocks.append(.secondary) }
            if slide.layout == .pip, !slide.pipImages.isEmpty {
                blocks.append(.pipCluster)
            }
        }
        return blocks
    }

    /// True when the selected block is the PIP photo cluster rather than a text block.
    /// Drives the toolbar branching below — text blocks use the typography chrome,
    /// the PIP cluster uses a dedicated delete / swap / count / border color chrome.
    private var isPIPClusterSelected: Bool {
        selectedBlock == .pipCluster
    }

    private var currentStyle: TextBlockStyle {
        guard let slide = currentSlide else { return TextBlockStyle() }
        return selectedBlock == .secondary ? slide.textStyle.secondary : slide.textStyle.primary
    }

    private var hasValidCurrentIndex: Bool {
        slides.indices.contains(currentIndex)
    }

    private func clampCurrentIndexIfNeeded() {
        guard !slides.isEmpty else {
            currentIndex = 0
            scrollPageID = nil
            selectedBlock = nil
            return
        }
        let clamped = min(max(currentIndex, 0), slides.count - 1)
        if clamped != currentIndex {
            currentIndex = clamped
            scrollPageID = clamped
            selectedBlock = nil
        }
        // If the target slide is now hidden (e.g. an undo re-activated a sibling's
        // PIP cluster), jump to the closest visible slide so the pager never sits
        // on a page that isn't in the `ForEach`.
        let visible = visibleSlideIndices
        guard !visible.isEmpty else { return }
        if !visible.contains(currentIndex) {
            // Stable tie-break: equal distance → prefer the earlier slide (deterministic
            // vs `min(by:)` on ties, which felt random when leaving a hidden sibling).
            let nearest = visible.min(by: { a, b in
                let da = abs(a - currentIndex)
                let db = abs(b - currentIndex)
                if da != db { return da < db }
                return a < b
            }) ?? visible[0]
            currentIndex = nearest
            scrollPageID = nearest
            selectedBlock = nil
        }
    }

    /// After the visible page list changes (e.g. PIP hides sibling singles), `scrollPosition`
    /// can briefly report an id that is no longer a rendered page, or snap the wrong
    /// way. Re-align `currentIndex` + binding to the slide the user was editing.
    private func reassertEditorPagerToSlide(at index: Int) {
        guard slides.indices.contains(index),
              visibleSlideIndices.contains(index) else { return }
        currentIndex = index
        // Nil pulse matches the initial-width workaround: forces `scrollPosition(id:)`
        // to re-resolve after sibling pages disappear from the left (offset drift).
        scrollPageID = nil
        DispatchQueue.main.async {
            guard visibleSlideIndices.contains(index) else { return }
            scrollPageID = index
        }
    }

    /// Stable string so `onChange` runs when the pager's page set changes (PIP collapse, etc.).
    private var visibleSlideIndicesTag: String {
        visibleSlideIndices.map(String.init).joined(separator: ",")
    }

    private var canExcludeCurrentSlide: Bool {
        guard hasValidCurrentIndex else { return false }
        let kind = slides[currentIndex].kind
        return (kind == .placeStop && onExcludePlaceFromStudio != nil) ||
               (isCarouselStudioMapKind(kind) && onExcludeMapFromStudio != nil)
    }

    /// Initiates exclusion of the current slide: shows confirmation unless the user opted out.
    private func performExcludeFromStudio() {
        guard canExcludeCurrentSlide else { return }
        if skipExcludeConfirm {
            commitExclude(at: currentIndex)
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showExcludeConfirmOverlay = true
            }
        }
    }

    /// Commits the exclusion of the slide at `idx`; keeps pager index valid.
    private func commitExclude(at idx: Int) {
        guard slides.indices.contains(idx) else { return }
        let kind = slides[idx].kind
        pushUndoSnapshot()
        if kind == .placeStop, let onExclude = onExcludePlaceFromStudio {
            onExclude(idx)
        } else if isCarouselStudioMapKind(kind), let onExclude = onExcludeMapFromStudio {
            onExclude(idx)
        } else {
            return
        }
        // Both place and map slides are hidden in-place (isSelected = false) — no array change,
        // no index arithmetic needed. clampCurrentIndexIfNeeded jumps to nearest visible slide.
        scrollPageID = currentIndex
        selectedBlock = nil
        clampCurrentIndexIfNeeded()
    }

    private func updateStyle(_ update: (inout TextBlockStyle) -> Void) {
        guard let selectedBlock else { return }
        let focusedIndex = editorPagerFocusedSlideIndex
        guard slides.indices.contains(focusedIndex) else { return }
        pushUndoSnapshot()
        if selectedBlock == .secondary { update(&slides[focusedIndex].textStyle.secondary) }
        else { update(&slides[focusedIndex].textStyle.primary) }
    }

    private func pushUndoSnapshot() {
        undoStack.append(slides)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
    }

    /// Text + inset-photo zones for place slides (`CarouselPlaceZoneLayout`).
    private func applyPlaceZoneLayout(_ layout: CarouselPlaceZoneLayout, to index: Int) {
        guard slides.indices.contains(index), slides[index].kind == .placeStop else { return }
        slides[index].placeZoneLayout = layout
        slides[index].textStyle.primary.offset = layout.templatePrimaryOffset
        slides[index].textStyle.secondary.offset = .zero
        slides[index].pipOffset = .zero
        slides[index].pipPhotoOffsets = []
    }

    /// Applies one text/photo zone preset to every place slide using `slidePhotoLayout`.
    private func applyCarouselWidePlaceZone(_ zone: CarouselPlaceZoneLayout, slidePhotoLayout: CarouselSlideLayout) {
        clampCurrentIndexIfNeeded()
        pushUndoSnapshot()
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            for i in slides.indices where slides[i].kind == .placeStop && slides[i].layout == slidePhotoLayout {
                applyPlaceZoneLayout(zone, to: i)
            }
        }
        showCarouselWidePlaceZoneSheet = false
        flashAppliedConfirmation()
    }

    private func placeSlideCount(for slidePhotoLayout: CarouselSlideLayout) -> Int {
        slides.filter { $0.kind == .placeStop && $0.layout == slidePhotoLayout }.count
    }

    private func carouselPhotoLayoutSectionTitle(_ layout: CarouselSlideLayout) -> String {
        switch layout {
        case .single: return "Single — full-width hero"
        case .pip: return "Multi — hero + inset photos"
        case .split: return "Split — top & bottom photos"
        }
    }

    /// Preset chips anchored above the postcard (consistent position for all decks with place slides).
    @ViewBuilder
    private func placeZoneVisualPresetStrip(editorContentWidth slideContentW: CGFloat,
                                            slideSlotHeight slotH: CGFloat) -> some View {
        let aspect = editorPreviewAspectRatio
        let editorSlideRenderW = min(max(220, slideContentW), slotH * aspect)
        let sideInset = max(0, (slideContentW - editorSlideRenderW) * 0.5)

        let focusedPlaceZone: CarouselPlaceZoneLayout? = slides.indices.contains(editorMutationSlideIndex)
            && slides[editorMutationSlideIndex].kind == .placeStop
            ? slides[editorMutationSlideIndex].placeZoneLayout
            : nil

        HStack(alignment: .center, spacing: 10) {
            if editorFocusedSlideIsPlaceStop,
               let slide = currentSlide,
               slide.kind == .placeStop {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CarouselPlaceZoneLayout.bulkZonePresets(for: slide.layout)) { zone in
                            Button {
                                pushUndoSnapshot()
                                applyPlaceZoneLayout(zone, to: editorMutationSlideIndex)
                            } label: {
                                PlaceZoneLayoutDiagramThumb(
                                    zone: zone,
                                    slidePhotoLayout: slide.layout,
                                    isSelected: focusedPlaceZone == zone,
                                    width: 54,
                                    height: 68
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, max(16, sideInset + 8))
                    .padding(.trailing, 6)
                    .padding(.vertical, 2)
                }
            } else {
                Spacer(minLength: sideInset + 8)
                Text("Place slides: pick a postcard to edit presets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 12)
            }

            Button {
                showCarouselWidePlaceZoneSheet = true
            } label: {
                Image(systemName: "square.stack.3d.forward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 40, height: 38)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, max(14, sideInset + 10))
            .accessibilityLabel("Whole carousel presets by Single, Multi, or Split layout")
        }
        .frame(height: 54)
        .padding(.bottom, 6)
    }

    private func commitPlaceZoneLayoutFromSheet(_ layout: CarouselPlaceZoneLayout) {
        pushUndoSnapshot()
        if placeZoneLayoutAppliesToAllPlaceSlides {
            for i in slides.indices where slides[i].kind == .placeStop {
                applyPlaceZoneLayout(layout, to: i)
            }
        } else {
            let idx = editorPagerFocusedSlideIndex
            applyPlaceZoneLayout(layout, to: idx)
        }
        hasSeenPlaceLayoutPicker = true
        showPlaceZoneLayoutSheet = false
    }

    private var editorFocusedSlideIsPlaceStop: Bool {
        slides.indices.contains(editorPagerFocusedSlideIndex)
            && slides[editorPagerFocusedSlideIndex].kind == .placeStop
    }

    private var deckHasPlaceSlides: Bool {
        slides.contains { $0.kind == .placeStop }
    }

    /// Active place slide in the editor (nil for cover/map).
    private var currentPlaceSlide: CarouselSlide? {
        guard editorFocusedSlideIsPlaceStop,
              slides.indices.contains(editorMutationSlideIndex) else { return nil }
        let slide = slides[editorMutationSlideIndex]
        guard slide.kind == .placeStop else { return nil }
        return slide
    }

    private var currentSlideZoneLayoutTitle: String {
        currentPlaceSlide?.placeZoneLayout.pickerTitle ?? "Layout"
    }

    private func presentCurrentSlideLayoutSheet() {
        guard slides.indices.contains(editorMutationSlideIndex) else { return }
        selectedPlaceZoneLayoutInSheet = slides[editorMutationSlideIndex].placeZoneLayout
        placeZoneLayoutAppliesToAllPlaceSlides = false
        DispatchQueue.main.async {
            showPlaceZoneLayoutSheet = true
        }
    }

    /// Single vs multi-photo layout for the current place-stop slide. Keeps sibling
    /// slide `isSelected` flags aligned with `SocialPostStudioSheet.setLayout` so
    /// export and the preview strip stay consistent.
    private func setPlaceStopLayout(_ layout: CarouselSlideLayout, for index: Int? = nil) {
        let index = index ?? editorPagerFocusedSlideIndex
        guard slides.indices.contains(index), slides[index].kind == .placeStop else { return }
        currentIndex = index
        let stopID = slides[index].placeStop?.id
        pushUndoSnapshot()
        // Do **not** animate `slides` here: a spring on every sibling + `layout` drives
        // heavy implicit transitions on each `SlideEditPage` while the pager's
        // `ForEach` removes pages — reads as a violent flash. Commit layout in a
        // non-animated transaction; animate only lightweight chrome below.
        var layoutTxn = Transaction()
        layoutTxn.disablesAnimations = true
        withTransaction(layoutTxn) {
            if layout == .single {
                if slides[index].layout == .pip {
                    releaseMultiLayoutGrouping(primaryIndex: index, slides: &slides)
                } else if slides[index].layout == .split {
                    releaseSplitLayoutGrouping(splitIndex: index, slides: &slides)
                }
            }
            slides[index].layout = layout
            if layout == .split {
                slides[index].splitBottomImage = nil
                slides[index].splitBottomPhotoID = nil
                slides[index].splitBottomFraming = nil
            } else {
                slides[index].splitTopFraming = nil
                slides[index].splitBottomFraming = nil
            }
            if layout != .pip {
                slides[index].pipThumbnailFramings = []
            }
            if layout == .pip {
                guard let stopID,
                      multiClusterCandidateIndices(from: index, stopID: stopID, in: slides).count > 1 else {
                    slides[index].layout = .single
                    return
                }
                applyMultiLayoutGrouping(primaryIndex: index, slides: &slides)
            } else if let stopID {
                for i in slides.indices where i != index {
                    guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                    slides[i].isSelected = true
                }
                if placeStopSiblingIndices(stopID: stopID, in: slides).count > 1 {
                    repopulatePipPayloadsForPlaceStop(stopID: stopID, slides: &slides)
                }
            }
        }
        if slides[index].layout == .pip {
            activeStyleCategory = nil
            withAnimation(.easeOut(duration: 0.18)) {
                selectedBlock = .pipCluster
            }
        } else {
            if selectedBlock == .pipCluster { selectedBlock = nil }
            activePIPCategory = nil
            pipInsetReplaceSession = nil
            if slides[index].layout == .split {
                autoFillSplitBottomIfTwoPhotos(slideIndex: index)
            }
            invalidatePIPBackgroundRemovalForMutation(at: index)
        }
        clampCurrentIndexIfNeeded()
        // Re-pin immediately: deferring only to `onChange(visibleSlideIndicesTag)` let
        // `scrollPosition` / `scrollPageID` race for a frame and landed users on the
        // wrong photo group (especially non-first photos at a stop).
        reassertEditorPagerToSlide(at: index)
    }

    private func layoutIcon(_ layout: CarouselSlideLayout) -> String {
        switch layout {
        case .single: return "rectangle.portrait"
        case .pip: return "pip"
        case .split: return "rectangle.split.1x2"
        }
    }

    private func layoutLabel(_ layout: CarouselSlideLayout) -> String {
        switch layout {
        case .single: return "Single"
        case .pip:    return "Multi"
        case .split:  return "Split"
        }
    }

    // MARK: - Persistent mode selector rows

    /// Row above the block toolbar: Single / PIP / Split for multi-photo place
    /// stops; invisible height reserve for cover, map, and single-photo places
    /// so every slide type shares the same vertical slide position.
    @ViewBuilder
    private var modeSelectRow: some View {
        if let slide = currentSlide {
            switch slide.kind {
            case .placeStop:
                if placeStopOffersLayoutModes(at: editorPagerFocusedSlideIndex, in: slides) {
                    let layouts = CarouselSlideLayout.allCases
                    let focusedIndex = editorPagerFocusedSlideIndex
                    let modeTrackCorner: CGFloat = 11
                    let modeActiveCorner: CGFloat = 8
                    HStack(spacing: 0) {
                        ForEach(Array(layouts.enumerated()), id: \.element.id) { _, layout in
                            let isActive = slide.layout == layout
                            Button {
                                setPlaceStopLayout(layout, for: focusedIndex)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: layoutIcon(layout))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(layoutLabel(layout))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 32)
                                .background {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: modeActiveCorner, style: .continuous)
                                            .fill(studioToolbarSegmentActiveColor)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.15), value: isActive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: modeTrackCorner, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(height: modeSelectorReservedHeight)
                } else {
                    Color.clear
                        .frame(height: modeSelectorReservedHeight)
                }
            case .cover, .mapRoute, .placeIntroMap:
                Color.clear
                    .frame(height: modeSelectorReservedHeight)
            }
        }
    }

    /// Tool strip shown below `modeSelectRow` only when split layout is
    /// active — Swap and Border divider controls.
    @ViewBuilder
    private var splitToolsRow: some View {
        if let slide = currentSlide,
           slide.layout == .split,
           slide.kind == .placeStop || slide.kind == .placeIntroMap {
            let canSwapSplitPhotos = slide.kind == .placeStop && slide.splitBottomPhotoID != nil
            ZStack(alignment: .trailing) {
                HStack(spacing: 10) {
                    Button {
                        let idx = editorPagerFocusedSlideIndex
                        guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
                        pipMultiRepositionSession = nil
                        splitRepositionSession = SplitRepositionSession(slideIndex: idx, initialSlot: .top)
                    } label: {
                        Label("Crop", systemImage: "crop")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    Button {
                        swapSplitTopBottom(slideIndex: editorPagerFocusedSlideIndex)
                    } label: {
                        Label("Swap", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(canSwapSplitPhotos ? 0.88 : 0.32))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSwapSplitPhotos)

                    HStack(spacing: 0) {
                        ForEach(CarouselSplitDividerStyle.allCases) { style in
                            let active = slide.splitDividerStyle == style
                            Button {
                                setSplitDividerStyle(style)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: style == .straight ? "line.3.horizontal" : "scribble")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(style == .straight ? "Straight" : "Curve")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(active ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    active
                                        ? RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(studioToolbarSegmentActiveColor)
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                style == .straight ? "Straight border" : "Curved border"
                            )
                        }
                    }
                    .padding(2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(height: splitToolsReservedHeight, alignment: .top)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        } else {
            Color.clear
                .frame(height: splitToolsReservedHeight)
        }
    }

    private func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            slides = previous
        }
        clampCurrentIndexIfNeeded()
        syncSelectionAfterUndo()
    }

    /// Clears or adjusts the selected text block if undo restored a state where it is not available.
    private func syncSelectionAfterUndo() {
        guard currentSlide != nil else {
            selectedBlock = nil
            return
        }
        guard let block = selectedBlock else { return }
        if !availableBlocks.contains(block) {
            selectedBlock = availableBlocks.first
        }
    }

    /// Hides the currently selected block on this slide. Undo restores the prior `slides` snapshot.
    /// For the PIP cluster this reverts the slide to the single-hero layout, which also
    /// re-selects sibling slides that were deselected when the cluster was created.
    private func deleteSelectedBlock() {
        guard let selectedBlock else { return }
        // Must match the slide the pager is actually showing — `scrollPageID` can lead
        // `currentIndex` for a frame after swiping; mutating `slides[currentIndex]` hid
        // the wrong slide or felt like a no-op on the visible card.
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx) else { return }
        pushUndoSnapshot()
        withAnimation(.easeInOut(duration: 0.25)) {
            switch selectedBlock {
            case .primary:
                slides[idx].isPrimaryHidden = true
            case .secondary:
                slides[idx].isSecondaryHidden = true
            case .pipCluster:
                revertPIPClusterToSingle(slideIndex: idx)
            }
        }
        // Clear selection after deleting the block.
        self.selectedBlock = availableBlocks.first
        // Collapse any open drop-up when the cluster disappears — the category tabs
        // for a different block type won't match the panel content.
        self.activePIPCategory = nil
    }

    /// Returns the editable text for the currently selected block, used to seed
    /// `inlineTextDraft` when the user opens the inline text editor.
    private var currentBlockText: String {
        guard let slide = currentSlide else { return "" }
        switch (slide.kind, selectedBlock) {
        case (.cover, .primary):      return slide.coverTitle ?? ""
        case (.mapRoute, .primary), (.placeIntroMap, .primary):
            return slide.dayTitle ?? slide.dayInfoLine1 ?? ""
        case (.mapRoute, .secondary), (.placeIntroMap, .secondary):
            return slide.dayStory ?? ""
        case (.placeStop, .primary):  return slide.placeStop?.placeTitle ?? ""
        case (.placeStop, .secondary): return slide.placeStop?.placeSubtitle ?? ""
        default: return ""
        }
    }

    /// Same as `currentBlockText` but reads from the captured slide/block so the `onDismiss`
    /// revert always reverts to the correct pre-edit value even if selection changed.
    private var capturedBlockText: String {
        guard slides.indices.contains(textEditSlideIndexCapture),
              let block = textEditBlockCapture else { return "" }
        let slide = slides[textEditSlideIndexCapture]
        switch (slide.kind, block) {
        case (.cover, .primary):       return slide.coverTitle ?? ""
        case (.mapRoute, .primary), (.placeIntroMap, .primary):
            return slide.dayTitle ?? slide.dayInfoLine1 ?? ""
        case (.mapRoute, .secondary), (.placeIntroMap, .secondary):
            return slide.dayStory ?? ""
        case (.placeStop, .primary):   return slide.placeStop?.placeTitle ?? ""
        case (.placeStop, .secondary): return slide.placeStop?.placeSubtitle ?? ""
        default: return ""
        }
    }

    /// True when the inline editor should show a second caption field (place name + caption).
    private var showsInlineCaptionField: Bool {
        textEditBlockCapture == .primary &&
        slides.indices.contains(textEditSlideIndexCapture) &&
        slides[textEditSlideIndexCapture].kind == .placeStop
    }

    private var inlineTextEditCapturePair: (CarouselSlideKind, SlideBlockID)? {
        guard slides.indices.contains(textEditSlideIndexCapture),
              let block = textEditBlockCapture else { return nil }
        return (slides[textEditSlideIndexCapture].kind, block)
    }

    private var inlineTextPrimarySectionTitle: String {
        guard let (kind, block) = inlineTextEditCapturePair else { return "Text" }
        switch (kind, block) {
        case (.cover, .primary): return "Cover title"
        case (.mapRoute, .primary): return "Day heading"
        case (.mapRoute, .secondary): return "Day story"
        case (.placeIntroMap, .primary): return "Place heading"
        case (.placeIntroMap, .secondary): return "Place story"
        case (.placeStop, .primary): return "Place name"
        case (.placeStop, .secondary): return "Subtitle"
        default: return "Text"
        }
    }

    private var inlineTextPrimarySectionSubtitle: String {
        guard let (kind, block) = inlineTextEditCapturePair else {
            return "Edits apply to the selected text on this slide."
        }
        switch (kind, block) {
        case (.cover, .primary):
            return "Shown centered on your carousel cover."
        case (.mapRoute, .primary):
            return "The large line at the top of the day map slide."
        case (.mapRoute, .secondary):
            return "Optional. Shown along the bottom of the map when this block has text."
        case (.placeIntroMap, .primary):
            return "Place name and city on the photo strip of this split map slide (same order as the classic map heading)."
        case (.placeIntroMap, .secondary):
            return "Optional. Shown along the bottom of the map when this block has text."
        case (.placeStop, .primary):
            return "The bold place title at the bottom of this photo."
        case (.placeStop, .secondary):
            return "Optional. Smaller line in the top corner (for example area or country)."
        default:
            return "Shown on this slide when this text block is visible."
        }
    }

    private var inlineTextSecondarySectionTitle: String? {
        guard showsInlineCaptionField else { return nil }
        return "Caption or story"
    }

    private var inlineTextSecondarySectionSubtitle: String? {
        guard showsInlineCaptionField else { return nil }
        return "Optional. Shown under the place name when there is something to display (photo caption, recap narrative, or notes)."
    }

    private var selectedBlockSupportsInlineTextEdit: Bool {
        guard let slide = currentSlide, let block = selectedBlock else { return false }
        return carouselStudioSlideBlockSupportsInlineTextEdit(kind: slide.kind, block: block)
    }

    private func presentInlineTextEditor() {
        guard selectedBlockSupportsInlineTextEdit,
              let block = selectedBlock else { return }
        let idx = editorPagerFocusedSlideIndex
        guard slides.indices.contains(idx) else { return }
        textEditSlideIndexCapture = idx
        textEditBlockCapture = block
        inlineTextEditCommitted = false
        let slide = slides[idx]
        switch (slide.kind, block) {
        case (.cover, .primary):
            inlineTextDraft = slide.coverTitle ?? ""
        case (.mapRoute, .primary), (.placeIntroMap, .primary):
            inlineTextDraft = slide.dayTitle ?? slide.dayInfoLine1 ?? ""
        case (.mapRoute, .secondary), (.placeIntroMap, .secondary):
            inlineTextDraft = slide.dayStory ?? ""
        case (.placeStop, .primary):
            inlineTextDraft = slide.placeStop?.placeTitle ?? ""
            inlineCaptionDraft = slide.photoCaption ?? slide.caption ?? ""
        case (.placeStop, .secondary):
            inlineTextDraft = slide.placeStop?.placeSubtitle ?? ""
        default:
            inlineTextDraft = ""
        }
        showsTextEditLine = true
    }

    /// Writes `inlineTextDraft` (and `inlineCaptionDraft` for placeStop primary) back
    /// into the appropriate field(s) of the captured slide and dismisses the text editor.
    /// Uses `textEditBlockCapture` / `textEditSlideIndexCapture` (set when the editor opens)
    /// so the write always targets the correct slide/block even if `selectedBlock` or
    /// `currentIndex` was changed by a lifecycle event while the cover was showing.
    private func commitInlineTextEdit() {
        let idx = textEditSlideIndexCapture
        guard slides.indices.contains(idx), let block = textEditBlockCapture else {
            showsTextEditLine = false
            return
        }
        inlineTextEditCommitted = true
        pushUndoSnapshot()
        // Keep PIP cluster position stable when saving text edits.
        let preservedPIPOffset = slides[idx].pipOffset
        let text = inlineTextDraft
        switch (slides[idx].kind, block) {
        case (.cover, .primary):      slides[idx].coverTitle = text
        case (.mapRoute, .primary), (.placeIntroMap, .primary):
            // Keep line 1 fields aligned so studio preview, export, and any reader of
            // `dayInfoLine1` (loaded map slides use it when `dayTitle` is nil) stay consistent.
            slides[idx].dayTitle = text
            slides[idx].dayInfoLine1 = text
            if var s = slides[idx].placeStop {
                s.placeTitle = text
                slides[idx].placeStop = s
            }
        case (.mapRoute, .secondary), (.placeIntroMap, .secondary): slides[idx].dayStory = text
        case (.placeStop, .primary):
            var slide = slides[idx]
            if var stop = slide.placeStop {
                stop.placeTitle = text
                slide.placeStop = stop
            }
            slide.photoCaption = inlineCaptionDraft
            slides[idx] = slide
        case (.placeStop, .secondary):
            var slide = slides[idx]
            if var stop = slide.placeStop {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.placeSubtitle = trimmed.isEmpty ? nil : trimmed
                slide.placeStop = stop
            }
            slides[idx] = slide
        default: break
        }
        if slides[idx].layout == .pip {
            slides[idx].pipOffset = preservedPIPOffset
        }
        showsTextEditLine = false
        inlineTextFocusField = nil
    }

    private func cancelInlineTextEdit() {
#if DEBUG
        print("[CarouselStudio][TextEdit] cancelInlineTextEdit()")
#endif
        inlineTextDraft = capturedBlockText
        if showsInlineCaptionField {
            let idx = textEditSlideIndexCapture
            inlineCaptionDraft = slides.indices.contains(idx)
                ? (slides[idx].photoCaption ?? slides[idx].caption ?? "")
                : ""
        }
        inlineTextEditCommitted = true
        showsTextEditLine = false
        inlineTextFocusField = nil
    }

    /// Reverts a place-stop slide back to the single-photo layout. Mirrors the
    /// sibling-sync logic in `SocialPostStudioSheet.setLayout(.single, ...)`:
    /// sibling slides that were auto-deselected when `.pip` activated are
    /// re-selected so every photo is visible again as its own slide.
    private func revertPIPClusterToSingle(slideIndex: Int) {
        guard slides.indices.contains(slideIndex) else { return }
        guard slides[slideIndex].kind == .placeStop else { return }
        let stopID = slides[slideIndex].placeStop?.id
        releaseMultiLayoutGrouping(primaryIndex: slideIndex, slides: &slides)
        slides[slideIndex].layout = .single
        slides[slideIndex].splitTopFraming = nil
        slides[slideIndex].splitBottomFraming = nil
        invalidatePIPBackgroundRemovalForMutation(at: slideIndex)
        if let stopID {
            repopulatePipPayloadsForPlaceStop(stopID: stopID, slides: &slides)
        }
    }

    /// Rotates the PIP cluster's photos so the current hero moves into the cluster and
    /// the first PIP thumbnail takes its place. Gives users a one-tap way to promote a
    /// cluster photo without leaving the editor. Rotates `pipPhotoIDs` alongside
    /// `pipImages` so the hero ID stays aligned with the hero image.
    private func swapPIPPhotos() {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip,
              !slides[idx].pipImages.isEmpty,
              let hero = slides[idx].heroImage else { return }
        pushUndoSnapshot()
        var pip = slides[idx].pipImages
        var pipIDs = slides[idx].pipPhotoIDs
        var framings = slides[idx].pipThumbnailFramings
        while framings.count < pip.count { framings.append(nil) }
        if framings.count > pip.count { framings = Array(framings.prefix(pip.count)) }
        if !framings.isEmpty { framings.removeFirst() }
        let promoted = pip.removeFirst()
        let promotedID: UUID? = pipIDs.isEmpty ? nil : pipIDs.removeFirst()
        pip.append(hero)
        framings.append(nil)
        if let heroID = slides[idx].heroPhotoID {
            pipIDs.append(heroID)
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            slides[idx].heroImage = promoted
            slides[idx].heroPhotoID = promotedID
            slides[idx].pipImages = pip
            slides[idx].pipPhotoIDs = pipIDs
            slides[idx].pipThumbnailFramings = framings
        }
        invalidatePIPBackgroundRemovalForMutation(at: idx)
    }

    /// Replaces the large hero backdrop with another included photo from the same place.
    /// If the picked photo already lives in the PIP strip, performs a straight swap with
    /// the current hero (images + IDs). Otherwise loads the asset and moves the former
    /// hero into the cluster the same way a new add would (hidden fourth slot allowed).
    private func swapHeroWithPlacePhoto(_ photo: RecapPhoto, slideIndex slideIdx: Int) {
        guard slides.indices.contains(slideIdx),
              slides[slideIdx].layout == .pip,
              slides[slideIdx].kind == .placeStop else { return }
        if photo.id == slides[slideIdx].heroPhotoID { return }
        pushUndoSnapshot()

        if let pipIdx = slides[slideIdx].pipPhotoIDs.firstIndex(of: photo.id) {
            let pipImg = slides[slideIdx].pipImages[pipIdx]
            let pipPID = slides[slideIdx].pipPhotoIDs[pipIdx]
            let oldHero = slides[slideIdx].heroImage
            let oldHID = slides[slideIdx].heroPhotoID
            var fr = slides[slideIdx].pipThumbnailFramings
            while fr.count <= pipIdx { fr.append(nil) }

            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].heroImage = pipImg
                slides[slideIdx].heroPhotoID = pipPID
                slides[slideIdx].pipImages[pipIdx] = oldHero ?? pipImg
                slides[slideIdx].pipPhotoIDs[pipIdx] = oldHID ?? pipPID
                fr[pipIdx] = nil
                slides[slideIdx].pipThumbnailFramings = fr
            }
            invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            return
        }

        Task {
            let targetSize = CGSize(width: 1080, height: 1080)
            guard let localId = photo.localIdentifier,
                  let loaded = await loadCarouselAssetImage(identifier: localId, size: targetSize, pixelCap: 1080)
            else { return }
            await MainActor.run {
                guard slides.indices.contains(slideIdx),
                      slides[slideIdx].layout == .pip else { return }
                let oldHero = slides[slideIdx].heroImage
                let oldHID = slides[slideIdx].heroPhotoID

                slides[slideIdx].heroImage = loaded
                slides[slideIdx].heroPhotoID = photo.id

                guard let oImg = oldHero, let oid = oldHID else { return }

                var imgs = slides[slideIdx].pipImages
                var ids = slides[slideIdx].pipPhotoIDs
                var fr = slides[slideIdx].pipThumbnailFramings
                let vc = slides[slideIdx].pipVisibleCount
                let insertAt = max(0, min(vc, imgs.count))
                while fr.count < insertAt { fr.append(nil) }
                fr.insert(nil, at: insertAt)
                imgs.insert(oImg, at: insertAt)
                ids.insert(oid, at: insertAt)

                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIdx].pipImages = imgs
                    slides[slideIdx].pipPhotoIDs = ids
                    slides[slideIdx].pipThumbnailFramings = fr
                    slides[slideIdx].pipVisibleCount = min(3, vc + 1)
                }
                invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            }
        }
    }

    /// Place photos that can fill one Multi inset: every photo on the stop except those
    /// already shown in **any** visible inset (so the grid stays duplicate-free). Hero may
    /// still appear for swap-with-main; not-included stop photos are included.
    private func recapPhotosEligibleForPIPInsetReplace(slide: CarouselSlide, thumbIndex: Int) -> [RecapPhoto] {
        guard let stop = slide.placeStop else { return [] }
        let vis = min(max(1, slide.pipVisibleCount), min(slide.pipImages.count, 3))
        guard thumbIndex >= 0, thumbIndex < vis else { return stop.photos }
        var blocked = Set<UUID>()
        for i in 0..<vis where i < slide.pipPhotoIDs.count {
            blocked.insert(slide.pipPhotoIDs[i])
        }
        return stop.photos.filter { !blocked.contains($0.id) }
    }

    /// If `assignedPhotoID` is already used on another Multi inset for the same place
    /// (including another slide in this deck), that slot receives the displaced content.
    private func reconcileOtherPIPSlotsDisplacedBy(
        assignedPhotoID: UUID,
        excludingSlide slideIdx: Int,
        excludingThumb thumbIdx: Int,
        displacedImage: UIImage,
        displacedPhotoID: UUID,
        displacedFraming: StudioImageFraming?
    ) {
        guard let stopID = slides[slideIdx].placeStop?.id else { return }
        var invalidatedSlides = Set<Int>()
        for si in slides.indices {
            guard slides[si].kind == .placeStop,
                  slides[si].layout == .pip,
                  slides[si].placeStop?.id == stopID else { continue }
            let vis = min(max(1, slides[si].pipVisibleCount), slides[si].pipImages.count, 3)
            for j in 0..<vis where !(si == slideIdx && j == thumbIdx) {
                guard j < slides[si].pipPhotoIDs.count, j < slides[si].pipImages.count else { continue }
                guard slides[si].pipPhotoIDs[j] == assignedPhotoID else { continue }
                slides[si].pipImages[j] = displacedImage
                slides[si].pipPhotoIDs[j] = displacedPhotoID
                while slides[si].pipThumbnailFramings.count <= j { slides[si].pipThumbnailFramings.append(nil) }
                slides[si].pipThumbnailFramings[j] = displacedFraming
                if slides[si].pipBackgroundRemoved, j < slides[si].pipProcessedImages.count {
                    slides[si].pipProcessedImages[j] = displacedImage
                }
                invalidatedSlides.insert(si)
            }
        }
        for si in invalidatedSlides {
            invalidatePIPBackgroundRemovalForMutation(at: si)
        }
    }

    /// Replaces one Multi inset slot (grouped or ungrouped) with another place photo.
    /// Swaps with the hero or another visible slot when the pick is already on the slide;
    /// otherwise loads from the photo library. Double-tap an inset to open the picker.
    private func replacePIPClusterInsetSlot(
        with photo: RecapPhoto,
        slideIndex slideIdx: Int,
        thumbIndex: Int
    ) {
        guard slides.indices.contains(slideIdx),
              slides[slideIdx].layout == .pip,
              slides[slideIdx].kind == .placeStop else { return }
        let vis = min(max(1, slides[slideIdx].pipVisibleCount), slides[slideIdx].pipImages.count)
        guard thumbIndex >= 0, thumbIndex < vis, thumbIndex < 3 else { return }
        guard thumbIndex < slides[slideIdx].pipPhotoIDs.count,
              thumbIndex < slides[slideIdx].pipImages.count else { return }
        if photo.id == slides[slideIdx].pipPhotoIDs[thumbIndex] { return }
        pushUndoSnapshot()

        if photo.id == slides[slideIdx].heroPhotoID {
            let pipImg = slides[slideIdx].pipImages[thumbIndex]
            let pipPID = slides[slideIdx].pipPhotoIDs[thumbIndex]
            let oldHero = slides[slideIdx].heroImage
            let oldHID = slides[slideIdx].heroPhotoID
            var fr = slides[slideIdx].pipThumbnailFramings
            while fr.count <= thumbIndex { fr.append(nil) }

            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].heroImage = pipImg
                slides[slideIdx].heroPhotoID = pipPID
                slides[slideIdx].pipImages[thumbIndex] = oldHero ?? pipImg
                slides[slideIdx].pipPhotoIDs[thumbIndex] = oldHID ?? pipPID
                fr[thumbIndex] = nil
                slides[slideIdx].pipThumbnailFramings = fr
            }
            invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            return
        }

        if let j = slides[slideIdx].pipPhotoIDs.firstIndex(of: photo.id),
           j < slides[slideIdx].pipImages.count,
           j != thumbIndex {
            var imgs = slides[slideIdx].pipImages
            var ids = slides[slideIdx].pipPhotoIDs
            var fr = slides[slideIdx].pipThumbnailFramings
            let hi = max(thumbIndex, j)
            while fr.count <= hi { fr.append(nil) }
            imgs.swapAt(thumbIndex, j)
            ids.swapAt(thumbIndex, j)
            fr.swapAt(thumbIndex, j)

            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].pipImages = imgs
                slides[slideIdx].pipPhotoIDs = ids
                slides[slideIdx].pipThumbnailFramings = fr
            }
            invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            return
        }

        let displacedImage = slides[slideIdx].pipImages[thumbIndex]
        let displacedPhotoID = slides[slideIdx].pipPhotoIDs[thumbIndex]
        let displacedFraming = thumbIndex < slides[slideIdx].pipThumbnailFramings.count
            ? slides[slideIdx].pipThumbnailFramings[thumbIndex]
            : nil

        Task {
            let targetSize = CGSize(width: 1080, height: 1080)
            let trimmed = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var loaded: UIImage?
            if !trimmed.isEmpty {
                loaded = await loadCarouselAssetImage(identifier: trimmed, size: targetSize, pixelCap: 1080)
            }
            if loaded == nil {
                loaded = await loadRecapPhotoUIImage(photo: photo, size: targetSize, pixelCap: 1080)
            }
            guard let loaded else { return }
            await MainActor.run {
                guard slides.indices.contains(slideIdx),
                      slides[slideIdx].layout == .pip,
                      thumbIndex < slides[slideIdx].pipImages.count,
                      thumbIndex < slides[slideIdx].pipPhotoIDs.count else { return }
                var fr = slides[slideIdx].pipThumbnailFramings
                while fr.count <= thumbIndex { fr.append(nil) }
                fr[thumbIndex] = nil
                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIdx].pipImages[thumbIndex] = loaded
                    slides[slideIdx].pipPhotoIDs[thumbIndex] = photo.id
                    slides[slideIdx].pipThumbnailFramings = fr
                }
                reconcileOtherPIPSlotsDisplacedBy(
                    assignedPhotoID: photo.id,
                    excludingSlide: slideIdx,
                    excludingThumb: thumbIndex,
                    displacedImage: displacedImage,
                    displacedPhotoID: displacedPhotoID,
                    displacedFraming: displacedFraming
                )
                invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            }
        }
    }

    /// Sets `pipVisibleCount` on the current slide (clamped 1 ... 3). Retained
    /// for internal callers (e.g. `addPIPPhotoToCluster`). The explicit 1/2/3
    /// count pills that used to live in the Photos drop-up were removed — count
    /// is driven indirectly via the Add / Remove pills in `pipCategoryTabBar`.
    private func setPIPVisibleCount(_ count: Int) {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        let clamped = min(max(count, 1), 3)
        guard slides[idx].pipVisibleCount != clamped else { return }
        pushUndoSnapshot()
        withAnimation(.easeInOut(duration: 0.2)) {
            slides[idx].pipVisibleCount = clamped
        }
    }

    /// Removes the bottom-most photo from the current cluster (the last
    /// visible slot) and drops `pipVisibleCount` by one. Inverse of
    /// `addPIPPhotoToCluster` — symmetry means Add-then-Remove cleanly walks
    /// the user back to where they started.
    private func removeLastPIPPhoto() {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        let slide = slides[idx]
        let visible = min(max(0, slide.pipVisibleCount), slide.pipImages.count)
        guard visible > 0 else { return }
        pushUndoSnapshot()
        let removeAt = visible - 1
        withAnimation(.easeInOut(duration: 0.22)) {
            removePIPPhotoArrayEntries(at: removeAt, in: idx)
            slides[idx].pipVisibleCount = max(1, visible - 1)
        }
        invalidatePIPBackgroundRemovalForMutation(at: idx)
    }

    /// Removes the photo at `photoIndex` when the cluster is ungrouped and that
    /// photo is currently selected. If only one photo remains after removal the
    /// cluster re-groups, preserving the removed photo's position as the new
    /// cluster anchor so the remaining photo doesn't jump.
    private func removeSelectedPIPPhoto() {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip,
              slides[idx].pipIsUngrouped,
              let photoIndex = selectedPIPPhotoIndex else { return }
        let visible = min(max(0, slides[idx].pipVisibleCount), slides[idx].pipImages.count)
        guard photoIndex < visible else { return }
        pushUndoSnapshot()
        selectedPIPPhotoIndex = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            removePIPPhotoArrayEntries(at: photoIndex, in: idx)
            let newVisible = max(1, visible - 1)
            slides[idx].pipVisibleCount = newVisible
            // Auto-rejoin when only one photo remains — no point being ungrouped.
            if newVisible <= 1 {
                let remainingOffset = slides[idx].pipPhotoOffsets.first ?? slides[idx].pipOffset
                slides[idx].pipOffset = remainingOffset
                slides[idx].pipIsUngrouped = false
                slides[idx].pipPhotoOffsets = []
                slides[idx].pipPhotoStyles = []
                slides[idx].pipUngroupedZOrder = []
            }
        }
        invalidatePIPBackgroundRemovalForMutation(at: idx)
    }

    /// Removes all index-aligned PIP array entries at `index`.
    /// Does NOT change `pipVisibleCount` — callers handle that.
    private func removePIPPhotoArrayEntries(at index: Int, in slideIndex: Int) {
        guard slides.indices.contains(slideIndex) else { return }
        func removeIfInBounds<T>(_ arr: inout [T], at i: Int) {
            guard i < arr.count else { return }
            arr.remove(at: i)
        }
        removeIfInBounds(&slides[slideIndex].pipImages, at: index)
        removeIfInBounds(&slides[slideIndex].pipPhotoIDs, at: index)
        removeIfInBounds(&slides[slideIndex].pipThumbnailFramings, at: index)
        removeIfInBounds(&slides[slideIndex].pipProcessedImages, at: index)
        removeIfInBounds(&slides[slideIndex].pipPhotoOffsets, at: index)
        removeIfInBounds(&slides[slideIndex].pipPhotoStyles, at: index)
        if slides[slideIndex].pipIsUngrouped {
            slides[slideIndex].pipUngroupedZOrder = slides[slideIndex].pipUngroupedZOrder
                .filter { $0 != index }
                .map { $0 > index ? $0 - 1 : $0 }
        }
    }

    /// Sets `pipBorderColor` on the current slide. Used by the Border color drop-up.
    /// Also re-enables the border, so tapping any color swatch after "no border"
    /// immediately paints the outline back in.
    // MARK: - PIP effective style (respects per-photo override when ungrouped)

    /// Border color to display in the toolbar — photo override when a photo is
    /// selected in ungrouped mode, cluster-level default otherwise.
    private var pipEffectiveBorderColor: StudioTextColor {
        guard let slide = currentSlide else { return .white }
        if slide.pipIsUngrouped, let i = selectedPIPPhotoIndex {
            return slide.effectivePIPPhotoStyle(at: i).borderColor
        }
        return slide.pipBorderColor
    }

    private var pipEffectiveBorderEnabled: Bool {
        guard let slide = currentSlide else { return true }
        if slide.pipIsUngrouped, let i = selectedPIPPhotoIndex {
            return slide.effectivePIPPhotoStyle(at: i).borderEnabled
        }
        return slide.pipBorderEnabled
    }

    private var pipEffectiveMaskStyle: CarouselPIPThumbMaskStyle {
        guard let slide = currentSlide else { return .roundedRect }
        if slide.pipIsUngrouped, let i = selectedPIPPhotoIndex {
            return slide.effectivePIPPhotoStyle(at: i).thumbMaskStyle
        }
        return slide.pipThumbMaskStyle
    }

    /// Ensures `slides[idx].pipPhotoStyles` is long enough for `photoIndex`,
    /// filling gaps with nil (cluster-level default).
    private func ensurePIPPhotoStyleCapacity(at photoIndex: Int, in slideIndex: Int) {
        guard slides.indices.contains(slideIndex) else { return }
        if slides[slideIndex].pipPhotoStyles.count <= photoIndex {
            let needed = photoIndex + 1 - slides[slideIndex].pipPhotoStyles.count
            slides[slideIndex].pipPhotoStyles.append(contentsOf: Array(repeating: nil, count: needed))
        }
        if slides[slideIndex].pipPhotoStyles[photoIndex] == nil {
            slides[slideIndex].pipPhotoStyles[photoIndex] = slides[slideIndex].effectivePIPPhotoStyle(at: photoIndex)
        }
    }

    private func setPIPBorderColor(_ color: StudioTextColor) {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        if slides[idx].pipIsUngrouped, let photoIndex = selectedPIPPhotoIndex {
            let current = slides[idx].effectivePIPPhotoStyle(at: photoIndex)
            guard current.borderColor != color || !current.borderEnabled else { return }
            pushUndoSnapshot()
            ensurePIPPhotoStyleCapacity(at: photoIndex, in: idx)
            slides[idx].pipPhotoStyles[photoIndex]?.borderColor = color
            slides[idx].pipPhotoStyles[photoIndex]?.borderEnabled = true
        } else {
            let slide = slides[idx]
            guard slide.pipBorderColor != color || !slide.pipBorderEnabled else { return }
            pushUndoSnapshot()
            slides[idx].pipBorderColor = color
            slides[idx].pipBorderEnabled = true
        }
    }

    /// Turns off the PIP thumbnail outline on the current slide (or selected photo
    /// when ungrouped). `pipBorderColor` is preserved so tapping a color swatch
    /// later restores the border without losing the previous selection.
    private func disablePIPBorder() {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        if slides[idx].pipIsUngrouped, let photoIndex = selectedPIPPhotoIndex {
            guard slides[idx].effectivePIPPhotoStyle(at: photoIndex).borderEnabled else { return }
            pushUndoSnapshot()
            ensurePIPPhotoStyleCapacity(at: photoIndex, in: idx)
            slides[idx].pipPhotoStyles[photoIndex]?.borderEnabled = false
        } else {
            guard slides[idx].pipBorderEnabled else { return }
            pushUndoSnapshot()
            slides[idx].pipBorderEnabled = false
        }
    }

    // MARK: - PIP background removal (Vision)

    private var pipBackgroundRemovalSupported: Bool {
        if #available(iOS 16, *) { return true }
        return false
    }

    private var pipBackgroundRemovalPanelBusy: Bool {
        pipBackgroundRemovalSlideIndex != nil && !pipBackgroundRemovalLoadingSlots.isEmpty
    }

    private var pipBackgroundRemovalToggle: Binding<Bool> {
        Binding(
            get: { currentSlide?.pipBackgroundRemoved ?? false },
            set: { setPIPBackgroundRemovalEnabled($0) }
        )
    }

    private var pipStyleToolbarCategories: [PIPStyleCategory] {
        let ordered: [PIPStyleCategory] = [.border, .shape, .size, .background]
        if #available(iOS 16, *) { return ordered }
        return ordered.filter { $0 != .background }
    }

    private func resetPIPBackgroundRemovalState(for slideIndex: Int) {
        guard slides.indices.contains(slideIndex) else { return }
        slides[slideIndex].pipBackgroundRemoved = false
        slides[slideIndex].pipProcessedImages = []
    }

    private func invalidatePIPBackgroundRemovalForMutation(at slideIndex: Int) {
        pipBackgroundRemovalGeneration += 1
        pipBackgroundRemovalSlideIndex = nil
        pipBackgroundRemovalLoadingSlots = []
        resetPIPBackgroundRemovalState(for: slideIndex)
    }

    private func setPIPBackgroundRemovalEnabled(_ enabled: Bool) {
        guard pipBackgroundRemovalSupported else { return }
        let idx = editorPagerFocusedSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip,
              !slides[idx].pipImages.isEmpty else { return }
        let visible = min(max(0, slides[idx].pipVisibleCount), slides[idx].pipImages.count)
        guard visible > 0 else { return }
        if slides[idx].pipBackgroundRemoved == enabled { return }

        let targetSlots: [Int]
        if slides[idx].pipIsUngrouped {
            guard let sel = selectedPIPPhotoIndex, sel >= 0, sel < visible else { return }
            targetSlots = [sel]
        } else {
            // Joined cluster: only the first inset (slot 0) — avoids running Vision on every thumb at once.
            targetSlots = [0]
        }

        pushUndoSnapshot()
        pipBackgroundRemovalGeneration += 1
        let generation = pipBackgroundRemovalGeneration
        if enabled {
            slides[idx].pipBackgroundRemoved = true
            slides[idx].pipProcessedImages = Array(repeating: nil, count: slides[idx].pipImages.count)
            pipBackgroundRemovalSlideIndex = idx
            pipBackgroundRemovalLoadingSlots = Set(targetSlots)
            Task {
                await runPIPBackgroundRemoval(
                    slideIndex: idx,
                    slotIndices: targetSlots,
                    generation: generation
                )
            }
        } else {
            pipBackgroundRemovalSlideIndex = nil
            pipBackgroundRemovalLoadingSlots = []
            slides[idx].pipBackgroundRemoved = false
            slides[idx].pipProcessedImages = []
        }
    }

    private func runPIPBackgroundRemoval(slideIndex: Int, slotIndices: [Int], generation: UInt64) async {
        for i in slotIndices {
            if Task.isCancelled { break }
            let source: UIImage? = await MainActor.run {
                guard slides.indices.contains(slideIndex),
                      i < slides[slideIndex].pipImages.count else { return nil }
                return slides[slideIndex].pipImages[i]
            }
            guard let src = source else { continue }
            let processed = await removePIPBackground(from: src) ?? src
            await MainActor.run {
                guard generation == pipBackgroundRemovalGeneration,
                      slides.indices.contains(slideIndex),
                      slides[slideIndex].pipBackgroundRemoved,
                      slides[slideIndex].pipProcessedImages.count == slides[slideIndex].pipImages.count
                else { return }
                slides[slideIndex].pipProcessedImages[i] = processed
                pipBackgroundRemovalLoadingSlots.remove(i)
            }
        }
        await MainActor.run { completePIPBackgroundRemovalIfCurrent(generation: generation) }
    }

    private func completePIPBackgroundRemovalIfCurrent(generation: UInt64) {
        guard generation == pipBackgroundRemovalGeneration else { return }
        pipBackgroundRemovalLoadingSlots = []
        pipBackgroundRemovalSlideIndex = nil
    }

    /// Writes a new PIP thumbnail size scale without its own undo snapshot — the
    /// Size strip captures undo once at drag begin (see `pipClusterSizeSliderPanel`).
    private func setPIPClusterSizeScaleLive(_ raw: CGFloat) {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        let snapped = StudioPIPClusterSize.clampAndSnap(raw)
        if slides[idx].pipIsUngrouped, let photoIdx = selectedPIPPhotoIndex {
            let current = slides[idx].effectivePIPPhotoSizeScale(at: photoIdx)
            guard abs(snapped - current) > 0.0001 else { return }
            ensurePIPPhotoStyleCapacity(at: photoIdx, in: idx)
            slides[idx].pipPhotoStyles[photoIdx]?.sizeScale = snapped
        } else {
            guard abs(snapped - slides[idx].pipClusterSizeScale) > 0.0001 else { return }
            slides[idx].pipClusterSizeScale = snapped
        }
    }

    /// Vertical vs horizontal stacking for the PIP thumbnail column — driven from
    /// the "Style" menu in `pipStyleMenuButton`.
    private func applyPIPClusterStackStyle(_ style: CarouselPIPClusterStackStyle) {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        guard slides[idx].pipClusterStackStyle != style else { return }
        pushUndoSnapshot()
        slides[idx].pipClusterStackStyle = style
    }

    private func applyPIPThumbMaskStyle(_ style: CarouselPIPThumbMaskStyle) {
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        if slides[idx].pipIsUngrouped, let photoIndex = selectedPIPPhotoIndex {
            guard slides[idx].effectivePIPPhotoStyle(at: photoIndex).thumbMaskStyle != style else { return }
            pushUndoSnapshot()
            ensurePIPPhotoStyleCapacity(at: photoIndex, in: idx)
            slides[idx].pipPhotoStyles[photoIndex]?.thumbMaskStyle = style
        } else {
            guard slides[idx].pipThumbMaskStyle != style else { return }
            pushUndoSnapshot()
            slides[idx].pipThumbMaskStyle = style
        }
    }

    /// Rough slide width/height in points for PIP layout math (matches editor slot when height is not capped).
    private func estimatedEditorSlideCanvasSizeForPIP() -> (w: CGFloat, h: CGFloat) {
        let outerW = max(280, UIScreen.main.bounds.width)
        let slideContentW = max(220, outerW - 48)
        let idealH = slideContentW / max(0.01, editorPreviewAspectRatio)
        return (slideContentW, idealH)
    }

    /// Normalized deltas (added to `pipOffset`) so separated thumbnails start where each tile
    /// sat inside the grouped cluster instead of pixel-identical on one slot.
    private func pipUngroupFanNormalizedDeltas(slide: CarouselSlide, slideW: CGFloat, slideH: CGFloat) -> [CGSize] {
        let maxSlots = max(0, min(slide.pipVisibleCount, slide.pipImages.count, 3))
        guard slideW > 0, slideH > 0, maxSlots > 0 else {
            return (0..<maxSlots).map { _ in .zero }
        }
        let scale = slide.pipClusterSizeScale
        let thumbW = slideW * 0.30 * scale
        let thumbH = thumbW * 0.72
        let slotW = thumbW
        let slotH: CGFloat = slide.pipThumbMaskStyle == .circle ? thumbW : thumbH
        let spacing: CGFloat = 5
        return (0..<maxSlots).map { i in
            let pt: CGSize
            switch slide.pipClusterStackStyle {
            case .vertical:
                pt = CGSize(width: 0, height: CGFloat(i) * (slotH + spacing))
            case .horizontal:
                // Grouped cluster grows left from the trailing corner; slot 0 stays at the anchor.
                pt = CGSize(width: -CGFloat(i) * (slotW + spacing), height: 0)
            }
            return CGSize(
                width: pt.width / slideW,
                height: pt.height / slideH
            )
        }
    }

    /// Toggles between grouped cluster and individually-draggable thumbnails.
    /// When ungrouping, each photo offset is seeded to the current cluster position
    /// plus the same in-cluster spacing as grouped mode so every thumb is visible.
    private func togglePIPGrouping(for idx: Int) {
        guard slides.indices.contains(idx),
              slides[idx].layout == .pip else { return }
        pushUndoSnapshot()
        selectedPIPPhotoIndex = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            if slides[idx].pipIsUngrouped {
                slides[idx].pipIsUngrouped = false
                slides[idx].pipPhotoOffsets = []
                slides[idx].pipPhotoStyles = []
                slides[idx].pipUngroupedZOrder = []
            } else {
                let count = max(0, min(slides[idx].pipVisibleCount, slides[idx].pipImages.count))
                let clusterOffset = slides[idx].pipOffset
                let (sw, sh) = estimatedEditorSlideCanvasSizeForPIP()
                let fan = pipUngroupFanNormalizedDeltas(slide: slides[idx], slideW: sw, slideH: sh)
                slides[idx].pipIsUngrouped = true
                slides[idx].pipUngroupedZOrder = Array(0..<count)
                slides[idx].pipPhotoOffsets = (0..<count).map { i in
                    let d = i < fan.count ? fan[i] : .zero
                    return CGSize(
                        width: clusterOffset.width + d.width,
                        height: clusterOffset.height + d.height
                    )
                }
            }
        }
    }

    /// Moves one ungrouped inset to the top of the stack; relative order of the others is unchanged.
    private func raisePIPUngroupedThumbToFront(slideIndex idx: Int, thumbIndex: Int) {
        guard slides.indices.contains(idx), slides[idx].pipIsUngrouped else { return }
        let vis = max(0, min(slides[idx].pipVisibleCount, slides[idx].pipImages.count, 3))
        guard thumbIndex >= 0, thumbIndex < vis else { return }
        var order = slides[idx].pipUngroupedDrawOrder(visibleCount: vis)
        order.removeAll { $0 == thumbIndex }
        order.append(thumbIndex)
        slides[idx].pipUngroupedZOrder = order
    }

    private func availableSplitBottomPhotos(for slideIndex: Int) -> [RecapPhoto] {
        guard slides.indices.contains(slideIndex) else { return [] }
        let slide = slides[slideIndex]
        guard let stop = slide.placeStop else { return [] }
        return stop.photos.filter { photo in
            guard photo.isIncluded else { return false }
            if let heroID = slide.heroPhotoID, photo.id == heroID { return false }
            return true
        }
    }

    /// Opens the split-bottom picker flow for a slide. If only one candidate
    /// photo exists, it auto-applies that photo instead of presenting a sheet.
    private func presentSplitBottomPicker(for slideIndex: Int) {
        guard slides.indices.contains(slideIndex),
              slides[slideIndex].layout == .split else { return }
        let options = availableSplitBottomPhotos(for: slideIndex)
        if options.count == 1, let only = options.first {
            setSplitBottomPhoto(only, slideIndex: slideIndex)
            selectedSplitSlot = nil
        } else {
            splitBottomPickSlideIndex = slideIndex
            showsSplitBottomPhotoPicker = true
        }
    }

    private func setSplitDividerStyle(_ style: CarouselSplitDividerStyle) {
        let idx = editorPagerFocusedSlideIndex
        guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
        guard slides[idx].splitDividerStyle != style else { return }
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            pushUndoSnapshot()
            slides[idx].splitDividerStyle = style
        }
    }

    private func clearSplitBottomPhoto(slideIndex: Int) {
        guard slides.indices.contains(slideIndex), slides[slideIndex].layout == .split else { return }
        pushUndoSnapshot()
        let stopID = slides[slideIndex].placeStop?.id
        let previousBottomID = slides[slideIndex].splitBottomPhotoID
        withAnimation(.easeInOut(duration: 0.2)) {
            slides[slideIndex].splitBottomImage = nil
            slides[slideIndex].splitBottomPhotoID = nil
            slides[slideIndex].splitBottomFraming = nil
            if let stopID, let previousBottomID {
                for i in slides.indices where i != slideIndex {
                    guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                    if slides[i].heroPhotoID == previousBottomID {
                        slides[i].isSelected = true
                    }
                }
            }
        }
    }

    private func autoFillSplitBottomIfTwoPhotos(slideIndex: Int) {
        guard slides.indices.contains(slideIndex),
              slides[slideIndex].layout == .split,
              let stop = slides[slideIndex].placeStop else { return }
        let cluster = multiClusterCandidateIndices(from: slideIndex, stopID: stop.id, in: slides)
        guard cluster.count >= 2,
              let bottomID = slides[cluster[1]].heroPhotoID,
              let partner = stop.photos.first(where: { $0.id == bottomID }) else { return }
        if slides[slideIndex].splitBottomPhotoID == partner.id,
           slides[slideIndex].splitBottomImage != nil { return }
        setSplitBottomPhoto(partner, slideIndex: slideIndex)
    }

    private func setSplitBottomPhoto(_ photo: RecapPhoto, slideIndex: Int) {
        guard slides.indices.contains(slideIndex),
              slides[slideIndex].layout == .split else { return }
        if slides[slideIndex].splitBottomPhotoID == photo.id,
           slides[slideIndex].splitBottomImage != nil { return }

        // When the bottom photo id is still nil after switching to `.split`, the
        // sibling single slide is not yet hidden (`isSlideHiddenBySiblingPIP`
        // requires `splitBottomPhotoID`). A one-frame visible list change can
        // confuse `scrollPosition(id:)` and advance the pager. Commit identity +
        // sibling flags synchronously; only full-res image work stays async.
        let alreadyCorrectID = slides[slideIndex].splitBottomPhotoID == photo.id
        if !alreadyCorrectID {
            pushUndoSnapshot()
        }
        let stopID = slides[slideIndex].placeStop?.id
        let previousBottomID = slides[slideIndex].splitBottomPhotoID

        if !alreadyCorrectID {
            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIndex].splitBottomPhotoID = photo.id
                slides[slideIndex].splitBottomFraming = nil
                if let pipIdx = slides[slideIndex].pipPhotoIDs.firstIndex(of: photo.id),
                   slides[slideIndex].pipImages.indices.contains(pipIdx) {
                    slides[slideIndex].splitBottomImage = slides[slideIndex].pipImages[pipIdx]
                } else {
                    slides[slideIndex].splitBottomImage = nil
                }
                if let stopID {
                    for i in slides.indices where i != slideIndex {
                        guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                        if let previousBottomID, slides[i].heroPhotoID == previousBottomID {
                            slides[i].isSelected = true
                        }
                        if slides[i].heroPhotoID == photo.id {
                            slides[i].isSelected = false
                        }
                    }
                }
            }
            // Choosing a bottom photo can hide an earlier `.single` sibling (`splitBottomPhotoID`
            // matches its hero). Removing the leftmost page keeps scroll offset in points, so
            // `scrollPosition(id:)` can land on the next slide — re-pin like `setPlaceStopLayout`.
            if visibleSlideIndices.contains(slideIndex) {
                reassertEditorPagerToSlide(at: slideIndex)
            }
        }

        guard slides[slideIndex].splitBottomImage == nil else { return }

        Task {
            let target = CGSize(width: 1080, height: 1080)
            guard let image = await loadRecapPhotoUIImage(photo: photo, size: target, pixelCap: 1080) else { return }
            await MainActor.run {
                guard slides.indices.contains(slideIndex),
                      slides[slideIndex].layout == .split,
                      slides[slideIndex].splitBottomPhotoID == photo.id else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIndex].splitBottomImage = image
                }
            }
        }
    }

    private func swapSplitTopBottom(slideIndex: Int) {
        guard slides.indices.contains(slideIndex),
              slides[slideIndex].layout == .split,
              !isCarouselStudioMapKind(slides[slideIndex].kind),
              let bottomImage = slides[slideIndex].splitBottomImage,
              let bottomID = slides[slideIndex].splitBottomPhotoID else { return }
        pushUndoSnapshot()
        let oldHeroImage = slides[slideIndex].heroImage
        let oldHeroID = slides[slideIndex].heroPhotoID
        let oldTopFraming = slides[slideIndex].splitTopFraming
        let oldBottomFraming = slides[slideIndex].splitBottomFraming
        withAnimation(.easeInOut(duration: 0.22)) {
            slides[slideIndex].heroImage = bottomImage
            slides[slideIndex].heroPhotoID = bottomID
            slides[slideIndex].splitBottomImage = oldHeroImage
            slides[slideIndex].splitBottomPhotoID = oldHeroID
            slides[slideIndex].splitTopFraming = oldBottomFraming
            slides[slideIndex].splitBottomFraming = oldTopFraming
        }
    }

    // MARK: - Add photo

    /// Photos belonging to the current slide's place stop that are eligible to
    /// be added to the PIP cluster. Excludes:
    ///   • the current hero photo (would duplicate what's already the big image)
    ///   • any photo currently visible in the cluster (`pipPhotoIDs[0..<pipVisibleCount]`)
    ///   • photos the user has marked as not-included for this place
    ///
    /// Photos that are *loaded but hidden* (because the user reduced the count)
    /// are intentionally still shown — "Add photo" gives a single path to
    /// bringing them back whether they're already in `pipImages` or have to be
    /// freshly loaded from the Photos library.
    private var availableAddablePhotos: [RecapPhoto] {
        guard let slide = currentSlide, let placeStop = slide.placeStop else { return [] }
        let visibleCount = max(0, min(slide.pipVisibleCount, slide.pipPhotoIDs.count))
        let visibleIDs = Set(slide.pipPhotoIDs.prefix(visibleCount))
        return placeStop.photos.filter { photo in
            guard photo.isIncluded else { return false }
            if let heroID = slide.heroPhotoID, photo.id == heroID { return false }
            return !visibleIDs.contains(photo.id)
        }
    }

    /// True when the cluster has room for another photo AND at least one
    /// eligible source photo exists. Drives the "Add photo" vs "Swap photos"
    /// label on the primary PIP action button.
    private var canAddPIPPhoto: Bool {
        guard let slide = currentSlide else { return false }
        guard slide.pipVisibleCount < 3 else { return false }
        return !availableAddablePhotos.isEmpty
    }

    /// Adds `photo` to the current slide's PIP cluster. If the photo is already
    /// loaded in a hidden slot we simply move it forward (no image reload); if
    /// it's fresh we load its image and append a new slot. In both cases
    /// `pipVisibleCount` is bumped so the newly-added photo is visible.
    private func addPIPPhotoToCluster(_ photo: RecapPhoto) {
        let slideIdx = editorMutationSlideIndex
        guard slides.indices.contains(slideIdx),
              slides[slideIdx].layout == .pip else { return }
        pushUndoSnapshot()

        var images = slides[slideIdx].pipImages
        var ids = slides[slideIdx].pipPhotoIDs
        let visibleCount = max(0, min(slides[slideIdx].pipVisibleCount, ids.count))

        // If the picked photo is already loaded somewhere in pipImages (hidden
        // slot, or simply later in the array), move it into the first position
        // beyond the current visible range so it appears on the next render.
        if let existingIdx = ids.firstIndex(of: photo.id) {
            if existingIdx != visibleCount {
                var fr = slides[slideIdx].pipThumbnailFramings
                let nBefore = images.count
                while fr.count < nBefore { fr.append(nil) }
                var movedFraming: StudioImageFraming? = nil
                if existingIdx < fr.count {
                    movedFraming = fr.remove(at: existingIdx)
                }
                let img = images.remove(at: existingIdx)
                let id = ids.remove(at: existingIdx)
                let insertAt = min(visibleCount, images.count)
                images.insert(img, at: insertAt)
                ids.insert(id, at: insertAt)
                if let mf = movedFraming {
                    fr.insert(mf, at: min(insertAt, fr.count))
                }
                slides[slideIdx].pipThumbnailFramings = fr
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].pipImages = images
                slides[slideIdx].pipPhotoIDs = ids
                slides[slideIdx].pipVisibleCount = min(3, visibleCount + 1)
            }
            invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            return
        }

        // Otherwise: load the image off-main, then append and bump visibleCount.
        // `guard` above ensured `layout == .pip`, but by the time the async load
        // returns the user may have navigated away or toggled the layout — we
        // re-check inside the Task before committing.
        Task {
            let targetSize = CGSize(width: 1080, height: 1080)
            guard let localId = photo.localIdentifier,
                  let loaded = await loadCarouselAssetImage(identifier: localId, size: targetSize, pixelCap: 1080) else {
                return
            }
            await MainActor.run {
                guard slides.indices.contains(slideIdx),
                      slides[slideIdx].layout == .pip else { return }
                var imgs = slides[slideIdx].pipImages
                var ids2 = slides[slideIdx].pipPhotoIDs
                var fr = slides[slideIdx].pipThumbnailFramings
                let insertAt = max(0, min(slides[slideIdx].pipVisibleCount, imgs.count))
                while fr.count < insertAt { fr.append(nil) }
                fr.insert(nil, at: insertAt)
                imgs.insert(loaded, at: insertAt)
                ids2.insert(photo.id, at: insertAt)
                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIdx].pipImages = imgs
                    slides[slideIdx].pipPhotoIDs = ids2
                    slides[slideIdx].pipThumbnailFramings = fr
                    slides[slideIdx].pipVisibleCount = min(3, slides[slideIdx].pipVisibleCount + 1)
                }
                invalidatePIPBackgroundRemovalForMutation(at: slideIdx)
            }
        }
    }

    /// Copies font design, color, and size from the current slide to every slide (all kinds),
    /// for primary and secondary separately. Does not change dragged positions.
    private func applyTypographyToAllSlides() {
        // Use editorMutationSlideIndex (not currentIndex) — scrollPageID can lead currentIndex
        // by a frame after paging, so currentIndex may point to the previous slide.
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx) else { return }
        pushUndoSnapshot()
        let refPrimary = slides[idx].textStyle.primary
        let refSecondary = slides[idx].textStyle.secondary
        var updatedSlides = slides
        for i in updatedSlides.indices {
            updatedSlides[i].textStyle.primary.mergeTypography(from: refPrimary)
            updatedSlides[i].textStyle.secondary.mergeTypography(from: refSecondary)
        }
        slides = updatedSlides
    }

    /// Copies primary/secondary text block offsets from the current photo slide to every
    /// `placeStop` slide. No-op if the current slide is not a photo slide.
    private func applyPhotoLayoutToAllPlaceStops() {
        // Use editorMutationSlideIndex (not currentIndex) — scrollPageID can lead currentIndex
        // by a frame after paging, so currentIndex may point to the previous slide.
        let idx = editorMutationSlideIndex
        guard slides.indices.contains(idx), slides[idx].kind == .placeStop else { return }
        pushUndoSnapshot()
        let refPrimary = slides[idx].textStyle.primary
        let refSecondary = slides[idx].textStyle.secondary
        var updatedSlides = slides
        for i in updatedSlides.indices where updatedSlides[i].kind == .placeStop {
            updatedSlides[i].textStyle.primary.mergeLayout(from: refPrimary)
            updatedSlides[i].textStyle.secondary.mergeLayout(from: refSecondary)
        }
        slides = updatedSlides
    }

    private func flashAppliedConfirmation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { didApplyToAll = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.25)) { didApplyToAll = false }
        }
    }

    // MARK: Body

    @ViewBuilder
    private func slideEditorGeometryContent(outerSize: CGSize) -> some View {
                // Stable slide slot height. Derived from the outer width and aspect
                // ratio, then capped to fit the outer height minus a reserve for the
                // chevron nav row and bottom chrome (`slotSizingBottomReserve`).
                let outerW = outerSize.width
                let outerH = outerSize.height
                let slideContentW = max(220, outerW - 48)
                let idealSlotH = slideContentW / editorPreviewAspectRatio
                let navRowReserve: CGFloat = 72
                // The bottom `safeAreaInset` reserves pts for the editing chrome.
                // The outer geometry still reports the full container height (SwiftUI's
                // GeometryReader is not affected by the inset), so we must
                // subtract the reserve here ourselves. Without this, a 9:16
                // Story/Reel slide sizes against `outerH - 72` and ends up taller
                // than the VStack's usable area — the slide pushes the chevron
                // row and toolbar straight off the bottom of the screen.
                //
                // Style drop-ups use `bottomChromeExpanded` in this reserve so `slotH`
                // stays constant when toggling Color / Font / Size panels (toolbar tap,
                // not slide gesture). Spacers absorb the difference vs collapsed chrome.
                let maxSlotH = max(260,
                                    outerH - navRowReserve - slotSizingBottomReserve)
                let slotH = min(idealSlotH, maxSlotH)

                VStack(spacing: 0) {
                    if slides.isEmpty {
                        ContentUnavailableView(
                            "No slides available",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Close and reopen editor after slides finish loading.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        // Top spacer mirrors the bottom one so the slide + chevron
                        // row read as a single unit centered in the available area
                        // (above the bottom toolbar inset). For 4:5 Post slides this
                        // creates symmetric breathing room top/bottom; for 9:16
                        // Story/Reel the slide already fills the available height,
                        // so the spacer collapses to zero.
                        Spacer(minLength: 0)

                        GeometryReader { slideGeo in
                            let slotW = slideGeo.size.width
                            ScrollView(.horizontal, showsIndicators: false) {
                                // HStack (not LazyHStack): .scrollPosition(id:) needs every
                                // page's size to be known up front when jumping to a non-zero
                                // initial index, otherwise SwiftUI estimates widths for
                                // unmaterialized pages and lands a few points off-center.
                                // Slide count is small (<= ~20), so eager layout is fine.
                                HStack(spacing: 0) {
                                    // Only paginate through visible slides so pages that
                                    // have been collapsed into a sibling's PIP cluster don't
                                    // reappear here. `.id(i)` keeps raw slide indices as page
                                    // IDs — `scrollPageID` and `currentIndex` stay indices
                                    // into `slides`, matching the rest of the editor's state.
                                    ForEach(visibleSlideIndices, id: \.self) { i in
                                        VStack(spacing: 0) {
                                            Spacer(minLength: 0)
                                            SlideEditPage(
                                                slide: $slides[i],
                                                aspectRatio: editorPreviewAspectRatio,
                                                layoutWidth: slotW,
                                                maxHeight: slotH,
                                                selectedBlock: selectedBlock,
                                                onSelectBlock: {
                                                    selectedBlock = $0
                                                    selectedSplitSlot = nil
                                                    // Switching to a non-PIP block clears photo selection
                                                    if $0 != .pipCluster { selectedPIPPhotoIndex = nil }
                                                },
                                                onDeselect: {
                                                    selectedBlock = nil
                                                    selectedPIPPhotoIndex = nil
                                                },
                                                recordUndoSnapshot: { pushUndoSnapshot() },
                                                locksHorizontalSlidePaging: $locksHorizontalSlidePaging,
                                                onRequestHeroSwap: { idx in
                                                    // Drop text/PIP selection and bottom chrome so the swap sheet
                                                    // is the only focus (case `nil` no longer forces the sheet closed).
                                                    selectedBlock = nil
                                                    selectedPIPPhotoIndex = nil
                                                    heroSwapSlideIndex = idx
                                                    showsHeroPhotoSwapSheet = true
                                                },
                                                onRequestPIPInsetReplace: { slideIdx, thumbIdx in
                                                    selectedBlock = .pipCluster
                                                    selectedPIPPhotoIndex = thumbIdx
                                                    pipInsetReplaceSession = PIPInsetReplaceSession(
                                                        slideIndex: slideIdx,
                                                        clusterThumbIndex: thumbIdx)
                                                },
                                                onRequestSplitBottomPick: { idx in
                                                    selectedBlock = nil
                                                    selectedPIPPhotoIndex = nil
                                                    guard slides.indices.contains(idx) else { return }
                                                    if isCarouselStudioMapKind(slides[idx].kind) {
                                                        // Visual lower half = map (`splitTopFraming`); do not open photo picker.
                                                        selectedSplitSlot = .top
                                                    } else {
                                                        selectedSplitSlot = .bottom
                                                        presentSplitBottomPicker(for: idx)
                                                    }
                                                },
                                                onRequestSplitTopSelect: { idx in
                                                    selectedBlock = nil
                                                    selectedPIPPhotoIndex = nil
                                                    guard slides.indices.contains(idx) else { return }
                                                    if isCarouselStudioMapKind(slides[idx].kind) {
                                                        // Visual upper half = photo (`splitBottomFraming`).
                                                        selectedSplitSlot = .bottom
                                                    } else {
                                                        selectedSplitSlot = .top
                                                    }
                                                },
                                                selectedSplitSlot: selectedSplitSlot,
                                                onRequestStudioCoverPhotoPick: onRequestStudioCoverPhotoPick,
                                                onRequestInlineTextEdit: { presentInlineTextEditor() },
                                                slidePageIndex: i,
                                                showPoweredByBloggoMapWatermark:
                                                    indexOfFirstCarouselStudioMapSlide(in: slides) == i,
                                                pipBackgroundRemovalLoadingSlots: pipBackgroundRemovalSlideIndex == i
                                                    ? pipBackgroundRemovalLoadingSlots
                                                    : [],
                                                selectedPIPPhotoIndex: selectedPIPPhotoIndex,
                                                onSelectPIPPhoto: { photoIdx in
                                                    raisePIPUngroupedThumbToFront(
                                                        slideIndex: i,
                                                        thumbIndex: photoIdx
                                                    )
                                                    selectedBlock = .pipCluster
                                                    selectedPIPPhotoIndex = photoIdx
                                                    selectedSplitSlot = nil
                                                }
                                            )
                                            Spacer(minLength: 0)
                                        }
                                        .frame(width: slotW, height: slotH)
                                        // Recreate page-local drag geometry state on ratio changes.
                                        .id("\(i)-\(editorPreviewAspectLabel)")
                                        .contentTransition(.identity)
                                        .onLongPressGesture(minimumDuration: 0.5) {
                                            guard i == editorPagerFocusedSlideIndex, canExcludeCurrentSlide else { return }
                                            performExcludeFromStudio()
                                        }
                                    }
                                }
                                // PIP collapses siblings → `visibleSlideIndices` changes. Suppress
                                // implicit insert/remove animations on the page stack (they fight
                                // `scrollPosition` and read as a strobe). Chevrons still use explicit
                                // `withAnimation` when the user taps them.
                                .animation(nil, value: visibleSlideIndicesTag)
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.paging)
                            .scrollPosition(id: $scrollPageID, anchor: .center)
                            .scrollDisabled(locksHorizontalSlidePaging)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { _ in
                                        // Clear a stuck paging lock — can happen with 50+ slides
                                        // when the drag-end event is dropped under load.
                                        if locksHorizontalSlidePaging {
                                            locksHorizontalSlidePaging = false
                                        }
                                        guard !didClearSelectionForPagerDrag else { return }
                                        didClearSelectionForPagerDrag = true
                                        selectedBlock = nil
                                        selectedPIPPhotoIndex = nil
                                        pipInsetReplaceSession = nil
                                        selectedSplitSlot = nil
                                        activeStyleCategory = nil
                                        activePIPCategory = nil
                                    }
                                    .onEnded { _ in
                                        didClearSelectionForPagerDrag = false
                                    }
                            )
                            // Reassert the current page whenever the slot width changes
                            // (sheet-present animation, rotation, toolbar settling). Without
                            // this, the initial `scrollPosition` can land while slotW == 0
                            // and the slide ends up slightly off-center.
                            .onChange(of: slotW) { _, newWidth in
                                guard newWidth > 0 else { return }
                                if !didPerformInitialScroll {
                                    // First real width: force a re-scroll to `initialIndex`.
                                    // The ScrollView may have already written `scrollPageID = 0`
                                    // back through the binding (and thus set `currentIndex = 0`)
                                    // during the 0→real width transition, so we restore from
                                    // `initialIndex` and null the ID first to guarantee the
                                    // `scrollPosition(id:)` modifier performs a fresh scroll.
                                    currentIndex = initialIndex
                                    scrollPageID = nil
                                    DispatchQueue.main.async {
                                        scrollPageID = initialIndex
                                        didPerformInitialScroll = true
                                    }
                                } else if hasValidCurrentIndex {
                                    scrollPageID = currentIndex
                                }
                            }
                        }
                        .frame(height: slotH)
                        .animation(.easeInOut(duration: 0.22), value: slotSizingBottomReserve)
                        .animation(.easeInOut(duration: 0.22), value: editorPreviewAspectRatio)

                        // Slide navigation sits directly beneath the slide (not
                        // pushed all the way to the bottom of the sheet). The
                        // `Spacer` below absorbs any vertical change from the
                        // bottom-inset chrome so the slide + chevrons stay pinned
                        // in place when the user taps a block.
                        // Chevrons walk the visible-slide list, not raw `slides.indices`,
                        // so collapsed PIP siblings are skipped over exactly the way the
                        // swipe gesture skips them.
                        let visibleIndices = visibleSlideIndices
                        let visiblePos = currentVisiblePosition
                        let canGoPrev = (visiblePos ?? 0) > 0
                        let canGoNext = visiblePos.map { $0 < visibleIndices.count - 1 } ?? false
                        /// 9:16 preview is tall; hide prev/next under the slide — paging stays swipe-based.
                        let showSlideNavChevrons =
                            abs(editorPreviewAspectRatio - Self.studioPreviewRatio916) >= 0.001
                        // Under the slide: aspect / overview use the same horizontal inset as
                        // `SlideEditPage`’s rendered slide width (`min(max(220, layoutWidth - 48),
                        // maxHeight * aspectRatio)`), so their edges line up with the photo card.
                        GeometryReader { navGeo in
                            let navW = max(navGeo.size.width, 1)
                            let editorSlideRenderW = min(
                                max(220, navW - 48),
                                slotH * editorPreviewAspectRatio
                            )
                            let photoSideInset = max(0, (navW - editorSlideRenderW) * 0.5)

                            ZStack {
                                HStack(alignment: .center, spacing: 0) {
                                    Button(action: toggleEditorPreviewAspect) {
                                        Text(editorPreviewAspectLabel)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white.opacity(0.92))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Preview \(editorPreviewAspectLabel). Tap to switch between 4:5 and 9:16.")
                                    .padding(.leading, photoSideInset)

                                    Spacer(minLength: 0)

                                    if let onOpenPicker = onOpenPhotoGroupPicker {
                                        let count = visibleSelectedSlideCount
                                        let isOver = count > 34
                                        let cautionTint = Color(red: 1.0, green: 0.72, blue: 0.06)
                                        Button {
                                            onOpenPicker()
                                        } label: {
                                            // `rectangle.3.group` is a newer symbol and can render empty on older OS;
                                            // `square.grid.2x2` is widely available and still reads as “grid overview.”
                                            Image(systemName: isOver ? "exclamationmark.triangle.fill" : "square.grid.2x2")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(isOver ? cautionTint : .white)
                                                .frame(width: 36, height: 36)
                                                .background(isOver ? cautionTint.opacity(0.22) : Color.white.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                        .accessibilityLabel("Slide overview, \(count) slide\(count == 1 ? "" : "s") selected for export")
                                        .padding(.trailing, photoSideInset)
                                    }
                                }

                                HStack(spacing: 16) {
                                    if showSlideNavChevrons {
                                        Button {
                                            guard let pos = visiblePos, pos > 0 else { return }
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                currentIndex = visibleIndices[pos - 1]
                                                scrollPageID = currentIndex
                                            }
                                        } label: {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(canGoPrev ? .white : .white.opacity(0.2))
                                                .frame(width: 36, height: 36)
                                                .background(Color.white.opacity(canGoPrev ? 0.12 : 0.05))
                                                .clipShape(Circle())
                                        }
                                        .disabled(!canGoPrev)
                                    }

                                    Text("\((visiblePos ?? 0) + 1) / \(max(visibleIndices.count, 1))")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.55))
                                        .frame(minWidth: 52)

                                    if showSlideNavChevrons {
                                        Button {
                                            guard let pos = visiblePos, pos < visibleIndices.count - 1 else { return }
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                currentIndex = visibleIndices[pos + 1]
                                                scrollPageID = currentIndex
                                            }
                                        } label: {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(canGoNext ? .white : .white.opacity(0.2))
                                                .frame(width: 36, height: 36)
                                                .background(Color.white.opacity(canGoNext ? 0.12 : 0.05))
                                                .clipShape(Circle())
                                        }
                                        .disabled(!canGoNext)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 44)
                        .padding(.top, 8)

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Tapping anywhere outside a text block dismisses the editing menu.
                // The inner `DraggableTextBlock` uses `highPriorityGesture` and `SlideEditPage`
                // has its own `.onTapGesture` — both consume taps before this outer handler,
                // so this only fires for "empty" areas (margins, chevron-row gaps, backdrop).
                // The bottom editing toolbar lives in the `safeAreaInset` below, so it is
                // outside this gesture's scope and remains fully interactive.
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedBlock != nil { selectedBlock = nil }
                    if selectedSplitSlot != nil { selectedSplitSlot = nil }
                    if showsTextEditLine {
                        showsTextEditLine = false
                        inlineTextFocusField = nil
                    }
                }
                .opacity(showsTextEditLine ? 0.1 : 1.0)
                .animation(.easeInOut(duration: 0.22), value: showsTextEditLine)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !slides.isEmpty {
                        // Bottom chrome height is dynamic:
                        //   • Hint + collapsed toolbar use `bottomChromeCollapsed`
                        //     (~116pt) — same height so transitioning between
                        //     them doesn't shift the slide during the tap-to-
                        //     select drag gesture (see `bottomChromeCollapsed`).
                        //   • Text style drop-ups and PIP category panels use
                        //     `bottomChromeExpanded` (~176pt).
                        //
                        // Painting differs by state:
                        //   • Hint: no backdrop, so the dark-blue main
                        //     background shows through — avoids the "tall gray
                        //     slab" the fixed reserve used to produce.
                        //   • Toolbar: gray backdrop that extends into the
                        //     bottom safe area so chrome meets the screen edge
                        //     without a dark-blue gap above the home indicator.
                        //
                        // Keyboard compensation: `fullScreenCover` + `GeometryReader`
                        // prevents the keyboard safe-area from propagating to this
                        // `safeAreaInset`, so the keyboard overlays the toolbar.
                        // A transparent spacer of `keyboardHeight` below the ZStack
                        // pushes the toolbar above the keyboard without changing its
                        // visual appearance.
                        VStack(spacing: 0) {
                            modeSelectRow
                            splitToolsRow

                            ZStack(alignment: .bottom) {
                                if selectedBlock != nil {
                                    Color(white: 0.08)
                                        .ignoresSafeArea(edges: .bottom)
                                        .transition(.opacity)
                                }

                                if isPIPClusterSelected {
                                    pipClusterToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else if selectedBlock == nil {
                                    emptySelectionHint
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity)
                                } else {
                                    textFormattingToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .frame(height: currentChromeHeight)
                            .animation(.easeInOut(duration: 0.22), value: selectedBlock)
                            .animation(.spring(response: 0.32, dampingFraction: 0.82),
                                       value: activeStyleCategory)
                            .animation(.spring(response: 0.32, dampingFraction: 0.82),
                                       value: activePIPCategory)
                            .animation(.spring(response: 0.32, dampingFraction: 0.82),
                                       value: showsTextEditLine)

                            Color.clear
                                .frame(height: showsTextEditLine ? 0 : keyboardHeight)
                        }
                        .opacity(showsTextEditLine ? 0 : 1)
                        .allowsHitTesting(!showsTextEditLine)
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboardHeight)
                    }
                }
    }

    @ViewBuilder
    private var inlineTextEditSheet: some View {
        SlideBlockTextEditView(
            primarySectionTitle: inlineTextPrimarySectionTitle,
            primarySectionSubtitle: inlineTextPrimarySectionSubtitle,
            secondarySectionTitle: inlineTextSecondarySectionTitle,
            secondarySectionSubtitle: inlineTextSecondarySectionSubtitle,
            textDraft: $inlineTextDraft,
            captionDraft: $inlineCaptionDraft,
            onCancel: cancelInlineTextEdit,
            onSave: commitInlineTextEdit
        )
    }

    @ViewBuilder
    private var excludeConfirmOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showExcludeConfirmOverlay = false }
                }
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    let k = slides.indices.contains(currentIndex) ? slides[currentIndex].kind : nil
                    let isDayOverviewMap = k == .mapRoute
                    let isAnyMapSlide = k.map { isCarouselStudioMapKind($0) } ?? false
                    Text(isAnyMapSlide ? "Remove map slide?" : "Remove this slide?")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text(isDayOverviewMap
                         ? "The day map will be excluded from the carousel."
                         : (isAnyMapSlide)
                         ? "This focused place map will be excluded from the carousel."
                         : "This photo slide will be excluded from the carousel.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                Toggle(isOn: $skipExcludeConfirm) {
                    Text("Don't ask again")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .tint(CarouselStudioChrome.accent)
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showExcludeConfirmOverlay = false }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button {
                        let idx = currentIndex
                        withAnimation(.easeOut(duration: 0.2)) { showExcludeConfirmOverlay = false }
                        commitExclude(at: idx)
                    } label: {
                        Text("Remove")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 1.0, green: 0.27, blue: 0.23))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(24)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .transition(.opacity)
    }



    private let exportHubGridColumns = [
        GridItem(.flexible(minimum: 120), spacing: 10),
        GridItem(.flexible(minimum: 120), spacing: 10)
    ]

    private func slidePickLabel(for slide: CarouselSlide) -> String {
        func firstLine(_ raw: String) -> String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            for lineSub in t.split(whereSeparator: \.isNewline) {
                let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { return line }
            }
            return ""
        }
        switch slide.kind {
        case .cover: return "Cover"
        case .mapRoute:
            let day = slide.dayInfoLine1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let d = slide.mapShortDateLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if day.isEmpty { return d.isEmpty ? "Map" : d }
            return d.isEmpty ? day : "\(day) - \(d)"
        case .placeIntroMap:
            let raw = slide.placeStop?.placeTitle ?? slide.dayInfoLine1 ?? ""
            let t = firstLine(raw)
            return t.isEmpty ? "Place map" : t
        case .placeStop:
            let raw = slide.placeStop?.placeTitle ?? ""
            let t = firstLine(raw)
            return t.isEmpty ? "Place" : t
        }
    }

    @ViewBuilder
    private var exportHubSharePickContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                let mapsOmitted = sharePickEffectivelyOmitsMapsFromShare
                if !sharePickMapSlideIndices.isEmpty {
                    Button {
                        let maps = Set(sharePickMapSlideIndices)
                        if mapsOmitted {
                            shareSlidePickSelection.formUnion(maps)
                        } else {
                            shareSlidePickSelection.subtract(maps)
                        }
                    } label: {
                        Label(
                            mapsOmitted ? "Include Maps" : "Remove Maps",
                            systemImage: mapsOmitted ? "map.fill" : "map"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mapsOmitted ? Color.primary : .white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(mapsOmitted
                                      ? Color(uiColor: .secondarySystemFill)
                                      : CarouselStudioChrome.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button(action: toggleShareSlidePickSelectAll) {
                    Label(
                        sharePickSelectionMatchesAll ? "Deselect All" : "Select All",
                        systemImage: sharePickSelectionMatchesAll ? "circle" : "checkmark.circle.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(sharePickSelectionMatchesAll ? Color.primary : .white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(sharePickSelectionMatchesAll
                                  ? Color(uiColor: .secondarySystemFill)
                                  : CarouselStudioChrome.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: exportHubGridColumns, spacing: 12) {
                    ForEach(studioDownloadCandidateIndices, id: \.self) { idx in
                        let selected = shareSlidePickSelection.contains(idx)
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geo in
                                let w = max(80, geo.size.width)
                                CarouselStudioDownloadStylePickCard(
                                    slide: slides[idx],
                                    width: w,
                                    aspectRatio: aspectRatio,
                                    isInCarousel: selected,
                                    mode: .singleAction { toggleSharePick(for: idx) }
                                )
                            }
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            Text(slidePickLabel(for: slides[idx]))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }

            VStack(spacing: 8) {
                let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
                let overLimit = pickedShareExportCount > lim
                if overLimit {
                    Label(
                        "Select \(lim) or fewer slides — deselect some or toggle off maps above.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    let order = orderedPickedShareIndices()
                    guard !order.isEmpty, order.count <= CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage else { return }
                    deferredExportHubWork = .sharePickedIndices(order, omitMapsFromShare: sharePickEffectivelyOmitsMapsFromShare)
                    showCarouselStudioExportHub = false
                } label: {
                    let label = pickedShareExportCount > 0 ? "Share (\(pickedShareExportCount))" : "Share"
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    orderedPickedShareIndices().isEmpty
                        || overLimit
                        || exportActions.exportActionsDisabled()
                )
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showCarouselStudioExportHub = false }
            }
            ToolbarItem(placement: .principal) {
                Text("Share").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var exportHubDownloadPickContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: toggleDownloadSlidePickSelectAll) {
                    Label(
                        downloadPickSelectionMatchesAll ? "Deselect All" : "Select All",
                        systemImage: downloadPickSelectionMatchesAll ? "circle" : "checkmark.circle.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(downloadPickSelectionMatchesAll ? Color.primary : .white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(downloadPickSelectionMatchesAll
                                  ? Color(uiColor: .secondarySystemFill)
                                  : CarouselStudioChrome.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: exportHubGridColumns, spacing: 12) {
                    ForEach(studioDownloadCandidateIndices, id: \.self) { idx in
                        let selected = downloadSlidePickSelection.contains(idx)
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geo in
                                let w = max(80, geo.size.width)
                                CarouselStudioDownloadStylePickCard(
                                    slide: slides[idx],
                                    width: w,
                                    aspectRatio: aspectRatio,
                                    isInCarousel: selected,
                                    mode: .singleAction { toggleDownloadPick(for: idx) }
                                )
                            }
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            Text(slidePickLabel(for: slides[idx]))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }

            VStack(spacing: 10) {
                Button {
                    let order = orderedPickedDownloadIndices()
                    guard !order.isEmpty else { return }
                    let limit = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
                    if downloadOutputMode == .photo, order.count > limit {
                        pendingBulkPhotosDownloadOrder = order
                        showBulkPhotosDownloadConfirmation = true
                    } else if downloadOutputMode == .pdf, order.count > limit {
                        pendingBulkPdfDownloadOrder = order
                        showBulkPdfDownloadConfirmation = true
                    } else {
                        deferredExportHubWork = downloadOutputMode == .photo
                            ? .savePhotosIndices(order) : .exportPDFIndices(order)
                        showCarouselStudioExportHub = false
                    }
                } label: {
                    let n = orderedPickedDownloadIndices().count
                    Text(n > 0 ? "Done (\(n))" : "Done")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(orderedPickedDownloadIndices().isEmpty || exportActions.exportActionsDisabled())
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showCarouselStudioExportHub = false }
            }
            ToolbarItem(placement: .principal) {
                Text("Download").font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Save as") {
                        ForEach(DownloadOutputMode.allCases) { mode in
                            Button { downloadOutputMode = mode } label: {
                                HStack {
                                    Label(mode.label, systemImage: mode.systemImage)
                                    Spacer(minLength: 8)
                                    if downloadOutputMode == mode {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: downloadOutputMode.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Save as")
                .accessibilityValue(downloadOutputMode.label)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var carouselStudioExportHubSheetContent: some View {
        NavigationStack {
            Group {
                switch carouselStudioExportHubPhase {
                case .pickShareSlides: exportHubSharePickContent
                case .pickDownloadSlides: exportHubDownloadPickContent
                }
            }
        }
        .onChange(of: studioDownloadCandidateIndices.count) { _, _ in
            guard carouselStudioExportHubPhase == .pickShareSlides else { return }
            selectAllSlidesForSharePick()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "Save in multiple batches?",
            isPresented: $showBulkPhotosDownloadConfirmation,
            titleVisibility: .visible
        ) {
            let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
            let n = pendingBulkPhotosDownloadOrder.count
            let batches = max(1, Int(ceil(Double(n) / Double(lim))))
            Button("Save \(n) slides (\(batches) batches, up to \(lim) each)") {
                showBulkPhotosDownloadConfirmation = false
                let order = pendingBulkPhotosDownloadOrder
                pendingBulkPhotosDownloadOrder = []
                deferredExportHubWork = .savePhotosIndices(order)
                showCarouselStudioExportHub = false
            }
            Button("Cancel", role: .cancel) {
                pendingBulkPhotosDownloadOrder = []
            }
        } message: {
            let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
            Text(
                "To keep the app stable, Photos saves run in batches of up to \(lim) slides. "
                + "Progress shows until all batches finish."
            )
        }
        .confirmationDialog(
            "Export multiple PDFs?",
            isPresented: $showBulkPdfDownloadConfirmation,
            titleVisibility: .visible
        ) {
            let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
            let n = pendingBulkPdfDownloadOrder.count
            let batches = max(1, Int(ceil(Double(n) / Double(lim))))
            Button("Create \(batches) PDF file\(batches == 1 ? "" : "s") (≤\(lim) pages each)") {
                showBulkPdfDownloadConfirmation = false
                let order = pendingBulkPdfDownloadOrder
                pendingBulkPdfDownloadOrder = []
                deferredExportHubWork = .exportPDFIndices(order)
                showCarouselStudioExportHub = false
            }
            Button("Cancel", role: .cancel) {
                pendingBulkPdfDownloadOrder = []
            }
        } message: {
            let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
            Text(
                "Each PDF has at most \(lim) slides. You'll get iOS Share for each PDF — tap Save to Files to put them on your device. After one file finishes, Bloggo offers the rest."
            )
        }
    }

    @ViewBuilder
    private func carouselStudioShareAndExportMenu(useExportHubGlyph: Bool) -> some View {
        let exportDisabled = exportActions.exportActionsDisabled()
        let limit = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        Menu {
            Button {
                if studioDownloadCandidateIndices.count <= limit {
                    Task { await exportActions.share() }
                } else {
                    selectAllSlidesForSharePick()
                    carouselStudioExportHubPhase = .pickShareSlides
                    showCarouselStudioExportHub = true
                }
            } label: {
                Label("Share to social apps…", systemImage: "square.and.arrow.up")
            }
            .disabled(exportDisabled)
            Button {
                selectAllSlidesForDownloadPick()
                downloadOutputMode = .photo
                carouselStudioExportHubPhase = .pickDownloadSlides
                showCarouselStudioExportHub = true
            } label: {
                Label("Download…", systemImage: "arrow.down.to.line")
            }
            .disabled(exportDisabled)
        } label: {
            if useExportHubGlyph {
                Image("CarouselStudioExportHub")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("Share or download")
    }

    @ToolbarContentBuilder
    private var editorToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                if let onDismissEditor {
                    onDismissEditor()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Close")

            let canUndo = !undoStack.isEmpty
            Button {
                undoLastChange()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(canUndo ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.18), value: canUndo)
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if currentPlaceSlide != nil {
                Button {
                    presentCurrentSlideLayoutSheet()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Layout selection")
            }

            carouselStudioShareAndExportMenu(useExportHubGlyph: false)
        }
    }

    private var editorNavigationContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CarouselStudioNavigationBarHairlineDisabler()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                GeometryReader { outerGeo in
                    slideEditorGeometryContent(outerSize: outerGeo.size)
                }
                if showExcludeConfirmOverlay {
                    excludeConfirmOverlay
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showExcludeConfirmOverlay)
            .background(Color(red: 5/255, green: 10/255, blue: 48/255).ignoresSafeArea())
            .navigationTitle("Carousel Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(onDismissEditor != nil ? .hidden : .automatic, for: .navigationBar)
            .toolbarBackground(Color(red: 5/255, green: 10/255, blue: 48/255), for: .navigationBar)
            .toolbarBackground(onDismissEditor != nil ? .hidden : .visible, for: .navigationBar)
            .toolbar { editorToolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                if onDismissEditor != nil {
                    embeddedEditorHeader
                }
            }
            .onAppear {
                guard !didOfferFirstRunPlaceLayout else { return }
                didOfferFirstRunPlaceLayout = true
                if !hasSeenPlaceLayoutPicker,
                   slides.contains(where: { $0.kind == .placeStop }) {
                    if let idx = slides.firstIndex(where: { $0.kind == .placeStop }) {
                        selectedPlaceZoneLayoutInSheet = slides[idx].placeZoneLayout
                    }
                    placeZoneLayoutAppliesToAllPlaceSlides = true
                    // Defer so the navigation stack finishes presenting; otherwise the sheet
                    // can appear then tear down in the same transition as layout settles.
                    // One run-loop (DispatchQueue.main.async) is not enough when the enclosing
                    // sheet is still animating — use a short sleep instead.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        showPlaceZoneLayoutSheet = true
                    }
                }
            }
            .sheet(isPresented: $showPlaceZoneLayoutSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        Picker("Apply to", selection: $placeZoneLayoutAppliesToAllPlaceSlides) {
                            Text("This slide").tag(false)
                            Text("All slides").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                        ScrollView {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)
                                ],
                                spacing: 16
                            ) {
                                let activeMode = currentPlaceSlide?.layout ?? .single
                                ForEach(CarouselPlaceZoneLayout.bulkZonePresets(for: activeMode)) { layout in
                                    Button {
                                        selectedPlaceZoneLayoutInSheet = layout
                                    } label: {
                                        PlaceZoneLayoutDiagramThumb(
                                            zone: layout,
                                            slidePhotoLayout: activeMode,
                                            isSelected: selectedPlaceZoneLayoutInSheet == layout,
                                            width: 124,
                                            height: 154
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                        }
                    }
                    .navigationTitle("Text & photo layout")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                hasSeenPlaceLayoutPicker = true
                                showPlaceZoneLayoutSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Apply") {
                                commitPlaceZoneLayoutFromSheet(selectedPlaceZoneLayoutInSheet)
                            }
                            .fontWeight(.semibold)
                            .tint(.blue)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCarouselWidePlaceZoneSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(CarouselSlideLayout.allCases) { slidePhotoLayout in
                                let rowCount = placeSlideCount(for: slidePhotoLayout)
                                if rowCount > 0 {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Image(systemName: layoutIcon(slidePhotoLayout))
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(CarouselStudioChrome.accent)
                                            Text(carouselPhotoLayoutSectionTitle(slidePhotoLayout))
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.horizontal, 4)

                                        LazyVGrid(
                                            columns: [
                                                GridItem(.flexible(), spacing: 14),
                                                GridItem(.flexible(), spacing: 14)
                                            ],
                                            spacing: 14
                                        ) {
                                            ForEach(CarouselPlaceZoneLayout.bulkZonePresets(for: slidePhotoLayout)) { zone in
                                                Button {
                                                    applyCarouselWidePlaceZone(zone, slidePhotoLayout: slidePhotoLayout)
                                                } label: {
                                                    PlaceZoneLayoutDiagramThumb(
                                                        zone: zone,
                                                        slidePhotoLayout: slidePhotoLayout,
                                                        isSelected: false,
                                                        width: 118,
                                                        height: 146
                                                    )
                                                    .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .navigationTitle("Carousel text layout")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCarouselWidePlaceZoneSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: scrollPageID) { _, newID in
                guard let newID else { return }
                // Ignore ScrollView write-backs until the initial scroll has been
                // asserted. During the 0→real width transition, SwiftUI can write
                // `scrollPageID = 0` back through the binding (the default content
                // offset now maps to page 0 once pages get real widths), which would
                // otherwise yank `currentIndex` away from `initialIndex`.
                guard didPerformInitialScroll else { return }
                // When PIP collapses sibling slides out of the pager, `scrollPosition` can
                // still emit an id for a page that no longer exists in `ForEach` — ignore
                // those writes and snap the binding back to the editor's slide.
                guard visibleSlideIndices.contains(newID) else {
                    DispatchQueue.main.async {
                        if scrollPageID != currentIndex {
                            scrollPageID = currentIndex
                        }
                    }
                    return
                }
                guard newID != currentIndex else { return }
                currentIndex = newID
                // Hero swap is tied to a slide index; dismiss if the user pages away.
                showsHeroPhotoSwapSheet = false
                heroSwapSlideIndex = nil
                pipInsetReplaceSession = nil
                pipMultiRepositionSession = nil
                showsSplitBottomPhotoPicker = false
                splitBottomPickSlideIndex = nil
                selectedBlock = nil
                selectedSplitSlot = nil
                activeStyleCategory = nil
                activePIPCategory = nil
                #if DEBUG
                if slides.indices.contains(newID), slides[newID].kind == .cover {
                    print("[CarouselStudio] scrollPageID → cover slide at index \(newID)")
                }
                #endif
            }
            .onChange(of: visibleSlideIndicesTag) { _, _ in
                guard didPerformInitialScroll, !slides.isEmpty else { return }
                // Pager content identity changed (e.g. enabling PIP removed earlier siblings).
                // Keep `currentIndex` aligned with what `scrollPosition` still claims, then
                // re-scroll so the centered page matches that id (avoids wrong hero after PIP).
                if let sid = scrollPageID, visibleSlideIndices.contains(sid) {
                    currentIndex = sid
                }
                guard visibleSlideIndices.contains(currentIndex) else {
                    clampCurrentIndexIfNeeded()
                    return
                }
                // Same-frame reassert: async deferred the scroll correction and allowed
                // wrong centered pages. `setPlaceStopLayout` also reasserts; a second pass
                // here covers undo / exclude when the visible list changes without PIP toggle.
                reassertEditorPagerToSlide(at: currentIndex)
            }
            .onChange(of: slides.count) { _, _ in
                clampCurrentIndexIfNeeded()
            }
            .onChange(of: externalJumpToSlideIndex) { _, newVal in
                guard let raw = newVal else { return }
                externalJumpToSlideIndex = nil
                DispatchQueue.main.async {
                    guard let idx = indexVisibleInEditorOrPreviewStrip(slides: slides, rawIndex: raw) else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentIndex = idx
                        scrollPageID = idx
                    }
                    showsHeroPhotoSwapSheet = false
                    heroSwapSlideIndex = nil
                    pipInsetReplaceSession = nil
                    pipMultiRepositionSession = nil
                    showsSplitBottomPhotoPicker = false
                    splitBottomPickSlideIndex = nil
                    selectedBlock = nil
                    selectedSplitSlot = nil
                    activeStyleCategory = nil
                    activePIPCategory = nil
                }
            }
        }
    }

    private var editorBodyBase: some View {
        editorNavigationContent
            // Bar-button labels still pick up global/accent tint on some OS builds unless
            // the navigation hierarchy sets an explicit toolbar tint.
            .toolbar(onDismissEditor != nil ? .hidden : .visible, for: .navigationBar)
            .tint(.white)
            .preferredColorScheme(.dark)
            // Text editing is presented in a fullScreenCover (isolated UIViewController).
            // This prevents any keyboard-driven safe-area inset from propagating back into
            // the slide editor and causing layout shifts / view shrinkage.
            .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var exportProgressOverlay: some View {
        if exportInProgress {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.1)
                        .tint(.white)
                    Text("Preparing export…")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var editorBodyWithPrimarySheets: some View {
        editorBodyBase
            .onChange(of: showsTextEditLine) { _, isShowing in
#if DEBUG
                print("[CarouselStudio][TextEdit] showsTextEditLine -> \(isShowing)")
#endif
                // The text editor's keyboard still delivers `keyboardWillChangeFrame` to this
                // view while the fullScreenCover is up. If we accumulate that height here,
                // the bottom chrome spacer becomes non-zero the moment the cover dismisses
                // and the studio layout jumps.
                if isShowing {
                    ignoreChromeKeyboardNotifications = true
                    var txn = Transaction()
                    txn.disablesAnimations = true
                    withTransaction(txn) {
                        keyboardHeight = 0
                    }
                } else {
                    ignoreChromeKeyboardNotifications = false
                    var txn = Transaction()
                    txn.disablesAnimations = true
                    withTransaction(txn) {
                        keyboardHeight = 0
                    }
                }
            }
            // fullScreenCover presents a fully isolated UIViewController context so the
            // keyboard inside the text editor cannot propagate safe-area insets back into
            // the slide editor and cause layout shifts or view shrinkage.
            .fullScreenCover(isPresented: $showsTextEditLine, onDismiss: {
#if DEBUG
                print("[CarouselStudio][TextEdit] fullScreenCover onDismiss; committed=\(inlineTextEditCommitted)")
#endif
                if !inlineTextEditCommitted {
                    // Cancelled without saving — restore drafts from captured values.
                    inlineTextDraft = capturedBlockText
                    if showsInlineCaptionField {
                        let idx = textEditSlideIndexCapture
                        inlineCaptionDraft = slides.indices.contains(idx)
                            ? (slides[idx].photoCaption ?? slides[idx].caption ?? "")
                            : ""
                    }
                    inlineTextFocusField = nil
                }
                inlineTextEditCommitted = false
                textEditBlockCapture = nil
            }, content: {
                inlineTextEditSheet
            })
            .sheet(isPresented: $showCarouselStudioExportHub, onDismiss: {
                carouselStudioExportHubPhase = .pickDownloadSlides
                let work = deferredExportHubWork
                deferredExportHubWork = nil
                guard let work else { return }
                DispatchQueue.main.async {
                    switch work {
                    case .sharePickedIndices(let order, let omitMapsFromShare):
                        Task { await exportActions.shareAtIndices(order, omitMapsFromShare) }
                    case .savePhotosIndices(let order):
                        Task { await exportActions.saveToPhotosAtIndices(order) }
                    case .exportPDFIndices(let order):
                        Task { await exportActions.exportPDFAtIndices(order) }
                    }
                }
            }, content: {
                carouselStudioExportHubSheetContent
            })
            .overlay { exportProgressOverlay }
    }

    var body: some View {
        editorBodyWithSplitRepositionCover
    }

    private var editorBodyWithCommonLifecycle: some View {
        editorBodyWithPrimarySheets
            .onReceive(NotificationCenter.default.publisher(for: .carouselStudioEditorExportBanner)) { note in
                guard let title = note.userInfo?["title"] as? String,
                      let message = note.userInfo?["message"] as? String else { return }
                editorExportBannerAlertTitle = title
                editorExportBannerAlertMessage = message
                showEditorExportBannerAlert = true
            }
            .alert(editorExportBannerAlertTitle, isPresented: $showEditorExportBannerAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(editorExportBannerAlertMessage)
            }
            // `currentIndex` and `scrollPageID` are seeded in `init`, so the ScrollView lays
            // out on the correct page from the very first frame. We only need to reset the
            // per-session editor state here.
            .onAppear {
                selectedBlock = nil
                activeStyleCategory = nil
                activePIPCategory = nil
                pipClusterSizeSliderUndoPrimed = false
                undoStack = []
                showsTextEditLine = false
                exportCanvasAspectRatio.wrappedValue = editorPreviewAspectRatio
            }
            .onChange(of: selectedBlock) { _, newValue in
                #if DEBUG
                if slides.indices.contains(currentIndex), slides[currentIndex].kind == .cover {
                    print("[CarouselStudio] cover slide selectedBlock → \(String(describing: newValue))")
                }
                #endif
                // Switching selection (or deselecting entirely) collapses whichever
                // drop-up was open so the panel content always matches the block type.
                pipClusterSizeSliderUndoPrimed = false
                showsTextEditLine = false
                switch newValue {
                case nil:
                    activeStyleCategory = nil
                    activePIPCategory = nil
                    showsAddPhotoPicker = false
                    splitRepositionSession = nil
                    pipMultiRepositionSession = nil
                    pipInsetReplaceSession = nil
                case .pipCluster:
                    activeStyleCategory = nil
                    splitRepositionSession = nil
                case .primary, .secondary:
                    activePIPCategory = nil
                    showsAddPhotoPicker = false
                    showsHeroPhotoSwapSheet = false
                    heroSwapSlideIndex = nil
                    pipInsetReplaceSession = nil
                    showsSplitBottomPhotoPicker = false
                    splitBottomPickSlideIndex = nil
                    splitRepositionSession = nil
                    pipMultiRepositionSession = nil
                }
            }
            .onChange(of: activePIPCategory) { _, _ in
                pipClusterSizeSliderUndoPrimed = false
            }
            // Track keyboard height so the toolbar spacer can push content above the keyboard.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
                guard !ignoreChromeKeyboardNotifications else { return }
                guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let newHeight = max(0, UIScreen.main.bounds.height - frame.minY)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    keyboardHeight = newHeight
                }
            }
    }

    private var editorBodyWithPickers: some View {
        editorBodyWithCommonLifecycle
            .sheet(isPresented: $showsAddPhotoPicker) {
                if let placeStop = currentSlide?.placeStop {
                    AddPIPPhotoPickerSheet(
                        placeStop: placeStop,
                        availablePhotos: availableAddablePhotos,
                        onPick: { photo in
                            addPIPPhotoToCluster(photo)
                            showsAddPhotoPicker = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showsHeroPhotoSwapSheet) {
                if let idx = heroSwapSlideIndex,
                   slides.indices.contains(idx),
                   let stop = slides[idx].placeStop,
                   slides[idx].layout == .pip {
                    SwapHeroPhotoSheet(
                        placeStop: stop,
                        heroPhotoID: slides[idx].heroPhotoID,
                        photos: stop.photos.filter(\.isIncluded),
                        onPick: { photo in
                            swapHeroWithPlacePhoto(photo, slideIndex: idx)
                            heroSwapSlideIndex = nil
                            showsHeroPhotoSwapSheet = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: showsHeroPhotoSwapSheet) { _, open in
                if !open { heroSwapSlideIndex = nil }
            }
            .sheet(item: $pipInsetReplaceSession) { session in
                if slides.indices.contains(session.slideIndex),
                   let stop = slides[session.slideIndex].placeStop,
                   slides[session.slideIndex].layout == .pip {
                    let thumbIdx = session.clusterThumbIndex
                    let slideForPicker = slides[session.slideIndex]
                    ReplacePIPInsetPhotoSheet(
                        placeStop: stop,
                        eligiblePhotos: recapPhotosEligibleForPIPInsetReplace(
                            slide: slideForPicker,
                            thumbIndex: thumbIdx
                        ),
                        heroPhotoID: slides[session.slideIndex].heroPhotoID,
                        onPick: { photo in
                            replacePIPClusterInsetSlot(
                                with: photo,
                                slideIndex: session.slideIndex,
                                thumbIndex: thumbIdx)
                            pipInsetReplaceSession = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showsSplitBottomPhotoPicker) {
                if let idx = splitBottomPickSlideIndex,
                   slides.indices.contains(idx),
                   slides[idx].layout == .split {
                    SplitBottomPhotoPickerSheet(
                        selectedPhotoID: slides[idx].splitBottomPhotoID,
                        availablePhotos: availableSplitBottomPhotos(for: idx),
                        onPick: { photo in
                            setSplitBottomPhoto(photo, slideIndex: idx)
                            splitBottomPickSlideIndex = nil
                            showsSplitBottomPhotoPicker = false
                        },
                        onClear: {
                            clearSplitBottomPhoto(slideIndex: idx)
                            splitBottomPickSlideIndex = nil
                            showsSplitBottomPhotoPicker = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: showsSplitBottomPhotoPicker) { _, open in
                if !open { splitBottomPickSlideIndex = nil }
            }
    }

    private var editorBodyWithSplitRepositionCover: some View {
        editorBodyWithPickers
            .fullScreenCover(item: $splitRepositionSession) { session in
                SplitPhotoRepositionCover(
                    slides: $slides,
                    slideIndex: session.slideIndex,
                    startingSlot: session.initialSlot,
                    slideAspectRatio: editorPreviewAspectRatio,
                    onClose: { splitRepositionSession = nil },
                    onApply: { framing, slot in
                        pushUndoSnapshot()
                        guard slides.indices.contains(session.slideIndex) else { return }
                        switch slot {
                        case .top:
                            slides[session.slideIndex].splitTopFraming = framing
                        case .bottom:
                            slides[session.slideIndex].splitBottomFraming = framing
                        }
                    },
                    onRequestBottomPhotoPick: {
                        splitRepositionSession = nil
                        DispatchQueue.main.async {
                            presentSplitBottomPicker(for: session.slideIndex)
                        }
                    }
                )
            }
            .fullScreenCover(item: $pipMultiRepositionSession) { session in
                PIPPhotoRepositionCover(
                    slides: $slides,
                    slideIndex: session.slideIndex,
                    initialClusterIndex: session.initialClusterIndex,
                    onClose: { pipMultiRepositionSession = nil },
                    onApply: { framing, clusterIndex in
                        pushUndoSnapshot()
                        guard slides.indices.contains(session.slideIndex) else { return }
                        while slides[session.slideIndex].pipThumbnailFramings.count <= clusterIndex {
                            slides[session.slideIndex].pipThumbnailFramings.append(nil)
                        }
                        slides[session.slideIndex].pipThumbnailFramings[clusterIndex] = framing
                    }
                )
            }
    }

    @ViewBuilder
    private var embeddedEditorHeader: some View {
        let canUndo = !undoStack.isEmpty
        // Three-column bar: equal flexible leading/trailing regions so the title stays
        // visually centered and does not crowd long trailing labels (e.g. "Excluded (n)").
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onDismissEditor?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Button {
                    undoLastChange()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(canUndo ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .accessibilityLabel("Undo")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Carousel Studio")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
                .layoutPriority(1)

            HStack(spacing: 10) {
                if currentPlaceSlide != nil {
                    Button {
                        presentCurrentSlideLayoutSheet()
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Layout selection")
                }

                carouselStudioShareAndExportMenu(useExportHubGlyph: true)
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 5/255, green: 10/255, blue: 48/255))
    }

    // MARK: - Formatting toolbar

    /// Bottom hint shown before the user taps a text block. Once a block is
    /// selected, this is swapped for `textFormattingToolbar`. Rendered without
    /// a backdrop — the surrounding safe-area-inset region keeps its height
    /// reserved for layout stability, but letting the main dark-blue
    /// background show through avoids the "tall empty gray slab" look that a
    /// full-height painted backdrop produced in the hint state.
    private var emptySelectionHint: some View {
        VStack(spacing: 10) {
            Image(systemName: currentSlide?.kind == .cover ? "photo.on.rectangle.angled" : "hand.tap")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))

            VStack(spacing: 4) {
                if currentSlide?.kind == .cover {
                    Text("Tap the cover photo to change it")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text("Tap the title, then Edit text — or tap the title twice")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                } else {
                    Text("Tap a block to edit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text("Drag to reposition · Swipe to change slides")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var textFormattingToolbar: some View {
        VStack(spacing: 0) {
            // Slide-level action row currently keeps only block deletion.
            // "Apply to all" actions now live in the bottom category bar via the
            // dedicated first-tab Apply menu.
            // Hidden while the text edit sheet is up (bottom chrome is removed then anyway).
            if !showsTextEditLine {
            HStack(spacing: 12) {
                Button {
                    presentInlineTextEditor()
                } label: {
                    Label("Edit text", systemImage: "character.cursor.ibeam")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!selectedBlockSupportsInlineTextEdit)

                Spacer()

                Button {
                    deleteSelectedBlock()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.red.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.red.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(selectedBlock == nil)
                .opacity(selectedBlock != nil ? 1 : 0.4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))
            }

            if !showsTextEditLine {
                // Drop-up panel: horizontally-scrollable options for the active category.
                // Collapses when `activeStyleCategory == nil`.
                if let category = activeStyleCategory {
                    styleDropUpPanel(for: category)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity))
                }

                // Category tab bar — always visible when a block is selected.
                styleCategoryTabBar
            }
        }
        .background(Color(white: 0.08))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeStyleCategory)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showsTextEditLine)
    }

    // MARK: - Split photo action toolbar

    /// Bottom chrome shown when a split photo slot is selected. Provides Crop
    /// (reposition), Replace (swap photo), and Remove (clear slot) actions for
    /// the selected slot. Style matches `textFormattingToolbar`'s top action row.
    @ViewBuilder
    private var splitPhotoActionToolbar: some View {
        if let slot = selectedSplitSlot,
           let slide = currentSlide,
           slide.layout == .split {
            let isTop = slot == .top
            let isMapSplitTopReplace = isTop && isCarouselStudioMapKind(slide.kind)

            HStack(spacing: 12) {
                // Crop — opens the full-screen pinch/pan repositioner for the selected slot.
                Button {
                    let idx = editorPagerFocusedSlideIndex
                    guard slides.indices.contains(idx), slides[idx].layout == .split else { return }
                    pipMultiRepositionSession = nil
                    splitRepositionSession = SplitRepositionSession(slideIndex: idx, initialSlot: slot)
                } label: {
                    Label("Crop", systemImage: "crop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Replace — hero swap for top slot (place split); map top is the snapshot (crop only).
                Button {
                    let idx = editorPagerFocusedSlideIndex
                    if isTop {
                        selectedBlock = nil
                        selectedSplitSlot = nil
                        heroSwapSlideIndex = idx
                        showsHeroPhotoSwapSheet = true
                    } else {
                        presentSplitBottomPicker(for: idx)
                    }
                } label: {
                    Label("Replace", systemImage: "photo.badge.arrow.up.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isMapSplitTopReplace)
                .opacity(isMapSplitTopReplace ? 0.35 : 1)

                Spacer()

                // Remove — disabled (grayed out) for top slot; clears bottom slot.
                Button {
                    guard !isTop else { return }
                    clearSplitBottomPhoto(slideIndex: editorPagerFocusedSlideIndex)
                    selectedSplitSlot = nil
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(isTop ? Color.white.opacity(0.06) : Color.red.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                isTop ? Color.white.opacity(0.1) : Color.red.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                        .opacity(isTop ? 0.4 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isTop)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(white: 0.08).ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: - PIP cluster toolbar

    /// Bottom chrome shown when the multi-photo PIP cluster is selected. Mirrors
    /// the visual language of `textFormattingToolbar` (action row + drop-up +
    /// category tab bar) but with photo-specific actions and categories so the
    /// user doesn't see irrelevant typography controls.
    ///
    /// Top row: Reposition (inset thumbnails only), Swap photos (rotates the hero into
    /// the cluster). Cluster size is adjusted with **Remove** in the tab bar, not a
    /// second trash action here. Below: Border / Shape / Size / Background drop-up (when
    /// open) and the PIP category tab bar.
    @ViewBuilder
    private var pipClusterToolbar: some View {
        let isUngrouped = currentSlide?.pipIsUngrouped ?? false
        let selectedPhotoIdx = selectedPIPPhotoIndex
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    let idx = editorPagerFocusedSlideIndex
                    guard slides.indices.contains(idx), slides[idx].layout == .pip else { return }
                    splitRepositionSession = nil
                    pipMultiRepositionSession = PIPClusterRepositionSession(
                        slideIndex: idx,
                        initialClusterIndex: 0
                    )
                } label: {
                    Label("Crop", systemImage: "crop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .disabled(currentSlide?.pipImages.isEmpty ?? true)
                .opacity((currentSlide?.pipImages.isEmpty ?? true) ? 0.4 : 1.0)

                // When ungrouped with a photo tapped, show which photo is selected
                // so the user knows border/shape actions apply to just that photo.
                if isUngrouped, let photoIdx = selectedPhotoIdx {
                    Text("Photo \(photoIdx + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CarouselStudioChrome.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(CarouselStudioChrome.accent.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                Spacer(minLength: 8)

                // Swap promotes the first PIP thumbnail into the hero slot and
                // demotes the current hero into the cluster — a one-tap way to
                // change which cluster photo is "featured". Add/remove lives in
                // the scrollable category bar (`pipAddPhotosTabButton` /
                // `pipRemovePhotosTabButton`).
                Button {
                    swapPIPPhotos()
                } label: {
                    Label("Swap photos", systemImage: "arrow.2.squarepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled((currentSlide?.pipImages.isEmpty ?? true))
                .opacity((currentSlide?.pipImages.isEmpty ?? true) ? 0.4 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPhotoIdx)

            if let category = activePIPCategory {
                pipDropUpPanel(for: category)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
            }

            pipCategoryTabBar
        }
        .background(Color(white: 0.08))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activePIPCategory)
    }

    @ViewBuilder
    private func pipDropUpPanel(for category: PIPStyleCategory) -> some View {
        Group {
            switch category {
            case .border:
                pipBorderColorOptionsStrip
            case .shape:
                pipThumbShapeOptionsStrip
            case .size:
                pipClusterSizeSliderPanel
            case .background:
                pipBackgroundRemovalPanel
            }
        }
        .padding(.vertical, pipDropUpPanelUsesTightChrome(category) ? 6 : 0)
        .frame(maxWidth: .infinity)
        .background(pipDropUpPanelUsesTightChrome(category) ? Color(white: 0.11) : Color.clear)
        .overlay(alignment: .top) {
            if pipDropUpPanelUsesTightChrome(category) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }

    private func pipDropUpPanelUsesTightChrome(_ category: PIPStyleCategory) -> Bool {
        switch category {
        case .border, .shape, .size, .background: return true
        }
    }

    /// Border-color drop-up: same color set as the text color panel so users
    /// can match cluster outline to an accent color they've used on text.
    /// The first swatch is a "no border" toggle (circle with a diagonal
    /// slash) that turns off the outline entirely without discarding the
    /// currently-selected color.
    private var pipBorderColorOptionsStrip: some View {
        let active = pipEffectiveBorderColor
        let borderOff = !pipEffectiveBorderEnabled
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button { disablePIPBorder() } label: {
                    pipBorderNoneSwatch(isActive: borderOff)
                }
                .buttonStyle(.plain)

                ForEach(StudioTextColor.allCases) { tc in
                    let isActive = !borderOff && tc == active
                    Button { setPIPBorderColor(tc) } label: {
                        Circle()
                            .fill(tc.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .overlay {
                                if isActive {
                                    Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(-3)
                                }
                            }
                            .shadow(color: .black.opacity(0.35), radius: 3)
                            .padding(4)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollClipDisabled()
    }

    /// Rounded-rectangle insets (default) vs circular PIP thumbnails.
    private var pipThumbShapeOptionsStrip: some View {
        let current = pipEffectiveMaskStyle
        return HStack(spacing: 8) {
            ForEach(CarouselPIPThumbMaskStyle.allCases) { style in
                let isActive = current == style
                Button {
                    applyPIPThumbMaskStyle(style)
                } label: {
                    Text(style.optionsStripLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isActive ? Color(white: 0.1) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isActive
                                      ? Color.white
                                      : Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isActive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    /// "No border" swatch — a dark circle with a diagonal line across it,
    /// matching the prohibition / "none" idiom used elsewhere in iOS. Rendered
    /// to the same 36pt footprint as the color swatches so the row aligns.
    @ViewBuilder
    private func pipBorderNoneSwatch(isActive: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.14))
                .frame(width: 36, height: 36)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
                }
            // Diagonal slash drawn as a rounded capsule so it reads clearly
            // against the dark fill at this size.
            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: 30, height: 2.4)
                .rotationEffect(.degrees(-45))
        }
        .overlay {
            if isActive {
                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                    .frame(width: 36, height: 36)
                    .padding(-3)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3)
        .padding(4)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
    }

    /// Horizontal track + draggable circle for PIP thumbnail scale (multi-photo cluster).
    private var pipClusterSizeSliderPanel: some View {
        let rawScale: CGFloat = {
            guard let slide = currentSlide else { return 1.0 }
            if slide.pipIsUngrouped, let i = selectedPIPPhotoIndex {
                return slide.effectivePIPPhotoSizeScale(at: i)
            }
            return slide.pipClusterSizeScale
        }()
        let scale = min(max(rawScale,
                              StudioPIPClusterSize.minScale),
                        StudioPIPClusterSize.maxScale)
        let range = StudioPIPClusterSize.maxScale - StudioPIPClusterSize.minScale
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Thumbnail size")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(round(scale * 100)))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .monospacedDigit()
            }
            // Preset size pills — quick jumps; slider below for fine-tuning.
            HStack(spacing: 8) {
                ForEach(Self.pipSizePresets, id: \.label) { preset in
                    let isActive = abs(scale - preset.value) < (StudioPIPClusterSize.step * 0.6)
                    Button {
                        pushUndoSnapshot()
                        setPIPClusterSizeScaleLive(preset.value)
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(isActive ? Color(white: 0.1) : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isActive
                                          ? Color.white
                                          : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let knob: CGFloat = 32
                let span = max(w - knob, 1)
                let t = CGFloat((scale - StudioPIPClusterSize.minScale) / range)
                let knobMinX = CGFloat(min(max(t, 0), 1)) * span

                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: w, height: 6)
                        .offset(x: 0, y: (h - 6) / 2)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(white: 0.88)],
                                startPoint: .top,
                                endPoint: .bottom)
                        )
                        .frame(width: knob, height: knob)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)
                        .offset(x: knobMinX, y: (h - knob) / 2)
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if !pipClusterSizeSliderUndoPrimed {
                                pushUndoSnapshot()
                                pipClusterSizeSliderUndoPrimed = true
                            }
                            let centerX = min(max(g.location.x, knob / 2), w - knob / 2)
                            let nt = (centerX - knob / 2) / span
                            let raw = StudioPIPClusterSize.minScale + nt * range
                            setPIPClusterSizeScaleLive(raw)
                        }
                        .onEnded { _ in
                            pipClusterSizeSliderUndoPrimed = false
                        }
                )
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var pipBackgroundRemovalPanel: some View {
        if pipBackgroundRemovalSupported {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "person.crop.square.filled.and.at.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 28, alignment: .center)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Remove background")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            if pipBackgroundRemovalPanelBusy {
                                ProgressView()
                                    .scaleEffect(0.78)
                                    .tint(.white.opacity(0.9))
                            }
                        }
                                        Group {
                            if currentSlide?.pipIsUngrouped == true {
                                Text("Select a small photo first. Only that inset is cut out.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.48))
                            } else if #available(iOS 17, *) {
                                Text("Joined cluster: only the first inset is cut out. Separated: pick one inset first.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.48))
                            } else {
                                Text("Joined cluster: first inset only. Separated: select one inset.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.48))
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Toggle("", isOn: pipBackgroundRemovalToggle)
                        .labelsHidden()
                        .tint(CarouselStudioChrome.accent)
                        .disabled(
                            (currentSlide?.pipImages.isEmpty ?? true)
                                || ((currentSlide?.pipIsUngrouped ?? false) && selectedPIPPhotoIndex == nil)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow.opacity(0.85))
                Text("Requires iOS 16 or later")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    /// Category tab bar for the PIP cluster. Leading pills scroll with the row:
    /// **Add Photos** opens the picker when there is room and eligible picks;
    /// **Remove** drops the bottom-most photo when two or more thumbnails are
    /// visible (each button disables independently). **Style** (vertical vs
    /// horizontal stack) sits third; then Border / Shape / Size / Remove BG drop-ups.
    /// Mirrors `styleCategoryTabBar`'s layout so the row heights align.
    private var pipCategoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    pipAddPhotosTabButton
                    pipRemovePhotosTabButton
                    pipGroupToggleTabButton
                    pipStyleMenuButton
                }
                ForEach(pipStyleToolbarCategories, id: \.self) { cat in
                    pipCategoryButton(cat)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color(white: 0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    /// Separate / Join button: breaks the cluster into individually draggable
    /// thumbnails (or re-groups them). Disabled when only one photo is visible.
    @ViewBuilder
    private var pipGroupToggleTabButton: some View {
        let isUngrouped = currentSlide?.pipIsUngrouped ?? false
        let visible = currentSlideEffectivePIPVisibleCount
        let canToggle = visible > 1

        Button {
            let idx = editorPagerFocusedSlideIndex
            guard slides.indices.contains(idx) else { return }
            togglePIPGrouping(for: idx)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isUngrouped ? "square.stack.fill" : "square.2.layers.3d.top.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(canToggle
                        ? (isUngrouped ? CarouselStudioChrome.accent : .white.opacity(0.75))
                        : .white.opacity(0.3))
                    .frame(width: 22, height: 22)
                Text(isUngrouped ? "Join" : "Separate")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canToggle ? .white : .white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .animation(.easeInOut(duration: 0.18), value: isUngrouped)
        .animation(.easeInOut(duration: 0.18), value: canToggle)
    }

    /// Stack direction (vertical column vs horizontal row) for the PIP cluster.
    @ViewBuilder
    private var pipStyleMenuButton: some View {
        let visible = currentSlideEffectivePIPVisibleCount
        let canUsePIPMultiPhotoControls = visible > 1
        let current = currentSlide?.pipClusterStackStyle ?? .vertical
        Menu {
            Button {
                applyPIPClusterStackStyle(.vertical)
            } label: {
                HStack {
                    Text("Vertical stack")
                    Spacer(minLength: 8)
                    if current == .vertical {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                applyPIPClusterStackStyle(.horizontal)
            } label: {
                HStack {
                    Text("Horizontal stack")
                    Spacer(minLength: 8)
                    if current == .horizontal {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "rectangle.split.1x2")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canUsePIPMultiPhotoControls
                        ? .white.opacity(0.75)
                        : .white.opacity(0.35))
                    .frame(width: 22, height: 22)
                Text("Style")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canUsePIPMultiPhotoControls
                        ? .white.opacity(0.55)
                        : .white.opacity(0.35))
                    .lineLimit(1)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canUsePIPMultiPhotoControls)
    }

    /// Leading **Add Photos** pill in `pipCategoryTabBar`: opens the picker when
    /// the cluster has fewer than three visible slots and at least one eligible
    /// library photo exists.
    @ViewBuilder
    private var pipAddPhotosTabButton: some View {
        let visible = currentSlideEffectivePIPVisibleCount
        let canAdd = visible < 3 && !availableAddablePhotos.isEmpty

        Button {
            showsAddPhotoPicker = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canAdd
                        ? CarouselStudioChrome.accent
                        : .white.opacity(0.3))
                    .frame(width: 22, height: 22)
                Text("Add Photos")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canAdd ? .white : .white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .animation(.easeInOut(duration: 0.18), value: canAdd)
    }

    /// Leading **Remove** pill: in ungrouped mode with a photo selected, removes
    /// that specific photo; otherwise drops the bottom-most visible photo
    /// (disabled when only one photo is in the cluster).
    @ViewBuilder
    private var pipRemovePhotosTabButton: some View {
        let visible = currentSlideEffectivePIPVisibleCount
        let isUngroupedWithSelection = (currentSlide?.pipIsUngrouped ?? false) && selectedPIPPhotoIndex != nil
        let canRemove = isUngroupedWithSelection || visible > 1

        Button {
            if isUngroupedWithSelection {
                removeSelectedPIPPhoto()
            } else {
                removeLastPIPPhoto()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canRemove
                        ? Color(red: 1.0, green: 0.45, blue: 0.45)
                        : .white.opacity(0.3))
                    .frame(width: 22, height: 22)
                Text("Remove")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canRemove ? .white : .white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRemove)
        .animation(.easeInOut(duration: 0.18), value: canRemove)
    }

    @ViewBuilder
    private func pipCategoryButton(_ cat: PIPStyleCategory) -> some View {
        let isActive = activePIPCategory == cat
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                activePIPCategory = isActive ? nil : cat
            }
        } label: {
            VStack(spacing: 4) {
                pipCategoryIcon(for: cat, isActive: isActive)
                Text(cat.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pipCategoryIcon(for cat: PIPStyleCategory, isActive: Bool) -> some View {
        switch cat {
        case .border:
            let borderOff = !pipEffectiveBorderEnabled
            ZStack {
                Circle()
                    .fill(borderOff
                          ? Color(white: 0.14)
                          : pipEffectiveBorderColor.color)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(
                        isActive ? Color.white : Color.white.opacity(0.35),
                        lineWidth: isActive ? 2 : 1))
                if borderOff {
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 18, height: 1.6)
                        .rotationEffect(.degrees(-45))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 2)
        case .shape:
            Image(systemName: pipEffectiveMaskStyle == .circle
                  ? "circle.fill"
                  : "square.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isActive ? .white : .white.opacity(0.75))
                .frame(width: 22, height: 22)
        case .size:
            Image(systemName: "aspectratio")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isActive ? .white : .white.opacity(0.75))
                .frame(width: 22, height: 22)
        case .background:
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isActive ? .white : .white.opacity(0.75))
                .frame(width: 22, height: 22)
        }
    }

    // MARK: Drop-up panels

    @ViewBuilder
    private func styleDropUpPanel(for category: StyleCategory) -> some View {
        Group {
            switch category {
            case .color:  colorOptionsStrip
            case .font:   fontOptionsStrip
            case .size:   sizeOptionsStrip
            case .format: formatOptionsStrip
            }
        }
        // Fixed height keeps the whole toolbar a constant size while the bottom
        // chrome is bottom-aligned in its slot — otherwise Font Size vs Format
        // (and other strips) had different intrinsic heights and the Apply row jumped.
        .frame(height: Self.styleDropUpContentHeight, alignment: .center)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.11))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var colorOptionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(StudioTextColor.allCases) { tc in
                    let isActive = currentStyle.textColor == tc
                    Button { updateStyle { $0.textColor = tc } } label: {
                        Circle()
                            .fill(tc.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .overlay {
                                if isActive {
                                    Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(-3)
                                }
                            }
                            .shadow(color: .black.opacity(0.35), radius: 3)
                            .padding(4)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    private var fontOptionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StudioFontDesign.allCases) { design in
                    let isActive = currentStyle.fontDesign == design
                    Button { updateStyle { $0.fontDesign = design } } label: {
                        Text(design.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: design.design))
                            .foregroundColor(isActive ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(isActive
                                        ? CarouselStudioChrome.accent
                                        : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(
                                isActive ? Color.white.opacity(0.35) : Color.white.opacity(0.08),
                                lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    /// Font-size panel: continuous slider plus −/+ steppers that surface the
    /// nominal point size (reference base = 20pt, scale × 20 ≈ classic iOS
    /// sizes 12 / 13 / … / 36). The slide text itself is still driven by a
    /// multiplicative `sizeScale` so every block kind stays in proportion.
    /// The slider snaps to 0.05 increments so every thumb position maps to
    /// a whole-point readout, and one drag collapses into a single undo step.
    private var sizeOptionsStrip: some View {
        HStack(spacing: 14) {
            Slider(
                value: Binding<CGFloat>(
                    get: { currentStyle.sizeScale },
                    set: { newValue in setSizeScaleLive(newValue) }
                ),
                in: Self.sizeScaleMin...Self.sizeScaleMax,
                step: Self.sizeScaleStep,
                onEditingChanged: { editing in
                    if editing { pushUndoSnapshot() }
                }
            )
            .tint(CarouselStudioChrome.accent)

            HStack(spacing: 8) {
                sizeStepperButton(systemName: "minus",
                                  isEnabled: currentStyle.sizeScale > Self.sizeScaleMin + 0.0005) {
                    adjustSizeScale(by: -Self.sizeScaleStep)
                }

                Text("\(Self.displayPoints(for: currentStyle.sizeScale))")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 30)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(currentStyle.sizeScale)))
                    .animation(.easeInOut(duration: 0.15), value: currentStyle.sizeScale)

                sizeStepperButton(systemName: "plus",
                                  isEnabled: currentStyle.sizeScale < Self.sizeScaleMax - 0.0005) {
                    adjustSizeScale(by: Self.sizeScaleStep)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    /// Circular −/+ button used inside the font-size strip. Matches the
    /// muted white-fill chrome of the other panels' pill buttons, and dims
    /// when the scale has hit its minimum/maximum so the range is obvious.
    @ViewBuilder
    private func sizeStepperButton(systemName: String,
                                   isEnabled: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(isEnabled ? 0.12 : 0.06))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Writes a new `sizeScale` without pushing a new undo snapshot — used
    /// from the slider's binding so a single drag coalesces into one undo
    /// step (the snapshot is taken in `onEditingChanged` when the drag
    /// starts).
    private func setSizeScaleLive(_ rawScale: CGFloat) {
        guard let selectedBlock else { return }
        let focusedIndex = editorPagerFocusedSlideIndex
        guard slides.indices.contains(focusedIndex) else { return }
        let snapped = StudioTextBlockSize.clampAndSnap(rawScale)
        guard abs(snapped - currentStyle.sizeScale) > 0.0001 else { return }
        if selectedBlock == .secondary {
            slides[focusedIndex].textStyle.secondary.sizeScale = snapped
        } else {
            slides[focusedIndex].textStyle.primary.sizeScale = snapped
        }
    }

    /// Tap handler for the −/+ stepper buttons. Each tap is its own undo
    /// step, matching how every other toolbar tap behaves.
    private func adjustSizeScale(by delta: CGFloat) {
        let next = currentStyle.sizeScale + delta
        let snapped = StudioTextBlockSize.clampAndSnap(next)
        guard abs(snapped - currentStyle.sizeScale) > 0.0001 else { return }
        updateStyle { $0.sizeScale = snapped }
    }

    /// Continuous font-size slider range. The matching display readout is
    /// computed via `displayPoints(for:)`, so min = 12pt and max = 36pt.
    private static let sizeScaleMin: CGFloat = StudioTextBlockSize.minScale
    private static let sizeScaleMax: CGFloat = StudioTextBlockSize.maxScale
    /// One display point = 0.05 scale units (since reference base = 20pt),
    /// so every slider position lines up with a whole-number readout.
    private static let sizeScaleStep: CGFloat = StudioTextBlockSize.step

    /// Format panel: horizontally-scrollable row of style toggles
    /// (Bold / Italic / Underline), a three-way text-case cycle (aA), and
    /// three alignment options. Each button writes directly to
    /// `currentStyle` via `updateStyle`, so one tap = one undo step.
    private var formatOptionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                formatToggleButton(
                    label: "B",
                    font: .system(size: 16, weight: .bold),
                    isActive: currentStyle.isBold
                ) { updateStyle { $0.isBold.toggle() } }

                formatToggleButton(
                    label: "I",
                    font: .system(size: 16, weight: .semibold).italic(),
                    isActive: currentStyle.isItalic
                ) { updateStyle { $0.isItalic.toggle() } }

                formatToggleButton(
                    label: "U",
                    font: .system(size: 16, weight: .semibold),
                    underline: true,
                    isActive: currentStyle.isUnderlined
                ) { updateStyle { $0.isUnderlined.toggle() } }

                // aA case cycle: none → UPPER → lower → none
                formatToggleButton(
                    label: "aA",
                    font: .system(size: 14, weight: .semibold),
                    isActive: currentStyle.textCase != .none
                ) {
                    updateStyle { style in
                        switch style.textCase {
                        case .none:  style.textCase = .upper
                        case .upper: style.textCase = .lower
                        case .lower: style.textCase = .none
                        }
                    }
                }

                // Visual divider between style toggles and alignment group.
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 4)

                ForEach([StudioTextAlignment.leading,
                         .center,
                         .trailing], id: \.self) { align in
                    alignmentButton(align)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    /// Shared pill button used for B / I / U / S / aA. `font` carries the
    /// weight + italic trait so we can mimic the label's style at rest, and
    /// the `underline` / `strikethrough` flags let the U / S pills display
    /// with their respective decoration applied to the label letter.
    @ViewBuilder
    private func formatToggleButton(label: String,
                                    font: Font,
                                    underline: Bool = false,
                                    strikethrough: Bool = false,
                                    isActive: Bool,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .underline(underline)
                .strikethrough(strikethrough)
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .frame(minWidth: 44, minHeight: 34)
                .padding(.horizontal, 4)
                .background(isActive
                            ? CarouselStudioChrome.accent
                            : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? Color.white.opacity(0.35) : Color.white.opacity(0.08),
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    /// Alignment pill. Tapping the already-active alignment resets to `.natural`,
    /// which falls back to the block's built-in default (center for cover
    /// titles, leading for everything else). That gives users a clean way to
    /// undo their alignment choice without needing a separate "reset" control.
    @ViewBuilder
    private func alignmentButton(_ align: StudioTextAlignment) -> some View {
        let isActive = currentStyle.alignment == align
        Button {
            updateStyle { $0.alignment = isActive ? .natural : align }
        } label: {
            Image(systemName: align.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .frame(minWidth: 44, minHeight: 34)
                .background(isActive
                            ? CarouselStudioChrome.accent
                            : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? Color.white.opacity(0.35) : Color.white.opacity(0.08),
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    /// Reference base so 100% shows as "20" (a natural mid-range iOS text size).
    /// The slide's actual rendered size still varies per block kind — this label
    /// is just a familiar, monotonic readout users can read like a font picker.
    private static let sizeReferencePoints: CGFloat = 20

    private static func displayPoints(for scale: CGFloat) -> Int {
        Int((scale * sizeReferencePoints).rounded())
    }

    // MARK: Category tab bar

    /// The category tab bar is horizontally scrollable so additional
    /// categories (Color / Font Style / Font Size / Format) can grow
    /// without cramping the buttons. Buttons use a fixed intrinsic width so
    /// their labels never truncate; if the row doesn't fit on narrower
    /// devices (e.g. iPhone SE), users scroll horizontally.
    /// First tab in the category bar: bulk-apply actions for all slides.
    /// Uses a Menu so the interaction matches the existing drop-down affordance.
    private var applyTabMenuButton: some View {
        Menu {
            Button {
                applyTypographyToAllSlides()
                flashAppliedConfirmation()
            } label: {
                Label("Typography to all slides", systemImage: "textformat")
            }
            if currentSlide?.kind == .placeStop {
                Button {
                    applyPhotoLayoutToAllPlaceStops()
                    flashAppliedConfirmation()
                } label: {
                    Label("Positions to all photo slides", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: didApplyToAll ? "checkmark" : "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(didApplyToAll ? .white : .white.opacity(0.85))
                    .frame(width: 22, height: 22)
                Text(didApplyToAll ? "Applied" : "Apply")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(didApplyToAll ? .white : .white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(didApplyToAll ? CarouselStudioChrome.accent.opacity(0.4) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: didApplyToAll)
    }

    private var styleCategoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                applyTabMenuButton
                ForEach(StyleCategory.allCases) { cat in
                    styleCategoryButton(cat)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            // Match the ScrollView's visible width so the Spacers above expand and
            // center the fixed-width category buttons. If a future 5th category
            // pushes the intrinsic content past this width, `containerRelativeFrame`
            // still lets the ScrollView take over and scroll horizontally.
            .containerRelativeFrame(.horizontal)
        }
        .scrollClipDisabled()
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color(white: 0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    /// Intrinsic width for each category button. Fixed (rather than
    /// `maxWidth: .infinity`) so adding a 5th category later just
    /// overflows the bar and enables horizontal scrolling — no per-button
    /// squeezing or truncation.
    private static let categoryButtonWidth: CGFloat = 86
    /// Inner height for the style drop-up content (swatches, slider, format row).
    private static let styleDropUpContentHeight: CGFloat = 56

    private struct PIPSizePreset { let label: String; let value: CGFloat }
    private static let pipSizePresets: [PIPSizePreset] = [
        PIPSizePreset(label: "XS", value: 0.55),
        PIPSizePreset(label: "S",  value: 0.72),
        PIPSizePreset(label: "M",  value: 1.00),
        PIPSizePreset(label: "L",  value: 1.22),
        PIPSizePreset(label: "XL", value: 1.45),
        PIPSizePreset(label: "XXL", value: 1.90),
    ]

    @ViewBuilder
    private func styleCategoryButton(_ cat: StyleCategory) -> some View {
        let isActive = activeStyleCategory == cat
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                activeStyleCategory = isActive ? nil : cat
            }
        } label: {
            VStack(spacing: 4) {
                categoryIcon(for: cat, isActive: isActive)
                Text(cat.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Category icon. For Color, we show the live swatch instead of a generic palette glyph
    /// so users can see the currently-chosen color at a glance.
    @ViewBuilder
    private func categoryIcon(for cat: StyleCategory, isActive: Bool) -> some View {
        switch cat {
        case .color:
            Circle()
                .fill(currentStyle.textColor.color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(
                    isActive ? Color.white : Color.white.opacity(0.35),
                    lineWidth: isActive ? 2 : 1))
                .shadow(color: .black.opacity(0.35), radius: 2)
        case .font:
            Text("Aa")
                .font(.system(size: 16, weight: .bold, design: currentStyle.fontDesign.design))
                .foregroundColor(isActive ? .white : .white.opacity(0.65))
                .frame(width: 22, height: 22)
        case .size:
            Image(systemName: cat.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isActive ? .white : .white.opacity(0.65))
                .frame(width: 22, height: 22)
        case .format:
            // "B" glyph reflects the Bold toggle's on/off state so the tab
            // hints at the current formatting without forcing the user to
            // open the panel. Using a text glyph (rather than SF Symbol)
            // lets it pick up the chosen font design too.
            Text("B")
                .font(.system(size: 16, weight: .heavy,
                              design: currentStyle.fontDesign.design))
                .italic(currentStyle.isItalic)
                .underline(currentStyle.isUnderlined)
                .strikethrough(currentStyle.isStrikethrough)
                .foregroundColor(isActive ? .white : .white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(width: 22, height: 22)
                .clipped()
        }
    }
}

// MARK: - Studio sheet — slide preparation loading

private struct StudioSlidePreparationLoadingView: View {
    var progress: Double

    private static let backdropNavy = Color(red: 5/255, green: 10/255, blue: 48/255)

    private var percentDisplay: Int {
        min(100, max(0, Int((progress * 100).rounded(.towardZero))))
    }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 50.0, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let spin = (t.truncatingRemainder(dividingBy: 2.8)) / 2.8 * 360.0
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    CarouselStudioChrome.accent.opacity(0.15),
                                    CarouselStudioChrome.accent.opacity(0.9),
                                    CarouselStudioChrome.accent.opacity(0.12)
                                ],
                                center: .center,
                                angle: .degrees(-30 + spin)
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 104, height: 104)
                }
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 5)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: max(0.015, progress))
                        .stroke(
                            CarouselStudioChrome.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.22), value: progress)
                    Text("\(percentDisplay)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.18), value: percentDisplay)
                }
            }
            .frame(width: 104, height: 104)

            VStack(spacing: 8) {
                Text("Preparing slides")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Loading photos and maps for your carousel")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaPadding(.vertical, 8)
        .background {
            ZStack {
                Self.backdropNavy
                LinearGradient(
                    colors: [
                        Self.backdropNavy,
                        Color(red: 14/255, green: 22/255, blue: 72/255),
                        Color(red: 8/255, green: 14/255, blue: 52/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Studio Sheet

struct SocialPostStudioSheet: View {
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case post, story, reel
        var id: String { rawValue }
        var title: String { switch self { case .post: "Post"; case .story: "Story"; case .reel: "Reel" } }
        var icon: String { switch self { case .post: "rectangle.portrait"; case .story: "sparkles.rectangle.stack"; case .reel: "film" } }
        var subtitle: String { switch self {
            case .post:  "Classic feed format for photo carousels"
            case .story: "Full-screen portrait for story posts"
            case .reel:  "Pick one slide as your Reel cover (9:16)"
        } }
        var aspectRatio: CGFloat { switch self { case .post: 4.0/5.0; case .story, .reel: 9.0/16.0 } }
        /// Reel exports a single cover image rather than a sequence.
        var isSingleSlide: Bool { self == .reel }
    }

    private struct EditableSlideRef: Identifiable {
        let index: Int; var id: Int { index }
    }

    let blog: RecapBlogDetail
    /// When `true`, the sheet is **Edit Slides** after load (Share → Post to Social), not Social Post Studio.
    var opensInEditMode: Bool = false
    /// My Places share: place photos + optional route map only — no per-day itinerary maps or “Day N” cards.
    var placesOnlyMode: Bool = false
    /// When the studio is embedded inline (not a system sheet), wire the nav Close button to this instead of `dismiss()`.
    var onDismissFromParent: (() -> Void)? = nil

    @State private var slides: [CarouselSlide] = []
    @State private var exportFormat: ExportFormat = .post
    /// Aspect used by `ImageRenderer` in export rendering; matches `exportFormat` until the slide editor toggles 4:5 ↔ 9:16.
    @State private var exportRenderAspectRatio: CGFloat = 4.0 / 5.0
    /// Per-format snapshot of each slide's text/pip offsets. Populated when the user
    /// switches aspect ratios so switching back restores the previous layout.
    @State private var savedFormatOffsets: [String: [(primary: CGSize, secondary: CGSize, pip: CGSize)]] = [:]
    @State private var isLoading = true
    /// 0…1 while `loadSlides()` runs; drives the preparation ring and percentage label.
    @State private var slidePreparationProgress: Double = 0
    /// Bumped at the start of each `loadSlides()` so an older async completion cannot overwrite `slides` after a newer reload (e.g. rapidly toggling skip-duplicate).
    @State private var loadSlidesGeneration: UInt64 = 0
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
    /// Two-line success alert after saving to Photos (title + message).
    @State private var savedAlertTitle = ""
    @State private var savedAlertBody = ""
    @State private var editingSlideRef: EditableSlideRef? = nil
    /// After `.pip` hides sibling place-stop cards, re-scroll so the slide the user
    /// tapped stays centered instead of the strip keeping a stale content offset.
    @State private var previewRecenterAfterPIPIndex: Int?
    @State private var previewRecenterAfterPIPNonce: Int = 0
    /// When set, the cover slide uses this included photo instead of `blog.selectedCoverPhotoIdentifier`.
    /// Never written back to the blog draft — studio / export only.
    @State private var studioCoverPhotoID: UUID? = nil
    @State private var showStudioCoverPicker = false
    /// Place photos removed from this session’s carousel (not the blog draft). Keys: `studioExclusionKey`.
    @State private var excludedStudioPhotoKeys: Set<String> = []
    /// Slide grid sheet: jump to a slide in the preview strip or editor.
    @State private var showPhotoGroupPicker = false
    /// When set, the horizontal preview strip scrolls this slide into view after the grid sheet closes.
    @State private var navigatePreviewToSlideIndex: Int?
    /// When set, `SlideTextEditorView` jumps its pager to this raw slide index (embedded or full-screen editor).
    @State private var studioEditorJumpToSlideIndex: Int?
    /// Fired after load when the selected slide count still exceeds 34 after auto-PIP.
    @State private var showSocialCarouselOverflowAlert = false
    @State private var socialCarouselOverflowSlideCount = 0
    /// Mirrors the child `SlideTextEditorView` AppStorage key so this view can defer the overflow
    /// alert until after the first-run layout picker sheet is dismissed (the two conflict if simultaneous).
    @AppStorage("carouselStudio.hasSeenPlaceLayoutPicker") private var hasSeenPlaceLayoutPicker = false
    /// Set when overflow is detected but the first-run layout picker sheet hasn't shown yet;
    /// cleared and overflow rechecked once `hasSeenPlaceLayoutPicker` flips to true.
    @State private var pendingOverflowAfterFirstRunLayoutPicker = false
    /// Confirms save / PDF when slide count exceeds the per-package cap (34); JPEG share caps before this runs.
    private enum LargeStudioExportMemoryGate: Equatable {
        case saveToPhotos(indices: [Int])
        case pdf(indices: [Int])
    }

    @State private var largeStudioExportMemoryGate: LargeStudioExportMemoryGate? = nil
    /// One-time dismissible tip for removing place photos from the preview strip (`UserDefaults`).
    @AppStorage("carouselStudio.removePlacePhotoTip.dismissed") private var removePlacePhotoTipDismissed = false
    @Environment(\.dismiss) private var dismiss
    /// JPEG share >34 steps: confirm truncating to cap before opening the share sheet.
    @State private var pendingShareJPEGHardCapSteps: [ShareJPEGExportStep]?
    @State private var showShareJPEGHardCapConfirmation = false
    /// Queued slide-index groups for PDF export after first share sheet completes (≤34 slides per PDF).
    @State private var pdfExportQueuedIndexChunks: [[Int]] = []
    @State private var pdfExportScheduledTotalChunks: Int = 0
    @State private var showPDFExportNextContinuation = false
    /// Slides Management: deck snapshot before removing all maps so turning the control off restores maps (session-only).
    @State private var slideManagementDeckSnapshotBeforeRemovingMaps: [CarouselSlide]? = nil
    /// Don’t present the >34 slides alert while Slides Management is open — it dismisses the sheet; run after dismiss instead.
    @State private var pendingSocialCarouselOverflowAfterSlidesPickerDismiss = false

    private let previewHeight: CGFloat = 450
    private let exportWidth: CGFloat = 1080
    private var exportHeight: CGFloat { exportWidth / exportFormat.aspectRatio }
    private var previewWidth: CGFloat { previewHeight * exportFormat.aspectRatio }
    private var selectedSlides: [CarouselSlide] {
        // Exclude slides hidden by a sibling's PIP cluster so their photo
        // doesn't get exported twice (once inside the cluster, once as its
        // own slide) even if the user flips "Select all" while PIP is on.
        let sel = slides.enumerated().compactMap { idx, slide -> CarouselSlide? in
            guard !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { return nil }
            return slide.isSelected ? slide : nil
        }
        return exportFormat.isSingleSlide ? Array(sel.prefix(1)) : sel
    }

    /// Disables export menu actions when there is nothing to export or work is in flight.
    private var exportActionsDisabled: Bool {
        isLoading || slides.isEmpty || selectedSlides.isEmpty || isRendering
    }

    /// Binding for Slides Management “remove maps” toggle: `true` when maps were removed using the toggle (restore available).
    private var slideManagementRemoveMapsFromCarouselBinding: Binding<Bool> {
        Binding(
            get: { slideManagementDeckSnapshotBeforeRemovingMaps != nil },
            set: { shouldRemoveMaps in
                if shouldRemoveMaps {
                    guard slides.contains(where: { isCarouselStudioMapKind($0.kind) }) else { return }
                    slideManagementDeckSnapshotBeforeRemovingMaps = slides
                    excludeAllMapSlidesFromStudio()
                } else {
                    guard let snap = slideManagementDeckSnapshotBeforeRemovingMaps else { return }
                    slides = snap
                    slideManagementDeckSnapshotBeforeRemovingMaps = nil
                    checkSocialCarouselOverflow()
                }
            }
        )
    }

    private func makeEditorExportActions() -> SlideTextEditorExportActions {
        SlideTextEditorExportActions(
            share: { await requestShareJPEGToSheet(indices: orderedExportSlideIndices(), omitMapsFromShare: false) },
            shareAtIndices: { indices, omitMapsFromShare in
                await requestShareJPEGToSheet(indices: indices, omitMapsFromShare: omitMapsFromShare)
            },
            saveToPhotos: { await requestSaveToPhotos(indices: orderedExportSlideIndices()) },
            saveToPhotosAtIndices: { indices in await requestSaveToPhotos(indices: indices) },
            exportPDFAtIndices: { indices in await requestExportPDFToShare(indices: indices) },
            exportPDF: { await requestExportPDFToShare(indices: orderedExportSlideIndices()) },
            exportActionsDisabled: { exportActionsDisabled }
        )
    }

    var body: some View {
        studioBodyWithPresentationChrome
    }

    @ViewBuilder
    private var studioRootContent: some View {
        if opensInEditMode {
            studioEditModeRoot
        } else {
            studioPreviewModeRoot
        }
    }

    @ViewBuilder
    private var studioEditModeRoot: some View {
        if isLoading {
            StudioSlidePreparationLoadingView(progress: slidePreparationProgress)
                .preferredColorScheme(.dark)
        } else if slides.isEmpty {
            Text("No places found in this blog.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 5/255, green: 10/255, blue: 48/255))
                .preferredColorScheme(.dark)
        } else {
            studioEmbeddedSlideEditor(initialIndex: 0, onDismissEditor: onDismissFromParent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var studioPreviewModeRoot: some View {
        NavigationStack {
            ZStack {
                Group {
                    if isLoading {
                        StudioSlidePreparationLoadingView(progress: slidePreparationProgress)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if slides.isEmpty {
                        Text("No places found in this blog.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        slidePreviewAndExport
                    }
                }
                if isRendering {
                    studioExportProgressOverlay
                }
            }
            .background(isLoading
                ? Color(red: 5/255, green: 10/255, blue: 48/255)
                : Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Social Post Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { studioPreviewToolbarContent }
            .preferredColorScheme(.dark)
        }
    }

    private var studioExportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .allowsHitTesting(true)
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(.white)
                Text("Preparing export…")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ToolbarContentBuilder
    private var studioPreviewToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14)).foregroundColor(.white)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button { Task { await shareViaSheet() } } label: {
                    Label("Share to social apps…", systemImage: "square.and.arrow.up")
                }
                Button { Task { await saveToPhotos() } } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle.angled")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .disabled(exportActionsDisabled)
            .accessibilityLabel("Export and share")
        }
    }

    private func studioEmbeddedSlideEditor(initialIndex: Int, onDismissEditor: (() -> Void)?) -> some View {
        SlideTextEditorView(
            slides: $slides,
            initialIndex: initialIndex,
            aspectRatio: exportFormat.aspectRatio,
            exportCanvasAspectRatio: $exportRenderAspectRatio,
            exportActions: makeEditorExportActions(),
            exportInProgress: $isRendering,
            externalJumpToSlideIndex: $studioEditorJumpToSlideIndex,
            onRequestStudioCoverPhotoPick: {
                #if DEBUG
                print("[CarouselStudio] opening cover picker (Edit Slides / Carousel Studio)")
                #endif
                showStudioCoverPicker = true
            },
            onExcludePlaceFromStudio: { idx in excludePlaceSlide(at: idx) },
            onExcludeMapFromStudio: { idx in
                guard slides.indices.contains(idx), isCarouselStudioMapKind(slides[idx].kind) else { return }
                if slides[idx].isSelected { excludeMapSlide(at: idx) } else { restoreMapSlide(at: idx) }
            },
            onOpenPhotoGroupPicker: { showPhotoGroupPicker = true },
            isSingleSlideDownloadMode: exportFormat.isSingleSlide,
            onDismissEditor: onDismissEditor,
            onExcludeAllMapsFromStudio: { excludeAllMapSlidesFromStudio() }
        )
    }

    private var studioBodyWithAlerts: some View {
        studioRootContent
            .task { await loadSlides() }
            .onChange(of: exportFormat) { _, _ in Task { await loadSlides() } }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                cleanupTempFiles()
                if !pdfExportQueuedIndexChunks.isEmpty {
                    showPDFExportNextContinuation = true
                }
            }, content: {
                ShareSheet(items: shareItems)
            })
            .alert(savedAlertTitle, isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(savedAlertBody) }
            .alert(largeExportMemoryAlertTitle, isPresented: largeExportMemoryAlertBinding) {
                Button("View slides") {
                    showPhotoGroupPicker = true
                    largeStudioExportMemoryGate = nil
                }
                Button("Continue anyway", role: .destructive) {
                    let gate = largeStudioExportMemoryGate
                    largeStudioExportMemoryGate = nil
                    switch gate {
                    case .saveToPhotos(let idx):
                        Task { await performSaveToPhotosStreaming(atIndices: idx) }
                    case .pdf(let idx):
                        Task { await performExportPDFStreaming(atIndices: idx) }
                    case .none:
                        break
                    }
                }
                Button("Cancel", role: .cancel) {
                    largeStudioExportMemoryGate = nil
                }
            } message: {
                Text(largeExportMemoryAlertMessage)
            }
            .alert("More PDFs to share", isPresented: $showPDFExportNextContinuation) {
                Button("Continue") {
                    showPDFExportNextContinuation = false
                    Task { await presentNextQueuedPDFExportSlice() }
                }
                Button("Done", role: .cancel) {
                    pdfExportQueuedIndexChunks = []
                    pdfExportScheduledTotalChunks = 0
                }
            } message: {
                let pkgsLeft = pdfExportQueuedIndexChunks.count
                Text(
                    "\(pkgsLeft) PDF file\(pkgsLeft == 1 ? "" : "s") remaining (up to \(CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage) slides each)."
                )
            }
            .alert("Sharing limit", isPresented: $showShareJPEGHardCapConfirmation) {
                let cap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
                Button("Share first \(cap)") {
                    guard let full = pendingShareJPEGHardCapSteps else { return }
                    pendingShareJPEGHardCapSteps = nil
                    let capped = Array(full.prefix(cap))
                    Task { await performUnbatchedShareJPEGExportSteps(capped) }
                }
                Button("Cancel", role: .cancel) {
                    pendingShareJPEGHardCapSteps = nil
                }
            } message: {
                Text(shareJPEGHardCapConfirmationMessage)
            }
            .alert("Your carousel is pretty large", isPresented: $showSocialCarouselOverflowAlert) {
                Button("View Slides") { showPhotoGroupPicker = true }
                Button("Continue Anyway", role: .cancel) {}
            } message: {
                Text(studioCarouselOverflowAlertMessage)
            }
    }

    private var studioCarouselOverflowAlertMessage: String {
        "Some platforms limit how many slides can be uploaded at once.\n\n"
        + "You currently have \(socialCarouselOverflowSlideCount) slides selected. Instagram may only post the first 34 slides.\n\n"
        + "You can:\n"
        + "• Trim slides\n"
        + "• Combine busy moments with Multi layout\n"
        + "• Continue anyway"
    }

    private var studioPhotoGroupPickerSheet: some View {
        CarouselPhotoGroupPickerSheet(
            slides: $slides,
            blog: blog,
            excludedKeys: excludedStudioPhotoKeys,
            aspectRatio: exportFormat.aspectRatio,
            isDeckReloading: isLoading,
            isReelExport: exportFormat.isSingleSlide,
            onSelectSlide: { index in
                showPhotoGroupPicker = false
                DispatchQueue.main.async {
                    if opensInEditMode || editingSlideRef != nil {
                        studioEditorJumpToSlideIndex = index
                    } else {
                        navigatePreviewToSlideIndex = index
                    }
                }
            },
            onRestoreExcludedPlacePhoto: { stopID, photoID in
                restoreExcludedPhoto(stopID: stopID, photoID: photoID)
            },
            onExcludePlaceFromStudio: { idx in
                guard slides.indices.contains(idx), slides[idx].kind == .placeStop else { return }
                if slides[idx].isSelected {
                    excludePlaceSlide(at: idx)
                } else {
                    restorePlaceSlide(at: idx)
                }
            },
            onExcludeMapFromStudio: { idx in
                guard slides.indices.contains(idx), isCarouselStudioMapKind(slides[idx].kind) else { return }
                if slides[idx].isSelected { excludeMapSlide(at: idx) } else { restoreMapSlide(at: idx) }
            },
            removeMapsFromCarousel: slideManagementRemoveMapsFromCarouselBinding,
            onBulkSlidesExportSelectionChanged: {
                Task {
                    let stopIDs = Set(slides.compactMap { $0.placeStop?.id })
                    for sid in stopIDs {
                        await rebuildPIPPayloadsForStop(stopID: sid)
                    }
                }
            },
            placesOnlyMode: placesOnlyMode
        )
    }

    private var studioBodyWithPresentationChrome: some View {
        studioBodyWithAlerts
            .sheet(isPresented: $showPhotoGroupPicker) {
                studioPhotoGroupPickerSheet
            }
            .onChange(of: showPhotoGroupPicker) { _, isPresented in
                if !isPresented, pendingSocialCarouselOverflowAfterSlidesPickerDismiss {
                    pendingSocialCarouselOverflowAfterSlidesPickerDismiss = false
                    checkSocialCarouselOverflow()
                }
            }
            .onChange(of: hasSeenPlaceLayoutPicker) { _, isSeen in
                if isSeen, pendingOverflowAfterFirstRunLayoutPicker {
                    pendingOverflowAfterFirstRunLayoutPicker = false
                    checkSocialCarouselOverflow()
                }
            }
            .fullScreenCover(item: $editingSlideRef, onDismiss: {
                exportRenderAspectRatio = exportFormat.aspectRatio
            }) { ref in
                studioEmbeddedSlideEditor(initialIndex: ref.index, onDismissEditor: nil)
            }
            .sheet(isPresented: $showStudioCoverPicker) {
                SocialPostStudioCoverPickerSheet(
                    blog: blog,
                    studioCoverPhotoID: studioCoverPhotoID,
                    onPick: { photo in
                        showStudioCoverPicker = false
                        Task { await applyStudioCoverFromPick(photo) }
                    }
                )
            }
            .onChange(of: showStudioCoverPicker) { _, isPresented in
                #if DEBUG
                if isPresented {
                    print("[CarouselStudio] cover photo picker sheet presented")
                }
                #endif
            }
    }

    // MARK: - Layout

    /// Visible slide indices (same rule as the slide editor / export).
    private var studioVisibleSlideIndices: [Int] {
        slides.indices.filter { !isSlideHiddenBySiblingPIP(at: $0, in: slides) }
    }

    /// Second line of the “saved to Photos” alert for one slide.
    private func savedToPhotosDetailLine(for slide: CarouselSlide) -> String {
        switch slide.kind {
        case .cover:
            return "Cover photo slide saved to Photos."
        case .mapRoute:
            return "Map slide saved to Photos."
        case .placeIntroMap:
            return "Place map slide saved to Photos."
        case .placeStop:
            let raw = slide.placeStop?.placeTitle ?? ""
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? "Photo" : name
            return "\(label) slide saved to Photos."
        }
    }

    /// Slide editor or full-screen editor is visible — Photos save UX uses an in-editor alert (notifications).
    private var carouselStudioSlideEditorIsActiveForPhotosBanner: Bool {
        opensInEditMode || editingSlideRef != nil
    }

    private var shareJPEGHardCapConfirmationMessage: String {
        let cap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        let n = pendingShareJPEGHardCapSteps?.count ?? 0
        return "You have \(n) slides selected. Only up to \(cap) can be shared at once with social apps—the rest will not be included. You can share again for the next batch, or trim your carousel first."
    }

    /// Presents after the current run loop so alerts reliably appear when the action was invoked from a `Menu`.
    @MainActor
    private func presentShareJPEGHardCapConfirmation(fullSteps: [ShareJPEGExportStep]) {
        pendingShareJPEGHardCapSteps = fullSteps
        DispatchQueue.main.async {
            showShareJPEGHardCapConfirmation = true
        }
    }

    /// Presents save outcome in the embedded editor (`SlideTextEditorView`) vs the studio chrome menu path.
    @MainActor
    private func presentPhotosSaveOutcomeForStudio(title: String, message: String) {
        if carouselStudioSlideEditorIsActiveForPhotosBanner {
            NotificationCenter.default.post(
                name: .carouselStudioEditorExportBanner,
                object: nil,
                userInfo: ["title": title, "message": message]
            )
        } else {
            savedAlertTitle = title
            savedAlertBody = message
            showSavedAlert = true
        }
    }

    private func savedPhotosOutcomeStrings(
        requestedIndices: [Int],
        savedCount: Int,
        photosPackagesUsed: Int = 1
    ) -> (title: String, message: String) {
        let locationHint = "\n\nOpen the Photos app and check Library."
        guard savedCount > 0 else {
            return ("Nothing saved", "No images were added to Photos.")
        }
        let pkg = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        var messageSuffix = ""
        if photosPackagesUsed > 1 {
            messageSuffix += "\n\nPhotos were saved in \(photosPackagesUsed) batches of up to \(pkg) slides each to keep exports stable."
        }
        if requestedIndices.count == 1,
           let idx = requestedIndices.first,
           slides.indices.contains(idx) {
            let slide = slides[idx]
            let slideNum = studioVisibleSlideIndices.firstIndex(of: idx).map { $0 + 1 } ?? (idx + 1)
            return ("Slide \(slideNum) saved", savedToPhotosDetailLine(for: slide) + locationHint + messageSuffix)
        }
        if savedCount == 1 {
            return ("1 slide saved", "Your slide image was saved to Photos." + locationHint + messageSuffix)
        }
        return ("\(savedCount) slides saved", "Your slideshow images were saved to Photos." + locationHint + messageSuffix)
    }

    /// Saves one UIImage with PhotoKit; returns whether the Photos change succeeded.
    @MainActor
    private func carouselStudioSaveUIImageToPhotos(_ image: UIImage) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Horizontally-scrollable mode picker. Every card uses the same layout
    /// (icon + title + aspect pill + subtitle) at the same fixed width so the
    /// three options read as a consistent row; the selected card is
    /// differentiated only by its blue gradient + heavier shadow, not by
    /// size. Paged scroll snaps to the selected card when it changes.
    private var modeSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        modeCard(for: format).id(format.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20).padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: exportFormat) { _, sel in
                withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(sel.id, anchor: .center) }
            }
            .task { proxy.scrollTo(exportFormat.id, anchor: .center) }
        }
    }

    /// All three mode cards share this fixed-width layout (equal-sized
    /// when unselected). The selected state only changes the background
    /// gradient, border, and shadow — the structure stays identical.
    private func modeCard(for format: ExportFormat) -> some View {
        let isSel = exportFormat == format
        return Button {
            guard format != exportFormat else { return }
            if format.aspectRatio != exportFormat.aspectRatio {
                // Save current offsets for the format we're leaving.
                savedFormatOffsets[exportFormat.rawValue] = slides.map {(
                    primary: $0.textStyle.primary.offset,
                    secondary: $0.textStyle.secondary.offset,
                    pip: $0.pipOffset
                )}
                // Restore previously saved offsets for the incoming format, or reset to .zero.
                let restored = savedFormatOffsets[format.rawValue]
                for i in slides.indices {
                    let r = restored.flatMap { $0.indices.contains(i) ? $0[i] : nil }
                    slides[i].textStyle.primary.offset = r?.primary ?? .zero
                    slides[i].textStyle.secondary.offset = r?.secondary ?? .zero
                    slides[i].pipOffset = r?.pip ?? .zero
                }
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { exportFormat = format }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: format.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(format.title)
                        .font(.headline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(format.aspectRatio == (4.0 / 5.0) ? "4:5" : "9:16")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(isSel ? 0.28 : 0.14))
                        .clipShape(Capsule())
                }
                Text(format.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(isSel ? 0.88 : 0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(width: 230, alignment: .leading)
            .background(
                LinearGradient(
                    colors: isSel
                        ? [Color(red: 0.14, green: 0.5, blue: 1),
                           Color(red: 0.24, green: 0.71, blue: 1)]
                        : [Color(white: 0.2), Color(white: 0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isSel ? 0.35 : 0.12), lineWidth: isSel ? 1.2 : 1))
            .shadow(color: .black.opacity(isSel ? 0.26 : 0.12),
                    radius: isSel ? 12 : 6, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .scrollTransition(.animated.threshold(.visible(0.75))) { c, p in
            c.scaleEffect(p.isIdentity ? 1 : 0.96)
             .opacity(p.isIdentity ? 1 : 0.86)
        }
    }

    private var slidePreviewAndExport: some View {
        VStack(spacing: 0) {
            modeSelector.padding(.top, 14)
            Group {
                if exportFormat.isSingleSlide {
                    Text("Tap any slide to use it as your Reel cover")
                        .font(.subheadline).foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                } else {
                    HStack(spacing: 8) {
                        if hasMapSlidesInDeck {
                            mapToggleControl
                        }

                        Spacer(minLength: 0)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                let shouldDeselectAll = selectedSlides.count > 0
                                for i in slides.indices {
                                    slides[i].isSelected = !shouldDeselectAll
                                }
                            }
                        } label: {
                            Text(selectedSlides.isEmpty ? "Select all" : "Deselect all")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 10).padding(.bottom, 12)

            removePlacePhotoTipBanner

            ScrollViewReader { previewScrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(slides.indices, id: \.self) { index in
                            if !isSlideHiddenBySiblingPIP(at: index, in: slides) {
                                slideCard(slide: slides[index], index: index)
                                    .id(index)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                        removal: .opacity.combined(with: .scale(scale: 0.92))))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 6)
                }
                .onChange(of: previewRecenterAfterPIPNonce) { _, _ in
                    guard let idx = previewRecenterAfterPIPIndex else { return }
                    previewRecenterAfterPIPIndex = nil
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            previewScrollProxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
                .onChange(of: navigatePreviewToSlideIndex) { _, newVal in
                    guard let raw = newVal else { return }
                    navigatePreviewToSlideIndex = nil
                    DispatchQueue.main.async {
                        guard let idx = indexVisibleInEditorOrPreviewStrip(slides: slides, rawIndex: raw) else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            previewScrollProxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    private var hasPlaceStopInPreviewStrip: Bool {
        slides.contains { $0.kind == .placeStop }
    }

    private var hasMapSlidesInDeck: Bool {
        slides.contains { isCarouselStudioMapKind($0.kind) } || slideManagementDeckSnapshotBeforeRemovingMaps != nil
    }

    private var mapToggleControl: some View {
        let mapsRemoved = slideManagementRemoveMapsFromCarouselBinding.wrappedValue
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                slideManagementRemoveMapsFromCarouselBinding.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "map")
                    .font(.system(size: 12, weight: .semibold))
                Text("Maps")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(mapsRemoved ? .secondary : CarouselStudioChrome.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((mapsRemoved ? Color.white : CarouselStudioChrome.accent).opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                (mapsRemoved ? Color.white : CarouselStudioChrome.accent).opacity(mapsRemoved ? 0.15 : 0.25),
                lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: mapsRemoved)
    }

    /// Pill showing the selected slide count; tapping it opens the slide grid navigator.
    /// Turns orange with a warning icon when the count exceeds the typical social carousel limit (34).
    private var studioSlideCountBadge: some View {
        let count = selectedSlides.count
        let isOver = count > 34
        return Button { showPhotoGroupPicker = true } label: {
            HStack(spacing: 5) {
                if isOver {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
                Text("\(count) slide\(count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isOver ? .orange : .secondary)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isOver ? .orange : Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((isOver ? Color.orange : Color.white).opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                (isOver ? Color.orange : Color.white).opacity(isOver ? 0.35 : 0.15),
                lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOver)
    }

    @ViewBuilder
    private var removePlacePhotoTipBanner: some View {
        if !removePlacePhotoTipDismissed, hasPlaceStopInPreviewStrip {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("Remove a place photo from this carousel: swipe up on its card, long-press the card, or tap ⋯ then Remove from carousel. To add a photo back, open Slides Management (slide count button) and tap a dimmed card—same layout as the Download slide picker. In the full editor, press and hold the slide or use ⋯ above. Nothing is deleted from your trip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button {
                    removePlacePhotoTipDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss tip")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    /// Space around the preview slide before the card `clipShape` so PIP rotation, drop
    /// shadow, and the selection checkmark are less likely to be cut off in the strip.
    private func previewCardBleedInsets(slide: CarouselSlide) -> EdgeInsets {
        let isPIPPreview = slide.kind == .placeStop && slide.layout == .pip && !slide.pipImages.isEmpty
        if isPIPPreview {
            // PIP visible thumb hugs the slide's top-trailing corner; rotation + drop shadow
            // (~12pt) extend past slide bounds, so give the strip clip plenty of room above
            // and to the right of the slide. Bottom/leading just need normal shadow room.
            return EdgeInsets(top: 22, leading: 10, bottom: 14, trailing: 24)
        }
        return EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 10)
    }

    @ViewBuilder
    private func slideCard(slide: CarouselSlide, index: Int) -> some View {
        let poweredByMapWatermark = indexOfFirstCarouselStudioMapSlide(in: slides) == index
        VStack(spacing: 10) {
            SwipeUpToRemoveCard(
                slideKey: slide.id,
                isEnabled: slide.kind == .placeStop || isCarouselStudioMapKind(slide.kind),
                onRemove: {
                    if slide.kind == .placeStop {
                        excludePlaceSlide(at: index)
                    } else if isCarouselStudioMapKind(slide.kind) {
                        excludeMapSlide(at: index)
                    }
                }
            ) {
                CarouselSlideView(
                    slide: slide,
                    width: previewWidth,
                    aspectRatio: exportFormat.aspectRatio,
                    onToggleSelection: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if exportFormat.isSingleSlide {
                                // Radio behavior: selecting any slide deselects the others.
                                for i in slides.indices { slides[i].isSelected = (i == index) }
                            } else {
                                slides[index].isSelected.toggle()
                            }
                        }
                    },
                    showsSelectionChrome: true,
                    onCoverImageTap: (index == 0 && slide.kind == .cover)
                        ? { showStudioCoverPicker = true }
                        : nil,
                    clipsFloatingContentToRoundedSlideOutline: false,
                    showPoweredByBloggoMapWatermark: poweredByMapWatermark
                )
                .frame(width: previewWidth)
                // Extra margin before the card clip so PIP shadows / slight rotations stay visible
                // in the horizontal preview strip (the slide’s photo stack is still rounded inside).
                .padding(previewCardBleedInsets(slide: slide))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
            }

            HStack(spacing: 8) {
                Button { editingSlideRef = EditableSlideRef(index: index) } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if slide.kind == .placeStop {
                    Menu {
                        Button(role: .destructive) {
                            excludePlaceSlide(at: index)
                        } label: {
                            Label("Remove from carousel", systemImage: "minus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else if isCarouselStudioMapKind(slide.kind) {
                    Menu {
                        Button(role: .destructive) {
                            excludeMapSlide(at: index)
                        } label: {
                            Label("Remove from carousel", systemImage: "minus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                // Layout toggle — multi-photo places (payload restored after leaving Multi).
                if slide.kind == .placeStop, placeStopOffersLayoutModes(at: index, in: slides) {
                    HStack(spacing: 6) {
                        ForEach(CarouselSlideLayout.allCases) { layout in
                            let isActive = slide.layout == layout
                            Button {
                                setLayout(layout, forSlideAt: index)
                            } label: {
                                Image(systemName: layoutIcon(layout))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(isActive
                                        ? CarouselStudioChrome.accent
                                        : Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(
                                        isActive ? Color.white.opacity(0.35) : Color.white.opacity(0.1),
                                        lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: isActive)
                        }
                    }
                }
            }
            .frame(width: previewWidth)
        }
    }

    // MARK: - Layout

    /// Sets the layout for the slide at `index` and syncs sibling-slide selection.
    /// When switching to `.pip`, sibling slides for the same place stop are deselected
    /// because their photos are already visible in the PIP cluster. Switching back to
    /// `.single` re-selects them so they appear as individual slides again.
    private func setLayout(_ layout: CarouselSlideLayout, forSlideAt index: Int) {
        guard slides.indices.contains(index), slides[index].kind == .placeStop else { return }
        let stopID = slides[index].placeStop?.id
        // Match editor: avoid animating every slide property — preview strip cards
        // would spring while rows disappear from the horizontal list (harsh flicker).
        var layoutTxn = Transaction()
        layoutTxn.disablesAnimations = true
        withTransaction(layoutTxn) {
            if layout == .single {
                if slides[index].layout == .pip {
                    releaseMultiLayoutGrouping(primaryIndex: index, slides: &slides)
                } else if slides[index].layout == .split {
                    releaseSplitLayoutGrouping(splitIndex: index, slides: &slides)
                }
            }
            slides[index].layout = layout
            if layout == .split {
                slides[index].splitBottomImage = nil
                slides[index].splitBottomPhotoID = nil
                slides[index].splitBottomFraming = nil
            } else {
                slides[index].splitTopFraming = nil
                slides[index].splitBottomFraming = nil
            }
            if layout != .pip {
                slides[index].pipBackgroundRemoved = false
                slides[index].pipProcessedImages = []
                slides[index].pipThumbnailFramings = []
            }
            if layout == .pip {
                guard let stopID,
                      multiClusterCandidateIndices(from: index, stopID: stopID, in: slides).count > 1 else {
                    slides[index].layout = .single
                    return
                }
                applyMultiLayoutGrouping(primaryIndex: index, slides: &slides)
            } else if let stopID {
                for i in slides.indices where i != index {
                    guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                    slides[i].isSelected = true
                }
                if placeStopSiblingIndices(stopID: stopID, in: slides).count > 1 {
                    repopulatePipPayloadsForPlaceStop(stopID: stopID, slides: &slides)
                }
            }
        }
        if slides[index].layout == .pip {
            previewRecenterAfterPIPIndex = index
            previewRecenterAfterPIPNonce += 1
            if let stopID {
                Task { await rebuildPIPPayloadsForStop(stopID: stopID) }
            }
        } else if slides[index].layout == .split {
            autoFillSplitBottomIfTwoPhotos(forSlideAt: index)
        }
    }

    private func layoutIcon(_ layout: CarouselSlideLayout) -> String {
        switch layout {
        case .single: return "rectangle.portrait"
        case .pip: return "pip"
        case .split: return "rectangle.split.1x2"
        }
    }

    private func autoFillSplitBottomIfTwoPhotos(forSlideAt index: Int) {
        guard slides.indices.contains(index),
              slides[index].layout == .split,
              let stop = slides[index].placeStop else { return }
        let cluster = multiClusterCandidateIndices(from: index, stopID: stop.id, in: slides)
        guard cluster.count >= 2,
              let bottomID = slides[cluster[1]].heroPhotoID else { return }
        slides[index].splitBottomPhotoID = bottomID
        slides[index].splitBottomFraming = nil
        if let pipIdx = slides[index].pipPhotoIDs.firstIndex(of: bottomID),
           slides[index].pipImages.indices.contains(pipIdx) {
            slides[index].splitBottomImage = slides[index].pipImages[pipIdx]
        } else if let img = slides[cluster[1]].heroImage {
            slides[index].splitBottomImage = img
        }
        let stopID = stop.id
        for i in slides.indices where i != index {
            guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
            if slides[i].heroPhotoID == bottomID {
                slides[i].isSelected = false
            } else {
                slides[i].isSelected = true
            }
        }
    }

    // MARK: - Social carousel slide-count overflow

    /// Enables PIP for the first slide of every multi-photo place stop that is still in `.single` mode.
    private func autoEnablePIPForAllGroups() {
        var seenStopIDs = Set<UUID>()
        var txn = Transaction(); txn.disablesAnimations = true
        withTransaction(txn) {
            for i in slides.indices {
                guard slides[i].kind == .placeStop,
                      !slides[i].pipImages.isEmpty,
                      slides[i].layout == .single,
                      let stopID = slides[i].placeStop?.id,
                      !seenStopIDs.contains(stopID) else { continue }
                seenStopIDs.insert(stopID)
                guard multiClusterCandidateIndices(from: i, stopID: stopID, in: slides).count > 1 else { continue }
                slides[i].layout = .pip
                applyMultiLayoutGrouping(primaryIndex: i, slides: &slides)
            }
        }
    }

    /// Called after `loadSlides()` completes. If selected slide count > 34 (common social carousel cap),
    /// alerts so the user can deselect slides or merge photos with Multi (PIP) — we no longer auto-enable PIP,
    /// so each included photo stays its own slide for share/export order.
    private func checkSocialCarouselOverflow() {
        guard !exportFormat.isSingleSlide, selectedSlides.count > 34 else { return }
        let remaining = selectedSlides.count
        guard remaining > 34 else { return }
        socialCarouselOverflowSlideCount = remaining
        if showPhotoGroupPicker {
            pendingSocialCarouselOverflowAfterSlidesPickerDismiss = true
            return
        }
        // If the first-run layout picker sheet hasn't appeared yet, it will auto-present shortly
        // after load. Presenting the overflow alert at the same time causes SwiftUI to dismiss
        // one or both modals. Defer until hasSeenPlaceLayoutPicker flips (sheet dismissed).
        if opensInEditMode && !hasSeenPlaceLayoutPicker {
            pendingOverflowAfterFirstRunLayoutPicker = true
            return
        }
        Task { @MainActor in
            showSocialCarouselOverflowAlert = true
        }
    }

    // MARK: - Studio photo exclusion

    /// Removes a day-map slide from the carousel for this session.
    @MainActor
    private func excludeMapSlide(at index: Int) {
        guard slides.indices.contains(index),
              isCarouselStudioMapKind(slides[index].kind) else { return }
        slides[index].isSelected = false
    }

    /// Restores a previously hidden map slide to the carousel (sets isSelected = true).
    @MainActor
    private func restoreMapSlide(at index: Int) {
        guard slides.indices.contains(index),
              isCarouselStudioMapKind(slides[index].kind) else { return }
        slides[index].isSelected = true
    }

    /// Hides every day map (`.mapRoute`) and place intro map (`.placeIntroMap`) slide for this session.
    @MainActor
    private func excludeAllMapSlidesFromStudio() {
        let indices = slides.indices.filter { isCarouselStudioMapKind(slides[$0].kind) }
        guard !indices.isEmpty else { return }
        for i in indices {
            slides[i].isSelected = false
        }
    }

    /// Hides a place photo slide from the carousel (sets isSelected = false).
    /// The slide stays in the array and remains visible in Slides Management as a dimmed card.
    @MainActor
    private func excludePlaceSlide(at index: Int) {
        guard slides.indices.contains(index),
              slides[index].kind == .placeStop,
              let stop = slides[index].placeStop else { return }
        slides[index].isSelected = false
        Task { await rebuildPIPPayloadsForStop(stopID: stop.id) }
    }

    /// Restores a previously hidden place photo slide to the carousel (sets isSelected = true).
    @MainActor
    private func restorePlaceSlide(at index: Int) {
        guard slides.indices.contains(index),
              slides[index].kind == .placeStop,
              let stop = slides[index].placeStop else { return }
        slides[index].isSelected = true
        Task { await rebuildPIPPayloadsForStop(stopID: stop.id) }
    }

    private func restoreExcludedPhoto(stopID: UUID, photoID: UUID) {
        let key = studioExclusionKey(stop: stopID, photo: photoID)
        guard excludedStudioPhotoKeys.contains(key),
              let stop = freshPlaceStop(stopID: stopID, blog: blog),
              let photo = stop.photos.first(where: { $0.id == photoID }),
              photo.isIncluded,
              let day = blog.days.first(where: { d in d.placeStops.contains(where: { $0.id == stopID }) })
        else { return }

        var newExcluded = excludedStudioPhotoKeys
        newExcluded.remove(key)
        let insertAt = insertIndexForPlacePhotoInDay(
            day: day, blog: blog, stopID: stopID, photoID: photoID,
            slides: slides, excludedKeys: newExcluded
        )
        let ew = exportWidth
        let eh = exportHeight

        Task {
            let slide = await buildPlaceCarouselSlideForStudio(
                blog: blog, stop: stop, photo: photo,
                excludedKeys: newExcluded,
                exportWidth: ew, exportHeight: eh
            )
            await MainActor.run {
                guard let slide else { return }
                excludedStudioPhotoKeys = newExcluded
                let bounded = min(max(0, insertAt), slides.count)
                slides.insert(slide, at: bounded)
                reconcilePlaceSlidesOrderInDeck(
                    slides: &slides,
                    blog: blog,
                    excludedKeys: newExcluded,
                    placesOnlyMode: placesOnlyMode
                )
            }
            await rebuildPIPPayloadsForStop(stopID: stopID)
        }
    }

    @MainActor
    private func rebuildPIPPayloadsForStop(stopID: UUID) async {
        guard let stop = freshPlaceStop(stopID: stopID, blog: blog) else { return }
        let included = stop.photos.filter { $0.isIncluded }.filter {
            !excludedStudioPhotoKeys.contains(studioExclusionKey(stop: stop.id, photo: $0.id))
        }
        let indices = slides.indices.filter { slides[$0].kind == .placeStop && slides[$0].placeStop?.id == stopID }
        guard !indices.isEmpty else { return }

        for i in indices {
            slides[i].placeStop = stop
        }

        if included.count <= 1 {
            for i in indices {
                slides[i].layout = .single
                slides[i].pipImages = []
                slides[i].pipPhotoIDs = []
                slides[i].pipThumbnailFramings = []
                slides[i].pipBackgroundRemoved = false
                slides[i].pipProcessedImages = []
            }
            return
        }

        let orderedPresentIDs = included.map(\.id).filter { pid in
            // Include the photo if its slide is visible OR if it's PIP-hidden by a sibling
            // (so the sibling's PIP cluster keeps showing it). Exclude only user-hidden slides
            // (isSelected = false but NOT hidden by a sibling PIP).
            indices.contains { idx in
                slides[idx].heroPhotoID == pid
                && (slides[idx].isSelected || isSlideHiddenBySiblingPIP(at: idx, in: slides))
            }
        }

        // PIP thumbnails are shown small in the cluster (~150–300 px); 540 px gives retina
        // quality while using ~9× less memory than a full export-size decode.
        let pipThumbSize = CGSize(width: exportWidth, height: exportHeight)
        let pipPixelCap: CGFloat = 540
        var cache: [UUID: UIImage] = [:]
        for pid in Set(orderedPresentIDs) {
            guard let p = included.first(where: { $0.id == pid }) else { continue }
            var img: UIImage?
            if let localId = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !localId.isEmpty {
                img = await loadCarouselAssetImage(identifier: localId, size: pipThumbSize, pixelCap: pipPixelCap)
            }
            if img == nil {
                img = await loadRecapPhotoUIImage(photo: p, size: pipThumbSize, pixelCap: pipPixelCap)
            }
            if let img { cache[pid] = img }
        }

        for i in indices {
            // Only the primary PIP slide carries the pip cluster payload.
            // Single-layout siblings (PIP-hidden or user-hidden) must have pip data cleared;
            // otherwise the same photo appears as a thumbnail on multiple Slides Management cards.
            guard slides[i].layout == .pip, let hid = slides[i].heroPhotoID else {
                slides[i].pipPhotoIDs = []
                slides[i].pipImages = []
                slides[i].pipThumbnailFramings = []
                slides[i].pipBackgroundRemoved = false
                slides[i].pipProcessedImages = []
                continue
            }
            let pipIDs = multiClusterCandidateIndices(from: i, stopID: stopID, in: slides)
                .dropFirst()
                .compactMap { slides[$0].heroPhotoID }
            // Keep `pipPhotoIDs` and `pipImages` index-aligned: `compactMap` on images
            // alone shifts thumbnails when any neighbor fails to load, so the cluster
            // can show the wrong photo next to each id (and SwiftUI reuse looks worse).
            let pipAligned: [(UUID, UIImage)] = pipIDs.compactMap { pid in
                guard let img = cache[pid] else { return nil }
                return (pid, img)
            }
            slides[i].pipPhotoIDs = pipAligned.map(\.0)
            slides[i].pipImages = pipAligned.map(\.1)
            slides[i].pipThumbnailFramings = []
            slides[i].pipBackgroundRemoved = false
            slides[i].pipProcessedImages = []
            if slides[i].pipImages.isEmpty {
                slides[i].layout = .single
            }
        }
    }

    // MARK: - Load

    private func loadCoverHeroImageForStudio() async -> UIImage? {
        let exportSize = CGSize(width: exportWidth, height: exportHeight)
        let cap = max(exportWidth, exportHeight)
        if let pid = studioCoverPhotoID,
           let photo = blog.allIncludedPhotos.first(where: { $0.id == pid }) {
            return await loadRecapPhotoUIImage(photo: photo, size: exportSize, pixelCap: cap)
        }
        let trimmed = blog.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           let match = blog.allIncludedPhotos.first(where: {
               ($0.localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
           }) {
            return await loadRecapPhotoUIImage(photo: match, size: exportSize, pixelCap: cap)
        }
        if !trimmed.isEmpty {
            return await loadCarouselAssetImage(identifier: trimmed, size: exportSize, pixelCap: cap)
        }
        return nil
    }

    private func applyStudioCoverFromPick(_ photo: RecapPhoto) async {
        let exportSize = CGSize(width: exportWidth, height: exportHeight)
        let img = await loadRecapPhotoUIImage(photo: photo, size: exportSize, pixelCap: max(exportWidth, exportHeight))
        await MainActor.run {
            studioCoverPhotoID = photo.id
            if let i = slides.firstIndex(where: { $0.kind == .cover }) {
                slides[i].heroImage = img
            }
        }
    }

    private func advanceSlidePreparationProgress(completed: inout Int, total: Int, generation: UInt64) async {
        completed += 1
        let p = min(1.0, Double(completed) / Double(max(total, 1)))
        await MainActor.run {
            guard generation == loadSlidesGeneration else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                slidePreparationProgress = p
            }
        }
    }

    private func loadSlides() async {
        let generation = await MainActor.run {
            loadSlidesGeneration += 1
            isLoading = true
            slidePreparationProgress = 0
            return loadSlidesGeneration
        }
        let excludedSnapshot = await MainActor.run { excludedStudioPhotoKeys }
        // Read format on the main actor; the rest of this function may run off-main during awaits.
        let (isReelSingleSlide, formatAspectRatio) = await MainActor.run {
            (exportFormat.isSingleSlide, exportFormat.aspectRatio)
        }
        let prepTotal = socialPostStudioLoadSlidesPreparationUnitCount(
            blog: blog,
            excludedKeys: excludedSnapshot,
            placesOnlyMode: placesOnlyMode
        )
        var prepCompleted = 0
        var result: [CarouselSlide] = []

        let coverImg = await loadCoverHeroImageForStudio()
        await advanceSlidePreparationProgress(completed: &prepCompleted, total: prepTotal, generation: generation)
        result.append(CarouselSlide(id: "cover-\(blog.id.uuidString)", kind: .cover, isSelected: true,
                                    heroImage: coverImg, coverTitle: blog.title))

        var globalStopIndex = 0

        for (dayIdx, day) in blog.days.enumerated() {
            let dayNumber = dayIdx + 1
            let exportSize = CGSize(width: exportWidth, height: exportHeight)
            var markerImages: [UUID: UIImage] = [:]
            var placeSlides: [CarouselSlide] = []
            let drawableForMap = carouselDrawableStopsForStudioDay(day: day, excludedKeys: excludedSnapshot)
            var isFirstDrawableStop = true

            for stop in day.placeStops {
                let included = stop.photos.filter { $0.isIncluded }
                    .filter { !excludedSnapshot.contains(studioExclusionKey(stop: stop.id, photo: $0.id)) }
                guard !included.isEmpty else { continue }

                globalStopIndex += 1
                let stopIdx = globalStopIndex

                // Load all included photos for this stop upfront so we can populate PIP images.
                // Use `loadRecapPhotoUIImage` (same as cover) so cloud URLs + AppCapture ids work
                // when `localIdentifier` is missing — `loadSlides` previously only called Photos for
                // local assets, which blanked place slides and map markers on some devices/sync states.
                // Cap at the actual export pixel dimensions so PHImageManager doesn't decode
                // images at 3× screen scale (e.g. 3240×4050 instead of 1080×1350), which
                // was the primary cause of out-of-memory crashes on large trips.
                let exportPixelCap = max(exportWidth, exportHeight)
                var stopImages: [UIImage?] = []
                for photo in included {
                    let img = await loadRecapPhotoUIImage(photo: photo, size: exportSize, pixelCap: exportPixelCap)
                    await advanceSlidePreparationProgress(completed: &prepCompleted, total: prepTotal, generation: generation)
                    #if DEBUG
                    if img == nil {
                        let hasLocal = !(photo.localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let hasCloud = !(photo.cloudURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        print("[CarouselStudio] loadSlides: nil hero photo=\(photo.id) stop=\(stop.id) includedLocal=\(hasLocal) includedCloud=\(hasCloud)")
                    }
                    #endif
                    stopImages.append(img)
                }

                if let firstImg = stopImages.compactMap({ $0 }).first {
                    markerImages[stop.id] = firstImg
                } else {
                    #if DEBUG
                    print("[CarouselStudio] loadSlides: no marker image for stop=\(stop.id) place=\(stop.placeTitle) (all \(included.count) loads nil)")
                    #endif
                }

                // Blog day stack: skip intro for the first stop (day route map covers it). My Places: one intro map per place when possible.
                if shouldIncludePlaceIntroMapSlide(
                    placesOnlyMode: placesOnlyMode,
                    isFirstDrawableStop: isFirstDrawableStop,
                    stopID: stop.id,
                    drawableForMap: drawableForMap
                ),
                   let dIdx = drawableForMap.firstIndex(where: { $0.id == stop.id }) {
                    if await MainActor.run(body: { generation != loadSlidesGeneration }) { return }
                    let introCandidate = await MapSnapshotHelper.generateCarouselPlaceIntroSnapshot(
                        drawableDayStops: drawableForMap,
                        focusedDrawableIndex: dIdx,
                        logicalSize: exportSize,
                        lightweightMapTiles: placesOnlyMode
                    )
                    await advanceSlidePreparationProgress(completed: &prepCompleted, total: prepTotal, generation: generation)
                    if let introSnap = introCandidate {
                        let subtitle = stop.placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let teaser = [stop.placeNarrative, stop.overallStory, stop.noteText]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .first { !$0.isEmpty }
                        let introBottom = Array(stopImages.compactMap { $0 }.prefix(3))
                        let bottomIdx = stopImages.firstIndex(where: { $0 != nil }) ?? 0
                        let splitBottomUIImage = stopImages[bottomIdx] ?? introBottom.first
                        let splitBottomID = included.indices.contains(bottomIdx) ? included[bottomIdx].id : included.first?.id
                        placeSlides.append(CarouselSlide(
                            id: "place-map-\(stop.id.uuidString)",
                            kind: .placeIntroMap,
                            isSelected: true,
                            mapSnapshot: introSnap,
                            mapShortDateLine: day.monthDayStringForStoryBookRange(),
                            dayInfoLine1: stop.placeTitle,
                            dayInfoLine2: (subtitle?.isEmpty == false) ? subtitle : nil,
                            placeStop: stop,
                            dayStory: teaser,
                            textStyle: .placeStopDefault,
                            layout: .split,
                            splitBottomImage: splitBottomUIImage,
                            splitBottomPhotoID: splitBottomID,
                            placeIntroBottomPhotos: []
                        ))
                    }
                }
                isFirstDrawableStop = false

                for (photoIdx, photo) in included.enumerated() {
                    // Always emit a `.placeStop` for each included photo (including when the place intro map already shows a single photo).
                    let hero = stopImages[photoIdx]
                    // PIP payload for Multi: the next up to three photos after this hero (four per group total).
                    let pipPairs: [(UIImage, UUID)] = included.enumerated()
                        .compactMap { (idx, candidate) -> (UIImage, UUID)? in
                            guard idx > photoIdx,
                                  idx <= photoIdx + CarouselStudioMultiPhotoGroup.maxInsetThumbnails,
                                  let img = stopImages[idx] else { return nil }
                            return (img, candidate.id)
                        }
                        .map { $0 }
                    let pipImages: [UIImage] = pipPairs.map(\.0)
                    let pipPhotoIDs: [UUID] = pipPairs.map(\.1)
                    placeSlides.append(CarouselSlide(
                        id: "\(stop.id.uuidString)-\(photo.id.uuidString)", kind: .placeStop,
                        isSelected: true, heroImage: hero, placeStop: stop,
                        photoCaption: photo.caption,
                        isFirstPhotoOfStop: photoIdx == 0,
                        textStyle: .placeStopDefault,
                        pipImages: pipImages,
                        pipPhotoIDs: pipPhotoIDs, heroPhotoID: photo.id,
                        stopIndex: stopIdx))
                }
            }

            if !placesOnlyMode {
                let mapSnap = await MapSnapshotHelper.generatePhotoRouteSnapshot(
                    for: day.placeStops, markerImagesByStopId: markerImages,
                    size: CGSize(width: exportWidth, height: exportHeight), regionPadding: 0.13,
                    carouselDayFirstStopFocus: false)
                await advanceSlidePreparationProgress(completed: &prepCompleted, total: prepTotal, generation: generation)

                let bestStory = [day.dayNarrative, day.dayCaption]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }

                result.append(CarouselSlide(
                    id: "map-\(day.id.uuidString)", kind: .mapRoute, isSelected: true,
                    mapSnapshot: mapSnap, mapShortDateLine: day.monthDayStringForStoryBookRange(),
                    dayInfoLine1: "Day \(dayNumber)",
                    dayInfoLine2: day.dayStoryDateLine, dayStory: bestStory))
            }
            result.append(contentsOf: placeSlides)
        }

        if isReelSingleSlide {
            // Reel: keep only the cover slide selected by default.
            for i in result.indices { result[i].isSelected = (i == 0) }
        }
        // All @State touches must run on the main actor (async load work may finish off-main).
        await MainActor.run {
            guard generation == loadSlidesGeneration else { return }
            var deck = result
            reconcilePlaceSlidesOrderInDeck(
                slides: &deck,
                blog: blog,
                excludedKeys: excludedSnapshot,
                placesOnlyMode: placesOnlyMode
            )
            slides = deck
            exportRenderAspectRatio = formatAspectRatio
            slidePreparationProgress = 1
            isLoading = false
            // Always defer: checkSocialCarouselOverflow calls withTransaction inside autoEnablePIPForAllGroups,
            // which can flush the current transaction before showSocialCarouselOverflowAlert is set,
            // causing the alert to appear and immediately disappear on the isLoading→false transition.
            Task { @MainActor in
                guard generation == loadSlidesGeneration else { return }
                slideManagementDeckSnapshotBeforeRemovingMaps = nil
                checkSocialCarouselOverflow()
            }
        }
    }

    private func loadAssetImage(identifier: String, size: CGSize) async -> UIImage? {
        await loadCarouselAssetImage(identifier: identifier, size: size)
    }

    // MARK: - Export

    /// Ordered slide indices that match `selectedSlides` (PIP-hidden excluded; Reel uses first selected only).
    private func orderedExportSlideIndices() -> [Int] {
        orderedStudioExportSlideIndices(slides: slides, singleSlideExport: exportFormat.isSingleSlide)
    }

    private var largeExportMemoryAlertBinding: Binding<Bool> {
        Binding(
            get: { largeStudioExportMemoryGate != nil },
            set: { newVal in if !newVal { largeStudioExportMemoryGate = nil } }
        )
    }

    private var largeExportMemoryAlertTitle: String {
        switch largeStudioExportMemoryGate {
        case .saveToPhotos: return "Large save to Photos"
        case .pdf: return "Large PDF export"
        case .none: return ""
        }
    }

    private var largeExportMemoryAlertSlideCount: Int {
        switch largeStudioExportMemoryGate {
        case .saveToPhotos(let i), .pdf(let i): return i.count
        case .none: return 0
        }
    }

    private var largeExportMemoryAlertMessage: String {
        let count = largeExportMemoryAlertSlideCount
        let lim = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        return "This export includes \(count) slides (above the \(lim)-slide package size). Saves and PDFs split into batches of \(lim). This warning is about memory: reduce slides or merge photos with Multi (PIP) if the app struggles."
    }

    /// Single-photo stop with no `.placeStop` slide in the deck (photo only appeared on the place map slide).
    private func singlePhotoMissingPlaceSlideAfterRemovingPlaceMap(stopID: UUID) -> UUID? {
        guard let stop = freshPlaceStop(stopID: stopID, blog: blog) else { return nil }
        let included = stop.photos.filter(\.isIncluded)
        guard included.count == 1 else { return nil }
        let hasPlaceSlide = slides.contains {
            $0.kind == .placeStop && $0.placeStop?.id == stopID
        }
        guard !hasPlaceSlide else { return nil }
        return included[0].id
    }

    private func buildShareJPEGExportSteps(fromOrderedIndices indices: [Int], omitMapsFromShare: Bool) -> [ShareJPEGExportStep] {
        var steps: [ShareJPEGExportStep] = []
        var seenDeck = Set<Int>()
        var recoveredStops = Set<UUID>()
        for idx in indices {
            guard slides.indices.contains(idx),
                  !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { continue }
            let slide = slides[idx]
            if omitMapsFromShare && isCarouselStudioMapKind(slide.kind) {
                if slide.kind == .placeIntroMap,
                   let stopID = slide.placeStop?.id,
                   !recoveredStops.contains(stopID),
                   let photoID = singlePhotoMissingPlaceSlideAfterRemovingPlaceMap(stopID: stopID) {
                    recoveredStops.insert(stopID)
                    steps.append(.recoveredPlace(stopID: stopID, photoID: photoID))
                }
                continue
            }
            guard !seenDeck.contains(idx) else { continue }
            seenDeck.insert(idx)
            steps.append(.deckIndex(idx))
        }
        return steps
    }

    @MainActor
    private func requestShareJPEGToSheet(indices: [Int], omitMapsFromShare: Bool = false) async {
        guard !indices.isEmpty else { return }
        let steps = buildShareJPEGExportSteps(fromOrderedIndices: indices, omitMapsFromShare: omitMapsFromShare)
        guard !steps.isEmpty else { return }
        let shareCap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        if steps.count > shareCap {
            presentShareJPEGHardCapConfirmation(fullSteps: steps)
            return
        }
        await performUnbatchedShareJPEGExportSteps(steps)
    }

    @MainActor
    private func requestSaveToPhotos(indices: [Int]) async {
        guard !indices.isEmpty else { return }
        let pkgCap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        if indices.count > pkgCap {
            largeStudioExportMemoryGate = .saveToPhotos(indices: indices)
            return
        }
        await performSaveToPhotosStreaming(atIndices: indices)
    }

    @MainActor
    private func requestExportPDFToShare(indices: [Int]) async {
        guard !indices.isEmpty else { return }
        let pkgCap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        if indices.count > pkgCap {
            largeStudioExportMemoryGate = .pdf(indices: indices)
            return
        }
        await performExportPDFStreaming(atIndices: indices)
    }

    @MainActor
    private func performUnbatchedShareJPEGExportSteps(_ steps: [ShareJPEGExportStep]) async {
        let shareCap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        guard steps.count <= shareCap else { return }
        pdfExportQueuedIndexChunks = []
        pdfExportScheduledTotalChunks = 0
        showPDFExportNextContinuation = false
        isRendering = true
        defer { isRendering = false }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let pair = await exportJPEGURLsStreaming(steps: steps, into: tempDir, startingFileNumber: 1)
        guard !pair.urls.isEmpty else { return }
        shareItems = pair.urls
        showShareSheet = true
    }

    @MainActor
    private func performSaveToPhotosStreaming(atIndices indices: [Int]) async {
        guard !indices.isEmpty else {
            presentPhotosSaveOutcomeForStudio(
                title: "Nothing to save",
                message: "Choose at least one slide before downloading.")
            return
        }
        var auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if auth == .notDetermined {
            auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard auth == .authorized || auth == .limited else {
            presentPhotosSaveOutcomeForStudio(
                title: "Photos access needed",
                message: "Bloggo needs permission to add images to your library. You can enable it in Settings → Privacy & Security → Photos → Bloggo."
            )
            return
        }
        pdfExportQueuedIndexChunks = []
        pdfExportScheduledTotalChunks = 0
        showPDFExportNextContinuation = false
        let pkgSize = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        let chunks = carouselStudioChunkedSlideIndexGroups(indices: indices, chunkSize: pkgSize)
        isRendering = true
        defer { isRendering = false }
        let firstMapWatermarkIndex = indexOfFirstCarouselStudioMapSlide(in: slides)
        var savedOk = 0
        var anyRendered = false
        var anySaveFailed = false
        for chunk in chunks {
            var seenChunk = Set<Int>()
            for idx in chunk {
                guard !seenChunk.contains(idx), slides.indices.contains(idx),
                      !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { continue }
                seenChunk.insert(idx)
                guard let image = renderStudioSlideUIImageForExport(at: idx, firstMapWatermarkIndex: firstMapWatermarkIndex) else { continue }
                anyRendered = true
                let ok = await carouselStudioSaveUIImageToPhotos(image)
                if ok {
                    savedOk += 1
                } else {
                    anySaveFailed = true
                }
                CATransaction.flush()
                await Task.yield()
            }
        }
        if savedOk == 0 {
            let msg: String
            if anySaveFailed && anyRendered {
                msg = "Photos couldn’t save those images (storage or Photos permissions). Check Settings or free space and try again."
            } else if !anyRendered {
                msg = "No slide images could be prepared for saving."
            } else {
                msg = "Save failed unexpectedly. Check Photos permissions in Settings."
            }
            presentPhotosSaveOutcomeForStudio(title: "Couldn’t save to Photos", message: msg)
            return
        }
        let (title, baseMessage) = savedPhotosOutcomeStrings(
            requestedIndices: indices,
            savedCount: savedOk,
            photosPackagesUsed: chunks.count
        )
        var message = baseMessage
        if anySaveFailed {
            message += "\n\nSome slides could not be saved; \(savedOk) image(s) were added to Photos."
        }
        presentPhotosSaveOutcomeForStudio(title: title, message: message)
    }

    /// Splits slide indices into PDFs of at most `CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage` pages when needed.
    @MainActor
    private func performExportPDFStreaming(atIndices indices: [Int]) async {
        guard !indices.isEmpty else { return }
        pdfExportQueuedIndexChunks = []
        pdfExportScheduledTotalChunks = 0
        showPDFExportNextContinuation = false
        let limit = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        let chunks = carouselStudioChunkedSlideIndexGroups(indices: indices, chunkSize: limit)
        guard let first = chunks.first else { return }
        if chunks.count == 1 {
            await exportCarouselStudioPDFSliceToShare(sliceIndices: first, partOneBased: nil, totalParts: nil)
        } else {
            pdfExportQueuedIndexChunks = Array(chunks.dropFirst())
            pdfExportScheduledTotalChunks = chunks.count
            await exportCarouselStudioPDFSliceToShare(sliceIndices: first, partOneBased: 1, totalParts: chunks.count)
        }
    }

    @MainActor
    private func presentNextQueuedPDFExportSlice() async {
        guard !pdfExportQueuedIndexChunks.isEmpty else {
            pdfExportScheduledTotalChunks = 0
            return
        }
        let slice = pdfExportQueuedIndexChunks.removeFirst()
        let partDisplayed = pdfExportScheduledTotalChunks - pdfExportQueuedIndexChunks.count
        await exportCarouselStudioPDFSliceToShare(
            sliceIndices: slice,
            partOneBased: partDisplayed,
            totalParts: pdfExportScheduledTotalChunks
        )
    }

    @MainActor
    private func exportCarouselStudioPDFSliceToShare(
        sliceIndices: [Int],
        partOneBased: Int?,
        totalParts: Int?
    ) async {
        isRendering = true
        defer { isRendering = false }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let safeTitle = blog.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = safeTitle.isEmpty ? "Social_Post_Studio" : safeTitle
        let partMarker: String = {
            guard let p = partOneBased, let t = totalParts, t > 1 else { return "" }
            return "_part\(p)of\(t)"
        }()
        let pdfURL = tempDir.appendingPathComponent("\(baseName)\(partMarker)_slides.pdf")
        let doc = PDFDocument()
        let firstMapWatermarkIndex = indexOfFirstCarouselStudioMapSlide(in: slides)
        var seen = Set<Int>()
        var pageIdx = 0
        for idx in sliceIndices {
            guard !seen.contains(idx), slides.indices.contains(idx),
                  !isSlideHiddenBySiblingPIP(at: idx, in: slides) else { continue }
            seen.insert(idx)
            guard let image = renderStudioSlideUIImageForExport(at: idx, firstMapWatermarkIndex: firstMapWatermarkIndex) else { continue }
            if pageIdx % 2 == 0 { await Task.yield() }
            guard let page = PDFPage(image: image) else { continue }
            doc.insert(page, at: doc.pageCount)
            pageIdx += 1
            CATransaction.flush()
            await Task.yield()
        }
        guard doc.pageCount > 0, doc.write(to: pdfURL) else { return }
        shareItems = [pdfURL]
        showShareSheet = true
    }

    /// Renders one slide for export; runs inside an `autoreleasepool` on the main actor.
    @MainActor
    private func renderStudioSlideUIImageForExport(at index: Int, firstMapWatermarkIndex: Int?) -> UIImage? {
        guard slides.indices.contains(index),
              !isSlideHiddenBySiblingPIP(at: index, in: slides) else { return nil }
        let slide = slides[index]
        let mapIdx = firstMapWatermarkIndex ?? indexOfFirstCarouselStudioMapSlide(in: slides)
        return autoreleasepool {
            let view = CarouselSlideView(slide: slide, width: exportWidth,
                                         aspectRatio: exportRenderAspectRatio,
                                         onToggleSelection: {}, showsSelectionChrome: false,
                                         showPoweredByBloggoMapWatermark: mapIdx == index)
            let r = ImageRenderer(content: view)
            r.scale = 1.0
            return r.uiImage
        }
    }

    /// Renders a slide value for export (e.g. recovered place slide not present in `slides`).
    @MainActor
    private func renderStudioSlideUIImageForExport(slide: CarouselSlide) -> UIImage? {
        autoreleasepool {
            let view = CarouselSlideView(slide: slide, width: exportWidth,
                                         aspectRatio: exportRenderAspectRatio,
                                         onToggleSelection: {}, showsSelectionChrome: false,
                                         showPoweredByBloggoMapWatermark: false)
            let r = ImageRenderer(content: view)
            r.scale = 1.0
            return r.uiImage
        }
    }

    /// Writes JPEGs for export steps into `tempDir`, numbering files `slide_{n}.jpg` starting at `startingFileNumber`.
    @MainActor
    private func exportJPEGURLsStreaming(steps: [ShareJPEGExportStep], into tempDir: URL, startingFileNumber: Int) async -> (urls: [URL], nextFileNumber: Int) {
        let firstMapWatermarkIndex = indexOfFirstCarouselStudioMapSlide(in: slides)
        var urls: [URL] = []
        var n = startingFileNumber
        for step in steps {
            let image: UIImage?
            switch step {
            case .deckIndex(let idx):
                image = renderStudioSlideUIImageForExport(at: idx, firstMapWatermarkIndex: firstMapWatermarkIndex)
            case .recoveredPlace(let stopID, let photoID):
                guard let stop = freshPlaceStop(stopID: stopID, blog: blog),
                      let photo = stop.photos.first(where: { $0.id == photoID }) else {
                    continue
                }
                guard let built = await buildPlaceCarouselSlideForStudio(
                    blog: blog, stop: stop, photo: photo,
                    excludedKeys: excludedStudioPhotoKeys,
                    exportWidth: exportWidth, exportHeight: exportHeight
                ) else {
                    continue
                }
                image = renderStudioSlideUIImageForExport(slide: built)
            }
            guard let image,
                  let data = image.jpegData(compressionQuality: 0.92) else { continue }
            let url = tempDir.appendingPathComponent("slide_\(n).jpg")
            try? data.write(to: url)
            urls.append(url)
            n += 1
            CATransaction.flush()
            await Task.yield()
        }
        return (urls, n)
    }

    @MainActor private func saveToPhotos() async {
        await requestSaveToPhotos(indices: orderedExportSlideIndices())
    }

    @MainActor private func saveToPhotos(atIndices indices: [Int]) async {
        await requestSaveToPhotos(indices: indices)
    }

    @MainActor private func shareViaSheet() async {
        await requestShareJPEGToSheet(indices: orderedExportSlideIndices())
    }

    /// One PDF page per rendered studio slide; written under a dedicated temp folder so `cleanupTempFiles` removes only that directory.
    @MainActor private func exportSlidesPDFAndShare() async {
        await requestExportPDFToShare(indices: orderedExportSlideIndices())
    }

    /// One PDF page per rendered index (same render pipeline used by the download picker).
    @MainActor private func exportSlidesPDFAndShare(atIndices indices: [Int]) async {
        await requestExportPDFToShare(indices: indices)
    }

    private func cleanupTempFiles() {
        for url in shareItems.compactMap({ $0 as? URL }) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); break
        }
        shareItems = []
    }
}

// MARK: - Social Post Studio cover picker

/// Grid of every included blog photo so the user can change the **studio** cover only
/// (never `RecapBlogDetail.selectedCoverPhotoIdentifier`).
private struct SocialPostStudioCoverPickerSheet: View {
    let blog: RecapBlogDetail
    let studioCoverPhotoID: UUID?
    let onPick: (RecapPhoto) -> Void

    @Environment(\.dismiss) private var dismiss

    private var photos: [RecapPhoto] { blog.allIncludedPhotos }

    private var effectiveHighlightID: UUID? {
        if let studioCoverPhotoID { return studioCoverPhotoID }
        let trimmed = blog.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           let p = photos.first(where: {
               ($0.localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
           }) { return p.id }
        return nil
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView(
                        "No photos",
                        systemImage: "photo",
                        description: Text("Add photos to this blog to pick a cover for these slides.")
                    )
                } else {
                    ScrollView {
                        Text("Only the slides in Social Post Studio change. Your blog's saved cover stays the same.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(photos) { photo in
                                let isCurrent = photo.id == effectiveHighlightID
                                ZStack(alignment: .topTrailing) {
                                    RecapPhotoThumbnail(
                                        photo: photo,
                                        cornerRadius: 10,
                                        showIcon: false,
                                        targetSize: CGSize(width: 360, height: 360)
                                    )
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                isCurrent ? Color.blue : Color.white.opacity(0.12),
                                                lineWidth: isCurrent ? 2.5 : 1
                                            )
                                    )
                                    if isCurrent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, CarouselStudioChrome.accent)
                                            .padding(6)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(photo) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Cover for slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Add-photo picker

/// Sheet presented from the PIP cluster toolbar when the user taps "Add photo".
/// Shows a grid of the place's photos that aren't currently visible in the
/// cluster. Tapping a tile commits the selection and dismisses the sheet.
///
/// Kept intentionally lightweight: no multi-select, no search, no quality
/// Bottom sheet: tap the large hero backdrop in PIP edit mode to pick another
/// included photo from the same place as the featured (full-bleed) image.
private struct SwapHeroPhotoSheet: View {
    let placeStop: PlaceStop
    let heroPhotoID: UUID?
    let photos: [RecapPhoto]
    let onPick: (RecapPhoto) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView(
                        "No photos",
                        systemImage: "photo",
                        description: Text("Add photos to this place in your trip to swap the backdrop.")
                    )
                } else if photos.count == 1 {
                    ContentUnavailableView(
                        "Add another photo",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("When this place has more than one photo, you can choose which one appears large behind the layout.")
                    )
                } else {
                    ScrollView {
                        Text("Choose which photo fills the background. The current backdrop moves into the small photo strip.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(photos) { photo in
                                let isFeatured = photo.id == heroPhotoID
                                ZStack(alignment: .topTrailing) {
                                    AddPIPPhotoTile(photo: photo)
                                        .opacity(isFeatured ? 0.55 : 1)
                                    if isFeatured {
                                        Text("Main")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(CarouselStudioChrome.accent.opacity(0.95))
                                            .clipShape(Capsule())
                                            .padding(6)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isFeatured else { return }
                                    onPick(photo)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Swap main photo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(placeStop.placeTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

/// Multi (grouped or ungrouped): pick which place photo fills one inset slot.
/// Opened from the slide with a **double-tap** on an inset. Lists every stop photo
/// except ones already used in other visible insets; Photo library matches assets
/// to this place’s `RecapPhoto` rows by local identifier.
private struct ReplacePIPInsetPhotoSheet: View {
    let placeStop: PlaceStop
    /// Photos not already shown in another visible inset on this slide (hero may appear for swap).
    let eligiblePhotos: [RecapPhoto]
    let heroPhotoID: UUID?
    let onPick: (RecapPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var libraryItem: PhotosPickerItem?
    @State private var libraryMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var libraryAlertPresented: Binding<Bool> {
        Binding(
            get: { libraryMessage != nil },
            set: { if !$0 { libraryMessage = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            replacePIPInsetSheetMain
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text("Replace inset photo")
                                .font(.system(size: 15, weight: .semibold))
                            Text(placeStop.placeTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                            Label("Library", systemImage: "photo.on.rectangle.angled")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel("Choose from photo library")
                    }
                }
                .onChange(of: libraryItem) { _, newItem in
                    handleLibraryItemChange(newItem)
                }
                .alert("Photo library", isPresented: libraryAlertPresented) {
                    Button("OK", role: .cancel) { libraryMessage = nil }
                } message: {
                    Text(libraryMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var replacePIPInsetSheetMain: some View {
        if eligiblePhotos.isEmpty {
            ContentUnavailableView(
                "No more photos",
                systemImage: "photo.stack",
                description: Text("Every photo from this place is already in the cluster, or add more in trip photos.")
            )
        } else {
            ScrollView {
                Text(
                    "Double-tap an inset on the slide to open this picker. "
                        + "Tap Main to swap with the large hero. "
                        + "Photos already in other inset slots are hidden. "
                        + "Trip photos that are not included for the blog still appear when they belong to this place."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(eligiblePhotos) { photo in
                        replacePIPInsetPhotoCell(photo: photo)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func replacePIPInsetPhotoCell(photo: RecapPhoto) -> some View {
        let isMain = photo.id == heroPhotoID
        ZStack(alignment: .topTrailing) {
            AddPIPPhotoTile(photo: photo)
            if isMain {
                Text("Main")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(CarouselStudioChrome.accent.opacity(0.95))
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onPick(photo) }
    }

    private func handleLibraryItemChange(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        let lid = newItem.itemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        libraryItem = nil
        guard !lid.isEmpty else {
            libraryMessage = "Could not read that library photo."
            return
        }
        if let found = placeStop.photos.first(where: {
            $0.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) == lid
        }) {
            onPick(found)
            dismiss()
        } else {
            libraryMessage =
                "That image is not linked to this place yet. Add it to this stop in trip photos first, then pick it here."
        }
    }
}

/// Presented from the PIP toolbar when the user taps **Add Photos**. The caller
/// supplies the filtered eligible list; this sheet only renders thumbnails (same
/// lightweight flow as hero swap — no full Photos picker).
private struct AddPIPPhotoPickerSheet: View {
    let placeStop: PlaceStop
    let availablePhotos: [RecapPhoto]
    let onPick: (RecapPhoto) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if availablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No more photos",
                        systemImage: "photo.stack",
                        description: Text("Every photo from this place is already in the cluster.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(availablePhotos) { photo in
                                AddPIPPhotoTile(photo: photo)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onPick(photo) }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Add photo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(placeStop.placeTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

private struct SplitBottomPhotoPickerSheet: View {
    let selectedPhotoID: UUID?
    let availablePhotos: [RecapPhoto]
    let onPick: (RecapPhoto) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var gridHorizontalPadding: CGFloat { 16 }
    /// Space between the nav title and the first grid row (not the sheet chrome above
    /// the title — see `principalHeaderTopPadding`).
    private var gridTopPadding: CGFloat {
        UIScreen.main.bounds.height < 736 ? 8 : 12
    }
    private var gridBottomPadding: CGFloat { 16 }
    var body: some View {
        NavigationStack {
            Group {
                if availablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No eligible photos",
                        systemImage: "photo.stack",
                        description: Text("This place needs at least one extra included photo to fill the bottom slot.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(availablePhotos) { photo in
                                let isCurrent = photo.id == selectedPhotoID
                                AddPIPPhotoTile(photo: photo)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                isCurrent ? Color.white : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onPick(photo) }
                            }
                        }
                        .padding(.horizontal, gridHorizontalPadding)
                        .padding(.top, gridTopPadding)
                        .padding(.bottom, gridBottomPadding)
                    }
                }
            }
            .background(Color(red: 5/255, green: 10/255, blue: 48/255))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 5/255, green: 10/255, blue: 48/255), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Select bottom photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                if selectedPhotoID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            onClear()
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

/// Square thumbnail for a single `RecapPhoto`. Uses `loadRecapPhotoUIImage` so
/// PH assets, AppCapture ids, and **cloud-only** rows (no `localIdentifier` yet)
/// match what the editor loads when a photo is chosen — older devices / iCloud
/// libraries were stuck on the placeholder when only `cloudURL` was populated.
private struct AddPIPPhotoTile: View {
    let photo: RecapPhoto
    @State private var image: UIImage? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(white: 0.15))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard image == nil else { return }
        let loaded = await loadRecapPhotoUIImage(
            photo: photo,
            size: CGSize(width: 320, height: 320)
        )
        await MainActor.run { self.image = loaded }
    }
}

// MARK: - Preview strip swipe-up to remove

/// Wraps a preview slide card with a swipe-up gesture that removes the slide.
/// Designed to coexist with the parent horizontal `ScrollView`, the card's tap
/// (selection toggle), and the in-card buttons (Edit, ⋯). Vertical-dominant
/// drags (`|dy| > |dx|`) past `activationSlop` claim the gesture and reveal a
/// "Release to remove" pill; horizontal-dominant drags are ignored so the
/// outer ScrollView keeps paging. Reset cleanly via `slideKey` so a stale
/// in-flight drag from a removed slide can never linger on a reused card slot.
private struct SwipeUpToRemoveCard<Content: View>: View {
    /// Stable identity (e.g. `CarouselSlide.id`); changing this resets the wrapper's drag state.
    let slideKey: String
    let isEnabled: Bool
    let onRemove: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragHeight: CGFloat = 0
    /// True once the user moves enough vertically to "claim" the gesture for swipe-up.
    @State private var isVerticalSwipe: Bool = false
    @State private var didTrigger: Bool = false

    private let activationSlop: CGFloat = 10
    private let triggerThreshold: CGFloat = 72
    private let maxPull: CGFloat = 180
    /// If horizontal motion clearly dominates, cancel so the strip scrolls normally.
    private let horizontalCancelSlop: CGFloat = 22

    var body: some View {
        let liftedBy = max(0, -dragHeight)
        let progress = min(1, liftedBy / triggerThreshold)
        ZStack(alignment: .top) {
            content()
                .offset(y: dragHeight)
                .scaleEffect(1.0 - progress * 0.04, anchor: .center)
                .opacity(1.0 - progress * 0.35)

            if isEnabled, liftedBy > activationSlop {
                Label(progress >= 1 ? "Release to remove" : "Swipe up to remove",
                      systemImage: progress >= 1 ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        (progress >= 1 ? Color.red : Color.black.opacity(0.7))
                            .clipShape(Capsule())
                    )
                    .offset(y: dragHeight - 24)
                    .opacity(progress)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: progress >= 1)
            }
        }
        .contentShape(Rectangle())
        .studioPreviewStripSwipeGesture(isEnabled, swipeGesture)
        .contextMenu {
            if isEnabled {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from carousel", systemImage: "minus.circle")
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: dragHeight)
        .onChange(of: slideKey) { _, _ in
            dragHeight = 0
            isVerticalSwipe = false
            didTrigger = false
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEnabled, !didTrigger else { return }
                let dy = value.translation.height
                let dx = value.translation.width

                // Strong horizontal pan → user is scrolling the strip; abandon swipe-remove.
                if abs(dx) > horizontalCancelSlop, abs(dx) > abs(dy) * 1.15 {
                    if isVerticalSwipe || dragHeight != 0 {
                        isVerticalSwipe = false
                        dragHeight = 0
                    }
                    return
                }

                if !isVerticalSwipe {
                    // Start on clear upward intent; slightly looser than |dy|>|dx| so diagonals still work.
                    guard dy < -activationSlop else { return }
                    guard abs(dy) >= abs(dx) - 4 else { return }
                    isVerticalSwipe = true
                }

                guard isVerticalSwipe else { return }
                // Mid-gesture: bail if user steers hard sideways.
                if abs(dx) > abs(dy) + 28, abs(dx) > 26 {
                    isVerticalSwipe = false
                    dragHeight = 0
                    return
                }
                dragHeight = max(min(dy, 0), -maxPull)
            }
            .onEnded { _ in
                guard isEnabled, !didTrigger else { return }
                let shouldRemove = isVerticalSwipe && dragHeight <= -triggerThreshold
                isVerticalSwipe = false
                if shouldRemove {
                    didTrigger = true
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onRemove()
                    dragHeight = 0
                } else {
                    dragHeight = 0
                }
            }
    }
}

// MARK: - Slide grid navigator sheet

/// Two-column grid in **loadSlides** order. Uses the same **Download** slide card (preview, dim, corner check)
/// and grid metrics as `carouselStudioExportHubPhase == .pickDownloadSlides`.
private struct CarouselPhotoGroupPickerSheet: View {
    private enum SlidesManagementGridRow: Identifiable {
        case dayBanner(Int)
        case deck(SlidesManagementItem)

        var id: String {
            switch self {
            case .dayBanner(let d): return "day-banner-\(d)"
            case .deck(let item): return item.id
            }
        }
    }

    @Binding var slides: [CarouselSlide]
    let blog: RecapBlogDetail
    let excludedKeys: Set<String>
    let aspectRatio: CGFloat
    /// While `SocialPostStudioSheet.loadSlides()` runs (e.g. after toggling single-photo deck rules), summary counts use a synchronous estimate.
    let isDeckReloading: Bool
    /// Reel format exports a single selected slide; mirrors `loadSlides` reel branch for the summary badge.
    let isReelExport: Bool
    let onSelectSlide: (Int) -> Void
    let onRestoreExcludedPlacePhoto: ((UUID, UUID) -> Void)?
    let onExcludePlaceFromStudio: ((Int) -> Void)?
    let onExcludeMapFromStudio: ((Int) -> Void)?
    /// Toggle on removes all map slides from the deck (with snapshot restore when turned off). Parent owns snapshot state.
    @Binding var removeMapsFromCarousel: Bool
    /// After bulk include/exclude of place slides, parent should rebuild PIP payloads per affected stop.
    let onBulkSlidesExportSelectionChanged: (() -> Void)?
    /// My Places share deck — affects expected slide count while reloading.
    let placesOnlyMode: Bool
    @Environment(\.dismiss) private var dismiss

    @AppStorage("blogify.slidesManagementTip.dismissed") private var slidesManagementTipDismissed = false

    private var managementItems: [SlidesManagementItem] {
        makeSlidesManagementItems(blog: blog, slides: slides, excludedKeys: excludedKeys)
    }

    private var removedPlaceCount: Int {
        managementItems.filter {
            if case .placeRemovedFromDeck = $0.payload { return true }
            return false
        }
        .count
    }

    private var exportSelectedSlideCount: Int {
        slides.enumerated().reduce(0) { partial, pair in
            let (idx, slide) = pair
            guard slide.isSelected else { return partial }
            if isSlideHiddenBySiblingPIP(at: idx, in: slides) { return partial }
            return partial + 1
        }
    }

    private var slidesManagementExpectedDeckSlideCount: Int {
        expectedSocialPostStudioDeckSlideCountAfterReload(
            blog: blog,
            excludedKeys: excludedKeys,
            placesOnlyMode: placesOnlyMode
        )
    }

    private var slidesManagementDisplayedExportSelectedCount: Int {
        if isDeckReloading {
            let full = slidesManagementExpectedDeckSlideCount
            return isReelExport ? min(1, full) : full
        }
        return exportSelectedSlideCount
    }

    private var slidesManagementDisplayedVisibleDeckCount: Int {
        if isDeckReloading {
            return slidesManagementDisplayedExportSelectedCount
        }
        return slidesManagementVisibleDeckSlideCount
    }

    /// Deck indices that export / the pager show — excludes hidden and PIP-collapsed slides.
    private var slidesManagementVisibleDeckSlideCount: Int {
        slides.indices.filter { slides[$0].isSelected && !isSlideHiddenBySiblingPIP(at: $0, in: slides) }.count
    }

    private var mapSlidesInDeckCount: Int {
        slides.filter { isCarouselStudioMapKind($0.kind) && $0.isSelected }.count
    }

    private var hasAnyMapSlides: Bool {
        slides.contains(where: { isCarouselStudioMapKind($0.kind) })
    }

    private var slidesManagementNavigationSubtitle: String {
        "Edit slides and choose what appears in your post"
    }

    /// Day index (1-based) for grouping rows in Slides Management, when derivable from the slide or stop.
    private func slidesManagementExportDayNumber(slide: CarouselSlide) -> Int? {
        switch slide.kind {
        case .cover:
            return nil
        case .mapRoute:
            let line = slide.dayInfoLine1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard line.hasPrefix("Day") else { return nil }
            let afterKeyword = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = afterKeyword.prefix(while: { $0.isNumber })
            return Int(digits)
        case .placeIntroMap, .placeStop:
            guard let stop = slide.placeStop else { return nil }
            for (dIdx, d) in blog.days.enumerated() where d.placeStops.contains(where: { $0.id == stop.id }) {
                return dIdx + 1
            }
            return nil
        }
    }

    private func slidesManagementExportDayNumber(item: SlidesManagementItem) -> Int? {
        switch item.payload {
        case .cover:
            return nil
        case .map(let i), .placeMap(let i), .placeInDeck(let i):
            guard slides.indices.contains(i) else { return nil }
            return slidesManagementExportDayNumber(slide: slides[i])
        case .placeRemovedFromDeck(let stop, _):
            for (dIdx, d) in blog.days.enumerated() where d.placeStops.contains(where: { $0.id == stop.id }) {
                return dIdx + 1
            }
            return nil
        }
    }

    private var slidesManagementGridRows: [SlidesManagementGridRow] {
        var rows: [SlidesManagementGridRow] = []
        var lastBannerDay: Int?
        for item in managementItems {
            if let day = slidesManagementExportDayNumber(item: item) {
                if lastBannerDay != day {
                    if case .map = item.payload {
                        // Day header is rendered inside the map slide card itself.
                    } else {
                        rows.append(.dayBanner(day))
                    }
                    lastBannerDay = day
                }
            } else {
                lastBannerDay = nil
            }
            rows.append(.deck(item))
        }
        return rows
    }

    private var slidesManagementHasPlaceSlidesForBulkBar: Bool {
        slides.contains { $0.kind == .placeStop }
    }

    /// Place slides that appear as their own card in the deck (PIP / split siblings are omitted).
    private var slidesManagementVisiblePlaceSlideIndices: [Int] {
        slides.indices.filter { slides[$0].kind == .placeStop && !isSlideHiddenBySiblingPIP(at: $0, in: slides) }
    }

    private var slidesManagementAllPlaceSlidesSelected: Bool {
        let idxs = slidesManagementVisiblePlaceSlideIndices
        guard !idxs.isEmpty else { return false }
        return idxs.allSatisfy { slides[$0].isSelected }
    }

    private var slidesManagementNoPlaceSlidesSelected: Bool {
        let idxs = slidesManagementVisiblePlaceSlideIndices
        guard !idxs.isEmpty else { return true }
        return idxs.allSatisfy { !slides[$0].isSelected }
    }

    private func slidesManagementSetAllPlacePhotoSlidesSelected(_ selected: Bool) {
        for i in slides.indices where slides[i].kind == .placeStop {
            slides[i].isSelected = selected
        }
        onBulkSlidesExportSelectionChanged?()
    }

    @ViewBuilder
    private func slidesManagementDaySectionHeader(day: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Day \(day)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    /// Scrolls with the sheet: bulk include/exclude for **place photo** slides only (not sticky with the export summary).
    @ViewBuilder
    private var slidesManagementPlacePhotoBulkSection: some View {
        if slidesManagementHasPlaceSlidesForBulkBar {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        slidesManagementSetAllPlacePhotoSlidesSelected(true)
                    } label: {
                        Label("Select all", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(CarouselStudioChrome.accent)
                    .disabled(slidesManagementAllPlaceSlidesSelected)

                    Button {
                        slidesManagementSetAllPlacePhotoSlidesSelected(false)
                    } label: {
                        Label("Deselect all", systemImage: "circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(slidesManagementNoPlaceSlidesSelected)
                }
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Always-visible summary above the scrolling grid (counts scroll away in the old layout).
    private var slidesManagementPinnedSelectionBar: some View {
        let sel = slidesManagementDisplayedExportSelectedCount
        let visibleDeck = slidesManagementDisplayedVisibleDeckCount
        let cap = CarouselStudioExportHardLimit.maxSlidesPerShareOrPackage
        let overShare = sel > cap
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(sel)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overShare ? Color.orange : CarouselStudioChrome.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: sel)
                VStack(alignment: .leading, spacing: 3) {
                    Text("slides selected for export")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(visibleDeck) slides in carousel\(removedPlaceCount > 0 ? " · \(removedPlaceCount) removed" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: visibleDeck)
                }
                Spacer(minLength: 0)
            }
            if isDeckReloading {
                Text("Refreshing deck…")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            if removedPlaceCount > 0 {
                Text("\(removedPlaceCount) photo\(removedPlaceCount == 1 ? "" : "s") hidden from your post — tap a faded card below to add \(removedPlaceCount == 1 ? "it" : "them") back.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if overShare {
                Label(
                    "Sharing to social apps includes up to \(cap) slides at a time. Trim the deck or share in batches.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    init(
        slides: Binding<[CarouselSlide]>,
        blog: RecapBlogDetail,
        excludedKeys: Set<String>,
        aspectRatio: CGFloat,
        isDeckReloading: Bool,
        isReelExport: Bool,
        onSelectSlide: @escaping (Int) -> Void,
        onRestoreExcludedPlacePhoto: ((UUID, UUID) -> Void)? = nil,
        onExcludePlaceFromStudio: ((Int) -> Void)? = nil,
        onExcludeMapFromStudio: ((Int) -> Void)? = nil,
        removeMapsFromCarousel: Binding<Bool>,
        onBulkSlidesExportSelectionChanged: (() -> Void)? = nil,
        placesOnlyMode: Bool = false
    ) {
        _slides = slides
        self.blog = blog
        self.excludedKeys = excludedKeys
        self.aspectRatio = aspectRatio
        self.isDeckReloading = isDeckReloading
        self.isReelExport = isReelExport
        self.onSelectSlide = onSelectSlide
        self.onRestoreExcludedPlacePhoto = onRestoreExcludedPlacePhoto
        self.onExcludePlaceFromStudio = onExcludePlaceFromStudio
        self.onExcludeMapFromStudio = onExcludeMapFromStudio
        _removeMapsFromCarousel = removeMapsFromCarousel
        self.onBulkSlidesExportSelectionChanged = onBulkSlidesExportSelectionChanged
        self.placesOnlyMode = placesOnlyMode
    }

    /// Two columns; `GeometryReader` per cell uses the grid’s **proposed** width so cards never exceed the slot (avoids overlap).
    private let gridColumns = [
        GridItem(.flexible(minimum: 100), spacing: 12),
        GridItem(.flexible(minimum: 100), spacing: 12),
    ]

    private var hasSlideRemovalActions: Bool {
        onExcludePlaceFromStudio != nil || onExcludeMapFromStudio != nil
    }

    private func canExcludeSlide(at rawIndex: Int) -> Bool {
        guard slides.indices.contains(rawIndex) else { return false }
        switch slides[rawIndex].kind {
        case .placeStop: return onExcludePlaceFromStudio != nil
        case .mapRoute, .placeIntroMap: return onExcludeMapFromStudio != nil
        case .cover: return false
        }
    }

    private func performExclude(at rawIndex: Int) {
        guard slides.indices.contains(rawIndex) else { return }
        switch slides[rawIndex].kind {
        case .placeStop:
            onExcludePlaceFromStudio?(rawIndex)
        case .mapRoute, .placeIntroMap:
            onExcludeMapFromStudio?(rawIndex)
        case .cover:
            break
        }
    }

    private func slidesManagementFirstTextLine(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        for lineSub in t.split(whereSeparator: \.isNewline) {
            let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        return ""
    }

    private func slideKindLabel(for slide: CarouselSlide) -> String {
        switch slide.kind {
        case .cover: return "Cover"
        case .mapRoute:
            let day = slide.dayInfoLine1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let d = slide.mapShortDateLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if day.isEmpty { return d.isEmpty ? "Map" : d }
            return d.isEmpty ? day : "\(day) - \(d)"
        case .placeIntroMap:
            let d = slide.mapShortDateLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = slide.placeStop?.placeTitle ?? slide.dayInfoLine1 ?? ""
            let t = slidesManagementFirstTextLine(raw)
            if d.isEmpty { return t.isEmpty ? "Place map" : "Place map — \(t)" }
            return t.isEmpty ? "Place map - \(d)" : "Place map — \(t) · \(d)"
        case .placeStop:
            let raw = slide.placeStop?.placeTitle ?? ""
            let t = slidesManagementFirstTextLine(raw)
            return t.isEmpty ? "Place" : t
        }
    }

    private func placeNameLabel(from stop: PlaceStop) -> String {
        let t = slidesManagementFirstTextLine(stop.placeTitle)
        return t.isEmpty ? "Place" : t
    }

    @ViewBuilder
    private func slidesManagementCaption(ordinal1Based: Int, title: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(ordinal1Based)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }

    /// Cap raster width inside each grid cell (cell is usually narrower than the old 320 cap — keeps slides smaller + faster).
    private static let slidesManagementThumbMaxWidth: CGFloat = 200

    /// Small horizontal strip of PIP thumbnail images shown at the bottom of a PIP-layout slide card.
    @ViewBuilder
    private func slidesManagementPIPStrip(pipImages: [UIImage]) -> some View {
        let thumbSize: CGFloat = 30
        HStack(spacing: 4) {
            ForEach(Array(pipImages.prefix(3).enumerated()), id: \.offset) { _, img in
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize, height: thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func slidesManagementDeckItemRow(ordinal1Based: Int, rawIndex: Int, slide: CarouselSlide) -> some View {
        let countsTowardExportSelection = slides.indices.contains(rawIndex)
            && slides[rawIndex].isSelected
            && !isSlideHiddenBySiblingPIP(at: rawIndex, in: slides)
        let isUserHidden = (slide.kind == .placeStop || isCarouselStudioMapKind(slide.kind)) && !countsTowardExportSelection
        let canSplit = !isUserHidden && canExcludeSlide(at: rawIndex)
        let hasPIP = slide.kind == .placeStop && slide.layout == .pip && !slide.pipImages.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let w = max(60, min(geo.size.width, Self.slidesManagementThumbMaxWidth))
                ZStack(alignment: .bottomLeading) {
                    if isUserHidden {
                        // Slide is hidden from the carousel; tapping anywhere restores it.
                        CarouselStudioDownloadStylePickCard(
                            slide: slide,
                            width: w,
                            aspectRatio: aspectRatio,
                            isInCarousel: false,
                            mode: .singleAction { performExclude(at: rawIndex) }
                        )
                    } else if canSplit {
                        CarouselStudioDownloadStylePickCard(
                            slide: slide,
                            width: w,
                            aspectRatio: aspectRatio,
                            isInCarousel: countsTowardExportSelection,
                            mode: .splitOpenInSlideRemoveFromCorner(
                                onOpen: { onSelectSlide(rawIndex) },
                                onRemoveFromDeck: { performExclude(at: rawIndex) }
                            )
                        )
                    } else {
                        CarouselStudioDownloadStylePickCard(
                            slide: slide,
                            width: w,
                            aspectRatio: aspectRatio,
                            isInCarousel: countsTowardExportSelection,
                            mode: .singleAction { onSelectSlide(rawIndex) }
                        )
                    }
                    if hasPIP {
                        slidesManagementPIPStrip(pipImages: slide.pipImages)
                    }
                }
                .frame(width: w)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            slidesManagementCaption(
                ordinal1Based: ordinal1Based,
                title: slideKindLabel(for: slide)
            )
        }
    }

    /// Session-excluded place: download-style unselected card; full-card tap adds back. Loads hero like `loadSlides`.
    private struct SlidesManagementRemovedSessionRow: View {
        let blog: RecapBlogDetail
        let stop: PlaceStop
        let photo: RecapPhoto
        let aspectRatio: CGFloat
        let onRestore: () -> Void
        @State private var hero: UIImage? = nil

        private var previewSlide: CarouselSlide {
            let stopIdx = globalStopIndexInBlog(blog: blog, stopID: stop.id) ?? 1
            let firstIncludedID = stop.photos.first(where: { $0.isIncluded })?.id
            return CarouselSlide(
                id: "slides-mgmt-removed-\(stop.id)-\(photo.id)", kind: .placeStop,
                isSelected: true, heroImage: hero, placeStop: stop, photoCaption: photo.caption,
                isFirstPhotoOfStop: photo.id == firstIncludedID,
                textStyle: .placeStopDefault, pipImages: [], pipPhotoIDs: [],
                heroPhotoID: photo.id, stopIndex: stopIdx
            )
        }

        var body: some View {
            GeometryReader { geo in
                let w = max(60, min(geo.size.width, CarouselPhotoGroupPickerSheet.slidesManagementThumbMaxWidth))
                CarouselStudioDownloadStylePickCard(
                    slide: previewSlide,
                    width: w,
                    aspectRatio: aspectRatio,
                    isInCarousel: false,
                    mode: .singleAction(onRestore)
                )
                .frame(width: w)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .task {
                if hero != nil { return }
                let w: CGFloat = 640
                let h = w / max(0.1, aspectRatio)
                if let img = await loadRecapPhotoUIImage(photo: photo, size: CGSize(width: w, height: h)) {
                    await MainActor.run { hero = img }
                }
            }
        }
    }

    @ViewBuilder
    private func slidesManagementRemovedItemRow(ordinal1Based: Int, stop: PlaceStop, photo: RecapPhoto) -> some View {
        let restore = onRestoreExcludedPlacePhoto
        VStack(alignment: .leading, spacing: 0) {
            if let restore {
                SlidesManagementRemovedSessionRow(
                    blog: blog,
                    stop: stop,
                    photo: photo,
                    aspectRatio: aspectRatio,
                    onRestore: { restore(stop.id, photo.id) }
                )
                slidesManagementCaption(
                    ordinal1Based: ordinal1Based,
                    title: placeNameLabel(from: stop),
                )
            }
        }
    }

    @ViewBuilder
    private func slidesManagementItemView(_ item: SlidesManagementItem) -> some View {
        let ord = item.ordinal
        switch item.payload {
        case .cover(rawIndex: let i):
            if slides.indices.contains(i) {
                slidesManagementDeckItemRow(ordinal1Based: ord, rawIndex: i, slide: slides[i])
            }
        case .map(rawIndex: let i):
            if slides.indices.contains(i) {
                slidesManagementDeckItemRow(ordinal1Based: ord, rawIndex: i, slide: slides[i])
            }
        case .placeMap(rawIndex: let i):
            if slides.indices.contains(i) {
                slidesManagementDeckItemRow(ordinal1Based: ord, rawIndex: i, slide: slides[i])
            }
        case .placeInDeck(rawIndex: let i):
            if slides.indices.contains(i) {
                slidesManagementDeckItemRow(ordinal1Based: ord, rawIndex: i, slide: slides[i])
            }
        case .placeRemovedFromDeck(stop: let stop, photo: let photo):
            slidesManagementRemovedItemRow(ordinal1Based: ord, stop: stop, photo: photo)
        }
    }

    private var slidesManagementTipBody: String {
        if onRestoreExcludedPlacePhoto != nil, hasSlideRemovalActions {
            "Tap a slide to edit it in the carousel. Tap the checkmark on a place or map to hide it from your post—your photos stay in the trip. Faded slides are hidden; tap one to add it back."
        } else if hasSlideRemovalActions {
            "Tap a slide to edit it in the carousel. Tap the checkmark on a place or map to hide it from your post. Hidden slides stay on this page—tap a faded card to add it back."
        } else {
            "Tap any slide to open it in the editor."
        }
    }

    @ViewBuilder
    private var slidesManagementTipBanner: some View {
        if !slidesManagementTipDismissed {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick tips")
                        .font(.title3.weight(.semibold))
                    Text(slidesManagementTipBody)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Got it") {
                    slidesManagementTipDismissed = true
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
        }
    }

    private var slidesManagementNavBarTitle: some View {
        VStack(spacing: 1) {
            Text("Slides Management")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(slidesManagementNavigationSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var slidesManagementGridOrEmpty: some View {
        if managementItems.isEmpty {
            Text("No slides in this carousel.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(slidesManagementGridRows) { row in
                    switch row {
                    case .dayBanner(let day):
                        slidesManagementDaySectionHeader(day: day)
                            .gridCellColumns(2)
                    case .deck(let item):
                        slidesManagementItemView(item)
                    }
                }
            }
            .padding(.horizontal, 0)
        }
    }

    private var slidesManagementScrollContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            slidesManagementTipBanner
            slidesManagementPlacePhotoBulkSection
            if hasAnyMapSlides {
                Toggle("Remove maps from carousel", isOn: $removeMapsFromCarousel)
                    .font(.body)
                    .tint(CarouselStudioChrome.accent)
                Text(
                    removeMapsFromCarousel
                        ? "Turn off to put all day maps and place maps back (restores the deck to its state before you turned this on)."
                        : "Turn on to hide all map slides at once. You can still hide or restore individual maps with the check in the corner."
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            slidesManagementGridOrEmpty
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                slidesManagementPinnedSelectionBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                ScrollView {
                    slidesManagementScrollContent
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }
}

// MARK: - Numeric helpers

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let d = pow(10.0, CGFloat(places)); return (self * d).rounded() / d
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

private extension View {
    @ViewBuilder
    func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}
