# Camera Landing & Bottom Nav Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace LandingView with CameraCaptureView as the app home screen and add a persistent BottomNavBar (My Blogs | Camera | My Places) across all three primary screens.

**Architecture:** CameraCaptureView becomes the permanent ZStack base layer in ContentView; LandingView is deleted after redistributing its responsibilities (SettingsView → own file, recentRecapsSection → MyBlogsProfileView, toast → ContentView, bottomMenuBar → BottomNavBar component). Each primary screen gets a gear icon (Settings) and BottomNavBar.

**Tech Stack:** SwiftUI, ZStack overlay navigation pattern (existing), safeAreaInset for bottom nav layout.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Views/SettingsView.swift` | Extracted from LandingView.swift; internal access |
| Create | `Views/Components/BottomNavBar.swift` | Shared 3-tab bottom nav component |
| Modify | `fastblog.xcodeproj/project.pbxproj` | Register 2 new files, remove LandingView |
| Modify | `Views/TripsView.swift` | CameraCaptureView: remove X, add BottomNavBar, remove swipe-dismiss |
| Modify | `ContentView.swift` | Camera as base, remove LandingView, add toast overlay |
| Modify | `Views/MyBlogsProfileView.swift` | Gear, Tap to Blog banner, Latest Edits, BottomNavBar |
| Modify | `Views/PlacesVisitedView.swift` | Gear icon in standalone toolbar |
| Delete | `Views/LandingView.swift` | All responsibilities redistributed |

---

## Task 1: Create `Views/SettingsView.swift`

`SettingsView` is currently `private struct SettingsView` inside `LandingView.swift` (line 884). It needs to be accessible from My Blogs and My Places. Move it to its own file.

**Files:**
- Create: `fastblog/Views/SettingsView.swift`
- Modify: `fastblog/Views/LandingView.swift` (remove the moved types)
- Modify: `fastblog.xcodeproj/project.pbxproj` (register new file)

- [ ] **Step 1: Create `fastblog/Views/SettingsView.swift`**

Copy these types from LandingView.swift, changing `private` to `internal` (drop the keyword):

```swift
//
//  SettingsView.swift
//  Capper
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings help topics

