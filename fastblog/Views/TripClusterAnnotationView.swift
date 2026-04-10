// fastblog/Views/TripClusterAnnotationView.swift

import SwiftUI

/// Map annotation view for a group of 2+ trips clustered at a single position.
///
/// Design:
/// - 60×60 representative cover photo (rounded rect)
/// - Ghost card offset behind to hint "stacked / grouped"
/// - Count pill (blue capsule, top-right) showing total trips in cluster
/// - No title text below — distinguishes cluster from individual TripAnnotationView at a glance
struct TripClusterAnnotationView: View {
    let cluster: TripCluster
    var isSelected: Bool = false

    private static let size: CGFloat = 60
    private static let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Ghost card behind — signals "there are more items here"
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .frame(width: Self.size - 4, height: Self.size - 4)
                .offset(x: 5, y: -5)

            // Representative photo card (front)
            TripCoverImage(
                theme: cluster.representative.coverImageName,
                coverAssetIdentifier: cluster.representative.coverAssetIdentifier,
                targetSize: CGSize(width: 120, height: 120)
            )
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.white : Color.white.opacity(0.65),
                        lineWidth: isSelected ? 3 : 1.5
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)

            // Count badge
            Text("\(cluster.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.blue))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2)
                .offset(x: 10, y: -10)
        }
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
