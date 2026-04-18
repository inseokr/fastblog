//
//  ScrollMetricsReportingTextEditor.swift
//  fastblog
//
//  UITextView wrapper; optionally reports scroll metrics for a custom overlay thumb.
//

import SwiftUI
import UIKit

struct ScrollMetricsReportingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var wantsKeyboardFocus: Bool
    var contentHeight: Binding<CGFloat>? = nil
    var visibleViewportHeight: Binding<CGFloat>? = nil
    var scrollOffsetY: Binding<CGFloat>? = nil

    var textInsets: UIEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    /// Cursor and selection tint; avoids system blue flashing on dark caption chrome during rapid relayout.
    var caretTint: UIColor = .label

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textContainerInset = textInsets
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = .label
        tv.tintColor = caretTint
        tv.keyboardDismissMode = .interactive
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.text = text
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tv.setContentHuggingPriority(.defaultLow, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.textContainerInset = textInsets
        uiView.font = UIFont.preferredFont(forTextStyle: .body)
        uiView.tintColor = caretTint
        uiView.showsVerticalScrollIndicator = false
        uiView.showsHorizontalScrollIndicator = false
        if uiView.text != text {
            uiView.text = text
        }
        if wantsKeyboardFocus {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            // Defer resign so we never call UIKit first-responder churn synchronously inside
            // SwiftUI's `updateUIView` pass (keyboard + safe-area updates can create AttributeGraph cycles).
            DispatchQueue.main.async { [weak uiView] in
                uiView?.resignFirstResponder()
            }
        }
        // Avoid publishing every `updateUIView` pass (keyboard / safe-area animation can thrash bindings
        // and make the caret or overlays flicker). Scroll and text changes still publish via delegate.
        context.coordinator.publishMetricsIfNeeded(from: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScrollMetricsReportingTextEditor
        private var lastPublishedVisible: CGFloat = -1
        private var lastPublishedContent: CGFloat = -1
        private var lastPublishedOffset: CGFloat = -1

        init(_ parent: ScrollMetricsReportingTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            publishMetrics(from: textView, force: true)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishMetrics(from: scrollView, force: true)
        }

        /// Coalesces noisy layout-driven updates; `force` is used when the user scrolls or edits text.
        func publishMetricsIfNeeded(from scrollView: UIScrollView) {
            publishMetrics(from: scrollView, force: false)
        }

        func publishMetrics(from scrollView: UIScrollView, force: Bool) {
            guard let contentBinding = parent.contentHeight,
                  let visibleBinding = parent.visibleViewportHeight,
                  let offsetBinding = parent.scrollOffsetY else {
                return
            }
            let visible = scrollView.bounds.height
                - scrollView.adjustedContentInset.top
                - scrollView.adjustedContentInset.bottom
            let content = scrollView.contentSize.height
            let offset = scrollView.contentOffset.y
            // Wider epsilon during implicit layout passes dampens keyboard-driven thrash.
            let eps: CGFloat = force ? 0.25 : 3
            if !force {
                if abs(lastPublishedVisible - visible) <= eps,
                   abs(lastPublishedContent - content) <= eps,
                   abs(lastPublishedOffset - offset) <= eps {
                    return
                }
            }
            lastPublishedVisible = visible
            lastPublishedContent = content
            lastPublishedOffset = offset
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if abs(visibleBinding.wrappedValue - visible) > 0.25 {
                    visibleBinding.wrappedValue = visible
                }
                if abs(contentBinding.wrappedValue - content) > 0.25 {
                    contentBinding.wrappedValue = content
                }
                if abs(offsetBinding.wrappedValue - offset) > 0.25 {
                    offsetBinding.wrappedValue = offset
                }
            }
        }
    }
}
