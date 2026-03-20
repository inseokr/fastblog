// fastblog/Views/StoryBook/PlaceBlockView.swift
import SwiftUI

struct PlaceBlockView: View {
    let place: PlaceContent
    let photos: [PhotoContent]   // caller passes place.photos[photoSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                Text(place.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                Spacer()
                if let ts = place.timestamp {
                    Text(ts)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Caption
            if let caption = place.caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            // Photos
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        PhotoCardView(photo: photos[i])
                    }
                }
                .frame(
                    maxWidth: photos.count == 1 ? UIScreen.main.bounds.width * 0.5 : .infinity,
                    minHeight: 200,
                    maxHeight: 200,
                    alignment: .leading
                )
                .clipped()
            }
        }
        .padding(.vertical, 4)
    }
}
