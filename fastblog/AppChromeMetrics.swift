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
    static let bottomNavBarRowHeight: CGFloat = 62
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
    /// Map + search stack only (`ContentView` owns the tab bar below this).
    static var homeTabFloatingSearchChromeHeight: CGFloat {
        homeMapActionSize + homeSearchChromeMapGap + homeSearchBarHeight + homeSearchBarOuterBottomPadding
    }

    /// Slightly tighter chrome on short screens (SE, mini) so search + map stay above the tab bar.
    static func homeTabFloatingSearchChromeHeight(isCompactHeight: Bool) -> CGFloat {
        if isCompactHeight {
            let map = CGFloat(44)
            let search = CGFloat(48)
            return map + homeSearchChromeMapGap + search + homeSearchBarOuterBottomPadding
        }
        return homeTabFloatingSearchChromeHeight
    }

    static func homeSearchBarHeight(isCompactHeight: Bool) -> CGFloat {
        isCompactHeight ? 48 : homeSearchBarHeight
    }

    static func homeMapActionSize(isCompactHeight: Bool) -> CGFloat {
        isCompactHeight ? 44 : homeMapActionSize
    }

    /// Camera shutter + Photo/Vibe/Reel picker stack (toast sits above this).
    static func cameraCaptureControlsBottomInset(isCompactHeight: Bool) -> CGFloat {
        isCompactHeight ? 138 : 156
    }
}

extension View {
    /// Map + search pinned above the home tab bar; scroll content avoids this band automatically.
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
