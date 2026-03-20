//
//  PDFPreviewSheet.swift
//  fastblog
//

import SwiftUI
import PDFKit

struct PDFPreviewSheet: View {
    let pdfURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                PDFKitPreview(url: pdfURL)
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
                ShareSheet(items: [pdfURL])
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PDFKitPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
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
