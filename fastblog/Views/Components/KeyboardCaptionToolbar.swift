//
//  KeyboardCaptionToolbar.swift
//  fastblog
//

import SwiftUI

struct KeyboardCaptionToolbar: View {
    var onCancel: () -> Void
    var onClear: () -> Void
    var onDone: () -> Void
    var isClearRed: Bool
    var doneButtonTitle: String = "Done"

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .foregroundColor(.white)
            Spacer()
            Button("Clear", action: onClear)
                .foregroundColor(isClearRed ? .red : .white)
            Spacer()
            Button(doneButtonTitle, action: onDone)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 0, green: 122/255, blue: 1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.75))
    }
}

#Preview {
    KeyboardCaptionToolbar(
        onCancel: {},
        onClear: {},
        onDone: {},
        isClearRed: true
    )
    .background(Color.black)
}
