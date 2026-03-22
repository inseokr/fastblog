// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent
    /// Width driven by the caller (half-page for 2 photos, full width for 1).
    let width: CGFloat
    /// Must match `StoryPageLayout` packing (`photoImageHeight` on the slot).
    let imageHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: imageHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                    .frame(width: width, height: imageHeight * 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: width, height: imageHeight)

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
