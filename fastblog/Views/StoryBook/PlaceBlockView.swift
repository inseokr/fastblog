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
                    .foregroundColor(Color.gray)
                    .padding(.top, 2)
                Text(place.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                Spacer()
                if let ts = place.timestamp {
                    Text(ts)
                        .font(.system(size: 11))
                        .foregroundColor(Color.gray)
                }
            }

            // Caption
            if let caption = place.caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(Color.black)
                    .lineLimit(2)
            }

            // Photos — each card is fixed 150×200 (3:4 portrait)
            if !photos.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        PhotoCardView(photo: photos[i])
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
