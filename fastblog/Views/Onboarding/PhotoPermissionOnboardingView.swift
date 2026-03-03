//
//  PhotoPermissionOnboardingView.swift
//  Capper
//

import Photos
import SwiftUI

struct PhotoPermissionOnboardingView: View {
    @ObservedObject var photoAuth: PhotosAuthorizationManager

    // Staggered animation phases (similar to ProblemStatementView)
    @State private var showIcon = false
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showTrustLine = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop,
                    OnboardingConstants.Colors.backgroundGradientBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                
                // Icon Header
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                    .padding(.bottom, 40)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.8)

                // Copy
                VStack(spacing: 16) {
                    Text("Find trips automatically")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text("Bloggo groups photos by date and location to build recap blogs.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(showBody ? 1 : 0)
                        .offset(y: showBody ? 0 : 8)
                    
                    Text("Photos stay on your device. Upload is optional.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 40)
                        .opacity(showTrustLine ? 1 : 0)
                        .offset(y: showTrustLine ? 0 : 8)
                }
                
                Spacer()

                // Button
                VStack(spacing: 8) {
                    Button {
                        // Triggers system prompt
                        Task {
                            await photoAuth.requestAccess()
                        }
                    } label: {
                        Text("Allow Photo Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)
                    }
                    
                    Text("You can choose specific photos instead.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startStaggeredAnimation()
        }
    }

    private func startStaggeredAnimation() {
        let duration: TimeInterval = 0.5

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showIcon = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.2)) {
            showHeadline = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.5)) {
            showBody = true
        }
        withAnimation(.easeOut(duration: duration).delay(0.8)) {
            showTrustLine = true
        }
        withAnimation(.easeOut(duration: duration).delay(1.1)) {
            showButton = true
        }
    }
}

#Preview {
    PhotoPermissionOnboardingView(photoAuth: PhotosAuthorizationManager())
}
