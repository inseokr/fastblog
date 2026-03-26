//
//  StoryWritingStyleSheet.swift
//  fastblog
//
//  Lets the user define a personal writing style prompt that guides the AI
//  when enhancing their travel stories. Stored globally in AppStorage.
//

import SwiftUI

/// The AppStorage key and default value for the user's writing style prompt.
enum StoryWritingStyle {
    static let storageKey = "bloggo.storyWritingStyle"
    static let defaultPrompt = "Write like I'm sharing memories with close friends and family — casual, warm, honest, and short."
}

/// Sheet for editing the personal AI writing style prompt.
struct StoryWritingStyleSheet: View {
    @AppStorage(StoryWritingStyle.storageKey) private var writingStyle: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    /// Local working copy — only committed to AppStorage when user taps Done.
    @State private var tempStyle: String = ""

    private var hasUnsavedChanges: Bool {
        tempStyle != writingStyle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    descriptionCard
                    editorCard
                    if !isFocused {
                        defaultCard
                    }
                }
                .padding(20)
                // Tap anywhere outside the TextEditor to dismiss keyboard
                .contentShape(Rectangle())
                .onTapGesture { isFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Writing Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { tempStyle = writingStyle }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sections

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your Style, Your Voice", systemImage: "wand.and.stars")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("When you tap the magic wand, the AI uses this style to complete and enrich your stories. It overrides all other instructions — your style comes first.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Prompt")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ZStack(alignment: .topLeading) {
                // Placeholder when empty
                if tempStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(StoryWritingStyle.defaultPrompt)
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $tempStyle)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
            .onTapGesture { isFocused = true }

            if !tempStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(role: .destructive) {
                    tempStyle = ""
                    isFocused = false
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var defaultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Example prompts")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(examplePrompts, id: \.self) { example in
                Button {
                    tempStyle = example
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        Text(example)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if hasUnsavedChanges {
                Button("Cancel") {
                    tempStyle = writingStyle   // discard changes
                    isFocused = false
                    dismiss()
                }
            } else {
                Button {
                    isFocused = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                writingStyle = tempStyle       // commit changes
                isFocused = false
                dismiss()
            }
            .fontWeight(hasUnsavedChanges ? .semibold : .regular)
        }
    }

    // MARK: - Examples

    private let examplePrompts: [String] = [
        "Write like I'm sharing memories with close friends and family — casual, warm, honest, and short.",
        "Keep it poetic and vivid — paint the atmosphere in a few words, like a travel journal entry.",
        "Write like a funny story I'd tell at dinner — light, relatable, with a hint of humor.",
        "Simple and heartfelt. No fancy words, just honest feelings about the moment.",
    ]
}
