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

    @State private var editedText: String = ""
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

                    // ── Clear button — shown only when text is non-empty ──
                    if !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                editedText = ""
                            }
                        } label: {
                            Label("Clear caption", systemImage: "trash")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.bottom, 20)
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
