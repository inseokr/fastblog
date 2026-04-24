//
//  PlaceCaptionEditSheet.swift
//  fastblog
//
//  Full-screen place story editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI
import UIKit

struct PlaceCaptionEditSheet: View {
    /// Matches `PlaceStopRowView` / `PlacePhotoModalView` AI story accent.
    private static let funAISparkleGradient = LinearGradient(
        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    let placeTitle: String
    let placeSubtitle: String?
    /// MK POI category raw string for this stop (optional tone hint for on-device “AI story”).
    var placeCategory: String? = nil
    let photos: [RecapPhoto]
    @Binding var caption: String
    /// Bindings for per-photo captions (strip lists every displayable selected photo).
    var photoCaption: (UUID) -> Binding<String>
    /// `placeCaptionChanged` / `changedPhotoIds` reflect edits vs. values when the sheet opened.
    var onSave: (_ placeCaptionChanged: Bool, _ changedPhotoIds: Set<UUID>) -> Void
    var onCancel: () -> Void
    var confirmLabel: String = "Save"
    /// When provided, the Enhance button is shown. Receives the draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result (so caller can mark overallStoryIsManual = false).
    var onEnhanceApplied: (() -> Void)? = nil
    /// Called after “AI story” writes a **per-photo** caption; use to mark that photo’s caption as AI (not overall place story).
    var onFunPhotoInsightApplied: ((UUID) -> Void)? = nil
    /// Pure translation — no AI story generation.
    var onTranslate: ((String) async -> String)? = nil
    /// Parent presents `EditPlaceStopNameSheet` (same as blog edit-mode place row).
    var onRequestEditPlaceName: (() -> Void)? = nil
    /// When true, the place story was typed by the user — hide on-device place “AI story”.
    var overallStoryIsManual: Bool = false
    /// Produces up to two sentences for the **place** caption using full stop context (tags, photo captions, daypart).
    var onGeneratePlaceAIShortStory: (() async -> String)? = nil
    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var isGeneratingAIShortStory = false
    @State private var selectedPhotoHasVisionTagsForAIStory = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @State private var isFocused: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// Matches kebab `PlaceStopActionSheet` “Edit Caption & Details” row (`text.alignleft`).
    private enum CaptionThumbnailSelection: Equatable {
        case placeCaption
        case photo(UUID)
    }

    @State private var captionThumbnailSelection: CaptionThumbnailSelection = .placeCaption
    @State private var draftPlaceCaption: String = ""
    @State private var draftPhotoCaptions: [UUID: String] = [:]
    @State private var initialPlaceCaption: String = ""
    @State private var initialPhotoCaptions: [UUID: String] = [:]

    private let thumbnailSize: CGFloat = 60
    private let thumbnailCorner: CGFloat = 10
    private let thumbnailStroke: CGFloat = 2

    /// Included photos that still resolve to real pixels (omits removed / missing library assets so the strip never shows gradient placeholders).
    private var captionStripPhotos: [RecapPhoto] {
        photos.filter(\.hasDisplayableLocalBacking)
    }

    /// When set, shows a large preview of that strip photo (second tap on the selected photo thumbnail).
    @State private var expandedPhotoPreviewId: UUID?
    @State private var expandedPhotoPreviewScale: CGFloat = 1.0
    @State private var expandedPhotoPreviewOffset: CGSize = .zero
    @GestureState private var expandedPhotoPreviewPinch: CGFloat = 1.0
    @GestureState private var expandedPhotoPreviewDrag: CGSize = .zero

    /// Horizontal inset for typed text inside the rounded editor (both sides).
    /// Also used as `textContainerInset` in ScrollMetricsReportingTextEditor so placeholder aligns exactly.
    private let editorTextHorizontalPadding: CGFloat = 14
    /// Matches `editorTextHorizontalPadding` exactly — no lineFragmentPadding fudge needed because
    /// ScrollMetricsReportingTextEditor zeroes lineFragmentPadding and uses textContainerInset instead.
    private let placeholderLeadingInset: CGFloat = 14
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches other blog sheets: non‑Max width + xxxLarge Dynamic Type so long placeholders don’t clip awkwardly.
    private var shouldUseTwoLineCaptionPlaceholder: Bool {
        UIScreen.main.bounds.width < 428 && dynamicTypeSize >= .xxxLarge
    }

    /// Single line by default; explicit newline on narrow phones at largest content sizes.
    private var captionPlaceholderText: String {
        switch captionThumbnailSelection {
        case .placeCaption:
            if shouldUseTwoLineCaptionPlaceholder {
                return "Describe this\nplace..."
            }
            return "Describe this place..."
        case .photo:
            if shouldUseTwoLineCaptionPlaceholder {
                return "Describe this\nmoment..."
            }
            return "Describe this moment..."
        }
    }

    private var captionPlaceholderLineLimit: Int {
        captionThumbnailSelection == .placeCaption ? 2 : 3
    }

    /// Minimum height for the caption editor (scrolls inside). Grows to fill space down to the thumbnail strip
    /// so the gap isn’t wasted; still scrolls when the keyboard leaves less room than this.
    private var captionTextEditorMinHeight: CGFloat {
        let w = UIScreen.main.bounds.width
        let narrowPhone = w < 400
        let belowLargePhoneWidth = w < 428

        if dynamicTypeSize >= .accessibility5 {
            return narrowPhone ? 92 : 104
        }
        if dynamicTypeSize >= .accessibility3 {
            return narrowPhone ? 104 : 116
        }
        if dynamicTypeSize >= .xxxLarge {
            return belowLargePhoneWidth ? 118 : 132
        }
        if dynamicTypeSize >= .xxLarge {
            return belowLargePhoneWidth ? 132 : 144
        }
        // Slightly taller default now that the header no longer shows a large photo preview.
        return 168
    }

    @ViewBuilder
    private var captionThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                placeCaptionThumbnailCell
                ForEach(captionStripPhotos) { photo in
                    photoThumbnailCell(photo)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: thumbnailSize)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var titleAndEditIconForeground: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var editPlaceNamePillFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.08)
    }

    /// Matches `PlaceStopRowView` edit-mode place title + pencil circle.
    @ViewBuilder
    private var placeTitleRowWithEditNameControl: some View {
        if let onEdit = onRequestEditPlaceName {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    requestEditPlaceName(openEditor: onEdit)
                } label: {
                    Text(placeTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(titleAndEditIconForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Button {
                    requestEditPlaceName(openEditor: onEdit)
                } label: {
                    ZStack {
                        Circle()
                            .fill(editPlaceNamePillFill)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(titleAndEditIconForeground)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit place name")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(placeTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var placeSubtitleIfAny: some View {
        if let placeSubtitle, !placeSubtitle.isEmpty {
            Text(placeSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var placeCaptionTitleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                placeTitleRowWithEditNameControl
                placeSubtitleIfAny
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(spacing: 0) {
            placeCaptionTitleHeader
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                ScrollMetricsReportingTextEditor(
                    text: $editedText,
                    wantsKeyboardFocus: $isFocused,
                    textInsets: UIEdgeInsets(
                        top: 14,
                        left: editorTextHorizontalPadding,
                        bottom: 14,
                        right: editorTextHorizontalPadding
                    ),
                    caretTint: .white
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))

                if editedText.isEmpty {
                    Text(captionPlaceholderText)
                        .font(.body)
                        .foregroundColor(Color(uiColor: .placeholderText))
                        .multilineTextAlignment(.leading)
                        .lineLimit(captionPlaceholderLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, placeholderLeadingInset)
                        .padding(.trailing, placeholderTrailingInset)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: captionTextEditorMinHeight, maxHeight: .infinity)
            .padding(.horizontal, 20)

            if LocalLLMStoryCaptionGenerator.isCapable, selectedPhotoHasVisionTagsForAIStory, let photo = selectedPhotoForFunAI,
               !photoCaptionBlocksAIShortStory(photo: photo) {
                HStack {
                    Spacer(minLength: 0)
                    if isGeneratingAIShortStory {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.75)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button {
                            runFunPhotoInsight(photo: photo)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(Self.funAISparkleGradient)
                                Text("AI story")
                                    .font(.caption)
                                    .foregroundStyle(Self.funAISparkleGradient)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isEnhancing || isTranslating || isGeneratingAIShortStory)
                        .accessibilityLabel("Generate up to two sentences from on-device photo tags")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            if LocalLLMStoryCaptionGenerator.isCapable,
               captionThumbnailSelection == .placeCaption,
               onGeneratePlaceAIShortStory != nil,
               !placeCaptionBlocksAIShortStory {
                HStack {
                    Spacer(minLength: 0)
                    if isGeneratingAIShortStory {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.75)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: runPlaceAIShortStory) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(Self.funAISparkleGradient)
                                Text("AI story")
                                    .font(.caption)
                                    .foregroundStyle(Self.funAISparkleGradient)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isEnhancing || isTranslating || isGeneratingAIShortStory)
                        .accessibilityLabel("Generate up to two sentences for this place from trip context")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            if !trimmedEditedText.isEmpty {
                HStack(spacing: 16) {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            editedText = ""
                            originalDraft = nil
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    if let draft = originalDraft {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                editedText = draft
                                originalDraft = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption)
                                Text("Revert")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Revert caption")
                    }

                    if let translate = onTranslate {
                        Button {
                            runTranslate(translate)
                        } label: {
                            if isTranslating {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.75)
                                    Text("Translating…")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "translate")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(isEnhancing || isTranslating || isGeneratingAIShortStory)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !photos.isEmpty {
                captionThumbnailStrip
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                Button("Cancel") {
                    isFocused = false
                    onCancel()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .buttonStyle(.plain)

                Spacer()

                Button(confirmLabel) {
                    flushCurrentDraftFromEditor()
                    caption = draftPlaceCaption
                    for p in captionStripPhotos {
                        photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
                    }
                    let placeChanged = draftPlaceCaption != initialPlaceCaption
                    let changedPhotoIds = Set(
                        captionStripPhotos.map(\.id).filter { id in
                            (draftPhotoCaptions[id] ?? "") != (initialPhotoCaptions[id] ?? "")
                        }
                    )
                    isFocused = false
                    onSave(placeChanged, changedPhotoIds)
                }
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .overlay {
            if let id = expandedPhotoPreviewId,
               let photo = captionStripPhotos.first(where: { $0.id == id }) {
                expandedPhotoPreviewOverlay(photo: photo)
                    .transition(.opacity)
            }
        }
        // Do not attach `.animation(value: expandedPhotoPreviewId)` here — it fights nested
        // `withAnimation` + zoom state and can trigger AttributeGraph cycles when the overlay appears.
        .preferredColorScheme(.dark)
        .task(id: captionThumbnailSelection) {
            switch captionThumbnailSelection {
            case .placeCaption:
                await MainActor.run { selectedPhotoHasVisionTagsForAIStory = false }
            case .photo(let pid):
                guard LocalLLMStoryCaptionGenerator.isCapable,
                      let p = captionStripPhotos.first(where: { $0.id == pid }) else {
                    await MainActor.run { selectedPhotoHasVisionTagsForAIStory = false }
                    return
                }
                let has = await StoryCaptionService.shared.photoHasAnalyzedVisionTags(photo: p)
                await MainActor.run {
                    if case .photo(let cur) = captionThumbnailSelection, cur == pid {
                        selectedPhotoHasVisionTagsForAIStory = has
                    }
                }
            }
        }
        .onAppear {
            initialPlaceCaption = caption
            draftPlaceCaption = caption
            var photoMap: [UUID: String] = [:]
            for p in captionStripPhotos {
                photoMap[p.id] = p.caption ?? ""
            }
            initialPhotoCaptions = photoMap
            draftPhotoCaptions = photoMap
            editedText = draftPlaceCaption
            captionThumbnailSelection = .placeCaption
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private func resetExpandedPhotoPreviewTransform() {
        expandedPhotoPreviewScale = 1.0
        expandedPhotoPreviewOffset = .zero
    }

    private func dismissExpandedPhotoPreview() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPhotoPreviewId = nil
            expandedPhotoPreviewScale = 1.0
            expandedPhotoPreviewOffset = .zero
        }
        // Mirror the defer in presentExpandedPhotoPreview: don't toggle first-responder
        // synchronously inside a SwiftUI update pass. Also restores focus so that
        // updateUIView doesn't call resignFirstResponder the next time the user types.
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func presentExpandedPhotoPreview(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPhotoPreviewScale = 1.0
            expandedPhotoPreviewOffset = .zero
            expandedPhotoPreviewId = id
        }
        // Avoid toggling keyboard focus in the same turn as overlay presentation (see ScrollMetricsReportingTextEditor).
        DispatchQueue.main.async {
            isFocused = false
        }
    }

    private func requestEditPlaceName(openEditor: @escaping () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            expandedPhotoPreviewId = nil
            resetExpandedPhotoPreviewTransform()
        }
        syncDraftToUnderlyingBindings()
        isFocused = false
        openEditor()
    }

    /// Pushes in-memory drafts into the recap bindings before opening another editor (e.g. rename place).
    private func syncDraftToUnderlyingBindings() {
        flushCurrentDraftFromEditor()
        caption = draftPlaceCaption
        for p in captionStripPhotos {
            photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
        }
    }

    private func flushCurrentDraftFromEditor() {
        switch captionThumbnailSelection {
        case .placeCaption:
            draftPlaceCaption = editedText
        case .photo(let id):
            draftPhotoCaptions[id] = editedText
        }
    }

    private func selectThumbnail(_ newSelection: CaptionThumbnailSelection) {
        if newSelection == captionThumbnailSelection {
            if case .photo(let id) = newSelection {
                if expandedPhotoPreviewId == id {
                    dismissExpandedPhotoPreview()
                } else {
                    presentExpandedPhotoPreview(id: id)
                }
            }
            return
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            expandedPhotoPreviewId = nil
            resetExpandedPhotoPreviewTransform()
        }
        flushCurrentDraftFromEditor()
        captionThumbnailSelection = newSelection
        switch newSelection {
        case .placeCaption:
            editedText = draftPlaceCaption
        case .photo(let id):
            editedText = draftPhotoCaptions[id] ?? ""
        }
    }

    /// Double-tap zooms in at 1×; when zoomed, double-tap resets. Single tap at 1× closes; single tap when zoomed resets zoom.
    private func expandedPhotoPreviewImageTapGesture() -> some Gesture {
        let doubleTap = TapGesture(count: 2).onEnded {
            if expandedPhotoPreviewScale <= 1.05 {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedPhotoPreviewScale = 2.5
                    expandedPhotoPreviewOffset = .zero
                }
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedPhotoPreviewScale = 1.0
                    expandedPhotoPreviewOffset = .zero
                }
            }
        }
        let singleTap = TapGesture(count: 1).onEnded {
            if expandedPhotoPreviewScale <= 1.05 {
                dismissExpandedPhotoPreview()
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedPhotoPreviewScale = 1.0
                    expandedPhotoPreviewOffset = .zero
                }
            }
        }
        return doubleTap.exclusively(before: singleTap)
    }

    @ViewBuilder
    private func expandedPhotoPreviewOverlay(photo: RecapPhoto) -> some View {
        let scale = max(1.0, expandedPhotoPreviewScale * expandedPhotoPreviewPinch)
        let offset = CGSize(
            width: expandedPhotoPreviewOffset.width + expandedPhotoPreviewDrag.width,
            height: expandedPhotoPreviewOffset.height + expandedPhotoPreviewDrag.height
        )

        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissExpandedPhotoPreview()
                }

            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: 12,
                showIcon: false,
                targetSize: CGSize(width: 1600, height: 1600)
            )
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 56)
            .scaleEffect(scale)
            .offset(offset)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .updating($expandedPhotoPreviewPinch) { current, state, _ in state = current }
                        .onEnded { value in
                            let newScale = max(1.0, min(5.0, expandedPhotoPreviewScale * value))
                            if newScale <= 1.05 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedPhotoPreviewScale = 1.0
                                    expandedPhotoPreviewOffset = .zero
                                }
                            } else {
                                expandedPhotoPreviewScale = newScale
                            }
                        },
                    DragGesture(minimumDistance: 5)
                        .updating($expandedPhotoPreviewDrag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            expandedPhotoPreviewOffset = CGSize(
                                width: expandedPhotoPreviewOffset.width + value.translation.width,
                                height: expandedPhotoPreviewOffset.height + value.translation.height
                            )
                        }
                )
            )
            .highPriorityGesture(expandedPhotoPreviewImageTapGesture())

            Button {
                dismissExpandedPhotoPreview()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("Close photo preview")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var placeCaptionThumbnailCell: some View {
        let placeSelected = captionThumbnailSelection == .placeCaption
        return Button {
            selectThumbnail(.placeCaption)
        } label: {
            ZStack {
                RoundedRectangle(appChromeBaseRadius: thumbnailCorner, style: .continuous)
                    .fill(placeSelected ? Color.white : Color.clear)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(placeSelected ? Color.black : Color.white)
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .opacity(placeSelected ? 1 : 0.6)
            .overlay {
                RoundedRectangle(appChromeBaseRadius: thumbnailCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: thumbnailStroke)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Place caption")
    }

    private func photoThumbnailCell(_ photo: RecapPhoto) -> some View {
        let photoSelected = captionThumbnailSelection == .photo(photo.id)
        return Button {
            selectThumbnail(.photo(photo.id))
        } label: {
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: thumbnailCorner,
                showIcon: false,
                targetSize: CGSize(width: 200, height: 200)
            )
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(appChromeBaseRadius: thumbnailCorner, style: .continuous))
            .overlay {
                RoundedRectangle(appChromeBaseRadius: thumbnailCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: photoSelected ? thumbnailStroke : 0)
            }
            .opacity(photoSelected ? 1 : (captionThumbnailSelection == .placeCaption ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo thumbnail")
    }

    private var currentStyleTitle: String {
        StoryWritingStyle.preset(for: stylePresetId)?.title
            ?? StoryWritingStyle.preset(matching: UserDefaults.standard.string(forKey: StoryWritingStyle.storageKey) ?? "")?.title
            ?? "Custom"
    }

    /// Photo strip selection is a concrete photo — used for on-device “fun AI” line (not the place row).
    private var selectedPhotoForFunAI: RecapPhoto? {
        guard case .photo(let id) = captionThumbnailSelection else { return nil }
        return captionStripPhotos.first(where: { $0.id == id })
    }

    private var placeCaptionBlocksAIShortStory: Bool {
        overallStoryIsManual && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func photoCaptionBlocksAIShortStory(photo: RecapPhoto) -> Bool {
        photo.captionIsManual && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runFunPhotoInsight(photo: RecapPhoto) {
        guard LocalLLMStoryCaptionGenerator.isCapable,
              selectedPhotoHasVisionTagsForAIStory,
              !photoCaptionBlocksAIShortStory(photo: photo) else { return }
        if originalDraft == nil { originalDraft = editedText }
        isGeneratingAIShortStory = true
        DispatchQueue.main.async { isFocused = false }
        let hintRaw = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoId = photo.id
        Task {
            let text = await StoryCaptionService.shared.generateFunPhotoInsight(
                photo: photo,
                placeName: placeTitle,
                placeSubtitle: placeSubtitle,
                placeCategoryMK: placeCategory,
                visitTimeZone: nil,
                userCaptionHint: hintRaw.isEmpty ? nil : hintRaw
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                isGeneratingAIShortStory = false
                guard selectedPhotoForFunAI?.id == photoId else { return }
                if !trimmed.isEmpty {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        editedText = trimmed
                    }
                    flushCurrentDraftFromEditor()
                    onFunPhotoInsightApplied?(photoId)
                }
            }
        }
    }

    private func runPlaceAIShortStory() {
        guard let gen = onGeneratePlaceAIShortStory,
              LocalLLMStoryCaptionGenerator.isCapable,
              !placeCaptionBlocksAIShortStory else { return }
        if originalDraft == nil { originalDraft = editedText }
        isGeneratingAIShortStory = true
        DispatchQueue.main.async { isFocused = false }
        Task {
            let text = await gen()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                isGeneratingAIShortStory = false
                guard captionThumbnailSelection == .placeCaption else { return }
                if !trimmed.isEmpty {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        editedText = trimmed
                    }
                    flushCurrentDraftFromEditor()
                    onEnhanceApplied?()
                }
            }
        }
    }

    private func runEnhance(_ enhance: @escaping (String) async -> String, preset: StoryWritingStylePreset?) {
        guard !isGeneratingAIShortStory else { return }
        if let preset {
            stylePresetId = preset.id
            UserDefaults.standard.set(preset.prompt, forKey: StoryWritingStyle.storageKey)
        }
        if originalDraft == nil { originalDraft = editedText }
        let textToEnhance = editedText
        isEnhancing = true
        Task {
            let result = await enhance(textToEnhance)
            await MainActor.run {
                editedText = result
                isEnhancing = false
                onEnhanceApplied?()
            }
        }
    }

    private func runTranslate(_ translate: @escaping (String) async -> String) {
        guard !isGeneratingAIShortStory else { return }
        if originalDraft == nil { originalDraft = editedText }
        let textToTranslate = editedText
        isTranslating = true
        Task {
            let result = await translate(textToTranslate)
            await MainActor.run {
                editedText = result
                isTranslating = false
            }
        }
    }
}
