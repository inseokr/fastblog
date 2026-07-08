//
//  NeighborhoodIntroView.swift
//  fastblog
//

import SwiftUI
import UIKit

struct NeighborhoodIntroView: View {
    var onDismiss: () -> Void

    private enum Stage {
        case choose
        case setHome
    }
    
    @State private var stage: Stage = .choose
    private var settingsBackground: Color {
        OnboardingConstants.Colors.background
    }

    var body: some View {
        ZStack {
            switch stage {
            case .choose:
                chooseNeighborhoodView
            case .setHome:
                NeighborhoodSelectionView(
                    onSelect: onDismiss,
                    onBack: nil // Use the navigation bar back button to return to Settings.
                )
            }
        }
    }
    
    private var chooseNeighborhoodView: some View {
        ZStack {
            settingsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // No close button/tab; rely on the navigation bar back button.
                Spacer()

                Image("ScanIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .padding(.bottom, 32)

                Text("Choose Your\nNeighborhood")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(OnboardingConstants.Colors.primaryText)
                    .padding(.bottom, 16)

                Text("This helps us organize your trips and\npersonalize your experience.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(OnboardingConstants.Colors.secondaryText)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)

                Spacer()

                Button {
                    stage = .setHome
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
                .padding(.bottom, 12)

                Text("You can change this anytime.")
                    .font(.caption)
                    .foregroundColor(OnboardingConstants.Colors.tertiaryText)
                    .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    NeighborhoodIntroView(onDismiss: {})
}
