// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent
    /// Width driven by the caller (half-page for 2 photos, ~60% for 1 photo)
    let width: CGFloat

    private var height: CGFloat { width * (4 / 3) }   // 3:4 portrait

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if photo.captionIsLong, let caption = photo.caption {
                    ZStack(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.75)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(width: width, height: height * 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: width, height: height)

            if !photo.captionIsLong, let caption = photo.caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(width: width)
            }
        }
    }
}