enum SettingsHelpTopic: String, Identifiable {
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

struct SettingsHelpTopicCard: View {
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

struct SettingsBlogBackupHelpContent: View {
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

struct SettingsMyHomeHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHelpTopicCard(
                icon: "house.fill",
                tint: Color(red: 0.35, green: 0.65, blue: 1.0),
                title: "What "My home" is",
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

struct SettingsHelpSheet: View {
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
                    case .blogBackup: SettingsBlogBackupHelpContent()
                    case .myHome:     SettingsMyHomeHelpContent()
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

            Button { dismiss() } label: {
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

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showNeighborhoodFlow = false
    @State private var showAuth = false
    @State private var showDeleteAccountAlert = false

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
                                                colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
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
                                    Text("Loading…").foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            } else if let error = cloudStorageError {
                                Text(error).foregroundColor(.secondary)
                            } else if let usage = cloudStorageUsage {
                                LabeledContent("Storage used", value: String(format: "%.2f MB", usage.totalMB))
                                LabeledContent("Photos", value: "\(usage.photoCount)")
                                if let updated = usage.lastUpdated, !updated.isEmpty {
                                    LabeledContent("Last updated", value: formatCloudStorageDate(updated))
                                }
                            }

                            Button { authService.signOut() } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Button { showAuth = true } label: {
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
                    } header: {
                        Text("Permissions")
                    }

                    Section {
                        Button { showNeighborhoodFlow = true } label: {
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
                            Button { settingsHelpTopic = .myHome } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Learn more about My home")
                        }
                    }

                    Section {
                        Button { showImportBackupPicker = true } label: {
                            Label("Import blog backup", systemImage: "arrow.down.doc")
                        }
                        .disabled(isImportingBackup)

                        Button { showReceiveBlogDrop = true } label: {
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

                        Button { Task { await exportAllBlogsBackupTapped() } } label: {
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
                            Button { settingsHelpTopic = .blogBackup } label: {
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
                                Text("Privacy Policy").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "hand.raised.fill").foregroundStyle(.white)
                            }
                        }
                        NavigationLink {
                            TermsOfServiceView()
                        } label: {
                            Label {
                                Text("Terms of Service").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "doc.text.fill").foregroundStyle(.white)
                            }
                        }
                    } header: {
                        Text("Legal")
                    }

                    if authService.isSignedIn {
                        Section {
                            Button { showDeleteAccountAlert = true } label: {
                                Label("Delete Account", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                                Button("Delete", role: .destructive) {
                                    Task { await authService.deleteAccount() }
                                    dismiss()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Are you sure? This will permanently delete your account and all associated data from our servers. This action is immediate and cannot be undone.")
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showNeighborhoodFlow) {
                    NeighborhoodIntroView(onDismiss: { showNeighborhoodFlow = false })
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
                    if let u = backupAllShareURL { ShareSheet(items: [u]) }
                }
                .sheet(isPresented: $showReceiveBlogDrop) {
                    BlogDropReceiveSheet().environmentObject(createdRecapStore)
                }
                .alert(backupFlowAlertTitle, isPresented: $showBackupFlowAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(backupFlowAlertMessage)
                }
            }

            if isImportingBackup || isExportingAllBackups {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(isImportingBackup ? "Importing backup…" : "Exporting backups…")
                        .font(.headline).foregroundStyle(.white)
                    ProgressView(value: backupFlowProgress, total: 1)
                        .tint(.white).frame(maxWidth: 220)
                    Text("\(Int((backupFlowProgress * 100).rounded(.down)))%")
                        .font(.title3.monospacedDigit()).foregroundStyle(.white.opacity(0.9))
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
        defer { isExportingAllBackups = false; backupFlowProgress = 0 }
        do {
            let url = try await BlogBackupService.exportAllVisibleBlogsZip(
                store: createdRecapStore,
                progress: { frac in Task { @MainActor in backupFlowProgress = frac } }
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
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }
        do {
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-import-staging-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: pickedURL, to: dest)
            let preferLibrary = preferPhotoLibraryWhenImportingBackup
            Task { @MainActor in await importBlogBackup(stagedZipURL: dest, preferPhotoLibrary: preferLibrary) }
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
            if preferPhotoLibrary, !photoAuth.isAuthorized { await photoAuth.requestAccess() }
            backupFlowProgress = 0.06
            await Task.yield()
            let ids = try await BlogBackupService.importFromZip(
                zipURL: stagedZipURL,
                store: createdRecapStore,
                preferPhotoLibrary: preferPhotoLibrary && photoAuth.isAuthorized,
                progress: { frac in Task { @MainActor in backupFlowProgress = 0.06 + 0.94 * frac } }
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
                await MainActor.run { cloudStorageUsage = usage; cloudStorageError = nil }
            } catch {
                await MainActor.run { cloudStorageUsage = nil; cloudStorageError = error.localizedDescription }
            }
            await MainActor.run { cloudStorageLoading = false }
        }
    }

    private func formatCloudStorageDate(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: isoString) { return date.formatted(date: .abbreviated, time: .shortened) }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        if let date = isoNoFrac.date(from: isoString) { return date.formatted(date: .abbreviated, time: .shortened) }
        return isoString
    }
}
```

- [ ] **Step 2: Remove moved types from `LandingView.swift`**

In `LandingView.swift`, delete the following blocks (they are now in `SettingsView.swift`):
- Lines 652–674: `private enum SettingsHelpTopic`
- Lines 676–716: `private struct SettingsHelpTopicCard`
- Lines 718–743: `private struct SettingsBlogBackupHelpContent`
- Lines 745–776: `private struct SettingsMyHomeHelpContent`
- Lines 778–881: `private struct SettingsHelpSheet`
- Lines 883–1466: `private struct SettingsView`

Keep these in LandingView.swift for now (they'll move in later tasks):
- `LatestEditsMoreHintCard` (line 558)
- `CreatedRecapCard` (line 594)

- [ ] **Step 3: Register `SettingsView.swift` in `fastblog.xcodeproj/project.pbxproj`**

Add to **PBXBuildFile** section (near line 70):
```
		BB0003B7 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0003B6 /* SettingsView.swift */; };
```

Add to **PBXFileReference** section (near line 340):
```
		BB0003B6 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
```

Add to **Views PBXGroup** (BB0001B2, near line 684):
```
				BB0003B6 /* SettingsView.swift */,
```

Add to **PBXSourcesBuildPhase** (near line 1070):
```
				BB0003B7 /* SettingsView.swift in Sources */,
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|warning: 'private'|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`. If you see "use of undeclared type 'SettingsView'" errors, check that `SettingsView.swift` is in the Sources phase.

- [ ] **Step 5: Commit**

```bash
git add fastblog/Views/SettingsView.swift fastblog/Views/LandingView.swift fastblog.xcodeproj/project.pbxproj
git commit -m "refactor: extract SettingsView to its own file for shared access"
```

---

## Task 2: Create `Views/Components/BottomNavBar.swift`

**Files:**
- Create: `fastblog/Views/Components/BottomNavBar.swift`
- Modify: `fastblog.xcodeproj/project.pbxproj` (register)

- [ ] **Step 1: Create `fastblog/Views/Components/BottomNavBar.swift`**

```swift
//
//  BottomNavBar.swift
//  Capper
//

import SwiftUI

enum BottomNavTab {
    case myBlogs
    case camera
    case myPlaces
}

struct BottomNavBar: View {
    let activeTab: BottomNavTab
    var onMyBlogs:  () -> Void = {}
    var onCamera:   () -> Void = {}
    var onMyPlaces: () -> Void = {}

    private let appBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        VStack(spacing: 0) {
            Color.white.opacity(0.12)
                .frame(height: 1 / UIScreen.main.scale)

            HStack(spacing: 0) {
                tabItem(
                    icon: { Image("MyBlogsIcon").resizable().renderingMode(.template).frame(width: 24, height: 24) },
                    label: "My Blogs",
                    isActive: activeTab == .myBlogs,
                    action: onMyBlogs
                )
                tabItem(
                    icon: { Image(systemName: "camera.fill").font(.system(size: 20)).frame(width: 24, height: 24) },
                    label: "Camera",
                    isActive: activeTab == .camera,
                    action: onCamera
                )
                tabItem(
                    icon: { Image("MyPlacesIcon").resizable().renderingMode(.template).frame(width: 24, height: 24) },
                    label: "My Places",
                    isActive: activeTab == .myPlaces,
                    action: onMyPlaces
                )
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .safeAreaPadding(.bottom)
        }
        .background(appBackground)
    }

    @ViewBuilder
    private func tabItem<Icon: View>(
        icon: () -> Icon,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                    .foregroundColor(isActive ? .white : .white.opacity(0.4))
                Text(label)
                    .font(.caption2)
                    .foregroundColor(isActive ? .white : .white.opacity(0.4))
                Circle()
                    .fill(isActive ? Color.white : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Register `BottomNavBar.swift` in `fastblog.xcodeproj/project.pbxproj`**

Add to **PBXBuildFile** section:
```
		BB0003B9 /* BottomNavBar.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0003B8 /* BottomNavBar.swift */; };
```

Add to **PBXFileReference** section:
```
		BB0003B8 /* BottomNavBar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BottomNavBar.swift; sourceTree = "<group>"; };
```

Add to **Components PBXGroup** (BB0001CB, near line 910):
```
				BB0003B8 /* BottomNavBar.swift */,
```

Add to **PBXSourcesBuildPhase**:
```
				BB0003B9 /* BottomNavBar.swift in Sources */,
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add fastblog/Views/Components/BottomNavBar.swift fastblog.xcodeproj/project.pbxproj
git commit -m "feat: add BottomNavBar component with My Blogs / Camera / My Places tabs"
```

---

## Task 3: Update `CameraCaptureView` in `Views/TripsView.swift`

Three changes: (1) add nav callbacks, (2) remove xmark close button, (3) remove swipe-down dismiss, (4) add BottomNavBar.

**Files:**
- Modify: `fastblog/Views/TripsView.swift`

- [ ] **Step 1: Add `onShowMyBlogs` and `onShowMyPlaces` callback parameters**

`CameraCaptureView` is defined at line 2227. After `var forcedTargetBlogId: UUID? = nil` (line 2238), the existing properties continue. Add the two new callbacks after line 2238:

Find this block (lines 2233–2238):
```swift
    /// When set (ZStack overlay presentation), called instead of dismiss().
    var onDismissOverlay: (() -> Void)? = nil
    var onNavigateToBlog: ((UUID) -> Void)? = nil
    /// When set, all captured photos are always routed to this blog regardless of date/on-the-go state.
    /// Used when the camera is opened from inside an existing blog.
    var forcedTargetBlogId: UUID? = nil
```

Replace with:
```swift
    /// When set (ZStack overlay presentation), called instead of dismiss().
    var onDismissOverlay: (() -> Void)? = nil
    var onNavigateToBlog: ((UUID) -> Void)? = nil
    /// When set, all captured photos are always routed to this blog regardless of date/on-the-go state.
    /// Used when the camera is opened from inside an existing blog.
    var forcedTargetBlogId: UUID? = nil
    /// Bottom nav callbacks — wired by ContentView when camera is the home screen.
    var onShowMyBlogs: () -> Void = {}
    var onShowMyPlaces: () -> Void = {}
```

- [ ] **Step 2: Remove the xmark close button from `nonCaptionCameraOverlay`**

The xmark button is at lines 2859–2873. Find this exact block in `nonCaptionCameraOverlay`:
```swift
        // Top controls: X (top-left) + Reverse / Flash / Save to Photos (top-right)
        Button {
            closeCamera()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel("Close camera")
        .padding(.top, 8)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

Delete this entire Button block. The top-right controls (flip, flash, save-to-photos) immediately following it are unchanged.

- [ ] **Step 3: Remove swipe-down dismiss from `inAppCameraChromeRoot`**

`inAppCameraChromeRoot` (line 3643) has a DragGesture that calls `closeCamera()` on downward swipe. Find this block:
```swift
            } else if value.translation.height > 50 {
                    // Swipe-down dismiss is allowed only before any photo is captured.
                    let hasCapturedPhotos = photosCapturedThisSession > 0
                        || !sessionCapturesForDisplay.isEmpty
                        || !sessionMoments.isEmpty
                    guard !hasCapturedPhotos else { return }
                    closeCamera()
                }
```

Replace with (remove the `else if` branch entirely — keep only the upward swipe for gallery):
```swift
            } else if value.translation.height < -50 {
                isShowingCapturesGallery = true
            }
```

The full DragGesture in `inAppCameraChromeRoot` after this change:
```swift
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        guard !isCaptionModeActive else { return }
                        if value.translation.height < -50 {
                            isShowingCapturesGallery = true
                        }
                    }
            )
```

- [ ] **Step 4: Add BottomNavBar to `inAppCameraChromeRoot`**

`inAppCameraChromeRoot` returns `inAppCameraPreviewStack` with several modifiers. Add `.safeAreaInset(edge: .bottom, spacing: 0)` with the BottomNavBar. Find the end of `inAppCameraChromeRoot` (around line 3679):

```swift
            .overlay(alignment: .top) { toastOverlay }
    }
```

Replace with:
```swift
            .overlay(alignment: .top) { toastOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isCaptionModeActive {
                    BottomNavBar(
                        activeTab: .camera,
                        onMyBlogs: onShowMyBlogs,
                        onCamera: {},
                        onMyPlaces: onShowMyPlaces
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isCaptionModeActive)
                }
            }
    }
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/TripsView.swift
git commit -m "feat: camera home screen — remove dismiss button, add bottom nav bar"
```

---

## Task 4: Update `ContentView.swift`

Replace LandingView as the base layer with CameraCaptureView. Add toast overlay. Remove showCameraFromHome and showProfile state.

**Files:**
- Modify: `fastblog/ContentView.swift`

- [ ] **Step 1: Remove unused state variables**

At the top of `ContentView`, remove these `@State` lines:
```swift
    @State private var showProfile = false
    @State private var showCameraFromHome = false
```

- [ ] **Step 2: Remove the LandingView block and camera overlay from `rootContent`**

In `rootContent`, the ZStack currently starts with a `NavigationStack { LandingView(...) }` base layer and has a `showCameraFromHome` camera overlay block. Replace the entire `rootContent` computed property with:

```swift
    private var rootContent: some View {
        ZStack {
            // Camera is the permanent home base layer.
            CameraCaptureView(
                tripsViewModel: tripsViewModel,
                postDismissToast: { msg in postCameraToastMessage = msg },
                onShowMyBlogs: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = true }
                },
                onShowMyPlaces: {
                    withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = true }
                }
            )
            .environmentObject(createdRecapStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Post-camera toast banner (appears over camera base layer)
            if let toastMsg = postCameraToastMessage {
                VStack {
                    HStack(spacing: 12) {
                        Group {
                            if toastMsg.contains("added to") {
                                Image("MyBlogsIcon")
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundColor(.green)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                        }
                        Text(toastMsg)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            withAnimation { postCameraToastMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(appChromeBaseRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(appChromeBaseRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }

            // My Blogs overlay (fade in/out).
            if showSeeAll {
                NavigationStack {
                    MyBlogsProfileView(
                        createdRecapStore: createdRecapStore,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
                        openRecapInEditMode: $openRecapInEditMode,
                        openRecapPresentShareYourBlogSheet: $openRecapPresentShareYourBlogSheet,
                        tripsViewModel: tripsViewModel,
                        onDismissCover: {
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = false }
                        },
                        onTapToBlog: {
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = false }
                            handleTapToBlog()
                        },
                        onShowCamera: {
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = false }
                        },
                        onShowMyPlaces: {
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = false }
                            withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = true }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.primary)
                .preferredColorScheme(.dark)
                .transition(.opacity)
                .zIndex(3)
            }

            // Places Visited overlay (fade in/out).
            if showPlacesVisited {
                NavigationStack {
                    PlacesVisitedStandaloneView(
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = false }
                        },
                        onShowCamera: {
                            withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = false }
                        },
                        onShowMyBlogs: {
                            withAnimation(.easeInOut(duration: 0.18)) { showPlacesVisited = false }
                            withAnimation(.easeInOut(duration: 0.25)) { showSeeAll = true }
                        }
                    )
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.primary)
                .transition(.opacity)
                .zIndex(4)
            }

            // Trips overlay.
            if showTrips || pendingShowTripsWhenIdle || tripsViewKeepMounted {
                NavigationStack {
                    TripsView(
                        viewModel: tripsViewModel,
                        selectedCreatedRecap: $selectedCreatedRecap,
                        initialDayIndexForRecap: $initialDayIndexForRecap,
                        onDismiss: dismissTripsOverlay
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showTrips ? 1 : 0)
                .allowsHitTesting(showTrips)
                .animation(.easeInOut(duration: 0.35), value: showTrips)
                .zIndex(5)
                .transition(.identity)
            }

            // Blog overlay.
            if let recap = selectedCreatedRecap {
                NavigationStack {
                    RecapBlogPageView(
                        blogId: recap.sourceTripId,
                        initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId),
                        initialDayIndex: initialDayIndexForRecap,
                        initialScrollToStopId: initialScrollToStopIdForRecap,
                        forceEditMode: openRecapInEditMode,
                        forcePresentShareYourBlogSheet: openRecapPresentShareYourBlogSheet,
                        onRequestDismiss: {
                            initialDayIndexForRecap = nil
                            initialScrollToStopIdForRecap = nil
                            openRecapInEditMode = false
                            openRecapPresentShareYourBlogSheet = false
                            selectedCreatedRecap = nil
                        }
                    )
                    .id("\(recap.sourceTripId.uuidString)-\(initialScrollToStopIdForRecap?.uuidString ?? "none")")
                    .environmentObject(createdRecapStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(10)
            }

            if tripsViewModel.scanState != .idle {
                LoadingScanView(
                    message: tripsViewModel.loadingMessage,
                    progress: tripsViewModel.defaultScanProgress,
                    onCancel: {
                        tripsViewModel.cancelDefaultScan()
                        pendingShowTripsWhenIdle = false
                        dismissTripsOverlay()
                    },
                    progressStepLabelOverride: { p in
                        p >= 0.9 ? "Almost done..." : "Please wait..."
                    },
                    useCenteredLayout: true
                )
                .transition(.identity)
                .zIndex(20)
            }
        }
    }
```

- [ ] **Step 3: Update `body` animations — remove showCameraFromHome animation**

In `body`, find:
```swift
            .animation(.easeInOut(duration: 0.18), value: showCameraFromHome)
```
Delete that line.

- [ ] **Step 4: Update `onChange` for `postCameraToastMessage`**

LandingView used to auto-dismiss the toast. Move that logic to ContentView's `body`. Find where the toast auto-dismiss timer is and add it to `body` (it was in LandingView's `.onChange(of: postCameraToastMessage)`). Add after the existing `.onChange` blocks in `body`:

```swift
            .onChange(of: postCameraToastMessage) { _, msg in
                if msg != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            postCameraToastMessage = nil
                        }
                    }
                }
            }
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`. Common error: "extra argument" on `MyBlogsProfileView` init — that's expected until Task 5 adds those params.

- [ ] **Step 6: Commit**

```bash
git add fastblog/ContentView.swift
git commit -m "feat: camera as home base layer — remove LandingView, add toast overlay"
```

---

## Task 5: Update `MyBlogsProfileView.swift`

Add gear button (Settings), Tap to Blog banner, Latest Edits section, BottomNavBar. Move `CreatedRecapCard` and `LatestEditsMoreHintCard` here from LandingView.

**Files:**
- Modify: `fastblog/Views/MyBlogsProfileView.swift`
- Modify: `fastblog/Views/LandingView.swift` (remove moved types)

- [ ] **Step 1: Add new callback parameters to `MyBlogsProfileView`**

Find the existing parameter declarations (around line 39):
```swift
    var onDismissCover: (() -> Void)? = nil
    var onTopScrollStateChange: ((Bool) -> Void)? = nil
