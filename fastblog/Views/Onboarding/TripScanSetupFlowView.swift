//
//  TripScanSetupFlowView.swift
//  fastblog
//

import SwiftUI

/// Home + distance setup shown the first time the user starts a trip scan.
enum TripScanSetupStep {
    case neighborhoodIntro
    case neighborhood
    case tripDistanceFromHome
}

struct TripScanSetupFlowView: View {
    @State private var step: TripScanSetupStep = .neighborhoodIntro
    var onComplete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch step {
                case .neighborhoodIntro:
                    NeighborhoodExplainerView {
                        step = .neighborhood
                    }
                case .neighborhood:
                    NeighborhoodSelectionView(
                        onSelect: {
                            step = .tripDistanceFromHome
                        },
                        onBack: {
                            step = .neighborhoodIntro
                        }
                    )
                case .tripDistanceFromHome:
                    TripDistanceFromHomeOnboardingView(
                        onContinue: onComplete,
                        onBack: {
                            step = .neighborhood
                        }
                    )
                }
            }

            if step == .neighborhoodIntro {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OnboardingConstants.Colors.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    TripScanSetupFlowView(onComplete: {}, onCancel: {})
}
