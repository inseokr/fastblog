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
        DispatchQueue.main.async {
            context.coordinator.publishMetrics(from: uiView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScrollMetricsReportingTextEditor

        init(_ parent: ScrollMetricsReportingTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            publishMetrics(from: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishMetrics(from: scrollView)
        }

        func publishMetrics(from scrollView: UIScrollView) {
            let visible = scrollView.bounds.height
                - scrollView.adjustedContentInset.top
                - scrollView.adjustedContentInset.bottom
            let content = scrollView.contentSize.height
            let offset = scrollView.contentOffset.y
            let eps: CGFloat = 0.25
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let p = self.parent
                if abs(p.visibleViewportHeight - visible) > eps {
                    self.parent.visibleViewportHeight = visible
                }
                if abs(p.contentHeight - content) > eps {
                    self.parent.contentHeight = content
                }
                if abs(p.scrollOffsetY - offset) > eps {
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
