//
//  StoryWritingStyleSheet.swift
//  fastblog
//
//  Lets the user define a personal writing style prompt that guides the AI
//  when enhancing their travel stories. Stored globally in AppStorage.
//

import SwiftUI

/// Sheet for editing the personal AI writing style prompt.
struct StoryWritingStyleSheet: View {
    @AppStorage(StoryWritingStyle.storageKey) private var writingStyle: String = ""
    @AppStorage(StoryWritingStyle.presetStorageKey) private var presetId: String = StoryWritingStyle.presets.first?.id ?? ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    /// Local working copy - only committed to AppStorage when user taps Done.
    @State private var tempStyle: String = ""
    @State private var selectedPresetId: String = StoryWritingStyle.presets.first?.id ?? ""
    @State private var useCustomPrompt = false

    private var hasUnsavedChanges: Bool {
        tempStyle != writingStyle || selectedPresetId != normalizedStoredPresetId
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    descriptionCard
                    presetCard
                    editorCard
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
            .onAppear(perform: hydrateDraft)
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

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Popular styles")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(StoryWritingStyle.presets) { preset in
                Button {
                    selectedPresetId = preset.id
                    tempStyle = preset.prompt
                    useCustomPrompt = false
                    isFocused = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(preset.prompt)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: selectedPresetId == preset.id && !useCustomPrompt ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedPresetId == preset.id && !useCustomPrompt ? .blue : .secondary)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Custom guideline")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(useCustomPrompt ? "Using Custom" : "Use Custom") {
                    useCustomPrompt = true
                    if !StoryWritingStyle.presets.contains(where: { $0.prompt == tempStyle }) {
                        selectedPresetId = StoryWritingStyle.customPresetId
                    }
                }
                .font(.caption)
            }

            ZStack(alignment: .topLeading) {
                // Placeholder when empty
                if useCustomPrompt && tempStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(StoryWritingStyle.defaultPrompt)
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $tempStyle)
                    .disabled(!useCustomPrompt)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundColor(useCustomPrompt ? .white : .secondary)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
            .onTapGesture {
                guard useCustomPrompt else { return }
                isFocused = true
            }

            if useCustomPrompt && !tempStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if hasUnsavedChanges {
                Button("Cancel") {
                    hydrateDraft()
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
                commitSelection()
                isFocused = false
                dismiss()
            }
            .fontWeight(hasUnsavedChanges ? .semibold : .regular)
        }
    }

    private var normalizedStoredPresetId: String {
        if !presetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetId
        }
        if let matched = StoryWritingStyle.preset(matching: writingStyle) {
            return matched.id
        }
        return StoryWritingStyle.customPresetId
    }

    private func hydrateDraft() {
        if let preset = StoryWritingStyle.preset(for: normalizedStoredPresetId), normalizedStoredPresetId != StoryWritingStyle.customPresetId {
            selectedPresetId = preset.id
            tempStyle = preset.prompt
            useCustomPrompt = false
            return
        }

        if let matched = StoryWritingStyle.preset(matching: writingStyle) {
            selectedPresetId = matched.id
            tempStyle = matched.prompt
            useCustomPrompt = false
        } else {
            selectedPresetId = StoryWritingStyle.customPresetId
            tempStyle = writingStyle
            useCustomPrompt = true
        }
    }

    private func commitSelection() {
        if useCustomPrompt {
            let trimmed = tempStyle.trimmingCharacters(in: .whitespacesAndNewlines)
            writingStyle = trimmed
            presetId = StoryWritingStyle.customPresetId
            return
        }
        let resolved = StoryWritingStyle.preset(for: selectedPresetId) ?? StoryWritingStyle.presets[0]
        writingStyle = resolved.prompt
        presetId = resolved.id
    }
}
