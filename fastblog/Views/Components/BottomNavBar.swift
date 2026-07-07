//
//  BottomNavBar.swift
//  Capper
//

import SwiftUI

enum BottomNavTab: Equatable {
    case myBlogs
    case create
    case myPlaces
}

struct BottomNavBar: View {
    let activeTab: BottomNavTab
    let onMyBlogs: () -> Void
    let onCreate: () -> Void
    let onMyPlaces: () -> Void

    private var menuIndicators: BlogMenuIndicatorStore { BlogMenuIndicatorStore.shared }

    private let backgroundBlue = Color(red: 5/255, green: 10/255, blue: 48/255)
    private let hairline = Color.white.opacity(0.12)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(hairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                navItem(
                    tab: .myBlogs,
                    label: "My Blogs",
                    icon: .asset("MyBlogsIcon"),
                    showsActivityBadge: menuIndicators.hasAnyIndicator,
                    action: onMyBlogs
                )
                navItem(
                    tab: .create,
                    label: "Create",
                    icon: .sfSymbol("plus.circle.fill"),
                    action: onCreate
                )
                navItem(
                    tab: .myPlaces,
                    label: "My Places",
                    icon: .asset("MyPlacesIcon"),
                    action: onMyPlaces
                )
            }
            // Keep the content higher (more top air) while avoiding extra bottom lift
            // beyond the home indicator safe area.
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(height: HomeChromeMetrics.bottomNavBarRowHeight)
        }
        .safeAreaPadding(.bottom, HomeChromeMetrics.bottomNavBarExtraBottomPadding)
        .background {
            backgroundBlue.ignoresSafeArea(edges: .bottom)
        }
        // Home tab content may use larger dynamic type; keep the tab bar height identical on every tab.
        .dynamicTypeSize(.medium)
    }

    private enum NavIcon {
        case asset(String)
        case sfSymbol(String)
    }

    private func navItem(
        tab: BottomNavTab,
        label: String,
        icon: NavIcon,
        showsActivityBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isActive = activeTab == tab
        let iconOpacity = isActive ? 1.0 : 0.4
        let textOpacity = isActive ? 1.0 : 0.4

        return Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        switch icon {
                        case .asset(let name):
                            Image(name)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        case .sfSymbol(let name):
                            Image(systemName: name)
                                .font(.system(size: 20))
                                .frame(width: 24, height: 24)
                        }
                    }
                    .foregroundColor(.white)
                    .opacity(iconOpacity)

                    if showsActivityBadge {
                        BlogMenuNavDotBadge()
                            .offset(x: 6, y: -5)
                    }
                }

                Text(label)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(.white)
                    .opacity(textOpacity)

                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .opacity(isActive ? 1 : 0)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home settings gear (My Blogs / Camera / My Places)

/// Shared settings control for home tabs.
struct HomeSettingsGearButton: View {
    enum Style {
        /// My Blogs / My Places navigation bar.
        case navigationBar
        /// Camera preview top row — frosted circle aligned with flip / flash controls.
        case cameraTopBar
    }

    var style: Style = .navigationBar
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .navigationBar:
                gearIcon(pointSize: HomeChromeMetrics.settingsIconPointSize)
                    .foregroundStyle(.white)
                    .frame(
                        width: HomeChromeMetrics.settingsTapSide,
                        height: HomeChromeMetrics.settingsTapSide
                    )
            case .cameraTopBar:
                gearIcon(pointSize: 16)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private func gearIcon(pointSize: CGFloat) -> some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: pointSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
    }
}
