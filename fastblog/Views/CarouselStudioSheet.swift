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
    var offset: CGSize = .zero
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

    var caption: String? {
        guard kind == .placeStop, let placeStop else { return nil }
        return [photoCaption, placeStop.placeNarrative, placeStop.overallStory, placeStop.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

// MARK: - Slide View

/// Pure rendering component for a repositionable text block.
/// The drag gesture intentionally lives in SlideTextEditorView (the full slide is the
/// gesture target) so that the hit-test area always covers the whole slide regardless
/// of where the block was dragged. SwiftUI's .offset() moves the view visually but
/// does NOT move the hit-test frame, so a self-contained gesture would stop responding
/// after the first drag. @GestureState also lives next to the state it updates,
/// eliminating the one-frame race where newStoredOffset + finalTranslation = 2× offset.
private struct DraggableTextBlock<Content: View>: View {
    let isEditingText: Bool
    let isSelected: Bool
    /// Pre-computed display offset: storedOffset + liveTranslation (for selected block).
    let offset: CGSize
    let onTap: () -> Void
    let content: () -> Content

    init(isEditingText: Bool,
         isSelected: Bool,
         offset: CGSize,
         onTap: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.isEditingText = isEditingText
        self.isSelected = isSelected
        self.offset = offset
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        content()
            .overlay {
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
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onTapGesture { onTap() }
            .offset(offset)
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
    /// Live translation injected from the parent drag gesture (SlideTextEditorView).
    /// Applied only to the block matching selectedBlockID so the selected block follows
    /// the finger smoothly without any hit-test mismatch.
    var liveDragTranslation: CGSize = .zero

    private var height: CGFloat { width / aspectRatio }
    private let heroImageScale: CGFloat = 1.12

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
                LinearGradient(colors: [.black.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                    .frame(width: width, height: height)
                if slide.dayStory != nil {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .init(x: 0.5, y: 0.52), endPoint: .bottom)
                        .frame(width: width, height: height)
                }

            case .placeStop:
                coverBackground
                // Top gradient: protects place name text
                LinearGradient(colors: [.black.opacity(0.65), .clear],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                    .frame(width: width, height: height)
                // Bottom gradient: protects caption text (only when caption exists)
                if slide.caption != nil {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                   startPoint: .init(x: 0.5, y: 0.58), endPoint: .bottom)
                        .frame(width: width, height: height)
                }
            }
        }
        // ── Draggable text overlays ───────────────────────────────────
        // Cover title — centered
        .overlay {
            if slide.kind == .cover, let title = slide.coverTitle, !title.isEmpty {
                DraggableTextBlock(
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .primary,
                    offset: slide.textStyle.primary.offset + (selectedBlockID == .primary ? liveDragTranslation : .zero),
                    onTap: { onSelectBlock?(.primary) }
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
            if slide.kind == .mapRoute {
                DraggableTextBlock(
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .primary,
                    offset: slide.textStyle.primary.offset + (selectedBlockID == .primary ? liveDragTranslation : .zero),
                    onTap: { onSelectBlock?(.primary) }
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
            if slide.kind == .mapRoute, let story = slide.dayStory, !story.isEmpty {
                DraggableTextBlock(
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    offset: slide.textStyle.secondary.offset + (selectedBlockID == .secondary ? liveDragTranslation : .zero),
                    onTap: { onSelectBlock?(.secondary) }
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
            if slide.kind == .placeStop {
                if let placeStop = slide.placeStop {
                    DraggableTextBlock(
                        isEditingText: isEditingText,
                        isSelected: selectedBlockID == .primary,
                        offset: slide.textStyle.primary.offset + (selectedBlockID == .primary ? liveDragTranslation : .zero),
                        onTap: { onSelectBlock?(.primary) }
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
            if slide.kind == .placeStop, let caption = slide.caption, !caption.isEmpty {
                DraggableTextBlock(
                    isEditingText: isEditingText,
                    isSelected: selectedBlockID == .secondary,
                    offset: slide.textStyle.secondary.offset + (selectedBlockID == .secondary ? liveDragTranslation : .zero),
                    onTap: { onSelectBlock?(.secondary) }
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

// MARK: - Full-Screen Text Editor

struct SlideTextEditorView: View {
    @Binding var slide: CarouselSlide
    let aspectRatio: CGFloat
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBlock: TextBlockID = .primary
    /// Live translation from the full-slide DragGesture. Injected into CarouselSlideView
    /// so the selected block follows the finger without any hit-test mismatch.
    @GestureState private var liveDragTranslation: CGSize = .zero

    // MARK: Helpers

    private var availableBlocks: [TextBlockID] {
        switch slide.kind {
        case .cover:   return [.primary]
        case .mapRoute: return slide.dayStory?.isEmpty == false ? [.primary, .secondary] : [.primary]
        case .placeStop: return slide.caption != nil ? [.primary, .secondary] : [.primary]
        }
    }

    private func blockLabel(_ id: TextBlockID) -> String {
        switch (slide.kind, id) {
        case (.cover, _):         return "Title"
        case (.mapRoute, .primary):   return "Heading"
        case (.mapRoute, .secondary): return "Story"
        case (.placeStop, .primary):  return "Place Name"
        case (.placeStop, .secondary): return "Caption"
        default: return "Text"
        }
    }

    private var currentStyle: TextBlockStyle {
        selectedBlock == .secondary ? slide.textStyle.secondary : slide.textStyle.primary
    }

    private func updateStyle(_ update: (inout TextBlockStyle) -> Void) {
        if selectedBlock == .secondary { update(&slide.textStyle.secondary) }
        else { update(&slide.textStyle.primary) }
    }

    /// Slide preview width: screen width minus horizontal margins.
    /// Avoids GeometryReader (which can cause double-render flicker in fullScreenCover).
    private var slideWidth: CGFloat {
        UIScreen.main.bounds.width - 48
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Select a block below, then drag anywhere on the slide to reposition")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)

                CarouselSlideView(
                    slide: slide,
                    width: slideWidth,
                    aspectRatio: aspectRatio,
                    onToggleSelection: {},
                    showsSelectionChrome: false,
                    isEditingText: true,
                    selectedBlockID: selectedBlock,
                    onSelectBlock: { selectedBlock = $0 },
                    liveDragTranslation: liveDragTranslation
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .updating($liveDragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let d = value.translation
                            if selectedBlock == .primary {
                                slide.textStyle.primary.offset.width  += d.width
                                slide.textStyle.primary.offset.height += d.height
                            } else {
                                slide.textStyle.secondary.offset.width  += d.width
                                slide.textStyle.secondary.offset.height += d.height
                            }
                        }
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
                .padding(.horizontal, 20)

                    Spacer()

                    textFormattingToolbar
                }
                .background(Color(red: 5/255, green: 10/255, blue: 48/255).ignoresSafeArea())
                .navigationTitle("Edit Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                slide.textStyle.primary.offset = .zero
                                slide.textStyle.secondary.offset = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset positions")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.medium)
            .onAppear {
                if !availableBlocks.contains(selectedBlock) { selectedBlock = .primary }
            }
        }

    // MARK: - Formatting toolbar

    @ViewBuilder
    private var textFormattingToolbar: some View {
        VStack(spacing: 0) {
            // Block selector tab bar (only when there are 2 blocks)
            if availableBlocks.count > 1 {
                HStack(spacing: 0) {
                    ForEach(availableBlocks, id: \.self) { blockID in
                        let isActive = selectedBlock == blockID
                        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedBlock = blockID } } label: {
                            Text(blockLabel(blockID))
                                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isActive
                                        ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.25)
                                        : Color.clear
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(white: 0.14))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
            }

            VStack(spacing: 16) {
                // Active block label
                HStack {
                    Text(blockLabel(selectedBlock))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                    Spacer()
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
        var icon: String { switch self { case .post: "rectangle.portrait"; case .story: "sparkles.rectangle.stack"; case .reel: "play.rectangle" } }
        var subtitle: String { switch self {
            case .post:  "Classic feed format for photo carousels"
            case .story: "Full-screen portrait layout for story posts"
            case .reel:  "Vertical cover format for short-form videos"
        } }
        var aspectRatio: CGFloat { switch self { case .post: 4.0/5.0; case .story, .reel: 9.0/16.0 } }
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
    private var selectedSlides: [CarouselSlide] { slides.filter { $0.isSelected } }

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
            SlideTextEditorView(slide: $slides[ref.index], aspectRatio: exportFormat.aspectRatio)
        }
    }

    // MARK: - Layout

    private var savedAlertMessage: String {
        "Saved \(selectedSlides.count) \(exportFormat.title.lowercased()) slides. You can post them now or refine later."
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
            Text("\(selectedSlides.count) of \(slides.count) slides selected")
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
                                      subtitle: "Save your \(exportFormat.title.lowercased()) slides, then publish or refine.")
                }
                .disabled(isRendering || selectedSlides.isEmpty)

                Button { Task { await shareViaSheet() } } label: {
                    exportButtonLabel(icon: "square.and.arrow.up",
                                      title: "Share…",
                                      subtitle: "Send your \(exportFormat.title.lowercased()) slides to any app (including Canva).")
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
                    withAnimation(.easeInOut(duration: 0.2)) { slides[index].isSelected.toggle() }
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
