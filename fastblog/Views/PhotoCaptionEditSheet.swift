//
//  PhotoCaptionEditSheet.swift
//  fastblog
//
//  Full-screen photo caption editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI
import UIKit

struct PhotoCaptionEditSheet: View {
    let photo: RecapPhoto
    let placeTitle: String
    let placeSubtitle: String?
    @Binding var caption: String
    var onSave: () -> Void
    var onCancel: () -> Void
    /// When provided, the Enhance button is shown. Receives the draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result.
    var onEnhanceApplied: (() -> Void)? = nil
    /// Pure translation — no AI story generation.
    var onTranslate: ((String) async -> String)? = nil
    /// Parent presents recap `PlacePhotoModalView` for this photo.
    var onRequestFullPhotoView: (() -> Void)? = nil
    /// Match `PlacePhotoModalItem.id` while that modal is presented; when it becomes nil, editor text reloads from the caption binding.
    var activePhotoModalToken: String? = nil

    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @State private var wantsCaptionKeyboardFocus = false
    @State private var showPlaceSearchWebPanel = false
    @State private var embeddedSearchCurrentURL: URL?
    @State private var pendingOpenPlaceSearchAfterKeyboardDismiss = false
    /// True when embedded search was opened while the caption editor had keyboard focus (keyboard is dismissed while search is visible).
    @State private var restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
    /// Restore caption focus after full-screen photo modal dismisses if it was focused before open.
    @State private var restoreCaptionKeyboardAfterPhotoModal = false
    @State private var captionScrollContentHeight: CGFloat = 0
    @State private var captionScrollVisibleHeight: CGFloat = 0
    @State private var captionScrollOffsetY: CGFloat = 0

    private let editorTextHorizontalPadding: CGFloat = 14
    private let placeholderLeadingInset: CGFloat = 34
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var photoCaptionPlaceTitleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(placeTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Image(systemName: showPlaceSearchWebPanel ? "chevron.down.circle.fill" : "magnifyingglass.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            perform: { commitEmbeddedPlaceSearchToggleFromPhotoCaptionSheet() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(placeTitle), place")
        .accessibilityHint(showPlaceSearchWebPanel ? "Hides search panel above" : "Shows search in browser above while you write")
    }

