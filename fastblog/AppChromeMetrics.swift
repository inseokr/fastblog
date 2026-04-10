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
