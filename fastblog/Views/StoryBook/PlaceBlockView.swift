// fastblog/Views/StoryBook/PlaceBlockView.swift
import SwiftUI

struct PlaceBlockView: View {
    let place: PlaceContent
    let photos: [PhotoContent]

    var body: some View {
        GeometryReader { geo in
            let hPadding: CGFloat = 32          // matches .padding(.horizontal, 16) × 2
            let pageWidth = geo.size.width
            let gap: CGFloat = 8
            // 2 photos side-by-side each get half width minus gap; 1 photo gets ~60% width
            let photoWidth: CGFloat = photos.count >= 2
                ? (pageWidth - gap) / 2
                : pageWidth * 0.60

            VStack(alignment: .leading, spacing: 6) {
                // Title row
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    Text(place.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                    Spacer()
                    if let ts = place.timestamp {
                        Text(ts)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Caption above photos
                if let caption = place.caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Photos
                if !photos.isEmpty {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<photos.count, id: \.self) { i in
                            PhotoCardView(photo: photos[i], width: photoWidth)
                        }
                        if photos.count == 1 { Spacer() }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        // Height hint so GeometryReader doesn't collapse
        .frame(minHeight: photos.isEmpty ? 60 : 260)
    }
}
