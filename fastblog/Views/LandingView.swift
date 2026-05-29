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
    private let latestEditsPageSize = 5
    @State private var latestEditsVisibleCount = 5
    @State private var isLoadingLatestEditsBatch = false

    /// Used to keep the "Blog Your Trips in Seconds" alternate CTA off smaller iPhones.
    /// iPhone Pro Max models have wider point bounds than non-Max models.
    private var isIPhoneMax: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        return UIScreen.main.bounds.width >= 420
    }

    private var showAlternateSecondsCTA: Bool {
        showAlternateText && isIPhoneMax
    }

    /// Used on 6.1" phones to keep the scan ring clear of Latest Edits below.
    private var isCompactIPhone61: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        // 6.1" models are non-Max and have shorter point heights than Pro Max (and larger).
        return UIScreen.main.bounds.width < 420 && UIScreen.main.bounds.height < 900
    }

    private var scanCTAOffsetY: CGFloat {
        var offset = ScanRingLayoutMetrics.centeredRingCenterYOffsetFromScreenCenter
        if isCompactIPhone61 { offset -= 18 }
        return offset
    }

    /// Stable vertical footprint so loading more rows does not shift the footer stack.
    private var latestEditsSectionHeight: CGFloat {
        22 + 12 + 128 + 16 + 8
    }

    private var allLatestEdits: [CreatedRecapBlog] {
        createdRecapStore.displayRecents
    }

    private var visibleLatestEdits: [CreatedRecapBlog] {
        Array(allLatestEdits.prefix(latestEditsVisibleCount))
    }

    private var hasMoreLatestEdits: Bool {
        allLatestEdits.count > latestEditsVisibleCount
    }

    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()

            // Scan CTA: vertically centered on screen (above footer chrome).
            scanCTA
                .offset(y: scanCTAOffsetY)

            // Top bar + bottom chrome (Latest Edits, menu).
            VStack(spacing: 0) {
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showNotifications = true }
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
            NotificationsOverlayView(onDismiss: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showNotifications = false }
            })
            .offset(x: showNotifications ? 0 : UIScreen.main.bounds.width)
            .opacity(showNotifications ? 1 : 0)
            .allowsHitTesting(showNotifications)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: showNotifications)
            .zIndex(10)

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
                .zIndex(15)
            }

        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .preferredColorScheme(.dark)
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
            RoundedRectangle(appChromeBaseRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(appChromeBaseRadius: 14)
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
        if !allLatestEdits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest Edits")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 22, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleLatestEdits) { recap in
                            CreatedRecapCard(recap: recap)
                                .onTapGesture {
                                    selectedCreatedRecap = recap
                                }
                        }

                        if hasMoreLatestEdits {
                            LatestEditsMoreHintCard {
                                loadMoreLatestEdits()
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .frame(height: 128)
                .clipped()
                .overlay(alignment: .trailing) {
                    if hasMoreLatestEdits {
                        LinearGradient(
                            colors: [
                                landingBackground.opacity(0),
                                landingBackground.opacity(0.75),
                                landingBackground
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 36)
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: latestEditsSectionHeight, alignment: .top)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .animation(nil, value: latestEditsVisibleCount)
            .onChange(of: allLatestEdits.count) { _, newCount in
                latestEditsVisibleCount = min(latestEditsVisibleCount, newCount)
            }
        }
    }

    private func loadMoreLatestEdits() {
        guard hasMoreLatestEdits, !isLoadingLatestEditsBatch else { return }
        isLoadingLatestEditsBatch = true
        latestEditsVisibleCount = min(
            latestEditsVisibleCount + latestEditsPageSize,
            allLatestEdits.count
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isLoadingLatestEditsBatch = false
        }
    }

    private var bottomMenuBar: some View {
        HStack(spacing: 0) {
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

            // Center: icon-sized tap target only — was full-width third of the bar, which overlapped
            // swipe-down-to-dismiss-Capture and edge taps near the home indicator.
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
        // Extra lift so the bar sits a bit farther from the system home / edge gesture band.
        .safeAreaPadding(.bottom, 24)
    }
}

private struct LatestEditsMoreHintCard: View {
    var onLoadMore: () -> Void

    var body: some View {
        Button(action: onLoadMore) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }

                Text("More")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 72, height: 100)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .overlay {
                RoundedRectangle(appChromeBaseRadius: 12)
                    .strokeBorder(
                        Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .appChromeCornerRadius(12)
        }
        .buttonStyle(.plain)
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
            ZStack(alignment: .topLeading) {
                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 10))
                if recap.lastEditedAt == nil {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .appChromeCornerRadius(4)
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
        .appChromeCornerRadius(12)
    }

    private var lastEditedText: String {
        let date = recap.lastEditedAt ?? recap.createdAt
        return "Edited \(Self.lastEditedFormatter.string(from: date))"
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
                            ZStack(alignment: .topLeading) {
                                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
                                if recap.lastEditedAt == nil {
                                    Text("Draft")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .appChromeCornerRadius(4)
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
    private let dismissThreshold: CGFloat = 100

    @GestureState private var dragOffsetX: CGFloat = 0

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
        .offset(x: max(0, dragOffsetX))
        .gesture(
            DragGesture()
                .updating($dragOffsetX) { value, state, _ in
                    if value.translation.width > 0 {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width > dismissThreshold {
                        onDismiss()
                    }
                }
        )
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
