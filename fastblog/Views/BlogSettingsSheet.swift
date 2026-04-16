//
//  BlogSettingsSheet.swift
//  Capper
//

import SwiftUI

// MARK: - Blog Font Helper
extension Font {
    /// Returns the blog font for the given user-selected style and size.
    /// - "Default"     → SF Pro (clean system font)
    /// - "Serif"       → Georgia (warm editorial — original blog look)
    /// - "Mono"        → SF Mono (code / typewriter feel)
    /// - "Rounded"     → SF Pro Rounded (soft, friendly)
    /// - "Baskerville" → Baskerville (classical literary serif)
    /// - "Avenir"      → Avenir Next (elegant geometric sans)
    /// - "Bodoni"      → Bodoni 72 (high-contrast luxury serif)
    /// - "Futura"      → Futura (geometric modernist sans)
    /// - "Optima"      → Optima (flared humanist sans)
    /// - "Typewriter"  → American Typewriter (nostalgic serif typewriter)
    static func blog(_ style: String, size: CGFloat, bold: Bool = false) -> Font {
        switch style {
        case "Serif":
            return .custom(bold ? "Georgia-Bold" : "Georgia", size: size)
        case "Mono":
            return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
        case "Rounded":
            return .system(size: size, weight: bold ? .bold : .regular, design: .rounded)
        case "Baskerville":
            return .custom(bold ? "Baskerville-Bold" : "Baskerville", size: size)
        case "Avenir":
            return .custom(bold ? "AvenirNext-Bold" : "AvenirNext-Regular", size: size)
        case "Bodoni":
            return .custom(bold ? "BodoniSvtyTwoITCTT-Bold" : "BodoniSvtyTwoITCTT-Book", size: size)
        case "Futura":
            return .custom(bold ? "Futura-Bold" : "Futura-Medium", size: size)
        case "Optima":
            return .custom(bold ? "Optima-Bold" : "Optima-Regular", size: size)
        case "Typewriter":
            return .custom(bold ? "AmericanTypewriter-Bold" : "AmericanTypewriter", size: size)
        default: // "Default"
            return .system(size: size, weight: bold ? .bold : .regular)
        }
    }
}

/// Shown from the blog page (RecapBlogPageView). Change title, cover, and manage photos.
struct BlogSettingsSheet: View {
    @Binding var draft: RecapBlogDetail
    @Binding var selectedDayIndex: Int
    var blogKey: Int?
    var onSave: () -> Void
    var onEditMode: (() -> Void)? = nil
    var onAddNewMoments: (() -> Void)? = nil
    var onRescanAllMoments: (() -> Void)? = nil
    var onDelete: () -> Void
    var onRemoveLocalOnly: (() -> Void)? = nil
    var onRemoveFromCloud: (() -> Void)? = nil
    /// Called after the user restores a removed place so the parent can persist the draft.
    var onRestore: (() -> Void)? = nil
    /// When true, shows “Share trip nearby” for saved blogs (inline overlay; uses ``TripNearbyShareSessionController`` from the environment).
    var canShareNearby: Bool = false
    /// Parent shows full-screen upload UI when `true`, hides when `false` (cover photo cloud sync).
    var onCoverCloudUploadStateChanged: ((Bool) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nearbyShare: TripNearbyShareSessionController
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @AppStorage(StoryWritingStyle.storageKey) private var writingStyle: String = ""
    @AppStorage(StoryWritingStyle.presetStorageKey) private var writingStylePresetId: String = ""
    @AppStorage(WeatherTemperatureUnit.storageKey) private var weatherTemperatureUnitRaw: String = WeatherTemperatureUnit.fahrenheit.rawValue
    @AppStorage("selectedBlogFont") private var selectedBlogFont: String = "Serif"

    @State private var showTitleChange = false
    @State private var showCoverChange = false
    @State private var coverPhotoIdentifierBeforeEdit: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var showRemoveFromCloudConfirmation = false
    @State private var showRestorePlaces = false
    @State private var showCustomDeletePopup = false
    @State private var showWritingStyle = false
    @State private var showCarouselStudio = false
    @State private var showNearbyShareHost = false
    @State private var showNearbyShareUnavailableAlert = false
    @State private var isExportingBackup = false
    @State private var backupExportProgress: Double = 0
    @State private var backupShareURL: URL?
    @State private var showBackupShareSheet = false
    @State private var backupExportErrorMessage: String?
    @State private var showBackupExportError = false

    private var hasCloudPhotos: Bool {
        draft.hasCloudPhotos
    }

    /// List row / backup uses the same blog as `draft.id` in the visible recents list.
    private var backupListRecap: CreatedRecapBlog? {
        createdRecapStore.visibleRecents.first { $0.sourceTripId == draft.id }
    }

    /// Export uses persisted data only; requires an explicit editor Save (`hasCommittedRecapSave`).
    private var canExportSavedBackup: Bool {
        guard let r = backupListRecap, r.hasCommittedRecapSave,
              let detail = createdRecapStore.getBlogDetail(blogId: draft.id),
              !detail.days.isEmpty else { return false }
        return true
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    settingsList
                    deleteButton
                }
                .navigationTitle("Blog Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationToolbar }
                .sheet(isPresented: $showTitleChange) { titleChangeSheet }
                .sheet(isPresented: $showCoverChange, onDismiss: handleCoverPickerDismiss) { coverPhotoPicker }
                .sheet(isPresented: $showRestorePlaces) { restorePlacesSheet }
                .sheet(isPresented: $showWritingStyle) { StoryWritingStyleSheet() }
                .sheet(isPresented: $showCarouselStudio) { CarouselStudioSheet(blog: draft) }
                .alert("Delete Blog?", isPresented: $showDeleteConfirmation) { deleteAlertButtons } message: { deleteAlertMessage }
                .overlay { customDeletePopup }
                .alert("Remove from Cloud?", isPresented: $showRemoveFromCloudConfirmation) { removeCloudAlertButtons } message: { removeCloudAlertMessage }
                .preferredColorScheme(.dark)
            }

            if isExportingBackup {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .zIndex(15)
                VStack(spacing: 16) {
                    Text("Exporting backup…")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ProgressView(value: backupExportProgress, total: 1)
                        .tint(.white)
                        .frame(maxWidth: 220)
                    Text("\(Int((backupExportProgress * 100).rounded(.down)))%")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 16))
                .zIndex(16)
            }

