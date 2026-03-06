                                                    //
//  LandingView.swift
//  Capper
//

import Combine
import SwiftUI

struct LandingView: View {
    @Binding var showTrips: Bool
    @Binding var showProfile: Bool
    @Binding var showSeeAll: Bool
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    /// Passed back to ContentView so RecapBlogPageView opens at the right day.
    @ObservedObject var tripsViewModel: TripsViewModel
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var splashManager: SplashStateManager

    // Circle zoom-reveal: starts at 0, springs to full size as logo lands
    @State private var circlesScale: CGFloat = 0.001
    // ScanIcon hidden while the animated splash logo overlay is on top
    @State private var showScanIcon: Bool = false

    @State private var showSettings = false
    @State private var showAuth = false
    /// True while we're waiting for a scan to finish before navigating to Trips.
    @State private var pendingNavigateAfterScan = false
    /// CTA text cycles every 5 seconds: "Tap to Blog" ↔ "Create A Blog Today"
    @State private var ctaIsAlternate = false
    @State private var ctaOpacity: Double = 1
    /// Fade-in opacity for the CTA label on first launch. Starts hidden, fades in after the button appears.
    @State private var ctaTextOpacity: Double = 0

    // New-moments popup (on-the-go feature)
    @State private var showNewMomentsAlert = false
    @State private var newMomentsAlertBlogTitle = ""
    @State private var newMomentsAlertBlogId: UUID? = nil
    @State private var newMomentsAlertDayIndex: Int? = nil

