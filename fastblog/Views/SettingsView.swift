//
//  SettingsView.swift
//  Capper
//

import SwiftUI
import UIKit

// MARK: - Settings help (Blog backup / My home)

private enum SettingsHelpTopic: String, Identifiable {
    case blogBackup
    case myHome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blogBackup: return "Blog backup"
        case .myHome: return "My home"
        }
    }

    var subtitle: String {
        switch self {
        case .blogBackup: return "Export, back up, and import your saved blogs on a new device."
        case .myHome: return "How distance from home works for trip scanning."
        }
    }
}

private struct SettingsHelpTopicCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct SettingsBlogBackupHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHelpTopicCard(
                icon: "doc.zipper",
                tint: Color(red: 0.35, green: 0.65, blue: 1.0),
                title: "1. Export your blogs as a ZIP",
                detail: "Tap Export all saved blogs. Bloggo packs your stories and JPEG photos into one file. Only blogs you have saved from the editor are included."
            )
            SettingsHelpTopicCard(
                icon: "icloud.fill",
                tint: Color(red: 0.25, green: 0.55, blue: 0.95),
                title: "2. Back it up to iCloud",
                detail: "Use Save to Files and put the ZIP in iCloud Drive, or send it to another cloud or computer. That way you can grab it again if this phone is lost or replaced."
            )
            SettingsHelpTopicCard(
                icon: "arrow.down.doc",
                tint: Color(red: 0.45, green: 0.85, blue: 0.55),
                title: "3. Import on another device",
                detail: "Whenever you are ready, open Bloggo on another phone or tablet, tap Import blog backup, and choose your ZIP. Turn on Add photos already on this device in Settings → Blog backup to link to matching library photos when possible (for example from iCloud Photos); turn it off to use only the JPEGs stored in the backup."
            )
        }
        .padding(.horizontal, 20)
    }
}

private struct SettingsMyHomeHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHelpTopicCard(
                icon: "house.fill",
                tint: Color(red: 0.35, green: 0.65, blue: 1.0),
                title: "What “My home” is",
                detail: "This is the spot Bloggo measures from. It helps tell everyday photos near you apart from trip photos that feel farther away."
            )
            SettingsHelpTopicCard(
                icon: "slider.horizontal.3",
                tint: Color(red: 0.45, green: 0.85, blue: 0.55),
                title: "The distance slider",
                detail: "This sets how far from home a photo can be before it appears in trip lists. Slide it higher to hide more neighborhood photos."
            )
            SettingsHelpTopicCard(
                icon: "arrow.triangle.2.circlepath",
                tint: Color(red: 1.0, green: 0.75, blue: 0.35),
                title: "After you change it",
                detail: "Release the slider and Bloggo will rescan when it can. If trips still look wrong, close Bloggo fully, reopen, then open Trips."
            )
            SettingsHelpTopicCard(
                icon: "photo.badge.plus",
                tint: Color(red: 0.75, green: 0.65, blue: 1.0),
                title: "Limited Photos access",
                detail: "If iOS only shows part of your library, home distance still applies, but scans use a default distance until you allow access to more photos."
            )
        }
        .padding(.horizontal, 20)
    }
}

private struct SettingsHelpSheet: View {
    let topic: SettingsHelpTopic
    @Environment(\.dismiss) private var dismiss

