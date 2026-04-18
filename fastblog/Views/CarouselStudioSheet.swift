// CarouselStudioSheet.swift
// fastblog

import Photos
import SwiftUI

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

/// Identifies which of a slide's two text blocks is active in the editor.
enum TextBlockID: Equatable, Hashable {
    case primary    // cover title / map heading / place name+subtitle
    case secondary  // map story / place caption
}

/// Categories in the bottom style tab bar. Selecting one opens a drop-up panel
/// with horizontally-scrollable options for that category.
private enum StyleCategory: String, CaseIterable, Identifiable {
    case color = "Color"
    case font  = "Font Style"
    case size  = "Font Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .font:  return "textformat"
        case .size:  return "textformat.size"
        }
    }
}

/// Style settings for a single independent text block.
struct TextBlockStyle: Equatable {
    var sizeScale: CGFloat = 1.0      // multiplier, 0.6 – 1.8
    var textColor: StudioTextColor = .white
    var fontDesign: StudioFontDesign = .default
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

private extension TextBlockStyle {
    /// Copies font, color, and size from `source`; leaves `offset` unchanged.
    mutating func mergeTypography(from source: TextBlockStyle) {
        fontDesign = source.fontDesign
        textColor = source.textColor
        sizeScale = source.sizeScale
    }

