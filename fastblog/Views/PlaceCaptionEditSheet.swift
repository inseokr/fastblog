//
//  PlaceCaptionEditSheet.swift
//  fastblog
//
//  Full-screen place story editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI

struct PlaceCaptionEditSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    @Binding var caption: String
    var onSave: () -> Void
    var onCancel: () -> Void
    /// When provided, the Enhance button is shown. Receives current draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result (so caller can mark overallStoryIsManual = false).
    var onEnhanceApplied: (() -> Void)? = nil

    @State private var editedText: String = ""
    @State private var isEnhancing = false
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @FocusState private var isFocused: Bool

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
                // Top chrome: only Cancel + Done (no NavigationStack — avoids duplicate back / parent toolbar bleed).
                HStack(alignment: .center) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Done") {
                        caption = editedText
                        onSave()
                    }
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

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

                // Caption editor — below the top row + title, with comfortable inset.
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)

                    if editedText.isEmpty {
                        Text("Write a caption for this place…")
                            .font(.body)
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .padding(.leading, 40)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

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
                                Label("Revert", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let enhance = onEnhance {
                            Button {
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
                            } label: {
                                if isEnhancing {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.75)
                                        Text("Enhancing…")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.subheadline)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color(red: 0.82, green: 0.48, blue: 0.95), Color(red: 0.62, green: 0.32, blue: 0.78)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        Text("Enhance")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                            .disabled(isEnhancing)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
                                RecapPhotoThumbnail(
                                    photo: photo,
                                    cornerRadius: 10,
                                    showIcon: false,
                                    targetSize: CGSize(width: 200, height: 200)
                                )
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 60)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemBackground))
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
}
