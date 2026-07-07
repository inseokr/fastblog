//
//  TripNarrativeEditSheet.swift
//  fastblog
//
//  Full-screen trip-level story editor (fade overlay from RecapBlogPageView).
//

import SwiftUI

struct TripNarrativeEditSheet: View {
    let blogTitle: String
    @Binding var narrative: String
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var editedText: String = ""
    @State private var originalDraft: String?
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var narrativeInputBackground: Color {
        colorScheme == .dark ? Color(white: 0.14) : Color(uiColor: .secondarySystemBackground)
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
                    narrative = editedText
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
                    Text("Trip story")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                    Text(blogTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
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
                        .background(narrativeInputBackground)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)

                    if editedText.isEmpty {
                        Text("Introduce your trip — where you went and what made it memorable.")
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
            editedText = narrative
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
