
import SwiftUI

/// A custom bottom sheet that hosts a scrollable view.
/// It only allows dragging down to dismiss when the internal scroll view is at the top.
struct BottomSheetView<Content: View>: View {
    let isOpen: Binding<Bool>
    let maxHeight: CGFloat
    let minHeight: CGFloat
    let content: Content

    @State private var offset: CGFloat = 0
    @State private var contentOffset: CGPoint = .zero
    @State private var isScrollEnabled = true

    init(
        isOpen: Binding<Bool>,
        maxHeight: CGFloat,
        minHeight: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.isOpen = isOpen
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.content = content()
    }

    private var indicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.white.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                indicator
                
                TrackableScrollView(
                    axes: .vertical,
                    showsIndicators: true,
                    contentOffset: $contentOffset,
                    isScrollEnabled: $isScrollEnabled
                ) {
                    content
                }
            }
            .background(Color.black)
            .cornerRadius(20)
            .frame(height: maxHeight, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: max(0, offset))
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let isAtTop = contentOffset.y <= 0
        
        // Only allow dragging down if we are at the top
        if isAtTop && value.translation.height > 0 {
            offset = value.translation.height
            isScrollEnabled = false // Disable scrolling to prevent bounce while dragging sheet
        } else {
            // Otherwise let the scroll view handle it
            offset = 0
            isScrollEnabled = true
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        // Dismiss if dragged down far enough
        if offset > 100 {
            isOpen.wrappedValue = false
        }
        
        // Reset state
        withAnimation {
            offset = 0
        }
        isScrollEnabled = true
    }
}

struct BottomSheetView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            BottomSheetView(
                isOpen: .constant(true),
                maxHeight: 600,
                minHeight: 100
            ) {
                VStack(spacing: 20) {
                    ForEach(0..<20) { i in
                        Text("Item \(i)")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}
