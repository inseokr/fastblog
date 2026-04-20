// CarouselStudioSheet.swift
// fastblog

import PDFKit
import Photos
import SwiftUI

// MARK: - Asset loading

/// Loads a `PHAsset` image by local identifier at the requested size. Shared
/// between `SocialPostStudioSheet` (initial slide load) and `SlideTextEditorView`
/// (loading a new photo into the PIP cluster via the "Add photo" picker). Kept
/// at file scope so both callers use identical request options and there's no
/// duplicated photo-framework boilerplate to drift out of sync.
private func loadCarouselAssetImage(identifier: String, size: CGSize) async -> UIImage? {
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
    let maxPixel: CGFloat = 3072
    let target: CGSize = {
        guard rawW > maxPixel || rawH > maxPixel else {
            return CGSize(width: rawW, height: rawH)
        }
        let r = maxPixel / max(rawW, rawH)
        return CGSize(width: floor(rawW * r), height: floor(rawH * r))
    }()

    return await withCheckedContinuation { cont in
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
            #if DEBUG
            if img == nil {
                let err = info?[PHImageErrorKey] as? Error
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool
                print("[CarouselStudio] loadCarouselAssetImage: nil image cancelled=\(cancelled) degraded=\(String(describing: degraded)) err=\(String(describing: err)) target=\(target)")
            }
            #endif
            cont.resume(returning: img)
        }
    }
}

/// Full-resolution load for carousel / Social Post Studio. Supports Photos assets,
/// on-disk app captures (`AppCapturePhotoService` ids), and signed cloud URLs.
private func loadRecapPhotoUIImage(photo: RecapPhoto, size: CGSize) async -> UIImage? {
    if let lid = photo.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
        if lid.hasPrefix(AppCapturePhotoService.prefix) {
            let img = await MainActor.run {
                AppCapturePhotoService.shared.loadImage(identifier: lid)
            }
            #if DEBUG
            if img == nil { print("[CarouselStudio] loadRecapPhotoUIImage: AppCapture nil photo=\(photo.id)") }
            #endif
            return img
        }
        let img = await loadCarouselAssetImage(identifier: lid, size: size)
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
    case placeStop
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
    var id: String { rawValue }
}

/// How inset PIP thumbnails are arranged when `CarouselSlideLayout` is `.pip`.
enum CarouselPIPClusterStackStyle: String, CaseIterable, Identifiable {
    /// Thumbnails stacked top-to-bottom along the trailing edge (default; anchored top-trailing).
    case vertical
    /// Thumbnails in a row, growing toward the leading edge from the top-trailing corner.
    case horizontal
    var id: String { rawValue }
}

/// Pill-shaped backdrop behind a text block. Tapping the block in the editor
/// cycles through these states (default → dark → light → default …). Purely
/// visual — dragging the block never changes this (see tap-vs-drag threshold
/// in `DraggableTextBlock`).
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
    case color  = "Color"
    case font   = "Font Style"
    case format = "Format"
    case size   = "Font Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .color:  return "paintpalette.fill"
        case .font:   return "textformat"
        case .size:   return "textformat.size"
        case .format: return "bold.italic.underline"
        }
    }
}

/// Categories in the bottom tab bar when the PIP photo cluster is selected.
/// Reorder opens the inset drag-to-reorder module for the cluster stack; Border
/// picks the outline color painted around each thumbnail.
/// Add and remove are separate scrollable pills — see `pipAddPhotosTabButton` /
/// `pipRemovePhotosTabButton`.
private enum PIPStyleCategory: String, CaseIterable, Identifiable {
    case order  = "Reorder"
    case border = "Border"
    case size   = "Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .order:  return "arrow.up.arrow.down"
        case .border: return "paintpalette.fill"
        case .size:   return "aspectratio"
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
    /// Pill backdrop behind the text. Default `.none` preserves the original
    /// "text only" look for every pre-existing slide; cycled by tapping the
    /// block in the editor.
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

/// Resolves the foreground color for a text layer. When the block's pill
/// backdrop is active we force white (on dark pill) or black (on light pill)
/// regardless of the user's picked `textColor`, so the text stays readable
/// against the pill. `naturalOpacity` preserves the per-row hierarchy (e.g.
/// subtitle at 0.8) whether or not a pill is showing.
private func studioEffectiveForegroundColor(_ style: TextBlockStyle,
                                            naturalOpacity: Double = 1.0) -> Color {
    switch style.background {
    case .none:      return style.textColor.color.opacity(naturalOpacity)
    case .darkPill:  return Color.white.opacity(naturalOpacity)
    case .lightPill: return Color.black.opacity(naturalOpacity)
    }
}

/// Paints a rounded-rect pill behind text content when the block's
/// `background` is set. When `.none`, the modifier is a no-op (no padding,
/// no fill) so slides that have never touched the pill feature render
/// identically to before.
private struct StudioTextPillBackground: ViewModifier {
    let style: TextBlockStyle
    let cornerRadius: CGFloat
    let hPadding: CGFloat
    let vPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, style.background == .none ? 0 : hPadding)
            .padding(.vertical, style.background == .none ? 0 : vPadding)
            .background(fill)
    }

    @ViewBuilder
    private var fill: some View {
        switch style.background {
        case .none:
            Color.clear
        case .darkPill:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.75))
        case .lightPill:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.75))
        }
    }
}

