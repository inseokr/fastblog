// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent

    // Fixed portrait dimensions (3:4)
    static let photoWidth: CGFloat = 150
    static let photoHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Photo with optional long-caption overlay
            ZStack(alignment: .bottom) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.photoWidth, height: Self.photoHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if photo.captionIsLong, let caption = photo.caption {
                    ZStack(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: Self.photoHeight * 0.4)
                        Text(caption)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.top, 6)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: Self.photoWidth, height: Self.photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: Self.photoWidth, height: Self.photoHeight)

            // Short caption sits below the photo, not clipped
            if !photo.captionIsLong, let caption = photo.caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundColor(Color.black)
                    .lineLimit(2)
                    .frame(width: Self.photoWidth, alignment: .leading)
            }
        }
    }
}
