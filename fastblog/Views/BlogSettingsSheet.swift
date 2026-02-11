//
//  BlogSettingsSheet.swift
//  Capper
//

import SwiftUI

/// Shown from the blog page (RecapBlogPageView). Change title, cover, and manage photos.
struct BlogSettingsSheet: View {
    @Binding var draft: RecapBlogDetail
    var onSave: () -> Void
    var onEditMode: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showTitleChange = false
    @State private var showCoverChange = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showTitleChange = true
                    } label: {
                        Label("Change Blog Title", systemImage: "textformat")
                    }
                    Button {
                        showCoverChange = true
                    } label: {
                        Label("Change Cover Photo", systemImage: "photo")
                    }
                    if onEditMode != nil {
                        Button {
                            onEditMode?()
                            dismiss()
                        } label: {
                            Label("Edit Mode", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("Blog Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTitleChange) {
                BlogTitleChangeSheet(title: $draft.title) {
                    showTitleChange = false
                }
            }
            .sheet(isPresented: $showCoverChange) {
                BlogCoverChangeSheet(coverTheme: $draft.coverTheme) {
                    showCoverChange = false
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Single-purpose sheet to edit the blog title.
struct BlogTitleChangeSheet: View {
    @Binding var title: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Blog title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Blog Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onDone()
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Single-purpose sheet to pick a cover theme (fallback when no photo library cover).
struct BlogCoverChangeSheet: View {
    @Binding var coverTheme: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let themes: [(id: String, label: String)] = [
        ("iceland", "Iceland"),
        ("morocco", "Morocco"),
        ("tokyo", "Tokyo"),
        ("paris", "Paris"),
        ("california", "California"),
        ("alps", "Alps"),
        ("barcelona", "Barcelona"),
        ("london", "London"),
        ("default", "Default")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(themes, id: \.id) { theme in
                        Button {
                            coverTheme = theme.id
                        } label: {
                            HStack {
                                TripCoverImage(theme: theme.id)
                                    .frame(width: 80, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(theme.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                if coverTheme == theme.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Cover Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
