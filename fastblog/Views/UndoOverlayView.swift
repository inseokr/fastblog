//
//  UndoOverlayView.swift
//  fastblog
//

import SwiftUI

struct UndoOverlayView: View {
    let text: String
    @Binding var isMinimized: Bool
    var onUndo: () -> Void
    var onDismiss: () -> Void

    private let minimizedSize: CGFloat = 44
    private let horizontalPadding: CGFloat = 16
    private let bottomPadding: CGFloat = 16

    var body: some View {
        VStack {
            if isMinimized {
                minimizedView
                    .transition(.scale(scale: 0.1, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                expandedView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isMinimized)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(true)
    }

    private var expandedView: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            Spacer()
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 0 {
                        withAnimation {
                            isMinimized = true
                        }
                    }
                }
        )
    }

    private var minimizedView: some View {
        HStack {
            Spacer()
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: minimizedSize, height: minimizedSize)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            UndoOverlayView(
                text: "Place deleted",
                isMinimized: .constant(false),
                onUndo: {},
                onDismiss: {}
            )
            UndoOverlayView(
                text: "Photo removed",
                isMinimized: .constant(true),
                onUndo: {},
                onDismiss: {}
            )
            .padding(.bottom, 80)
        }
    }
}