    private let scrollBottomInset: CGFloat = 132

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop,
                    OnboardingConstants.Colors.backgroundGradientBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(height: 28)

                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(appChromeBaseRadius: 16))
                        .padding(.bottom, 10)

                    VStack(spacing: 10) {
                        Text(topic.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(topic.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                    switch topic {
                    case .blogBackup:
                        SettingsBlogBackupHelpContent()
                    case .myHome:
                        SettingsMyHomeHelpContent()
                    }
                }
                .padding(.bottom, scrollBottomInset)
            }
            .scrollIndicators(.visible)

            settingsHelpBottomCTA
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var settingsHelpBottomCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop.opacity(0),
                    OnboardingConstants.Colors.backgroundGradientBottom.opacity(0.55),
                    OnboardingConstants.Colors.backgroundGradientBottom.opacity(0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 52)
            .allowsHitTesting(false)

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(OnboardingConstants.Colors.doneButtonBlue)
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.32), radius: 10, y: 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .background(
                OnboardingConstants.Colors.backgroundGradientBottom
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showNeighborhoodFlow = false
    @State private var showAuth = false
    @State private var showDeleteAccountAlert = false
    #if DEBUG
    @AppStorage("capper.tripClustering.debugLogging") private var tripClusteringDebug = false
    #endif

    @State private var customProfileImageData: Data?

    @State private var cloudStorageUsage: APIManager.CloudStorageUsageItem?
    @State private var cloudStorageLoading = false
    @State private var cloudStorageError: String?

    @State private var tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles

    @State private var showImportBackupPicker = false
    @State private var showReceiveBlogDrop = false
    @State private var isExportingAllBackups = false
    @State private var isImportingBackup = false
    @State private var backupFlowProgress: Double = 0
    @State private var backupAllShareURL: URL?
    @State private var showBackupAllShareSheet = false
    @State private var backupFlowAlertTitle = ""
    @State private var backupFlowAlertMessage = ""
    @State private var showBackupFlowAlert = false
    @AppStorage("bloggo.backupImport.preferPhotoLibrary") private var preferPhotoLibraryWhenImportingBackup = true
    @State private var settingsHelpTopic: SettingsHelpTopic?

    private var travelStats: (countries: Int, cities: Int, places: Int) {
        let store = CreatedRecapBlogStore.shared
        let countries = store.countrySummaries.filter { $0.countryName != "Unknown" }.count
        let allPlaces = store.visitedPlaces
        let cities = Set(allPlaces.compactMap { place -> String? in
            let t = place.city.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t.lowercased()
        }).count
        let places = allPlaces.count
        return (countries, cities, places)
    }

    private var travelStatsRow: some View {
        HStack(spacing: 0) {
            StatColumn(value: travelStats.countries, label: "Countries")
            Divider().frame(height: 36)
            StatColumn(value: travelStats.cities, label: "Cities")
            Divider().frame(height: 36)
            StatColumn(value: travelStats.places, label: "Places")
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    private var hasAnyBackupableBlog: Bool {
        createdRecapStore.visibleRecents.contains { blog in
            blog.hasCommittedRecapSave && createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) != nil
        }
    }

    private struct StatColumn: View {
        let value: Int
        let label: String
        var body: some View {
            VStack(alignment: .center, spacing: 4) {
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    Section {
                        travelStatsRow
                    } header: {
                        Text("Travel Stats")
                    }

                    Section {
                        if let user = authService.currentUser {
                            HStack(spacing: 14) {
                                if let data = customProfileImageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [
                                                    Color(red: 0.2, green: 0.5, blue: 1),
                                                    Color(red: 0.1, green: 0.3, blue: 0.8)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 40, height: 40)
                                        Text(user.initials)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = user.displayName, !name.isEmpty {
                                        Text(name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    Text(user.email ?? user.provider.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)

                            if cloudStorageLoading {
                                HStack {
                                    ProgressView()
                                    Text("Loading…")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            } else if let error = cloudStorageError {
                                Text(error)
                                    .foregroundColor(.secondary)
                            } else if let usage = cloudStorageUsage {
                                LabeledContent("Storage used", value: String(format: "%.2f MB", usage.totalMB))
                                LabeledContent("Photos", value: "\(usage.photoCount)")
                                if let updated = usage.lastUpdated, !updated.isEmpty {
                                    LabeledContent("Last updated", value: formatCloudStorageDate(updated))
                                }
                            }

                            Button {
                                authService.signOut()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Button {
                                showAuth = true
                            } label: {
                                HStack {
                                    Label("Sign In / Create Account", systemImage: "person.badge.plus")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Account")
                    } footer: {
                        if authService.isSignedIn {
                            Text("You can save and export unlimited blogs.")
                        } else {
                            Text("Create an account to save and download unlimited blogs.")
                        }
                    }

                    Section {
                        PhotoAccessRow()
                        PushNotificationAccessRow()
                    } header: {
                        Text("Permissions")
                    } footer: {
                        Text("Notifications cover memory recalls, My Places digests, and capture reminders.")
                    }

                    Section {
                        Button {
                            showNeighborhoodFlow = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Neighborhood", systemImage: "mappin.circle.fill")
                                    if let name = NeighborhoodStore.getDisplayName() {
                                        Text(name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if photoAuth.status != .limited {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Exclude photos closer than")
                                    Spacer()
                                    Text("\(Int(tripExclusionRadius)) miles")
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { tripExclusionRadius },
                                        set: { newValue in
                                            tripExclusionRadius = newValue
                                            NeighborhoodStore.tripExclusionRadiusMiles = newValue
                                        }
                                    ),
                                    in: 5...200,
                                    step: 1,
                                    onEditingChanged: { isEditing in
                                        if !isEditing {
                                            NotificationCenter.default.post(
                                                name: .blogifyTripExclusionRadiusDidFinishAdjusting,
                                                object: nil
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    } header: {
                        HStack {
                            Text("My home")
                            Spacer(minLength: 8)
                            Button {
                                settingsHelpTopic = .myHome
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Learn more about My home")
                        }
                    }

                    Section {
                        Button {
                            showImportBackupPicker = true
                        } label: {
                            Label("Import blog backup", systemImage: "arrow.down.doc")
                        }
                        .disabled(isImportingBackup)

                        Button {
                            showReceiveBlogDrop = true
                        } label: {
                            Label("Receive Blog Drop", systemImage: "arrow.down.circle")
                        }

                        Toggle(isOn: $preferPhotoLibraryWhenImportingBackup) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add photos already on this device")
                                Text("Prefer library photos when they match; otherwise use the backup.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            Task { await exportAllBlogsBackupTapped() }
                        } label: {
                            Label("Export all saved blogs", systemImage: "square.and.arrow.up.on.square")
                                .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                        .opacity((isExportingAllBackups || !hasAnyBackupableBlog) ? 0.45 : 1.0)
                        .disabled(isExportingAllBackups || !hasAnyBackupableBlog)
                    } header: {
                        HStack {
                            Text("Blog backup")
                            Spacer(minLength: 8)
                            Button {
                                settingsHelpTopic = .blogBackup
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Learn more about blog backup")
                        }
                    }

                    Section {
                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            Label {
                                Text("Privacy Policy")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        NavigationLink {
                            TermsOfServiceView()
                        } label: {
                            Label {
                                Text("Terms of Service")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                    } header: {
                        Text("Legal")
                    }

                    if authService.isSignedIn {
                        Section {
                            Button {
                                showDeleteAccountAlert = true
                            } label: {
                                Label("Delete Account", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                                Button("Delete", role: .destructive) {
                                    Task { await authService.deleteAccount() }
                                    dismiss()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("Are you sure? This will permanently delete your account and all associated data from our servers. This action is immediate and cannot be undone.")
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showNeighborhoodFlow) {
                    NeighborhoodIntroView(onDismiss: {
                        showNeighborhoodFlow = false
                    })
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(.white)
                    }
                }
                .preferredColorScheme(.dark)
                .sheet(item: $settingsHelpTopic) { topic in
                    SettingsHelpSheet(topic: topic)
                }
                .fullScreenCover(isPresented: $showAuth) {
                    AuthView(onAuthenticated: {
                        showAuth = false
                        dismiss()
                    })
                    .environmentObject(authService)
                }
                .onAppear {
                    customProfileImageData = authService.profileImageData
                    loadCloudStorageIfNeeded()
                    tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles
                }
                .onChange(of: authService.currentUser?.id) { _, _ in
                    customProfileImageData = authService.profileImageData
                    loadCloudStorageIfNeeded()
                }
                .onChange(of: photoAuth.status) { _, _ in
                    tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles
                }
                .fileImporter(
                    isPresented: $showImportBackupPicker,
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        stageImportBackupAndPrompt(from: url)
                    case .failure(let error):
                        backupFlowAlertTitle = "Import failed"
                        backupFlowAlertMessage = error.localizedDescription
                        showBackupFlowAlert = true
                    }
                }
                .sheet(isPresented: $showBackupAllShareSheet, onDismiss: {
                    if let u = backupAllShareURL {
                        try? FileManager.default.removeItem(at: u)
                        backupAllShareURL = nil
                    }
                }) {
                    if let u = backupAllShareURL {
                        ShareSheet(items: [u])
                    }
                }
                .sheet(isPresented: $showReceiveBlogDrop) {
                    BlogDropReceiveSheet()
                        .environmentObject(createdRecapStore)
                }
                .alert(backupFlowAlertTitle, isPresented: $showBackupFlowAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(backupFlowAlertMessage)
                }
            }

            if isImportingBackup || isExportingAllBackups {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(isImportingBackup ? "Importing backup…" : "Exporting backups…")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ProgressView(value: backupFlowProgress, total: 1)
                        .tint(.white)
                        .frame(maxWidth: 220)
                    Text("\(Int((backupFlowProgress * 100).rounded(.down)))%")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 16))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isImportingBackup)
        .animation(.easeInOut(duration: 0.2), value: isExportingAllBackups)
    }

    @MainActor
    private func exportAllBlogsBackupTapped() async {
        isExportingAllBackups = true
        backupFlowProgress = 0
        defer {
            isExportingAllBackups = false
            backupFlowProgress = 0
        }
        do {
            let url = try await BlogBackupService.exportAllVisibleBlogsZip(
                store: createdRecapStore,
                progress: { frac in
                    Task { @MainActor in
                        backupFlowProgress = frac
                    }
                }
            )
            await Task.yield()
            backupFlowProgress = 1
            backupAllShareURL = url
            showBackupAllShareSheet = true
        } catch {
            backupFlowAlertTitle = "Export failed"
            backupFlowAlertMessage = error.localizedDescription
            showBackupFlowAlert = true
        }
    }

    @MainActor
    private func stageImportBackupAndPrompt(from pickedURL: URL) {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { pickedURL.stopAccessingSecurityScopedResource() }
        }
        do {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("bloggo-import-staging-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: pickedURL, to: dest)
            let preferLibrary = preferPhotoLibraryWhenImportingBackup
            Task { @MainActor in
                await importBlogBackup(stagedZipURL: dest, preferPhotoLibrary: preferLibrary)
            }
        } catch {
            backupFlowAlertTitle = "Import failed"
            backupFlowAlertMessage = error.localizedDescription
            showBackupFlowAlert = true
        }
    }

    @MainActor
    private func importBlogBackup(stagedZipURL: URL, preferPhotoLibrary: Bool) async {
        isImportingBackup = true
        backupFlowProgress = 0
        defer {
            isImportingBackup = false
            backupFlowProgress = 0
            try? FileManager.default.removeItem(at: stagedZipURL)
        }
        do {
            if preferPhotoLibrary, !photoAuth.isAuthorized {
                await photoAuth.requestAccess()
            }
            backupFlowProgress = 0.06
            await Task.yield()
            let ids = try await BlogBackupService.importFromZip(
                zipURL: stagedZipURL,
                store: createdRecapStore,
                preferPhotoLibrary: preferPhotoLibrary && photoAuth.isAuthorized,
                progress: { frac in
                    Task { @MainActor in
                        backupFlowProgress = 0.06 + 0.94 * frac
                    }
                }
            )
            backupFlowAlertTitle = "Import complete"
            backupFlowAlertMessage = ids.count == 1 ? "Added 1 blog." : "Added \(ids.count) blogs."
            showBackupFlowAlert = true
        } catch {
            backupFlowAlertTitle = "Import failed"
            backupFlowAlertMessage = error.localizedDescription
            showBackupFlowAlert = true
        }
    }

    private func loadCloudStorageIfNeeded() {
        guard authService.isSignedIn, EntitlementManager.shared.realProActive else {
            cloudStorageUsage = nil
            cloudStorageError = nil
            return
        }
        cloudStorageLoading = true
        cloudStorageError = nil
        Task {
            do {
                let usage = try await APIManager.shared.fetchCloudStorageUsage()
                await MainActor.run {
                    cloudStorageUsage = usage
                    cloudStorageError = nil
                }
            } catch {
                await MainActor.run {
                    cloudStorageUsage = nil
                    cloudStorageError = error.localizedDescription
                }
            }
            await MainActor.run {
                cloudStorageLoading = false
            }
        }
    }

    private func formatCloudStorageDate(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        if let date = isoNoFrac.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return isoString
    }
}

