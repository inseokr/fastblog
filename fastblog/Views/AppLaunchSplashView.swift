//
//  AppLaunchSplashView.swift
//  fastblog
//

import SwiftUI

struct AppLaunchSplashView: View {
    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)
    /// Matches cold-start overlay in `fastblogApp`.
    private static let splashLogoSide: CGFloat = 140

    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()

            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: Self.splashLogoSide, height: Self.splashLogoSide)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
    }
}

#Preview {
    AppLaunchSplashView()
}
