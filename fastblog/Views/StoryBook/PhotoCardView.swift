// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI

struct PhotoCardView: View {
    let photo: PhotoContent
    /// Width driven by the caller (half-page for 2 photos, full width for 1).
    let width: CGFloat
    /// Must match `StoryPageLayout` packing (`photoImageHeight` on the slot).
    let imageHeight: CGFloat
    var fontTheme: FontTheme = .classic
    var blogColor: BlogColor = .white

    private var captionColor: Color {
        blogColor == .black ? Color.white.opacity(0.78) : Color.black.opacity(0.55)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryPageLayout.photoCaptionToImageSpacing) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: imageHeight)
                .clipped()
                .clipShape(RoundedRectangle(appChromeBaseRadius: 12))

            if let caption = photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                Text(caption)
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: StoryPageLayout.photoCaptionFontSize)))
                    .foregroundColor(captionColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
