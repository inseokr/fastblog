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
    @State private var captionScrollContentHeight: CGFloat = 0
    @State private var captionScrollVisibleHeight: CGFloat = 0
    @State private var captionScrollOffsetY: CGFloat = 0

    private let editorTextHorizontalPadding: CGFloat = 14
    private let placeholderLeadingInset: CGFloat = 34
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                wantsCaptionKeyboardFocus = false
                openFull()
            }

            // Overlaid content (no opaque background)
            VStack(spacing: 0) {
                Spacer()

                // Place title as context
                VStack(alignment: .leading, spacing: 4) {
                    Text(placeTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let placeSubtitle, !placeSubtitle.isEmpty {
                        Text(placeSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

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
                        )
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
                            .padding(.top, 22)
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
        .safeAreaInset(edge: .top, spacing: 0) {
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
            .padding(.vertical, 12)
            .background(Color.clear)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            editedText = caption
            DispatchQueue.main.async {
                wantsCaptionKeyboardFocus = true
            }
        }
        .onChange(of: activePhotoModalToken) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                editedText = caption
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
