//
//  CountryCardView.swift
//  Capper
//
//  One card per country: cover image with dark gradient overlay, country name, "Last Blog MMM yyyy".
//

import SwiftUI

private let lastBlogFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM yyyy"
    return f
}()

/// Full-width country card: latest blog's cover as background, dark gradient overlay, country name and "Last Visited MMM yyyy".
struct CountryCardView: View {
    let section: CountrySection
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TripCoverImage(
                theme: section.latestCoverBlog.coverImageName,
                coverAssetIdentifier: section.latestCoverBlog.coverAssetIdentifier
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16/10, contentMode: .fill)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.25), .black.opacity(0.6), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(section.blogs.count)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .padding(12)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    Text(displayCountryName(section.countryName))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                    Text("Last Visited \(lastBlogFormatter.string(from: section.lastBlogDate))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.bottom, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func displayCountryName(_ name: String) -> String {
        name.isEmpty || name == "Unknown" ? "Other" : name
    }
}
