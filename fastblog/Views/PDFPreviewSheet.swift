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
    @State private var showSavedToFilesBanner = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                PDFKitPreview(url: pdfURL)
                    .background(Color.black)

                if showSavedToFilesBanner {
                    SavedToFilesBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSavedToFilesBanner)
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
                ShareSheet(items: [pdfURL]) { completed in
                    if completed {
                        showSavedToFilesBanner = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showSavedToFilesBanner = false
                        }
                    }
                }
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