    /// Per-user profile photo — loaded from authService on appear/user-change.
    @State private var avatarImageData: Data?

    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)
    private let ctaInterval: TimeInterval = 5

    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()

            // EXACT CENTER CONTENT
            scanCTA

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
                    // Text("Bloggo")
                    //     .font(.system(size: 34))
                    //     .fontWeight(.bold)
                    //     .foregroundColor(.white)
                    Spacer()
                    Button {
                        if authService.isSignedIn {
                            showProfile = true
                        } else {
                            showAuth = true
                        }
                    } label: {
                        if let user = authService.currentUser {
                            // Signed-in avatar
                            if let data = avatarImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 32, height: 32)
                                    Text(user.initials)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                Spacer()
                
                recentRecapsSection
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

            // Scanning overlay — fades in on top of landing while scan runs
            if tripsViewModel.scanState != .idle {
                LoadingScanView(
                    message: tripsViewModel.loadingMessage,
                    progress: tripsViewModel.defaultScanProgress > 0 ? tripsViewModel.defaultScanProgress : nil
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture()
                .onEnded { value in
                    // Detect swipe left
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        if authService.isSignedIn {
                            showProfile = true
                        } else {
                            showAuth = true
                        }
                    }
                    // Detect swipe up (negative height translation)
                    if value.translation.height < -50 && abs(value.translation.height) > abs(value.translation.width) {
                        showSeeAll = true
                    }
                }
        )
        .onReceive(Timer.publish(every: ctaInterval, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.5)) { ctaOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                ctaIsAlternate.toggle()
                withAnimation(.easeInOut(duration: 0.5)) { ctaOpacity = 1 }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onProfileTapped: {
                showProfile = true
            })
            .environmentObject(authService)
        }
        .alert(
            "New moments added to \"\(newMomentsAlertBlogTitle)\"",
            isPresented: $showNewMomentsAlert
        ) {
            Button("View") {
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
        .onAppear {
            AppAnalytics.shared.trackEvent(name: "app_opened")
            avatarImageData = authService.profileImageData
            // If a scan is already running (e.g. from onboarding), track it for navigation
            if tripsViewModel.scanState != .idle {
                pendingNavigateAfterScan = true
            }
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
        // Navigate to TripsView once scanning finishes
        .onChange(of: tripsViewModel.scanState) { _, newState in
            if newState == .idle && pendingNavigateAfterScan {
                pendingNavigateAfterScan = false
                showTrips = true
            }
        }
    }

    /// Success notification card: icon, title, "Tap to view", optional dismiss. Auto-dismisses after 6s; tap opens latest blog.
    private var recapCreatedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.7, blue: 1), Color(red: 0.3, green: 0.5, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Your recap blog is ready!")
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
            // Check for on-the-go new moments first — only when the user already has a created blog.
            if OnTheGoTripStore.hasNewMoments,
               let blogId = OnTheGoTripStore.activeBlogId,
               let title = OnTheGoTripStore.activeBlogTitle,
               createdRecapStore.visibleRecents.contains(where: { $0.sourceTripId == blogId }) {
                newMomentsAlertBlogId = blogId
                newMomentsAlertBlogTitle = title
                newMomentsAlertDayIndex = OnTheGoTripStore.newMomentsDayIndex
                showNewMomentsAlert = true
            } else if tripsViewModel.tripDrafts.isEmpty {
                // Start scan — navigation will happen when scan finishes (via onChange below)
                tripsViewModel.startDefaultScan()
                pendingNavigateAfterScan = true
            } else {
                showTrips = true
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
                
                // Both lines in same spot so they stay centered when cross-fading
                ZStack {
                    Text("Tap to Blog")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity((ctaIsAlternate ? 0 : ctaOpacity) * ctaTextOpacity)
                    Text("Create A Blog Today")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity((ctaIsAlternate ? ctaOpacity : 0) * ctaTextOpacity)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.5), value: ctaIsAlternate)
                .animation(.easeInOut(duration: 0.5), value: ctaOpacity)
                .offset(y: -156)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentRecapsSection: some View {
        if !createdRecapStore.displayRecents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showSeeAll = true
                } label: {
                    HStack {
                        Text("My Blogs")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("See all")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            .padding(.bottom, 28)
            .background(Color.black.opacity(0.3))
            // Use simultaneousGesture so it doesn't block the inner horizontal ScrollView
            .simultaneousGesture(
                DragGesture()
                    .onEnded { value in
                        // Detect a swipe up: negative height translation
                        // Also check that it's mostly vertical to prevent accidental triggers while horizontal scrolling
                        if value.translation.height < -40 && abs(value.translation.height) > abs(value.translation.width) {
                            showSeeAll = true
                        }
                    }
            )
        }
    }
}

struct CreatedRecapCard: View {
    let recap: CreatedRecapBlog
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    private static let lastEditedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.doesRelativeDateFormatting = true
        return f
    }()

    @State private var showRemoveCloudPopup = false

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
                } else {
                    if createdRecapStore.isBlogInCloud(blogId: recap.sourceTripId) {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.green))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showRemoveCloudPopup = true
                            }
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(4)
                            .background(Circle().fill(Color.white))
                    }
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
        .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup) {
            Button("Yes", role: .destructive) {
                createdRecapStore.removeFromCloud(blogId: recap.sourceTripId)
            }
            Button("No", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove this blog from the cloud?")
        }
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
    @State private var showNeighborhoodSheet = false
    @State private var showAuth = false
    @State private var showDeleteAccountAlert = false
    @State private var showAdminDashboard = false
    #if DEBUG
    @AppStorage("capper.tripClustering.debugLogging") private var tripClusteringDebug = false
    #endif

    var onProfileTapped: (() -> Void)? = nil

    // Per-user profile photo — loaded from authService on appear.
    @State private var customProfileImageData: Data?

    // Cloud storage usage — fetched when Settings is shown and user is signed in.
    @State private var cloudStorageUsage: APIManager.CloudStorageUsageItem?
    @State private var cloudStorageLoading = false
    @State private var cloudStorageError: String?

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section {
                    if let user = authService.currentUser {
                        // Signed-in row
                        Button {
                            dismiss()
                            onProfileTapped?()
                        } label: {
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
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

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
                    Button {
                        showNeighborhoodSheet = true
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
                } header: {
                    Text("My home")
                } footer: {
                    Text("Used to exclude nearby photos from trip results. Change this to update which area counts as \"home.\"")
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
                }
            }
            .sheet(isPresented: $showNeighborhoodSheet) {
                NeighborhoodIntroView(onDismiss: {
                    showNeighborhoodSheet = false
                })
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
            }
            .onChange(of: authService.currentUser?.id) { _, _ in
                customProfileImageData = authService.profileImageData
                loadCloudStorageIfNeeded()
            }
        }
    }

    private func loadCloudStorageIfNeeded() {
        guard authService.isSignedIn else {
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
    
    @State private var showRemoveCloudPopup = false
    @State private var blogToRemove: CreatedRecapBlog?

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
                                } else {
                                    if createdRecapStore.isBlogInCloud(blogId: recap.sourceTripId) {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Circle().fill(Color.green))
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                blogToRemove = recap
                                                showRemoveCloudPopup = true
                                            }
                                    } else {
                                        Image(systemName: "icloud.and.arrow.up")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .padding(4)
                                            .background(Circle().fill(Color.white))
                                    }
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
            .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup, presenting: blogToRemove) { blog in
                Button("Yes", role: .destructive) {
                    createdRecapStore.removeFromCloud(blogId: blog.sourceTripId)
                }
                Button("No", role: .cancel) {
                    blogToRemove = nil
                }
            } message: { blog in
                Text("Are you sure you want to remove this blog from the cloud?")
            }
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

#Preview {
    NavigationStack {
        LandingView(
            showTrips: .constant(false),
            showProfile: .constant(false),
            showSeeAll: .constant(false),
            selectedCreatedRecap: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SplashStateManager())
    }
}
