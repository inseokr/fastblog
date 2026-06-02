//
//  PreviewCaptionKeyboardDock.swift
//  fastblog
//
//  Pins SwiftUI caption chrome to UIKit's keyboardLayoutGuide so the panel
//  rides flush on top of the keyboard (no manual frame notifications).
//
//  Height is self-sizing: the hosting controller's intrinsicContentSize drives
//  the vertical extent, which grows as the user types more lines.
//

import SwiftUI
import UIKit

/// Hosts `content` with its bottom edge constrained to `keyboardLayoutGuide.topAnchor`.
/// The panel self-sizes vertically — it grows upward as content expands.
struct PreviewCaptionKeyboardDock<Content: View>: UIViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DockContainerView {
        let container = DockContainerView()

        let host = UIHostingController(rootView: content())
        // Keep intrinsicContentSize in sync with SwiftUI layout so the panel
        // grows/shrinks as text is added or removed (iOS 16+).
        if #available(iOS 16.0, *) {
            host.sizingOptions = .intrinsicContentSize
        }
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(host.view)
        context.coordinator.hostingController = host
        context.coordinator.installConstraints(hostView: host.view, in: container)
        return container
    }

    func updateUIView(_ uiView: DockContainerView, context: Context) {
        context.coordinator.hostingController?.rootView = content()
        // Belt-and-suspenders for iOS < 16: nudge AutoLayout to re-query
        // intrinsicContentSize after every SwiftUI state update.
        context.coordinator.hostingController?.view.invalidateIntrinsicContentSize()
    }

    final class Coordinator {
        var hostingController: UIHostingController<Content>?

        func installConstraints(hostView: UIView, in container: DockContainerView) {
            if #available(iOS 17.0, *) {
                container.keyboardLayoutGuide.followsUndockedKeyboard = true
            }
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                // Bottom rides the keyboard guide — panel grows upward from here.
                hostView.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor),
            ])
        }
    }
}

/// Full-screen transparent container; the hosted panel self-sizes and sits above the keyboard.
final class DockContainerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}
