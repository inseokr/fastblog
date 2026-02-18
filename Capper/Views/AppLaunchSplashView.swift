//
//  AppLaunchSplashView.swift
//  Capper
//

import SwiftUI

struct AppLaunchSplashView: View {
    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)
    
    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()
            
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
    }
}

#Preview {
    AppLaunchSplashView()
}
