//
//  POIInfoSheet.swift
//  fastblog
//
//  Bottom sheet presenting a Google Maps place page for a tapped map POI.
//

import MapKit
import SwiftUI

struct POIInfoSheet: View {
    let feature: MapFeature
    @Environment(\.dismiss) private var dismiss
    @State private var currentPageURL: URL? = nil

    private var placeName: String {
        let t = feature.title ?? ""
        return t.isEmpty ? "Nearby Place" : t
    }

    private var googleMapsURL: URL {
        let encoded = placeName.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? placeName
        let lat = feature.coordinate.latitude
        let lng = feature.coordinate.longitude
        let urlString = "https://www.google.com/maps/search/?api=1&query=\(encoded)&center=\(lat),\(lng)"
        return URL(string: urlString) ?? URL(string: "https://www.google.com/maps")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(white: 0.5).opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Header
            HStack(alignment: .center) {
                Text(placeName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            GoogleSearchEmbeddedWebView(url: googleMapsURL, currentPageURL: $currentPageURL)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
