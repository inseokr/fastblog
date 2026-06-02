//
//  PreviewCaptionKeyboardDock.swift
//  fastblog
//
//  Pins SwiftUI caption chrome to UIKit's keyboardLayoutGuide so the panel
//  rides flush on top of the keyboard (no manual frame notifications).
//
//  Background strategy
//  ───────────────────
//  A UIVisualEffectView (.systemChromeMaterial) is added in UIKit behind the
//  SwiftUI host.  Its bottom is constrained to keyboardLayoutGuide.top + 40 pt,
//  so it bleeds ~40 pt under the keyboard's rounded top corners — eliminating the
//  transparent-corner "holes" that appear when the panel meets the keyboard edge.
//  The keyboard window renders on top of everything, so the extra 40 pt is never
//  actually visible; it just fills in what would otherwise be camera bleed-through.
//

import SwiftUI
import UIKit

/// Hosts `content` with its bottom edge constrained to `keyboardLayoutGuide.topAnchor`.
/// The panel self-sizes vertically (grows upward as content expands) and shares the
/// same frosted-glass surface as the system keyboard with no visible seam.
struct PreviewCaptionKeyboardDock<Content: View>: UIViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DockContainerView {
        let container = DockContainerView()

        // ── Blur background ──────────────────────────────────────────────────
        // .systemChromeMaterial matches the keyboard's own blur surface.
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blur)
        context.coordinator.blurView = blur

        // ── SwiftUI content host ─────────────────────────────────────────────
        let host = UIHostingController(rootView: content())
        if #available(iOS 16.0, *) {
            host.sizingOptions = .intrinsicContentSize
        }
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        context.coordinator.hostingController = host

        context.coordinator.installConstraints(
            hostView: host.view,
            blurView: blur,
            in: container
        )
        return container
    }

    func updateUIView(_ uiView: DockContainerView, context: Context) {
        context.coordinator.hostingController?.rootView = content()
        context.coordinator.hostingController?.view.invalidateIntrinsicContentSize()
    }

    final class Coordinator {
        var hostingController: UIHostingController<Content>?
        var blurView: UIVisualEffectView?

        func installConstraints(
            hostView: UIView,
            blurView: UIView,
            in container: DockContainerView
        ) {
            if #available(iOS 17.0, *) {
                container.keyboardLayoutGuide.followsUndockedKeyboard = true
            }

            NSLayoutConstraint.activate([
                // Content: full-width, bottom flush with keyboard top.
                hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostView.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor),

                // Background blur: matches content width and top, but its bottom
                // extends 40 pt below keyboard top to cover the keyboard's rounded
                // top-corner cutouts.
                blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                blurView.topAnchor.constraint(equalTo: hostView.topAnchor),
                blurView.bottomAnchor.constraint(
                    equalTo: container.keyboardLayoutGuide.topAnchor,
                    constant: 40
                ),
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
