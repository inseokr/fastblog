//
//  UnsavedTripCard.swift
//  Capper
//
//  A horizontal-oriented card for unsaved trips in the Profile page.
//

import SwiftUI

struct UnsavedTripCard: View {
    let trip: TripDraft
    var onViewPhotos: () -> Void

    private let cardWidth: CGFloat = 260
    private let cardHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverSection
            
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(locationText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                
                Text("\(trip.totalPhotoCount) Photos • \(trip.dateRangeText)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                
                Button(action: onViewPhotos) {
                    Text("View Photos")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(6)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
        .frame(width: cardWidth)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var coverSection: some View {
        ZStack(alignment: .bottomLeading) {
            if let coverId = trip.coverAssetIdentifier {
                AssetPhotoView(assetIdentifier: coverId, cornerRadius: 0, targetSize: CGSize(width: 500, height: 300))
                    .frame(height: 100)
            } else {
                MockPhotoView(seed: trip.id.hashValue, cornerRadius: 0)
                    .frame(height: 100)
            }
            
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 40)
        }
        .frame(height: 100)
        .clipped()
        .cornerRadius(12, corners: [.topLeft, .topRight])
    }

    private var locationText: String {
        let city = trip.cityWithMostPhotosDisplayName
        let country = trip.primaryCountryDisplayName ?? ""
        if country.isEmpty { return city }
        if city == "New Place" || city.isEmpty { return country }
        return "\(city), \(country)"
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
