
import SwiftUI
import UIKit

/// A SwiftUI scroll view wrapper that exposes its content offset and scroll state.
/// Useful for coordinating scroll position with other gestures (e.g. bottom sheet).
struct TrackableScrollView<Content: View>: UIViewRepresentable {
    let axes: Axis.Set
    let showsIndicators: Bool
    @Binding var contentOffset: CGPoint
    @Binding var isScrollEnabled: Bool
    let content: Content

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        contentOffset: Binding<CGPoint>,
        isScrollEnabled: Binding<Bool> = .constant(true),
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self._contentOffset = contentOffset
        self._isScrollEnabled = isScrollEnabled
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = showsIndicators && axes.contains(.vertical)
        scrollView.showsHorizontalScrollIndicator = showsIndicators && axes.contains(.horizontal)
        scrollView.backgroundColor = .clear
        
        // Host the SwiftUI content
        let hostView = UIHostingController(rootView: content)
        hostView.view.backgroundColor = .clear
        hostView.view.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(hostView.view)
        
        // Constraints
        NSLayoutConstraint.activate([
            hostView.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostView.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostView.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostView.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            // Width constraint for vertical scrolling
            hostView.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        uiView.showsVerticalScrollIndicator = showsIndicators && axes.contains(.vertical)
        uiView.showsHorizontalScrollIndicator = showsIndicators && axes.contains(.horizontal)
        uiView.isScrollEnabled = isScrollEnabled
        
        // Update content if needed (HostingController handles this automatically mostly)
        if let hostView = uiView.subviews.first(where: { $0.next is UIHostingController<Content> })?.next as? UIHostingController<Content> {
            hostView.rootView = content
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TrackableScrollView

        init(_ parent: TrackableScrollView) {
            self.parent = parent
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            DispatchQueue.main.async {
                self.parent.contentOffset = scrollView.contentOffset
            }
        }
    }
}
