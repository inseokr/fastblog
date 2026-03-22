//
//  BlogSettingsSheet.swift
//  Capper
//

import SwiftUI

/// Shown from the blog page (RecapBlogPageView). Change title, cover, and manage photos.
struct BlogSettingsSheet: View {
    @Binding var draft: RecapBlogDetail
    @Binding var selectedDayIndex: Int
    var blogKey: Int?
    var onSave: () -> Void
    var onEditMode: (() -> Void)? = nil
    var onAddNewMoments: (() -> Void)? = nil
    var onDelete: () -> Void
    var onRemoveLocalOnly: (() -> Void)? = nil
    var onRemoveFromCloud: (() -> Void)? = nil
    /// Called after the user restores a removed place so the parent can persist the draft.
    var onRestore: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StoryWritingStyle.storageKey) private var writingStyle: String = ""
    @AppStorage(WeatherTemperatureUnit.storageKey) private var weatherTemperatureUnitRaw: String = WeatherTemperatureUnit.fahrenheit.rawValue

    @State private var showTitleChange = false
    @State private var showCoverChange = false
    @State private var coverPhotoIdentifierBeforeEdit: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var showRemoveFromCloudConfirmation = false
    @State private var showRestorePlaces = false
    @State private var showCustomDeletePopup = false
    @State private var showWritingStyle = false

    private var hasCloudPhotos: Bool {
        draft.hasCloudPhotos
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    settingsList
                    deleteButton
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationToolbar }
                .sheet(isPresented: $showTitleChange) { titleChangeSheet }
                .sheet(isPresented: $showCoverChange, onDismiss: handleCoverPickerDismiss) { coverPhotoPicker }
                .sheet(isPresented: $showRestorePlaces) { restorePlacesSheet }
                .sheet(isPresented: $showWritingStyle) { StoryWritingStyleSheet() }
                .alert("Delete Blog?", isPresented: $showDeleteConfirmation) { deleteAlertButtons } message: { deleteAlertMessage }
                .overlay { customDeletePopup }
                .alert("Remove from Cloud?", isPresented: $showRemoveFromCloudConfirmation) { removeCloudAlertButtons } message: { removeCloudAlertMessage }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var settingsList: some View {
        List {
            editAndRestoreSection
            titleAndCoverSection
            writingStyleSection
            weatherSection
            cloudSection
        }
    }

    private var editAndRestoreSection: some View {
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
            if onAddNewMoments != nil {
                Button {
                    onAddNewMoments?()
                    dismiss()
                } label: {
                    Label("Add New Moments", systemImage: "plus.circle")
                }
            }
        }
    }

    private var titleAndCoverSection: some View {
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
        }
    }

    private var writingStyleSection: some View {
        let activeStyle = writingStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = activeStyle.isEmpty ? StoryWritingStyle.defaultPrompt : activeStyle
        return Section {
            Button {
                showWritingStyle = true
            } label: {
                Label("Writing Style", systemImage: "wand.and.stars")
            }
        } footer: {
            Text(displayPrompt)
                .lineLimit(3)
        }
    }

    private var weatherSection: some View {
        Section {
            Picker("Day weather", selection: $weatherTemperatureUnitRaw) {
                ForEach(WeatherTemperatureUnit.allCases, id: \.rawValue) { unit in
                    Text(unit.displayName).tag(unit.rawValue)
                }
            }
        } footer: {
            Text("High and low temperatures shown on each day in the blog use this unit.")
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        if hasCloudPhotos {
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
    }

    private var deleteButton: some View {
        Button {
            if blogKey != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCustomDeletePopup = true
                }
            } else {
                showDeleteConfirmation = true
            }
        } label: {
            Text("Delete Blog")
                .font(.headline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
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

    private var titleChangeSheet: some View {
        BlogTitleChangeSheet(title: $draft.title, blogKey: blogKey) {
            showTitleChange = false
        }
    }

    private var coverPhotoPicker: some View {
        BlogCoverPhotoPickerView(
            photos: draft.allIncludedPhotos,
            selectedIdentifier: $draft.selectedCoverPhotoIdentifier
        ) {
            showCoverChange = false
        }
    }

    private func handleCoverPickerDismiss() {
        if let key = blogKey,
           let newId = draft.selectedCoverPhotoIdentifier,
           newId != coverPhotoIdentifierBeforeEdit {
            Task { try? await APIManager.shared.uploadAndUpdateCoverPhoto(blogKey: key, assetIdentifier: newId) }
        }
        coverPhotoIdentifierBeforeEdit = nil
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Delete", role: .destructive) {
            onDelete()
            dismiss()
        }
        Button("Cancel", role: .cancel) {}
    }

    private var deleteAlertMessage: some View {
        Text("Are you sure you want to delete this blog? It will be removed from your profile, but the trip will be available in Trips to customize again.")
    }

    @ViewBuilder
    private var customDeletePopup: some View {
        if showCustomDeletePopup {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showCustomDeletePopup = false
                        }
                    }
                
                VStack(spacing: 24) {
                    Image("Blogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                    
                    VStack(spacing: 8) {
                        Text("Delete This Blog?")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("\"\(draft.title)\"")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 12) {
                        Button {
                            withAnimation { showCustomDeletePopup = false }
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Everywhere")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            withAnimation { showCustomDeletePopup = false }
                            onRemoveLocalOnly?()
                            dismiss()
                        } label: {
                            Text("Remove from This Device")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(white: 0.2))
                                .cornerRadius(12)
                        }
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCustomDeletePopup = false
                            }
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .padding(24)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var removeCloudAlertButtons: some View {
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
    }

    private var removeCloudAlertMessage: some View {
        Text("Are you sure you want to remove this blog from the cloud?")
    }

    private var restorePlacesSheet: some View {
        RemovedPlacesSheet(draft: $draft, selectedDayIndex: $selectedDayIndex) {
            onRestore?()
            onSave()
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
