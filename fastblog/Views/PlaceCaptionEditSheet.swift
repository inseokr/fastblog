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
    /// Bindings for per-photo captions (only the first three thumbnails are shown).
    var photoCaption: (UUID) -> Binding<String>
    /// `placeCaptionChanged` / `changedPhotoIds` reflect edits vs. values when the sheet opened.
    var onSave: (_ placeCaptionChanged: Bool, _ changedPhotoIds: Set<UUID>) -> Void
    var onCancel: () -> Void
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
    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showPlaceSearchWebPanel = false
    @State private var embeddedSearchCurrentURL: URL?
    @State private var pendingOpenPlaceSearchAfterKeyboardDismiss = false
    /// True when embedded search was opened while the caption editor had keyboard focus.
    @State private var restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
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

    /// Horizontal inset for typed text inside the rounded editor (both sides). Slightly tight so the caret sits a bit left of default.
    private let editorTextHorizontalPadding: CGFloat = 14
    /// Matches `editorTextHorizontalPadding` so placeholder lines up with the caret (outer sheet padding is on the ZStack, not inside it).
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
                ForEach(photos.prefix(3)) { photo in
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

    private var deviceSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    private var referenceScreenBoundsHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.height
            ?? UIScreen.main.bounds.height
    }

    private var placeTitleRowWithSearchButton: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(placeTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Image(systemName: showPlaceSearchWebPanel ? "chevron.down.circle.fill" : "magnifyingglass.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            perform: { commitEmbeddedPlaceSearchToggleFromTitleRow() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(placeTitle), place")
        .accessibilityHint(showPlaceSearchWebPanel ? "Hides search panel above" : "Shows search in browser above while you write")
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
    private var placeCaptionSearchAndTitleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showPlaceSearchWebPanel,
               let searchURL = StoryPlaceGoogleSearch.url(placeName: placeTitle, placeSubtitle: placeSubtitle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Button {
                            openEmbeddedPlaceSearchInDefaultBrowser()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("Open in browser")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                StoryPlaceExternalLinkIcon(titleFontSize: 16, foregroundColor: .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Open in browser")
                        .accessibilityHint("Opens this page in your default browser")
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, Color.primary.opacity(0.35))
                            .contentShape(Rectangle())
                            .padding(4)
                            .onLongPressGesture(
                                minimumDuration: 0,
                                maximumDistance: 64,
                                perform: { dismissEmbeddedPlaceSearchFromChrome() }
                            )
                            .accessibilityLabel("Close search")
                            .accessibilityAddTraits(.isButton)
                    }
                    // Keeps this row below Cancel/Done; avoids visual overlap with the main header bar.
                    .padding(.vertical, 6)
                    GoogleSearchEmbeddedWebView(url: searchURL, currentPageURL: $embeddedSearchCurrentURL)
                        .frame(height: placeCaptionEmbeddedSearchWebHeight(
                            layoutHeight: referenceScreenBoundsHeight,
                            safeTopInset: deviceSafeAreaInsets.top,
                            captionFieldFocused: isFocused
                        ))
                        .animation(nil, value: isFocused)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .padding(.top, 4)
                .padding(.bottom, 4)
                // Moving from the top animates into the same band as Cancel/Done and reads as overlap.
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Photo vs place caption is indicated by the thumbnail strip; no large preview (redundant, wastes vertical space).
            VStack(alignment: .leading, spacing: 4) {
                placeTitleRowWithSearchButton
                placeSubtitleIfAny
                if case .photo(let photoId) = captionThumbnailSelection, let openFull = onRequestFullPhotoView {
                    Button {
                        syncDraftToUnderlyingBindings()
                        restoreCaptionKeyboardAfterPhotoModal = isFocused
                        isFocused = false
                        openFull(photoId)
                    } label: {
                        Text("View full-size photo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBlue))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captionEditTopBar: some View {
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

            Button("Done") {
                flushCurrentDraftFromEditor()
                caption = draftPlaceCaption
                for p in photos.prefix(3) {
                    photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
                }
                let placeChanged = draftPlaceCaption != initialPlaceCaption
                let changedPhotoIds = Set(
                    photos.prefix(3).map(\.id).filter { id in
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
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemBackground))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !showPlaceSearchWebPanel {
                captionEditTopBar
            }

            placeCaptionSearchAndTitleHeader
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $editedText)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundColor(.primary)
                    .tint(Color(white: 0.92))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .padding(.horizontal, editorTextHorizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
        .preferredColorScheme(.dark)
        .onAppear {
            initialPlaceCaption = caption
            draftPlaceCaption = caption
            var photoMap: [UUID: String] = [:]
            for p in photos.prefix(3) {
                photoMap[p.id] = p.caption ?? ""
            }
            initialPhotoCaptions = photoMap
            draftPhotoCaptions = photoMap
            editedText = draftPlaceCaption
            captionThumbnailSelection = .placeCaption
            DispatchQueue.main.async {
                if !showPlaceSearchWebPanel {
                    isFocused = true
                }
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
        .onChange(of: isFocused) { _, focused in
            if focused {
                pendingOpenPlaceSearchAfterKeyboardDismiss = false
                closeEmbeddedSearchForCaptionInteraction()
            } else if pendingOpenPlaceSearchAfterKeyboardDismiss {
                pendingOpenPlaceSearchAfterKeyboardDismiss = false
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    showPlaceSearchWebPanel = true
                }
            }
        }
        .onChange(of: editedText) { _, _ in
            if showPlaceSearchWebPanel {
                closeEmbeddedSearchForCaptionInteraction()
            }
        }
        .onChange(of: showPlaceSearchWebPanel) { _, isShown in
            if !isShown {
                embeddedSearchCurrentURL = nil
            }
        }
    }

    private func placeCaptionEmbeddedSearchWebHeight(layoutHeight: CGFloat, safeTopInset: CGFloat, captionFieldFocused: Bool) -> CGFloat {
        let compactHeight: CGFloat = 240
        guard !captionFieldFocused else { return compactHeight }
        let topBarChrome = safeTopInset + 56
        let titleAndSpacing: CGFloat = 72
        let thumbStripReserve: CGFloat = photos.isEmpty ? 0 : (thumbnailSize + 8 + 10 + 12 + 20)
        let bottomReserve: CGFloat = captionTextEditorFixedHeight + titleAndSpacing + thumbStripReserve + 100
        let verticalBreathingRoom: CGFloat = 40
        let available = layoutHeight - topBarChrome - bottomReserve - verticalBreathingRoom
        return max(compactHeight, available)
    }

    private func openEmbeddedPlaceSearchInDefaultBrowser() {
        let fallback = StoryPlaceGoogleSearch.url(placeName: placeTitle, placeSubtitle: placeSubtitle)
        guard let url = embeddedSearchCurrentURL ?? fallback else { return }
        UIApplication.shared.open(url)
    }

    private func dismissEmbeddedPlaceSearchFromChrome() {
        guard showPlaceSearchWebPanel else { return }
        let restoreKeyboard = restoreCaptionKeyboardWhenEmbeddedSearchCloses
        restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            showPlaceSearchWebPanel = false
        }
        if restoreKeyboard {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private func closeEmbeddedSearchForCaptionInteraction() {
        guard showPlaceSearchWebPanel else { return }
        restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            showPlaceSearchWebPanel = false
        }
    }

    private func commitEmbeddedPlaceSearchToggleFromTitleRow() {
        let name = placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              StoryPlaceGoogleSearch.url(placeName: name, placeSubtitle: placeSubtitle) != nil else { return }
        let wasOpen = showPlaceSearchWebPanel
        if !wasOpen {
            if isFocused {
                restoreCaptionKeyboardWhenEmbeddedSearchCloses = true
                pendingOpenPlaceSearchAfterKeyboardDismiss = true
                isFocused = false
                return
            }
            restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                showPlaceSearchWebPanel = true
            }
            return
        }
        let restoreKeyboard = restoreCaptionKeyboardWhenEmbeddedSearchCloses
        restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            showPlaceSearchWebPanel = false
        }
        if restoreKeyboard {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    /// Pushes in-memory drafts into the recap bindings so `PlacePhotoModalView` sees the latest text.
    private func syncDraftToUnderlyingBindings() {
        flushCurrentDraftFromEditor()
        caption = draftPlaceCaption
        for p in photos.prefix(3) {
            photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
        }
    }

    /// After the full-screen photo viewer dismisses, pull caption text from bindings (modal may have edited them).
    private func refreshDraftFromBindings() {
        draftPlaceCaption = caption
        for p in photos.prefix(3) {
            draftPhotoCaptions[p.id] = photoCaption(p.id).wrappedValue
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

    private func selectThumbnail(_ newSelection: CaptionThumbnailSelection) {
        guard newSelection != captionThumbnailSelection else { return }
        flushCurrentDraftFromEditor()
        pendingOpenPlaceSearchAfterKeyboardDismiss = false
        let restoreAfterSearch = restoreCaptionKeyboardWhenEmbeddedSearchCloses
        restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            showPlaceSearchWebPanel = false
        }
        embeddedSearchCurrentURL = nil
        if restoreAfterSearch {
            DispatchQueue.main.async { isFocused = true }
        }
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
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                    .fill(placeSelected ? Color.white : Color.clear)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(placeSelected ? Color.black : Color.white)
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .opacity(placeSelected ? 1 : 0.6)
            .overlay {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
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
