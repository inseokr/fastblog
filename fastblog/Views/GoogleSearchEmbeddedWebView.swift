//
//  GoogleSearchEmbeddedWebView.swift
//  fastblog
//
//  Shared WKWebView wrapper for in-flow Google results (place caption editors, photo modal).
//

import SwiftUI
import WebKit

struct GoogleSearchEmbeddedWebView: UIViewRepresentable {
    let url: URL
    @Binding var currentPageURL: URL?

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastRequestedURL: URL?
        var currentPageURLBinding: Binding<URL?> = .constant(nil)

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.currentPageURLBinding.wrappedValue = webView.url
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.currentPageURLBinding.wrappedValue = webView.url
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.indicatorStyle = .white
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.currentPageURLBinding = $currentPageURL
        guard context.coordinator.lastRequestedURL != url else { return }
        context.coordinator.lastRequestedURL = url
        currentPageURL = nil
        webView.load(URLRequest(url: url))
    }
}
