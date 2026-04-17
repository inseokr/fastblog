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
    case white, cream, yellow, orange, cyan, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white:  return .white
        case .cream:  return Color(red: 1.0, green: 0.97, blue: 0.88)
        case .yellow: return Color(red: 1.0, green: 0.92, blue: 0.30)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.20)
        case .cyan:   return Color(red: 0.38, green: 0.92, blue: 1.00)
        case .pink:   return Color(red: 1.0, green: 0.40, blue: 0.70)
        }
    }
}

/// Identifies which of a slide's two text blocks is active in the editor.
enum TextBlockID: Equatable, Hashable {
    case primary    // cover title / map heading / place name+subtitle
    case secondary  // map story / place caption
}

/// Style settings for a single independent text block.
struct TextBlockStyle: Equatable {
    var sizeScale: CGFloat = 1.0      // multiplier, 0.6 – 1.8
    var textColor: StudioTextColor = .white
    var fontDesign: StudioFontDesign = .default
    /// The block's desired center in slide-local coordinates (points).
    /// `nil` means use the natural anchor position.
    /// Storing absolute center — not a displacement from the anchor — makes the value
    /// meaningful across slides with different text lengths.
    var center: CGPoint? = nil
}

/// Holds per-block styles for a slide. Each block is independently styled and draggable.
struct TextOverlayStyle: Equatable {
    var primary: TextBlockStyle = TextBlockStyle()    // title / heading / name+subtitle
    var secondary: TextBlockStyle = TextBlockStyle()  // story / caption
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
    /// Desired center of the block in slide-local coordinates. `nil` = natural anchor position.
    @Binding var anchoredCenter: CGPoint?
    /// Slide rect in its local coord space (e.g. `(0, 0, slideW, slideH)`), used to clamp drags.
    let slideBounds: CGRect
    var onSelect: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    let content: () -> Content

    @GestureState private var liveDrag: CGSize = .zero
    /// Block frame at its natural (anchor-based) position — captured once on first appear.
    @State private var naturalRect: CGRect?

    /// Offset to apply for the current `anchoredCenter`, relative to the natural anchor.
    private var displayOffset: CGSize {
        guard let center = anchoredCenter, let natural = naturalRect else { return .zero }
        return CGSize(width: center.x - natural.midX, height: center.y - natural.midY)
    }

    var body: some View {
        content()
            .background(naturalRectCapture)
            .overlay(editingRing)
            .contentShape(Rectangle())
            .offset(x: displayOffset.width + liveDrag.width,
                    y: displayOffset.height + liveDrag.height)
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
                        let proposed = CGSize(
                            width: displayOffset.width + value.translation.width,
                            height: displayOffset.height + value.translation.height
                        )
                        let clampedOffset = clamped(proposed: proposed)
                        if let natural = naturalRect {
                            anchoredCenter = CGPoint(
                                x: natural.midX + clampedOffset.width,
                                y: natural.midY + clampedOffset.height
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
                .onAppear {
                    guard naturalRect == nil else { return }
                    let current = geo.frame(in: .named(studioSlideCoordSpace))
                    guard current.width > 0, current.height > 0 else { return }
                    // Strip any existing offset so we always store the un-displaced rect.
                    naturalRect = current.offsetBy(
                        dx: -displayOffset.width,
                        dy: -displayOffset.height
                    )
                }
        }
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
                .padding(-6)
        }
    }

