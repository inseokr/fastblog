//
//  BlogMenuIndicatorBadge.swift
//  Capper
//

import SwiftUI

/// Small accent badge for My Blogs list rows and country cards.
struct BlogMenuIndicatorBadge: View {
    let kind: BlogMenuIndicatorStore.Kind

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    private var label: String {
        switch kind {
        case .newBlog: return "New"
        case .newMoments: return "New moments"
        }
    }

    private var accentColor: Color {
        switch kind {
        case .newBlog: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .newMoments: return Color(red: 1.0, green: 0.45, blue: 0.25)
        }
    }
}

/// Dot badge for the bottom nav My Blogs icon.
struct BlogMenuNavDotBadge: View {
    var body: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.45, blue: 0.25))
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: Color(red: 1.0, green: 0.45, blue: 0.25).opacity(0.8), radius: 3)
    }
}
