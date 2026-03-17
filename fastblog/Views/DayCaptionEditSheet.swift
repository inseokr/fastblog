//
//  DayCaptionEditSheet.swift
//  fastblog
//
//  Pull-up modal for editing a day-level caption in Recap Blog Edit Mode.
//

import SwiftUI

struct DayCaptionEditSheet: View {
    /// e.g. "Day 1 · Saturday Jan-18"
    let dayLabel: String
    @Binding var caption: String
    var onSave: () -> Void
    var onCancel: () -> Void
    /// When provided, the Enhance button is shown. Receives current draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result.
    var onEnhanceApplied: (() -> Void)? = nil

    @State private var editedText: String = ""
    @State private var isEnhancing = false
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    // ── Caption editor ────────────────────────────────────
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $editedText)
                            .focused($isFocused)
                            .font(.body)
                            .foregroundColor(.primary)
                            .scrollContentBackground(.hidden)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(14)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                        // Placeholder
                        if editedText.isEmpty {
                            Text("Describe your day in a sentence…")
                                .font(.body)
                                .foregroundColor(Color(uiColor: .placeholderText))
                                .padding(.horizontal, 28)
                                .padding(.top, 24)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // ── Action bar — shown when text is non-empty ─────────
                    let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
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
                                                        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                            Text("Enhance")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
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
                }
            }
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        caption = editedText
                        onSave()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            editedText = caption
            // slight delay so the sheet finishes its animation before keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
