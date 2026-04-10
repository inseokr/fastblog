//
//  PlaceCaptionEditSheet.swift
//  fastblog
//
//  Full-screen place story editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI
import UIKit

struct PlaceCaptionEditSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    @Binding var caption: String
    /// Bindings for per-photo captions (only the first three displayable thumbnails are shown in the strip).
    var photoCaption: (UUID) -> Binding<String>
    /// `placeCaptionChanged` / `changedPhotoIds` reflect edits vs. values when the sheet opened.
    var onSave: (_ placeCaptionChanged: Bool, _ changedPhotoIds: Set<UUID>) -> Void
    var onCancel: () -> Void
    var confirmLabel: String = "Save"
    /// When provided, the Enhance button is shown. Receives the draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result (so caller can mark overallStoryIsManual = false).
    var onEnhanceApplied: (() -> Void)? = nil
    /// Pure translation — no AI story generation.
    var onTranslate: ((String) async -> String)? = nil
    /// Parent presents recap `PlacePhotoModalView` for this photo id (e.g. sets `placePhotoModalItem`).
    var onRequestFullPhotoView: ((UUID) -> Void)? = nil
    /// Match `PlacePhotoModalItem.id` while that modal is presented; when it becomes nil, local drafts reload from bindings.
    var activePhotoModalToken: String? = nil
    /// Parent presents `EditPlaceStopNameSheet` (same as blog edit-mode place row).
    var onRequestEditPlaceName: (() -> Void)? = nil
    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @State private var isFocused: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// Restore caption focus after full-screen photo modal dismisses if it was focused before open.
    @State private var restoreCaptionKeyboardAfterPhotoModal = false

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

    /// Up to three photos that still resolve to real pixels (omits removed / missing library assets so the strip never shows gradient placeholders).
    private var captionStripPhotos: [RecapPhoto] {
        Array(photos.filter(\.hasDisplayableLocalBacking).prefix(3))
    }

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

    /// Caption editor uses a **fixed** height (scrolls inside). It must not expand with spare vertical space,
    /// or the thumbnail strip can end up under the keyboard on small phones at large Dynamic Type sizes.
    private var captionTextEditorFixedHeight: CGFloat {
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

    @ViewBuilder
    private var placeCaptionTitleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if case .photo(let photoId) = captionThumbnailSelection {
                    VStack(alignment: .leading, spacing: 4) {
                        placeTitleRowWithEditNameControl
                        placeSubtitleIfAny
                        if onRequestFullPhotoView != nil {
                            Button {
                                presentFullPhotoViewer(for: photoId)
                            } label: {
                                Text("View full photo")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(uiColor: .systemBlue))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View full photo")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        placeTitleRowWithEditNameControl
                        placeSubtitleIfAny
                    }
                }
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
            .frame(height: captionTextEditorFixedHeight)
            .padding(.horizontal, 20)

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
                            Label("", systemImage: "arrow.uturn.backward")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
                        .disabled(isEnhancing || isTranslating)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)
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
        .preferredColorScheme(.dark)
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
        .onChange(of: activePhotoModalToken) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                refreshDraftFromBindings()
                if restoreCaptionKeyboardAfterPhotoModal {
                    restoreCaptionKeyboardAfterPhotoModal = false
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
            }
        }
    }

    private func requestEditPlaceName(openEditor: @escaping () -> Void) {
        syncDraftToUnderlyingBindings()
        isFocused = false
        openEditor()
    }

    /// Pushes in-memory drafts into the recap bindings so `PlacePhotoModalView` sees the latest text.
    private func syncDraftToUnderlyingBindings() {
        flushCurrentDraftFromEditor()
        caption = draftPlaceCaption
        for p in captionStripPhotos {
            photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
        }
    }

    /// After the full-screen photo viewer dismisses, pull caption text from bindings (modal may have edited them).
    private func refreshDraftFromBindings() {
        draftPlaceCaption = caption
        for p in captionStripPhotos {
            draftPhotoCaptions[p.id] = photoCaption(p.id).wrappedValue
        }
        if case .photo(let id) = captionThumbnailSelection,
           !captionStripPhotos.contains(where: { $0.id == id }) {
            captionThumbnailSelection = .placeCaption
        }
        switch captionThumbnailSelection {
        case .placeCaption:
            editedText = draftPlaceCaption
        case .photo(let id):
            editedText = draftPhotoCaptions[id] ?? ""
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

    private func presentFullPhotoViewer(for photoId: UUID) {
        guard let openFull = onRequestFullPhotoView else { return }
        syncDraftToUnderlyingBindings()
        restoreCaptionKeyboardAfterPhotoModal = isFocused
        isFocused = false
        openFull(photoId)
    }

    private func selectThumbnail(_ newSelection: CaptionThumbnailSelection) {
        if newSelection == captionThumbnailSelection {
            if case .photo(let photoId) = newSelection {
                presentFullPhotoViewer(for: photoId)
            }
            return
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

    private func runEnhance(_ enhance: @escaping (String) async -> String, preset: StoryWritingStylePreset?) {
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
