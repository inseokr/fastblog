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

extension BottomNavBar {
    /// Tab row height (divider + icons/labels). Home indicator is added via `safeAreaPadding(.bottom)`.
    static let contentStackHeight: CGFloat = 62
    /// Gap between floating bottom chrome (search bar, map button) and the nav bar.
    static let gapAboveBarWhenStacked: CGFloat = 8
    /// Gap between the camera shutter / Photo·Vibe·Reel picker and the nav bar.
    static let cameraShutterGapAboveBar: CGFloat = 24
    static var floatingChromeBottomPadding: CGFloat { contentStackHeight + gapAboveBarWhenStacked }
}

struct BottomNavBar: View {
    let activeTab: BottomNavTab
    var onMyBlogs:  () -> Void = {}
    var onCamera:   () -> Void = {}
    var onMyPlaces: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.15))

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
        .background(.ultraThinMaterial)
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
