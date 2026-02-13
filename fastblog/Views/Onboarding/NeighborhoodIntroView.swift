//
//  NeighborhoodIntroView.swift
//  fastblog
//

import SwiftUI

struct NeighborhoodIntroView: View {
    var onDismiss: () -> Void

    @State private var navigateToSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.1, blue: 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.6))
                                .padding()
                        }
                    }

                    Spacer()

                    Image("ScanIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .padding(.bottom, 32)

                    Text("Choose Your\nNeighborhood")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.bottom, 16)

                    Text("This helps us organize your trips and\npersonalize your experience.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 32)
                        .padding(.bottom, 48)

                    Spacer()

                    Button {
                        navigateToSearch = true
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    Text("You can change this anytime.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 24)
                }
            }
            .navigationDestination(isPresented: $navigateToSearch) {
                NeighborhoodSearchView(onDismiss: onDismiss)
            }
        }
    }
}

#Preview {
    NeighborhoodIntroView(onDismiss: {})
}
