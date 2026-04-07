//
//  DayCaptionEditSheet.swift
//  fastblog
//
//  Full-screen day story editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI

struct DayCaptionEditSheet: View {
    /// Trip day ordinal (shown as "Day N").
    let dayNumber: Int
    /// Weekday, month, and date (e.g. "Saturday, January 18").
    let dateLine: String
    @Binding var caption: String
    var onSave: () -> Void
    var onCancel: () -> Void
    /// When provided, the Enhance button is shown.
    /// Receives the draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result.
    var onEnhanceApplied: (() -> Void)? = nil
    /// Pure translation — no AI story generation.
    var onTranslate: ((String) async -> String)? = nil

    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @FocusState private var isFocused: Bool

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .buttonStyle(.plain)

                Spacer()

                Button {
                    caption = editedText
                    onSave()
                } label: {
                    Text("Done")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(Color(uiColor: .systemBlue))
                }
                .buttonStyle(.plain)
                .tint(Color(uiColor: .systemBlue))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(dayNumber)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                    Text(dateLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $editedText)
                        .focused($isFocused)
                        .font(.body)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(minHeight: 180)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)

                    if editedText.isEmpty {
                        Text("Describe your day in a sentence…")
                            .font(.body)
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .padding(.leading, 40)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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

                    if let translate = onTranslate, !trimmedEditedText.isEmpty {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .defaultFocus($isFocused, true)
        .onAppear {
            editedText = caption
            DispatchQueue.main.async {
                isFocused = true
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