```

Replace with:
```swift
    var onDismissCover: (() -> Void)? = nil
    var onTapToBlog: (() -> Void)? = nil
    var onShowCamera: (() -> Void)? = nil
    var onShowMyPlaces: (() -> Void)? = nil
    var onTopScrollStateChange: ((Bool) -> Void)? = nil
```

- [ ] **Step 2: Update the `init` to accept new callbacks**

Find the `init` function (lines 69–86). Replace with:
```swift
    init(
        createdRecapStore: CreatedRecapBlogStore,
        selectedCreatedRecap: Binding<CreatedRecapBlog?>,
        initialDayIndexForRecap: Binding<Int?> = .constant(nil),
        openRecapInEditMode: Binding<Bool> = .constant(false),
        openRecapPresentShareYourBlogSheet: Binding<Bool> = .constant(false),
        tripsViewModel: TripsViewModel,
        onDismissCover: (() -> Void)? = nil,
        onTapToBlog: (() -> Void)? = nil,
        onShowCamera: (() -> Void)? = nil,
        onShowMyPlaces: (() -> Void)? = nil,
        onTopScrollStateChange: ((Bool) -> Void)? = nil
    ) {
        _selectedCreatedRecap = selectedCreatedRecap
        _initialDayIndexForRecap = initialDayIndexForRecap
        _openRecapInEditMode = openRecapInEditMode
        _openRecapPresentShareYourBlogSheet = openRecapPresentShareYourBlogSheet
        _tripsViewModel = ObservedObject(wrappedValue: tripsViewModel)
        self.onDismissCover = onDismissCover
        self.onTapToBlog = onTapToBlog
        self.onShowCamera = onShowCamera
        self.onShowMyPlaces = onShowMyPlaces
        self.onTopScrollStateChange = onTopScrollStateChange
    }
