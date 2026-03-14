//
//  PlaceCaptionEditSheet.swift
//  fastblog
//
//  Pull-up modal for editing a place-level overall story in Recap Blog Edit Mode.
//

import SwiftUI

struct PlaceCaptionEditSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    @Binding var caption: String
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var editedText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Caption editor region ─────────────────────────────
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

                    // Placeholder
                    if editedText.isEmpty {
                        Text("Write a caption for this place…")
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
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // ── Photo strip — anchored just above keyboard ────────
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
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle(placeTitle)
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
