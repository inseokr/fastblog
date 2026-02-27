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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Button("Clear", action: onClear)
                    .font(.subheadline)
                    .foregroundColor(isClearRed ? .red : .white)
                Spacer()
                Button(doneButtonTitle, action: onDone)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 0, green: 122/255, blue: 1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.horizontal, 12)
            
            Color.clear.frame(height: 12)
        }
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