```

- [ ] **Step 3: Add `showSettings` state variable**

After the existing `@State private var countrySearchBarFocused = false` line, add:
```swift
    @State private var showSettings = false
```

- [ ] **Step 4: Add Latest Edits state variables**

After `showSettings`, add:
```swift
    private let latestEditsPageSize = 5
    @State private var latestEditsVisibleCount = 5
    @State private var isLoadingLatestEditsBatch = false
```

- [ ] **Step 5: Change xmark to gearshape in toolbar**

In the toolbar (`.topBarLeading` ToolbarItem, `.blogs` case), replace the xmark button:

Find:
```swift
                case .blogs:
                    Button {
                        isSearchFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onDismissCover?()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
```

Replace with:
```swift
                case .blogs:
                    Button {
                        isSearchFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.semibold))
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 1.5).onEnded { _ in
                            OnboardingStore.hasCompletedOnboarding = false
                        }
                    )
```

- [ ] **Step 6: Add SettingsView sheet to `body`**

After the existing `.sheet(isPresented: $showManage)` block, add:
```swift
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(photoAuth)
                .environmentObject(createdRecapStore)
        }
```

Where `authService` and `photoAuth` need to be accessible. Add these at the top of `MyBlogsProfileView`:
```swift
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
```

(Add after the existing `@EnvironmentObject private var createdRecapStore` line at the top of the struct, around line 30.)

- [ ] **Step 7: Add Tap to Blog banner computed property**

Add after the existing `private var isOnBlogsPage: Bool` computed property:

```swift
    @ViewBuilder
    private var tapToBlogBanner: some View {
        Button {
            onTapToBlog?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tap to Blog")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Scan your photos into a blog")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.12))
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 12)
                    .stroke(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.25), lineWidth: 1)
            )
            .appChromeCornerRadius(12)
            .padding(.horizontal, horizontalPadding)
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 8: Add Latest Edits section computed properties and helpers**

