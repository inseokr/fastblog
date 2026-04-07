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
    @State private var wantsCaptionKeyboardFocus = false
    /// Restore caption focus after full-screen photo modal dismisses if it was focused before open.
    @State private var restoreCaptionKeyboardAfterPhotoModal = false

    private let editorTextHorizontalPadding: CGFloat = 14
    private let placeholderLeadingInset: CGFloat = 34
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches `PlaceStopRowView` edit-mode title row on dark caption chrome.
    @ViewBuilder
    private var photoCaptionPlaceTitleRow: some View {
        if let onEdit = onRequestEditPlaceName {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    caption = editedText
                    wantsCaptionKeyboardFocus = false
                    onEdit()
                } label: {
                    Text(placeTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Button {
                    caption = editedText
                    wantsCaptionKeyboardFocus = false
                    onEdit()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
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
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
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

            VStack(spacing: 0) {
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
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)

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

                Button("Save") {
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
                if restoreCaptionKeyboardAfterPhotoModal {
                    restoreCaptionKeyboardAfterPhotoModal = false
                    DispatchQueue.main.async {
                        wantsCaptionKeyboardFocus = true
                    }
                }
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
