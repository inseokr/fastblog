//
//  AppChromeMetrics.swift
//  fastblog
//
//  Shared corner helpers for the app chrome. These pass through to standard SwiftUI radii
//  (no dynamic scaling or device-specific metrics).
//

import SwiftUI

extension RoundedRectangle {
    init(appChromeBaseRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadius: appChromeBaseRadius, style: style)
    }
}

extension View {
    func appChromeCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Shared layout for home tabs (My Blogs, Camera, My Places).
enum HomeChromeMetrics {
    /// Navigation-bar gear size — matches UIKit bar-button symbol scale.
    static let settingsIconPointSize: CGFloat = 22
    /// Minimum tappable area in the navigation bar.
    static let settingsTapSide: CGFloat = 44
    /// Tab row below the hairline in `BottomNavBar`.
    static let bottomNavBarRowHeight: CGFloat = 66
    /// Extra lift above the home-indicator band (matches legacy landing menu spacing).
    static let bottomNavBarExtraBottomPadding: CGFloat = 12
    /// Hairline + tab row + extra bottom padding — inset content height (home indicator is additional).
    static var bottomNavBarTotalHeight: CGFloat {
        bottomNavBarRowHeight + 1 + bottomNavBarExtraBottomPadding
    }

    /// My Blogs / My Places floating search field height.
    static let homeSearchBarHeight: CGFloat = 56
    /// Map action above the search field.
    static let homeMapActionSize: CGFloat = 52
    static let homeSearchChromeMapGap: CGFloat = 8
    static let homeSearchBarOuterBottomPadding: CGFloat = 12
    /// Horizontal inset for map + search (My Places uses 20).
    static let homeChromeHorizontalPadding: CGFloat = 20
    /// Map + search stack only (`ContentView` owns the tab bar below this).
    static var homeTabFloatingSearchChromeHeight: CGFloat {
        homeMapActionSize + homeSearchChromeMapGap + homeSearchBarHeight + homeSearchBarOuterBottomPadding
    }

    /// Camera shutter + zoom strip + Photo/Vibe/Reel picker stack (excludes home-indicator safe area).
    static func cameraCaptureControlsBottomInset(isCompactHeight: Bool) -> CGFloat {
        // mode picker + spacing + shutter row + spacing + zoom preset bar
        isCompactHeight ? 180 : 194
    }

    /// How long "moment saved" / "added to …" camera toasts stay visible before auto-dismiss.
    static let momentCaptureToastAutoDismissSeconds: TimeInterval = 3

    /// Bottom padding for camera "moment added" toasts — clears gallery, shutter, zoom, and mode picker.
    static func cameraToastBottomPadding(isCompactHeight: Bool) -> CGFloat {
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .safeAreaInsets.bottom ?? 34
        return cameraCaptureControlsBottomInset(isCompactHeight: isCompactHeight)
            + max(safeBottom, 8)
            + 16
    }

    /// Post-capture preview (Save moment) — toast sits above the caption chrome + Save dock.
    static func cameraPreviewToastBottomPadding(safeBottom: CGFloat) -> CGFloat {
        max(safeBottom, 8) + 6 + 44 + 10 + 132 + 16
    }

    /// Bottom search field typography (My Blogs + My Places).
    static let homeSearchFieldFont: Font = .body
    static let homeSearchPlaceholderColor = Color.white.opacity(0.7)
}

// MARK: - My Blogs / My Places bottom search + map (shared sizing)

/// Blue map capsule above the search field — same 52×52 on My Blogs and My Places.
struct HomeTabMapFloatingButton: View {
    let action: () -> Void

    /// Matches `.title2` (22pt) — fixed so map glyph scale is identical across home tabs.
    private static let mapSymbolPointSize: CGFloat = 22

    var body: some View {
        Button(action: action) {
            Image(systemName: "map.fill")
                .font(.system(size: Self.mapSymbolPointSize))
                .foregroundColor(.white)
                .frame(width: HomeChromeMetrics.homeMapActionSize, height: HomeChromeMetrics.homeMapActionSize)
                .background(Color.blue)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Shared search row for My Blogs / My Places — subheadline text + white field styling.
struct HomeTabSearchFieldRow<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(HomeChromeMetrics.homeSearchFieldFont)
                .foregroundStyle(HomeChromeMetrics.homeSearchPlaceholderColor)
            ZStack(alignment: .leading) {
                // Overlay placeholder — UITextField `prompt:` auto-shrinks long strings but not short ones,
                // so "Search city or blog title" looked larger than "Search place, city, or country".
                if text.isEmpty {
                    Text(placeholder)
                        .font(HomeChromeMetrics.homeSearchFieldFont)
                        .foregroundStyle(HomeChromeMetrics.homeSearchPlaceholderColor)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .font(HomeChromeMetrics.homeSearchFieldFont)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .focused(focus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

/// Search field chrome (56pt tall, 12pt corner radius) — content supplied by each tab.
struct HomeTabSearchBarContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: HomeChromeMetrics.homeSearchBarHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            .padding(.horizontal, HomeChromeMetrics.homeChromeHorizontalPadding)
            .padding(.bottom, HomeChromeMetrics.homeSearchBarOuterBottomPadding)
    }
}

/// Map row + search bar inset above the home tab bar.
struct HomeTabFloatingSearchChrome<SearchContent: View>: View {
    let onMapTap: () -> Void
    @ViewBuilder let searchContent: () -> SearchContent

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HomeTabMapFloatingButton(action: onMapTap)
                    .padding(.trailing, HomeChromeMetrics.homeChromeHorizontalPadding)
                    .padding(.bottom, HomeChromeMetrics.homeSearchChromeMapGap)
            }
            HomeTabSearchBarContainer(content: searchContent)
        }
        .allowsHitTesting(true)
    }
}

extension View {
    /// Pins map + search above the home tab bar; tab content scrolls clear of this band.
    @ViewBuilder
    func homeTabFloatingSearchInset<Chrome: View>(@ViewBuilder chrome: () -> Chrome) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            chrome()
        }
    }

    /// Persistent home bottom tab bar — single instance in `ContentView`, not per-tab overlays.
    @ViewBuilder
    func homeBottomNavigationBar(
        isVisible: Bool,
        activeTab: BottomNavTab,
        onSelect: @escaping (BottomNavTab) -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isVisible {
                BottomNavBar(
                    activeTab: activeTab,
                    onMyBlogs: { onSelect(.myBlogs) },
                    onCamera: { onSelect(.camera) },
                    onMyPlaces: { onSelect(.myPlaces) }
                )
            }
        }
    }

    /// Leading settings gear for home tabs — same placement in the navigation bar on every tab.
    @ViewBuilder
    func homeSettingsToolbar(onShowSettings: (() -> Void)?) -> some View {
        if let onShowSettings {
            toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeSettingsGearButton(action: onShowSettings)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            self
        }
    }
}

/// Named shapes for sheets and chrome (bottom pull-ups, etc.).
enum AppChromeShapes {
    /// Top corners rounded, bottom square — typical bottom sheet surface.
    static func pullUpTopSurface(topBase: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: topBase,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: topBase
            ),
            style: .continuous
        )
    }
}

// MARK: - Recap editor toolbar Save

/// Trailing navigation **Save** for recap editor sheets (blog title, change cover, etc.): blue text, consistent padding, no fill.
struct RecapEditorToolbarSaveLabel: View {
    var body: some View {
        Text("Save")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .fixedSize()
    }
}