    /// Copies `offset` from `source`; leaves typography unchanged.
    mutating func mergeLayout(from source: TextBlockStyle) {
        offset = source.offset
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

    var caption: String? {
        guard kind == .placeStop, let placeStop else { return nil }
        return [photoCaption, placeStop.placeNarrative, placeStop.overallStory, placeStop.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

// MARK: - Slide View

/// Named coordinate space for the slide, used when measuring each block's natural
/// (anchor-based) frame so drags can be clamped to the slide bounds.
private let studioSlideCoordSpace = "studio.slide.space"

/// Edge inset (in points) used in two places that **must stay in sync**:
/// 1. `DraggableTextBlock.clamped(proposed:)` shrinks the allowed slide area by
///    this much, so the block can never be dragged flush against the slide edge.
/// 2. Each anchored overlay (top/bottom-leading) in `CarouselSlideView` pads its
///    draggable block by the same amount so the block's *natural* (anchor) rect
///    already sits inside that clamp region.
///
/// Keeping these equal means a fresh slide — where `savedOffset == .zero` — already
/// renders at the exact position the clamp would push it to. That eliminates the
/// small "snap" users used to see on their first tap: `DragGesture` uses
/// `minimumDistance: 0`, so a tap fires `.onEnded` with zero translation, and the
/// clamp would otherwise rewrite `savedOffset` from 0 to this inset amount,
/// visibly nudging the block ~6pt inward on first tap only.
private let studioTextBlockEdgeInset: CGFloat = 6

/// Repositionable text block. The drag gesture lives on the block itself; SwiftUI's
/// `.offset()` is visually displacing AND hit-testable, so the on-screen rect is the
/// one that receives touches — no external hit catchers required.
///
/// `savedOffset` is the committed displacement (written on drag-end after clamping to
/// `slideBounds`). `liveDrag` is the in-flight translation held in gesture state so it
/// auto-resets on gesture end and there is no one-frame snap between end and commit.
private struct DraggableTextBlock<Content: View>: View {
    let id: TextBlockID
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
    let content: () -> Content

    @GestureState private var liveDrag: CGSize = .zero
    /// Block frame at its natural (anchor-based) position in the slide coord space,
    /// used only for drag clamping. Captured once at `.zero` offset.
    @State private var naturalRect: CGRect?

    /// `savedOffset` converted from a normalized fraction into absolute points for the
    /// current `slideBounds`. This is what `.offset()` actually consumes.
    private var savedPointOffset: CGSize {
        CGSize(width: savedOffset.width * slideBounds.width,
               height: savedOffset.height * slideBounds.height)
    }

    var body: some View {
        content()
            .background(naturalRectCapture)
            .overlay(editingRing)
            .contentShape(Rectangle())
            .offset(x: savedPointOffset.width + liveDrag.width,
                    y: savedPointOffset.height + liveDrag.height)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($liveDrag) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { _ in
                        onDragStart()
                        onSelect()
                    }
                    .onEnded { value in
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

    /// Stores the block's natural (un-offset) frame in slide coords. `.frame(in: .named(...))`
    /// reports post-offset position, so we subtract whatever point-offset is currently applied
    /// (savedPointOffset + liveDrag) to recover the natural rect.
    ///
    /// We recapture on every size/bounds change (not just once) because the slide can
    /// resize mid-session on 9:16 formats when the toolbar grows or collapses. A stale
    /// natural rect makes `clamped(proposed:)` reject otherwise-valid drags and causes
    /// committed offsets to render in the wrong spot, which reads as "my move didn't save."
    private func captureNaturalRect(from geo: GeometryProxy) {
        let current = geo.frame(in: .named(studioSlideCoordSpace))
        guard current.width > 0, current.height > 0 else { return }
        let activeOffset = CGSize(
            width: savedPointOffset.width + liveDrag.width,
            height: savedPointOffset.height + liveDrag.height
        )
        naturalRect = current.offsetBy(dx: -activeOffset.width, dy: -activeOffset.height)
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

private func placeCaptionVisible(_ slide: CarouselSlide) -> Bool {
    !(slide.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct CarouselSlideView: View {
    let slide: CarouselSlide
    let width: CGFloat
    let aspectRatio: CGFloat
    let onToggleSelection: () -> Void
    let showsSelectionChrome: Bool
    var isEditingText: Bool = false
    /// Which text block is currently selected for editing (shown with a solid blue border).
    var selectedBlockID: TextBlockID? = nil
    /// Called when the user taps a text block to select it.
    var onSelectBlock: ((TextBlockID) -> Void)? = nil
    /// Edit-mode write-back: commit a block's new offset. Nil in read-only (preview/export) use.
    var onUpdateBlockOffset: ((TextBlockID, CGSize) -> Void)? = nil
    /// Fires on drag-start — the editor uses it to lock horizontal slide paging.
    var onBlockDragStart: (() -> Void)? = nil
    /// Fires on drag-end — the editor uses it to release the paging lock.
    var onBlockDragEnd: (() -> Void)? = nil

    private var height: CGFloat { width / aspectRatio }
    private let heroImageScale: CGFloat = 1.12
    private var slideBounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// Binding for the block's committed offset. Reads from `slide.textStyle.*`; writes
    /// go through `onUpdateBlockOffset` (nil-callback in read-only contexts makes it a no-op).
    private func offsetBinding(for id: TextBlockID) -> Binding<CGSize> {
        Binding(
            get: {
                id == .primary ? slide.textStyle.primary.offset
                               : slide.textStyle.secondary.offset
            },
            set: { newOffset in onUpdateBlockOffset?(id, newOffset) }
        )
    }

    var body: some View {
        ZStack {
            // ── Backgrounds ───────────────────────────────────────────
            switch slide.kind {
            case .cover:
                coverBackground
                LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.3), .clear],
                               startPoint: .bottom, endPoint: .top)
                    .frame(width: width, height: height)

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
                // Top gradient: protects place name text
                if !slide.isPrimaryHidden {
                    LinearGradient(colors: [.black.opacity(0.65), .clear],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                        .frame(width: width, height: height)
                }
                // Bottom gradient: only when caption text is present
                if placeCaptionVisible(slide), !slide.isSecondaryHidden {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                   startPoint: .init(x: 0.5, y: 0.58), endPoint: .bottom)
                        .frame(width: width, height: height)
                }
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
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    Text(title)
                        .font(.system(size: width * 0.085 * slide.textStyle.primary.sizeScale,
                                      weight: .heavy,
                                      design: slide.textStyle.primary.fontDesign.design))
                        .foregroundColor(slide.textStyle.primary.textColor.color)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
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
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let l1 = slide.dayInfoLine1 {
                            Text(l1)
                                .font(.system(size: width * 0.075 * slide.textStyle.primary.sizeScale,
                                              weight: .heavy,
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(slide.textStyle.primary.textColor.color)
                        }
                        if let l2 = slide.dayInfoLine2 {
                            Text(l2)
                                .font(.system(size: width * 0.038 * slide.textStyle.primary.sizeScale,
                                              weight: .semibold,
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(slide.textStyle.primary.textColor.color.opacity(0.88))
                                .lineLimit(1)
                        }
                    }
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
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    Text(storyText)
                        .font(.system(size: width * 0.042 * slide.textStyle.secondary.sizeScale,
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(slide.textStyle.secondary.textColor.color.opacity(0.88))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(width * 0.038)
                }
                .padding(studioTextBlockEdgeInset)
            }
        }
        // Place name + subtitle — top-leading
        .overlay(alignment: .topLeading) {
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
                        onDragEnd: { onBlockDragEnd?() }
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(placeStop.placeTitle)
                                .font(.system(size: width * 0.065 * slide.textStyle.primary.sizeScale,
                                              weight: .bold,
                                              design: slide.textStyle.primary.fontDesign.design))
                                .foregroundColor(slide.textStyle.primary.textColor.color)
                                .lineLimit(2)
                            if let sub = placeStop.placeSubtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.system(size: width * 0.048 * slide.textStyle.primary.sizeScale,
                                                  design: slide.textStyle.primary.fontDesign.design))
                                    .foregroundColor(slide.textStyle.primary.textColor.color.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
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
        // Place caption — bottom-leading
        .overlay(alignment: .bottomLeading) {
            let captionText = (slide.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slide.kind == .placeStop, !slide.isSecondaryHidden, !captionText.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    savedOffset: offsetBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    Text(captionText)
                        .font(.system(size: width * 0.044 * slide.textStyle.secondary.sizeScale,
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(slide.textStyle.secondary.textColor.color.opacity(0.85))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(width * 0.038)
                }
                .padding(studioTextBlockEdgeInset)
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
                Color.black.opacity(0.45)
                Text("Not Selected")
                    .font(.system(size: width * 0.05, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(slide.isSelected ? 1.0 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { if showsSelectionChrome { onToggleSelection() } }
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

// MARK: - Per-slide edit page

private struct SlideEditPage: View {
    @Binding var slide: CarouselSlide
    let aspectRatio: CGFloat
    /// Width of the paging cell (used with `maxHeight` so the slide scales like the old screen-based math).
    let layoutWidth: CGFloat
    /// Maximum height the slide can occupy — used to scale width down for tall formats (e.g. 9:16).
    let maxHeight: CGFloat
    let selectedBlock: TextBlockID?
    let onSelectBlock: (TextBlockID) -> Void
    /// Called when the user taps the slide background (outside any text block) — used to deselect.
    let onDeselect: () -> Void
    /// Called immediately before committing a new text-block offset (drag end) so the parent can record undo.
    let recordUndoSnapshot: () -> Void
    /// While true, the slide pager's horizontal scrolling is disabled (text drag / tap on a block).
    @Binding var locksHorizontalSlidePaging: Bool

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
                if id == .primary {
                    slide.textStyle.primary.offset = newOffset
                } else {
                    slide.textStyle.secondary.offset = newOffset
                }
            },
            onBlockDragStart: { locksHorizontalSlidePaging = true },
            onBlockDragEnd: { locksHorizontalSlidePaging = false }
        )
        .coordinateSpace(.named(studioSlideCoordSpace))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 20)
        // Tap anywhere on the slide outside a text block deselects. Taps on a block
        // are consumed by its `highPriorityGesture` drag, so this only fires for
        // taps on the slide background / margins.
        .onTapGesture { onDeselect() }
    }
}

// MARK: - Full-Screen Text Editor

struct SlideTextEditorView: View {
    @Binding var slides: [CarouselSlide]
    let initialIndex: Int
    let aspectRatio: CGFloat
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    /// Drives the paged `ScrollView`; optional to match `scrollPosition(id:)`.
    /// Seeded in `init` to `initialIndex` so the very first layout pass of the paging
    /// ScrollView already has the correct target page. Without this the ScrollView lays
    /// out at offset 0 first, then tries to scroll once `.onAppear`/`.task` sets the ID —
    /// which races with the `fullScreenCover` present animation and (especially for 9:16
    /// Story/Reel slides) lands a few points off-center.
    @State private var scrollPageID: Int?
    @State private var selectedBlock: TextBlockID? = nil
    /// Which style category (Color / Font Style / Font Size) is currently open in
    /// the drop-up panel. `nil` collapses the panel and only the category tab bar is shown.
    @State private var activeStyleCategory: StyleCategory? = nil
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

    init(slides: Binding<[CarouselSlide]>, initialIndex: Int, aspectRatio: CGFloat) {
        self._slides = slides
        self.initialIndex = initialIndex
        self.aspectRatio = aspectRatio
        self._currentIndex = State(initialValue: initialIndex)
        self._scrollPageID = State(initialValue: initialIndex)
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

    /// Current inset height. Drives the `.safeAreaInset` frame so the chrome
    /// is only as tall as it needs to be — eliminates the ~60pt of dead gray
    /// that previously sat above Delete / Apply to… when no panel was open.
    private var currentChromeHeight: CGFloat {
        activeStyleCategory == nil ? bottomChromeCollapsed : bottomChromeExpanded
    }

    // MARK: Helpers

    private var currentSlide: CarouselSlide? {
        guard slides.indices.contains(currentIndex) else { return nil }
        return slides[currentIndex]
    }

    private var availableBlocks: [TextBlockID] {
        guard let slide = currentSlide else { return [] }
        var blocks: [TextBlockID] = []
        switch slide.kind {
        case .cover:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
        case .mapRoute:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden { blocks.append(.secondary) }
        case .placeStop:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden { blocks.append(.secondary) }
        }
        return blocks
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
    private func deleteSelectedBlock() {
        guard let selectedBlock, hasValidCurrentIndex else { return }
        pushUndoSnapshot()
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedBlock == .primary {
                slides[currentIndex].isPrimaryHidden = true
            } else {
                slides[currentIndex].isSecondaryHidden = true
            }
        }
        // Clear selection after deleting the block.
        self.selectedBlock = availableBlocks.first
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

    var body: some View {
        NavigationStack {
            GeometryReader { outerGeo in
                // Stable slide slot height. Derived from the outer width and aspect
                // ratio, then capped to fit the outer height minus a reserve for the
                // chevron nav row and the worst-case chrome height (`bottomChromeExpanded`).
                // Sizing against the *expanded* chrome means `slotH` stays constant
                // when the user opens or closes a style drop-up panel — the extra
                // space when the panel is collapsed is absorbed by the top/bottom
                // Spacers around the slide.
                let outerW = outerGeo.size.width
                let outerH = outerGeo.size.height
                let slideContentW = max(220, outerW - 48)
                let idealSlotH = slideContentW / aspectRatio
                let navRowReserve: CGFloat = 72
                // The bottom `safeAreaInset` reserves pts for the editing chrome.
                // `outerGeo` still reports the full container height (SwiftUI's
                // GeometryReader is not affected by the inset), so we must
                // subtract the reserve here ourselves. Without this, a 9:16
                // Story/Reel slide sizes against `outerH - 72` and ends up taller
                // than the VStack's usable area — the slide pushes the chevron
                // row and toolbar straight off the bottom of the screen.
                //
                // We intentionally subtract the *expanded* chrome height, not the
                // current one, so the slide is sized for the worst case and its
                // size stays constant when the user expands a drop-up panel.
                // When the panel is collapsed, the extra space is absorbed by
                // the top/bottom Spacers around the slide.
                let maxSlotH = max(260, outerH - navRowReserve - bottomChromeExpanded)
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
                                    ForEach(slides.indices, id: \.self) { i in
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
                                                locksHorizontalSlidePaging: $locksHorizontalSlidePaging
                                            )
                                            Spacer(minLength: 0)
                                        }
                                        .frame(width: slotW, height: slotH)
                                        .id(i)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.paging)
                            .scrollPosition(id: $scrollPageID, anchor: .center)
                            .scrollDisabled(locksHorizontalSlidePaging)
                            .animation(.easeInOut(duration: 0.22), value: currentIndex)
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

                        // Slide navigation sits directly beneath the slide (not
                        // pushed all the way to the bottom of the sheet). The
                        // `Spacer` below absorbs any vertical change from the
                        // bottom-inset chrome so the slide + chevrons stay pinned
                        // in place when the user taps a block.
                        HStack(spacing: 16) {
                            Button {
                                guard currentIndex > 0 else { return }
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentIndex -= 1
                                    scrollPageID = currentIndex
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(currentIndex > 0 ? 0.12 : 0.05))
                                    .clipShape(Circle())
                            }
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1) / \(slides.count)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                                .frame(minWidth: 52)

                            Button {
                                guard currentIndex < slides.count - 1 else { return }
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentIndex += 1
                                    scrollPageID = currentIndex
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(currentIndex < slides.count - 1 ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(currentIndex < slides.count - 1 ? 0.12 : 0.05))
                                    .clipShape(Circle())
                            }
                            .disabled(currentIndex == slides.count - 1)
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
                        //   • Expanded drop-up panel uses `bottomChromeExpanded`
                        //     (~176pt). This shift is safe because it's
                        //     triggered by a tap on the toolbar's category
                        //     buttons, not on the slide itself.
                        //
                        // Painting differs by state:
                        //   • Hint: no backdrop, so the dark-blue main
                        //     background shows through — avoids the "tall gray
                        //     slab" the fixed reserve used to produce.
                        //   • Toolbar: gray backdrop that extends into the
                        //     bottom safe area so chrome meets the screen edge
                        //     without a dark-blue gap above the home indicator.
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
                            } else {
                                textFormattingToolbar
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .frame(height: currentChromeHeight)
                        .animation(.easeInOut(duration: 0.22), value: selectedBlock)
                        .animation(.spring(response: 0.32, dampingFraction: 0.82),
                                   value: activeStyleCategory)
                    }
                }
            }
            .background(Color(red: 5/255, green: 10/255, blue: 48/255).ignoresSafeArea())
            .navigationTitle("Edit Slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    let canUndo = !undoStack.isEmpty
                    Button {
                        undoLastChange()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .opacity(canUndo ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.18), value: canUndo)
                    }
                    .disabled(!canUndo)
                    .accessibilityLabel("Undo")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
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
                if newID != currentIndex { currentIndex = newID }
                selectedBlock = nil
            }
            .onChange(of: slides.count) { _, _ in
                clampCurrentIndexIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.medium)
        // `currentIndex` and `scrollPageID` are seeded in `init`, so the ScrollView lays
        // out on the correct page from the very first frame. We only need to reset the
        // per-session editor state here.
        .onAppear {
            selectedBlock = nil
            activeStyleCategory = nil
            undoStack = []
        }
        .onChange(of: selectedBlock) { _, newValue in
            // Closing a block's selection also collapses the style drop-up.
            if newValue == nil { activeStyleCategory = nil }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var textFormattingToolbar: some View {
        VStack(spacing: 0) {
            // Slide-level actions: delete the selected block, or bulk-apply typography /
            // photo text positions from the current slide.
            HStack(spacing: 12) {
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

                Spacer()

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
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(Color(white: 0.08))

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
    }

    // MARK: Drop-up panels

    @ViewBuilder
    private func styleDropUpPanel(for category: StyleCategory) -> some View {
        Group {
            switch category {
            case .color: colorOptionsStrip
            case .font:  fontOptionsStrip
            case .size:  sizeOptionsStrip
            }
        }
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
            .padding(.horizontal, 14)
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

    /// Font-size panel: horizontally-scrollable row of preset sizes labeled in
    /// "nominal" points (reference base = 20pt, scale × 20 ≈ classic iOS sizes
    /// 12 / 14 / 16 / … / 36). The slide text itself is still driven by a
    /// multiplicative `sizeScale` so every block kind stays in proportion.
    private var sizeOptionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.sizePresetScales, id: \.self) { scale in
                    let isActive = abs(currentStyle.sizeScale - scale) < 0.001
                    Button {
                        updateStyle { $0.sizeScale = scale }
                    } label: {
                        Text("\(Self.displayPoints(for: scale))")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(isActive ? .white : .white.opacity(0.6))
                            .frame(minWidth: 44)
                            .padding(.horizontal, 12).padding(.vertical, 9)
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

    /// Preset size scales shown in the drop-up strip. 60%–180% in 10% steps,
    /// matching the allowed range for `sizeScale`.
    private static let sizePresetScales: [CGFloat] = stride(from: 0.6, through: 1.8, by: 0.1).map {
        CGFloat(($0 * 10).rounded() / 10)
    }

    /// Reference base so 100% shows as "20" (a natural mid-range iOS text size).
    /// The slide's actual rendered size still varies per block kind — this label
    /// is just a familiar, monotonic readout users can read like a font picker.
    private static let sizeReferencePoints: CGFloat = 20

    private static func displayPoints(for scale: CGFloat) -> Int {
        Int((scale * sizeReferencePoints).rounded())
    }

    // MARK: Category tab bar

    private var styleCategoryTabBar: some View {
        HStack(spacing: 0) {
            ForEach(StyleCategory.allCases) { cat in
                styleCategoryButton(cat)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color(white: 0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

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
            }
            .frame(maxWidth: .infinity)
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

    @State private var slides: [CarouselSlide] = []
    @State private var exportFormat: ExportFormat = .post
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
    @State private var editingSlideRef: EditableSlideRef? = nil
    @Environment(\.dismiss) private var dismiss

    private let previewHeight: CGFloat = 325
    private let exportWidth: CGFloat = 1080
    private var exportHeight: CGFloat { exportWidth / exportFormat.aspectRatio }
    private var previewWidth: CGFloat { previewHeight * exportFormat.aspectRatio }
    private var selectedSlides: [CarouselSlide] {
        let sel = slides.filter { $0.isSelected }
        return exportFormat.isSingleSlide ? Array(sel.prefix(1)) : sel
    }

    var body: some View {
        NavigationStack {
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
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Social Post Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14)).foregroundColor(.white)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .dynamicTypeSize(.medium)
        .task { await loadSlides() }
        .onChange(of: exportFormat) { _, _ in Task { await loadSlides() } }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ShareSheet(items: shareItems,
                       excludedActivityTypes: [UIActivity.ActivityType(rawValue: "com.burbn.instagram.shareextension")])
        }
        .alert("Slides Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(savedAlertMessage) }
        .fullScreenCover(item: $editingSlideRef) { ref in
            SlideTextEditorView(slides: $slides, initialIndex: ref.index, aspectRatio: exportFormat.aspectRatio)
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
                } else {
                    Text("\(selectedSlides.count) of \(slides.count) slides selected")
                }
            }
            .font(.subheadline).foregroundColor(.secondary)
            .padding(.top, 10).padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(slides.indices, id: \.self) { index in
                        slideCard(slide: slides[index], index: index)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }

            Spacer()

            VStack(spacing: 10) {
                Button { Task { await saveToPhotos() } } label: {
                    exportButtonLabel(icon: "photo.on.rectangle.angled",
                                      title: "Save to Photos",
                                      subtitle: exportFormat.isSingleSlide
                                          ? "Save your Reel cover, then post it to Instagram or TikTok."
                                          : "Save your \(exportFormat.title.lowercased()) slides, then publish or refine.")
                }
                .disabled(isRendering || selectedSlides.isEmpty)

                Button { Task { await shareViaSheet() } } label: {
                    exportButtonLabel(icon: "square.and.arrow.up",
                                      title: "Share…",
                                      subtitle: exportFormat.isSingleSlide
                                          ? "Send your Reel cover to any app (including Canva)."
                                          : "Send your \(exportFormat.title.lowercased()) slides to any app (including Canva).")
                }
                .disabled(isRendering || selectedSlides.isEmpty)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func slideCard(slide: CarouselSlide, index: Int) -> some View {
        VStack(spacing: 10) {
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
                showsSelectionChrome: true
            )
            .frame(width: previewWidth)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

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
        }
    }

    // MARK: - Load

    private func loadSlides() async {
        var result: [CarouselSlide] = []

        let coverImage: UIImage? = blog.selectedCoverPhotoIdentifier.map { _ in nil } ?? nil
        if let id = blog.selectedCoverPhotoIdentifier {
            let img = await loadAssetImage(identifier: id, size: CGSize(width: exportWidth, height: exportHeight))
            result.append(CarouselSlide(id: "cover-\(blog.id.uuidString)", kind: .cover, isSelected: true,
                                        heroImage: img, coverTitle: blog.title))
        } else {
            result.append(CarouselSlide(id: "cover-\(blog.id.uuidString)", kind: .cover, isSelected: true,
                                        coverTitle: blog.title))
        }

        for (dayIdx, day) in blog.days.enumerated() {
            let dayNumber = dayIdx + 1
            var markerImages: [UUID: UIImage] = [:]
            var placeSlides: [CarouselSlide] = []

            for stop in day.placeStops {
                let included = stop.photos.filter { $0.isIncluded }
                guard !included.isEmpty else { continue }
                for (photoIdx, photo) in included.enumerated() {
                    var hero: UIImage?
                    if let localId = photo.localIdentifier {
                        hero = await loadAssetImage(identifier: localId,
                                                    size: CGSize(width: exportWidth, height: exportHeight))
                    }
                    if photoIdx == 0, let img = hero { markerImages[stop.id] = img }
                    placeSlides.append(CarouselSlide(
                        id: "\(stop.id.uuidString)-\(photo.id.uuidString)", kind: .placeStop,
                        isSelected: true, heroImage: hero, placeStop: stop, photoCaption: photo.caption))
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
    }

    private func loadAssetImage(identifier: String, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = fetch.firstObject else { cont.resume(returning: nil); return }
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            PHImageManager.default().requestImage(for: asset, targetSize: size,
                                                  contentMode: .aspectFill, options: opts) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    // MARK: - Export

    @ViewBuilder
    private func exportButtonLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            if isRendering { ProgressView().tint(.white) }
            else { Image(systemName: icon).font(.system(size: 18)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).lineLimit(2).opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, alignment: .leading)
        .padding(.vertical, 14).padding(.horizontal, 18)
        .background(Color(white: 0.18)).foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

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
