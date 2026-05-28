//
//  KakaoPlaceDetailSheet.swift
//  fastblog
//
//  In-app Kakao Map place detail (WKWebView) for a row in the nearby POI picker.
//

import SwiftUI
import UIKit

/// Kakao Map place page pushed inside the nearby POI picker (not a separate sheet).
struct KakaoPlaceDetailSheet: View {
    let candidate: MapTapPOICandidate
    @State private var currentPageURL: URL?

    private var detailURL: URL? { candidate.detailWebURL }

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
                if let appURL = candidate.kakaoMapAppURL,
                   UIApplication.shared.canOpenURL(appURL) {
                    Button("Kakao Map") {
                        UIApplication.shared.open(appURL)
                    }
                } else if let url = detailURL {
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

            HStack(spacing: 12) {
                Text(
                    candidate.distanceMeters < 8
                        ? "Very near your tap"
                        : String(format: "About %.0f m from your tap", candidate.distanceMeters)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)

                if let phone = candidate.phone {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var webContent: some View {
        if let url = detailURL {
            GoogleSearchEmbeddedWebView(url: url, currentPageURL: $currentPageURL)
        } else {
            ContentUnavailableView(
                "No place page",
                systemImage: "map",
                description: Text("Kakao Map doesn’t have a detail link for this place.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