Add after `tapToBlogBanner`:

```swift
    private var allLatestEdits: [CreatedRecapBlog] { createdRecapStore.displayRecents }
    private var visibleLatestEdits: [CreatedRecapBlog] { Array(allLatestEdits.prefix(latestEditsVisibleCount)) }
    private var hasMoreLatestEdits: Bool { allLatestEdits.count > latestEditsVisibleCount }

    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

    @ViewBuilder
    private var recentRecapsSection: some View {
        if !allLatestEdits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest Edits")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: 22, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleLatestEdits) { recap in
                            CreatedRecapCard(recap: recap)
                                .onTapGesture { selectedCreatedRecap = recap }
                        }
                        if hasMoreLatestEdits {
                            LatestEditsMoreHintCard { loadMoreLatestEdits() }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .contentMargins(.horizontal, horizontalPadding, for: .scrollContent)
                .frame(height: 128)
                .clipped()
                .overlay(alignment: .trailing) {
                    if hasMoreLatestEdits {
                        LinearGradient(
                            colors: [landingBackground.opacity(0), landingBackground.opacity(0.75), landingBackground],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 36)
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(.top, 16)
            .animation(nil, value: latestEditsVisibleCount)
            .onChange(of: allLatestEdits.count) { _, newCount in
                latestEditsVisibleCount = min(latestEditsVisibleCount, newCount)
            }
        }
    }

    private func loadMoreLatestEdits() {
        guard hasMoreLatestEdits, !isLoadingLatestEditsBatch else { return }
        isLoadingLatestEditsBatch = true
        latestEditsVisibleCount = min(latestEditsVisibleCount + latestEditsPageSize, allLatestEdits.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isLoadingLatestEditsBatch = false }
    }
```

