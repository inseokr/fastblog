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

// MARK: - Blog recap place title (Google search)

/// Pull-up sheet for a blog place row — same chrome as ``POIInfoSheet``, loads ``StoryPlaceGoogleSearch`` URL in-app.
struct PlaceGoogleSearchSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    /// Row header copy (e.g. ``PlaceStop/cleanedPlaceTitle``).
    let displayTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentPageURL: URL? = nil

    private var searchURL: URL? {
        StoryPlaceGoogleSearch.url(placeName: placeTitle, placeSubtitle: placeSubtitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(white: 0.5).opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(alignment: .center) {
                Text(displayTitle.isEmpty ? "Place" : displayTitle)
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

            if let url = searchURL {
                GoogleSearchEmbeddedWebView(url: url, currentPageURL: $currentPageURL)
            } else {
                Text("Couldn’t open web results for this place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Map tap disambiguation (Apple Maps → Google)

/// Pushed from the nearby / ambiguous place picker when the embedded map is MapKit.
struct MapTapPOIGoogleDetailView: View {
    let candidate: MapTapPOICandidate
    @State private var currentPageURL: URL?

    private var searchURL: URL? { candidate.googleDetailWebURL }

    var body: some View {
        VStack(spacing: 0) {
            placeSummaryHeader
            Divider()
            webContent
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(candidate.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = searchURL {
                    Button("Safari") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var placeSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.name)
                .font(.headline)
                .foregroundStyle(.primary)

            if let categoryLabel = candidate.categoryLabel {
                Text(categoryLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let address = candidate.addressSubtitle {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            Text(
                candidate.distanceMeters < 8
                    ? "Very near your tap"
                    : String(format: "About %.0f m from your tap", candidate.distanceMeters)
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var webContent: some View {
        if let url = searchURL {
            GoogleSearchEmbeddedWebView(url: url, currentPageURL: $currentPageURL)
        } else {
            ContentUnavailableView(
                "No web results",
                systemImage: "magnifyingglass",
                description: Text("Couldn’t open web results for this place.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
