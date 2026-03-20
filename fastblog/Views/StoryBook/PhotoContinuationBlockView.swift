// fastblog/Views/StoryBook/PhotoContinuationBlockView.swift
import SwiftUI

struct PhotoContinuationBlockView: View {
    let placeName: String
    let photos: [PhotoContent]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let photoWidth: CGFloat = photos.count >= 2
                ? (geo.size.width - gap) / 2
                : geo.size.width * 0.60

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(placeName)
                        .font(.system(size: 14, weight: .bold))
                    Text("More Photos")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                        .italic()
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        PhotoCardView(photo: photos[i], width: photoWidth)
                    }
                    if photos.count == 1 { Spacer() }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 260)
    }
}
