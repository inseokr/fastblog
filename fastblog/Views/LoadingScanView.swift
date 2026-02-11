//
//  LoadingScanView.swift
//  Capper
//

import SwiftUI

private let loadingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

struct LoadingScanView: View {
    var message: String = "Loading Past Trips…"

    var body: some View {
        ZStack {
            loadingBackground
                .ignoresSafeArea()
            VStack(spacing: 32) {
                ScanningAnimationView()
                Text(message)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    LoadingScanView(message: "Loading Past Trips…")
}