    @ViewBuilder
    private var photoCaptionEmbeddedSearchBlock: some View {
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
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 2)
                            StoryPlaceExternalLinkIcon(titleFontSize: 16, foregroundColor: .white)
                                .shadow(color: .black.opacity(0.35), radius: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Open in browser")
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .white.opacity(0.35))
                        .contentShape(Rectangle())
                        .padding(4)
                        .onLongPressGesture(
                            minimumDuration: 0,
                            maximumDistance: 64,
                            perform: { dismissEmbeddedPlaceSearchFromChromePhotoSheet() }
                        )
                        .accessibilityLabel("Close search")
                        .accessibilityAddTraits(.isButton)
                }
                GoogleSearchEmbeddedWebView(url: searchURL, currentPageURL: $embeddedSearchCurrentURL)
                    .frame(height: photoCaptionSheetEmbeddedSearchWebHeight(
                        layoutHeight: referenceScreenBoundsHeight,
                        safeTopInset: deviceSafeAreaInsets.top,
                        captionFieldFocused: wantsCaptionKeyboardFocus
                    ))
                    .animation(nil, value: wantsCaptionKeyboardFocus)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            }
            .padding(.bottom, 8)
            .transition(.move(edge: .top))
        }
    }

    var body: some View {
        // No nested NavigationStack: RecapBlogPageView already lives in NavigationStack and hides the nav bar
        // while this overlay is up — inner `.toolbar` items can fail to show or receive taps.
        ZStack {
            // Full-screen dimmed photo background
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: 0,
                showIcon: false,
                targetSize: CGSize(width: 600, height: 900)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.52).ignoresSafeArea())
            .allowsHitTesting(onRequestFullPhotoView != nil)
            .onTapGesture {
                guard let openFull = onRequestFullPhotoView else { return }
                caption = editedText
                restoreCaptionKeyboardAfterPhotoModal = wantsCaptionKeyboardFocus
                wantsCaptionKeyboardFocus = false
                openFull()
            }

            // Overlaid content (no opaque background). Cancel/Done live in the scroll stack so they sit in the
            // safe area below the status bar — `safeAreaInset(edge: .top)` fought overlay layout and hid Done.
            VStack(spacing: 0) {
                if !showPlaceSearchWebPanel {
                    HStack(alignment: .center) {
                        Button("Cancel") {
                            wantsCaptionKeyboardFocus = false
                            onCancel()
                        }
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Done") {
                            caption = editedText
                            wantsCaptionKeyboardFocus = false
                            onSave()
                        }
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(Color(uiColor: .systemBlue))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)

                    Spacer(minLength: 0)
                }

                photoCaptionEmbeddedSearchBlock
                    .padding(.horizontal, 20)
                    .padding(.top, showPlaceSearchWebPanel ? 8 : 0)

                VStack(alignment: .leading, spacing: 4) {
                    photoCaptionPlaceTitleRow
                    if let placeSubtitle, !placeSubtitle.isEmpty {
                        Text(placeSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                // Text editor
                ZStack(alignment: .topLeading) {
                    ScrollMetricsReportingTextEditor(
                        text: $editedText,
                        contentHeight: $captionScrollContentHeight,
                        visibleViewportHeight: $captionScrollVisibleHeight,
                        scrollOffsetY: $captionScrollOffsetY,
                        wantsKeyboardFocus: $wantsCaptionKeyboardFocus,
                        textInsets: UIEdgeInsets(
                            top: 14,
                            left: editorTextHorizontalPadding,
                            bottom: 14,
                            right: editorTextHorizontalPadding
                        ),
                        caretTint: .white
                    )
                    .frame(minHeight: 140)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .overlay(alignment: .topTrailing) {
                        GeometryReader { geo in
                            CaptionEditorVerticalScrollThumb(
                                contentHeight: captionScrollContentHeight,
                                visibleHeight: captionScrollVisibleHeight,
                                scrollOffsetY: captionScrollOffsetY,
                                trackLength: geo.size.height
                            )
                            .padding(.trailing, 26)
                        }
                        .allowsHitTesting(false)
                    }

                    if editedText.isEmpty {
                        Text("Describe this moment...")
                            .font(.body)
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .padding(.leading, placeholderLeadingInset)
                            .padding(.trailing, placeholderTrailingInset)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
                .contentShape(Rectangle())

                // Action bar
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
                                    .foregroundColor(.white.opacity(0.7))
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
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                } else {
                                    Image(systemName: "translate")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .disabled(isEnhancing || isTranslating)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            editedText = caption
            DispatchQueue.main.async {
                if !showPlaceSearchWebPanel {
                    wantsCaptionKeyboardFocus = true
                }
            }
        }
        .onChange(of: activePhotoModalToken) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                editedText = caption
                if restoreCaptionKeyboardAfterPhotoModal {
                    restoreCaptionKeyboardAfterPhotoModal = false
                    DispatchQueue.main.async {
                        wantsCaptionKeyboardFocus = true
                    }
                }
            }
        }
        .onChange(of: wantsCaptionKeyboardFocus) { _, focused in
            if focused {
                pendingOpenPlaceSearchAfterKeyboardDismiss = false
                closeEmbeddedSearchForPhotoCaptionSheet()
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
                closeEmbeddedSearchForPhotoCaptionSheet()
            }
        }
        .onChange(of: showPlaceSearchWebPanel) { _, isShown in
            if !isShown {
                embeddedSearchCurrentURL = nil
            }
        }
    }

    private func photoCaptionSheetEmbeddedSearchWebHeight(layoutHeight: CGFloat, safeTopInset: CGFloat, captionFieldFocused: Bool) -> CGFloat {
        let compactHeight: CGFloat = 220
        guard !captionFieldFocused else { return compactHeight }
        let topBarChrome = safeTopInset + 56
        let bottomReserve: CGFloat = 300
        let verticalBreathingRoom: CGFloat = 36
        let available = layoutHeight - topBarChrome - bottomReserve - verticalBreathingRoom
        return max(compactHeight, available)
    }

    private func openEmbeddedPlaceSearchInDefaultBrowser() {
        let fallback = StoryPlaceGoogleSearch.url(placeName: placeTitle, placeSubtitle: placeSubtitle)
        guard let url = embeddedSearchCurrentURL ?? fallback else { return }
        UIApplication.shared.open(url)
    }

    private func dismissEmbeddedPlaceSearchFromChromePhotoSheet() {
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
                wantsCaptionKeyboardFocus = true
            }
        }
    }

    private func closeEmbeddedSearchForPhotoCaptionSheet() {
        guard showPlaceSearchWebPanel else { return }
        restoreCaptionKeyboardWhenEmbeddedSearchCloses = false
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            showPlaceSearchWebPanel = false
        }
    }

    private func commitEmbeddedPlaceSearchToggleFromPhotoCaptionSheet() {
        let name = placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              StoryPlaceGoogleSearch.url(placeName: name, placeSubtitle: placeSubtitle) != nil else { return }
        let wasOpen = showPlaceSearchWebPanel
        if !wasOpen {
            if wantsCaptionKeyboardFocus {
                restoreCaptionKeyboardWhenEmbeddedSearchCloses = true
                pendingOpenPlaceSearchAfterKeyboardDismiss = true
                wantsCaptionKeyboardFocus = false
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
                wantsCaptionKeyboardFocus = true
            }
        }
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