            if showNearbyShareHost {
                TripNearbyShareHostBlogSettingsOverlay(recap: draft, controller: nearbyShare) {
                    showNearbyShareHost = false
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showNearbyShareHost)
        .animation(.easeInOut(duration: 0.2), value: isExportingBackup)
        .alert("Can’t share this trip", isPresented: $showNearbyShareUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nearby sharing needs at least one included photo that is still on this device (or saved in Bloggo). Photos that exist only in the cloud aren’t sent peer-to-peer.")
        }
        .sheet(isPresented: $showBackupShareSheet, onDismiss: {
            if let u = backupShareURL {
                try? FileManager.default.removeItem(at: u)
                backupShareURL = nil
            }
        }) {
            if let u = backupShareURL {
                ShareSheet(items: [u])
            }
        }
        .alert("Couldn’t export backup", isPresented: $showBackupExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupExportErrorMessage ?? "")
        }
    }

    private var settingsList: some View {
        List {
            editAndRestoreSection
            titleAndCoverSection
            unusedPhotosSection
            fontStyleAndWeatherSection
            backupSection
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
            if onRescanAllMoments != nil {
                Button {
                    onRescanAllMoments?()
                    dismiss()
                } label: {
                    Label("Rescan All Moments", systemImage: "arrow.clockwise.circle")
                }
            }
            Button {
                showCarouselStudio = true
            } label: {
                Label("Carousel Studio", systemImage: "rectangle.stack")
            }
        }
    }

    private var unusedPhotosSection: some View {
        Section {
            NavigationLink {
                StorageManagementView(draft: $draft, onSave: onSave)
            } label: {
                Label {
                    Text("Unused Photos")
                } icon: {
                    Image(systemName: "photo.stack")
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var titleAndCoverSection: some View {
        Section {
            Button {
                AppAnalytics.trackEvent(name: "Blog-Change-BlogTitle")
                showTitleChange = true
            } label: {
                Label("Change Blog Title", systemImage: "textformat")
            }
            Button {
                AppAnalytics.trackEvent(name: "Blog-Pick-CoverPhoto")
                coverPhotoIdentifierBeforeEdit = draft.selectedCoverPhotoIdentifier
                showCoverChange = true
            } label: {
                Label("Change Cover Photo", systemImage: "photo")
            }
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                Task { await exportBlogBackupTapped() }
            } label: {
                Label("Export Backup (ZIP)", systemImage: "arrow.up.doc")
            }
            .disabled(isExportingBackup || !canExportSavedBackup)
        } footer: {
            if canExportSavedBackup {
                Text("Creates a backup file of this blog so you can import it to another device using Bloggo. Import can be found in the App Settings page.")
            } else {
                Text("Save this blog from the editor first (toolbar Save). Export only includes saved blogs, not draft-only recaps.")
            }
        }
    }

    @MainActor
    private func exportBlogBackupTapped() async {
        isExportingBackup = true
        backupExportProgress = 0
        defer {
            isExportingBackup = false
            backupExportProgress = 0
        }
        do {
            guard let persistedDetail = createdRecapStore.getBlogDetail(blogId: draft.id),
                  let recap = backupListRecap, recap.hasCommittedRecapSave else {
                backupExportErrorMessage = "Save this blog from the editor before exporting a backup."
                showBackupExportError = true
                return
            }
            let url = try await BlogBackupService.exportZip(
                detail: persistedDetail,
                createdRecapSnapshot: recap,
                progress: { frac in
                    Task { @MainActor in
                        backupExportProgress = frac
                    }
                }
            )
            // Let any pending MainActor progress updates apply before presenting share.
            await Task.yield()
            backupExportProgress = 1
            backupShareURL = url
            showBackupShareSheet = true
        } catch {
            backupExportErrorMessage = error.localizedDescription
            showBackupExportError = true
        }
    }

    private var fontStyleAndWeatherSection: some View {
        Section {
            Picker(selection: $selectedBlogFont) {
                Text("Default")
                    .font(.system(size: 16))
                    .tag("Default")
                Text("Serif")
                    .font(.custom("Georgia", size: 16))
                    .tag("Serif")
                Text("Mono")
                    .font(.system(size: 16, design: .monospaced))
                    .tag("Mono")
                Text("Rounded")
                    .font(.system(size: 16, design: .rounded))
                    .tag("Rounded")
                Text("Baskerville")
                    .font(.custom("Baskerville", size: 16))
                    .tag("Baskerville")
                Text("Avenir")
                    .font(.custom("AvenirNext-Regular", size: 16))
                    .tag("Avenir")
                Text("Bodoni")
                    .font(.custom("BodoniSvtyTwoITCTT-Book", size: 16))
                    .tag("Bodoni")
                Text("Futura")
                    .font(.custom("Futura-Medium", size: 16))
                    .tag("Futura")
                Text("Optima")
                    .font(.custom("Optima-Regular", size: 16))
                    .tag("Optima")
                Text("Typewriter")
                    .font(.custom("AmericanTypewriter", size: 16))
                    .tag("Typewriter")
            } label: {
                Label {
                    Text("Font Style")
                } icon: {
                    Image(systemName: "textformat.alt")
                        .foregroundStyle(.white)
                }
            }
            Picker(selection: $weatherTemperatureUnitRaw) {
                ForEach(WeatherTemperatureUnit.allCases, id: \.rawValue) { unit in
                    Text(unit.displayName).tag(unit.rawValue)
                }
            } label: {
                Label {
                    Text("Day weather")
                } icon: {
                    Image(systemName: "sun.max")
                        .foregroundStyle(.white)
                }
            }
        } footer: {
            Text("High and low temperatures shown on each day in the blog use this unit.")
        }
    }

    private var writingStyleSection: some View {
        let activeStyle = writingStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = StoryWritingStyle.resolvedPrompt(storedPrompt: activeStyle)
        let styleName = StoryWritingStyle.preset(for: writingStylePresetId)?.title
            ?? StoryWritingStyle.preset(matching: activeStyle)?.title
            ?? "Custom"
        return Section {
            Button {
                showWritingStyle = true
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Writing Style")
                    }
                    Spacer()
                    Text(styleName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            Text(displayPrompt)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        if blogKey != nil && hasCloudPhotos {
            Section {
                Button(role: .destructive) {
                    showRemoveFromCloudConfirmation = true
                } label: {
                    Text("Remove from Cloud")
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
                .appChromeCornerRadius(12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                onSave()
                dismiss()
            }
            .fontWeight(.semibold)
            .foregroundColor(.white)
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
            Task { @MainActor in
                onCoverCloudUploadStateChanged?(true)
                defer { onCoverCloudUploadStateChanged?(false) }
                do {
                    let url = try await APIManager.shared.uploadAndUpdateCoverPhoto(blogKey: key, assetIdentifier: newId)
                    var d = draft
                    d.setCloudURL(url, forLocalAssetIdentifier: newId)
                    draft = d
                    onSave()
                } catch {
                    print("🚨 Cover photo cloud update failed: \(error)")
                }
            }
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
        Text("This blog will be removed from your device. You can recreate it later.")
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
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
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

                        Text("This blog will be removed from your device. You can recreate it later.")
                            .font(.subheadline)
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
                                .appChromeCornerRadius(12)
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
                                .appChromeCornerRadius(12)
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
                .appChromeCornerRadius(24)
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
                    .appChromeCornerRadius(16)
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
                    Button {
                        title = tempTitle
                        if let key = blogKey {
                            let newTitle = tempTitle
                            Task { try? await APIManager.shared.updateBlogTitle(blogKey: key, title: newTitle) }
                        }
                        onDone()
                        dismiss()
                    } label: {
                        RecapEditorToolbarSaveLabel()
                    }
                    .buttonStyle(.plain)
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
                                    .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
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
                            .appChromeCornerRadius(12)
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
