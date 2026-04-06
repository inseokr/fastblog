//
//  LandingView.swift
//  Capper
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LandingView: View {
    @Binding var showTrips: Bool
    @Binding var showProfile: Bool
    @Binding var showSeeAll: Bool
    @Binding var showPlacesVisited: Bool
    @Binding var showCameraFromHome: Bool
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @Binding var postCameraToastMessage: String?
    /// Passed back to ContentView so RecapBlogPageView opens at the right day.
    @ObservedObject var tripsViewModel: TripsViewModel
    /// When provided, "Tap to Blog" calls this instead of setting showTrips; parent shows Trips when scan is ready.
    var onTapToBlog: (() -> Void)? = nil
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var splashManager: SplashStateManager

    // Circle zoom-reveal: starts at 0, springs to full size as logo lands
    @State private var circlesScale: CGFloat = 0.001
    // ScanIcon hidden while the animated splash logo overlay is on top
    @State private var showScanIcon: Bool = false

    @State private var showSettings = false
    @State private var showAuth = false
    @State private var showNotifications = false

    /// Fade-in opacity for the CTA label on first launch. Starts hidden, fades in after the button appears.
    @State private var ctaTextOpacity: Double = 0

    /// Cycles between "Tap to Blog" and "Blog Your Trips in Seconds" every 7 seconds.
    @State private var showAlternateText = false
    private let textCycleTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    // New-moments popup (on-the-go feature)
    @State private var showNewMomentsAlert = false
    @State private var newMomentsAlertBlogTitle = ""
    @State private var newMomentsAlertBlogId: UUID? = nil
    @State private var newMomentsAlertDayIndex: Int? = nil

    /// Per-user profile photo — loaded from authService on appear/user-change.
    @State private var avatarImageData: Data?

    @StateObject private var photoAuth = PhotosAuthorizationManager()

    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

    /// Used to keep the "Blog Your Trips in Seconds" alternate CTA off smaller iPhones.
    /// iPhone Pro Max models have wider point bounds than non-Max models.
    private var isIPhoneMax: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        return UIScreen.main.bounds.width >= 420
    }

    private var showAlternateSecondsCTA: Bool {
        showAlternateText && isIPhoneMax
    }

    /// Used to keep the centered "Tap to Blog" circle from feeling cramped
    /// against the "Latest Edits" section on smaller (6.1") iPhone heights.
    private var isCompactIPhone61: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        // 6.1" models are non-Max and have shorter point heights than Pro Max (and larger).
        return UIScreen.main.bounds.width < 420 && UIScreen.main.bounds.height < 900
    }

    private var scanCTAOffsetY: CGFloat {
        isCompactIPhone61 ? -18 : 0
    }

    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()

            // EXACT CENTER CONTENT
            scanCTA
                .offset(y: scanCTAOffsetY)

            // Top bar and Footer
            VStack {
                HStack {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 1.5).onEnded { _ in
                            OnboardingStore.hasCompletedOnboarding = false
                        }
                    )
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { showNotifications = true }
                    } label: {
                        Image(systemName: "bell.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                Spacer()

                recentRecapsSection
                bottomMenuBar
            }

            // Auth slide-in from the right
            if showAuth {
                AuthView(onAuthenticated: {
                    showProfile = true
                    showAuth = false
                }, onDismiss: {
                    showAuth = false
                })
                .environmentObject(authService)
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }

            // Notifications slide-in from the right
            if showNotifications {
                NotificationsOverlayView(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) { showNotifications = false }
                })
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }

            // Post-camera toast banner
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
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(15)
            }

        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture()
                .onEnded { value in
                    // Swipe left to open Profile/Auth is disabled.
                    // Swipe up opens in-app Capture (same as the bottom "Capture" control).
                    if value.translation.height < -50 && abs(value.translation.height) > abs(value.translation.width) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showCameraFromHome = true
                        }
                    }
                }
        )
        .sheet(isPresented: $showSettings) {
            SettingsView()
            .environmentObject(authService)
            .environmentObject(photoAuth)
            .environmentObject(createdRecapStore)
        }
        .alert(
            "New moments added to \"\(newMomentsAlertBlogTitle)\"",
            isPresented: $showNewMomentsAlert
        ) {
            Button("View") {
                if let blogId = newMomentsAlertBlogId {
                    createdRecapStore.injectPhotos(
                        tripsViewModel.newlyScannedPhotos,
                        intoSourceTripId: blogId
                    )
                }
                tripsViewModel.clearNewMomentsSignal()
                OnTheGoTripStore.clearNewMoments()
                if let blogId = newMomentsAlertBlogId,
                   let recap = createdRecapStore.displayRecents.first(where: { $0.sourceTripId == blogId }) {
                    selectedCreatedRecap = recap
                }
            }
            Button("Ok", role: .cancel) {
                OnTheGoTripStore.clearNewMoments()
                // Proceed to Trips page so user can keep exploring
                if !tripsViewModel.tripDrafts.isEmpty {
                    showTrips = true
                }
            }
        } message: {
            Text("Your trip has new content since you last looked. Tap View to go to the latest day.")
        }
        .animation(.easeInOut(duration: 0.3), value: showAuth)
        .onReceive(textCycleTimer) { _ in
            guard isIPhoneMax else {
                showAlternateText = false
                ctaTextOpacity = 1
                return
            }
            guard ctaTextOpacity >= 1 else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                ctaTextOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                showAlternateText.toggle()
                withAnimation(.easeIn(duration: 0.25)) {
                    ctaTextOpacity = 1
                }
            }
        }
        .onChange(of: postCameraToastMessage) { _, msg in
            if msg != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        postCameraToastMessage = nil
                    }
                }
            }
        }
        .onAppear {
            AppAnalytics.track(.appOpen)
            avatarImageData = authService.profileImageData
            // If already past splash (e.g. navigating back), show everything immediately
            if splashManager.phase == .done {
                circlesScale = 1.0
                showScanIcon = true
                ctaTextOpacity = 1
            } else {
                // Circles zoom out 0.35s after appear — synced to logo spring landing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                        circlesScale = 1.0
                    }
                }
                // ScanIcon appears once the splash overlay has faded (~0.85s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    showScanIcon = true
                    // Fade the CTA text in shortly after the button appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeIn(duration: 0.55)) {
                            ctaTextOpacity = 1
                        }
                    }
                }
            }
        }
        .onChange(of: authService.currentUser?.id) { _, _ in
            avatarImageData = authService.profileImageData
        }
    }

    /// Success notification card: icon, title, "Tap to view", optional dismiss. Auto-dismisses after 6s; tap opens latest blog.
    private var recapCreatedBanner: some View {
        HStack(spacing: 14) {
            Image("MyBlogsIcon")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.7, blue: 1), Color(red: 0.3, green: 0.5, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your blog is ready")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Available in your Profile")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createdRecapStore.dismissRecapCreatedBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .onTapGesture {
            if let latest = createdRecapStore.displayRecents.first {
                selectedCreatedRecap = latest
            }
            createdRecapStore.dismissRecapCreatedBanner()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                createdRecapStore.dismissRecapCreatedBanner()
            }
        }
    }

    private var scanCTA: some View {
        Button {
            if let onTapToBlog = onTapToBlog {
                onTapToBlog()
            } else {
                tripsViewModel.startDefaultScan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showTrips = true
                }
            }
        } label: {
            ZStack {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 220, height: 220)
                    
                    ScanningAnimationView(ringCount: 4, ringSpacing: 28, pulseDuration: 1.8, showIcon: showScanIcon, iconName: "SplashIcon")
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 220, height: 220)
                }
                .clipShape(Circle())
                .scaleEffect(circlesScale)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.72).delay(0.35),
                    value: circlesScale
                )
                
                if photoAuth.status == .limited {
                    Text(showAlternateSecondsCTA ? "Blog Your Trips in Seconds" : "Select Photos to Blog")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(ctaTextOpacity)
                        .frame(maxWidth: .infinity)
                        .offset(y: -156)
                } else {
                    Text(showAlternateSecondsCTA ? "Blog Your Trips in Seconds" : "Tap to Blog")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(ctaTextOpacity)
                        .frame(maxWidth: .infinity)
                        .offset(y: -156)
                }
            }
        }
        .buttonStyle(.plain)
        // Hide the landing scan button while a trip scan is actively running,
        // so its animation doesn't show behind the Trips loading overlay.
        .opacity(tripsViewModel.scanState == .idle ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: tripsViewModel.scanState == .idle)
    }

    @ViewBuilder
    private var recentRecapsSection: some View {
        if !createdRecapStore.displayRecents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest Edits")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(createdRecapStore.displayRecents) { recap in
                            CreatedRecapCard(recap: recap)
                                .onTapGesture {
                                    selectedCreatedRecap = recap
                                }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .frame(height: 128)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    private var bottomMenuBar: some View {
        HStack {
            Button {
                showSeeAll = true
            } label: {
                VStack(spacing: 4) {
                    Image("MyBlogsIcon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                    Text("My Blogs")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                showCameraFromHome = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                    Text("Capture")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                showPlacesVisited = true
            } label: {
                VStack(spacing: 4) {
                    Image("MyPlacesIcon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                    Text("My Places")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .safeAreaPadding(.bottom, 16)
    }
}

struct CreatedRecapCard: View {
    let recap: CreatedRecapBlog

    private static let lastEditedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if recap.lastEditedAt == nil {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recap.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let range = recap.tripDateRangeText, !range.isEmpty {
                    Text(range)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                Text(lastEditedText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .padding(10)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private var lastEditedText: String {
        let date = recap.lastEditedAt ?? recap.createdAt
        return "Edited \(Self.lastEditedFormatter.string(from: date))"
    }
}

/// Settings sheet from the home page (gear icon). Includes neighborhood selection.
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var photoAuth: PhotosAuthorizationManager
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showNeighborhoodFlow = false
    @State private var showAuth = false
    @State private var showDeleteAccountAlert = false
    @State private var showAdminDashboard = false
    #if DEBUG
    @AppStorage("capper.tripClustering.debugLogging") private var tripClusteringDebug = false
    #endif

    // Per-user profile photo — loaded from authService on appear.
    @State private var customProfileImageData: Data?

    // Cloud storage usage — fetched when Settings is shown and user is signed in.
    @State private var cloudStorageUsage: APIManager.CloudStorageUsageItem?
    @State private var cloudStorageLoading = false
    @State private var cloudStorageError: String?

    @State private var tripExclusionRadius = NeighborhoodStore.tripExclusionRadiusMiles

    @State private var showImportBackupPicker = false
    @State private var isExportingAllBackups = false
    @State private var isImportingBackup = false
    @State private var backupFlowProgress: Double = 0
    @State private var backupAllShareURL: URL?
    @State private var showBackupAllShareSheet = false
    @State private var backupFlowAlertTitle = ""
    @State private var backupFlowAlertMessage = ""
    @State private var showBackupFlowAlert = false
    @AppStorage("bloggo.preferPhotoLibraryWhenImportingBackup") private var preferPhotoLibraryWhenImportingBackup = false

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
                // Travel Stats
                Section {
                    travelStatsRow
                } header: {
                    Text("Travel Stats")
                }

                // Account
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
                        Text("Your recaps sync to the cloud and can be edited on web.")
                    } else {
                        Text("Sign in to back up your recaps, access them on web, and restore Pro.")
                    }
                }

                // Permissions
                Section {
                    PhotoAccessRow()
                } header: {
                    Text("Permissions")
                }

                Section {
                    Toggle(isOn: $preferPhotoLibraryWhenImportingBackup) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Match Photo Library when importing")
                            Text("Uses capture time and location from the backup to link to photos already on this device (e.g. from iCloud). If no match, the copy inside the ZIP is used.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showImportBackupPicker = true
                    } label: {
                        Label("Import blog backup", systemImage: "arrow.down.doc")
                    }
                    .disabled(isImportingBackup)

                    Button {
                        Task { await exportAllBlogsBackupTapped() }
                    } label: {
                        Label("Export all saved blogs", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(isExportingAllBackups || !hasAnyBackupableBlog)
                } header: {
                    Text("Blog backup")
                } footer: {
                    Text("Export includes only blogs you’ve saved from the editor (not draft-only recaps). It packs them into a ZIP with text and JPEG images (compressed, not a full copy of every original camera file). Save that ZIP somewhere outside this phone—such as iCloud Drive, another cloud app, or a computer—if you want to recover after a lost device. Import adds new blogs here. With “Match Photo Library,” the blog references your existing library photos when possible (nothing new is saved to the library). Otherwise imported images are stored inside Bloggo only, not added to your Camera Roll.")
                }

                Section {
                    NavigationLink(
                        destination: NeighborhoodIntroView(onDismiss: {
                            showNeighborhoodFlow = false
                        }),
                        isActive: $showNeighborhoodFlow
                    ) {
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
                        }
                    }

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
                    Text("My home")
                } footer: {
                    if photoAuth.status == .limited {
                        Text("Home sets where nearby photos are measured from. With limited photo access, trip scans use the default distance from home for your neighborhood.")
                    } else {
                        Text("Please adjust it to a smaller value if you want to blog about activities around your neighborhood. Changing this distance only affects your trip list after a full library scan—when you release the slider, Bloggo starts one automatically if it can. If your trips still look wrong afterward, quit the app completely and reopen, then open Trips.")
                    }
                }

                /*
                #if DEBUG
                Section {
                    Toggle("Trip clustering debug logging", isOn: $tripClusteringDebug)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("When on, scan logs why each day merged or split (neighborhood_pass, country_fallback_pass, etc.).")
                }
                #endif
                */

                // Legal at bottom of Settings
                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }
                } header: {
                    Text("Legal")
                }

                if let user = authService.currentUser,
                   AdminAnalyticsDashboardView.isAdminUser(user) {
                    Section {
                        Button {
                            showAdminDashboard = true
                        } label: {
                            HStack {
                                Label("Admin Analytics", systemImage: "chart.bar.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text("Admin")
                    }
                }

                if authService.isSignedIn {
                    Section {
                        Button {
                            showDeleteAccountAlert = true
                        } label: {
                            Label("Delete Account", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await authService.deleteAccount()
                                }
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("This will permanently delete your account and all local data. This action cannot be undone.")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showAdminDashboard) {
                AdminAnalyticsDashboardView()
                    .environmentObject(CreatedRecapBlogStore.shared)
                    .environmentObject(authService)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showAuth) {
                AuthView(onAuthenticated: {
                    showAuth = false
                    dismiss()
                })
                .environmentObject(authService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                    Task { @MainActor in
                        await importBlogBackup(from: url)
                    }
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
    private func importBlogBackup(from url: URL) async {
        isImportingBackup = true
        backupFlowProgress = 0
        defer {
            isImportingBackup = false
            backupFlowProgress = 0
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            if preferPhotoLibraryWhenImportingBackup, !photoAuth.isAuthorized {
                await photoAuth.requestAccess()
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-import-\(UUID().uuidString).zip")
            backupFlowProgress = 0.02
            await Task.yield()
            try FileManager.default.copyItem(at: url, to: dest)
            backupFlowProgress = 0.06
            await Task.yield()
            defer { try? FileManager.default.removeItem(at: dest) }
            let ids = try await BlogBackupService.importFromZip(
                zipURL: dest,
                store: createdRecapStore,
                preferPhotoLibrary: preferPhotoLibraryWhenImportingBackup && photoAuth.isAuthorized,
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
        guard authService.isSignedIn, EntitlementManager.shared.isProActive else {
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

struct AllRecentsSheet: View {
    @ObservedObject var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedRecap: CreatedRecapBlog?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(createdRecapStore.visibleRecents) { recap in
                    Button {
                        selectedRecap = recap
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack(alignment: .bottomLeading) {
                                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if recap.lastEditedAt == nil {
                                    Text("Draft")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                        .padding(3)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recap.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(recap.createdAt, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Recent Recaps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Notifications overlay (slides in from right on home)
private struct NotificationsOverlayView: View {
    var onDismiss: () -> Void
    private let backgroundBlue = Color(red: 5/255, green: 10/255, blue: 48/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("Notifications")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Spacer()
            Text("No Notifications")
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundBlue.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        LandingView(
            showTrips: .constant(false),
            showProfile: .constant(false),
            showSeeAll: .constant(false),
            showPlacesVisited: .constant(false),
            showCameraFromHome: .constant(false),
            selectedCreatedRecap: .constant(nil),
            postCameraToastMessage: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SplashStateManager())
    }
}
