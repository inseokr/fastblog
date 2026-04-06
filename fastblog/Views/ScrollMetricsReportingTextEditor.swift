//
//  ScrollMetricsReportingTextEditor.swift
//  fastblog
//
//  UITextView wrapper that reports scroll metrics so SwiftUI can draw a proportional vertical thumb.
//

import SwiftUI
import UIKit

struct ScrollMetricsReportingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    @Binding var visibleViewportHeight: CGFloat
    @Binding var scrollOffsetY: CGFloat
    @Binding var wantsKeyboardFocus: Bool

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
            uiView.resignFirstResponder()
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
                let p = self.parent
                if abs(p.visibleViewportHeight - visible) > 0.25 {
                    self.parent.visibleViewportHeight = visible
                }
                if abs(p.contentHeight - content) > 0.25 {
                    self.parent.contentHeight = content
                }
                if abs(p.scrollOffsetY - offset) > 0.25 {
                    self.parent.scrollOffsetY = offset
                }
            }
        }
    }
}

/// Windows-style vertical scroll thumb aligned to the trailing edge of the editor.
struct CaptionEditorVerticalScrollThumb: View {
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
    let scrollOffsetY: CGFloat
    let trackLength: CGFloat
    var trackTopInset: CGFloat = 20
    var trackBottomInset: CGFloat = 14
    var thumbWidth: CGFloat = 3
    var minThumbLength: CGFloat = 28
    var thumbColor: Color = Color(uiColor: .placeholderText).opacity(0.45)

    private var needsScrollIndicator: Bool {
        contentHeight > visibleHeight + 0.5 && visibleHeight > 1 && trackLength > minThumbLength
    }

    var body: some View {
        Group {
            if needsScrollIndicator {
                thumbView()
            }
        }
    }

    private func thumbView() -> some View {
        let innerTrack = max(0, trackLength - trackTopInset - trackBottomInset)
        let maxScrollY = max(0, contentHeight - visibleHeight)
        let thumbLength = max(
            minThumbLength,
            min(innerTrack, (visibleHeight / contentHeight) * innerTrack)
        )
        let travel = max(0, innerTrack - thumbLength)
        let progress = maxScrollY > 0 ? min(1, max(0, scrollOffsetY / maxScrollY)) : 0
        let thumbY = trackTopInset + progress * travel

        return Capsule()
            .fill(thumbColor)
            .frame(width: thumbWidth, height: thumbLength)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, thumbY)
    }
}
