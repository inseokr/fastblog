//
//  PDFPreviewSheet.swift
//  fastblog
//

import SwiftUI
import PDFKit

struct PDFPreviewSheet: View {
    let pdfURL: URL
    let previewStyle: PreviewStyle
    let shareURL: URL?

    enum PreviewStyle {
        case recap // existing behavior: continuous vertical scrolling
        case storyBook // page-by-page horizontal
    }

    init(pdfURL: URL, previewStyle: PreviewStyle = .recap, shareURL: URL? = nil) {
        self.pdfURL = pdfURL
        self.previewStyle = previewStyle
        self.shareURL = shareURL
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                PDFKitPreview(url: pdfURL, previewStyle: previewStyle)
                    .background(Color.black)
            }
            .navigationTitle("PDF Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        showShareSheet = true
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareURL ?? pdfURL])
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PDFKitPreview: UIViewRepresentable {
    let url: URL
    let previewStyle: PDFPreviewSheet.PreviewStyle

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        switch previewStyle {
        case .recap:
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
        case .storyBook:
            pdfView.displayMode = .singlePage
            pdfView.displayDirection = .horizontal
            pdfView.usePageViewController(true)
        }
        pdfView.backgroundColor = .black
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
