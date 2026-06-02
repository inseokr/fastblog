//
//  BottomNavBar.swift
//  Capper
//

import SwiftUI

enum BottomNavTab: Equatable {
    case myBlogs
    case camera
    case myPlaces
}

struct BottomNavBar: View {
    let activeTab: BottomNavTab
    let onMyBlogs: () -> Void
    let onCamera: () -> Void
    let onMyPlaces: () -> Void

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
                    action: onMyBlogs
                )
                navItem(
                    tab: .camera,
                    label: "Camera",
                    icon: .sfSymbol("camera.fill"),
                    action: onCamera
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
            .padding(.bottom, 2)
            .frame(height: 62)
        }
        .background(backgroundBlue)
    }

    private enum NavIcon {
        case asset(String)
        case sfSymbol(String)
    }

    private func navItem(
        tab: BottomNavTab,
        label: String,
        icon: NavIcon,
        action: @escaping () -> Void
    ) -> some View {
        let isActive = activeTab == tab
        let iconOpacity = isActive ? 1.0 : 0.4
        let textOpacity = isActive ? 1.0 : 0.4

        return Button(action: action) {
            VStack(spacing: 4) {
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

                Text(label)
                    .font(.caption2)
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