- [ ] **Step 9: Inject Tap to Blog banner + Latest Edits into blog page content**

Find the place in `pageContent` (or the blogs page `LazyVStack`) where country cards begin. In `MyBlogsProfileView`, the main blog list scrolls country sections. Add the banner and Latest Edits at the top of the country list content. 

Search for the blogs page content — look for the `LazyVStack` that renders country cards inside the blog page scroll view. Add before the first `ForEach` of country sections:

```swift
                        tapToBlogBanner
                            .padding(.top, 8)
                        recentRecapsSection
```

This goes inside the `LazyVStack` in the blog page's `ScrollView`, before the `ForEach(viewModel.countrySections)` call.

- [ ] **Step 10: Add BottomNavBar to the outer ZStack**

At the end of the `ZStack(alignment: .bottom)` body, before `.navigationTitle(...)`, add:

```swift
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavBar(
                activeTab: .myBlogs,
                onMyBlogs: {},
                onCamera: { onShowCamera?() },
                onMyPlaces: { onShowMyPlaces?() }
            )
        }
```

- [ ] **Step 11: Move `CreatedRecapCard` and `LatestEditsMoreHintCard` from `LandingView.swift`**

Copy `LatestEditsMoreHintCard` (LandingView.swift line 558–591) and `CreatedRecapCard` (LandingView.swift line 594–650) to the bottom of `MyBlogsProfileView.swift` (after the closing brace of `MyBlogsProfileView`). Change `private struct` to `struct` (remove `private`).

