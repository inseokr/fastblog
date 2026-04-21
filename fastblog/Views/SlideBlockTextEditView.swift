// SlideBlockTextEditView.swift
// fastblog
//
// Separate full-screen text editor for Carousel Studio slide blocks.
// Presented via fullScreenCover so the keyboard inside this view cannot
// propagate safe-area insets back to the slide editor.

import SwiftUI

struct SlideBlockTextEditView: View {
    let primarySectionTitle: String
    let primarySectionSubtitle: String
    let secondarySectionTitle: String?
    let secondarySectionSubtitle: String?
    @Binding var textDraft: String
    @Binding var captionDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private enum Field: Hashable { case primary, secondary }
    @FocusState private var focusField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("", text: $textDraft, axis: .vertical)
                        .focused($focusField, equals: .primary)
                        .lineLimit(1...6)
                } header: {
                    fieldChrome(title: primarySectionTitle, subtitle: primarySectionSubtitle)
                }

                if let t2 = secondarySectionTitle, let s2 = secondarySectionSubtitle {
                    Section {
                        TextField("", text: $captionDraft, axis: .vertical)
                            .focused($focusField, equals: .secondary)
                            .lineLimit(1...8)
                    } header: {
                        fieldChrome(title: t2, subtitle: s2)
                    }
                }
            }
            .navigationTitle("Edit text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
            .onAppear {
                focusField = .primary
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func fieldChrome(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}
