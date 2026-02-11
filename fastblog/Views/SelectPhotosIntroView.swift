//
//  SelectPhotosIntroView.swift
//  Capper
//

import SwiftUI

/// Shown after scan completes with trips, before the list of places. "Select Photos" / "To Create A Blog" with Get Started CTA and "Do not show again" checkbox.
struct SelectPhotosIntroView: View {
    @State private var doNotShowAgain: Bool = false
    var onGetStarted: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 60)

                VStack(spacing: 12) {
                    Text("Select Photos")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("To Create A Blog")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                VStack(spacing: 24) {
                    Toggle(isOn: $doNotShowAgain) {
                        Text("Do not show again")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .tint(.orange)
                    .padding(.horizontal, 8)

                    Button {
                        onGetStarted(doNotShowAgain)
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SelectPhotosIntroView(onGetStarted: { _ in })
}