Then delete those two types from `LandingView.swift`.

- [ ] **Step 12: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 13: Commit**

```bash
git add fastblog/Views/MyBlogsProfileView.swift fastblog/Views/LandingView.swift
git commit -m "feat: My Blogs — gear settings, Tap to Blog banner, Latest Edits, bottom nav"
```

---

## Task 6: Update `PlacesVisitedStandaloneView` and `PlacesVisitedView`

Add gear icon (Settings) and BottomNavBar to My Places.

**Files:**
- Modify: `fastblog/Views/PlacesVisitedView.swift`

- [ ] **Step 1: Add callbacks and settings state to `PlacesVisitedStandaloneView`**

`PlacesVisitedStandaloneView` is at line 17 of `PlacesVisitedView.swift`. Add callback params and settings state:

Find the struct declaration:
```swift
struct PlacesVisitedStandaloneView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    var onDismiss: () -> Void
```

Replace with:
```swift
struct PlacesVisitedStandaloneView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var initialScrollToStopIdForRecap: UUID?
    var onDismiss: () -> Void
    var onShowCamera: (() -> Void)? = nil
    var onShowMyBlogs: (() -> Void)? = nil

    @State private var showSettings = false
```

- [ ] **Step 2: Update `PlacesVisitedStandaloneView.body` to add BottomNavBar and pass settings callback**

Current body:
```swift
    var body: some View {
        PlacesVisitedView(
            searchText: $searchText,
            showPlacesMap: $showPlacesMap,
            selectedCreatedRecap: $selectedCreatedRecap,
            initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
            standaloneOnDismiss: onDismiss
        )
        .background(backgroundBlue.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Places Visited")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
    }
```

Replace with:
```swift
    var body: some View {
        PlacesVisitedView(
            searchText: $searchText,
            showPlacesMap: $showPlacesMap,
            selectedCreatedRecap: $selectedCreatedRecap,
            initialScrollToStopIdForRecap: $initialScrollToStopIdForRecap,
            standaloneOnDismiss: onDismiss,
            onShowSettings: { showSettings = true }
        )
        .background(backgroundBlue.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Places Visited")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavBar(
                activeTab: .myPlaces,
                onMyBlogs: { onShowMyBlogs?() },
                onCamera: { onShowCamera?() },
                onMyPlaces: {}
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(photoAuth)
                .environmentObject(createdRecapStore)
        }
    }
```

- [ ] **Step 3: Add `onShowSettings` parameter to `PlacesVisitedView`**

`PlacesVisitedView` is at line 46. It accepts `standaloneOnDismiss`. Add `onShowSettings` next to it:

Find:
```swift
    var standaloneOnDismiss: (() -> Void)? = nil
```

