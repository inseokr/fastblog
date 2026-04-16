//
//  ShareSheet.swift
//  Capper
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Raw file URLs in `activityItems` make Launch Services / ShareSheet probe UTIs and file-provider
        // metadata heavily (noisy logs and noticeable delay), especially for zips in tmp. Item providers
        // advertise type up front and behave better for on-disk files.
        let activityItems: [Any] = items.map { item in
            if let url = item as? URL, url.isFileURL {
                if let provider = NSItemProvider(contentsOf: url) {
                    return provider
                }
                if let inferred = UTType(filenameExtension: url.pathExtension),
                   inferred != .data {
                    let fallback = NSItemProvider()
                    fallback.registerFileRepresentation(
                        forTypeIdentifier: inferred.identifier,
                        fileOptions: [],
                        visibility: .all
                    ) { completion in
                        completion(url, true, nil)
                        return nil
                    }
                    return fallback
                }
                return url
            }
            return item
        }
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SavedToFilesBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15, weight: .semibold))
            Text("Blog saved to your files")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}
