//
//  PlaceStopActionSheet.swift
//  Capper
//

import SwiftUI

struct PlaceStopActionSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    var onEditName: () -> Void
    var onManagePhotos: () -> Void
    var onEditMode: () -> Void
    var onRemoveFromBlog: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Header - Typography Hierarchy
            VStack(spacing: 4) {
                Text(placeTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let subtitle = placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 24)

            // Section 1: Editing Actions
            VStack(spacing: 0) {
                actionRow(icon: "pencil", title: "Edit Place Name", action: {
                    dismiss()
                    onEditName()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(icon: "photo.on.rectangle", title: "Manage Photos", action: {
                    dismiss()
                    onManagePhotos()
                })
                Divider()
                    .background(Color(white: 0.3))
                actionRow(icon: "text.alignleft", title: "Edit Caption & Details", action: {
                    dismiss()
                    onEditMode()
                })
            }
            .background(Color(white: 0.15))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            // Section 2: Destructive Action
            VStack(spacing: 0) {
                Button(action: {
                    dismiss()
                    onRemoveFromBlog()
                }) {
                    Text("Hide from Blog")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .background(Color(white: 0.15))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .presentationBackground {
            // Subtle blur for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .presentationDetents([.height(380)])
        .preferredColorScheme(.dark)
        .onAppear {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlaceStopActionSheet(
        placeTitle: "Golden Gate Bridge",
        placeSubtitle: "San Francisco",
        onEditName: {},
        onManagePhotos: {},
        onEditMode: {},
        onRemoveFromBlog: {}
    )
}
