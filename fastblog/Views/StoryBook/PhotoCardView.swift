// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .clipped()

            if photo.captionIsLong, let caption = photo.caption {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let caption = photo.caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
