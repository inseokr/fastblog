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
}

extension View {
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