Replace with:
```swift
    var standaloneOnDismiss: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil
```

- [ ] **Step 4: Change xmark to gearshape in `PlacesVisitedView` toolbar**

Find the standalone dismiss toolbar item (around line 388–400):
```swift
                if let standaloneOnDismiss {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            standaloneOnDismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
```

Replace with:
```swift
                if standaloneOnDismiss != nil {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        onShowSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add fastblog/Views/PlacesVisitedView.swift
git commit -m "feat: My Places — gear settings, bottom nav bar"
```

---

## Task 7: Delete `LandingView.swift` and clean up

`LandingView` is no longer referenced. Remove it from the project and delete the file.

**Files:**
- Delete: `fastblog/Views/LandingView.swift`
- Modify: `fastblog.xcodeproj/project.pbxproj`

- [ ] **Step 1: Verify nothing still imports or references `LandingView`**

```bash
grep -rn "LandingView\|SettingsView\|LatestEditsMoreHintCard\|CreatedRecapCard\|AllRecentsSheet\|NotificationsOverlayView" /Users/justinseo/Desktop/Bloggo/fastblog/fastblog/fastblog --include="*.swift" | grep -v "LandingView.swift\|old_landing\|.diff"
```

Expected: zero matches for `LandingView` in active Swift files. `SettingsView` should appear in `SettingsView.swift`, `MyBlogsProfileView.swift`, and `PlacesVisitedView.swift` only. If any file still references `LandingView`, fix those references first before deleting.

- [ ] **Step 2: Remove LandingView entries from `project.pbxproj`**

Remove these three lines from `project.pbxproj`:
- `BB000136 /* LandingView.swift in Sources */ = {isa = PBXBuildFile; ...};` (PBXBuildFile section)
- `BB000135 /* LandingView.swift */ = {isa = PBXFileReference; ...};` (PBXFileReference section)
- `BB000135 /* LandingView.swift */,` (Views PBXGroup children)
- `BB000136 /* LandingView.swift in Sources */,` (PBXSourcesBuildPhase)

- [ ] **Step 3: Delete the file**

```bash
rm /Users/justinseo/Desktop/Bloggo/fastblog/fastblog/fastblog/Views/LandingView.swift
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog/fastblog && xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`. If you see "undeclared identifier" errors, one of the types that used to be in LandingView (`SettingsView`, `CreatedRecapCard`, etc.) wasn't fully moved — check which file it's referenced from.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete LandingView.swift — all responsibilities redistributed"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Camera as base layer in ContentView | Task 4 |
| LandingView removed | Task 7 |
| showTrips/pending scan flow stays in ContentView | Task 4 (preserved in rootContent) |
| Post-camera toast stays in ContentView | Task 4 (moved from LandingView) |
| CameraCaptureView: remove xmark | Task 3 |
| CameraCaptureView: add BottomNavBar (camera active) | Task 3 |
| CameraCaptureView: shift shutter bar up via safeAreaInset | Task 3 |
| CameraCaptureView: remove swipe-down dismiss | Task 3 |
| MyBlogsProfileView: gear → SettingsView | Task 5 |
| MyBlogsProfileView: Tap to Blog banner | Task 5 |
| MyBlogsProfileView: Latest Edits carousel | Task 5 |
| MyBlogsProfileView: BottomNavBar (myBlogs active) | Task 5 |
| PlacesVisitedStandaloneView: gear → SettingsView | Task 6 |
| PlacesVisitedStandaloneView: BottomNavBar (myPlaces active) | Task 6 |
| SettingsView extracted to own file | Task 1 |
| BottomNavBar shared component | Task 2 |
| Project.pbxproj updated | Tasks 1, 2, 7 |

**Placeholder scan:** No TBDs, no "implement later", no "similar to Task N". All code blocks are complete.

**Type consistency:**
- `BottomNavTab` defined in Task 2, used in Tasks 3, 5, 6 ✓
- `BottomNavBar(activeTab:onMyBlogs:onCamera:onMyPlaces:)` defined in Task 2, used in Tasks 3, 5, 6 ✓
- `SettingsView()` defined in Task 1, referenced in Tasks 5 and 6 with same `.sheet` pattern ✓
- `onShowMyBlogs`, `onShowMyPlaces`, `onShowCamera` callbacks: consistent naming across ContentView → CameraCaptureView, ContentView → MyBlogsProfileView, ContentView → PlacesVisitedStandaloneView ✓
- `CreatedRecapCard`, `LatestEditsMoreHintCard`: moved from LandingView.swift to MyBlogsProfileView.swift in Task 5 ✓
