//
//  PlaceStopActionSheet.swift
//  Capper
//

import SwiftUI

struct PlaceStopActionSheet: View {
    let placeTitle: String
    var onEditName: () -> Void
    var onManagePhotos: () -> Void
    var onRemoveFromBlog: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Text("Multi Selection - Smart Menu")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                actionRow(title: "Edit Name", action: {
                    dismiss()
                    onEditName()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(title: "Manage Photos", action: {
                    dismiss()
                    onManagePhotos()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(title: "Remove From Blog", action: {
                    dismiss()
                    onRemoveFromBlog()
                })
            }
            .background(Color(white: 0.18))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func actionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlaceStopActionSheet(
        placeTitle: "Stop 1",
        onEditName: {},
        onManagePhotos: {},
        onRemoveFromBlog: {}
    )
}
