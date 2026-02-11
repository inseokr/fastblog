//
//  TitleInputView.swift
//  Capper
//

import SwiftUI

struct TitleInputView: View {
    @Binding var title: String
    var onNext: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Title")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            TextField("Trip to Place Name", text: $title)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.vertical, 12)
                .focused($isTitleFocused)
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }

            Spacer()

            Button(action: onNext) {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            isTitleFocused = true
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    TitleInputView(title: .constant("Trip to Denver"), onNext: {})
}
