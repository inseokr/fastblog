//
//  BlogSettingsSheet.swift
//  Capper
//

import SwiftUI

/// Shown from the blog page (RecapBlogPageView). Change title, cover, and manage photos.
struct BlogSettingsSheet: View {
    @Binding var draft: RecapBlogDetail
    var blogKey: Int?
    var onSave: () -> Void
    var onEditMode: (() -> Void)? = nil
    var onDelete: () -> Void
    var onRemoveFromCloud: (() -> Void)? = nil
    /// Called after the user restores a removed place so the parent can persist the draft.
    var onRestore: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showTitleChange = false
    @State private var showCoverChange = false
    @State private var coverPhotoIdentifierBeforeEdit: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var showRemoveFromCloudConfirmation = false
    @State private var showRestorePlaces = false

    private var hasCloudPhotos: Bool {
        draft.days.flatMap(\.placeStops).flatMap(\.photos).contains { $0.cloudURL != nil }
    }

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
                        coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
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

                if hasCloudPhotos {
                    Section {
                        if onEditMode != nil {
                            Button {
                                onEditMode?()
                                dismiss()
                            } label: {
                                Label("Edit Mode", systemImage: "pencil")
                            }
                        }
                        if !draft.removedPlaceStops.isEmpty {
                            Button {
                                showRestorePlaces = true
                            } label: {
                                Label("Restore Places (\(draft.removedPlaceStops.count))", systemImage: "arrow.uturn.backward.circle")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            showRemoveFromCloudConfirmation = true
                        } label: {
                            Label("Remove from Cloud", systemImage: "icloud.slash")
                        }
                    } footer: {
                        Text("This will remove uploaded photos from the cloud. Your local blog and photos are not affected.")
                    }
                }

                // Delete Blog — pinned to bottom
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Blog", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Blog Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                    }
                }
            }
            .sheet(isPresented: $showTitleChange) {
                BlogTitleChangeSheet(title: $draft.title, blogKey: blogKey) {
                    showTitleChange = false
                }
            }
            .sheet(isPresented: $showCoverChange, onDismiss: {
                if let key = blogKey,
                   let newId = draft.selectedCoverPhotoIdentifier,
                   newId != coverPhotoIdentifierBeforeEdit {
                    Task { try? await APIManager.shared.uploadAndUpdateCoverPhoto(blogKey: key, assetIdentifier: newId) }
                }
                coverPhotoIdentifierBeforeEdit = nil
            }) {
                BlogCoverPhotoPickerView(
                    photos: draft.days.flatMap(\.placeStops).flatMap(\.photos).filter(\.isIncluded),
                    selectedIdentifier: $draft.selectedCoverPhotoIdentifier
                ) {
                    showCoverChange = false
                }
            }
            .alert("Delete Blog?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this blog? It will be removed from your profile, but the trip will be available in Trips to customize again.")
            }
            .alert("Remove from Cloud?", isPresented: $showRemoveFromCloudConfirmation) {
                Button("Yes", role: .destructive) {
                    // Clear cloud URLs from the draft in-place
                    for dayIdx in draft.days.indices {
                        for stopIdx in draft.days[dayIdx].placeStops.indices {
                            for photoIdx in draft.days[dayIdx].placeStops[stopIdx].photos.indices {
                                draft.days[dayIdx].placeStops[stopIdx].photos[photoIdx].cloudURL = nil
                            }
                        }
                    }
                    print("Removed cloud URLs from draft for blogKey \(blogKey ?? -1)")
                    onRemoveFromCloud?()
                    onSave()
                    dismiss()
                }
                Button("No", role: .cancel) {}
            } message: {
                Text("Are you sure you want to remove this blog from the cloud?")
            }
            .sheet(isPresented: $showRestorePlaces) {
                RemovedPlacesSheet(draft: $draft) {
                    onRestore?()
                    onSave()
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Single-purpose sheet to edit the blog title.
struct BlogTitleChangeSheet: View {
    @Binding var title: String
    var blogKey: Int? = nil
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var tempTitle = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Blog title", text: $tempTitle)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding()
                    .focused($isFocused)
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
                    Button("Done") {
                        title = tempTitle
                        if let key = blogKey {
                            let newTitle = tempTitle
                            Task { try? await APIManager.shared.updateBlogTitle(blogKey: key, title: newTitle) }
                        }
                        onDone()
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempTitle = title
                isFocused = true
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
