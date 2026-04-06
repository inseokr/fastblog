import SwiftUI
import UIKit

/// Nudges UIKit to apply `preferredStatusBarStyle` for full-screen SwiftUI overlays where `preferredColorScheme` alone may not update the status bar.
struct StatusBarStyleApplier: UIViewControllerRepresentable {
    var style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> StatusBarStyleViewController {
        let vc = StatusBarStyleViewController()
        vc.appliedStyle = style
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: StatusBarStyleViewController, context: Context) {
        uiViewController.appliedStyle = style
        uiViewController.setNeedsStatusBarAppearanceUpdate()
        uiViewController.navigationController?.setNeedsStatusBarAppearanceUpdate()
    }

    final class StatusBarStyleViewController: UIViewController {
        var appliedStyle: UIStatusBarStyle = .default

        override var preferredStatusBarStyle: UIStatusBarStyle {
            appliedStyle
        }
    }
}