private extension View {
    /// Apply the optional rounded-pill backdrop for a text block.
    func studioTextPill(_ style: TextBlockStyle,
                        cornerRadius: CGFloat,
                        hPadding: CGFloat,
                        vPadding: CGFloat) -> some View {
        modifier(StudioTextPillBackground(style: style,
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

struct CarouselSlide: Identifiable {
    let id: String
    let kind: CarouselSlideKind
    var isSelected = true
    var heroImage: UIImage?
    var coverTitle: String?
    var mapSnapshot: UIImage?
    var dayInfoLine1: String?
    var dayInfoLine2: String?
    var placeStop: PlaceStop?
    var dayTitle: String?
    var photoCaption: String?
    var dayStory: String?
    var textStyle: TextOverlayStyle = TextOverlayStyle()
    /// When true, the primary text block (title / heading / place name) is hidden on this slide.
    var isPrimaryHidden: Bool = false
    /// When true, the secondary text block (story / caption) is hidden on this slide.
    var isSecondaryHidden: Bool = false
    /// Layout variant — only meaningful for `.placeStop` slides.
    var layout: CarouselSlideLayout = .single
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
    /// Outline color painted around each PIP thumbnail. Defaults to white to
    /// preserve the classic "photo print" look; users can change it per slide
    /// in the edit toolbar when the PIP cluster is selected.
    var pipBorderColor: StudioTextColor = .white
    /// Whether the PIP thumbnail outline is drawn at all. When `false`, each
    /// thumbnail renders without a border regardless of `pipBorderColor`. Users
    /// toggle this via the "no border" option at the start of the Border
    /// color strip.
    var pipBorderEnabled: Bool = true
    /// How many PIP thumbnails to render (1 ... 3). Clamped at render time
    /// against the number of available images, so this can be lowered without
    /// discarding image data — raising it back restores the earlier photos.
    var pipVisibleCount: Int = 3
    /// Row vs column layout for the inset PIP thumbnails (`.pip` only).
    var pipClusterStackStyle: CarouselPIPClusterStackStyle = .vertical
    /// Scales PIP thumbnail footprint relative to the default (~30% of slide width).
    /// Driven from the multi-photo toolbar Size strip; `.pip` layout only.
    var pipClusterSizeScale: CGFloat = 1.0
    /// `RecapPhoto.id` of the current hero photo. Lets the "Add photo" picker
    /// exclude it from the available list so users don't duplicate the hero
    /// into the cluster.
    var heroPhotoID: UUID? = nil
    /// 1-based sequential stop number across all days; when set, a white POI marker is shown before the place name.
    var stopIndex: Int? = nil

    var caption: String? {
        guard kind == .placeStop, let placeStop else { return nil }
        return [photoCaption, placeStop.placeNarrative, placeStop.overallStory, placeStop.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Returns `true` when the slide at `index` is a `.placeStop` slide in `.single`
/// layout whose photo is already represented inside a sibling's PIP cluster
/// (same `placeStop.id`, `layout == .pip`). The preview and export pipelines
/// hide these so activating multi-photo collapses the stop down to its single
/// PIP slide; flipping the sibling back to `.single` resurfaces them.
private func isSlideHiddenBySiblingPIP(at index: Int, in slides: [CarouselSlide]) -> Bool {
    guard slides.indices.contains(index) else { return false }
    let slide = slides[index]
    guard slide.kind == .placeStop,
          slide.layout == .single,
          let stopID = slide.placeStop?.id else { return false }
    return slides.contains { other in
        other.id != slide.id &&
        other.kind == .placeStop &&
        other.layout == .pip &&
        other.placeStop?.id == stopID
    }
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

private func insertIndexForPlacePhotoInDay(
    day: RecapBlogDay,
    stopID: UUID,
    photoID: UUID,
    slides: [CarouselSlide],
    excludedKeys: Set<String>
) -> Int {
    let expected = expectedPlaceTuples(day: day, excludedKeys: excludedKeys)
    guard let targetSlot = expected.firstIndex(where: { $0.stop == stopID && $0.photo == photoID }) else {
        return slides.count
    }
    let mapSlideId = "map-\(day.id.uuidString)"
    guard let mapIdx = slides.firstIndex(where: { $0.id == mapSlideId }) else { return slides.count }
    let afterMap = slides.index(after: mapIdx)
    let nextMap = slides[afterMap...].firstIndex(where: { $0.kind == .mapRoute }) ?? slides.endIndex
    let dayPlaceRange = afterMap..<nextMap
    var matched = 0
    for s in 0..<targetSlot {
        let slot = expected[s]
        if slides[dayPlaceRange].contains(where: {
            $0.kind == .placeStop && $0.placeStop?.id == slot.stop && $0.heroPhotoID == slot.photo
        }) {
            matched += 1
        }
    }
    return afterMap + matched
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

    var stopImages: [UIImage?] = []
    for p in included {
        var img: UIImage?
        if let localId = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !localId.isEmpty {
            img = await loadCarouselAssetImage(identifier: localId,
                                               size: CGSize(width: exportWidth, height: exportHeight))
        }
        if img == nil {
            img = await loadRecapPhotoUIImage(photo: p, size: CGSize(width: exportWidth, height: exportHeight))
        }
        stopImages.append(img)
    }

    let hero = stopImages[photoIdx]
    let pipPairs: [(UIImage, UUID)] = included.enumerated()
        .compactMap { (idx, candidate) -> (UIImage, UUID)? in
            guard idx != photoIdx, let img = stopImages[idx] else { return nil }
            return (img, candidate.id)
        }
        .prefix(3)
        .map { $0 }
    let heroPhoto = included[photoIdx]
    return CarouselSlide(
        id: "\(stop.id.uuidString)-\(heroPhoto.id.uuidString)",
        kind: .placeStop,
        isSelected: true,
        heroImage: hero,
        placeStop: stop,
        photoCaption: heroPhoto.caption,
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
/// 1. `DraggableTextBlock.clamped(proposed:)` / `DraggablePIPCluster.clampedOffset`
///    shrink the allowed slide area so the block's visual rect stays inside the slide.
/// 2. Each anchored overlay in `CarouselSlideView` pads its draggable block by the
///    same amount so the block's *natural* (anchor) rect already sits inside that
///    clamp region — avoiding a first-tap "nudge" when `savedOffset == .zero`.
///
/// Set to `0` so blocks can sit flush on the left/right/top/bottom edges. Rubber-band
/// on finger lift is avoided by clamping the **displayed** offset during the gesture
/// (`displayPointOffset`), not only on `onEnded`.
private let studioTextBlockEdgeInset: CGFloat = 0

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
    /// more than `tapSlop` points — i.e. it was a tap, not a drag. Used by
    /// the editor to cycle the block's pill backdrop without reacting to
    /// drag motion.
    var onTap: () -> Void = {}
    let content: () -> Content

    @GestureState private var liveDrag: CGSize = .zero
    /// Block frame at its natural (anchor-based) position in the slide coord space,
    /// used only for drag clamping. Captured once at `.zero` offset.
    @State private var naturalRect: CGRect?
    /// Snapshot of `isSelected` taken at the first `onChanged` of a gesture, used
    /// so taps only cycle the pill backdrop when the block was *already* selected
    /// before the finger went down. Without this, tapping an unselected block
    /// would both select it AND cycle its pill style in one gesture.
    @State private var wasSelectedAtGestureStart: Bool = false
    /// True from first `onChanged` until `onEnded` — gates the snapshot above so
    /// we only capture on press-start, not on every drag update.
    @State private var didBeginGesture: Bool = false

    /// `savedOffset` converted from a normalized fraction into absolute points for the
    /// current `slideBounds`. This is what `.offset()` actually consumes.
    private var savedPointOffset: CGSize {
        CGSize(width: savedOffset.width * slideBounds.width,
               height: savedOffset.height * slideBounds.height)
    }

    /// In-slide offset actually applied (clamped every frame). Using raw `liveDrag`
    /// here made blocks follow the finger past valid bounds, then snap inward on lift.
    private var displayPointOffset: CGSize {
        clamped(proposed: CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        ))
    }

    var body: some View {
        content()
            .background(naturalRectCapture)
            .overlay(editingRing)
            .contentShape(Rectangle())
            .offset(x: displayPointOffset.width, y: displayPointOffset.height)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
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
                        // We route taps to `onTap` (e.g. cycle pill backdrop) and
                        // *don't* rewrite `savedOffset`, so a tap can never nudge
                        // the block's committed position.
                        let tapSlop: CGFloat = 6
                        let moved = max(abs(value.translation.width),
                                        abs(value.translation.height))
                        let beganSelected = wasSelectedAtGestureStart
                        didBeginGesture = false
                        wasSelectedAtGestureStart = false
                        if moved < tapSlop {
                            // Only cycle the pill backdrop if the block was already
                            // selected before this tap. A first tap on an unselected
                            // block just selects it — it must not also flip the style.
                            if beganSelected { onTap() }
                        } else {
                            let proposedPoints = CGSize(
                                width: savedPointOffset.width + value.translation.width,
                                height: savedPointOffset.height + value.translation.height
                            )
                            let clampedPoints = clamped(proposed: proposedPoints)
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
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var naturalRectCapture: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { captureNaturalRect(from: geo) }
                .onChange(of: geo.size) { _, _ in captureNaturalRect(from: geo) }
                // Story/Reel (9:16) slides resize when the formatting toolbar
                // opens/closes. The block's own intrinsic size does not always
                // change with the slide, so we must also recapture on
                // `slideBounds` changes — otherwise the cached natural rect
                // stays in the old coord space, and drag clamping writes a
                // committed offset that doesn't match the live rendering.
                .onChange(of: slideBounds) { _, _ in captureNaturalRect(from: geo) }
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
    /// natural rect makes `clamped(proposed:)` reject otherwise-valid drags and causes
    /// committed offsets to render in the wrong spot, which reads as "my move didn't save."
    private func captureNaturalRect(from geo: GeometryProxy) {
        let current = geo.frame(in: .named(studioSlideCoordSpace))
        guard current.width > 0, current.height > 0 else { return }
        naturalRect = current
    }

    @ViewBuilder
    private var editingRing: some View {
        if isEditingText {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isSelected
                        ? Color(red: 0.14, green: 0.52, blue: 1.0)
                        : Color.white.opacity(0.35),
                    style: isSelected
                        ? StrokeStyle(lineWidth: 2.0)
                        : StrokeStyle(lineWidth: 1.0, dash: [5, 3])
                )
                .padding(-3)
        }
    }

    /// Constrains the proposed offset so the block's visual rect stays inside `slideBounds`.
    private func clamped(proposed: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }

        let bounds = slideBounds.insetBy(dx: studioTextBlockEdgeInset,
                                         dy: studioTextBlockEdgeInset)
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

private func mapRouteStoryVisible(_ slide: CarouselSlide) -> Bool {
    !(slide.dayStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Whether the place-stop slide has any top-leading secondary text to show.
/// The secondary block renders the place subtitle (city, country) at the top —
/// so the top gradient is gated on that, not on the primary block.
private func placeSubtitleVisible(_ slide: CarouselSlide) -> Bool {
    guard let sub = slide.placeStop?.placeSubtitle else { return false }
    return !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// PIP cluster default placement and clamping rules.
///
/// The cluster has **no internal padding** so its measured frame equals the visible
/// thumbnail rect. That makes two things work correctly at the same time:
///   1. Drag-clamping in `DraggablePIPCluster.clampedOffset` uses the visible rect,
///      so the user can drag PIP **all the way to the slide's top-right corner**
///      (Edit Slides complaint: "PIP can't get closer to the right corner").
///   2. At default `pipOffset == .zero`, the visible thumb hugs the slide's
///      top-trailing corner — no hidden padding pushing it inward (Social Post
///      Studio complaint: "PIP got cut on top" was actually PIP being shoved
///      down by `top + rotation` padding).
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
    /// Fires on a true tap (no drag motion) — the editor uses it to cycle
    /// the block's pill backdrop without reacting to accidental drag motion.
    var onBlockTap: ((SlideBlockID) -> Void)? = nil
    /// Edit-mode write-back: commit a new PIP cluster offset. Nil in read-only (preview/export) use.
    var onUpdatePIPOffset: ((CGSize) -> Void)? = nil
    /// Multi-photo layout only: fired when the user taps the large hero backdrop (areas not covered
    /// by text blocks or the PIP cluster). Opens the hero-swap picker in `SlideTextEditorView`.
    var onTapHeroBackdrop: (() -> Void)? = nil
    /// When set, tapping the cover hero (behind title chrome) runs this — e.g. studio cover picker
    /// in Social Post Studio preview, or the same picker from Carousel Studio (`SlideTextEditorView`).
    var onCoverImageTap: (() -> Void)? = nil
    /// When `true` (default), floating overlays use the slide’s rounded-rect outline. For
    /// `.placeStop` + `.pip`, only the **background** stack is clipped so the inset cluster
    /// (rotation + shadow) is not shaved off; other kinds still get one outer clip. When
    /// `false`, only the photo/gradient stack is clipped — used for small studio previews.
    var clipsFloatingContentToRoundedSlideOutline: Bool = true

    private var height: CGFloat { width / aspectRatio }
    private let heroImageScale: CGFloat = 1.12
    private var slideBounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

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

    /// Photo, map snapshot, gradients, and (in PIP edit mode) the hero tap catcher.
    @ViewBuilder
    private var slideBackgroundStack: some View {
        ZStack {
            // ── Backgrounds ───────────────────────────────────────────
            switch slide.kind {
            case .cover:
                coverBackground
                LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.3), .clear],
                               startPoint: .bottom, endPoint: .top)
                    .frame(width: width, height: height)
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

            case .mapRoute:
                mapRouteBackground
                if !slide.isPrimaryHidden {
                    LinearGradient(colors: [.black.opacity(0.6), .clear],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                        .frame(width: width, height: height)
                }
                if mapRouteStoryVisible(slide), !slide.isSecondaryHidden {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .init(x: 0.5, y: 0.52), endPoint: .bottom)
                        .frame(width: width, height: height)
                }

            case .placeStop:
                coverBackground
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
            }
        }
    }

    var body: some View {
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
            if slide.kind == .cover, !slide.isPrimaryHidden, let title = slide.coverTitle, !title.isEmpty {
                DraggableTextBlock(
                    id: .primary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .primary,
                    savedOffset: offsetBinding(for: .primary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.primary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.primary) }
                ) {
                    Text(title)
                        .font(.system(size: width * 0.085 * slide.textStyle.primary.sizeScale,
                                      weight: studioFontWeight(base: .heavy,
                                                               isBold: slide.textStyle.primary.isBold),
                                      design: slide.textStyle.primary.fontDesign.design))
                        .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary))
                        .lineLimit(3)
                        .multilineTextAlignment(
                            slide.textStyle.primary.resolvedMultilineAlignment(fallback: .center))
                        .studioTextFormat(slide.textStyle.primary)
                        .studioTextPill(slide.textStyle.primary,
                                        cornerRadius: width * 0.055,
                                        hPadding: width * 0.04,
                                        vPadding: width * 0.022)
                        .padding(.horizontal, width * 0.038)
                }
            }
        }
        // Map heading — top-leading
        .overlay(alignment: .topLeading) {
            if slide.kind == .mapRoute, !slide.isPrimaryHidden {
                DraggableTextBlock(
                    id: .primary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .primary,
                    savedOffset: offsetBinding(for: .primary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.primary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.primary) }
                ) {
                    VStack(alignment: slide.textStyle.primary.alignment.stackAlignment(fallback: .leading),
                           spacing: 4) {
                        if let l1 = slide.dayInfoLine1 {
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
                }
                // Nudge the block inward by the same amount the clamp enforces,
                // so a fresh `savedOffset == .zero` already renders at the
                // clamp's resting position (no visible snap on first tap).
                .padding(studioTextBlockEdgeInset)
            }
        }
        // Map story — bottom-leading
        .overlay(alignment: .bottomLeading) {
            let storyText = (slide.dayStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slide.kind == .mapRoute, !slide.isSecondaryHidden, !storyText.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    savedOffset: offsetBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.secondary) }
                ) {
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
                }
                .padding(studioTextBlockEdgeInset)
            }
        }
        // Place name + caption — bottom-leading
        .overlay(alignment: .bottomLeading) {
            if slide.kind == .placeStop, !slide.isPrimaryHidden {
                if let placeStop = slide.placeStop {
                    DraggableTextBlock(
                        id: .primary,
                        isEditingText: isEditingText,
                        isSelected: selectedBlockID == .primary,
                        savedOffset: offsetBinding(for: .primary),
                        slideBounds: slideBounds,
                        onSelect: { onSelectBlock?(.primary) },
                        onDragStart: { onBlockDragStart?() },
                        onDragEnd: { onBlockDragEnd?() },
                        onTap: { onBlockTap?(.primary) }
                    ) {
                        VStack(alignment: slide.textStyle.primary.alignment.stackAlignment(fallback: .leading),
                               spacing: 4) {
                            HStack(alignment: .center, spacing: 6) {
                                if slide.stopIndex != nil {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: width * 0.062 * slide.textStyle.primary.sizeScale,
                                                      weight: .medium))
                                        .foregroundStyle(.white)
                                        .symbolRenderingMode(.monochrome)
                                }
                                Text(placeStop.placeTitle)
                                    .font(.system(size: width * 0.065 * slide.textStyle.primary.sizeScale,
                                                  weight: studioFontWeight(base: .bold,
                                                                           isBold: slide.textStyle.primary.isBold),
                                                  design: slide.textStyle.primary.fontDesign.design))
                                    .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.primary))
                                    .lineLimit(2)
                                    .multilineTextAlignment(
                                        slide.textStyle.primary.resolvedMultilineAlignment(fallback: .leading))
                                    .studioTextFormat(slide.textStyle.primary)
                            }
                            let primaryCaption = (slide.caption ?? "")
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
                                        slide.textStyle.primary.resolvedMultilineAlignment(fallback: .leading))
                                    .studioTextFormat(slide.textStyle.primary)
                            }
                        }
                        .studioTextPill(slide.textStyle.primary,
                                        cornerRadius: width * 0.045,
                                        hPadding: width * 0.032,
                                        vPadding: width * 0.02)
                        .padding(width * 0.038)
                    }
                    .padding(studioTextBlockEdgeInset)
                } else {
                    Text("Missing place data")
                        .font(.system(size: width * 0.05, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(width * 0.038)
                        .padding(studioTextBlockEdgeInset)
                }
            }
        }
        // Place subtitle (city, country) — top-leading
        .overlay(alignment: .topLeading) {
            let subtitleText = (slide.placeStop?.placeSubtitle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if slide.kind == .placeStop, !slide.isSecondaryHidden, !subtitleText.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    savedOffset: offsetBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onTap: { onBlockTap?(.secondary) }
                ) {
                    Text(subtitleText)
                        .font(.system(size: width * 0.048 * slide.textStyle.secondary.sizeScale,
                                      weight: studioFontWeight(base: .regular,
                                                               isBold: slide.textStyle.secondary.isBold),
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(studioEffectiveForegroundColor(slide.textStyle.secondary,
                                                                        naturalOpacity: 0.85))
                        .lineLimit(1)
                        .multilineTextAlignment(
                            slide.textStyle.secondary.resolvedMultilineAlignment(fallback: .leading))
                        .studioTextFormat(slide.textStyle.secondary)
                        .studioTextPill(slide.textStyle.secondary,
                                        cornerRadius: width * 0.038,
                                        hPadding: width * 0.03,
                                        vPadding: width * 0.018)
                        .padding(width * 0.038)
                }
                .padding(studioTextBlockEdgeInset)
            }
        }
        // PIP thumbnail cluster — top-trailing (same anchor in Edit Slides + Social Post Studio)
        .overlay(alignment: .topTrailing) {
            if slide.kind == .placeStop, slide.layout == .pip, !slide.pipImages.isEmpty {
                DraggablePIPCluster(
                    savedOffset: pipOffsetBinding,
                    slideBounds: slideBounds,
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() },
                    onSelect: { onSelectBlock?(.pipCluster) },
                    images: slide.pipImages,
                    pipPhotoIDs: slide.pipPhotoIDs,
                    slideWidth: width,
                    borderColor: slide.pipBorderEnabled ? slide.pipBorderColor.color : .clear,
                    visibleCount: slide.pipVisibleCount,
                    stackStyle: slide.pipClusterStackStyle,
                    pipSizeScale: slide.pipClusterSizeScale,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .pipCluster
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
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
        .clipCarouselPostcardOutline(
            clipsFloatingContentToRoundedSlideOutline && !pipClusterNeedsUnclippedFloatingChrome
        )
        .opacity(slide.isSelected ? 1.0 : 0.72)
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

    private var mapRouteBackground: some View {
        Group {
            if let image = slide.mapSnapshot {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(red: 12/255, green: 16/255, blue: 33/255)
            }
        }
        .frame(width: width, height: height).clipped()
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
    /// Parallel to `images` for visible slots; stable `ForEach` identity when reordering.
    var pipPhotoIDs: [UUID] = []
    let slideWidth: CGFloat
    /// Outline color painted around each thumbnail. Defaults to white.
    var borderColor: Color = .white
    /// Maximum number of thumbnails to render (1 ... 3). Further clamped by
    /// the number of supplied images, so at most `min(images.count, visibleCount)`
    /// tiles ever appear.
    var visibleCount: Int = 3
    var stackStyle: CarouselPIPClusterStackStyle = .vertical
    /// 1.0 = default thumbnail width; clamped in the editor before assignment.
    var sizeScale: CGFloat = 1.0

    private var thumbW: CGFloat { slideWidth * 0.30 * sizeScale }
    private var thumbH: CGFloat { thumbW * 0.72 }
    private let rotations: [Double] = [1.5, -1.0, 1.8]

    private struct PIPThumbTile: Identifiable {
        let id: AnyHashable
        let image: UIImage
        /// Stack position (0,1,2) for rotation styling — not the photo's identity.
        let slot: Int
    }

    private var shownThumbnails: [PIPThumbTile] {
        let clamped = max(0, min(visibleCount, min(images.count, 3)))
        return (0..<clamped).map { i in
            let id: AnyHashable = (i < pipPhotoIDs.count) ? pipPhotoIDs[i] : i
            return PIPThumbTile(id: id, image: images[i], slot: i)
        }
    }

    var body: some View {
        Group {
            switch stackStyle {
            case .vertical:
                VStack(alignment: .trailing, spacing: 5) { pipThumbnails }
            case .horizontal:
                HStack(alignment: .bottom, spacing: 5) { pipThumbnails }
            }
        }
        // No internal top/trailing padding: cluster frame = visible thumbs, so the user can drag
        // PIP all the way into the top-right corner and the studio default sits flush to it.
        .animation(.easeInOut(duration: 0.2), value: stackStyle)
    }

    @ViewBuilder
    private var pipThumbnails: some View {
        ForEach(shownThumbnails) { tile in
            Image(uiImage: tile.image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbW, height: thumbH)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 2.2)
                )
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                .rotationEffect(.degrees(rotations[tile.slot % rotations.count]))
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
    let slideWidth: CGFloat
    var borderColor: Color = .white
    var visibleCount: Int = 3
    var stackStyle: CarouselPIPClusterStackStyle = .vertical
    var pipSizeScale: CGFloat = 1.0
    /// True while the slide is in the full-screen text editor; enables the
    /// selection ring and routes taps through `onSelect`.
    var isEditingText: Bool = false
    /// True when `selectedBlock == .pipCluster` in the editor.
    var isSelected: Bool = false

    @GestureState private var liveDrag: CGSize = .zero
    @State private var naturalRect: CGRect?

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
                       visibleCount: visibleCount,
                       stackStyle: stackStyle,
                       sizeScale: pipSizeScale)
            .background(naturalRectCapture)
            .overlay(selectionRing)
            .contentShape(Rectangle())
            .offset(x: displayPointOffset.width, y: displayPointOffset.height)
            // Use minimumDistance: 0 in the editor so taps can select the
            // cluster (mirrors `DraggableTextBlock`'s gesture). Outside the
            // editor, keep the original 4pt threshold so PIP never accidentally
            // swallows taps meant for the slide selection chrome.
            .highPriorityGesture(
                DragGesture(minimumDistance: isEditingText ? 0 : 4,
                            coordinateSpace: .local)
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onChanged { _ in onDragStart() }
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
                        onDragEnd()
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isEditingText {
            // Cluster frame is the visible thumb rect; expand the ring by a few points so
            // it visually hugs the tiles without sitting on top of them.
            let ringBreathing: CGFloat = 4
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected
                        ? Color(red: 0.14, green: 0.52, blue: 1.0)
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
                .onChange(of: slideBounds) { _, _ in captureNaturalRect(from: geo) }
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
        let bounds = slideBounds.insetBy(dx: studioTextBlockEdgeInset, dy: studioTextBlockEdgeInset)
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
    /// Cover slide only: open the blog photo grid to change the slide hero (studio / editor).
    let onRequestStudioCoverPhotoPick: (() -> Void)?
    /// Which horizontal page this edit surface represents (`slides` index).
    let slidePageIndex: Int

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
                // Tap-to-cycle: default → dark pill → light pill → default.
                // Guarded by the drag-vs-tap threshold in `DraggableTextBlock`
                // so drags never flip the backdrop mid-reposition. PIP taps
                // don't cycle anything — their tap is already consumed by
                // `onSelect` on the cluster, which routes through `onSelectBlock`.
                guard id == .primary || id == .secondary else { return }
                recordUndoSnapshot()
                withAnimation(.easeInOut(duration: 0.18)) {
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
            onTapHeroBackdrop: {
                guard slide.kind == .placeStop, slide.layout == .pip else { return }
                onRequestHeroSwap(slidePageIndex)
            },
            onCoverImageTap: (slide.kind == .cover ? onRequestStudioCoverPhotoPick : nil)
        )
        .coordinateSpace(.named(studioSlideCoordSpace))
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

// MARK: - Full-Screen Text Editor

/// Share / save / PDF from the editor nav bar — implemented by `SocialPostStudioSheet`.
struct SlideTextEditorExportActions {
    let share: () async -> Void
    let saveToPhotos: () async -> Void
    let exportPDF: () async -> Void
    let exportActionsDisabled: () -> Bool
}

struct SlideTextEditorView: View {
    @Binding var slides: [CarouselSlide]
    let initialIndex: Int
    let aspectRatio: CGFloat
    /// Nav bar `…` menu (share / save / PDF); parent owns sheets, alerts, and export rendering.
    let exportActions: SlideTextEditorExportActions
    /// Mirrors parent `SocialPostStudioSheet.isRendering` so export progress covers the editor when presented in `fullScreenCover`.
    @Binding var exportInProgress: Bool
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
    /// Which PIP category (Reorder / Border / Size) is currently open. Parallels
    /// `activeStyleCategory` but for the photo-cluster toolbar that shows when
    /// `selectedBlock == .pipCluster`. Kept separate from `activeStyleCategory`
    /// so switching between a text block and the PIP block resets panel state.
    @State private var activePIPCategory: PIPStyleCategory? = nil
    /// True while the "Add photo" picker sheet is presented. Nil-able to work
    /// with `.sheet(isPresented:)`. The picker reads `currentSlide?.placeStop`
    /// and the exclusion set live, so no extra context needs to be captured.
    @State private var showsAddPhotoPicker: Bool = false
    /// PIP layout: pick another place photo to feature as the large backdrop.
    @State private var showsHeroPhotoSwapSheet: Bool = false
    /// Slide index captured when opening `showsHeroPhotoSwapSheet` (stable if user changes pages).
    @State private var heroSwapSlideIndex: Int?
    /// Ensures `pushUndoSnapshot()` runs once at the start of a PIP size drag (coalesced undo).
    @State private var pipClusterSizeSliderUndoPrimed = false
    /// Disables horizontal slide paging while the user touches a text block (see `SlideEditPage`).
    @State private var locksHorizontalSlidePaging = false
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
    @State private var inlineTextDraft = ""
    /// Secondary draft for the place caption field shown beneath the place name
    /// when editing a placeStop primary block.
    @State private var inlineCaptionDraft = ""
    @FocusState private var isInlineTextEditorFocused: Bool
    @FocusState private var isInlineCaptionFocused: Bool
    /// Which backing field receives caption edits for the current place-stop primary block.
    @State private var placeCaptionWriteTarget: PlaceSlideCaptionTarget = .none
    /// Tracks the on-screen keyboard height so the toolbar can be pushed above it.
    /// Needed because `fullScreenCover` + `GeometryReader` doesn't propagate keyboard
    /// safe-area changes to the nested `safeAreaInset`, causing the keyboard to overlay the toolbar.
    @State private var keyboardHeight: CGFloat = 0
    /// When set, the editor can remove the current place slide from the carousel (Social Post Studio).
    let onExcludePlaceFromStudio: ((Int) -> Void)?
    /// When set, the editor can remove a day-map slide from the carousel.
    let onExcludeMapFromStudio: ((Int) -> Void)?
    /// Opens the excluded-photo gallery (parent-owned sheet).
    let onOpenExcludedPhotos: (() -> Void)?
    /// Count of photos excluded this session — drives the **Excluded** toolbar affordance.
    let excludedFromStudioCount: Int
    /// Opens the photo-group manager (bulk PIP / enable–disable per place stop).
    let onOpenPhotoGroupPicker: (() -> Void)?

    /// Persisted preference: skip the remove-slide confirmation alert.
    @AppStorage("blogify.studioSkipExcludeConfirm") private var skipExcludeConfirm = false
    /// True while the slide-exclusion confirmation overlay is visible.
    @State private var showExcludeConfirmOverlay = false

    init(
        slides: Binding<[CarouselSlide]>,
        initialIndex: Int,
        aspectRatio: CGFloat,
        exportActions: SlideTextEditorExportActions,
        exportInProgress: Binding<Bool>,
        onRequestStudioCoverPhotoPick: (() -> Void)? = nil,
        onExcludePlaceFromStudio: ((Int) -> Void)? = nil,
        onExcludeMapFromStudio: ((Int) -> Void)? = nil,
        onOpenExcludedPhotos: (() -> Void)? = nil,
        excludedFromStudioCount: Int = 0,
        onOpenPhotoGroupPicker: (() -> Void)? = nil
    ) {
        self._slides = slides
        self.initialIndex = initialIndex
        self.aspectRatio = aspectRatio
        self.exportActions = exportActions
        self._exportInProgress = exportInProgress
        self.onRequestStudioCoverPhotoPick = onRequestStudioCoverPhotoPick
        self.onExcludePlaceFromStudio = onExcludePlaceFromStudio
        self.onExcludeMapFromStudio = onExcludeMapFromStudio
        self.onOpenExcludedPhotos = onOpenExcludedPhotos
        self.excludedFromStudioCount = excludedFromStudioCount
        self.onOpenPhotoGroupPicker = onOpenPhotoGroupPicker
        self._currentIndex = State(initialValue: initialIndex)
        self._scrollPageID = State(initialValue: initialIndex)
    }

    /// Number of visible (non-PIP-hidden) selected slides — used to badge the
    /// photo-group picker button when the count exceeds TikTok's 34-slide limit.
    private var visibleSelectedSlideCount: Int {
        slides.enumerated().filter { idx, slide in
            !isSlideHiddenBySiblingPIP(at: idx, in: slides) && slide.isSelected
        }.count
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

    /// Extra-tall chrome while the PIP "Photos" stack-order drop-up is open — hosts the
    /// drag-to-reorder list inside an inset card without covering the slide to
    /// the top of the screen.
    private let bottomChromePIPReorder: CGFloat = 392

    /// Extra height reserved when the inline text-edit line is visible (single field).
    private let bottomTextEditLineHeight: CGFloat = 54
    /// Extra height when two fields are shown (place name + caption).
    private let bottomTextEditLineTallHeight: CGFloat = 100

    /// Height of the inline editor based on how many fields are shown.
    private var inlineEditorHeight: CGFloat {
        showsTextEditLine ? (showsInlineCaptionField ? bottomTextEditLineTallHeight : bottomTextEditLineHeight) : 0
    }

    /// Reserve subtracted from available height when computing `maxSlotH` for the
    /// slide pager. Matches pre–PIP-reorder behavior (`bottomChromeExpanded`) for
    /// all cases except while the tall PIP reorder drop-up is visible (multi-image),
    /// where we temporarily reserve `bottomChromePIPReorder` so the slide + chevrons
    /// stay above the actual inset without permanently shrinking the editor by 392pt
    /// when reorder is closed.
    private var slotSizingBottomReserve: CGFloat {
        if activePIPCategory == .order,
           let slide = currentSlide,
           slide.layout == .pip {
            let images = slide.pipImages
            let visible = min(max(0, slide.pipVisibleCount), images.count)
            if visible > 1 { return bottomChromePIPReorder }
        }
        return bottomChromeExpanded + inlineEditorHeight
    }

    /// Current inset height. Drives the `.safeAreaInset` frame so the chrome
    /// is only as tall as it needs to be — eliminates the ~60pt of dead gray
    /// that previously sat above Delete / Apply to… when no panel was open.
    private var currentChromeHeight: CGFloat {
        if activePIPCategory == .order {
            let images = currentSlide?.pipImages ?? []
            let visible = min(max(0, currentSlide?.pipVisibleCount ?? 0), images.count)
            if visible <= 1 { return bottomChromeExpanded }
            return bottomChromePIPReorder
        }
        let expanded = activeStyleCategory != nil || activePIPCategory != nil
        let base = expanded ? bottomChromeExpanded : bottomChromeCollapsed
        return base + inlineEditorHeight
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

    private var currentSlide: CarouselSlide? {
        let idx = editorPagerFocusedSlideIndex
        guard slides.indices.contains(idx) else { return nil }
        return slides[idx]
    }

    /// Slides the editor's swipe pager should actually render — mirrors the
    /// filter used by the preview/export pipelines so a place-stop slide that
    /// has been "folded into" a sibling's PIP cluster (same stop, `.pip`
    /// layout) doesn't reappear here. Without this, flipping a stop to
    /// multi-photo in the preview grid and then tapping Edit would still let
    /// the user swipe across the very slides that were just collapsed away.
    private var visibleSlideIndices: [Int] {
        slides.indices.filter { !isSlideHiddenBySiblingPIP(at: $0, in: slides) }
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
        case .mapRoute:
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
               (kind == .mapRoute && onExcludeMapFromStudio != nil)
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
        } else if kind == .mapRoute, let onExclude = onExcludeMapFromStudio {
            onExclude(idx)
        } else {
            return
        }
        if idx < currentIndex {
            currentIndex -= 1
        } else if idx == currentIndex {
            currentIndex = min(idx, max(0, slides.count - 1))
        }
        scrollPageID = currentIndex
        selectedBlock = nil
        clampCurrentIndexIfNeeded()
    }

    private func updateStyle(_ update: (inout TextBlockStyle) -> Void) {
        guard let selectedBlock, hasValidCurrentIndex else { return }
        pushUndoSnapshot()
        if selectedBlock == .secondary { update(&slides[currentIndex].textStyle.secondary) }
        else { update(&slides[currentIndex].textStyle.primary) }
    }

    private func pushUndoSnapshot() {
        undoStack.append(slides)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
    }

    /// Single vs multi-photo layout for the current place-stop slide. Keeps sibling
    /// slide `isSelected` flags aligned with `SocialPostStudioSheet.setLayout` so
    /// export and the preview strip stay consistent.
    private func setPlaceStopLayout(_ layout: CarouselSlideLayout) {
        let index = editorPagerFocusedSlideIndex
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
            slides[index].layout = layout
            for i in slides.indices where i != index {
                guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                slides[i].isSelected = (layout == .single)
            }
        }
        if layout == .pip {
            activeStyleCategory = nil
            withAnimation(.easeOut(duration: 0.18)) {
                selectedBlock = .pipCluster
            }
        } else {
            if selectedBlock == .pipCluster { selectedBlock = nil }
            activePIPCategory = nil
        }
        clampCurrentIndexIfNeeded()
        // Re-pin immediately: deferring only to `onChange(visibleSlideIndicesTag)` let
        // `scrollPosition` / `scrollPageID` race for a frame and landed users on the
        // wrong photo group (especially non-first photos at a stop).
        reassertEditorPagerToSlide(at: index)
    }

    @ViewBuilder
    private var placeStopLayoutToggleChrome: some View {
        if let slide = currentSlide,
           slide.kind == .placeStop,
           !slide.pipImages.isEmpty {
            HStack(spacing: 6) {
                ForEach(CarouselSlideLayout.allCases) { layout in
                    let isActive = slide.layout == layout
                    Button {
                        setPlaceStopLayout(layout)
                    } label: {
                        Image(systemName: layout == .single ? "rectangle.portrait" : "pip")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isActive ? .white : .white.opacity(0.45))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(isActive
                                ? Color(red: 0.04, green: 0.52, blue: 1.0)
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
        guard let selectedBlock, hasValidCurrentIndex else { return }
        pushUndoSnapshot()
        withAnimation(.easeInOut(duration: 0.25)) {
            switch selectedBlock {
            case .primary:
                slides[currentIndex].isPrimaryHidden = true
            case .secondary:
                slides[currentIndex].isSecondaryHidden = true
            case .pipCluster:
                revertPIPClusterToSingle(slideIndex: currentIndex)
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
        case (.mapRoute, .primary):   return slide.dayTitle ?? slide.dayInfoLine1 ?? ""
        case (.mapRoute, .secondary): return slide.dayStory ?? ""
        case (.placeStop, .primary):  return slide.placeStop?.placeTitle ?? ""
        case (.placeStop, .secondary): return slide.photoCaption ?? slide.caption ?? ""
        default: return ""
        }
    }

    /// True when the inline editor should show a second caption field (place name + caption).
    private var showsInlineCaptionField: Bool {
        currentSlide?.kind == .placeStop && selectedBlock == .primary
    }

    /// Writes `inlineTextDraft` (and `inlineCaptionDraft` for placeStop primary) back
    /// into the appropriate field(s) of the current slide and dismisses the inline editor.
    private func commitInlineTextEdit() {
        guard hasValidCurrentIndex, let block = selectedBlock else {
            showsTextEditLine = false
            return
        }
        pushUndoSnapshot()
        let text = inlineTextDraft
        switch (slides[currentIndex].kind, block) {
        case (.cover, .primary):      slides[currentIndex].coverTitle = text
        case (.mapRoute, .primary):   slides[currentIndex].dayTitle = text
        case (.mapRoute, .secondary): slides[currentIndex].dayStory = text
        case (.placeStop, .primary):
            slides[currentIndex].placeStop?.placeTitle = text
            slides[currentIndex].photoCaption = inlineCaptionDraft
        case (.placeStop, .secondary): slides[currentIndex].photoCaption = text
        default: break
        }
        showsTextEditLine = false
        isInlineTextEditorFocused = false
        isInlineCaptionFocused = false
    }

    /// Reverts a place-stop slide back to the single-photo layout. Mirrors the
    /// sibling-sync logic in `SocialPostStudioSheet.setLayout(.single, ...)`:
    /// sibling slides that were auto-deselected when `.pip` activated are
    /// re-selected so every photo is visible again as its own slide.
    private func revertPIPClusterToSingle(slideIndex: Int) {
        guard slides.indices.contains(slideIndex) else { return }
        guard slides[slideIndex].kind == .placeStop else { return }
        let stopID = slides[slideIndex].placeStop?.id
        slides[slideIndex].layout = .single
        // Reset the cluster's positional offset so re-enabling PIP later starts clean.
        slides[slideIndex].pipOffset = .zero
        slides[slideIndex].pipClusterSizeScale = 1.0
        for i in slides.indices where i != slideIndex {
            guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
            slides[i].isSelected = true
        }
    }

    /// Rotates the PIP cluster's photos so the current hero moves into the cluster and
    /// the first PIP thumbnail takes its place. Gives users a one-tap way to promote a
    /// cluster photo without leaving the editor. Rotates `pipPhotoIDs` alongside
    /// `pipImages` so the hero ID stays aligned with the hero image.
    private func swapPIPPhotos() {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip,
              !slides[currentIndex].pipImages.isEmpty,
              let hero = slides[currentIndex].heroImage else { return }
        pushUndoSnapshot()
        var pip = slides[currentIndex].pipImages
        var pipIDs = slides[currentIndex].pipPhotoIDs
        let promoted = pip.removeFirst()
        let promotedID: UUID? = pipIDs.isEmpty ? nil : pipIDs.removeFirst()
        pip.append(hero)
        if let heroID = slides[currentIndex].heroPhotoID {
            pipIDs.append(heroID)
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            slides[currentIndex].heroImage = promoted
            slides[currentIndex].heroPhotoID = promotedID
            slides[currentIndex].pipImages = pip
            slides[currentIndex].pipPhotoIDs = pipIDs
        }
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

            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].heroImage = pipImg
                slides[slideIdx].heroPhotoID = pipPID
                slides[slideIdx].pipImages[pipIdx] = oldHero ?? pipImg
                slides[slideIdx].pipPhotoIDs[pipIdx] = oldHID ?? pipPID
            }
            return
        }

        Task {
            let targetSize = CGSize(width: 1080, height: 1080)
            guard let localId = photo.localIdentifier,
                  let loaded = await loadCarouselAssetImage(identifier: localId, size: targetSize)
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
                let vc = slides[slideIdx].pipVisibleCount
                let insertAt = max(0, min(vc, imgs.count))
                imgs.insert(oImg, at: insertAt)
                ids.insert(oid, at: insertAt)

                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIdx].pipImages = imgs
                    slides[slideIdx].pipPhotoIDs = ids
                    slides[slideIdx].pipVisibleCount = min(3, vc + 1)
                }
            }
        }
    }

    /// Sets `pipVisibleCount` on the current slide (clamped 1 ... 3). Retained
    /// for internal callers (e.g. `addPIPPhotoToCluster`). The explicit 1/2/3
    /// count pills that used to live in the Photos drop-up were removed — the
    /// Reorder tab hosts drag-to-reorder, and count is driven indirectly
    /// via the Add / Remove pills in `pipCategoryTabBar`.
    private func setPIPVisibleCount(_ count: Int) {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        let clamped = min(max(count, 1), 3)
        guard slides[currentIndex].pipVisibleCount != clamped else { return }
        pushUndoSnapshot()
        withAnimation(.easeInOut(duration: 0.2)) {
            slides[currentIndex].pipVisibleCount = clamped
        }
    }

    /// Applies a drag-reorder gesture from `List.onMove` (in the Reorder tab
    /// module) to both the visible image array and the parallel
    /// photo-ID array, so the PIP cluster on the slide redraws in the new
    /// order immediately. `source` and `destination` follow SwiftUI's
    /// `move(fromOffsets:toOffset:)` semantics: indices are in the visible
    /// range and `destination` is the slot the items should land *in front
    /// of* — passing `visible` moves them to the end of the visible range.
    /// Indices outside the visible range are rejected so a stale drag
    /// triggered just as the cluster size changes can't mangle the arrays.
    private func reorderPIPPhotos(fromOffsets source: IndexSet,
                                  toOffset destination: Int) {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        let slide = slides[currentIndex]
        let visible = min(max(0, slide.pipVisibleCount), slide.pipImages.count)
        guard visible > 1 else { return }
        guard source.allSatisfy({ (0..<visible).contains($0) }),
              (0...visible).contains(destination) else { return }
        pushUndoSnapshot()
        // Commit without implicit animation: `List` already animates the drag/drop,
        // and wrapping this in `withAnimation` was delaying the slide + list
        // settling on the final order by a full extra animation pass.
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            slides[currentIndex].pipImages.move(fromOffsets: source,
                                                toOffset: destination)
            // Keep the parallel ID array in step. Only perform the move when
            // the IDs fully cover the visible range — otherwise the caller
            // has a shorter IDs array (legacy slides), and skipping the move
            // leaves it untouched rather than indexing out of range.
            if slides[currentIndex].pipPhotoIDs.count >= visible {
                slides[currentIndex].pipPhotoIDs.move(fromOffsets: source,
                                                     toOffset: destination)
            }
        }
    }

    /// Removes the bottom-most photo from the current cluster (the last
    /// visible slot) and drops `pipVisibleCount` by one. Inverse of
    /// `addPIPPhotoToCluster` — symmetry means Add-then-Remove cleanly walks
    /// the user back to where they started.
    private func removeLastPIPPhoto() {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        let slide = slides[currentIndex]
        let visible = min(max(0, slide.pipVisibleCount), slide.pipImages.count)
        guard visible > 0 else { return }
        pushUndoSnapshot()
        let removeAt = visible - 1
        withAnimation(.easeInOut(duration: 0.22)) {
            slides[currentIndex].pipImages.remove(at: removeAt)
            if removeAt < slides[currentIndex].pipPhotoIDs.count {
                slides[currentIndex].pipPhotoIDs.remove(at: removeAt)
            }
            slides[currentIndex].pipVisibleCount = max(1, visible - 1)
        }
    }

    /// Sets `pipBorderColor` on the current slide. Used by the Border color drop-up.
    /// Also re-enables the border, so tapping any color swatch after "no border"
    /// immediately paints the outline back in.
    private func setPIPBorderColor(_ color: StudioTextColor) {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        let slide = slides[currentIndex]
        guard slide.pipBorderColor != color || !slide.pipBorderEnabled else { return }
        pushUndoSnapshot()
        slides[currentIndex].pipBorderColor = color
        slides[currentIndex].pipBorderEnabled = true
    }

    /// Turns off the PIP thumbnail outline on the current slide. `pipBorderColor`
    /// is preserved so users can flip the border back on by tapping any color
    /// swatch without losing their previous selection.
    private func disablePIPBorder() {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        guard slides[currentIndex].pipBorderEnabled else { return }
        pushUndoSnapshot()
        slides[currentIndex].pipBorderEnabled = false
    }

    /// Writes a new PIP thumbnail size scale without its own undo snapshot — the
    /// Size strip captures undo once at drag begin (see `pipClusterSizeSliderPanel`).
    private func setPIPClusterSizeScaleLive(_ raw: CGFloat) {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        let clamped = min(max(raw, Self.pipClusterSizeScaleMin), Self.pipClusterSizeScaleMax)
        let snapped = (clamped / Self.pipClusterSizeScaleStep).rounded() * Self.pipClusterSizeScaleStep
        guard abs(snapped - slides[currentIndex].pipClusterSizeScale) > 0.0001 else { return }
        slides[currentIndex].pipClusterSizeScale = snapped
    }

    /// Vertical vs horizontal stacking for the PIP thumbnail column — driven from
    /// the "Style" menu in `pipStyleMenuButton`.
    private func applyPIPClusterStackStyle(_ style: CarouselPIPClusterStackStyle) {
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        guard slides[currentIndex].pipClusterStackStyle != style else { return }
        pushUndoSnapshot()
        slides[currentIndex].pipClusterStackStyle = style
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
        guard hasValidCurrentIndex,
              slides[currentIndex].layout == .pip else { return }
        pushUndoSnapshot()

        let slideIdx = currentIndex
        var images = slides[slideIdx].pipImages
        var ids = slides[slideIdx].pipPhotoIDs
        let visibleCount = max(0, min(slides[slideIdx].pipVisibleCount, ids.count))

        // If the picked photo is already loaded somewhere in pipImages (hidden
        // slot, or simply later in the array), move it into the first position
        // beyond the current visible range so it appears on the next render.
        if let existingIdx = ids.firstIndex(of: photo.id) {
            if existingIdx != visibleCount {
                let img = images.remove(at: existingIdx)
                let id = ids.remove(at: existingIdx)
                let insertAt = min(visibleCount, images.count)
                images.insert(img, at: insertAt)
                ids.insert(id, at: insertAt)
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                slides[slideIdx].pipImages = images
                slides[slideIdx].pipPhotoIDs = ids
                slides[slideIdx].pipVisibleCount = min(3, visibleCount + 1)
            }
            return
        }

        // Otherwise: load the image off-main, then append and bump visibleCount.
        // `guard` above ensured `layout == .pip`, but by the time the async load
        // returns the user may have navigated away or toggled the layout — we
        // re-check inside the Task before committing.
        Task {
            let targetSize = CGSize(width: 1080, height: 1080)
            guard let localId = photo.localIdentifier,
                  let loaded = await loadCarouselAssetImage(identifier: localId, size: targetSize) else {
                return
            }
            await MainActor.run {
                guard slides.indices.contains(slideIdx),
                      slides[slideIdx].layout == .pip else { return }
                var imgs = slides[slideIdx].pipImages
                var ids2 = slides[slideIdx].pipPhotoIDs
                let insertAt = max(0, min(slides[slideIdx].pipVisibleCount, imgs.count))
                imgs.insert(loaded, at: insertAt)
                ids2.insert(photo.id, at: insertAt)
                withAnimation(.easeInOut(duration: 0.22)) {
                    slides[slideIdx].pipImages = imgs
                    slides[slideIdx].pipPhotoIDs = ids2
                    slides[slideIdx].pipVisibleCount = min(3, slides[slideIdx].pipVisibleCount + 1)
                }
            }
        }
    }

    /// Copies font design, color, and size from the current slide to every slide (all kinds),
    /// for primary and secondary separately. Does not change dragged positions.
    private func applyTypographyToAllSlides() {
        clampCurrentIndexIfNeeded()
        guard hasValidCurrentIndex else { return }
        pushUndoSnapshot()
        let refPrimary = slides[currentIndex].textStyle.primary
        let refSecondary = slides[currentIndex].textStyle.secondary
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
        clampCurrentIndexIfNeeded()
        guard hasValidCurrentIndex, slides[currentIndex].kind == .placeStop else { return }
        pushUndoSnapshot()
        let refPrimary = slides[currentIndex].textStyle.primary
        let refSecondary = slides[currentIndex].textStyle.secondary
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
                // Uses `bottomChromeExpanded` by default (same as pre–PIP-reorder).
                // Only while the tall PIP reorder panel is open do we reserve the
                // larger height so the slide does not sit under the reorder card.
                let outerW = outerSize.width
                let outerH = outerSize.height
                let slideContentW = max(220, outerW - 48)
                let idealSlotH = slideContentW / aspectRatio
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
                let maxSlotH = max(260, outerH - navRowReserve - slotSizingBottomReserve)
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
                                                aspectRatio: aspectRatio,
                                                layoutWidth: slotW,
                                                maxHeight: slotH,
                                                selectedBlock: selectedBlock,
                                                onSelectBlock: { selectedBlock = $0 },
                                                onDeselect: { selectedBlock = nil },
                                                recordUndoSnapshot: { pushUndoSnapshot() },
                                                locksHorizontalSlidePaging: $locksHorizontalSlidePaging,
                                                onRequestHeroSwap: { idx in
                                                    // Drop text/PIP selection and bottom chrome so the swap sheet
                                                    // is the only focus (case `nil` no longer forces the sheet closed).
                                                    selectedBlock = nil
                                                    heroSwapSlideIndex = idx
                                                    showsHeroPhotoSwapSheet = true
                                                },
                                                onRequestStudioCoverPhotoPick: onRequestStudioCoverPhotoPick,
                                                slidePageIndex: i
                                            )
                                            Spacer(minLength: 0)
                                        }
                                        .frame(width: slotW, height: slotH)
                                        .id(i)
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
                        HStack(spacing: 16) {
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

                            Text("\((visiblePos ?? 0) + 1) / \(max(visibleIndices.count, 1))")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                                .frame(minWidth: 52)

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
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !slides.isEmpty {
                        // Bottom chrome height is dynamic:
                        //   • Hint + collapsed toolbar use `bottomChromeCollapsed`
                        //     (~116pt) — same height so transitioning between
                        //     them doesn't shift the slide during the tap-to-
                        //     select drag gesture (see `bottomChromeCollapsed`).
                        //   • Text style drop-ups use `bottomChromeExpanded` (~176pt).
                        //   • PIP reorder (2+ visible photos) uses `bottomChromePIPReorder`
                        //     (~392pt). That resize is toolbar-triggered, not slide drag.
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
                            ZStack(alignment: .bottom) {
                                if selectedBlock != nil {
                                    Color(white: 0.08)
                                        .ignoresSafeArea(edges: .bottom)
                                        .transition(.opacity)
                                }

                                if selectedBlock == nil {
                                    emptySelectionHint
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity)
                                } else if isPIPClusterSelected {
                                    pipClusterToolbar
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
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

                            Color.clear
                                .frame(height: keyboardHeight)
                        }
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboardHeight)
                    }
                }
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
                    let isMap = slides.indices.contains(currentIndex) && slides[currentIndex].kind == .mapRoute
                    Text(isMap ? "Remove map slide?" : "Remove this slide?")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text(isMap
                         ? "The day map will be excluded from the carousel."
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
                .tint(Color(red: 0.04, green: 0.52, blue: 1.0))
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    let canUndo = !undoStack.isEmpty
                    Button {
                        undoLastChange()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .opacity(canUndo ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.18), value: canUndo)
                    }
                    .disabled(!canUndo)
                    .accessibilityLabel("Undo")

                    if excludedFromStudioCount > 0, let onOpenExcluded = onOpenExcludedPhotos {
                        Button {
                            onOpenExcluded()
                        } label: {
                            Text("Excluded (\(excludedFromStudioCount))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("Excluded photos, \(excludedFromStudioCount)")
                    }

                    Menu {
                        if canExcludeCurrentSlide {
                            let isMap = slides.indices.contains(currentIndex) && slides[currentIndex].kind == .mapRoute
                            Section {
                                Button(role: .destructive) {
                                    performExcludeFromStudio()
                                } label: {
                                    Label(isMap ? "Remove map from carousel" : "Remove from carousel",
                                          systemImage: "minus.circle")
                                }
                            } footer: {
                                if isMap {
                                    Text("You can also press and hold the map slide to remove it.")
                                } else {
                                    Text("You can also press and hold this slide. In the studio preview, long-press the photo card or swipe up.")
                                }
                            }
                        }
                        if let onOpenPicker = onOpenPhotoGroupPicker {
                            let count = visibleSelectedSlideCount
                            let isOver = count > 34
                            Button { onOpenPicker() } label: {
                                Label(
                                    isOver
                                        ? "Manage photo groups (\(count))"
                                        : "Manage photo groups",
                                    systemImage: isOver ? "exclamationmark.triangle.fill" : "rectangle.3.group"
                                )
                            }
                            .accessibilityLabel(isOver
                                ? "Manage photo groups — \(count) slides, over TikTok limit"
                                : "Manage photo groups")
                        }
                        Button {
                            Task { await exportActions.share() }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(exportActions.exportActionsDisabled())
                        Button {
                            Task { await exportActions.saveToPhotos() }
                        } label: {
                            Label("Save to Photos", systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(exportActions.exportActionsDisabled())
                        Button {
                            Task { await exportActions.exportPDF() }
                        } label: {
                            Label("Export as PDF", systemImage: "doc.richtext")
                        }
                        .disabled(exportActions.exportActionsDisabled())
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Share and export")
                }
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
                selectedBlock = nil
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
        }
        .preferredColorScheme(.dark)
        .overlay {
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
            case .pipCluster:
                activeStyleCategory = nil
            case .primary, .secondary:
                activePIPCategory = nil
                showsAddPhotoPicker = false
                showsHeroPhotoSwapSheet = false
                heroSwapSlideIndex = nil
            }
        }
        .onChange(of: activePIPCategory) { _, _ in
            pipClusterSizeSliderUndoPrimed = false
        }
        // Track keyboard height so the toolbar spacer can push content above the keyboard.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
            guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let newHeight = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                keyboardHeight = newHeight
            }
        }
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
            Image(systemName: "hand.tap")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))

            VStack(spacing: 4) {
                Text("Tap a block to edit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                Text("Drag to reposition · Swipe to change slides")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            .multilineTextAlignment(.center)

            placeStopLayoutToggleChrome
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var textFormattingToolbar: some View {
        VStack(spacing: 0) {
            // Slide-level actions: bulk-apply typography / photo text positions from the
            // current slide (left), delete the selected block (right).
            HStack(spacing: 12) {
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
                    Label(didApplyToAll ? "Applied!" : "Apply to…",
                          systemImage: didApplyToAll ? "checkmark" : "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(didApplyToAll ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.45) : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(didApplyToAll ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: didApplyToAll)

                placeStopLayoutToggleChrome

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

            // Inline text editor — appears above the drop-up panel when the "Text" button is tapped.
            if showsTextEditLine {
                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 6) {
                        TextField(showsInlineCaptionField ? "Place name…" : "Edit text…", text: $inlineTextDraft)
                            .focused($isInlineTextEditorFocused)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onSubmit { showsInlineCaptionField ? (isInlineCaptionFocused = true) : commitInlineTextEdit() }

                        if showsInlineCaptionField {
                            TextField("Caption…", text: $inlineCaptionDraft)
                                .focused($isInlineCaptionFocused)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onSubmit { commitInlineTextEdit() }
                        }
                    }

                    Button {
                        commitInlineTextEdit()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color(red: 0.04, green: 0.52, blue: 1.0))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(white: 0.08))
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity))
            }

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
        .background(Color(white: 0.08))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeStyleCategory)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showsTextEditLine)
    }

