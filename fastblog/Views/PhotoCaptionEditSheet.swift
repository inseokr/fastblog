//
//  PhotoCaptionEditSheet.swift
//  fastblog
//
//  Full-screen photo caption editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI

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
    @FocusState private var isFocused: Bool

    private let editorTextHorizontalPadding: CGFloat = 14
    private let placeholderLeadingInset: CGFloat = 34
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hero image for the editor; tappable when `onRequestFullPhotoView` is set.
    private var mainEditorPhotoBase: some View {
        RecapPhotoThumbnail(
            photo: photo,
            cornerRadius: 12,
            showIcon: false,
            targetSize: CGSize(width: 600, height: 400)
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var body: some View {
        // No nested NavigationStack: RecapBlogPageView already lives in NavigationStack and hides the nav bar
        // while this overlay is up — inner `.toolbar` items can fail to show or receive taps.
        VStack(spacing: 0) {
            // Photo fills available space — before keyboard: full modal; after keyboard: shrinks naturally
            Group {
                if let openFull = onRequestFullPhotoView {
                    Button {
                        caption = editedText
                        isFocused = false
                        openFull()
                    } label: {
                        mainEditorPhotoBase
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View full photo")
                } else {
                    mainEditorPhotoBase
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Place title as context
            VStack(alignment: .leading, spacing: 4) {
                Text(placeTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let placeSubtitle, !placeSubtitle.isEmpty {
                    Text(placeSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Text editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editedText)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundColor(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, editorTextHorizontalPadding)
                    .padding(.vertical, 14)
                    .frame(minHeight: 140)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)

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
                                Image(systemName: "translate")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
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
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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

                Button("Done") {
                    caption = editedText
                    isFocused = false
                    onSave()
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
            editedText = caption
            DispatchQueue.main.async {
                isFocused = true
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
