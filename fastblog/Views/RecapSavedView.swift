//
//  RecapSavedView.swift
//  Capper
//

import SwiftUI

/// Shown after the user completes the Create Blog sequence. Close navigates back to Landing.
struct RecapSavedView: View {
    @Environment(\.dismissToLanding) private var dismissToLanding

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("ScanIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)

            VStack(spacing: 8) {
                Text("Recap Blog Saved To Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Share your trip with ease.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Button {
                dismissToLanding()
            } label: {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Environment key for dismissing to Landing
private struct DismissToLandingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dismissToLanding: () -> Void {
        get { self[DismissToLandingKey.self] }
        set { self[DismissToLandingKey.self] = newValue }
    }
}

#Preview {
    RecapSavedView()
        .environment(\.dismissToLanding, {})
}