    // MARK: - PIP cluster toolbar

    /// Bottom chrome shown when the multi-photo PIP cluster is selected. Mirrors
    /// the visual language of `textFormattingToolbar` (action row + drop-up +
    /// category tab bar) but with photo-specific actions and categories so the
    /// user doesn't see irrelevant typography controls.
    ///
    /// Top row: Delete (removes the cluster, reverts the slide to its single
    /// hero layout) and Swap (rotates the hero into the cluster, promoting the
    /// first PIP thumbnail). Below that: the Reorder / Border drop-up (when open)
    /// and the PIP category tab bar.
    @ViewBuilder
    private var pipClusterToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                placeStopLayoutToggleChrome

                // Swap promotes the first PIP thumbnail into the hero slot and
                // demotes the current hero into the cluster — a one-tap way to
                // change which cluster photo is "featured". Add/remove lives in
                // the scrollable category bar (`pipAddPhotosTabButton` /
                // `pipRemovePhotosTabButton`);
                // the Reorder tab opens the drag-to-reorder module.
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))

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
            case .order:
                pipReorderModulePanel
            case .border:
                pipBorderColorOptionsStrip
            case .size:
                pipClusterSizeSliderPanel
            }
        }
        .padding(.vertical, (category == .border || category == .size) ? 6 : 0)
        .frame(maxWidth: .infinity)
        .background((category == .border || category == .size) ? Color(white: 0.11) : Color.clear)
        .overlay(alignment: .top) {
            if category == .border || category == .size {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }

    /// Stable row identity for the Reorder `List`. Index-only IDs fight SwiftUI's
    /// `onMove` reconciliation and can leave the list + slide preview lagging after drop.
    private struct PIPReorderListRow: Identifiable {
        let id: AnyHashable
        let position: Int
        let image: UIImage
    }

    /// Inset “module” card for the Reorder tab: drag-to-reorder `List` in the
    /// bottom chrome with horizontal margins and rounded corners so the slide
    /// (and nav bar) stay visible — not a full-screen takeover.
    @ViewBuilder
    private var pipReorderModulePanel: some View {
        let images = currentSlide?.pipImages ?? []
        let photoIDs = currentSlide?.pipPhotoIDs ?? []
        let visible = min(max(0, currentSlide?.pipVisibleCount ?? 0), images.count)
        let orderedRows: [PIPReorderListRow] = (0..<visible).map { i in
            let rowID: AnyHashable = (i < photoIDs.count) ? photoIDs[i] : i
            return PIPReorderListRow(id: rowID, position: i + 1, image: images[i])
        }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reorder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text("Drag a photo to change the order")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if orderedRows.count <= 1 {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                    Text(visible == 0 ? "No photos in cluster" : "Add another photo to reorder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                List {
                    ForEach(orderedRows) { row in
                        PIPReorderOverlayRow(
                            image: row.image,
                            position: row.position
                        )
                        .listRowInsets(EdgeInsets(
                            top: 6, leading: 16, bottom: 6, trailing: 16
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: reorderPIPPhotos)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// Border-color drop-up: same color set as the text color panel so users
    /// can match cluster outline to an accent color they've used on text.
    /// The first swatch is a "no border" toggle (circle with a diagonal
    /// slash) that turns off the outline entirely without discarding the
    /// currently-selected color.
    private var pipBorderColorOptionsStrip: some View {
        let active = currentSlide?.pipBorderColor ?? .white
        let borderOff = !(currentSlide?.pipBorderEnabled ?? true)
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
        let scale = min(max(currentSlide?.pipClusterSizeScale ?? 1.0,
                              Self.pipClusterSizeScaleMin),
                        Self.pipClusterSizeScaleMax)
        let range = Self.pipClusterSizeScaleMax - Self.pipClusterSizeScaleMin
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
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let knob: CGFloat = 32
                let span = max(w - knob, 1)
                let t = CGFloat((scale - Self.pipClusterSizeScaleMin) / range)
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
                            let raw = Self.pipClusterSizeScaleMin + nt * range
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

    /// Category tab bar for the PIP cluster. Leading pills scroll with the row:
    /// **Add Photos** opens the picker when there is room and eligible picks;
    /// **Remove** drops the bottom-most photo when two or more thumbnails are
    /// visible (each button disables independently). **Style** (vertical vs
    /// horizontal stack) sits third; then Reorder / Border / Size drop-ups.
    /// Mirrors `styleCategoryTabBar`'s layout so the row heights align.
    private var pipCategoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    pipAddPhotosTabButton
                    pipRemovePhotosTabButton
                    pipStyleMenuButton
                }
                ForEach(PIPStyleCategory.allCases) { cat in
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

    /// Stack direction (vertical column vs horizontal row) for the PIP cluster.
    @ViewBuilder
    private var pipStyleMenuButton: some View {
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
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                Text("Style")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: Self.categoryButtonWidth)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Leading **Add Photos** pill in `pipCategoryTabBar`: opens the picker when
    /// the cluster has fewer than three visible slots and at least one eligible
    /// library photo exists.
    @ViewBuilder
    private var pipAddPhotosTabButton: some View {
        let visible = currentSlide?.pipVisibleCount ?? 0
        let canAdd = visible < 3 && !availableAddablePhotos.isEmpty

        Button {
            showsAddPhotoPicker = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canAdd
                        ? Color(red: 0.28, green: 0.64, blue: 1.0)
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

    /// Leading **Remove** pill: drops the bottom-most visible photo when two or
    /// more thumbnails are shown (disabled at a single-photo cluster).
    @ViewBuilder
    private var pipRemovePhotosTabButton: some View {
        let visible = currentSlide?.pipVisibleCount ?? 0
        let canRemove = visible > 1

        Button {
            removeLastPIPPhoto()
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
        case .order:
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isActive ? .white : .white.opacity(0.75))
                .frame(width: 22, height: 22)
        case .border:
            let borderOff = !(currentSlide?.pipBorderEnabled ?? true)
            ZStack {
                Circle()
                    .fill(borderOff
                          ? Color(white: 0.14)
                          : (currentSlide?.pipBorderColor ?? .white).color)
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
        case .size:
            Image(systemName: "aspectratio")
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
                                // For very light fills we'd lose the edge against the dark
                                // panel; a thin outline keeps every swatch readable.
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .overlay {
                                if isActive {
                                    Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(-3)
                                }
                            }
                            .shadow(color: .black.opacity(0.35), radius: 3)
                            // `.padding(4)` reserves the halo space in layout so the
                            // active-state ring doesn't get clipped by the ScrollView.
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
                                        ? Color(red: 0.04, green: 0.52, blue: 1.0)
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
            .tint(Color(red: 0.04, green: 0.52, blue: 1.0))

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
        guard let selectedBlock, hasValidCurrentIndex else { return }
        let clamped = min(max(rawScale, Self.sizeScaleMin), Self.sizeScaleMax)
        let snapped = (clamped / Self.sizeScaleStep).rounded() * Self.sizeScaleStep
        guard abs(snapped - currentStyle.sizeScale) > 0.0001 else { return }
        if selectedBlock == .secondary {
            slides[currentIndex].textStyle.secondary.sizeScale = snapped
        } else {
            slides[currentIndex].textStyle.primary.sizeScale = snapped
        }
    }

    /// Tap handler for the −/+ stepper buttons. Each tap is its own undo
    /// step, matching how every other toolbar tap behaves.
    private func adjustSizeScale(by delta: CGFloat) {
        let next = currentStyle.sizeScale + delta
        let clamped = min(max(next, Self.sizeScaleMin), Self.sizeScaleMax)
        let snapped = (clamped / Self.sizeScaleStep).rounded() * Self.sizeScaleStep
        guard abs(snapped - currentStyle.sizeScale) > 0.0001 else { return }
        updateStyle { $0.sizeScale = snapped }
    }

    /// Continuous font-size slider range. The matching display readout is
    /// computed via `displayPoints(for:)`, so min = 12pt and max = 36pt.
    private static let sizeScaleMin: CGFloat = 0.6
    private static let sizeScaleMax: CGFloat = 1.8
    /// One display point = 0.05 scale units (since reference base = 20pt),
    /// so every slider position lines up with a whole-number readout.
    private static let sizeScaleStep: CGFloat = 0.05

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
                            ? Color(red: 0.04, green: 0.52, blue: 1.0)
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
                            ? Color(red: 0.04, green: 0.52, blue: 1.0)
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
    /// categories (now 4: Color / Font Style / Font Size / Format) can grow
    /// without cramping the buttons. Buttons use a fixed intrinsic width so
    /// their labels never truncate; if the row doesn't fit on narrower
    /// devices (e.g. iPhone SE), users scroll horizontally.
    /// Tab button for the inline text editor — styled identically to `styleCategoryButton`
    /// so it sits naturally as the first item in the category tab bar.
    private var textEditTabButton: some View {
        let isActive = showsTextEditLine
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                if isActive {
                    showsTextEditLine = false
                    isInlineTextEditorFocused = false
                } else {
                    inlineTextDraft = currentBlockText
                    inlineCaptionDraft = currentSlide?.photoCaption ?? currentSlide?.caption ?? ""
                    showsTextEditLine = true
                    isInlineTextEditorFocused = true
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.65))
                    .frame(width: 22, height: 22)
                Text("Text")
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

    private var styleCategoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                textEditTabButton
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

    /// PIP cluster thumbnail scale range (`1.0` matches the original default footprint).
    private static let pipClusterSizeScaleMin: CGFloat = 0.55
    private static let pipClusterSizeScaleMax: CGFloat = 1.45
    private static let pipClusterSizeScaleStep: CGFloat = 0.02

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

    @State private var slides: [CarouselSlide] = []
    @State private var exportFormat: ExportFormat = .post
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
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
    @State private var showExcludedPhotosSheet = false
    /// Photo-group manager: bulk PIP / enable–disable per place stop.
    @State private var showPhotoGroupPicker = false
    /// Fired after load when the selected slide count still exceeds 34 after auto-PIP.
    @State private var showTikTokOverflowAlert = false
    @State private var tikTokOverflowRemainingCount = 0
    /// One-time dismissible tip for removing place photos from the preview strip (`UserDefaults`).
    @AppStorage("carouselStudio.removePlacePhotoTip.dismissed") private var removePlacePhotoTipDismissed = false
    @Environment(\.dismiss) private var dismiss

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

    private func makeEditorExportActions() -> SlideTextEditorExportActions {
        SlideTextEditorExportActions(
            share: { await shareViaSheet() },
            saveToPhotos: { await saveToPhotos() },
            exportPDF: { await exportSlidesPDFAndShare() },
            exportActionsDisabled: { exportActionsDisabled }
        )
    }

    var body: some View {
        Group {
            if opensInEditMode {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing slides…").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 5/255, green: 10/255, blue: 48/255))
                    .preferredColorScheme(.dark)
                } else if slides.isEmpty {
                    Text("No places found in this blog.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 5/255, green: 10/255, blue: 48/255))
                        .preferredColorScheme(.dark)
                } else {
                    SlideTextEditorView(
                        slides: $slides,
                        initialIndex: 0,
                        aspectRatio: exportFormat.aspectRatio,
                        exportActions: makeEditorExportActions(),
                        exportInProgress: $isRendering,
                        onRequestStudioCoverPhotoPick: {
                            #if DEBUG
                            print("[CarouselStudio] opening cover picker (Edit Slides / Carousel Studio)")
                            #endif
                            showStudioCoverPicker = true
                        },
                        onExcludePlaceFromStudio: { idx in excludePlaceSlide(at: idx) },
                        onExcludeMapFromStudio: { idx in excludeMapSlide(at: idx) },
                        onOpenExcludedPhotos: { showExcludedPhotosSheet = true },
                        excludedFromStudioCount: excludedStudioPhotoKeys.count,
                        onOpenPhotoGroupPicker: { showPhotoGroupPicker = true }
                    )
                }
            } else {
                NavigationStack {
                    ZStack {
                        Group {
                            if isLoading {
                                VStack(spacing: 16) { ProgressView(); Text("Preparing slides…").foregroundColor(.secondary) }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if slides.isEmpty {
                                Text("No places found in this blog.").foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                slidePreviewAndExport
                            }
                        }
                        if isRendering {
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
                    .background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle("Social Post Studio")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark").font(.system(size: 14)).foregroundColor(.white)
                            }
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if !excludedStudioPhotoKeys.isEmpty {
                                Button {
                                    showExcludedPhotosSheet = true
                                } label: {
                                    Text("Excluded (\(excludedStudioPhotoKeys.count))")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .accessibilityLabel("Excluded photos")
                            }
                            Menu {
                                Button {
                                    Task { await shareViaSheet() }
                                } label: {
                                    Label("Share to TikTok, Instagram, Facebook…", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    Task { await saveToPhotos() }
                                } label: {
                                    Label("Save to Photos", systemImage: "photo.on.rectangle.angled")
                                }
                                Button {
                                    Task { await exportSlidesPDFAndShare() }
                                } label: {
                                    Label("Export as PDF", systemImage: "doc.richtext")
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
                    .preferredColorScheme(.dark)
                }
            }
        }
        .task { await loadSlides() }
        .onChange(of: exportFormat) { _, _ in Task { await loadSlides() } }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ShareSheet(items: shareItems,
                       excludedActivityTypes: [UIActivity.ActivityType(rawValue: "com.burbn.instagram.shareextension")])
        }
        .alert("Slides Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(savedAlertMessage) }
        .alert("Too Many Slides for TikTok", isPresented: $showTikTokOverflowAlert) {
            Button("Manage Photo Groups") { showPhotoGroupPicker = true }
            Button("Continue Anyway", role: .cancel) {}
        } message: {
            Text("TikTok supports up to 34 photos per carousel. You have \(tikTokOverflowRemainingCount) slides selected. Use the photo group manager to trim down.")
        }
        .sheet(isPresented: $showPhotoGroupPicker) {
            CarouselPhotoGroupPickerSheet(slides: $slides)
        }
        .fullScreenCover(item: $editingSlideRef) { ref in
            SlideTextEditorView(
                slides: $slides,
                initialIndex: ref.index,
                aspectRatio: exportFormat.aspectRatio,
                exportActions: makeEditorExportActions(),
                exportInProgress: $isRendering,
                onRequestStudioCoverPhotoPick: {
                    #if DEBUG
                    print("[CarouselStudio] opening cover picker (from slide editor sheet)")
                    #endif
                    showStudioCoverPicker = true
                },
                onExcludePlaceFromStudio: { idx in excludePlaceSlide(at: idx) },
                onExcludeMapFromStudio: { idx in excludeMapSlide(at: idx) },
                onOpenExcludedPhotos: { showExcludedPhotosSheet = true },
                excludedFromStudioCount: excludedStudioPhotoKeys.count,
                onOpenPhotoGroupPicker: { showPhotoGroupPicker = true }
            )
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
        .sheet(isPresented: $showExcludedPhotosSheet) {
            StudioExcludedPhotosGallerySheet(
                blog: blog,
                excludedKeys: excludedStudioPhotoKeys,
                onRestore: { stopID, photoID in
                    restoreExcludedPhoto(stopID: stopID, photoID: photoID)
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

    private var savedAlertMessage: String {
        if exportFormat.isSingleSlide {
            return "Saved your Reel cover. You can post it now or refine later."
        }
        return "Saved \(selectedSlides.count) \(exportFormat.title.lowercased()) slides. You can post them now or refine later."
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

                        Spacer(minLength: 0)

                        studioSlideCountBadge
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
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    private var hasPlaceStopInPreviewStrip: Bool {
        slides.contains { $0.kind == .placeStop }
    }

    /// Pill showing the selected slide count; tapping it opens the photo-group manager.
    /// Turns orange with a warning icon when the count exceeds TikTok's 34-slide limit.
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
                Image(systemName: "rectangle.3.group")
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
                Text("Remove a place photo from this carousel: swipe up on its card, long-press the card, or tap ⋯ then Remove from carousel. In the full editor, press and hold the slide or use ⋯ above. Nothing is deleted from your trip.")
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
        VStack(spacing: 10) {
            SwipeUpToRemoveCard(
                slideKey: slide.id,
                isEnabled: slide.kind == .placeStop,
                onRemove: { excludePlaceSlide(at: index) }
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
                    clipsFloatingContentToRoundedSlideOutline: false
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
                }

                Spacer(minLength: 0)

                // Layout toggle — only for placeStop slides with multiple photos loaded
                if slide.kind == .placeStop, !slide.pipImages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(CarouselSlideLayout.allCases) { layout in
                            let isActive = slide.layout == layout
                            Button {
                                setLayout(layout, forSlideAt: index)
                            } label: {
                                Image(systemName: layout == .single ? "rectangle.portrait" : "pip")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(isActive
                                        ? Color(red: 0.04, green: 0.52, blue: 1.0)
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
            slides[index].layout = layout
            for i in slides.indices where i != index {
                guard slides[i].kind == .placeStop, slides[i].placeStop?.id == stopID else { continue }
                slides[i].isSelected = (layout == .single)
            }
        }
        if layout == .pip {
            previewRecenterAfterPIPIndex = index
            previewRecenterAfterPIPNonce += 1
        }
    }

    // MARK: - TikTok overflow management

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
                slides[i].layout = .pip
                for j in slides.indices where j != i {
                    guard slides[j].kind == .placeStop,
                          slides[j].placeStop?.id == stopID else { continue }
                    slides[j].isSelected = false
                }
            }
        }
    }

    /// Called after `loadSlides()` completes. If selected slide count > 34 (TikTok limit),
    /// first auto-enables PIP for every multi-photo stop, then alerts if still over limit.
    private func checkTikTokOverflow() {
        guard !exportFormat.isSingleSlide, selectedSlides.count > 34 else { return }
        autoEnablePIPForAllGroups()
        let remaining = selectedSlides.count
        if remaining > 34 {
            tikTokOverflowRemainingCount = remaining
            showTikTokOverflowAlert = true
        }
    }

    // MARK: - Studio photo exclusion

    /// Removes a day-map slide from the carousel for this session.
    @MainActor
    private func excludeMapSlide(at index: Int) {
        guard slides.indices.contains(index),
              slides[index].kind == .mapRoute else { return }
        slides.remove(at: index)
    }

    /// Removes a place photo slide from the carousel and remembers it so the user can add it back later.
    @MainActor
    private func excludePlaceSlide(at index: Int) {
        guard slides.indices.contains(index),
              slides[index].kind == .placeStop,
              let stop = slides[index].placeStop,
              let hid = slides[index].heroPhotoID else { return }
        excludedStudioPhotoKeys.insert(studioExclusionKey(stop: stop.id, photo: hid))
        slides.remove(at: index)
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
            day: day, stopID: stopID, photoID: photoID,
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
            }
            await rebuildPIPPayloadsForStop(stopID: stopID)
            await MainActor.run {
                if excludedStudioPhotoKeys.isEmpty { showExcludedPhotosSheet = false }
            }
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
            }
            return
        }

        let orderedPresentIDs = included.map(\.id).filter { pid in
            indices.contains { slides[$0].heroPhotoID == pid }
        }

        var cache: [UUID: UIImage] = [:]
        for pid in Set(orderedPresentIDs) {
            guard let p = included.first(where: { $0.id == pid }) else { continue }
            var img: UIImage?
            if let localId = p.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !localId.isEmpty {
                img = await loadCarouselAssetImage(identifier: localId,
                                                   size: CGSize(width: exportWidth, height: exportHeight))
            }
            if img == nil {
                img = await loadRecapPhotoUIImage(photo: p, size: CGSize(width: exportWidth, height: exportHeight))
            }
            if let img { cache[pid] = img }
        }

        for i in indices {
            guard let hid = slides[i].heroPhotoID else { continue }
            let pipIDs = Array(orderedPresentIDs.filter { $0 != hid }.prefix(3))
            // Keep `pipPhotoIDs` and `pipImages` index-aligned: `compactMap` on images
            // alone shifts thumbnails when any neighbor fails to load, so the cluster
            // can show the wrong photo next to each id (and SwiftUI reuse looks worse).
            let pipAligned: [(UUID, UIImage)] = pipIDs.compactMap { pid in
                guard let img = cache[pid] else { return nil }
                return (pid, img)
            }
            slides[i].pipPhotoIDs = pipAligned.map(\.0)
            slides[i].pipImages = pipAligned.map(\.1)
            if slides[i].layout == .pip, slides[i].pipImages.isEmpty {
                slides[i].layout = .single
            }
        }
    }

    // MARK: - Load

    private func loadCoverHeroImageForStudio() async -> UIImage? {
        let exportSize = CGSize(width: exportWidth, height: exportHeight)
        if let pid = studioCoverPhotoID,
           let photo = blog.allIncludedPhotos.first(where: { $0.id == pid }) {
            return await loadRecapPhotoUIImage(photo: photo, size: exportSize)
        }
        let trimmed = blog.selectedCoverPhotoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           let match = blog.allIncludedPhotos.first(where: {
               ($0.localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
           }) {
            return await loadRecapPhotoUIImage(photo: match, size: exportSize)
        }
        if !trimmed.isEmpty {
            return await loadAssetImage(identifier: trimmed, size: exportSize)
        }
        return nil
    }

    private func applyStudioCoverFromPick(_ photo: RecapPhoto) async {
        let exportSize = CGSize(width: exportWidth, height: exportHeight)
        let img = await loadRecapPhotoUIImage(photo: photo, size: exportSize)
        await MainActor.run {
            studioCoverPhotoID = photo.id
            if let i = slides.firstIndex(where: { $0.kind == .cover }) {
                slides[i].heroImage = img
            }
        }
    }

    private func loadSlides() async {
        let excludedSnapshot = await MainActor.run { excludedStudioPhotoKeys }
        var result: [CarouselSlide] = []

        let coverImg = await loadCoverHeroImageForStudio()
        result.append(CarouselSlide(id: "cover-\(blog.id.uuidString)", kind: .cover, isSelected: true,
                                    heroImage: coverImg, coverTitle: blog.title))

        var globalStopIndex = 0

        for (dayIdx, day) in blog.days.enumerated() {
            let dayNumber = dayIdx + 1
            var markerImages: [UUID: UIImage] = [:]
            var placeSlides: [CarouselSlide] = []

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
                var stopImages: [UIImage?] = []
                let exportSize = CGSize(width: exportWidth, height: exportHeight)
                for photo in included {
                    let img = await loadRecapPhotoUIImage(photo: photo, size: exportSize)
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

                for (photoIdx, photo) in included.enumerated() {
                    let hero = stopImages[photoIdx]
                    // PIP images = all other loaded images from this stop (up to 3).
                    // We zip image + photo ID so the editor can compute the
                    // "available to add" set (photos at this place that aren't
                    // currently shown in the cluster) without a second lookup.
                    let pipPairs: [(UIImage, UUID)] = included.enumerated()
                        .compactMap { (idx, candidate) -> (UIImage, UUID)? in
                            guard idx != photoIdx, let img = stopImages[idx] else { return nil }
                            return (img, candidate.id)
                        }
                        .prefix(3)
                        .map { $0 }
                    let pipImages: [UIImage] = pipPairs.map(\.0)
                    let pipPhotoIDs: [UUID] = pipPairs.map(\.1)
                    placeSlides.append(CarouselSlide(
                        id: "\(stop.id.uuidString)-\(photo.id.uuidString)", kind: .placeStop,
                        isSelected: true, heroImage: hero, placeStop: stop,
                        photoCaption: photo.caption,
                        textStyle: .placeStopDefault,
                        pipImages: pipImages,
                        pipPhotoIDs: pipPhotoIDs, heroPhotoID: photo.id,
                        stopIndex: stopIdx))
                }
            }

            let mapSnap = await MapSnapshotHelper.generatePhotoRouteSnapshot(
                for: day.placeStops, markerImagesByStopId: markerImages,
                size: CGSize(width: exportWidth, height: exportHeight), regionPadding: 0.015)

            let bestStory = [day.dayNarrative, day.dayCaption]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            result.append(CarouselSlide(
                id: "map-\(day.id.uuidString)", kind: .mapRoute, isSelected: true,
                mapSnapshot: mapSnap, dayInfoLine1: "Day \(dayNumber)",
                dayInfoLine2: day.dayStoryDateLine, dayStory: bestStory))
            result.append(contentsOf: placeSlides)
        }

        if exportFormat.isSingleSlide {
            // Reel: keep only the cover slide selected by default.
            for i in result.indices { result[i].isSelected = (i == 0) }
        }
        slides = result
        isLoading = false
        checkTikTokOverflow()
    }

    private func loadAssetImage(identifier: String, size: CGSize) async -> UIImage? {
        await loadCarouselAssetImage(identifier: identifier, size: size)
    }

    // MARK: - Export

    @MainActor private func saveToPhotos() async {
        isRendering = true; defer { isRendering = false }
        for image in renderSlides() { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
        showSavedAlert = true
    }

    @MainActor private func shareViaSheet() async {
        isRendering = true; defer { isRendering = false }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, image) in renderSlides().enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.92) else { continue }
            let url = tempDir.appendingPathComponent("slide_\(i + 1).jpg")
            try? data.write(to: url); urls.append(url)
        }
        shareItems = urls; showShareSheet = true
    }

    /// One PDF page per rendered studio slide; written under a dedicated temp folder so `cleanupTempFiles` removes only that directory.
    @MainActor private func exportSlidesPDFAndShare() async {
        isRendering = true
        defer { isRendering = false }
        let images = renderSlides()
        guard !images.isEmpty else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let safeTitle = blog.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = safeTitle.isEmpty ? "Social_Post_Studio" : safeTitle
        let pdfURL = tempDir.appendingPathComponent("\(baseName)_slides.pdf")
        let doc = PDFDocument()
        for (idx, image) in images.enumerated() {
            if idx % 2 == 0 { await Task.yield() }
            guard let page = PDFPage(image: image) else { continue }
            doc.insert(page, at: doc.pageCount)
        }
        guard doc.pageCount > 0, doc.write(to: pdfURL) else { return }
        shareItems = [pdfURL]
        showShareSheet = true
    }

    @MainActor private func renderSlides() -> [UIImage] {
        selectedSlides.compactMap { slide in
            let view = CarouselSlideView(slide: slide, width: exportWidth,
                                         aspectRatio: exportFormat.aspectRatio,
                                         onToggleSelection: {}, showsSelectionChrome: false)
            let r = ImageRenderer(content: view); r.scale = 1.0; return r.uiImage
        }
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
                                            .foregroundStyle(.white, Color(red: 0.14, green: 0.52, blue: 1.0))
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
                                            .background(Color(red: 0.14, green: 0.52, blue: 1.0).opacity(0.95))
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

/// Row used inside the Reorder tab `List`. The photo reads as a 72×72 thumbnail, with
/// a large position badge alongside and a dotted "card" background that
/// visually separates rows. We deliberately skip any move controls inside
/// the row because the parent List is in edit mode, so SwiftUI renders its
/// own drag handle on the trailing edge and handles the drag gesture for us.
/// Anything drawn *inside* the row (including a trailing icon) would fight
/// the handle's hit target and confuse users.
private struct PIPReorderOverlayRow: View {
    let image: UIImage
    let position: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("\(position)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, alignment: .center)
                .monospacedDigit()

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Square thumbnail for a single `RecapPhoto`. Loads the PHAsset image on
/// appear at a modest grid size — `AddPIPPhotoPickerSheet` re-loads at full
/// resolution when the user actually picks the photo, so we optimize for fast
/// grid population here.
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
        guard image == nil, let localId = photo.localIdentifier else { return }
        let loaded = await loadCarouselAssetImage(
            identifier: localId,
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

// MARK: - Excluded photos gallery (Carousel Studio)

private struct StudioExcludedPhotoThumb: View {
    let photo: RecapPhoto
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: 0.2))
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task {
                let loaded = await loadRecapPhotoUIImage(photo: photo, size: CGSize(width: 400, height: 500))
                await MainActor.run { image = loaded }
            }
    }
}

/// Grid of thumbnails for place photos removed from the carousel this session; **Revert** restores a slide.
private struct StudioExcludedPhotosGallerySheet: View {
    let blog: RecapBlogDetail
    let excludedKeys: Set<String>
    let onRestore: (UUID, UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let id: String
        let stopID: UUID
        let photoID: UUID
        let placeTitle: String
        let photo: RecapPhoto
    }

    private var items: [Item] {
        excludedKeys.compactMap { key -> Item? in
            guard let (stopID, photoID) = parseStudioExclusionKey(key) else { return nil }
            guard let stop = freshPlaceStop(stopID: stopID, blog: blog),
                  let photo = stop.photos.first(where: { $0.id == photoID }),
                  photo.isIncluded else { return nil }
            return Item(id: key, stopID: stopID, photoID: photoID, placeTitle: stop.placeTitle, photo: photo)
        }
        .sorted { lhs, rhs in
            lhs.placeTitle.localizedCaseInsensitiveCompare(rhs.placeTitle) == .orderedAscending
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 108), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    Text("Nothing here — excluded photos appear after you remove a place slide from the carousel.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                StudioExcludedPhotoThumb(photo: item.photo)
                                Text(item.placeTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Button {
                                    onRestore(item.stopID, item.photoID)
                                } label: {
                                    Text("Revert")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Excluded photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Photo group picker

/// Sheet that lists every place stop as a "photo group" with controls to:
/// - Toggle the whole group in/out of the exported carousel (select/deselect all its slides)
/// - Switch between full (one slide per photo) and PIP (one slide with inset thumbnails) mode
/// A running slide count vs the TikTok 34-slide limit guides the user toward the right shape.
private struct CarouselPhotoGroupPickerSheet: View {
    @Binding var slides: [CarouselSlide]
    @Environment(\.dismiss) private var dismiss

    private let tiktokLimit = 34

    // MARK: - Group model

    private struct PhotoGroup: Identifiable {
        let id: UUID              // placeStop.id
        let placeName: String
        let placeSubtitle: String
        let slideIndices: [Int]   // indices into `slides` for this stop
        let thumbnailImage: UIImage?
        let isInPIPMode: Bool     // true when the first slide's layout == .pip
        let isEnabled: Bool       // true when any slide for this stop is selected
        let photoCount: Int       // total photos loaded for this stop
    }

    private var photoGroups: [PhotoGroup] {
        var order: [UUID] = []
        var byStop: [UUID: [Int]] = [:]
        for (i, slide) in slides.enumerated() {
            guard slide.kind == .placeStop, let sid = slide.placeStop?.id else { continue }
            if byStop[sid] == nil { order.append(sid); byStop[sid] = [] }
            byStop[sid]!.append(i)
        }
        return order.compactMap { sid -> PhotoGroup? in
            guard let indices = byStop[sid], !indices.isEmpty else { return nil }
            let first = slides[indices[0]]
            guard let stop = first.placeStop else { return nil }
            let isEnabled = indices.contains { slides[$0].isSelected }
            let isInPIPMode = first.layout == .pip
            let photoCount = 1 + first.pipImages.count  // hero + available PIPs
            return PhotoGroup(
                id: sid,
                placeName: stop.placeTitle,
                placeSubtitle: stop.placeSubtitle ?? "",
                slideIndices: indices,
                thumbnailImage: first.heroImage,
                isInPIPMode: isInPIPMode,
                isEnabled: isEnabled,
                photoCount: photoCount
            )
        }
    }

    /// Contribution of one group toward the total slide count.
    private func slideContribution(of group: PhotoGroup) -> Int {
        guard group.isEnabled else { return 0 }
        return group.isInPIPMode ? 1 : group.slideIndices.count
    }

    private var totalSelectedCount: Int {
        let coverAndMap = slides.enumerated().filter { idx, slide in
            (slide.kind == .cover || slide.kind == .mapRoute) &&
            !isSlideHiddenBySiblingPIP(at: idx, in: slides) &&
            slide.isSelected
        }.count
        return coverAndMap + photoGroups.reduce(0) { $0 + slideContribution(of: $1) }
    }

    // MARK: - Mutations

    private func toggleGroupEnabled(_ group: PhotoGroup) {
        let newEnabled = !group.isEnabled
        for i in group.slideIndices { slides[i].isSelected = newEnabled }
    }

    private func toggleGroupPIP(_ group: PhotoGroup) {
        guard let firstIdx = group.slideIndices.first else { return }
        let newLayout: CarouselSlideLayout = group.isInPIPMode ? .single : .pip
        var txn = Transaction(); txn.disablesAnimations = true
        withTransaction(txn) {
            slides[firstIdx].layout = newLayout
            for i in group.slideIndices where i != firstIdx {
                slides[i].isSelected = (newLayout == .single)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    countBanner
                }

                let groups = photoGroups
                if groups.isEmpty {
                    Section {
                        Text("No photo groups found.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Photo Groups") {
                        ForEach(groups) { group in
                            groupRow(group)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Manage Photo Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Count banner

    private var countBanner: some View {
        let count = totalSelectedCount
        let isOver = count > tiktokLimit
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((isOver ? Color.orange : Color.green).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: isOver ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOver ? Color.orange : Color.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count) slide\(count == 1 ? "" : "s") selected")
                    .font(.headline)
                Text(isOver
                     ? "TikTok allows up to \(tiktokLimit) — remove some groups or enable PIP"
                     : "Within TikTok's \(tiktokLimit)-slide limit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isOver)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Group row

    @ViewBuilder
    private func groupRow(_ group: PhotoGroup) -> some View {
        let contrib = slideContribution(of: group)
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let img = group.thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .systemFill)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(group.isEnabled ? 1.0 : 0.4)

            // Place info
            VStack(alignment: .leading, spacing: 3) {
                Text(group.placeName.isEmpty ? "Unnamed place" : group.placeName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !group.placeSubtitle.isEmpty {
                    Text(group.placeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(group.isEnabled
                     ? (contrib == 1 ? "1 slide" : "\(contrib) slides")
                     : "excluded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(group.isEnabled
                                     ? Color(red: 0.04, green: 0.52, blue: 1.0)
                                     : Color(uiColor: .tertiaryLabel))
            }
            .opacity(group.isEnabled ? 1.0 : 0.5)

            Spacer(minLength: 0)

            // PIP toggle (only for stops with multiple photos)
            if group.photoCount > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { toggleGroupPIP(group) }
                } label: {
                    Image(systemName: group.isInPIPMode ? "pip" : "rectangle.portrait")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(group.isInPIPMode ? .white : Color(uiColor: .tertiaryLabel))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(group.isInPIPMode
                                    ? Color(red: 0.04, green: 0.52, blue: 1.0)
                                    : Color(uiColor: .systemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!group.isEnabled)
                .opacity(group.isEnabled ? 1.0 : 0.4)
            }

            // Include / exclude toggle
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { toggleGroupEnabled(group) }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
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