    /// Constrains the proposed offset so the block's visual rect stays inside `slideBounds`.
    private func clamped(proposed: CGSize) -> CGSize {
        guard let natural = naturalRect,
              slideBounds.width > 0, slideBounds.height > 0
        else { return proposed }

        let inset: CGFloat = 6
        let bounds = slideBounds.insetBy(dx: inset, dy: inset)
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
    /// Edit-mode write-back: commit a block's new center. Nil in read-only (preview/export) use.
    var onUpdateBlockCenter: ((TextBlockID, CGPoint?) -> Void)? = nil
    /// Fires on drag-start — the editor uses it to lock horizontal slide paging.
    var onBlockDragStart: (() -> Void)? = nil
    /// Fires on drag-end — the editor uses it to release the paging lock.
    var onBlockDragEnd: (() -> Void)? = nil

    private var height: CGFloat { width / aspectRatio }
    private let heroImageScale: CGFloat = 1.12
    private var slideBounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// Binding for the block's committed center. Reads from `slide.textStyle.*`; writes
    /// go through `onUpdateBlockCenter` (nil-callback in read-only contexts makes it a no-op).
    private func centerBinding(for id: TextBlockID) -> Binding<CGPoint?> {
        Binding(
            get: {
                id == .primary ? slide.textStyle.primary.center
                               : slide.textStyle.secondary.center
            },
            set: { newCenter in onUpdateBlockCenter?(id, newCenter) }
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
                if slide.dayStory != nil, !slide.isSecondaryHidden {
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
                // Bottom gradient: protects caption text (only when caption exists)
                if slide.caption != nil, !slide.isSecondaryHidden {
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
                    anchoredCenter: centerBinding(for: .primary),
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
                        .padding(.horizontal, width * 0.06)
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
                    anchoredCenter: centerBinding(for: .primary),
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
                    .padding(width * 0.055)
                }
            }
        }
        // Map story — bottom-leading
        .overlay(alignment: .bottomLeading) {
            if slide.kind == .mapRoute, !slide.isSecondaryHidden, let story = slide.dayStory, !story.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    anchoredCenter: centerBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    Text(story)
                        .font(.system(size: width * 0.042 * slide.textStyle.secondary.sizeScale,
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(slide.textStyle.secondary.textColor.color.opacity(0.88))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(width * 0.055)
                }
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
                        anchoredCenter: centerBinding(for: .primary),
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
                        .padding(width * 0.06)
                    }
                } else {
                    Text("Missing place data")
                        .font(.system(size: width * 0.05, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(width * 0.06)
                }
            }
        }
        // Place caption — bottom-leading
        .overlay(alignment: .bottomLeading) {
            if slide.kind == .placeStop, !slide.isSecondaryHidden, let caption = slide.caption, !caption.isEmpty {
                DraggableTextBlock(
                    id: .secondary,
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    anchoredCenter: centerBinding(for: .secondary),
                    slideBounds: slideBounds,
                    onSelect: { onSelectBlock?(.secondary) },
                    onDragStart: { onBlockDragStart?() },
                    onDragEnd: { onBlockDragEnd?() }
                ) {
                    Text(caption)
                        .font(.system(size: width * 0.044 * slide.textStyle.secondary.sizeScale,
                                      design: slide.textStyle.secondary.fontDesign.design))
                        .foregroundColor(slide.textStyle.secondary.textColor.color.opacity(0.85))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, width * 0.06)
                        .padding(.vertical, width * 0.03)
                }
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
    let selectedBlock: TextBlockID?
    let onSelectBlock: (TextBlockID) -> Void
    /// While true, the slide pager's horizontal scrolling is disabled (text drag / tap on a block).
    @Binding var locksHorizontalSlidePaging: Bool

    private var slideWidth: CGFloat { UIScreen.main.bounds.width - 48 }

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
            onUpdateBlockCenter: { id, newCenter in
                if id == .primary {
                    slide.textStyle.primary.center = newCenter
                } else {
                    slide.textStyle.secondary.center = newCenter
                }
            },
            onBlockDragStart: { locksHorizontalSlidePaging = true },
            onBlockDragEnd: { locksHorizontalSlidePaging = false }
        )
        .coordinateSpace(.named(studioSlideCoordSpace))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 20)
    }
}

// MARK: - Full-Screen Text Editor

struct SlideTextEditorView: View {
    @Binding var slides: [CarouselSlide]
    let initialIndex: Int
    let aspectRatio: CGFloat
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    /// Drives the paged `ScrollView`; optional to match `scrollPosition(id:)`.
    @State private var scrollPageID: Int?
    @State private var selectedBlock: TextBlockID? = nil
    /// Disables horizontal slide paging while the user touches a text block (see `SlideEditPage`).
    @State private var locksHorizontalSlidePaging = false
    /// Briefly true after "Apply to all slides" to show a confirmation flash.
    @State private var didApplyToAll = false

    // MARK: Helpers

    private var slide: CarouselSlide { slides[currentIndex] }

    /// Slide preview width: screen width minus horizontal margins.
    /// Avoids GeometryReader (which can cause double-render flicker in fullScreenCover).
    private var slideWidth: CGFloat { UIScreen.main.bounds.width - 48 }
    private var slideHeight: CGFloat { slideWidth / aspectRatio }

    private var availableBlocks: [TextBlockID] {
        var blocks: [TextBlockID] = []
        switch slide.kind {
        case .cover:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
        case .mapRoute:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden, slide.dayStory?.isEmpty == false { blocks.append(.secondary) }
        case .placeStop:
            if !slide.isPrimaryHidden { blocks.append(.primary) }
            if !slide.isSecondaryHidden, slide.caption != nil { blocks.append(.secondary) }
        }
        return blocks
    }

    private var currentStyle: TextBlockStyle {
        selectedBlock == .secondary ? slide.textStyle.secondary : slide.textStyle.primary
    }

    private func updateStyle(_ update: (inout TextBlockStyle) -> Void) {
        guard let selectedBlock else { return }
        if selectedBlock == .secondary { update(&slides[currentIndex].textStyle.secondary) }
        else { update(&slides[currentIndex].textStyle.primary) }
    }

