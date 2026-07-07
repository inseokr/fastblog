//
//  LandingView.swift
//  Capper
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LandingView: View {
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @ObservedObject var tripsViewModel: TripsViewModel
    var onTapToBlog: (() -> Void)? = nil
    var onOpenCamera: () -> Void
    var onShowSettings: () -> Void
    var onReplayOnboarding: (() -> Void)? = nil
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var splashManager: SplashStateManager

    @State private var circlesScale: CGFloat = 0.001
    @State private var showScanIcon: Bool = false
    @State private var ctaTextOpacity: Double = 0
    @State private var showAlternateText = false
    private let textCycleTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    @StateObject private var photoAuth = PhotosAuthorizationManager()

    @State private var backgroundPhase = HomeBackdropPhase.current()
    private let backgroundRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let latestEditsPageSize = 5
    @State private var latestEditsVisibleCount = 5
    @State private var isLoadingLatestEditsBatch = false

    /// Used to keep the "Rewind Your Trips in Seconds" alternate CTA off smaller iPhones.
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
        22 + 12 + CreatedRecapCard.layoutHeight + 16 + 8
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
            HomeBackdropView(phase: backgroundPhase)
                .ignoresSafeArea()

            // Scan CTA: vertically centered on screen (above footer chrome).
            scanCTA
                .offset(y: scanCTAOffsetY)

            // Top bar + bottom chrome (Latest Edits, menu).
            VStack(spacing: 0) {
                HStack {
                    HomeSettingsGearButton(
                        tint: backgroundPhase.iconColor,
                        action: { onShowSettings() },
                        onLongPress: onReplayOnboarding
                    )
                    Spacer()
                    Button {
                        onOpenCamera()
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(backgroundPhase.iconColor)
                            .frame(width: 44, height: 44)
                            .background(backgroundPhase.controlFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Camera")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Spacer()

                recentRecapsSection
            }

        }
        .animation(.easeInOut(duration: 0.4), value: tripsViewModel.scanState != .idle)
        .preferredColorScheme(backgroundPhase.preferredColorScheme)
        .onReceive(backgroundRefreshTimer) { date in
            let nextPhase = HomeBackdropPhase(date: date)
            guard nextPhase != backgroundPhase else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                backgroundPhase = nextPhase
            }
        }
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
        .onAppear {
            AppAnalytics.track(.appOpen)
            if splashManager.phase == .done {
                circlesScale = 1.0
                showScanIcon = true
                ctaTextOpacity = 1
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                        circlesScale = 1.0
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    showScanIcon = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeIn(duration: 0.55)) {
                            ctaTextOpacity = 1
                        }
                    }
                }
            }
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
                    .foregroundColor(backgroundPhase.primaryText)
                Text("Available in your Profile")
                    .font(.caption)
                    .foregroundColor(backgroundPhase.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createdRecapStore.dismissRecapCreatedBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(backgroundPhase.tertiaryText)
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
                        .stroke(backgroundPhase.borderColor, lineWidth: 1)
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
            }
        } label: {
            ZStack {
                ZStack {
                    Circle()
                        .fill(backgroundPhase.scanCircleFill)
                        .frame(width: 220, height: 220)
                    
                    ScanningAnimationView(
                        ringCount: 4,
                        ringSpacing: 28,
                        pulseDuration: 1.8,
                        showIcon: showScanIcon,
                        systemIconName: "gobackward"
                    )
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .strokeBorder(backgroundPhase.borderColor, lineWidth: 1)
                        .frame(width: 220, height: 220)
                }
                .clipShape(Circle())
                .scaleEffect(circlesScale)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.72).delay(0.35),
                    value: circlesScale
                )
                
                if photoAuth.status == .limited {
                    Text(showAlternateSecondsCTA ? "Rewind Your Trips in Seconds" : "Select Photos to Rewind")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(backgroundPhase.primaryText)
                        .opacity(ctaTextOpacity)
                        .frame(maxWidth: .infinity)
                        .offset(y: -156)
                } else {
                    Text(showAlternateSecondsCTA ? "Rewind Your Trips in Seconds" : "Tap to Rewind")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(backgroundPhase.primaryText)
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
                    .foregroundColor(backgroundPhase.primaryText)
                    .padding(.horizontal, 20)
                    .frame(height: 22, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleLatestEdits) { recap in
                            LatestEditsRecapCardButton(recap: recap, phase: backgroundPhase) {
                                selectedCreatedRecap = recap
                            }
                        }

                        if hasMoreLatestEdits {
                            LatestEditsMoreHintCard(phase: backgroundPhase) {
                                loadMoreLatestEdits()
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(height: CreatedRecapCard.layoutHeight)
                .overlay(alignment: .trailing) {
                    if hasMoreLatestEdits {
                        LinearGradient(
                            colors: backgroundPhase.trailingFadeColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 36)
                        .padding(.bottom, 8)
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

}

enum HomeBackdropPhase: Equatable {
    case day
    case night

    init(date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        self = (6..<18).contains(hour) ? .day : .night
    }

    static func current() -> HomeBackdropPhase {
        HomeBackdropPhase(date: Date())
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .day: return .light
        case .night: return .dark
        }
    }

    var primaryText: Color {
        switch self {
        case .day: return Color(white: 0.12)
        case .night: return .white
        }
    }

    var secondaryText: Color {
        switch self {
        case .day: return Color(white: 0.34)
        case .night: return .white.opacity(0.72)
        }
    }

    var tertiaryText: Color {
        switch self {
        case .day: return Color(white: 0.50)
        case .night: return .white.opacity(0.62)
        }
    }

    var iconColor: Color {
        primaryText
    }

    var cardFill: Color {
        switch self {
        case .day: return .white.opacity(0.58)
        case .night: return .white.opacity(0.10)
        }
    }

    var subtleFill: Color {
        switch self {
        case .day: return Color(red: 0.75, green: 0.61, blue: 0.42).opacity(0.13)
        case .night: return .white.opacity(0.08)
        }
    }

    var controlFill: Color {
        switch self {
        case .day: return Color(red: 0.96, green: 0.90, blue: 0.79).opacity(0.74)
        case .night: return .white.opacity(0.14)
        }
    }

    var scanCircleFill: Color {
        switch self {
        case .day: return Color(white: 0.86).opacity(0.78)
        case .night: return .white.opacity(0.12)
        }
    }

    var borderColor: Color {
        switch self {
        case .day: return Color(red: 0.45, green: 0.36, blue: 0.23).opacity(0.16)
        case .night: return .white.opacity(0.18)
        }
    }

    var hairlineColor: Color {
        switch self {
        case .day: return Color(red: 0.45, green: 0.36, blue: 0.23).opacity(0.14)
        case .night: return .white.opacity(0.12)
        }
    }

    var trailingFadeColors: [Color] {
        switch self {
        case .day:
            return [
                Color(red: 0.98, green: 0.96, blue: 0.91).opacity(0),
                Color(red: 0.98, green: 0.96, blue: 0.91).opacity(0.76),
                Color(red: 0.98, green: 0.96, blue: 0.91)
            ]
        case .night:
            return [
                Color(red: 0.04, green: 0.06, blue: 0.16).opacity(0),
                Color(red: 0.04, green: 0.06, blue: 0.16).opacity(0.78),
                Color(red: 0.04, green: 0.06, blue: 0.16)
            ]
        }
    }

    var bottomNavBackground: Color {
        switch self {
        case .day: return Color(red: 0.98, green: 0.96, blue: 0.91)
        case .night: return Color(red: 0.04, green: 0.06, blue: 0.16)
        }
    }
}

struct HomeBackdropView: View {
    let phase: HomeBackdropPhase

    private let stars: [HomeBackdropStar] = [
        .init(x: 0.10, y: 0.12, size: 2.2, opacity: 0.80),
        .init(x: 0.22, y: 0.08, size: 1.4, opacity: 0.58),
        .init(x: 0.34, y: 0.18, size: 2.8, opacity: 0.74),
        .init(x: 0.52, y: 0.10, size: 1.8, opacity: 0.62),
        .init(x: 0.69, y: 0.15, size: 2.4, opacity: 0.82),
        .init(x: 0.84, y: 0.09, size: 1.5, opacity: 0.66),
        .init(x: 0.92, y: 0.22, size: 2.0, opacity: 0.56),
        .init(x: 0.15, y: 0.29, size: 1.7, opacity: 0.52),
        .init(x: 0.43, y: 0.31, size: 2.1, opacity: 0.64),
        .init(x: 0.61, y: 0.27, size: 1.3, opacity: 0.58),
        .init(x: 0.77, y: 0.34, size: 2.5, opacity: 0.70),
        .init(x: 0.28, y: 0.43, size: 1.4, opacity: 0.50),
        .init(x: 0.55, y: 0.46, size: 1.9, opacity: 0.54),
        .init(x: 0.88, y: 0.48, size: 1.5, opacity: 0.60)
    ]

    var body: some View {
        ZStack {
            switch phase {
            case .day:
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.92),
                        Color(red: 0.96, green: 0.93, blue: 0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .night:
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.05, blue: 0.15),
                        Color(red: 0.06, green: 0.08, blue: 0.20),
                        Color(red: 0.02, green: 0.03, blue: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                GeometryReader { proxy in
                    ForEach(stars) { star in
                        Circle()
                            .fill(Color.white.opacity(star.opacity))
                            .frame(width: star.size, height: star.size)
                            .position(
                                x: proxy.size.width * star.x,
                                y: proxy.size.height * star.y
                            )
                    }
                }
            }
        }
    }
}

private struct HomeBackdropStar: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}

private struct LatestEditsMoreHintCard: View {
    let phase: HomeBackdropPhase
    var onLoadMore: () -> Void

    var body: some View {
        Button(action: onLoadMore) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(phase.subtleFill)
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(phase.secondaryText)
                }

                Text("More")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(phase.secondaryText)
            }
            .frame(width: 72, height: 100)
            .padding(.vertical, 10)
            .background(phase.subtleFill)
            .overlay {
                RoundedRectangle(appChromeBaseRadius: 12)
                    .strokeBorder(
                        phase.borderColor,
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
    var menuIndicatorKind: BlogMenuIndicatorStore.Kind? = nil
    var phase: HomeBackdropPhase = .night

    private static let coverSide: CGFloat = 76
    private static let cardWidth: CGFloat = 260
    private static let cardPadding: CGFloat = 10
    private static let badgeRowHeight: CGFloat = 18
    /// Always two lines max — fixed height keeps Latest Edits row even.
    private static let titleRowHeight: CGFloat = 36
    private static let dateRangeRowHeight: CGFloat = 15
    private static let lastEditedRowHeight: CGFloat = 13
    private static let textRowSpacing: CGFloat = 3
    private static var textColumnHeight: CGFloat {
        badgeRowHeight
            + textRowSpacing + titleRowHeight
            + textRowSpacing + dateRangeRowHeight
            + textRowSpacing + lastEditedRowHeight
    }
    private static var innerContentHeight: CGFloat {
        max(coverSide, textColumnHeight)
    }

    /// Total card height for horizontal Latest Edits scroller (padding applied once).
    static var layoutHeight: CGFloat {
        innerContentHeight + cardPadding * 2
    }

    private static let lastEditedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                    .frame(width: Self.coverSide, height: Self.coverSide)
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
            .overlay(alignment: .topTrailing) {
                if menuIndicatorKind != nil {
                    BlogMenuNavDotBadge()
                        .padding(2)
                }
            }

            VStack(alignment: .leading, spacing: Self.textRowSpacing) {
                ZStack(alignment: .leading) {
                    if let menuIndicatorKind {
                        BlogMenuIndicatorBadge(kind: menuIndicatorKind)
                    }
                }
                .frame(height: Self.badgeRowHeight, alignment: .leading)

                Text(recap.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(phase.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(height: Self.titleRowHeight, alignment: .topLeading)

                Text(dateRangeLine)
                    .font(.caption)
                    .foregroundColor(phase.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: Self.dateRangeRowHeight, alignment: .leading)

                Text(lastEditedText)
                    .font(.caption2)
                    .foregroundColor(phase.tertiaryText)
                    .lineLimit(1)
                    .frame(height: Self.lastEditedRowHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: Self.textColumnHeight, maxHeight: Self.textColumnHeight, alignment: .topLeading)
        }
        .frame(width: Self.cardWidth - Self.cardPadding * 2, height: Self.innerContentHeight, alignment: .topLeading)
        .padding(Self.cardPadding)
        .frame(width: Self.cardWidth, height: Self.layoutHeight, alignment: .topLeading)
        .background(phase.cardFill)
        .overlay(
            RoundedRectangle(appChromeBaseRadius: 12)
                .stroke(phase.borderColor, lineWidth: 1)
        )
        .appChromeCornerRadius(12)
    }

    private var dateRangeLine: String {
        let trimmed = recap.tripDateRangeText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? " " : trimmed
    }

    private var lastEditedText: String {
        let date = recap.lastEditedAt ?? recap.createdAt
        return "Edited \(Self.lastEditedFormatter.string(from: date))"
    }
}

/// Latest Edits card — tappable inside a horizontal ScrollView.
struct LatestEditsRecapCardButton: View {
    let recap: CreatedRecapBlog
    var menuIndicatorKind: BlogMenuIndicatorStore.Kind? = nil
    var phase: HomeBackdropPhase = .night
    let action: () -> Void

    var body: some View {
        CreatedRecapCard(recap: recap, menuIndicatorKind: menuIndicatorKind, phase: phase)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: action)
    }
}

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

    /// Short line under the onboarding-style headline.
    var subtitle: String {
        switch self {
        case .blogBackup: return "Export, back up, and import your saved blogs on a new device."
        case .myHome: return "How distance from home works for trip scanning."
        }
    }
}

/// Shared card chrome for Settings help sheets (Blog backup, My home).
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

/// Structured help for Blog backup: same layout as My home (logo + cards).
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

/// Structured help for “My home”: cards and logo instead of a wall of text.
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

    /// Space so the last cards can scroll above the floating CTA + gradient.
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
                    // Keep a comfortable gap below the sheet grabber/drag area
                    // so the title does not feel cramped in medium detent.
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

    /// Gradient scrim + primary action so scroll content can pass underneath (onboarding-style).
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

/// Settings sheet from the home page (gear icon). Includes neighborhood selection.
private struct LandingSettingsView: View {
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

    // Per-user profile photo — loaded from authService on appear.
    @State private var customProfileImageData: Data?

    // Cloud storage usage — fetched when Settings is shown and user is signed in.
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
                        Text("You can save and export unlimited blogs.")
                    } else {
                        Text("Create an account to save and download unlimited blogs.")
                    }
                }

                // Permissions
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
                                Task {
                                    await authService.deleteAccount()
                                }
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
                    Button("Done") {
                        dismiss()
                    }
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

    /// Copies the picked backup into a temp file, then shows the library-vs-ZIP choice. Security-scoped access ends here.
    @MainActor
    private func stageImportBackupAndPrompt(from pickedURL: URL) {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { pickedURL.stopAccessingSecurityScopedResource() }
        }
        do {
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bloggo-import-staging-\(UUID().uuidString).zip")
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

    /// Imports from a temp ZIP already copied from the document picker. Removes the staged file when finished.
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

#Preview {
    NavigationStack {
        LandingView(
            selectedCreatedRecap: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            onOpenCamera: {},
            onShowSettings: {}
        )
        .environmentObject(CreatedRecapBlogStore.shared)
        .environmentObject(SplashStateManager())
    }
}
