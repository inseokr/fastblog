//
//  POIInfoSheet.swift
//  fastblog
//
//  Bottom sheet presenting Google Search results for a tapped map POI.
//

import CoreLocation
import MapKit
import SwiftUI

struct POIInfoSheet: View {
    let feature: MapFeature
    @Environment(\.dismiss) private var dismiss
    // Satisfies GoogleSearchEmbeddedWebView's binding contract; not read by this view.
    @State private var currentPageURL: URL? = nil
    @State private var resolvedCity: String?
    @State private var searchReady = false

    private var placeName: String {
        let t = feature.title ?? ""
        return t.isEmpty ? "Nearby Place" : t
    }

    private var googleSearchURL: URL {
        var query = placeName
        if let city = resolvedCity { query += " \(city)" }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? query
        return URL(string: "https://www.google.com/search?q=\(encoded)") ?? URL(string: "https://www.google.com/search")!
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

            if searchReady {
                GoogleSearchEmbeddedWebView(url: googleSearchURL, currentPageURL: $currentPageURL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .task {
            let geocoder = CLGeocoder()
            let location = CLLocation(
                latitude: feature.coordinate.latitude,
                longitude: feature.coordinate.longitude
            )
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                resolvedCity = placemark.locality ?? placemark.administrativeArea
            }
            searchReady = true
        }
    }
}