    /// Hides the currently selected block on this slide. The deletion is reversible via
    /// the toolbar "reset" button, which also unhides both blocks for the current slide.
    private func deleteSelectedBlock() {
        guard let selectedBlock else { return }
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

    /// Copies this slide's full text style (font design, color, size, position) to every
    /// slide in the carousel, for both blocks. Hidden flags are left alone so per-slide
    /// deletions survive.
    private func applyStyleToAllSlides() {
        let primary = slides[currentIndex].textStyle.primary
        let secondary = slides[currentIndex].textStyle.secondary
        withAnimation(.easeInOut(duration: 0.2)) {
            for i in slides.indices {
                slides[i].textStyle.primary   = primary
                slides[i].textStyle.secondary = secondary
            }
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Tap a block to select · Drag to reposition · Swipe to change slides")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                // Slide navigation
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
                .padding(.bottom, 10)

                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(slides.indices, id: \.self) { i in
                                SlideEditPage(
                                    slide: $slides[i],
                                    aspectRatio: aspectRatio,
                                    selectedBlock: selectedBlock,
                                    onSelectBlock: { selectedBlock = $0 },
                                    locksHorizontalSlidePaging: $locksHorizontalSlidePaging
                                )
                                .frame(width: geo.size.width)
                                .id(i)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPageID)
                    .scrollDisabled(locksHorizontalSlidePaging)
                    .animation(.easeInOut(duration: 0.22), value: currentIndex)
                }
                .frame(height: slideHeight)

                Spacer()

                textFormattingToolbar
            }
            .background(Color(red: 5/255, green: 10/255, blue: 48/255).ignoresSafeArea())
            .navigationTitle("Edit Slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            slides[currentIndex].textStyle.primary.center = nil
                            slides[currentIndex].textStyle.secondary.center = nil
                            slides[currentIndex].isPrimaryHidden = false
                            slides[currentIndex].isSecondaryHidden = false
                        }
                        selectedBlock = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset slide")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onChange(of: scrollPageID) { _, newID in
                guard let newID else { return }
                if newID != currentIndex { currentIndex = newID }
                selectedBlock = nil
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.medium)
        .onAppear {
            currentIndex = initialIndex
            scrollPageID = initialIndex
            selectedBlock = nil
        }
    }

    // MARK: - Formatting toolbar

    @ViewBuilder
    private var textFormattingToolbar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Slide-level actions: delete the selected block, or push this slide's
                // visual style (font / color / size) to every slide in the carousel.
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

                    Button {
                        applyStyleToAllSlides()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { didApplyToAll = true }
                        Task {
                            try? await Task.sleep(for: .milliseconds(1400))
                            withAnimation(.easeOut(duration: 0.25)) { didApplyToAll = false }
                        }
                    } label: {
                        Label(didApplyToAll ? "Applied!" : "Apply to all slides",
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

                // Font design pills
                HStack(spacing: 8) {
                    ForEach(StudioFontDesign.allCases) { design in
                        let isActive = currentStyle.fontDesign == design
                        Button { updateStyle { $0.fontDesign = design } } label: {
                            Text(design.rawValue)
                                .font(.system(size: 13, weight: .semibold, design: design.design))
                                .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(isActive
                                            ? Color(red: 0.04, green: 0.52, blue: 1.0)
                                            : Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isActive)
                    }
                    Spacer()
                }

                // Color swatches + size
                HStack(alignment: .center, spacing: 0) {
                    ForEach(StudioTextColor.allCases) { tc in
                        let isActive = currentStyle.textColor == tc
                        Button { updateStyle { $0.textColor = tc } } label: {
                            Circle()
                                .fill(tc.color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if isActive {
                                        Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(1)
                                    }
                                }
                                .shadow(color: .black.opacity(0.35), radius: 3)
                                .scaleEffect(isActive ? 1.15 : 1.0)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 7)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            updateStyle { $0.sizeScale = max(0.6, ($0.sizeScale - 0.1).rounded(toPlaces: 1)) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                                .frame(width: 38, height: 38).background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }

                        Text("\(Int((currentStyle.sizeScale * 100).rounded()))%")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 44, alignment: .center)

                        Button {
                            updateStyle { $0.sizeScale = min(1.8, ($0.sizeScale + 0.1).rounded(toPlaces: 1)) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                                .frame(width: 38, height: 38).background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Color(white: 0.08))
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

    private var modeSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in modeCard(for: format).id(format.id) }
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .onChange(of: exportFormat) { _, sel in
                withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(sel.id, anchor: .center) }
            }
            .task { proxy.scrollTo(exportFormat.id, anchor: .center) }
        }
    }

    private func modeCard(for format: ExportFormat) -> some View {
        let isSel = exportFormat == format
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { exportFormat = format }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: format.icon).font(.system(size: 18, weight: .semibold))
                    Text(format.title).font(.headline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(format.aspectRatio == (4.0/5.0) ? "4:5" : "9:16")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(isSel ? 0.28 : 0.14)).clipShape(Capsule())
                }
                Text(format.subtitle).font(.subheadline).foregroundColor(.white.opacity(0.86))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(width: 230, alignment: .leading)
            .background(LinearGradient(
                colors: isSel ? [Color(red:0.14,green:0.5,blue:1), Color(red:0.24,green:0.71,blue:1)]
                              : [Color(white:0.2), Color(white:0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isSel ? 0.35 : 0.12), lineWidth: isSel ? 1.2 : 1))
            .shadow(color: .black.opacity(isSel ? 0.26 : 0.12), radius: isSel ? 12 : 6, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .scrollTransition(.animated.threshold(.visible(0.75))) { c, p in
            c.scaleEffect(p.isIdentity ? 1 : 0.96).opacity(p.isIdentity ? 1 : 0.86)
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
                size: CGSize(width: exportWidth, height: exportHeight), regionPadding: 0.04)

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
